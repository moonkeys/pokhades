@tool
class_name MapBase
extends Node2D

@onready var _ground:     TileMapLayer = $Ground
@onready var _water:      TileMapLayer = $Water
@onready var _tall_grass: TileMapLayer = $TallGrass
@onready var _objects:    TileMapLayer = $Objects

# ── Réglage des tiles (Inspecteur → Zone1) ───────────────────────────────
@export_group("Source Atlas")
@export var source_id: int = 0   # ID de l'atlas dans le TileSet (généralement 0)

@export_group("Tiles Sol")
@export var tile_grass: Vector2i = Vector2i(56, 33)  # herbe verte

@export_group("Tiles Objets")
# Arbre = bloc 3×3 dans l'atlas, coin haut-gauche = (1,0)
@export var tile_tree_origin: Vector2i = Vector2i(1, 0)

@export_group("Tiles Eau")
@export var tile_water: Vector2i = Vector2i(46, 26)  # eau

@export_group("Tiles Haute Herbe")
@export var tile_tg: Vector2i = Vector2i(3, 20)  # haute herbe

@export_group("Tiles Sol — Chemins")
@export var tile_chemin_terre: Vector2i = Vector2i(2, 16)
@export var tile_dalle_bois:   Vector2i = Vector2i(60, 16)

@export_group("Tiles Décor — Fleurs")
@export var tile_fleur_rouge:    Vector2i = Vector2i(12, 21)
@export var tile_fleur_violette: Vector2i = Vector2i(12, 22)
@export var tile_fleur_blanche:  Vector2i = Vector2i(11, 21)
@export var tiles_petites_fleurs: Array[Vector2i] = [
	Vector2i(10, 20), Vector2i(11, 20), Vector2i(12, 20), Vector2i(10, 21)
]

@export_group("Tiles Décor — Végétation")
@export var tile_petite_herbe:      Vector2i = Vector2i(1, 20)
@export var tile_petit_tronc:       Vector2i = Vector2i(6, 12)
@export var tile_rondin_g:          Vector2i = Vector2i(1, 12)
@export var tile_rondin_d:          Vector2i = Vector2i(2, 12)
@export var tile_gros_tronc_origin: Vector2i = Vector2i(16, 12)

@export_group("Tiles Décor — Roches")
@export var tile_rocher:  Vector2i = Vector2i(22, 37)
@export var tile_cliff:   Vector2i = Vector2i(2, 37)

@export_group("Tiles Coffre")
@export var tile_chest_closed: Vector2i = Vector2i(88, 61)
@export var tile_chest_open:   Vector2i = Vector2i(91, 61)

@export_group("Décors — Densité")
@export_range(0.0, 0.20) var flower_density: float = 0.05
@export_range(0.0, 0.10) var herb_density:   float = 0.025
@export_range(0.0, 0.05) var rock_density:   float = 0.005

# ── Dimensions arène ─────────────────────────────────────────────────────
const W := 80   # 80 × 16px = 1280px (plein écran)
const H := 45   # 45 × 16px = 720px

# Shader eau
var _water_mat: ShaderMaterial = null
const _WATER_SHADER := """
shader_type canvas_item;
uniform float wave_t : hint_range(0.0, 100.0) = 0.0;
void fragment() {
    float wave = sin(UV.y * 12.0 + wave_t) * 0.0025
               + sin(UV.y * 6.0  - wave_t * 0.6) * 0.0015;
    vec2 uv2 = vec2(clamp(UV.x + wave, 0.001, 0.999), UV.y);
    COLOR = texture(TEXTURE, uv2);
    float shimmer = max(0.0, sin(UV.y * 12.0 + wave_t)) * 0.04;
    COLOR.rgb += vec3(0.0, shimmer * 0.6, shimmer);
}
"""


@export_group("Portes")
@export var entry_tile: Vector2i = Vector2i(38, 42)   # bas-centre (entrée)
@export var exit_A:     Vector2i = Vector2i(9,  0)    # sortie haut-gauche
@export var exit_B:     Vector2i = Vector2i(38, 0)    # sortie haut-centre
@export var exit_C:     Vector2i = Vector2i(68, 0)    # sortie haut-droite

@export_group("Éditeur")
@export_tool_button("⟳ Regénérer la map") var _regen: Callable = _generate

func _ready() -> void:
	_generate()
	_setup_water_shader()
	if not Engine.is_editor_hint():
		_build_map_collision()
		_build_pathfinding_grid()
		add_to_group("combat_map")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _water_mat:
		var raw: Variant = _water_mat.get_shader_parameter("wave_t")
		var t: float = float(raw) if raw != null else 0.0
		_water_mat.set_shader_parameter("wave_t", t + delta * 1.2)


# ── Génération ────────────────────────────────────────────────────────────

func _generate() -> void:
	if not _ground.tile_set:
		push_error("Zone1: Ground n'a pas de TileSet assigné !")
		return
	# Auto-détecte le premier source_id disponible si le réglage est invalide
	if not _ground.tile_set.has_source(source_id):
		if _ground.tile_set.get_source_count() == 0:
			push_error("Zone1: TileSet vide, aucun atlas.")
			return
		source_id = _ground.tile_set.get_source_id(0)
		print("Zone1: source_id auto-détecté → %d" % source_id)
	print("Zone1: génération map (source_id=%d)" % source_id)
	_gen_ground()
	_gen_water_pools()
	_gen_border_trees()
	_gen_inner_trees()
	_gen_tall_grass_patches()
	_gen_decorations()
	_gen_chests()
	_clear_exit_gaps()   # doit rester en dernier — efface les couloirs d'accès
	print("Zone1: map générée ✓")


func _gen_ground() -> void:
	for y in H:
		for x in W:
			_ground.set_cell(Vector2i(x, y), source_id, tile_grass)


func _gen_border_trees() -> void:
	var gaps: Array[Vector2i] = [entry_tile, exit_A, exit_B, exit_C]
	var step  := 3
	for x in range(0, W, step):
		if not _near_gap(x, 0,     gaps): _stamp_tree(x, 0)
		if not _near_gap(x, H - 3, gaps): _stamp_tree(x, H - 3)
	for y in range(0, H, step):
		if not _near_gap(0,     y, gaps): _stamp_tree(0, y)
		if not _near_gap(W - 3, y, gaps): _stamp_tree(W - 3, y)


func _near_gap(tx: int, ty: int, gaps: Array[Vector2i]) -> bool:
	for g: Vector2i in gaps:
		if abs(tx - g.x) <= 3 and abs(ty - g.y) <= 3:
			return true
	return false


func _gen_water_pools() -> void:
	# Lac principal — bas gauche
	_fill_water(4, H - 14, 14, H - 3)
	# Petit étang — haut droite
	_fill_water(W - 16, 3, W - 6, 10)


func _fill_water(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			_water.set_cell(Vector2i(x, y), source_id, tile_water)
			# Supprime l'herbe sous l'eau
			_ground.erase_cell(Vector2i(x, y))


func _gen_inner_trees() -> void:
	# Clusters intérieurs
	_fill_trees(9,  3,  18, 9)    # haut-gauche
	_fill_trees(32, H - 12, 42, H - 6)  # bas-centre (H-6 pour laisser le passage entrée libre)
	_fill_trees(W - 18, 15, W - 9, 22)  # droite-centre
	# Arbres isolés pour casser la symétrie
	for pos in [Vector2i(24, 12), Vector2i(54, 9), Vector2i(60, 30),
				Vector2i(18, 30), Vector2i(45, 37), Vector2i(30, 15)]:
		_stamp_tree(pos.x, pos.y)


func _stamp_tree(cx: int, cy: int) -> void:
	# Annule si une case du bloc 3×3 est sur de l'eau
	for dy in range(3):
		for dx in range(3):
			if _water.get_cell_source_id(Vector2i(cx + dx, cy + dy)) != -1:
				return
	for dy in range(3):
		for dx in range(3):
			var atlas_coord := tile_tree_origin + Vector2i(dx, dy)
			_objects.set_cell(Vector2i(cx + dx, cy + dy), source_id, atlas_coord)


func _fill_trees(x0: int, y0: int, x1: int, y1: int) -> void:
	var step := 3
	var y := y0
	while y + 3 <= y1:
		var x := x0
		while x + 3 <= x1:
			_stamp_tree(x, y)
			x += step
		y += step


func _gen_tall_grass_patches() -> void:
	# 4 patches de haute herbe stratégiquement placés
	_fill_tg(18, 8, 26, 14)    # haut-gauche
	_fill_tg(W - 28, 8, W - 20, 14)   # haut-droite
	_fill_tg(18, H - 18, 26, H - 12)  # bas-gauche
	_fill_tg(W - 28, H - 18, W - 20, H - 12)  # bas-droite


func _fill_tg(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			# Haute herbe seulement si pas d'arbre à cet endroit
			if _objects.get_cell_source_id(Vector2i(x, y)) == -1:
				_tall_grass.set_cell(Vector2i(x, y), source_id, tile_tg)


# ── Décorations ──────────────────────────────────────────────────────────

func _gen_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99371

	var flowers := [tile_fleur_rouge, tile_fleur_violette, tile_fleur_blanche]
	flowers.append_array(tiles_petites_fleurs)

	for y in range(3, H - 3):
		for x in range(3, W - 3):
			var cell := Vector2i(x, y)
			if _ground.get_cell_source_id(cell) == -1:    continue
			if _objects.get_cell_source_id(cell) != -1:   continue
			if _water.get_cell_source_id(cell) != -1:     continue
			if _tall_grass.get_cell_source_id(cell) != -1: continue
			# Pas de décorations sur les tiles de chemin (dalles, terre)
			var ground_a := _ground.get_cell_atlas_coords(cell)
			if ground_a == tile_chemin_terre or ground_a == tile_dalle_bois: continue
			var r := rng.randf()
			if r < flower_density:
				# Fleurs → layer tallgrass (rendu sol, pas au-dessus du joueur)
				_tall_grass.set_cell(cell, source_id, flowers[rng.randi() % flowers.size()])
			elif r < flower_density + herb_density:
				_tall_grass.set_cell(cell, source_id, tile_petite_herbe)
			elif r < flower_density + herb_density + rock_density:
				_objects.set_cell(cell, source_id, tile_rocher)

	_gen_logs()


func _gen_logs() -> void:
	for pos: Vector2i in [Vector2i(22, 16), Vector2i(55, 22), Vector2i(38, 33), Vector2i(15, 29)]:
		var r := Vector2i(pos.x + 1, pos.y)
		if _objects.get_cell_source_id(pos) != -1: continue
		if _water.get_cell_source_id(pos) != -1: continue
		_objects.set_cell(pos, source_id, tile_rondin_g)
		_objects.set_cell(r,   source_id, tile_rondin_d)
	for pos: Vector2i in [Vector2i(28, 10), Vector2i(64, 29), Vector2i(46, 18)]:
		if _objects.get_cell_source_id(pos) != -1: continue
		if _water.get_cell_source_id(pos) != -1: continue
		_objects.set_cell(pos, source_id, tile_petit_tronc)


func _gen_chests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var candidates: Array[Vector2i] = []
	for y in range(12, H - 12):   # loin des couloirs d'entrée/sortie
		for x in range(10, W - 10):
			var cell := Vector2i(x, y)
			if _objects.get_cell_source_id(cell) != -1: continue
			if _water.get_cell_source_id(cell)   != -1: continue
			if _tall_grass.get_cell_source_id(cell) != -1: continue
			var ga := _ground.get_cell_atlas_coords(cell)
			if ga == tile_chemin_terre or ga == tile_dalle_bois: continue
			candidates.append(cell)
	candidates.shuffle()
	var count := mini(2, candidates.size())
	for i in count:
		_objects.set_cell(candidates[i], source_id, tile_chest_closed)


func _clear_exit_gaps() -> void:
	# Creuse un couloir 7 tuiles large — profondeur limitée à la bordure seulement
	# (trop profond = coupe les arbres intérieurs des zones enfants)
	for exit in [exit_A, exit_B, exit_C]:
		for dy in range(-1, 4):   # y = exit.y-1 à +3 : couvre uniquement la bordure
			for dx in range(-3, 4):
				var c := Vector2i(exit.x + dx, exit.y + dy)
				if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H: continue
				_objects.erase_cell(c)
				_tall_grass.erase_cell(c)
	# Entrée (bas) — même profondeur limitée
	for dy in range(-4, 1):
		for dx in range(-3, 4):
			var c := Vector2i(entry_tile.x + dx, entry_tile.y + dy)
			if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H: continue
			_objects.erase_cell(c)
			_tall_grass.erase_cell(c)


func _is_decor_tile(a: Vector2i) -> bool:
	if a == tile_fleur_rouge or a == tile_fleur_violette or a == tile_fleur_blanche:
		return true
	if a == tile_petite_herbe:
		return true
	for f: Vector2i in tiles_petites_fleurs:
		if a == f:
			return true
	return false


# ── Collisions ───────────────────────────────────────────────────────────

func _build_map_collision() -> void:
	# Un seul StaticBody2D pour toutes les tiles — réduit massivement la création de noeuds
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	add_child(body)
	for cell: Vector2i in _objects.get_used_cells():
		var atlas := _objects.get_cell_atlas_coords(cell)
		if not _is_decor_tile(atlas):
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size     = _col_size(atlas)
			cs.position = _objects.map_to_local(cell)
			cs.shape    = sh
			body.add_child(cs)
	for cell: Vector2i in _water.get_used_cells():
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = Vector2(10, 10)   # réduit : laisse 6px de passage vs arbre (10px)
		cs.position = _water.map_to_local(cell)
		cs.shape    = sh
		body.add_child(cs)
	_add_border_walls()


func _col_size(atlas: Vector2i) -> Vector2:
	if atlas == tile_rocher:
		return Vector2(8, 8)
	if atlas == tile_cliff:
		return Vector2(14, 5)
	if atlas == tile_rondin_g or atlas == tile_rondin_d:
		return Vector2(12, 6)
	if atlas == tile_petit_tronc:
		return Vector2(8, 8)
	# Arbres et gros tronc : hitbox centré dans la tile
	return Vector2(10, 10)


func _add_tile_body(cell: Vector2i, layer: TileMapLayer, col_size: Vector2 = Vector2(10, 10)) -> void:
	var body := StaticBody2D.new()
	body.position       = layer.map_to_local(cell)
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size  = col_size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


func _add_border_walls() -> void:
	# 4 murs invisibles autour de la map entière
	for wall_rect in [
		Rect2(-8,      -8,      W * 16 + 16, 8),          # haut
		Rect2(-8,      H * 16,  W * 16 + 16, 8),          # bas
		Rect2(-8,      -8,      8,            H * 16 + 16), # gauche
		Rect2(W * 16,  -8,      8,            H * 16 + 16), # droite
	]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = wall_rect.size
		cs.position = wall_rect.get_center()
		cs.shape    = sh
		body.add_child(cs)
		add_child(body)


# ── Eau shader ────────────────────────────────────────────────────────────

func _setup_water_shader() -> void:
	if not is_instance_valid(_water):
		return
	var sh := Shader.new()
	sh.code       = _WATER_SHADER
	_water_mat    = ShaderMaterial.new()
	_water_mat.shader = sh
	_water.material   = _water_mat


# ── Haute herbe → Area2D pour combat ─────────────────────────────────────

func _build_tall_grass_areas() -> void:
	if not is_instance_valid(_tall_grass):
		return
	var ts := Vector2(16, 16)
	if _tall_grass.tile_set:
		ts = Vector2(_tall_grass.tile_set.tile_size)
	for cell: Vector2i in _tall_grass.get_used_cells():
		var area := Area2D.new()
		var cs   := CollisionShape2D.new()
		var sh   := RectangleShape2D.new()
		sh.size       = ts
		cs.shape      = sh
		area.position = _tall_grass.map_to_local(cell)
		area.name     = "TG_%d_%d" % [cell.x, cell.y]
		area.collision_layer = 0
		area.collision_mask  = 2
		area.add_child(cs)
		add_child(area)


# ── API publique ──────────────────────────────────────────────────────────

## Dimensions réelles de la map en pixels — override dans MapGenerator.
func get_map_pixel_size() -> Vector2:
	return Vector2(W * 16, H * 16)


func is_valid_spawn(world_pos: Vector2) -> bool:
	var cell := _ground.local_to_map(_ground.to_local(world_pos))
	if cell.x < 6 or cell.x >= W - 6: return false
	if cell.y < 6 or cell.y >= H - 6: return false
	if _water.get_cell_source_id(cell)   != -1: return false
	if _objects.get_cell_source_id(cell) != -1: return false
	# Exclure aussi les tiles adjacentes — évite les spawns collés à un arbre
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _objects.get_cell_source_id(cell + Vector2i(dx, dy)) != -1:
				return false
	return _ground.get_cell_source_id(cell) != -1


func get_chest_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _objects.get_used_cells():
		if _objects.get_cell_atlas_coords(cell) == tile_chest_closed:
			cells.append(cell)
	return cells


## Taille de la map en cellules — surchargé dans MapGenerator (taille variable).
func get_map_cell_size() -> Vector2i:
	return Vector2i(W, H)


## Cellules d'entrée de grotte — surchargé dans MapGenerator. Vide par défaut.
func get_cave_cells() -> Array[Vector2i]:
	return []


## Obstacles CS — surchargés dans MapGenerator. Vides par défaut.
func get_force_boulder_approaches() -> Dictionary:
	return {}

func get_coupe_tree_approaches() -> Array:
	return []

func break_rock_at(_cell: Vector2i) -> void:
	pass

func cut_tree_group(_cells: Array) -> void:
	pass


func get_objects_layer() -> TileMapLayer:
	return _objects


func is_tall_grass(world_pos: Vector2) -> bool:
	if not is_instance_valid(_tall_grass):
		return false
	var cell := _tall_grass.local_to_map(_tall_grass.to_local(world_pos))
	if _tall_grass.get_cell_source_id(cell) == -1:
		return false
	# Seule la tile tile_tg déclenche les combats — pas les fleurs/petites herbes
	return _tall_grass.get_cell_atlas_coords(cell) == tile_tg


# ── Pathfinding (contournement d'obstacles pour l'IA) ──────────────────────

var _astar: AStarGrid2D = null

## Construit la grille A* à partir des mêmes obstacles que _build_map_collision()
## (objets non-décoratifs + eau). Appelé une fois après génération.
func _build_pathfinding_grid() -> void:
	var sz := get_map_cell_size()
	_astar = AStarGrid2D.new()
	_astar.region        = Rect2i(0, 0, sz.x, sz.y)
	_astar.cell_size      = Vector2(16, 16)
	_astar.diagonal_mode   = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic  = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

	for cell: Vector2i in _objects.get_used_cells():
		if not _astar.is_in_boundsv(cell):
			continue
		if not _is_decor_tile(_objects.get_cell_atlas_coords(cell)):
			_astar.set_point_solid(cell, true)
	for cell: Vector2i in _water.get_used_cells():
		if _astar.is_in_boundsv(cell):
			_astar.set_point_solid(cell, true)


## Prochaine case (en coordonnées monde) à viser pour contourner les obstacles
## entre `from_world` et `to_world`. Retourne `to_world` tel quel si aucun
## chemin n'est trouvé (cible hors grille, dans un mur, etc.) — fallback ligne droite.
func get_next_path_point(from_world: Vector2, to_world: Vector2) -> Vector2:
	if not is_instance_valid(_astar):
		return to_world
	var from_cell := _objects.local_to_map(_objects.to_local(from_world))
	var to_cell   := _objects.local_to_map(_objects.to_local(to_world))
	if not _astar.is_in_boundsv(from_cell) or not _astar.is_in_boundsv(to_cell):
		return to_world
	if _astar.is_point_solid(from_cell) or _astar.is_point_solid(to_cell):
		return to_world
	var ids: Array = _astar.get_id_path(from_cell, to_cell)
	if ids.size() < 2:
		return to_world
	return _objects.map_to_local(ids[1])
