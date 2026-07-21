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

const W := 80
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
## Zone d'entraînement aux mécaniques de terrain (herbes hautes + boue) —
## à l'est de la map agrandie, reliée par la bande de chemin horizontale.
const TRAINING_ZONE := Rect2i(58, 3, 20, 10)
## Clairière plate à l'est — abritait un enclos clôturé pour les Pokémon
## débloqués, supprimé (retour joueurs : "l'enclos c'est moche, je veux qu'ils
## se baladent partout dans le hub"). Reste une zone plate pour le décor de
## camp (cf. _place_east_camp_decor) et l'un des points de déambulation des
## libérés (cf. HubWorld.FREED_ROAM_SPOTS). Démarre à z=20 (sous la bande de
## chemin z14-20) pour ne pas chevaucher.
const EAST_CLEARING := Rect2i(58, 20, 20, 12)

const _FLAT_RECTS: Array[Rect2i] = [
	Rect2i(24, 2, 8, 30),    # chemin vertical
	Rect2i(4, 14, 74, 6),    # bande de chemin horizontale — étendue jusqu'à la zone est
	Rect2i(20, 12, 16, 12),  # plaza centrale
	Rect2i(3, 21, 13, 11),   # étang + berges
	# (Stand de marché, tour et ruines retirés — leurs zones plates aussi, pour
	# que l'herbe/les arbres/le décor les remplissent.)
	Rect2i(28, 23, 12, 7),   # tournesols + barrières
	Rect2i(15, 21, 5, 4),    # feu de camp ouest
	Rect2i(37, 22, 5, 4),    # feu de camp est
	Rect2i(47, 25, 5, 5),    # grand arbre "hero"
	TRAINING_ZONE,           # zone d'entraînement (herbes hautes + boue)
	EAST_CLEARING,           # clairière est (ex-enclos des Pokémon libérés)
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
	# Tour et ruines (sprites 2D du tileset) retirées — retour joueurs.
	_place_stone_dallage()   # dalles de pierre à quelques endroits (plaza, abords)
	_place_tents()
	_place_campfires()
	_place_sunflower_fences()
	_scatter_tall_grass()   # bouquets de haute herbe pixel-art (cf. GrassPatch)
	_place_training_zone()
	_place_east_camp_decor()
	# Statue centrale retirée (retour joueurs : "la statue moche au centre").
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
	noise.domain_warp_enabled  = true
	noise.domain_warp_amplitude = 18.0
	noise.domain_warp_frequency = HEIGHT_NOISE_FREQ * 0.6

	# Calque "macro" très basse fréquence — mêmes principes que
	# MapGenerator._compute_height_field() : porte les grandes formes du
	# relief (une colline, un creux) sous le détail fin du calque principal.
	var macro := FastNoiseLite.new()
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro.seed        = HEIGHT_SEED + 1
	macro.frequency   = HEIGHT_NOISE_FREQ * 0.28
	macro.fractal_octaves = 1

	var field: Array = []
	field.resize(H)
	for r in H:
		var row := PackedFloat32Array()
		row.resize(W)
		for c in W:
			if _is_flat_cell(c, r):
				row[c] = 0.0
				continue
			var detail := noise.get_noise_2d(float(c), float(r))
			var macro_h := macro.get_noise_2d(float(c), float(r))
			row[c] = (macro_h * 0.65 + detail * 0.35) * HEIGHT_AMPLITUDE
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
	# Sol saturé/assombri + "peint" (bruit organique) — même rendu que les maps
	# de run améliorées, pour casser l'aspect dalle uniforme.
	mesh_inst.material_override = GrassPatch.ground_material(
		load(NATURE_DIR + "grass.png"), 1.45, 0.88, 1.0, Color.WHITE, 0.0, 1.0)
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
	_scatter_kit_pool(rng, KitProps.MUSHROOMS,   14, 1.7, 2.3, false)   # + de champignons
	_scatter_kit_pool(rng, KitProps.STUMPS,       5, 4.0, 5.0, true)
	_scatter_kit_pool(rng, KitProps.LOGS,         7, 7.0, 8.5, true)   # rondins-bancs (échelle lisible)
	_scatter_kit_pool(rng, KitProps.GRASS_SMALL, 60, 1.0, 1.7, false)   # touffes basses (couvre-sol)
	_scatter_kit_pool(rng, KitProps.BUSHES,      16, 1.1, 1.7, false)   # buissons variés


## Zones PAVÉES : dalles de pierre carrées (une par case, léger joint + teinte
## variée) sur la plaza et devant quelques PNJ — un vrai sol dallé plutôt que
## de la terre battue.
func _place_stone_dallage() -> void:
	_dallage_patch(Vector2i(23, 13), Vector2i(33, 23))   # plaza centrale
	_dallage_patch(Vector2i(6, 12),  Vector2i(11, 16))   # devant la Boutique (ouest)
	_dallage_patch(Vector2i(44, 12), Vector2i(48, 16))   # devant les Améliorations (est)


## Un plan carrelé avec la MÊME tuile de chemin de pierre que le biome Village
## (tileset, cf. MapGenerator.tile_chemin_pierre_orig), bords dissous dans
## l'herbe par le shader de bruit — plus les vilaines boîtes grises.
const ATLAS_STONE_FLOOR := Vector2i(46, 15)   # = MapGenerator.tile_chemin_pierre_orig

func _dallage_patch(a: Vector2i, b: Vector2i) -> void:
	var w := float(b.x - a.x)
	var h := float(b.y - a.y)
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	mesh_inst.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _get_path_dissolve_shader()
	mat.set_shader_parameter("tex", Billboard3D.crop_tile(TILESET_PATH, ATLAS_STONE_FLOOR, 1, 1))
	mat.set_shader_parameter("tiles", Vector2(w, h))          # 1 dalle par unité
	mat.set_shader_parameter("half_size", Vector2(w * 0.5, h * 0.5))
	mesh_inst.material_override = mat
	# Au-dessus du chemin de terre (0,045) pour le recouvrir sans z-fight.
	mesh_inst.position = Vector3(float(a.x) + w * 0.5, 0.06, float(a.y) + h * 0.5)
	add_child(mesh_inst)


## Bouquets de HAUTE HERBE pixel-art (mêmes touffes que les biomes de run, cf.
## GrassPatch.build_tufts) — semés en petits amas hors chemins/eau/structures,
## deux MultiMesh (pleines / à cœur creux) pour la variété. Purement décoratif.
func _scatter_tall_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	var full: Array = []
	var hollow: Array = []
	for _cluster in 30:
		var cc := Vector2i(rng.randi_range(3, W - 4), rng.randi_range(3, H - 4))
		if _in_no_flower_zone(cc) or _water_cells.has(cc):
			continue
		for _blade in rng.randi_range(3, 7):
			var cell := cc + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			if cell.x < 2 or cell.x >= W - 2 or cell.y < 2 or cell.y >= H - 2:
				continue
			if _in_no_flower_zone(cell) or _water_cells.has(cell):
				continue
			var px := float(cell.x) + rng.randf_range(0.2, 0.8)
			var pz := float(cell.y) + rng.randf_range(0.2, 0.8)
			var y := get_height_at_world(Vector3(px, 0, pz))
			var xf := Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.35)),
				Vector3(px, y, pz))
			if rng.randf() < 0.3:
				hollow.append(xf)
			else:
				full.append(xf)
	var tint := Color(0.95, 1.08, 0.85)
	if not full.is_empty():
		add_child(GrassPatch.build_tufts(full, tint, false))
	if not hollow.is_empty():
		add_child(GrassPatch.build_tufts(hollow, tint, true))


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

	_build_pond_collision()
	_draw_pond_edges_and_banks()


## L'étang BLOQUE le passage (bug : on marchait dessus). Le hub n'a pas de CS
## Surf, donc une collision pleine sur la couche des obstacles suffit.
func _build_pond_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "PondCollision"
	body.collision_layer = 1     # même couche que les autres obstacles du hub
	body.collision_mask  = 0
	add_child(body)
	for cell: Vector2i in _water_cells:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 1.2, 1.0)
		cs.shape = box
		cs.position = Vector3(float(cell.x) + 0.5, 0.6, float(cell.y) + 0.5)
		body.add_child(cs)


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
	var w := float(x1 - x0)
	var h := float(y1 - y0)
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	mesh_inst.mesh = plane
	# Bords DISSOUS dans l'herbe par un bruit (le chemin flotte au-dessus du
	# sol, cf. y=0.045) — jointure organique façon biomes de run, plus de bord
	# rectangulaire net (retour joueurs).
	var mat := ShaderMaterial.new()
	mat.shader = _get_path_dissolve_shader()
	mat.set_shader_parameter("tex", load(NATURE_DIR + "path.png"))
	mat.set_shader_parameter("tiles", Vector2(w, h))
	mat.set_shader_parameter("half_size", Vector2(w * 0.5, h * 0.5))
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(float(x0 + x1) * 0.5, 0.045, float(y0 + y1) * 0.5)
	add_child(mesh_inst)


static var _path_shader: Shader = null

const _PATH_DISSOLVE_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, repeat_enable, filter_nearest;
uniform vec2 tiles = vec2(1.0);
uniform vec2 half_size = vec2(1.0);
uniform float feather = 1.6;   // largeur de la frange dissoute (unités monde)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1,0)), c = hash(i + vec2(0,1)), d = hash(i + vec2(1,1));
	vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
void fragment() {
	ALBEDO = texture(tex, UV * tiles).rgb;
	ROUGHNESS = 1.0;
	// Distance au bord le plus proche (en unités monde).
	vec2 p = (UV - 0.5) * (half_size * 2.0);
	float edge = min(half_size.x - abs(p.x), half_size.y - abs(p.y));
	// Frange déchiquetée : le seuil de fondu est perturbé par du bruit.
	float n = noise(UV * tiles * 1.5) - 0.5;
	ALPHA = clamp(smoothstep(0.0, feather, edge + n * feather * 1.1), 0.0, 1.0);
}
"""

func _get_path_dissolve_shader() -> Shader:
	if _path_shader == null:
		_path_shader = Shader.new()
		_path_shader.code = _PATH_DISSOLVE_SHADER
	return _path_shader


# ── Forêts organiques (bordure + bosquets intérieurs) ─────────────────────

var _tree_rng := RandomNumberGenerator.new()

## Bordure de forêt sur une ELLIPSE BRUITÉE plutôt que sur le rectangle de la
## map — le hub se lit comme une clairière ronde (pas un cercle parfait : le
## rayon ondule) et les COINS sont comblés d'arbres (retour joueurs : "je
## voudrais que la map soit un peu plus en forme de cercle").
func _draw_border_trees() -> void:
	var cx := float(W) * 0.5
	var cz := float(H) * 0.5
	var rx := cx - 1.0
	var rz := cz - 1.0
	var wobble := FastNoiseLite.new()
	wobble.seed = 4321
	wobble.frequency = 0.9

	# 1) Lisière : deux anneaux d'arbres sur l'ellipse, rayon ondulé.
	for ring in 2:
		var n := 92 - ring * 10
		for i in n:
			var ang := (TAU / float(n)) * i + _tree_rng.randf_range(-0.02, 0.02)
			var k := 1.0 + wobble.get_noise_1d(ang * 3.0) * 0.06 - ring * 0.055
			var p := Vector2(cx + cos(ang) * rx * k, cz + sin(ang) * rz * k)
			_try_spawn_forest_tree(p)

	# 2) Coins : tout ce qui tombe HORS de l'ellipse est bouché par la forêt.
	for r in range(1, H - 1):
		for c in range(1, W - 1):
			var dx := (float(c) + 0.5 - cx) / rx
			var dz := (float(r) + 0.5 - cz) / rz
			if dx * dx + dz * dz <= 1.0:
				continue   # dans la clairière
			if _tree_rng.randf() < 0.55:
				_try_spawn_forest_tree(Vector2(float(c) + _tree_rng.randf_range(0.1, 0.9),
					float(r) + _tree_rng.randf_range(0.1, 0.9)))


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


## Shader procédural de flamme — remplace l'ancien quad "texture floue teintée
## par le dégradé de particules" (retour joueurs : flammes pas assez belles).
## Silhouette effilée (large à la base, pointue en haut) qui ondule dans le
## temps (deux sinusoïdes déphasées sur les bords) + fondu au sommet — donne
## une languette de feu vivante par particule, sans texture ni asset externe.
static var _fire_mat_cache: ShaderMaterial = null

static func _fire_shader_material() -> ShaderMaterial:
	if _fire_mat_cache != null:
		return _fire_mat_cache
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// 'billboard' n'est pas supporté par le renderer GL Compatibility (utilisé
// par ce projet) — billboard manuel, même recette que BILLBOARD_ENABLED.
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 7.0;
	float wobble = sin(uv.y * 16.0 + t) * 0.035 + sin(uv.y * 6.0 - t * 1.6) * 0.06;
	float dx = abs(uv.x - 0.5 + wobble);
	float taper = mix(0.46, 0.03, pow(uv.y, 0.85));
	float edge = smoothstep(taper, taper * 0.25, dx);
	float top_fade = smoothstep(1.0, 0.5, uv.y);
	float base_glow = smoothstep(0.0, 0.25, uv.y) * (1.0 - smoothstep(0.0, 0.12, uv.y) * 0.4);
	ALBEDO = COLOR.rgb;
	ALPHA = edge * top_fade * base_glow * COLOR.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_fire_mat_cache = mat
	return mat


# ── Feux de camp (mesh Kenney + flamme émissive + lumière vacillante) ────

func _place_campfires() -> void:
	_place_campfire(Vector3(17.5, 0, 22.5), 0)
	_place_campfire(Vector3(39.5, 0, 23.5), 1)
	_place_campfire(Vector3(28.0, 0, 8.5),  0)   # feu supplémentaire, haut du hub


## Feu en particules : une gerbe de flammes qui montent et rétrécissent
## (dégradé jaune→orange→rouge, mélange additif) + de fines braises qui
## s'envolent. Rendu vivant, contrairement au cône émissif d'avant.
func _build_flame() -> Node3D:
	var root := Node3D.new()

	# ── Flammes ──
	var flame := GPUParticles3D.new()
	flame.amount   = 30
	flame.lifetime = 0.75
	flame.preprocess = 1.0
	flame.local_coords = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.38            # base plus large, flammes bien posées sur le foyer
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 16.0
	pm.gravity = Vector3(0, 0.7, 0)               # monte moins haut, reste bas et large
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.55
	pm.scale_min = 0.7
	pm.scale_max = 1.15
	var scurve := Curve.new()                     # grossit puis s'éteint
	scurve.add_point(Vector2(0.0, 0.5))
	scurve.add_point(Vector2(0.25, 1.0))
	scurve.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = scurve
	pm.scale_curve = sct
	var grad := Gradient.new()                    # jaune vif → orange → rouge fondu
	grad.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	grad.add_point(0.35, Color(1.0, 0.6, 0.15, 0.95))
	grad.set_color(1, Color(0.75, 0.12, 0.04, 0.0))
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pm.color_ramp = gtex
	flame.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.48)   # plus large que haut — silhouette basse et large
	quad.material = _fire_shader_material()
	flame.draw_pass_1 = quad
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)

	# ── Braises (fines étincelles qui montent plus haut) ──
	var ember := GPUParticles3D.new()
	ember.amount   = 14
	ember.lifetime = 1.6
	ember.preprocess = 1.0
	ember.local_coords = true
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.22
	em.direction = Vector3(0, 1, 0)
	em.spread = 22.0
	em.gravity = Vector3(0, 0.9, 0)
	em.initial_velocity_min = 0.6
	em.initial_velocity_max = 1.3
	em.scale_min = 0.10
	em.scale_max = 0.20
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	eg.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = eg
	em.color_ramp = egt
	ember.process_material = em
	var eq := QuadMesh.new()
	eq.size = Vector2(0.16, 0.16)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.albedo_texture   = CombatVFX._get_soft_texture()
	ember_mat.billboard_mode   = BaseMaterial3D.BILLBOARD_PARTICLES
	ember_mat.blend_mode       = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	ember_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	eq.material = ember_mat       # petites étincelles rondes, matériau simple
	ember.draw_pass_1 = eq
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ember)

	return root


func _place_campfire(pos: Vector3, variant: int) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	# campfire_stones : foyer de pierres, à une échelle LISIBLE (retour joueurs :
	# les feux étaient minuscules à 2.2).
	var fire := KitProps.instance("campfire_stones.glb")
	fire.scale = Vector3.ONE * 6.0
	root.add_child(fire)

	# VRAIES flammes en particules (montantes, colorées, + braises) au lieu
	# d'un cône (retour joueurs).
	var flame := _build_flame()
	flame.position = Vector3(0, 0.18, 0)   # posé au ras des bûches, plus flottant au-dessus
	flame.scale = Vector3.ONE * 0.8
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


## Zone d'entraînement : herbe haute dense (visuel) + une bande de boue
## (TerrainEffectZone, cf. scripts/world/TerrainEffectZone.gd) qui ralentit
## réellement le joueur — pour tester les mécaniques de terrain hors combat.
func _place_training_zone() -> void:
	var rect := TRAINING_ZONE
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415

	# Herbes hautes concentrées sur la moitié nord de la zone — même recette
	# que le biome Prairie (MapRender3D._build_pixel_grass) : touffes
	# "buissonneuses" (build_tufts) + couche de REMPLISSAGE plus dense
	# (build), sinon le rendu reste trop clairsemé par rapport aux run maps
	# (retour joueurs : "pas retrouvé les hautes herbes de la prairie").
	var grass_tint := Color(0.95, 1.08, 0.85)
	var full: Array = []
	var filler: Array = []
	for _i in 260:
		var px := rng.randf_range(float(rect.position.x) + 1.0, float(rect.end.x) - 1.0)
		var pz := rng.randf_range(float(rect.position.y) + 1.0, float(rect.position.y) + rect.size.y * 0.55)
		var y := get_height_at_world(Vector3(px, 0, pz))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			.scaled(Vector3.ONE * rng.randf_range(0.9, 1.35)), Vector3(px, y, pz))
		if rng.randf() < 0.55:
			full.append(xf)
		else:
			filler.append(xf)
	if not full.is_empty():
		add_child(GrassPatch.build_tufts(full, grass_tint, false))
	if not filler.is_empty():
		add_child(GrassPatch.build(filler, grass_tint))

	# Bande de boue sur la moitié sud — ralentit le joueur (cf. HubPlayer._speed_mult).
	var mud_w := float(rect.size.x) - 4.0
	var mud_d := rect.size.y * 0.32
	var mud_center := Vector3(
		float(rect.position.x) + rect.size.x * 0.5, 0.0,
		float(rect.position.y) + rect.size.y * 0.72)

	var zone := TerrainEffectZone.new()
	zone.speed_multiplier = 0.4   # net à ressentir (0.5 passait trop inaperçu)
	zone.collision_layer = 8   # layer dédié (n'interfère pas avec murs/ennemis)
	zone.collision_mask  = 1   # détecte les corps sur le layer par défaut (joueur)
	zone.position = mud_center + Vector3(0, 0.3, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(mud_w, 1.4, mud_d)   # plus haut que la capsule joueur : pas de trou de détection sur relief
	cs.shape = box
	zone.add_child(cs)
	add_child(zone)

	# Vrai sol boueux (même tuile pixel-art que le biome Marécage,
	# MapGenerator.tile_sol_boueux, passée par le même shader de sol que le
	# reste du hub) — au lieu d'un aplat de couleur (retour joueurs : "je
	# devrais avoir le sol boueux des marécages").
	var mud_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(mud_w, mud_d)
	mud_mesh.mesh = plane
	var mud_tex := Billboard3D.crop_tile(TILESET_PATH, Vector2i(23, 16), 1, 1)
	mud_mesh.material_override = GrassPatch.ground_material(mud_tex, 1.45, 0.82, mud_w * 0.5)
	mud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mud_mesh.position = mud_center + Vector3(0, -0.03, 0)
	add_child(mud_mesh)

	# Quelques rondins en bordure — repère visuel de "parcours d'essai".
	for lp: Vector3 in [
		Vector3(float(rect.position.x) + 1.5, 0, float(rect.position.y) + 1.5),
		Vector3(float(rect.end.x) - 1.5, 0, float(rect.position.y) + 1.5),
	]:
		var log_prop := KitProps.instance(KitProps.LOGS[0])
		log_prop.position = lp
		add_child(log_prop)


## Kit "mini-dungeon" (tonneaux, bannière, coffre) — pour habiller l'entrée
## des nouvelles zones à l'est en ambiance "campement de ralliement" plutôt
## que prairie nue.
const MINI_DUNGEON_DIR := "res://assets/kenney_mini-dungeon/Models/GLB format/"

## Décor de camp au carrefour des deux zones à l'est (chemin z14-20, x~55-58) :
## un feu + une tente pour signaler le "camp d'entraînement", bannière et
## tonneaux pour marquer l'entrée de la clairière.
func _place_east_camp_decor() -> void:
	_place_campfire(Vector3(56.0, 0, 16.0), 1)

	var tent := KitProps.instance_textured(NATURE_FULL_DIR, "tent_smallOpen.glb")
	tent.scale = Vector3.ONE * 2.8
	tent.position = Vector3(59.0, 0, 17.5)
	tent.rotation.y = deg_to_rad(-90.0)
	add_child(tent)
	_add_box_collision(tent.position, Vector3(2.0, 1.4, 2.0))

	var banner := KitProps.instance_textured(MINI_DUNGEON_DIR, "banner.glb")
	banner.scale = Vector3.ONE * 1.6
	banner.position = Vector3(float(EAST_CLEARING.position.x) + EAST_CLEARING.size.x * 0.5, 0, float(EAST_CLEARING.position.y) - 1.0)
	add_child(banner)

	for bp: Vector3 in [
		Vector3(float(EAST_CLEARING.position.x) - 1.5, 0, float(EAST_CLEARING.position.y) + 1.5),
		Vector3(float(EAST_CLEARING.position.x) - 1.5, 0, float(EAST_CLEARING.position.y) + 3.5),
	]:
		var barrel := KitProps.instance_textured(MINI_DUNGEON_DIR, "barrel.glb")
		barrel.scale = Vector3.ONE * 1.4
		barrel.position = bp
		add_child(barrel)
		_add_box_collision(bp, Vector3(0.8, 1.0, 0.8))


## Assets du kit COMPLET (pas dans le dossier plat de KitProps) — tentes et
## barrières demandées. Chargés par chemin, matériaux d'origine conservés.
const NATURE_FULL_DIR := "res://assets/kenney_nature-kit/Models/GLTF format/"


## Campement : deux tentes près du feu du haut — donne de la vie au hub.
func _place_tents() -> void:
	var t1 := KitProps.instance_textured(NATURE_FULL_DIR, "tent_detailedOpen.glb")
	t1.scale = Vector3.ONE * 3.2
	t1.position = Vector3(24.5, 0, 8.0)
	t1.rotation.y = deg_to_rad(20.0)
	add_child(t1)
	_add_box_collision(t1.position, Vector3(2.4, 1.6, 2.4))

	var t2 := KitProps.instance_textured(NATURE_FULL_DIR, "tent_detailedClosed.glb")
	t2.scale = Vector3.ONE * 3.2
	t2.position = Vector3(31.5, 0, 8.5)
	t2.rotation.y = deg_to_rad(-35.0)
	add_child(t2)
	_add_box_collision(t2.position, Vector3(2.4, 1.6, 2.4))


func _add_box_collision(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos + Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	add_child(body)


func _place_fence(pos: Vector3, rot_y_deg: float) -> void:
	# Barrières demandées (kit complet) : planches doubles, plus lisibles que
	# l'ancienne fence_simpleLow minuscule.
	var fence := KitProps.instance_textured(NATURE_FULL_DIR, "fence_planksDouble.glb")
	fence.scale = Vector3.ONE * 2.4
	fence.position = pos
	fence.rotation.y = deg_to_rad(rot_y_deg)
	add_child(fence)
	return


func _place_fence_old(pos: Vector3, rot_y_deg: float) -> void:
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
