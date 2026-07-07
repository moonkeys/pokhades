@tool
class_name HubMap
extends Node3D

## Génération procédurale du Hub en 3D — version compacte et vallonnée.
## Même principe de placement par case que l'ancienne version TileMapLayer,
## sur une map resserrée (56×34, l'ancienne 80×45 était trop vide). Rendu
## façon Octopath Traveler : sol en RELIEF doux (collines procédurales
## déterministes, aplaties sous les chemins/structures/étang), végétation
## (arbres, buissons, rochers, fleurs, champignons, souches) et eau en VRAIS
## volumes 3D — mêmes techniques que MapRender3D (maps de combat), via
## l'utilitaire partagé KitProps.gd (pack Kenney Nature Kit, CC0). Décors de
## vie : feux de camp éclairés (lumière vacillante), barrières autour des
## tournesols, statues. Les structures bâties (lampadaires, stand, tour,
## ruines) restent en sprite du tileset Pokémon Essentials — pas
## d'équivalent architectural dans le pack nature. 1 unité monde = 1
## ancienne tuile (16px).

const W := 56
const H := 34
const TILESET_PATH := "res://assets/tilesets/tileset pokemon.png"
const NATURE_DIR    := "res://assets/nature/"
const SPRITES_DIR    := "res://assets/nature/sprites/"

# ── Tileset externe Pokémon Essentials (tuiles 32px, pas 16px) — coordonnées
# à repérer et remplir dans l'Inspecteur (voir groupe "Outside.png" plus bas).
const OUTSIDE_TILESET_PATH := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Tilesets/Outside.png"
const OUTSIDE_TILE_PX := 32
const OUTSIDE_UNSET := Vector2i(-1, -1)   # sentinelle "pas encore rempli"

# ── Coordonnées d'atlas (héritées de l'ancienne version TileMapLayer) ────
# Encore utilisées pour les props pas encore remplacés (tour, ruines).
const ATLAS_ARCH        := Vector2i(71, 48)   # bloc 3×4
const ATLAS_TOWER       := Vector2i(27, 44)   # bloc 3×5
const ATLAS_RUINS_FLOOR := Vector2i(55, 44)   # bloc 3×3 (dalles + bordures)


# ── Végétation — vrais volumes 3D du pack Kenney (cf. KitProps.gd) ───────
const TREE_TARGET_HEIGHT     := 3.4   # arbre normal
const BIG_TREE_TARGET_HEIGHT := 5.2   # arbre "hero"
const BUSH_TARGET_HEIGHT     := 1.3
const ROCK_TARGET_SCALE      := 1.3
const FLOWER_SCALE           := 2.1
## Un groupe par couleur — un champ de fleurs n'utilise qu'un seul groupe
## (même couleur, formes variées), pas un mélange de couleurs. Le pack
## Kenney n'a pas de fleur blanche dédiée : on réutilise la forme "jaune"
## avec son matériau pétale reteinté (même astuce que MapRender3D).
const FLOWER_POOLS: Array = [
	{"pool": KitProps.FLOWERS_RED,    "tints": {}},
	{"pool": KitProps.FLOWERS_PURPLE, "tints": {}},
	{"pool": KitProps.FLOWERS_YELLOW, "tints": {"colorYellow": Color(0.94, 0.94, 0.92)}},   # "blanc"
	{"pool": KitProps.FLOWERS_YELLOW, "tints": {}},
]

# ── Relief (collines douces) ──────────────────────────────────────────────
# Seed FIXE : le champ de hauteur doit être identique entre l'éditeur (où la
# map est générée/figée) et le runtime (où joueur/PNJ suivent le terrain via
# get_height_at_world sans que la grille soit sauvegardée dans la scène).
const HEIGHT_SEED          := 987123
const HEIGHT_AMPLITUDE     := 0.55
const HEIGHT_NOISE_FREQ    := 0.075
const HEIGHT_SMOOTH_PASSES := 2

## Zones toujours PLATES (relief = 0, marge d'une case incluse) : chemins,
## plaza, étang, structures, enclos des tournesols, feux de camp. Sert aussi
## de zone d'exclusion pour les fleurs/décors épars.
const _FLAT_RECTS: Array[Rect2i] = [
	Rect2i(24, 2, 8, 30),    # chemin vertical
	Rect2i(4, 14, 48, 6),    # bande de chemin horizontale
	Rect2i(20, 12, 16, 12),  # plaza centrale
	Rect2i(3, 21, 13, 11),   # étang + berges
	Rect2i(4, 10, 7, 5),     # stand de marché
	Rect2i(2, 3, 6, 6),      # tour
	Rect2i(40, 3, 11, 8),    # ruines + statues
	Rect2i(28, 23, 12, 7),   # tournesols + barrières
	Rect2i(15, 21, 5, 4),    # feu de camp ouest
	Rect2i(37, 22, 5, 4),    # feu de camp est
	Rect2i(47, 25, 5, 5),    # grand arbre "hero"
]

# ── Étang (blob organique, plus un rectangle) ────────────────────────────
const POND_CENTER := Vector2(9.5, 26.5)
const POND_RX := 4.6
const POND_RZ := 3.4
const WATER_SURFACE_Y := 0.06

var _water_cells: Dictionary = {}   # Vector2i -> true
var _height_grid: Array = []        # Array[PackedFloat32Array]

@export_group("Outside.png (Pokémon Essentials) — emplacements vides à remplir")
## Coordonnée de la tuile en haut à gauche de chaque objet dans Outside.png
## (en tuiles 32px, pas en pixels) + sa taille en tuiles (largeur, hauteur).
## NB : les rangées de test ne sont plus posées sur la map (elles
## encombraient le hub compact) — cf. _place_outside_tileset_test_props,
## conservée mais plus appelée par _generate().
@export var pine_tree_cell: Vector2i = OUTSIDE_UNSET
@export var pine_tree_size: Vector2i = Vector2i(2, 2)
@export var round_tree_cell: Vector2i = OUTSIDE_UNSET
@export var round_tree_size: Vector2i = Vector2i(3, 3)
@export var bush_cell: Vector2i = OUTSIDE_UNSET
@export var bush_size: Vector2i = Vector2i(2, 2)
@export var rock_cell: Vector2i = OUTSIDE_UNSET
@export var rock_size: Vector2i = Vector2i(2, 2)
@export var boulder_cell: Vector2i = OUTSIDE_UNSET
@export var boulder_size: Vector2i = Vector2i(3, 3)
@export var hill_cell: Vector2i = OUTSIDE_UNSET
@export var hill_size: Vector2i = Vector2i(4, 3)
@export var stairs_cell: Vector2i = OUTSIDE_UNSET
@export var stairs_size: Vector2i = Vector2i(2, 2)
@export var cave_entrance_cell: Vector2i = OUTSIDE_UNSET
@export var cave_entrance_size: Vector2i = Vector2i(3, 3)

@export_subgroup("Chemin de terre")
@export var dirt_center: Vector2i = OUTSIDE_UNSET
@export var dirt_edge_n: Vector2i = OUTSIDE_UNSET
@export var dirt_edge_s: Vector2i = OUTSIDE_UNSET
@export var dirt_edge_e: Vector2i = OUTSIDE_UNSET
@export var dirt_edge_w: Vector2i = OUTSIDE_UNSET
@export var dirt_corner_ne: Vector2i = OUTSIDE_UNSET
@export var dirt_corner_nw: Vector2i = OUTSIDE_UNSET
@export var dirt_corner_se: Vector2i = OUTSIDE_UNSET
@export var dirt_corner_sw: Vector2i = OUTSIDE_UNSET

@export_subgroup("Chemin de pierre")
@export var stone_center: Vector2i = OUTSIDE_UNSET
@export var stone_edge_n: Vector2i = OUTSIDE_UNSET
@export var stone_edge_s: Vector2i = OUTSIDE_UNSET
@export var stone_edge_e: Vector2i = OUTSIDE_UNSET
@export var stone_edge_w: Vector2i = OUTSIDE_UNSET
@export var stone_corner_ne: Vector2i = OUTSIDE_UNSET
@export var stone_corner_nw: Vector2i = OUTSIDE_UNSET
@export var stone_corner_se: Vector2i = OUTSIDE_UNSET
@export var stone_corner_sw: Vector2i = OUTSIDE_UNSET

@export_subgroup("Eau")
@export var water_center: Vector2i = OUTSIDE_UNSET
@export var water_edge_n: Vector2i = OUTSIDE_UNSET
@export var water_edge_s: Vector2i = OUTSIDE_UNSET
@export var water_edge_e: Vector2i = OUTSIDE_UNSET
@export var water_edge_w: Vector2i = OUTSIDE_UNSET
@export var water_corner_ne: Vector2i = OUTSIDE_UNSET
@export var water_corner_nw: Vector2i = OUTSIDE_UNSET
@export var water_corner_se: Vector2i = OUTSIDE_UNSET
@export var water_corner_sw: Vector2i = OUTSIDE_UNSET

@export_subgroup("Sable")
@export var sand_center: Vector2i = OUTSIDE_UNSET
@export var sand_edge_n: Vector2i = OUTSIDE_UNSET
@export var sand_edge_s: Vector2i = OUTSIDE_UNSET
@export var sand_edge_e: Vector2i = OUTSIDE_UNSET
@export var sand_edge_w: Vector2i = OUTSIDE_UNSET
@export var sand_corner_ne: Vector2i = OUTSIDE_UNSET
@export var sand_corner_nw: Vector2i = OUTSIDE_UNSET
@export var sand_corner_se: Vector2i = OUTSIDE_UNSET
@export var sand_corner_sw: Vector2i = OUTSIDE_UNSET

@export_subgroup("Falaise")
@export var cliff_center: Vector2i = OUTSIDE_UNSET
@export var cliff_edge_n: Vector2i = OUTSIDE_UNSET
@export var cliff_edge_s: Vector2i = OUTSIDE_UNSET
@export var cliff_edge_e: Vector2i = OUTSIDE_UNSET
@export var cliff_edge_w: Vector2i = OUTSIDE_UNSET
@export var cliff_corner_ne: Vector2i = OUTSIDE_UNSET
@export var cliff_corner_nw: Vector2i = OUTSIDE_UNSET
@export var cliff_corner_se: Vector2i = OUTSIDE_UNSET
@export var cliff_corner_sw: Vector2i = OUTSIDE_UNSET

@export_subgroup("Eau de mer")
@export var sea_center: Vector2i = OUTSIDE_UNSET
@export var sea_edge_n: Vector2i = OUTSIDE_UNSET
@export var sea_edge_s: Vector2i = OUTSIDE_UNSET
@export var sea_edge_e: Vector2i = OUTSIDE_UNSET
@export var sea_edge_w: Vector2i = OUTSIDE_UNSET
@export var sea_corner_ne: Vector2i = OUTSIDE_UNSET
@export var sea_corner_nw: Vector2i = OUTSIDE_UNSET
@export var sea_corner_se: Vector2i = OUTSIDE_UNSET
@export var sea_corner_sw: Vector2i = OUTSIDE_UNSET

@export_group("Éditeur")
## Attention : efface tout le contenu actuel de HubMapBg (y compris tes
## modifications manuelles) et repart de zéro depuis la génération
## procédurale.
@export_tool_button("⟳ Tout regénérer (efface les modifs manuelles)") var _regen: Callable = _regenerate_in_editor


func _regenerate_in_editor() -> void:
	_clear()
	_generate()
	# `add_child()` seul ne suffit pas à faire persister les nœuds générés :
	# sans `owner` pointant vers la racine de la scène éditée, l'éditeur ne
	# les inclut PAS à la sauvegarde (ils restent visibles dans le viewport
	# tant que la scène n'est pas rechargée, puis disparaissent) — piège
	# classique des scripts @tool qui génèrent du contenu par code.
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else self
	_assign_owner_recursive(self, root)


func _assign_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.owner != root:
			child.owner = root
		_assign_owner_recursive(child, root)


## Le hub a été généré une fois puis figé (bouton "⟳ Tout regénérer" pour
## reconstruire) — _ready() ne régénère pas, mais recalcule le champ de
## hauteur (déterministe, cf. HEIGHT_SEED) : joueur et PNJ en ont besoin au
## runtime pour suivre le relief, et la grille n'est pas sauvegardée.
func _ready() -> void:
	_compute_water_cells()
	_compute_height_field()
	if not Engine.is_editor_hint():
		# Génération AU RUNTIME si la scène sauvegardée a un HubMapBg vide
		# (cf. note : le contenu est généré à chaud, pas baké — évite les
		# corruptions de sauvegarde et garde le hub toujours cohérent).
		if get_child_count() == 0:
			_generate()
		_build_border_walls()


func _clear() -> void:
	# free() IMMÉDIAT (pas queue_free différé) : sinon une régénération ajoute
	# les nouveaux nœuds AVANT que les anciens soient libérés, et
	# _assign_owner_recursive leur donne à TOUS un owner → la scène sauvegardée
	# se retrouve DUPLIQUÉE (2× la géométrie et les collisions superposées, ce
	# qui fait exploser le broadphase physique au chargement = jeu figé).
	for c in get_children():
		remove_child(c)
		c.free()
	_water_cells.clear()


# ── Génération principale ─────────────────────────────────────────────────

func _generate() -> void:
	_compute_water_cells()     # avant tout : le masque plat/les scatters en dépendent
	_compute_height_field()
	_fill_ground()
	_draw_water_pond()
	_draw_paths()
	_scatter_flowers()
	_scatter_bushes()
	_scatter_rocks()
	_scatter_life_decor()
	_draw_border_trees()
	_draw_inner_trees()
	_place_lampadaires()
	# _place_market_stall() retiré — sprite (stall_*.png) supprimé, pas de
	# substitut GLB dans le kit nature ; laissait un mur invisible gênant.
	_place_big_tree()
	_place_ruins()
	_place_tower()
	_place_campfires()
	_place_sunflower_fences()
	_place_plaza_statue()
	# Les tournesols animés sont gérés par SunflowerField.gd (HubWorld._build_sunflowers)
	# Rangées de test Outside.png : plus posées (encombraient le hub compact).


func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)


# ── Relief — collines douces déterministes ───────────────────────────────

func _compute_height_field() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed       = HEIGHT_SEED
	noise.frequency  = HEIGHT_NOISE_FREQ

	var field: Array = []
	field.resize(H)
	for r in H:
		var row := PackedFloat32Array()
		row.resize(W)
		for c in W:
			row[c] = 0.0 if _is_flat_cell(c, r) else \
				noise.get_noise_2d(float(c), float(r)) * HEIGHT_AMPLITUDE
		field[r] = row

	# Lissage (pentes douces) puis re-verrouillage à plat des zones réservées
	for i in HEIGHT_SMOOTH_PASSES:
		field = _smooth_height_field(field)
	for r in H:
		for c in W:
			if _is_flat_cell(c, r):
				field[r][c] = 0.0
	_height_grid = field


func _is_flat_cell(c: int, r: int) -> bool:
	# Eau + berge d'une case : raccord propre avec les franges du contour
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _water_cells.has(Vector2i(c + dx, r + dy)):
				return true
	for rect: Rect2i in _FLAT_RECTS:
		if rect.has_point(Vector2i(c, r)):
			return true
	return false


func _smooth_height_field(src: Array) -> Array:
	var out: Array = []
	out.resize(H)
	for r in H:
		var row := PackedFloat32Array()
		row.resize(W)
		for c in W:
			var sum := 0.0
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nr := r + dy
					var nc := c + dx
					if nr < 0 or nr >= H or nc < 0 or nc >= W: continue
					sum += (src[nr] as PackedFloat32Array)[nc]
					count += 1
			row[c] = sum / float(count)
		out[r] = row
	return out


func get_height_at_cell(cell: Vector2i) -> float:
	if _height_grid.is_empty(): return 0.0
	if cell.y < 0 or cell.y >= _height_grid.size(): return 0.0
	var row: PackedFloat32Array = _height_grid[cell.y]
	if cell.x < 0 or cell.x >= row.size(): return 0.0
	return row[cell.x]


## Interpolation bilinéaire — suivi fluide du relief par joueur/PNJ/caméra.
func get_height_at_world(pos: Vector3) -> float:
	if _height_grid.is_empty(): return 0.0
	var fx := clampf(pos.x - 0.5, 0.0, float(W - 1))
	var fy := clampf(pos.z - 0.5, 0.0, float(H - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, W - 1)
	var y1 := mini(y0 + 1, H - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var row0: PackedFloat32Array = _height_grid[y0]
	var row1: PackedFloat32Array = _height_grid[y1]
	return lerpf(lerpf(row0[x0], row0[x1], tx), lerpf(row1[x0], row1[x1], tx), ty)


# ── Helpers plans texturés ───────────────────────────────────────────────

## Plan horizontal carrelé avec une tuile du tileset (props ponctuels : dalles).
func _make_tiled_plane(atlas_cell: Vector2i, w: float, h: float, tileset_path: String = TILESET_PATH, tile_px: int = Billboard3D.TILE_PX) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture   = Billboard3D.crop_tile(tileset_path, atlas_cell, 1, 1, tile_px)
	mat.uv1_scale        = Vector3(w, h, 1.0)
	mat.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness        = 0.9
	mesh_inst.material_override = mat
	return mesh_inst


## Plan horizontal carrelé avec une texture du pack nature (chemins, lit de
## l'étang) — tuiles conçues pour carreler sans raccord visible.
func _make_nature_plane(filename: String, w: float, h: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	mesh_inst.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture   = load(NATURE_DIR + filename)
	mat.uv1_scale        = Vector3(w, h, 1.0)
	mat.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness        = 0.9
	mesh_inst.material_override = mat
	return mesh_inst


# ── Sol — maillage en relief ─────────────────────────────────────────────

## Grille de sommets (W+1)×(H+1) déplacés selon le champ de hauteur — même
## technique que MapRender3D._build_heightfield_mesh. UV en coordonnées
## monde : la texture d'herbe carrelle 1 tuile par unité.
func _fill_ground() -> void:
	var corner_h: Array = []
	corner_h.resize(H + 1)
	for cy in range(H + 1):
		var row := PackedFloat32Array()
		row.resize(W + 1)
		for cx in range(W + 1):
			row[cx] = _corner_height(cx, cy)
		corner_h[cy] = row

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cy in H:
		for cx in W:
			var p00 := Vector3(cx,     corner_h[cy][cx],         cy)
			var p10 := Vector3(cx + 1, corner_h[cy][cx + 1],     cy)
			var p01 := Vector3(cx,     corner_h[cy + 1][cx],     cy + 1)
			var p11 := Vector3(cx + 1, corner_h[cy + 1][cx + 1], cy + 1)
			st.set_uv(Vector2(cx, cy));         st.add_vertex(p00)
			st.set_uv(Vector2(cx + 1, cy));     st.add_vertex(p10)
			st.set_uv(Vector2(cx + 1, cy + 1)); st.add_vertex(p11)
			st.set_uv(Vector2(cx, cy));         st.add_vertex(p00)
			st.set_uv(Vector2(cx + 1, cy + 1)); st.add_vertex(p11)
			st.set_uv(Vector2(cx, cy + 1));     st.add_vertex(p01)
	st.generate_normals()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Ground"
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture  = load(NATURE_DIR + "grass.png")
	mat.texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness       = 0.9
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_inst)


func _corner_height(cx: int, cy: int) -> float:
	var sum := 0.0
	var count := 0
	for cell: Vector2i in [Vector2i(cx - 1, cy - 1), Vector2i(cx, cy - 1), Vector2i(cx - 1, cy), Vector2i(cx, cy)]:
		if cell.x < 0 or cell.x >= W or cell.y < 0 or cell.y >= H:
			continue
		sum += get_height_at_cell(cell)
		count += 1
	return sum / float(count) if count > 0 else 0.0


func _in_no_flower_zone(cell: Vector2i) -> bool:
	for r: Rect2i in _FLAT_RECTS:
		if r.has_point(cell):
			return true
	return false


# ── Fleurs / buissons / rochers épars (suivent le relief) ────────────────

## Petits champs de fleurs groupées — vrais meshes du pack Kenney (ondulation
## de vent intégrée), regroupés en un seul MultiMeshInstance3D par variante.
func _scatter_flowers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var by_key: Dictionary = {}   # "pool_idx|fichier" -> {"tints":{}, "transforms":[], "phases":[]}

	for i in 46:
		var cell := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if _in_no_flower_zone(cell) or _water_cells.has(cell):
			continue
		var pool_idx := rng.randi() % FLOWER_POOLS.size()
		var pool_def: Dictionary = FLOWER_POOLS[pool_idx]
		var pool: Array = pool_def["pool"]
		var count := rng.randi_range(4, 7)
		for k in count:
			var file: String = pool[rng.randi() % pool.size()]
			var key := "%d|%s" % [pool_idx, file]
			if not by_key.has(key):
				by_key[key] = {"tints": pool_def["tints"], "transforms": [], "phases": []}
			var origin := _cell_to_world(cell) + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			origin.y = get_height_at_world(origin)
			var s := FLOWER_SCALE * rng.randf_range(0.85, 1.15)
			var basis := Basis.from_euler(Vector3(0, rng.randf_range(0.0, TAU), 0)).scaled(Vector3.ONE * s)
			(by_key[key]["transforms"] as Array).append(Transform3D(basis, origin))
			(by_key[key]["phases"] as Array).append(rng.randf_range(0.0, TAU))

	for key: String in by_key:
		var file: String = key.split("|")[1]
		var data: Dictionary = by_key[key]
		add_child(KitProps.build_multimesh(file, data["transforms"], data["phases"], data["tints"]))


func _scatter_bushes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	for i in 20:
		var cell := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if _in_no_flower_zone(cell) or _water_cells.has(cell):
			continue
		var file: String = KitProps.BUSHES[rng.randi() % KitProps.BUSHES.size()]
		var pos := _cell_to_world(cell) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		pos.y = get_height_at_world(pos)
		var native_h: float = KitProps.BUSH_NATIVE_HEIGHT.get(file, 0.28)

		var bush := KitProps.instance(file)
		bush.scale = Vector3.ONE * (BUSH_TARGET_HEIGHT * rng.randf_range(0.85, 1.2) / native_h)
		bush.rotation.y = rng.randf_range(0.0, TAU)
		bush.position = pos
		add_child(bush)

		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = BUSH_TARGET_HEIGHT * 0.35
		shape.height = 0.8
		cs.shape = shape
		cs.position = pos + Vector3(0, 0.4, 0)
		body.add_child(cs)
		add_child(body)


func _scatter_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9191
	for i in 12:
		var cell := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if _in_no_flower_zone(cell) or _water_cells.has(cell):
			continue
		var file: String = KitProps.ROCKS_SMALL[rng.randi() % KitProps.ROCKS_SMALL.size()]
		var pos := _cell_to_world(cell) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		pos.y = get_height_at_world(pos)

		var rock := KitProps.instance(file)
		rock.scale = Vector3.ONE * ROCK_TARGET_SCALE * rng.randf_range(0.8, 1.25)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		rock.position = pos
		add_child(rock)

		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = ROCK_TARGET_SCALE * 0.3
		shape.height = 0.7
		cs.shape = shape
		cs.position = pos + Vector3(0, 0.35, 0)
		body.add_child(cs)
		add_child(body)


## Décors de vie épars : champignons (traversables), souches et rondins
## (petites collisions) — dispersés hors chemins/structures, sur le relief.
func _scatter_life_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	_scatter_kit_pool(rng, KitProps.MUSHROOMS, 9, 1.7, 2.3, false)
	_scatter_kit_pool(rng, KitProps.STUMPS,    5, 1.8, 2.2, true)
	_scatter_kit_pool(rng, KitProps.LOGS,      4, 1.8, 2.2, true)


func _scatter_kit_pool(rng: RandomNumberGenerator, pool: Array, count: int,
		s_min: float, s_max: float, collide: bool) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var cell := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if _in_no_flower_zone(cell) or _water_cells.has(cell):
			continue
		var file: String = pool[rng.randi() % pool.size()]
		var pos := _cell_to_world(cell) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		pos.y = get_height_at_world(pos)

		var prop := KitProps.instance(file)
		prop.scale = Vector3.ONE * rng.randf_range(s_min, s_max)
		prop.rotation.y = rng.randf_range(0.0, TAU)
		prop.position = pos
		add_child(prop)
		placed += 1

		if collide:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.35
			shape.height = 0.6
			cs.shape = shape
			cs.position = pos + Vector3(0, 0.3, 0)
			body.add_child(cs)
			add_child(body)


# ── Étang — blob organique, surface animée, franges et roseaux ───────────
# Surface : WaterSurface.gd (partagé avec les maps de combat) — maillage
# subdivisé, houle visible, écume animée qui clapote sur les rives.

const _POND_EDGE_DIRS := [
	{"delta": Vector2i(0, -1), "off": Vector3(0.5, 0.0, 0.0), "rot": 0.0},
	{"delta": Vector2i(0, 1),  "off": Vector3(0.5, 0.0, 1.0), "rot": 180.0},
	{"delta": Vector2i(-1, 0), "off": Vector3(0.0, 0.0, 0.5), "rot": 90.0},
	{"delta": Vector2i(1, 0),  "off": Vector3(1.0, 0.0, 0.5), "rot": -90.0},
]


func _compute_water_cells() -> void:
	_water_cells.clear()
	for z in range(int(POND_CENTER.y - POND_RZ) - 1, int(POND_CENTER.y + POND_RZ) + 2):
		for x in range(int(POND_CENTER.x - POND_RX) - 1, int(POND_CENTER.x + POND_RX) + 2):
			var dx := (float(x) + 0.5 - POND_CENTER.x) / POND_RX
			var dz := (float(z) + 0.5 - POND_CENTER.y) / POND_RZ
			if dx * dx + dz * dz <= 1.0:
				_water_cells[Vector2i(x, z)] = true


## Lit texturé + surface animée + franges d'herbe sur le contour + roseaux
## et pierres de berge — étang organique, plus le rectangle d'origine.
func _draw_water_pond() -> void:
	var bed_st := SurfaceTool.new()
	bed_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in _water_cells:
		_add_flat_cell_quad(bed_st, cell)
	bed_st.generate_normals()

	var bed := MeshInstance3D.new()
	bed.name = "PondBed"
	bed.mesh = bed_st.commit()
	bed.position.y = 0.02
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_texture = load(NATURE_DIR + "water.png")
	bed_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bed_mat.roughness      = 0.9
	bed.material_override = bed_mat
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)

	var surf := WaterSurface.build(_water_cells.keys(),
		Color(0.32, 0.62, 0.66, 0.70), Color(0.13, 0.32, 0.42, 0.86))
	surf.name = "PondSurface"
	surf.position.y = WATER_SURFACE_Y
	add_child(surf)

	_draw_pond_edges_and_banks()


func _add_flat_cell_quad(st: SurfaceTool, cell: Vector2i) -> void:
	var x0 := float(cell.x)
	var z0 := float(cell.y)
	var p00 := Vector3(x0, 0, z0)
	var p10 := Vector3(x0 + 1, 0, z0)
	var p01 := Vector3(x0, 0, z0 + 1)
	var p11 := Vector3(x0 + 1, 0, z0 + 1)
	st.set_uv(Vector2(x0, z0));         st.add_vertex(p00)
	st.set_uv(Vector2(x0 + 1, z0));     st.add_vertex(p10)
	st.set_uv(Vector2(x0 + 1, z0 + 1)); st.add_vertex(p11)
	st.set_uv(Vector2(x0, z0));         st.add_vertex(p00)
	st.set_uv(Vector2(x0 + 1, z0 + 1)); st.add_vertex(p11)
	st.set_uv(Vector2(x0, z0 + 1));     st.add_vertex(p01)


func _draw_pond_edges_and_banks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_texture = load(NATURE_DIR + "edge_grass.png")
	edge_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	edge_mat.cull_mode       = BaseMaterial3D.CULL_DISABLED
	edge_mat.roughness       = 1.0

	for cell: Vector2i in _water_cells:
		for d: Dictionary in _POND_EDGE_DIRS:
			var neighbor: Vector2i = cell + d["delta"]
			if _water_cells.has(neighbor):
				continue
			# Frange d'herbe sur le bord terre→eau
			var mi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(1, 1)
			mi.mesh = plane
			mi.position = Vector3(cell.x, WATER_SURFACE_Y + 0.01, cell.y) + (d["off"] as Vector3)
			mi.rotation_degrees = Vector3(-90, d["rot"], 0)
			mi.material_override = edge_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

			# Roseaux/pierres épars côté terre — berge vivante
			var roll := rng.randf()
			var bank := _cell_to_world(neighbor) + Vector3(0.5 + rng.randf_range(-0.2, 0.2), 0, 0.5 + rng.randf_range(-0.2, 0.2))
			if roll < 0.30:
				var reed := KitProps.instance(KitProps.REEDS[rng.randi() % KitProps.REEDS.size()])
				reed.scale = Vector3.ONE * rng.randf_range(1.6, 2.4)
				reed.rotation.y = rng.randf_range(0.0, TAU)
				reed.position = bank
				add_child(reed)
			elif roll < 0.42:
				var rock := KitProps.instance(KitProps.ROCKS_SMALL[rng.randi() % KitProps.ROCKS_SMALL.size()])
				rock.scale = Vector3.ONE * rng.randf_range(0.9, 1.4)
				rock.rotation.y = rng.randf_range(0.0, TAU)
				rock.position = bank
				add_child(rock)


# ── Chemins (zones plates, léger décalage au-dessus du sol) ──────────────

func _draw_paths() -> void:
	_fill_path(26, 30, 3, 31)    # vertical central
	_fill_path(5, 26, 15, 19)    # horizontal gauche
	_fill_path(30, 51, 15, 19)   # horizontal droite
	_fill_path(21, 35, 13, 23)   # plaza centrale


func _fill_path(x0: int, x1: int, y0: int, y1: int) -> void:
	var mesh_inst := _make_nature_plane("path.png", x1 - x0, y1 - y0)
	mesh_inst.position = Vector3(float(x0 + x1) * 0.5, 0.045, float(y0 + y1) * 0.5)
	add_child(mesh_inst)


# ── Forêts organiques (bordure + bosquets intérieurs) ─────────────────────

var _tree_rng := RandomNumberGenerator.new()

func _draw_border_trees() -> void:
	var m := 1.6
	_scatter_forest_strip(Vector2(m, m), Vector2(W - m, m))          # haut
	_scatter_forest_strip(Vector2(m, H - m), Vector2(W - m, H - m))  # bas
	_scatter_forest_strip(Vector2(m, m), Vector2(m, H - m))          # gauche
	_scatter_forest_strip(Vector2(W - m, m), Vector2(W - m, H - m))  # droite


func _scatter_forest_strip(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var dir := (to - from) / length
	var normal := Vector2(-dir.y, dir.x)
	var step := 1.5
	var count := int(length / step)
	for i in count:
		var t := float(i) * step + _tree_rng.randf_range(-0.4, 0.4)
		var base := from + dir * t
		var p := base + normal * _tree_rng.randf_range(-0.9, 0.9)
		_try_spawn_forest_tree(p)


func _draw_inner_trees() -> void:
	_scatter_forest_patch(8, 5, 18, 10)
	_scatter_forest_patch(36, 5, 40, 11)
	_scatter_forest_patch(16, 28, 24, 32)
	_scatter_forest_patch(41, 28, 50, 32)


func _scatter_forest_patch(x0: int, y0: int, x1: int, y1: int) -> void:
	var area := float((x1 - x0) * (y1 - y0))
	var count := int(area / 4.0)
	for i in count:
		var p := Vector2(_tree_rng.randf_range(x0, x1), _tree_rng.randf_range(y0, y1))
		_try_spawn_forest_tree(p)


func _try_spawn_forest_tree(p: Vector2) -> void:
	var cell := Vector2i(int(round(p.x)), int(round(p.y)))
	if cell.x < 1 or cell.y < 1 or cell.x >= W - 1 or cell.y >= H - 1 or _water_cells.has(cell):
		return
	# Mélange feuillus/sapins pour la variété — le Hub n'est pas rattaché à
	# un biome précis contrairement aux maps de combat.
	var pool: Array = KitProps.TREES_ROUND if _tree_rng.randf() < 0.7 else KitProps.TREES_PINE
	var file: String = pool[_tree_rng.randi() % pool.size()]
	var scale_var := _tree_rng.randf_range(0.8, 1.25)
	var pos := Vector3(p.x, 0, p.y)
	pos.y = get_height_at_world(pos)
	_spawn_tree(pos, file, TREE_TARGET_HEIGHT * scale_var)


## Vrai volume 3D du pack Kenney, normalisé sur `target_h` (chaque variante
## a sa propre hauteur native, cf. KitProps.TREE_NATIVE_HEIGHT).
func _spawn_tree(pos: Vector3, file: String, target_h: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var native_h: float = KitProps.TREE_NATIVE_HEIGHT.get(file, 1.7)
	var tree := KitProps.instance(file)
	tree.scale = Vector3.ONE * (target_h / native_h)
	tree.rotation.y = _tree_rng.randf_range(0.0, TAU)
	root.add_child(tree)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = target_h * 0.10
	shape.height = target_h * 0.5
	cs.shape = shape
	cs.position = Vector3(0, target_h * 0.25, 0)
	body.add_child(cs)
	root.add_child(body)


# ── Lampadaires (sprite réduit + vraie lumière chaude, contenue) ─────────

func _place_lampadaires() -> void:
	for cell in [Vector2i(22, 14), Vector2i(34, 14), Vector2i(22, 22), Vector2i(34, 22),
			Vector2i(25, 7), Vector2i(31, 7)]:
		_place_lamp(_cell_to_world(cell))


func _place_lamp(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	# Le sprite du lampadaire (assets/nature/sprites/lamp_*) a été retiré —
	# le halo de lumière + la collision restent (l'essentiel de l'ambiance).
	var lamp_h := 2.1

	var light := OmniLight3D.new()
	light.position = Vector3(0, lamp_h * 0.9, 0)
	light.light_color  = Color(1.0, 0.80, 0.50)
	light.light_energy = 0.55
	light.omni_range   = 3.2
	root.add_child(light)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.10
	shape.height = lamp_h
	cs.shape = shape
	cs.position = Vector3(0, lamp_h * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)


# ── Feux de camp (mesh Kenney + flamme émissive + lumière vacillante) ────

func _place_campfires() -> void:
	_place_campfire(Vector3(17.5, 0, 22.5), 0)
	_place_campfire(Vector3(39.5, 0, 23.5), 1)


func _place_campfire(pos: Vector3, variant: int) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var fire := KitProps.instance(KitProps.CAMPFIRES[variant % KitProps.CAMPFIRES.size()])
	fire.scale = Vector3.ONE * 2.2
	root.add_child(fire)

	# Flamme stylisée : petit cône émissif — le glow de l'Environment fait le reste
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius    = 0.0
	cone.bottom_radius = 0.13
	cone.height        = 0.30
	flame.mesh = cone
	flame.position = Vector3(0, 0.28, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color    = Color(1.0, 0.55, 0.15)
	fmat.emission_enabled = true
	fmat.emission         = Color(1.0, 0.45, 0.10)
	fmat.emission_energy_multiplier = 1.6
	flame.material_override = fmat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)

	# Lumière chaude vacillante (script CampfireFlicker, actif en jeu seulement)
	var light: OmniLight3D = CampfireFlicker.new()
	light.position = Vector3(0, 0.7, 0)
	light.light_color  = Color(1.0, 0.62, 0.28)
	light.light_energy = 1.0
	light.omni_range   = 4.5
	root.add_child(light)

	# Sièges : deux souches face au feu
	for ang in [0.9, 2.4]:
		var seat := KitProps.instance(KitProps.STUMPS[0])
		seat.scale = Vector3.ONE * 2.0
		seat.position = Vector3(cos(ang) * 1.3, 0, sin(ang) * 1.3)
		seat.rotation.y = -ang
		root.add_child(seat)

	# On ne marche pas dans le feu
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 0.6
	cs.shape = shape
	cs.position = Vector3(0, 0.3, 0)
	body.add_child(cs)
	root.add_child(body)


# ── Enclos des tournesols (barrières basses, portillon au nord) ──────────
# Les champs eux-mêmes sont posés par HubWorld._build_sunflowers — garder
# les positions synchronisées ((31.5, 26.5) et (35.5, 26.5)).

func _place_sunflower_fences() -> void:
	for x in range(29, 38):
		if x >= 33 and x < 35:   # ouverture d'accès au nord
			continue
		_place_fence(Vector3(x + 0.5, 0, 24.0), 0.0)
	for x in range(29, 38):
		_place_fence(Vector3(x + 0.5, 0, 29.0), 0.0)
	for z in range(24, 29):
		_place_fence(Vector3(29.0, 0, z + 0.5), 90.0)
		_place_fence(Vector3(38.0, 0, z + 0.5), 90.0)

	# Collisions : barres pleines par côté (2 au nord pour laisser l'ouverture)
	for seg: Array in [
		[Vector3(31.0, 0, 24.0), Vector3(4.0, 0.6, 0.18)],
		[Vector3(36.5, 0, 24.0), Vector3(3.0, 0.6, 0.18)],
		[Vector3(33.5, 0, 29.0), Vector3(9.0, 0.6, 0.18)],
		[Vector3(29.0, 0, 26.5), Vector3(0.18, 0.6, 5.0)],
		[Vector3(38.0, 0, 26.5), Vector3(0.18, 0.6, 5.0)],
	]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = seg[1]
		cs.shape = shape
		cs.position = (seg[0] as Vector3) + Vector3(0, 0.3, 0)
		body.add_child(cs)
		add_child(body)


func _place_fence(pos: Vector3, rot_y_deg: float) -> void:
	var fence := KitProps.instance(KitProps.FENCE_LOW)
	fence.scale = Vector3.ONE * 0.96   # segment natif 1.04 → 1 case
	fence.rotation_degrees = Vector3(0, rot_y_deg, 0)
	fence.position = pos
	add_child(fence)


# ── Statues (centre de plaza + accents des ruines) ───────────────────────

func _place_plaza_statue() -> void:
	_place_statue(KitProps.STATUE_RING, Vector3(28.0, 0, 17.0), 2.2, 0.6)


func _place_statue(file: String, pos: Vector3, scale_mult: float, col_radius: float) -> void:
	var statue := KitProps.instance(file)
	statue.scale = Vector3.ONE * scale_mult
	statue.position = pos
	add_child(statue)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = col_radius
	shape.height = 1.4
	cs.shape = shape
	cs.position = pos + Vector3(0, 0.7, 0)
	body.add_child(cs)
	add_child(body)



# ── Grand arbre "hero" ────────────────────────────────────────────────────

func _place_big_tree() -> void:
	_spawn_tree(_cell_to_world(Vector2i(49, 27)), "tree_oak.glb", BIG_TREE_TARGET_HEIGHT)


# ── Ruines (arche sprite + sols dallés + statues Kenney) ──────────────────

func _place_ruins() -> void:
	_stamp_arch(_cell_to_world(Vector2i(44, 5)))
	_stamp_ruins_floor(_cell_to_world(Vector2i(46, 8)))
	_stamp_ruins_floor(_cell_to_world(Vector2i(43, 9)))
	_place_statue(KitProps.STATUE_HEAD, Vector3(48.5, 0, 5.5), 2.0, 0.7)
	_place_statue(KitProps.STATUE_RING, Vector3(41.5, 0, 8.5), 1.6, 0.5)


func _stamp_arch(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var spr := Billboard3D.make_tile_sprite(TILESET_PATH, ATLAS_ARCH, 3, 4, TOWER_SCALE)
	root.add_child(spr)

	# Piliers élargis pour coller à la largeur visible — le passage central
	# reste ouvert (une arche se traverse), seuls les côtés bloquent.
	for x_off in [-0.85 * TOWER_SCALE, 0.85 * TOWER_SCALE]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.75, 3.0, 0.75) * TOWER_SCALE
		cs.shape = shape
		cs.position = Vector3(x_off, 1.5 * TOWER_SCALE, 0)
		body.add_child(cs)
		root.add_child(body)


func _stamp_ruins_floor(pos: Vector3) -> void:
	var mesh_inst := _make_tiled_plane(ATLAS_RUINS_FLOOR, 3, 3)
	mesh_inst.position = pos + Vector3(0, 0.008, 0)
	add_child(mesh_inst)


# ── Tour (sprite 3×5) ──────────────────────────────────────────────────────

const TOWER_SCALE := 1.15   # cohérent avec le grossissement des personnages/props

func _place_tower() -> void:
	var root := Node3D.new()
	root.position = _cell_to_world(Vector2i(4, 5))
	add_child(root)

	var spr := Billboard3D.make_tile_sprite(TILESET_PATH, ATLAS_TOWER, 3, 5, TOWER_SCALE)
	root.add_child(spr)

	# Collision pleine sur toute la largeur visible — empêche de se faufiler
	# sur les côtés ou de finir "derrière" la tour.
	var w := Billboard3D.get_tile_sprite_width(TILESET_PATH, ATLAS_TOWER, 3, 5, TOWER_SCALE)
	var h := 6.0 * TOWER_SCALE
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, w * 0.6)
	cs.shape = shape
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)


# ── Murs de bordure ───────────────────────────────────────────────────────

func _build_border_walls() -> void:
	for r in [
		Rect2(-0.5, -0.5, W + 1, 0.5),
		Rect2(-0.5, H, W + 1, 0.5),
		Rect2(-0.5, -0.5, 0.5, H + 1),
		Rect2(W, -0.5, 0.5, H + 1),
	]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(r.size.x, 3.0, r.size.y)
		cs.shape = shape
		cs.position = Vector3(r.get_center().x, 1.5, r.get_center().y)
		body.add_child(cs)
		add_child(body)


# ── Rangée de test pour les tuiles Outside.png (Pokémon Essentials) ────────
# Conservées pour référence mais PLUS appelées par _generate() — elles
# encombraient le hub compact. Rappeler manuellement au besoin.

func _place_outside_tileset_test_props() -> void:
	var slot := 0
	slot = _place_outside_test_prop(pine_tree_cell, pine_tree_size, slot)
	slot = _place_outside_test_prop(round_tree_cell, round_tree_size, slot)
	slot = _place_outside_test_prop(bush_cell, bush_size, slot)
	slot = _place_outside_test_prop(rock_cell, rock_size, slot)
	slot = _place_outside_test_prop(boulder_cell, boulder_size, slot)
	slot = _place_outside_test_prop(hill_cell, hill_size, slot)
	slot = _place_outside_test_prop(stairs_cell, stairs_size, slot)
	slot = _place_outside_test_prop(cave_entrance_cell, cave_entrance_size, slot)


func _place_outside_test_prop(cell: Vector2i, size: Vector2i, slot: int) -> int:
	if cell == OUTSIDE_UNSET:
		return slot
	var pos := _cell_to_world(Vector2i(10 + slot * 3, 10))
	var spr := Billboard3D.make_tile_sprite(
		OUTSIDE_TILESET_PATH, cell, size.x, size.y, 1.0, OUTSIDE_TILE_PX
	)
	spr.position = pos
	add_child(spr)
	return slot + 1


# ── API publique ──────────────────────────────────────────────────────────

func get_map_size() -> Vector2i:
	return Vector2i(W, H)


func is_water(cell: Vector2i) -> bool:
	return _water_cells.has(cell)
