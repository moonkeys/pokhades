@tool
class_name Zone3
extends Zone1

# Ruines — sol en terre, allées en bois, rochers épars, falaises, douves d'eau.


func _gen_ground() -> void:
	# Sol principalement en terre, bordures en herbe
	for y in H:
		for x in W:
			var border := (x < 6 or x >= W - 6 or y < 6 or y >= H - 6)
			var tile := tile_grass if border else tile_chemin_terre
			_ground.set_cell(Vector2i(x, y), source_id, tile)


func _gen_water_pools() -> void:
	# Douves à gauche — long couloir d'eau
	_fill_water(6, 8, 14, H - 8)
	# Flaque en bas à droite
	_fill_water(W - 18, H - 16, W - 6, H - 6)


func _gen_border_trees() -> void:
	var gaps: Array[Vector2i] = [entry_tile, exit_A, exit_B, exit_C]
	var step  := 3   # bordure solide — ruines enfermées
	for x in range(0, W, step):
		if not _near_gap(x, 0,     gaps): _stamp_tree(x, 0)
		if not _near_gap(x, H - 3, gaps): _stamp_tree(x, H - 3)
	for y in range(0, H, step):
		if not _near_gap(0,     y, gaps): _stamp_tree(0, y)
		if not _near_gap(W - 3, y, gaps): _stamp_tree(W - 3, y)


func _gen_inner_trees() -> void:
	# Quelques arbres isolés — les ruines ne sont plus une forêt
	for pos: Vector2i in [
		Vector2i(20, 8),  Vector2i(60, 8),
		Vector2i(20, 33), Vector2i(60, 33),
		Vector2i(38, 6),  Vector2i(38, H - 9),
	]:
		_stamp_tree(pos.x, pos.y)


func _gen_tall_grass_patches() -> void:
	# Herbe folle dans les coins des ruines
	_fill_tg(18, 8,  26, 14)
	_fill_tg(W - 26, 8, W - 18, 14)
	_fill_tg(18, H - 14, 26, H - 8)


func _gen_decorations() -> void:
	# Dalle bois : allées en croix formant des ruines de couloirs
	_fill_path_tiles(16, W - 16, H / 2 - 1, H / 2 + 2, tile_dalle_bois)   # horizontal
	_fill_path_tiles(W / 2 - 1, W / 2 + 2, 8, H - 8, tile_dalle_bois)     # vertical

	# Falaises — ligne de rochers-bordure comme vieux mur
	_fill_cliff_line(16, H / 2 - 5, 28, tile_cliff)
	_fill_cliff_line(W - 28, H / 2 - 5, W - 16, tile_cliff)
	_fill_cliff_line(16, H / 2 + 4, 28, tile_cliff)
	_fill_cliff_line(W - 28, H / 2 + 4, W - 16, tile_cliff)

	# Rochers épars dans les ruines
	var saved_rock := rock_density
	rock_density = 0.03
	var saved_flower := flower_density
	flower_density = 0.02
	super._gen_decorations()
	rock_density   = saved_rock
	flower_density = saved_flower


func _fill_path_tiles(x0: int, x1: int, y0: int, y1: int, tile: Vector2i) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell := Vector2i(x, y)
			if _objects.get_cell_source_id(cell) != -1: continue
			if _water.get_cell_source_id(cell)  != -1: continue
			_ground.set_cell(cell, source_id, tile)


func _fill_cliff_line(x0: int, y: int, x1: int, tile: Vector2i) -> void:
	for x in range(x0, x1):
		var cell := Vector2i(x, y)
		if _objects.get_cell_source_id(cell) != -1: continue
		if _water.get_cell_source_id(cell)   != -1: continue
		_objects.set_cell(cell, source_id, tile)


func _gen_logs() -> void:
	for pos: Vector2i in [Vector2i(24, 20), Vector2i(55, 20), Vector2i(40, 30)]:
		var r := Vector2i(pos.x + 1, pos.y)
		if _objects.get_cell_source_id(pos) != -1: continue
		if _water.get_cell_source_id(pos)   != -1: continue
		_objects.set_cell(pos, source_id, tile_rondin_g)
		_objects.set_cell(r,   source_id, tile_rondin_d)
