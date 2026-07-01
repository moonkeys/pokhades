@tool
class_name HubMap
extends Node2D

@export_group("Source Atlas")
@export var source_id: int = 0

@export_group("Tiles")
@export var tile_grass:       Vector2i = Vector2i(56, 33)
@export var tile_tree_origin: Vector2i = Vector2i(1, 0)
@export var tile_water:       Vector2i = Vector2i(46, 26)
@export var tile_path:        Vector2i = Vector2i(56, 33)

const W := 80
const H := 45

var _ground:  TileMapLayer = null
var _water:   TileMapLayer = null
var _objects: TileMapLayer = null

const NPC_TILES := {
	"start":    Vector2i(40, 11),
	"shop":     Vector2i(13, 24),
	"pokedex":  Vector2i(13, 35),
	"upgrades": Vector2i(66, 35),
	"moves":    Vector2i(40, 18),   # Espeon — tuteur de capacités, chemin central
}
const PLAYER_TILE := Vector2i(40, 31)

# Position pixel du sommet de la tour (pour le Pokémon garde dans HubWorld)
const TOWER_GUARD_POS := Vector2(88, 136)

@export_group("Éditeur")
@export_tool_button("⟳ Regénérer la map") var _regen: Callable = _regenerate_in_editor

func _regenerate_in_editor() -> void:
	_create_layers(); _auto_source_id(); _generate()

func _ready() -> void:
	_create_layers(); _auto_source_id(); _generate()
	if not Engine.is_editor_hint():
		_build_collision()

func _create_layers() -> void:
	var g := get_node_or_null("Ground")  as TileMapLayer
	var w := get_node_or_null("Water")   as TileMapLayer
	var o := get_node_or_null("Objects") as TileMapLayer
	_ground  = g if is_instance_valid(g) else _make_layer("Ground",  0)
	_water   = w if is_instance_valid(w) else _make_layer("Water",   1)
	_objects = o if is_instance_valid(o) else _make_layer("Objects", 2)

func _make_layer(n: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = n; layer.z_index = z; layer.rendering_quadrant_size = 16
	var ts := "res://scenes/world/rse.tres"
	if ResourceLoader.exists(ts): layer.tile_set = load(ts)
	add_child(layer); return layer

func _auto_source_id() -> void:
	if not _ground.tile_set: return
	if not _ground.tile_set.has_source(source_id):
		if _ground.tile_set.get_source_count() > 0:
			source_id = _ground.tile_set.get_source_id(0)


# ── Génération principale ─────────────────────────────────────────────────

func _generate() -> void:
	if not (_ground and _ground.tile_set):
		push_error("HubMap: TileSet manquant"); return
	_ground.clear(); _water.clear(); _objects.clear()
	_fill_ground()
	_draw_water_pond()
	_draw_paths()
	_draw_border_trees()
	_draw_inner_trees()
	_place_lampadaires()
	_place_market_stall()
	_place_big_tree()
	_place_tournesol()
	_place_ruins()
	_place_tower()


# ── Fond herbeux ──────────────────────────────────────────────────────────

func _fill_ground() -> void:
	for y in H:
		for x in W:
			_ground.set_cell(Vector2i(x, y), source_id, tile_grass)


# ── Étang ─────────────────────────────────────────────────────────────────

func _draw_water_pond() -> void:
	for y in range(36, 43):
		for x in range(5, 12):
			_water.set_cell(Vector2i(x, y), source_id, tile_water)
			_ground.erase_cell(Vector2i(x, y))


# ── Chemins ───────────────────────────────────────────────────────────────

func _draw_paths() -> void:
	_fill_path(38, 42, 3, 44)        # vertical central
	_fill_path(6,  37, 22, 26)       # horizontal gauche — MIRA/YUNA niveau haut
	_fill_path(42, 74, 22, 26)       # horizontal droite — KO niveau haut
	_fill_path(6,  37, 33, 37)       # horizontal gauche — YUNA niveau bas
	_fill_path(42, 74, 33, 37)       # horizontal droite — ARCAS niveau bas
	_fill_path(33, 47, 27, 37)       # plaza centrale autour du joueur

func _fill_path(x0: int, x1: int, y0: int, y1: int) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			_ground.set_cell(Vector2i(x, y), source_id, tile_path)


# ── Arbres de bordure ─────────────────────────────────────────────────────

func _draw_border_trees() -> void:
	for x in range(0, W - 2, 3):
		_stamp_tree(x, 0)
		_stamp_tree(x, H - 3)
	for y in range(0, H - 2, 3):
		_stamp_tree(0, y)
		_stamp_tree(W - 3, y)


# ── Arbres intérieurs ─────────────────────────────────────────────────────

func _draw_inner_trees() -> void:
	_fill_trees(9, 4, 21, 17)    # haut-gauche (clair pour market stall en-dessous)
	_fill_trees(71, 4, 77, 21)   # haut-droite (clair pour ruines + grand arbre)
	_fill_trees(14, 38, 21, 42)  # bas-gauche (à droite de l'étang)
	_fill_trees(71, 38, 77, 42)  # bas-droite
	_fill_trees(9, 27, 21, 32)   # entre MIRA et YUNA
	_fill_trees(71, 27, 77, 32)  # entre KO et ARCAS

func _fill_trees(x0: int, y0: int, x1: int, y1: int) -> void:
	var y := y0
	while y + 3 <= y1:
		var x := x0
		while x + 3 <= x1:
			_stamp_tree(x, y)
			x += 3
		y += 3

func _stamp_tree(cx: int, cy: int) -> void:
	for dy in range(3):
		for dx in range(3):
			var pos := Vector2i(cx + dx, cy + dy)
			if pos.x >= W or pos.y >= H: return
			if _water.get_cell_source_id(pos) != -1: return
	for dy in range(3):
		for dx in range(3):
			_objects.set_cell(Vector2i(cx + dx, cy + dy),
				source_id, tile_tree_origin + Vector2i(dx, dy))


# ── Lampadaires ───────────────────────────────────────────────────────────

func _place_lampadaires() -> void:
	# Flanquant le chemin vertical vers PÉPITE
	_stamp_lamp_std(36, 15)
	_stamp_lamp_std(42, 15)
	# Jonction chemin horizontal gauche ↔ vertical
	_stamp_lamp_right(34, 22)
	_stamp_lamp_right(34, 33)
	# Jonction chemin horizontal droite ↔ vertical
	_stamp_lamp_left(47, 22)
	_stamp_lamp_left(47, 33)
	# Entrée de la plaza
	_stamp_lamp_double(37, 27)
	_stamp_lamp_double(42, 27)

func _stamp_lamp_std(mx: int, my: int) -> void:
	_objects.set_cell(Vector2i(mx, my),   source_id, Vector2i(37, 60))
	_objects.set_cell(Vector2i(mx, my+1), source_id, Vector2i(37, 61))
	_objects.set_cell(Vector2i(mx, my+2), source_id, Vector2i(37, 62))

func _stamp_lamp_right(mx: int, my: int) -> void:
	# Pôle col gauche (38,x), bras col droite (39,x)
	_objects.set_cell(Vector2i(mx,   my),   source_id, Vector2i(38, 60))
	_objects.set_cell(Vector2i(mx,   my+1), source_id, Vector2i(38, 61))
	_objects.set_cell(Vector2i(mx,   my+2), source_id, Vector2i(38, 62))
	_objects.set_cell(Vector2i(mx+1, my),   source_id, Vector2i(39, 60))
	_objects.set_cell(Vector2i(mx+1, my+1), source_id, Vector2i(39, 61))

func _stamp_lamp_left(mx: int, my: int) -> void:
	# Bras col gauche (40,x), pôle col droite (41,x)
	_objects.set_cell(Vector2i(mx,   my),   source_id, Vector2i(40, 60))
	_objects.set_cell(Vector2i(mx,   my+1), source_id, Vector2i(40, 61))
	_objects.set_cell(Vector2i(mx+1, my),   source_id, Vector2i(41, 60))
	_objects.set_cell(Vector2i(mx+1, my+1), source_id, Vector2i(41, 61))
	_objects.set_cell(Vector2i(mx+1, my+2), source_id, Vector2i(41, 62))

func _stamp_lamp_double(mx: int, my: int) -> void:
	_objects.set_cell(Vector2i(mx, my),   source_id, Vector2i(42, 60))
	_objects.set_cell(Vector2i(mx, my+1), source_id, Vector2i(42, 61))
	_objects.set_cell(Vector2i(mx, my+2), source_id, Vector2i(42, 62))


# ── Paravent marché ───────────────────────────────────────────────────────

func _place_market_stall() -> void:
	# Juste au-dessus du chemin gauche, près de MIRA (shop)
	_stamp_market(9, 18)

func _stamp_market(mx: int, my: int) -> void:
	for dy in range(4):
		for dx in range(4):
			_objects.set_cell(Vector2i(mx+dx, my+dy),
				source_id, Vector2i(31+dx, 60+dy))


# ── Grand arbre 5×5 ──────────────────────────────────────────────────────

func _place_big_tree() -> void:
	# Coin supérieur droit, entre la zone ruines et la bordure
	_stamp_big_tree(65, 5)

func _stamp_big_tree(mx: int, my: int) -> void:
	# Atlas centré en (57,52) → bloc 5×5 de (55,50) à (59,54)
	for dy in range(5):
		for dx in range(5):
			_objects.set_cell(Vector2i(mx+dx, my+dy),
				source_id, Vector2i(55+dx, 50+dy))


# ── Ensemble tournesols 3×3 ───────────────────────────────────────────────

func _place_tournesol() -> void:
	# Jardin en bas de la plaza
	_stamp_tournesol(41, 38)
	_stamp_tournesol(45, 38)

func _stamp_tournesol(mx: int, my: int) -> void:
	# Atlas centré en (89,49) → bloc 3×3 de (88,48) à (90,50)
	for dy in range(3):
		for dx in range(3):
			_objects.set_cell(Vector2i(mx+dx, my+dy),
				source_id, Vector2i(88+dx, 48+dy))


# ── Ruines ────────────────────────────────────────────────────────────────

func _place_ruins() -> void:
	# Arche ronde cassée 3×4
	_stamp_arch(59, 5)
	# Sols avec bordures d'herbe
	_stamp_ruins_floor(62, 8)
	_stamp_ruins_floor(62, 11)

func _stamp_arch(mx: int, my: int) -> void:
	# Atlas 3×4 de (71,48) à (73,51)
	for dy in range(4):
		for dx in range(3):
			_objects.set_cell(Vector2i(mx+dx, my+dy),
				source_id, Vector2i(71+dx, 48+dy))

func _stamp_ruins_floor(mx: int, my: int) -> void:
	# Sol dallé 3×3 avec bordures d'herbe directionnelles
	# Atlas : centre (56,45), coins/bords autour
	_ground.set_cell(Vector2i(mx,   my),   source_id, Vector2i(55, 44))  # coin ↖
	_ground.set_cell(Vector2i(mx+1, my),   source_id, Vector2i(56, 44))  # bord ↑
	_ground.set_cell(Vector2i(mx+2, my),   source_id, Vector2i(57, 44))  # coin ↗
	_ground.set_cell(Vector2i(mx,   my+1), source_id, Vector2i(55, 45))  # bord ←
	_ground.set_cell(Vector2i(mx+1, my+1), source_id, Vector2i(56, 45))  # centre
	_ground.set_cell(Vector2i(mx+2, my+1), source_id, Vector2i(57, 45))  # bord →
	_ground.set_cell(Vector2i(mx,   my+2), source_id, Vector2i(55, 46))  # coin ↙
	_ground.set_cell(Vector2i(mx+1, my+2), source_id, Vector2i(56, 46))  # bord ↓
	_ground.set_cell(Vector2i(mx+2, my+2), source_id, Vector2i(57, 46))  # coin ↘


# ── Tour ──────────────────────────────────────────────────────────────────

func _place_tower() -> void:
	# Tour 3×5 dans le coin supérieur gauche
	# Atlas (27,44) à (29,48) — la tile (28,45) montre le garde au sommet
	_stamp_tower(4, 7)

func _stamp_tower(mx: int, my: int) -> void:
	for dy in range(5):
		for dx in range(3):
			_objects.set_cell(Vector2i(mx+dx, my+dy),
				source_id, Vector2i(27+dx, 44+dy))


# ── Collisions ────────────────────────────────────────────────────────────

func _build_collision() -> void:
	for cell: Vector2i in _objects.get_used_cells():
		_add_wall(cell, _objects)
	for cell: Vector2i in _water.get_used_cells():
		_add_wall(cell, _water)
	_add_border_walls()

func _add_wall(cell: Vector2i, layer: TileMapLayer) -> void:
	var body := StaticBody2D.new()
	body.position        = layer.map_to_local(cell)
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size  = Vector2(16, 16)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)

func _add_border_walls() -> void:
	for r: Rect2 in [
		Rect2(-8, -8,     W * 16 + 16, 8),
		Rect2(-8, H * 16, W * 16 + 16, 8),
		Rect2(-8, -8,     8, H * 16 + 16),
		Rect2(W * 16, -8, 8, H * 16 + 16),
	]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = r.size
		cs.position = r.get_center()
		cs.shape    = sh
		body.add_child(cs)
		add_child(body)
