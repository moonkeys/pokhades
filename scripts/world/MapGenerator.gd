@tool
class_name MapGenerator
extends Zone1  # MUST extend Zone1 — CombatArena.gd cast: get_node("Map") as Zone1

enum Terrain { GRASS = 0, PATH = 1, WATER = 2, TREE = 3 }
enum GatingType { NONE = 0, SURF = 1, COUPE = 2, FORCE = 3 }

## ─────────────────────────────────────────────────────────────────
## EXPORTS SPÉCIFIQUES AU GÉNÉRATEUR PROCÉDURAL
## (tile_*, source_id, flower_density, entry_tile, exit_A/B/C, etc.
##  sont hérités de Zone1 — ne pas re-déclarer ici)
## ─────────────────────────────────────────────────────────────────
@export_group("Map — Taille")
@export var map_size:     Vector2i = Vector2i(80, 45)
@export var map_seed:     int      = 0
@export var random_size:  bool     = true
@export var map_size_min: Vector2i = Vector2i(60, 35)
@export var map_size_max: Vector2i = Vector2i(96, 56)

@export_group("Map — Chemins")
@export_range(1, 7) var path_width: int = 3

@export_group("Terrain — Eau")
@export_range(0.0, 1.0) var water_threshold:      float = 0.45
@export var water_noise_frequency: float = 0.08
@export var water_noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_CELLULAR
@export_range(0, 5) var min_water_pools: int = 2

@export_group("Terrain — Arbres")
@export_range(0.0, 1.0) var tree_density:         float = 0.35
@export var tree_noise_frequency: float = 0.12

@export_group("Ennemis")
@export_range(1, 20) var min_enemy_distance: int = 8

@export_group("Coffre & Gating")
@export var gating_type: GatingType = GatingType.NONE

@export_group("Tiles Gating")
@export var tile_bush:    Vector2i = Vector2i(3,  20)
@export var tile_boulder: Vector2i = Vector2i(22, 37)

## ─────────────────────────────────────────────────────────────────
## ÉTAT INTERNE
## ─────────────────────────────────────────────────────────────────
var _grid: Array = []
var _rng:  RandomNumberGenerator = RandomNumberGenerator.new()
var _flower_mat: ShaderMaterial = null

const _FLOWER_SHADER := """
shader_type canvas_item;
uniform float wind_t : hint_range(0.0, 1000.0) = 0.0;
void vertex() {
    float sway = sin(wind_t * 1.6 + VERTEX.x * 0.06) * 0.7;
    VERTEX.x += sway * (1.0 - UV.y);
}
"""


## ─────────────────────────────────────────────────────────────────
## CALLBACKS GODOT
## ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_generate()
	_setup_water_shader()
	if not Engine.is_editor_hint():
		_build_map_collision()
		_build_tall_grass_areas()
		_setup_flower_shader()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _water_mat:
		var raw: Variant = _water_mat.get_shader_parameter("wave_t")
		var t: float = float(raw) if raw != null else 0.0
		_water_mat.set_shader_parameter("wave_t", t + delta * 1.2)
	if _flower_mat:
		var raw: Variant = _flower_mat.get_shader_parameter("wind_t")
		var t: float = float(raw) if raw != null else 0.0
		_flower_mat.set_shader_parameter("wind_t", t + delta * 0.8)


## ─────────────────────────────────────────────────────────────────
## GÉNÉRATION — override de Zone1._generate()
## Le bouton "⟳ Regénérer la map" hérité de Zone1 appelle _generate(),
## qui pointe maintenant vers cette méthode.
## ─────────────────────────────────────────────────────────────────

func _generate() -> void:
	if not is_instance_valid(_ground) or not _ground.tile_set:
		push_error("MapGenerator: Ground layer manquant ou sans TileSet.")
		return
	if not _ground.tile_set.has_source(source_id):
		if _ground.tile_set.get_source_count() == 0:
			push_error("MapGenerator: TileSet vide.")
			return
		source_id = _ground.tile_set.get_source_id(0)

	_rng.seed = map_seed if map_seed != 0 else randi()

	if random_size:
		map_size = Vector2i(
			_rng.randi_range(map_size_min.x, map_size_max.x),
			_rng.randi_range(map_size_min.y, map_size_max.y)
		)
	_compute_portals()

	print("MapGenerator: seed=%d  taille=%s" % [_rng.seed, map_size])

	_init_grid()
	_gen_water_noise()
	_ensure_water_pools()
	_gen_tree_noise()
	_carve_border()
	_carve_paths()
	_apply_to_tilemap()
	_gen_tall_grass()
	_gen_decorations()
	_place_chest_gated()
	_clear_portal_zones()
	_objects.y_sort_enabled = true
	print("MapGenerator: génération terminée.")


## ─────────────────────────────────────────────────────────────────
## 1 — INIT
## ─────────────────────────────────────────────────────────────────

func _init_grid() -> void:
	var W := map_size.x
	var H := map_size.y
	_grid.clear()
	_grid.resize(H)
	for r in H:
		var row := PackedByteArray()
		row.resize(W)
		row.fill(Terrain.GRASS)
		_grid[r] = row
	_ground.clear()
	_water.clear()
	_tall_grass.clear()
	_objects.clear()


## ─────────────────────────────────────────────────────────────────
## 2 — EAU
## ─────────────────────────────────────────────────────────────────

func _gen_water_noise() -> void:
	var W := map_size.x
	var H := map_size.y
	var noise := FastNoiseLite.new()
	noise.noise_type = water_noise_type
	noise.seed       = _rng.randi()
	noise.frequency  = water_noise_frequency
	var threshold := water_threshold * 2.0 - 1.0
	for r in range(3, H - 3):
		for c in range(3, W - 3):
			if _is_near_portal(c, r, 5):
				continue
			if noise.get_noise_2d(float(c), float(r)) > threshold:
				_grid[r][c] = Terrain.WATER


func _ensure_water_pools() -> void:
	var W := map_size.x
	var H := map_size.y
	var visited: Dictionary = {}
	var pool_count := 0
	for r in range(3, H - 3):
		for c in range(3, W - 3):
			var cell := Vector2i(c, r)
			if _grid[r][c] != Terrain.WATER or cell in visited:
				continue
			pool_count += 1
			var q: Array[Vector2i] = [cell]
			visited[cell] = true
			while not q.is_empty():
				var cur: Vector2i = q.pop_back()
				for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nb: Vector2i = cur + d
					if nb.x < 0 or nb.x >= W or nb.y < 0 or nb.y >= H: continue
					if nb in visited or _grid[nb.y][nb.x] != Terrain.WATER: continue
					visited[nb] = true
					q.append(nb)

	var needed := min_water_pools - pool_count
	if needed <= 0:
		return
	var candidates: Array[Vector2i] = []
	for r in range(8, H - 8):
		for c in range(8, W - 8):
			if _grid[r][c] == Terrain.GRASS and not _is_near_portal(c, r, 8):
				candidates.append(Vector2i(c, r))
	candidates.shuffle()
	var placed := 0
	for center: Vector2i in candidates:
		if placed >= needed:
			break
		var too_close := false
		for dy in range(-6, 7):
			if too_close: break
			for dx in range(-6, 7):
				var ny := center.y + dy
				var nx := center.x + dx
				if ny < 0 or ny >= H or nx < 0 or nx >= W: continue
				if _grid[ny][nx] == Terrain.WATER:
					too_close = true
					break
		if too_close:
			continue
		for dy in range(-2, 3):
			for dx in range(-3, 4):
				if abs(dx) == 3 and abs(dy) == 2: continue
				var cell := center + Vector2i(dx, dy)
				if cell.x < 3 or cell.x >= W - 3 or cell.y < 3 or cell.y >= H - 3: continue
				_grid[cell.y][cell.x] = Terrain.WATER
		placed += 1


## ─────────────────────────────────────────────────────────────────
## 3 — ARBRES
## ─────────────────────────────────────────────────────────────────

func _gen_tree_noise() -> void:
	var W := map_size.x
	var H := map_size.y
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed       = _rng.randi()
	noise.frequency  = tree_noise_frequency
	for r in range(2, H - 2):
		for c in range(2, W - 2):
			if _grid[r][c] == Terrain.WATER:
				continue
			if _is_near_portal(c, r, 4):
				continue
			var v := (noise.get_noise_2d(float(c), float(r)) + 1.0) * 0.5
			if v < tree_density:
				_grid[r][c] = Terrain.TREE


func _compute_portals() -> void:
	var W := map_size.x
	var H := map_size.y
	entry_tile = Vector2i(W / 2, H - 5)
	exit_A     = Vector2i(W / 6,     0)
	exit_B     = Vector2i(W / 2,     0)
	exit_C     = Vector2i(W * 5 / 6, 0)


## ─────────────────────────────────────────────────────────────────
## 4 — BORDURE D'ARBRES
## ─────────────────────────────────────────────────────────────────

func _carve_border() -> void:
	var W := map_size.x
	var H := map_size.y
	for r in H:
		for c in W:
			if r < 4 or r >= H - 4 or c < 4 or c >= W - 4:
				_grid[r][c] = Terrain.TREE


## ─────────────────────────────────────────────────────────────────
## 5 — CHEMINS (BFS + waypoints pour casser le motif trident)
## ─────────────────────────────────────────────────────────────────

func _carve_paths() -> void:
	var W := map_size.x
	for ex: Vector2i in [exit_A, exit_B, exit_C]:
		# Waypoint décalé latéralement — donne des chemins en L ou S
		var mid_x: int = clampi(
			(entry_tile.x + ex.x) / 2 + _rng.randi_range(-W / 4, W / 4),
			6, W - 6
		)
		var mid_y: int = (entry_tile.y + ex.y) / 2
		var wp    := Vector2i(mid_x, mid_y)
		_carve_single_path(entry_tile, wp)
		_carve_single_path(wp, ex)


func _carve_single_path(from: Vector2i, to: Vector2i) -> void:
	var W := map_size.x
	var H := map_size.y
	var came_from: Dictionary = { from: from }
	var queue: Array[Vector2i] = [from]
	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var found := false

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			found = true
			break
		for d: Vector2i in dirs:
			var n := cur + d
			if n.x < 0 or n.x >= W or n.y < 0 or n.y >= H: continue
			if n in came_from: continue
			came_from[n] = cur
			queue.append(n)

	if not found:
		push_warning("MapGenerator: pas de chemin %s → %s" % [from, to])
		return

	var path: Array[Vector2i] = []
	var cur := to
	while cur != from:
		path.append(cur)
		cur = came_from[cur]
	path.append(from)

	var half := path_width / 2
	for tile: Vector2i in path:
		for dy in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var cell := tile + Vector2i(dx, dy)
				if cell.x < 2 or cell.x >= W - 2 or cell.y < 2 or cell.y >= H - 2: continue
				_grid[cell.y][cell.x] = Terrain.PATH


## ─────────────────────────────────────────────────────────────────
## 6 — GRILLE → TILEMAPLAYERS
## ─────────────────────────────────────────────────────────────────

func _apply_to_tilemap() -> void:
	var W := map_size.x
	var H := map_size.y
	for r in H:
		for c in W:
			if _grid[r][c] == Terrain.TREE and _can_stamp_tree(c, r):
				_stamp_tree(c, r)
				for dy in 3:
					for dx in 3:
						if r + dy < H and c + dx < W:
							_grid[r + dy][c + dx] = Terrain.TREE

	for r in H:
		for c in W:
			var cell := Vector2i(c, r)
			match _grid[r][c]:
				Terrain.WATER:
					_water.set_cell(cell, source_id, tile_water)
				Terrain.PATH:
					_ground.set_cell(cell, source_id, tile_chemin_terre)
				_:
					if _ground.get_cell_source_id(cell) == -1:
						_ground.set_cell(cell, source_id, tile_grass)


func _can_stamp_tree(c: int, r: int) -> bool:
	var W := map_size.x
	var H := map_size.y
	if c + 2 >= W or r + 2 >= H:
		return false
	for dy in 3:
		for dx in 3:
			var cx := c + dx
			var cy := r + dy
			var t: int = _grid[cy][cx]
			if t == Terrain.WATER or t == Terrain.PATH:
				return false
			if _objects.get_cell_source_id(Vector2i(cx, cy)) != -1:
				return false
			if _is_near_portal(cx, cy, 6):
				return false
	return true


# Override de Zone1._stamp_tree — pose aussi le sol sous l'arbre.
func _stamp_tree(cx: int, cy: int) -> void:
	for dy in 3:
		for dx in 3:
			_ground.set_cell(Vector2i(cx + dx, cy + dy), source_id, tile_grass)
	for dy in 3:
		for dx in 3:
			_objects.set_cell(
				Vector2i(cx + dx, cy + dy),
				source_id,
				tile_tree_origin + Vector2i(dx, dy)
			)


## ─────────────────────────────────────────────────────────────────
## 7 — HAUTE HERBE
## ─────────────────────────────────────────────────────────────────

func _gen_tall_grass() -> void:
	var W := map_size.x
	var H := map_size.y
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed       = _rng.randi()
	noise.frequency  = 0.15
	for r in range(3, H - 3):
		for c in range(3, W - 3):
			var cell := Vector2i(c, r)
			if _grid[r][c] != Terrain.GRASS: continue
			if _objects.get_cell_source_id(cell) != -1: continue
			if _is_near_portal(c, r, 5): continue
			var v := (noise.get_noise_2d(float(c), float(r)) + 1.0) * 0.5
			if v > 0.65:
				_tall_grass.set_cell(cell, source_id, tile_tg)


## ─────────────────────────────────────────────────────────────────
## 8 — DÉCORATIONS (override de Zone1._gen_decorations)
## ─────────────────────────────────────────────────────────────────

func _gen_decorations() -> void:
	var W := map_size.x
	var H := map_size.y
	var flowers: Array[Vector2i] = [tile_fleur_rouge, tile_fleur_violette, tile_fleur_blanche]
	flowers.append_array(tiles_petites_fleurs)

	for r in range(3, H - 3):
		for c in range(3, W - 3):
			var cell := Vector2i(c, r)
			if _ground.get_cell_source_id(cell)     == -1: continue
			if _objects.get_cell_source_id(cell)    != -1: continue
			if _water.get_cell_source_id(cell)      != -1: continue
			if _tall_grass.get_cell_source_id(cell) != -1: continue
			if _grid[r][c] == Terrain.PATH:                continue
			if _is_near_portal(c, r, 4):                   continue
			var roll := _rng.randf()
			if roll < flower_density:
				_tall_grass.set_cell(cell, source_id, flowers[_rng.randi() % flowers.size()])
			elif roll < flower_density + herb_density:
				_tall_grass.set_cell(cell, source_id, tile_petite_herbe)
			elif roll < flower_density + herb_density + rock_density:
				_objects.set_cell(cell, source_id, tile_rocher)

	_gen_logs()


# Override de Zone1._gen_logs — positions aléatoires.
func _gen_logs() -> void:
	var candidates := _get_walkable_cells(6)
	candidates.shuffle()
	var placed := 0
	for pos: Vector2i in candidates:
		if placed >= 4: break
		var right := pos + Vector2i(1, 0)
		if _objects.get_cell_source_id(pos)   != -1: continue
		if _objects.get_cell_source_id(right) != -1: continue
		if _water.get_cell_source_id(pos)     != -1: continue
		_objects.set_cell(pos,   source_id, tile_rondin_g)
		_objects.set_cell(right, source_id, tile_rondin_d)
		placed += 1


## ─────────────────────────────────────────────────────────────────
## 9 — COFFRE AVEC GATING
## ─────────────────────────────────────────────────────────────────

func _place_chest_gated() -> void:
	match gating_type:
		GatingType.NONE:  _place_chest_free()
		GatingType.SURF:  _place_chest_surf()
		GatingType.COUPE: _place_chest_coupe()
		GatingType.FORCE: _place_chest_force()


func _place_chest_free() -> void:
	var candidates := _get_walkable_cells(10)
	candidates.shuffle()
	for cell: Vector2i in candidates:
		if _is_near_portal(cell.x, cell.y, 8): continue
		_objects.set_cell(cell, source_id, tile_chest_closed)
		return
	push_warning("MapGenerator: aucun emplacement pour coffre libre.")


func _place_chest_surf() -> void:
	var W := map_size.x
	var H := map_size.y
	var water_cells: Array[Vector2i] = []
	for r in range(6, H - 6):
		for c in range(6, W - 6):
			water_cells.append(Vector2i(c, r))
	water_cells.shuffle()
	for cell: Vector2i in water_cells:
		if _water.get_cell_source_id(cell) == -1: continue
		var all_water := true
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _water.get_cell_source_id(cell + d) == -1:
				all_water = false
				break
		if all_water:
			_water.erase_cell(cell)
			_ground.set_cell(cell, source_id, tile_grass)
			_objects.set_cell(cell, source_id, tile_chest_closed)
			return
	_create_water_island_chest()


func _create_water_island_chest() -> void:
	var candidates := _get_walkable_cells(12)
	candidates.shuffle()
	for center: Vector2i in candidates:
		if not _can_place_ring(center, 2): continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx == 0 and dy == 0: continue
				var cell := center + Vector2i(dx, dy)
				_water.set_cell(cell, source_id, tile_water)
				_ground.erase_cell(cell)
				_objects.erase_cell(cell)
				_tall_grass.erase_cell(cell)
				_grid[cell.y][cell.x] = Terrain.WATER
		_objects.set_cell(center, source_id, tile_chest_closed)
		return
	_place_chest_free()


func _place_chest_coupe() -> void:
	var candidates := _get_walkable_cells(10)
	candidates.shuffle()
	for center: Vector2i in candidates:
		if _is_near_portal(center.x, center.y, 8): continue
		if not _can_place_ring(center, 1): continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var cell := center + Vector2i(dx, dy)
				_objects.erase_cell(cell)
				_tall_grass.set_cell(cell, source_id, tile_bush)
		_objects.set_cell(center, source_id, tile_chest_closed)
		return
	_place_chest_free()


func _place_chest_force() -> void:
	var candidates := _get_walkable_cells(10)
	candidates.shuffle()
	for center: Vector2i in candidates:
		if _is_near_portal(center.x, center.y, 8): continue
		if not _can_place_ring(center, 1): continue
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			_objects.set_cell(center + d, source_id, tile_boulder)
		_objects.set_cell(center, source_id, tile_chest_closed)
		return
	_place_chest_free()


func _can_place_ring(center: Vector2i, radius: int) -> bool:
	var W := map_size.x
	var H := map_size.y
	for dy in range(-radius - 1, radius + 2):
		for dx in range(-radius - 1, radius + 2):
			var c := center + Vector2i(dx, dy)
			if c.x < 4 or c.x >= W - 4 or c.y < 4 or c.y >= H - 4: return false
			if _water.get_cell_source_id(c) != -1: return false
	return true


## ─────────────────────────────────────────────────────────────────
## 10 — DÉGAGEMENT DES ZONES PORTAIL
## ─────────────────────────────────────────────────────────────────

func _clear_portal_zones() -> void:
	for exit: Vector2i in [exit_A, exit_B, exit_C]:
		for dy in range(-1, 5):
			for dx in range(-3, 4):
				_clear_cell(exit + Vector2i(dx, dy))
	for dy in range(-5, 1):
		for dx in range(-3, 4):
			_clear_cell(entry_tile + Vector2i(dx, dy))


func _clear_cell(c: Vector2i) -> void:
	var W := map_size.x
	var H := map_size.y
	if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H: return
	var atlas := _objects.get_cell_atlas_coords(c)
	if atlas != Vector2i(-1, -1):
		var ox := atlas.x - tile_tree_origin.x
		var oy := atlas.y - tile_tree_origin.y
		if ox >= 0 and ox < 3 and oy >= 0 and oy < 3:
			var top_left := c - Vector2i(ox, oy)
			for dy in 3:
				for dx in 3:
					_objects.erase_cell(top_left + Vector2i(dx, dy))
		else:
			_objects.erase_cell(c)
	_tall_grass.erase_cell(c)
	_water.erase_cell(c)
	if _ground.get_cell_source_id(c) == -1:
		_ground.set_cell(c, source_id, tile_grass)


## ─────────────────────────────────────────────────────────────────
## API PUBLIQUE — ENNEMIS
## ─────────────────────────────────────────────────────────────────

func get_enemy_spawn_positions(count: int, player_pos: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var candidates := _get_walkable_cells(min_enemy_distance)
	candidates.shuffle()
	var player_cell := world_to_cell(player_pos)
	for cell: Vector2i in candidates:
		if result.size() >= count: break
		if _cell_dist(cell, entry_tile) < min_enemy_distance: continue
		if _cell_dist(cell, player_cell) < min_enemy_distance: continue
		if not is_valid_spawn_cell(cell): continue
		result.append(_ground.to_global(_ground.map_to_local(cell)))
	return result


func is_valid_spawn_cell(cell: Vector2i) -> bool:
	var W := map_size.x
	var H := map_size.y
	if cell.x < 4 or cell.x >= W - 4 or cell.y < 4 or cell.y >= H - 4: return false
	if _water.get_cell_source_id(cell)   != -1: return false
	if _objects.get_cell_source_id(cell) != -1: return false
	if _ground.get_cell_source_id(cell)  == -1: return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _objects.get_cell_source_id(cell + Vector2i(dx, dy)) != -1:
				return false
	return true


# Override de Zone1.is_valid_spawn — prend en compte la taille variable.
func is_valid_spawn(world_pos: Vector2) -> bool:
	return is_valid_spawn_cell(world_to_cell(world_pos))


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return _ground.local_to_map(_ground.to_local(world_pos))


## Override — retourne la taille réelle générée (variable).
func get_map_pixel_size() -> Vector2:
	return Vector2(map_size.x * 16, map_size.y * 16)


func get_entry_world_pos() -> Vector2:
	return _ground.to_global(_ground.map_to_local(entry_tile))


func get_exit_world_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for ex: Vector2i in [exit_A, exit_B, exit_C]:
		result.append(_ground.to_global(_ground.map_to_local(ex)))
	return result


## ─────────────────────────────────────────────────────────────────
## HAUTE HERBE — AREAS (override Zone1 — filtre sur tile_tg seulement)
## ─────────────────────────────────────────────────────────────────

func _build_tall_grass_areas() -> void:
	if not is_instance_valid(_tall_grass):
		return
	var ts := Vector2(16, 16)
	if _tall_grass.tile_set:
		ts = Vector2(_tall_grass.tile_set.tile_size)
	for cell: Vector2i in _tall_grass.get_used_cells():
		if _tall_grass.get_cell_atlas_coords(cell) != tile_tg:
			continue
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


## ─────────────────────────────────────────────────────────────────
## COLLISION (override Zone1 — tronc d'arbre uniquement)
## ─────────────────────────────────────────────────────────────────

func _build_map_collision() -> void:
	_ground.collision_enabled     = false
	_water.collision_enabled      = false
	_tall_grass.collision_enabled = false
	_objects.collision_enabled    = false

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	add_child(body)

	for cell: Vector2i in _objects.get_used_cells():
		var atlas := _objects.get_cell_atlas_coords(cell)
		if _is_decor_tile(atlas): continue
		# Arbres 3×3 : collision seulement sur la rangée du tronc (oy == 2).
		# Le feuillage (oy 0-1) n'a pas de hitbox → le joueur passe "sous" la canopée.
		var ox := atlas.x - tile_tree_origin.x
		var oy := atlas.y - tile_tree_origin.y
		if ox >= 0 and ox < 3 and oy >= 0 and oy < 3:
			if oy < 2: continue
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = _col_size(atlas)
		cs.position = _objects.map_to_local(cell)
		cs.shape    = sh
		body.add_child(cs)

	for cell: Vector2i in _water.get_used_cells():
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = Vector2(10, 10)
		cs.position = _water.map_to_local(cell)
		cs.shape    = sh
		body.add_child(cs)

	_fill_border_walls(body)


func _fill_border_walls(body: StaticBody2D) -> void:
	var W := map_size.x
	var H := map_size.y
	for wall_rect: Rect2 in [
		Rect2(-8,      -8,      W * 16 + 16, 8),
		Rect2(-8,      H * 16,  W * 16 + 16, 8),
		Rect2(-8,      -8,      8,            H * 16 + 16),
		Rect2(W * 16,  -8,      8,            H * 16 + 16),
	]:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = wall_rect.size
		cs.position = wall_rect.get_center()
		cs.shape    = sh
		body.add_child(cs)


## ─────────────────────────────────────────────────────────────────
## SHADER FLEURS
## ─────────────────────────────────────────────────────────────────

func _setup_flower_shader() -> void:
	if not is_instance_valid(_tall_grass):
		return
	var sh := Shader.new()
	sh.code = _FLOWER_SHADER
	_flower_mat = ShaderMaterial.new()
	_flower_mat.shader = sh
	_tall_grass.material = _flower_mat


## ─────────────────────────────────────────────────────────────────
## UTILITAIRES INTERNES
## ─────────────────────────────────────────────────────────────────

func _get_walkable_cells(margin: int) -> Array[Vector2i]:
	var W := map_size.x
	var H := map_size.y
	var result: Array[Vector2i] = []
	for r in range(margin, H - margin):
		for c in range(margin, W - margin):
			var cell := Vector2i(c, r)
			if _water.get_cell_source_id(cell)   != -1: continue
			if _objects.get_cell_source_id(cell) != -1: continue
			if _ground.get_cell_source_id(cell)  == -1: continue
			result.append(cell)
	return result


func _is_near_portal(c: int, r: int, radius: int) -> bool:
	var v := Vector2i(c, r)
	if _cell_dist(v, entry_tile) <= radius: return true
	for ex: Vector2i in [exit_A, exit_B, exit_C]:
		if _cell_dist(v, ex) <= radius: return true
	return false


func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# Override de Zone1._col_size
func _col_size(atlas: Vector2i) -> Vector2:
	if atlas == tile_rocher:                              return Vector2(8, 8)
	if atlas == tile_rondin_g or atlas == tile_rondin_d: return Vector2(12, 6)
	return Vector2(10, 10)


# Override de Zone1._is_decor_tile — ajoute le coffre (pas de hitbox solide)
func _is_decor_tile(a: Vector2i) -> bool:
	if a == tile_fleur_rouge or a == tile_fleur_violette or a == tile_fleur_blanche:
		return true
	if a == tile_petite_herbe or a == tile_chest_closed:
		return true
	for f: Vector2i in tiles_petites_fleurs:
		if a == f: return true
	return false
