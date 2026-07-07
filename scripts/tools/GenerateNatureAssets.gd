extends SceneTree

## Script one-off (headless) : génère un petit pack d'assets "nature" propre
## pour la 2.5D — fleurs isolées ancrées pile au sol (zéro marge, donc zéro
## effet de lévitation), sol carrelable (herbe/chemin/eau), et une tuile de
## bordure transparente superposable pour adoucir les transitions. Tout est
## procédural, sauvegardé en PNG réels dans res://assets/nature/.
##
## Lancer : godot --headless --script scripts/tools/GenerateNatureAssets.gd

const OUT_DIR := "res://assets/nature/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_gen_flower("flower_red.png",    Color(0.86, 0.22, 0.18), Color(0.98, 0.80, 0.10))
	_gen_flower("flower_purple.png", Color(0.56, 0.28, 0.78), Color(0.98, 0.80, 0.10))
	_gen_flower("flower_white.png",  Color(0.96, 0.96, 0.92), Color(0.92, 0.62, 0.16))
	_gen_flower("flower_yellow.png", Color(0.95, 0.80, 0.12), Color(0.60, 0.32, 0.10))

	_gen_algae("algae.png")

	_gen_tileable("grass.png", Color(0.30, 0.52, 0.24), Color(0.38, 0.60, 0.28), 2, false)
	_gen_tileable("path.png",  Color(0.60, 0.48, 0.32), Color(0.70, 0.58, 0.42), 2, false)
	_gen_tileable("water.png", Color(0.22, 0.44, 0.60), Color(0.32, 0.56, 0.72), 3, true)

	_gen_edge_overlay("edge_grass.png")

	print("GenerateNatureAssets: pack généré dans ", OUT_DIR)
	quit()


# ── Fleur isolée 16×16, ancrée à la dernière rangée (pas de marge) ────────

func _gen_flower(filename: String, petal: Color, center: Color) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var stem := Color(0.22, 0.48, 0.16)
	var stem_dk := stem.darkened(0.3)
	# Tige — dernière rangée opaque = y=15 (bas de l'image = zéro marge)
	for y in range(9, 16):
		img.set_pixel(7, y, stem)
		img.set_pixel(8, y, stem)
	# Feuilles
	for p in [Vector2i(5, 12), Vector2i(6, 13), Vector2i(10, 12), Vector2i(9, 13)]:
		img.set_pixel(p.x, p.y, stem_dk)

	# Tête de fleur (cercle rempli, contour légèrement assombri)
	var head_c := Vector2(7.5, 6.0)
	var petal_dk := petal.darkened(0.25)
	for y in range(2, 10):
		for x in range(3, 13):
			var d := Vector2(x, y).distance_to(head_c)
			if d < 2.6:
				img.set_pixel(x, y, petal)
			elif d < 3.1:
				img.set_pixel(x, y, petal_dk)
	# Centre
	for y in range(5, 8):
		for x in range(6, 9):
			if Vector2(x, y).distance_to(head_c) < 1.3:
				img.set_pixel(x, y, center)

	img.save_png(OUT_DIR + filename)


## Petite algue/plante aquatique — même principe, pour animer sous l'eau.
func _gen_algae(filename: String) -> void:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c1 := Color(0.16, 0.44, 0.30)
	var c2 := Color(0.22, 0.56, 0.38)
	for y in range(4, 16):
		var sway := int(round(sin(float(y) * 0.5) * 1.5))
		var cx := 6 + sway
		img.set_pixel(clampi(cx - 1, 0, 11), y, c1)
		img.set_pixel(clampi(cx, 0, 11), y, c2)
	img.save_png(OUT_DIR + filename)


# ── Sol carrelable (herbe / chemin / eau) — bruit par blocs, tuile sans
# raccord visible (bruit pur = pas de motif directionnel à raccorder) ──────

func _gen_tileable(filename: String, base: Color, hi: Color, block: int, banded: bool) -> void:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var bx := x / block
			var by := y / block
			var n := _hash01(bx, by)
			if banded:
				n = clampf(n + sin(float(y) * 0.35) * 0.18, 0.0, 1.0)
			var col: Color = base.lerp(hi, n)
			img.set_pixel(x, y, col)
	img.save_png(OUT_DIR + filename)


func _hash01(x: int, y: int) -> float:
	var v := sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453
	return fmod(abs(v), 1.0)


## Bordure transparente superposable — touffes d'herbe le long du bord haut,
## le reste de la tuile est transparent (pour poser sur un chemin/étang et
## adoucir la transition avec l'herbe environnante).
func _gen_edge_overlay(filename: String) -> void:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c1 := Color(0.30, 0.52, 0.24)
	var c2 := Color(0.38, 0.60, 0.28)
	for x in range(size):
		var tuft_h := 3 + int(round(sin(float(x) * 0.8) * 2.0)) + (x % 3)
		for y in range(tuft_h):
			var col := c1 if (x + y) % 2 == 0 else c2
			img.set_pixel(x, y, col)
	img.save_png(OUT_DIR + filename)
