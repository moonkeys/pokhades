extends SceneTree

## Script one-off (headless) : découpe les planches de sprites générées par
## IA (fond magenta), détecte automatiquement chaque sprite par composantes
## connexes (fonctionne pour une rangée simple OU une grille NxM), détoure
## le fond avec nettoyage de la contamination JPEG sur les contours, et
## rogne chaque sprite pile sur son contenu opaque (ancre les pieds au bord
## bas, zéro marge).
##
## Lancer : godot --headless --script scripts/tools/ProcessNatureSprites.gd

const SRC_DIR := "res://assets/nature/"
const OUT_DIR := "res://assets/nature/sprites/"

# fichier source -> nom de base (numérotées dans l'ordre de lecture : haut→bas, gauche→droite)
const JOBS := {
	"arbres.jpeg":           "tree",
	"buissons.jpeg":         "bush",
	"fleurs rouges.jpeg":    "flower_red",
	"fleurs violettes.jpeg": "flower_purple",
	"fleurs blanches.jpeg":  "flower_white",
	"fleurs jaunes.jpeg":    "flower_yellow",
	"tournesols.jpeg":       "sunflower",
	"lampadaires.jpeg":      "lamp",
	"stands.jpeg":           "stall",
}

# Planches en grille régulière NxM connue — traitées cellule par cellule avec
# échantillonnage de fond LOCAL (la couleur magenta dérive légèrement d'une
# cellule à l'autre à cause de la compression JPEG, un seul échantillon
# global ne suffit pas).
const GRID_JOBS := {
	"rochers.jpeg": {"name": "rock", "cols": 3, "rows": 2},
}

const BG_THRESHOLD := 0.30


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for src_name in JOBS:
		var base_name: String = JOBS[src_name]
		_process_sheet(SRC_DIR + src_name, base_name)
	for src_name in GRID_JOBS:
		var info: Dictionary = GRID_JOBS[src_name]
		_process_grid_sheet(SRC_DIR + src_name, info["name"], info["cols"], info["rows"])
	print("ProcessNatureSprites: terminé.")
	quit()


## Découpe une planche en grille régulière connue (cols×rows), avec un
## échantillon de fond propre à chaque cellule.
func _process_grid_sheet(path: String, base_name: String, cols: int, rows: int) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	var img := Image.new()
	if img.load(abs_path) != OK:
		print("Échec chargement: ", abs_path)
		return

	var cw := img.get_width() / cols
	var ch := img.get_height() / rows
	var n := 0
	for row in rows:
		for col in cols:
			var cell := Rect2i(col * cw, row * ch, cw, ch)
			var local_bg := img.get_pixel(cell.position.x + 3, cell.position.y + 3)
			var cropped := img.get_region(cell)
			_chroma_key(cropped, local_bg)
			_clean_outline_fringe(cropped)
			_erode_edge(cropped)
			var trimmed := _auto_trim(cropped)
			if trimmed == null:
				continue
			n += 1
			var out_path := ProjectSettings.globalize_path(OUT_DIR + "%s_%d.png" % [base_name, n])
			trimmed.save_png(out_path)
			print("Sauvé: %s_%d.png (%dx%d)" % [base_name, n, trimmed.get_width(), trimmed.get_height()])


func _process_sheet(path: String, base_name: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	var img := Image.new()
	if img.load(abs_path) != OK:
		print("Échec chargement: ", abs_path)
		return

	var bg := img.get_pixel(2, 2)
	var boxes := _find_sprite_blobs(img, bg)
	print(base_name, ": ", boxes.size(), " sprite(s) détecté(s)")

	for i in boxes.size():
		var box: Rect2i = boxes[i]
		var pad := 3
		var x0 := maxi(0, box.position.x - pad)
		var y0 := maxi(0, box.position.y - pad)
		var x1 := mini(img.get_width(), box.position.x + box.size.x + pad)
		var y1 := mini(img.get_height(), box.position.y + box.size.y + pad)
		var cropped := img.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
		_chroma_key(cropped, bg)
		_clean_outline_fringe(cropped)
		_erode_edge(cropped)
		var trimmed := _auto_trim(cropped)
		if trimmed == null:
			continue
		var out_path := ProjectSettings.globalize_path(OUT_DIR + "%s_%d.png" % [base_name, i + 1])
		trimmed.save_png(out_path)
		print("  Sauvé: %s_%d.png (%dx%d)" % [base_name, i + 1, trimmed.get_width(), trimmed.get_height()])


## Détecte chaque sprite par composantes connexes (flood fill) — fonctionne
## pour une rangée simple ou une grille NxM, peu importe l'agencement.
## Trie le résultat en ordre de lecture (haut→bas, puis gauche→droite).
func _find_sprite_blobs(img: Image, bg: Color) -> Array:
	var w := img.get_width()
	var h := img.get_height()

	var is_content := PackedByteArray()
	is_content.resize(w * h)
	for y in range(h):
		for x in range(w):
			is_content[y * w + x] = 1 if _color_dist(img.get_pixel(x, y), bg) > BG_THRESHOLD else 0

	var visited := PackedByteArray()
	visited.resize(w * h)
	var boxes: Array = []

	for start_y in range(h):
		for start_x in range(w):
			var idx0 := start_y * w + start_x
			if visited[idx0] == 1 or is_content[idx0] == 0:
				continue

			var min_x := start_x
			var max_x := start_x
			var min_y := start_y
			var max_y := start_y
			var pixel_count := 0
			var stack: Array[Vector2i] = [Vector2i(start_x, start_y)]
			visited[idx0] = 1

			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				pixel_count += 1
				min_x = mini(min_x, p.x); max_x = maxi(max_x, p.x)
				min_y = mini(min_y, p.y); max_y = maxi(max_y, p.y)
				var neighbors: Array[Vector2i] = [
					Vector2i(p.x + 1, p.y), Vector2i(p.x - 1, p.y),
					Vector2i(p.x, p.y + 1), Vector2i(p.x, p.y - 1),
				]
				for n: Vector2i in neighbors:
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					var nidx := n.y * w + n.x
					if visited[nidx] == 1 or is_content[nidx] == 0:
						continue
					visited[nidx] = 1
					stack.append(n)

			var box_w := max_x - min_x + 1
			var box_h := max_y - min_y + 1
			var box_area := box_w * box_h
			var fill_ratio := float(pixel_count) / float(maxi(box_area, 1))
			# Élimine le bruit JPEG (petit) ET les traits fins (lignes de
			# grille séparant les cellules — faible ratio de remplissage)
			if box_area > 200 and fill_ratio > 0.20:
				boxes.append(Rect2i(min_x, min_y, box_w, box_h))

	# Fusionne les boîtes qui se chevauchent/se touchent (un sprite peut être
	# scindé en plusieurs composantes si un détail fin le coupe en deux)
	boxes = _merge_overlapping(boxes)

	# Ordre de lecture : rangée (regroupe par bande Y proche), puis colonne
	boxes.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		var row_a := a.position.y / 80
		var row_b := b.position.y / 80
		if row_a != row_b:
			return row_a < row_b
		return a.position.x < b.position.x
	)
	return boxes


func _merge_overlapping(boxes: Array) -> Array:
	var changed := true
	while changed:
		changed = false
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a: Rect2i = boxes[i]
				var b: Rect2i = boxes[j]
				var expanded := Rect2i(a.position - Vector2i(6, 6), a.size + Vector2i(12, 12))
				if expanded.intersects(b):
					boxes[i] = a.merge(b)
					boxes.remove_at(j)
					changed = true
					break
			if changed:
				break
	return boxes


func _chroma_key(img: Image, bg: Color) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var dist := _color_dist(c, bg)
			if dist < 0.22:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))


func _clean_outline_fringe(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate()
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(h):
		for x in range(w):
			var c: Color = src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var is_edge := false
			for d: Vector2i in neighbors:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or src.get_pixel(nx, ny).a < 0.5:
					is_edge = true
					break
			if not is_edge:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			var magenta_bias := (c.r + c.b) * 0.5 - c.g
			if lum < 0.38 and magenta_bias > 0.04:
				img.set_pixel(x, y, Color(0, 0, 0, 1))


func _erode_edge(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate()
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(h):
		for x in range(w):
			if src.get_pixel(x, y).a < 0.5:
				continue
			for d: Vector2i in neighbors:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or src.get_pixel(nx, ny).a < 0.5:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					break


func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _auto_trim(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x == -1:
		return null
	min_x = maxi(0, min_x - 1)
	min_y = maxi(0, min_y - 1)
	max_x = mini(w - 1, max_x + 1)
	max_y = mini(h - 1, max_y + 1)
	return img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
