extends Node2D

# ── Constantes RSE ──────────────────────────────────────────────────────
const TS   := 16          # taille d'une tile en pixels (RSE = 16x16)
const COLS := 80          # 1280 / 16
const ROWS := 45          # 720  / 16

# Palette exacte Ruby/Saphir Émeraude
const C_GRASS_L  := Color(0.47, 0.78, 0.28)   # herbe claire (base)
const C_GRASS_M  := Color(0.35, 0.62, 0.20)   # herbe foncée (checker)
const C_TG_L     := Color(0.27, 0.53, 0.14)   # haute herbe clair
const C_TG_D     := Color(0.19, 0.40, 0.09)   # haute herbe foncé
const C_PATH     := Color(0.82, 0.69, 0.44)   # chemin sable
const C_PATH_SH  := Color(0.68, 0.55, 0.30)   # ombre chemin
const C_PATH_LT  := Color(0.92, 0.81, 0.60)   # reflet chemin
const C_WATER    := Color(0.25, 0.56, 0.97)   # eau (frame 0)
const C_WATER_H  := Color(0.55, 0.78, 1.00)   # reflet eau
const C_WATER_D  := Color(0.14, 0.38, 0.78)   # profondeur eau
const C_TREE_BK  := Color(0.08, 0.28, 0.05)   # ombre arbre
const C_TREE_D   := Color(0.17, 0.45, 0.10)   # arbre foncé
const C_TREE_M   := Color(0.26, 0.58, 0.16)   # arbre moyen
const C_TREE_L   := Color(0.38, 0.72, 0.24)   # arbre clair
const C_TREE_H   := Color(0.55, 0.86, 0.38)   # reflet arbre
const C_TRUNK    := Color(0.46, 0.30, 0.10)   # tronc
const C_TRUNK_D  := Color(0.28, 0.18, 0.05)   # tronc foncé
const C_ROCK     := Color(0.72, 0.66, 0.50)   # rocher
const C_ROCK_H   := Color(0.90, 0.86, 0.72)   # reflet rocher
const C_ROCK_D   := Color(0.48, 0.42, 0.30)   # ombre rocher
const C_ROCK_BK  := Color(0.0,  0.0,  0.0, 0.22)

# ── Données de la map ───────────────────────────────────────────────────
# Grille de tiles (0=herbe, 1=chemin H, 2=chemin V, 3=eau, 4=arbre)
var _grid: Array = []          # ROWS × COLS

var _tall_grass_tiles: Array = []   # Array[Vector2i] en coordonnées tile
var _tree_tiles:       Array = []   # Array[Vector2i]
var _rock_tiles:       Array = []   # Array[Vector2i]

# Animation
var _water_t:    float = 0.0
var _water_frame: int  = 0
var _grass_t:    float = 0.0
var _grass_frame: int  = 0

# Collision
var _collision_built := false


func _ready() -> void:
	_build_grid()
	_build_collision()


func _process(delta: float) -> void:
	# Eau : 3 frames à ~2fps
	_water_t += delta
	var wf := int(_water_t * 2.0) % 3
	if wf != _water_frame:
		_water_frame = wf
		queue_redraw()

	# Herbe haute : 2 frames à 4fps
	_grass_t += delta
	var gf := int(_grass_t * 4.0) % 2
	if gf != _grass_frame:
		_grass_frame = gf
		queue_redraw()


# ── Construction de la grille ────────────────────────────────────────────

func _build_grid() -> void:
	# Initialise tout en herbe (0)
	_grid.resize(ROWS)
	for r in ROWS:
		var row := PackedByteArray()
		row.resize(COLS)
		row.fill(0)
		_grid[r] = row

	# Chemin horizontal : rangées 20-21 (y pixel 320-351)
	for r in range(20, 22):
		for c in COLS:
			_grid[r][c] = 1

	# Chemin vertical : colonnes 38-39
	for r in ROWS:
		for c in range(38, 40):
			if _grid[r][c] == 0:
				_grid[r][c] = 2
			else:
				_grid[r][c] = 1   # intersection

	# Eau : coin bas-droite 8×5
	for r in range(38, 43):
		for c in range(70, 78):
			_grid[r][c] = 3

	# Eau : coin haut-gauche 5×4
	for r in range(2, 6):
		for c in range(3, 8):
			_grid[r][c] = 3

	# Bordure d'arbres (2 tiles)
	for r in ROWS:
		for c in COLS:
			if r < 2 or r >= ROWS - 2 or c < 2 or c >= COLS - 2:
				_grid[r][c] = 4
				_tree_tiles.append(Vector2i(c, r))

	# Bouquets d'arbres intérieurs
	_add_tree_cluster([Vector2i(52,6), Vector2i(53,6), Vector2i(54,6),
					   Vector2i(52,7), Vector2i(53,7), Vector2i(54,7)])
	_add_tree_cluster([Vector2i(9,28), Vector2i(10,28), Vector2i(11,28),
					   Vector2i(9,29), Vector2i(10,29)])
	_add_tree_cluster([Vector2i(63,24), Vector2i(64,24), Vector2i(65,24),
					   Vector2i(63,25), Vector2i(64,25)])
	_add_tree_cluster([Vector2i(35,36), Vector2i(36,36), Vector2i(37,36),
					   Vector2i(35,37), Vector2i(36,37)])
	_add_tree_cluster([Vector2i(18,10), Vector2i(19,10), Vector2i(18,11)])
	_add_tree_cluster([Vector2i(58,33), Vector2i(59,33), Vector2i(58,34)])

	# Rochers isolés
	for pos in [Vector2i(15,14), Vector2i(16,15),
				Vector2i(56,16), Vector2i(57,17),
				Vector2i(24,30), Vector2i(25,31),
				Vector2i(68,8),  Vector2i(69,9)]:
		if _grid[pos.y][pos.x] == 0:
			_rock_tiles.append(pos)

	# Haute herbe (patches)
	_add_tall_grass_patch(6,  5,  12, 9)
	_add_tall_grass_patch(55, 3,  70, 8)
	_add_tall_grass_patch(5,  24, 18, 30)
	_add_tall_grass_patch(44, 24, 60, 30)
	_add_tall_grass_patch(20, 30, 35, 38)
	_add_tall_grass_patch(62, 30, 72, 40)


func _add_tree_cluster(tiles: Array) -> void:
	for pos: Vector2i in tiles:
		if pos.y >= 0 and pos.y < ROWS and pos.x >= 0 and pos.x < COLS:
			_grid[pos.y][pos.x] = 4
			if not _tree_tiles.has(pos):
				_tree_tiles.append(pos)


func _add_tall_grass_patch(c0: int, r0: int, c1: int, r1: int) -> void:
	for r in range(r0, r1):
		for c in range(c0, c1):
			if r >= 0 and r < ROWS and c >= 0 and c < COLS and _grid[r][c] == 0:
				_tall_grass_tiles.append(Vector2i(c, r))


# ── Collision ────────────────────────────────────────────────────────────

func _build_collision() -> void:
	if _collision_built:
		return
	_collision_built = true

	for pos: Vector2i in _tree_tiles:
		var px := pos.x * TS + TS / 2
		var py := pos.y * TS + TS / 2
		var body := StaticBody2D.new()
		var cs   := CollisionShape2D.new()
		var sh   := RectangleShape2D.new()
		sh.size      = Vector2(TS, TS)
		cs.shape     = sh
		cs.position  = Vector2(px, py)
		body.add_child(cs)
		add_child(body)

	for pos: Vector2i in _rock_tiles:
		var px := pos.x * TS + TS / 2
		var py := pos.y * TS + TS / 2
		var body := StaticBody2D.new()
		var cs   := CollisionShape2D.new()
		var sh   := CircleShape2D.new()
		sh.radius    = TS * 0.42
		cs.shape     = sh
		cs.position  = Vector2(px, py)
		body.add_child(cs)
		add_child(body)

	# Eau = collision
	for r in ROWS:
		for c in COLS:
			if _grid[r][c] == 3:
				var body := StaticBody2D.new()
				var cs   := CollisionShape2D.new()
				var sh   := RectangleShape2D.new()
				sh.size      = Vector2(TS, TS)
				cs.position  = Vector2(c * TS + TS / 2, r * TS + TS / 2)
				cs.shape     = sh
				body.add_child(cs)
				add_child(body)

	# Haute herbe = Area2D (détection rencontre)
	for pos: Vector2i in _tall_grass_tiles:
		var area := Area2D.new()
		area.name = "TG_%d_%d" % [pos.x, pos.y]
		var cs   := CollisionShape2D.new()
		var sh   := RectangleShape2D.new()
		sh.size      = Vector2(TS, TS)
		cs.position  = Vector2(pos.x * TS + TS / 2, pos.y * TS + TS / 2)
		cs.shape     = sh
		area.add_child(cs)
		area.set_collision_layer(0)
		area.set_collision_mask(2)   # masque joueur
		add_child(area)


# ── Rendu ────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Passe 1 : tuiles sol (herbe, chemin, eau)
	for r in ROWS:
		for c in COLS:
			var tile: int = _grid[r][c]
			var rx := c * TS
			var ry := r * TS
			match tile:
				0: _draw_grass(rx, ry, r, c)
				1: _draw_path(rx, ry, true)
				2: _draw_path(rx, ry, false)
				3: _draw_water(rx, ry)
				4: _draw_grass(rx, ry, r, c)  # herbe sous l'arbre

	# Passe 2 : rochers (avant arbres)
	for pos: Vector2i in _rock_tiles:
		_draw_rock(pos.x * TS, pos.y * TS)

	# Passe 3 : arbres (ordre Y pour superposition)
	for pos: Vector2i in _tree_tiles:
		_draw_tree(pos.x * TS, pos.y * TS)

	# Passe 4 : haute herbe (par-dessus le sol, mais avant joueur)
	for pos: Vector2i in _tall_grass_tiles:
		_draw_tall_grass(pos.x * TS, pos.y * TS)


# ── Dessin des tuiles ────────────────────────────────────────────────────

func _draw_grass(rx: int, ry: int, row: int, col: int) -> void:
	var dark := (row + col) % 2 == 1
	draw_rect(Rect2(rx, ry, TS, TS), C_GRASS_M if dark else C_GRASS_L)
	# Petits pixels d'herbe façon RSE
	if not dark:
		draw_rect(Rect2(rx + 3, ry + 2,  2, 3), C_GRASS_M)
		draw_rect(Rect2(rx + 9, ry + 6,  2, 3), C_GRASS_M)
		draw_rect(Rect2(rx + 6, ry + 11, 2, 3), C_GRASS_M)


func _draw_path(rx: int, ry: int, horizontal: bool) -> void:
	draw_rect(Rect2(rx, ry, TS, TS), C_PATH)
	# Granulé texture chemin
	if horizontal:
		draw_rect(Rect2(rx,      ry,      TS, 2), C_PATH_LT)
		draw_rect(Rect2(rx,      ry + 14, TS, 2), C_PATH_SH)
		draw_rect(Rect2(rx + 4,  ry + 5,  3,  2), C_PATH_SH)
		draw_rect(Rect2(rx + 11, ry + 9,  3,  2), C_PATH_SH)
	else:
		draw_rect(Rect2(rx,      ry,  2,  TS), C_PATH_LT)
		draw_rect(Rect2(rx + 14, ry,  2,  TS), C_PATH_SH)
		draw_rect(Rect2(rx + 5,  ry + 4,  2, 3), C_PATH_SH)
		draw_rect(Rect2(rx + 9,  ry + 11, 2, 3), C_PATH_SH)


func _draw_water(rx: int, ry: int) -> void:
	draw_rect(Rect2(rx, ry, TS, TS), C_WATER)
	# 3 frames d'animation : reflets horizontaux qui se décalent
	var offsets := [[3, 10], [5, 12], [1, 8]]
	var frame_offsets: Array = offsets[_water_frame]
	for yo: int in frame_offsets:
		if yo < TS:
			draw_rect(Rect2(rx + 1,  ry + yo, 6,  1), C_WATER_H)
			draw_rect(Rect2(rx + 9,  ry + yo, 5,  1), C_WATER_H)
	# Ombre profondeur bas/droite
	draw_rect(Rect2(rx,      ry + 14, TS, 2), C_WATER_D)
	draw_rect(Rect2(rx + 14, ry,      2,  TS), C_WATER_D)


func _draw_tall_grass(rx: int, ry: int) -> void:
	# Fond légèrement plus foncé
	draw_rect(Rect2(rx, ry, TS, TS), C_TG_D)
	# Brins d'herbe (2 frames : brins penchés gauche/droite)
	var lean := -1 if _grass_frame == 0 else 1
	for brin in [[2, 10], [6, 8], [10, 11], [13, 9]]:
		var bx: int = brin[0]
		var by: int = brin[1]
		# Brin bas (foncé)
		draw_rect(Rect2(rx + bx, ry + by, 2, 4), C_TG_D)
		# Brin haut (clair) avec léger lean
		draw_rect(Rect2(rx + bx + lean, ry + by - 5, 2, 5), C_TG_L)
		# Pointe du brin
		draw_rect(Rect2(rx + bx + lean, ry + by - 7, 1, 2), C_TG_L.lightened(0.2))


func _draw_tree(rx: int, ry: int) -> void:
	# Tuile 16×16 style RSE : feuillage en blocs
	# Ombre portée
	draw_rect(Rect2(rx + 2, ry + 2, TS - 2, TS - 2), C_TREE_BK)
	# Corps principal foncé
	draw_rect(Rect2(rx, ry, TS - 2, TS - 2), C_TREE_D)
	# Zone centrale plus claire
	draw_rect(Rect2(rx + 2, ry + 2, 9, 9), C_TREE_M)
	# Reflets top-left
	draw_rect(Rect2(rx + 2, ry + 2, 4, 2), C_TREE_L)
	draw_rect(Rect2(rx + 2, ry + 2, 2, 4), C_TREE_L)
	# Pixel highlight
	draw_rect(Rect2(rx + 3, ry + 3, 2, 2), C_TREE_H)
	# Tronc (bas de tuile)
	draw_rect(Rect2(rx + 5, ry + 11, 4, 3), C_TRUNK)
	draw_rect(Rect2(rx + 5, ry + 11, 1, 3), C_TRUNK_D)


func _draw_rock(rx: int, ry: int) -> void:
	# Ombre
	draw_rect(Rect2(rx + 3, ry + 3, 11, 10), C_ROCK_BK)
	# Corps
	draw_rect(Rect2(rx + 1, ry + 2, 12, 9), C_ROCK)
	draw_rect(Rect2(rx + 2, ry + 1, 10, 2), C_ROCK)
	draw_rect(Rect2(rx + 2, ry + 11, 10, 2), C_ROCK)
	# Reflet haut-gauche
	draw_rect(Rect2(rx + 2, ry + 2, 5, 2), C_ROCK_H)
	draw_rect(Rect2(rx + 2, ry + 2, 2, 4), C_ROCK_H)
	draw_rect(Rect2(rx + 3, ry + 3, 2, 2), Color.WHITE)
	# Ombre bas-droite
	draw_rect(Rect2(rx + 9,  ry + 5,  3, 5), C_ROCK_D)
	draw_rect(Rect2(rx + 5,  ry + 9,  7, 3), C_ROCK_D)
