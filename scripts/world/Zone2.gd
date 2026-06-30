@tool
class_name Zone2
extends Zone1

# Forêt dense — deux massifs boisés, rivière à gauche, corridor central.


func _gen_ground() -> void:
	for y in H:
		for x in W:
			_ground.set_cell(Vector2i(x, y), source_id, tile_grass)


func _gen_water_pools() -> void:
	# Deux petits lacs dans les corridors dégagés (pas dans les clusters d'arbres)
	_fill_water(26, 17, 34, 24)       # couloir central gauche
	_fill_water(W - 34, 17, W - 26, 24) # couloir central droit


func _gen_border_trees() -> void:
	# Bordure solide identique à Zone1 — la forêt dense est à l'intérieur
	var gaps: Array[Vector2i] = [entry_tile, exit_A, exit_B, exit_C]
	var step  := 3
	for x in range(0, W, step):
		if not _near_gap(x, 0,     gaps): _stamp_tree(x, 0)
		if not _near_gap(x, H - 3, gaps): _stamp_tree(x, H - 3)
	for y in range(0, H, step):
		if not _near_gap(0,     y, gaps): _stamp_tree(0, y)
		if not _near_gap(W - 3, y, gaps): _stamp_tree(W - 3, y)


func _gen_inner_trees() -> void:
	# Forêt gauche (entre rivière et couloir)
	_fill_trees(14, 5, 26, 20)
	_fill_trees(14, 28, 26, H - 7)
	# Forêt droite
	_fill_trees(W - 26, 5, W - 8, 20)
	_fill_trees(W - 26, 28, W - 8, H - 7)
	# Îlot central haut
	_fill_trees(34, 5, 46, 13)
	# Îlot central bas
	_fill_trees(34, H - 14, 46, H - 7)
	# Arbres isolés dans le couloir pour briser la ligne de vue
	for pos in [Vector2i(28, 18), Vector2i(51, 18), Vector2i(28, 26), Vector2i(51, 26)]:
		_stamp_tree(pos.x, pos.y)


func _gen_tall_grass_patches() -> void:
	# Herbe dense aux intersections du couloir
	_fill_tg(27, 14, 33, 20)
	_fill_tg(27, 26, 33, 32)
	_fill_tg(47, 14, 53, 20)
	_fill_tg(47, 26, 53, 32)
	_fill_tg(34, 18, 46, 28)   # centre


func _gen_decorations() -> void:
	# Plus de fleurs et de végétation qu'en Zone1
	var saved_flower_density := flower_density
	var saved_herb_density   := herb_density
	flower_density = 0.10
	herb_density   = 0.04
	super._gen_decorations()
	flower_density = saved_flower_density
	herb_density   = saved_herb_density


func _gen_logs() -> void:
	# Rondins abondants dans la forêt — paires horizontales
	var log_positions: Array[Vector2i] = [
		Vector2i(20, 8),  Vector2i(55, 8),
		Vector2i(20, 32), Vector2i(55, 32),
		Vector2i(36, 14), Vector2i(36, 32),
		Vector2i(29, 22), Vector2i(50, 22),
		Vector2i(40, 20),
	]
	for pos: Vector2i in log_positions:
		var r := Vector2i(pos.x + 1, pos.y)
		if pos.x + 1 >= W - 6: continue
		if _objects.get_cell_source_id(pos) != -1: continue
		if _water.get_cell_source_id(pos) != -1: continue
		_objects.set_cell(pos, source_id, tile_rondin_g)
		_objects.set_cell(r,   source_id, tile_rondin_d)
	for pos: Vector2i in [Vector2i(30, 10), Vector2i(49, 10), Vector2i(30, 35), Vector2i(49, 35)]:
		if _objects.get_cell_source_id(pos) != -1: continue
		if _water.get_cell_source_id(pos) != -1: continue
		_objects.set_cell(pos, source_id, tile_petit_tronc)
