class_name MapRender3D
extends Node3D

## Couche de RENDU HD-2D des maps de combat procédurales (phase 2).
##
## MapGenerator continue de générer dans ses TileMapLayers — ils deviennent un
## pur modèle de données (cachés à l'exécution) et ce nœud les lit pour
## construire la scène 3D, sans toucher à la logique de génération :
##   - sol : Ground + Water (+ décors plats comme les nénuphars) bakés en une
##     texture posée sur un PlaneMesh — préserve à l'identique les jointures
##     de boue du marécage, les chemins de pierre… ;
##   - herbe/fleurs : vrais meshes du pack Kenney Nature Kit (CC0), dressés
##     au sol avec ondulation de vent, groupés en MultiMeshInstance3D par
##     variante pour un coût quasi constant même sur les zones denses ;
##   - arbres/rochers/gros cailloux : vrais meshes du pack Kenney (props
##     individuels — comptages modestes, pas besoin de MultiMesh) ;
##   - relief : falaises en VRAIS blocs empilés du pack Kenney (dessus herbe
##     / flancs roche déjà sur le modèle, reteintés par thème), regroupés en
##     MultiMeshInstance3D par palier de hauteur — coût quasi constant même
##     pour les longs murs de l'arène de grotte ;
##   - décors restants (souches, rondins, champignons, arbre mort…) :
##     billboards via Billboard3D, comme dans le Hub ;
##   - collisions 3D : obstacles couche 1, eau couche 4 (CS Surf), murs de
##     bordure.
## 1 unité monde = 1 tuile de 16 px, comme le Hub.

const TILESET_PATH := "res://assets/tilesets/tileset pokemon.png"
const TILE_PX          := 16
const OBSTACLE_HEIGHT  := 1.2
const BORDER_WALL_H    := 3.0

## ─────────────────────────────────────────────────────────────────
## PACK D'ASSETS GRATUIT (Kenney Nature Kit, CC0) — arbres et rochers en
## vrais meshes low-poly, à la place des primitives procédurales/billboards.
## cf. assets/kenney_nature_kit/License.txt pour la licence (CC0, domaine
## public, aucune attribution requise). Les fichiers/pools/stylisation
## communs vivent dans KitProps.gd, partagé avec HubMap (même style visuel
## sur tout le jeu, une seule copie de la logique de préparation des meshes).
## ─────────────────────────────────────────────────────────────────
const KIT_TREE_TARGET_HEIGHT := 4.2   # ≈2.4× la hauteur des sprites (TeamMember.DISPLAY_UNITS=1.75)
const KIT_ROCK_LARGE_SCALE   := 2.1   # ≈ footprint 2×2 cases (tailles natives ~0.8-1.1)
const KIT_ROCK_SMALL_SCALE   := 1.7   # ≈ décor 1 case (tailles natives ~0.35-0.6)

# Pas de type dur sur la map (MapGenerator ↔ MapRender3D se référencent).
var _map: Node2D = null

var _prop_by_cell:      Dictionary = {}   # case → Node3D (partagé pour les props multi-cases)
var _collision_by_cell: Dictionary = {}   # case → CollisionShape3D (obstacles retirables : CS Coupe/Force)

var _obstacle_body: StaticBody3D = null


## Point d'entrée — appelé par MapGenerator après génération (hors éditeur).
func build(map: Node2D) -> void:
	_map = map
	_bake_ground_plane()
	_build_water_surface()
	_build_water_edges()
	_build_bridge()
	_build_cliff_formations()
	_build_props()
	_build_grass()
	_build_pixel_grass()
	_build_flowers()
	_build_leaf_litter()
	_build_swamp_flora()
	_build_berry_trees()
	if _map.theme == MapGenerator.MapTheme.VILLAGE:
		_build_village_houses()
	if _map.arena_mode:
		# Village : on est entré par une PORTE → intérieur de MAISON, pas une
		# grotte (cf. MapGenerator.interior_style / CombatArena._load_cave).
		if str(_map.get("interior_style")) == "house":
			_build_house_interior()
		else:
			_build_cave_kit_arena()
			_build_cave_crystals()
			_build_cave_decor()
	_build_collisions()
	_build_border_walls()


## MAISONS du biome Village (cf. MapGenerator._place_houses) — bâtiments
## procéduraux : murs (BoxMesh crépi), toit à deux pentes (PrismMesh tuile),
## porte + fenêtres sombres en façade sud (côté caméra), collision pleine.
## Pas d'asset de maison dans les packs → construction à la main, style
## cohérent avec les portes de sortie (ExitPortal).
const _HOUSE_WALLS: Array = [
	Color(0.90, 0.86, 0.74), Color(0.86, 0.80, 0.68), Color(0.82, 0.78, 0.72),
	Color(0.78, 0.72, 0.60),
]
const _HOUSE_ROOFS: Array = [
	Color(0.60, 0.24, 0.20), Color(0.42, 0.34, 0.28),
	Color(0.34, 0.40, 0.52), Color(0.50, 0.44, 0.30),
]

func _build_village_houses() -> void:
	for rect: Rect2i in _map.get_village_houses():
		_build_house(rect)


func _build_house(rect: Rect2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rect.position) + 47
	var w := float(rect.size.x)
	var d := float(rect.size.y)
	var cx := float(rect.position.x) + w * 0.5
	var cz := float(rect.position.y) + d * 0.5
	var wall_h := rng.randf_range(2.2, 3.2)
	# Marge pour que le bâtiment ne déborde pas sur la rue (emprise - 0.3).
	w -= 0.4
	d -= 0.4

	var wall_col: Color = _HOUSE_WALLS[rng.randi() % _HOUSE_WALLS.size()]
	var trim_col := Color(0.96, 0.93, 0.86)   # encadrements crème

	var house := Node3D.new()
	house.position = Vector3(cx, 0.0, cz)
	add_child(house)

	# Soubassement : plinthe de pierre un peu plus large, sombre.
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(w + 0.18, 0.32, d + 0.18)
	base.mesh = bb
	base.position = Vector3(0, 0.16, 0)
	base.material_override = _flat_mat(Color(0.42, 0.38, 0.34))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	house.add_child(base)

	# Murs
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(w, wall_h, d)
	wall.mesh = wb
	wall.position = Vector3(0, wall_h * 0.5 + 0.2, 0)
	wall.material_override = _flat_mat(wall_col)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	house.add_child(wall)

	# Bandeau sous toiture (corniche) — fine bordure claire en haut des murs.
	var cornice := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(w + 0.14, 0.16, d + 0.14)
	cornice.mesh = cb
	cornice.position = Vector3(0, wall_h + 0.12, 0)
	cornice.material_override = _flat_mat(trim_col.darkened(0.1))
	house.add_child(cornice)

	# Toit à deux pentes (prisme) — faîte le long de X, débord de toiture.
	var roof_h := rng.randf_range(1.0, 1.6)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.6, roof_h, d + 0.6)
	roof.mesh = pm
	roof.position = Vector3(0, wall_h + 0.2 + roof_h * 0.5, 0)
	roof.material_override = _flat_mat(_HOUSE_ROOFS[rng.randi() % _HOUSE_ROOFS.size()])
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	house.add_child(roof)

	# Cheminée (petit conduit + couronne sombre) sur un côté du toit.
	var chim := MeshInstance3D.new()
	var chb := BoxMesh.new()
	chb.size = Vector3(0.4, roof_h + 0.6, 0.4)
	chim.mesh = chb
	chim.position = Vector3(w * 0.3, wall_h + 0.2 + roof_h * 0.6, d * 0.15)
	chim.material_override = _flat_mat(Color(0.52, 0.34, 0.28))
	chim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	house.add_child(chim)
	_house_quad(house, Vector3(w * 0.3, wall_h + 0.2 + roof_h * 1.1, d * 0.15 + 0.21), Vector2(0.46, 0.14), Color(0.14, 0.11, 0.10))

	# Façade sud (+Z) : porte encadrée + deux fenêtres encadrées à volets.
	var face_z := d * 0.5 + 0.02
	var door_base := 0.2
	# Porte : encadrement crème + battant sombre.
	_house_quad(house, Vector3(0, door_base + 0.62, face_z), Vector2(0.86, 1.30), trim_col)
	_house_quad(house, Vector3(0, door_base + 0.60, face_z + 0.02), Vector2(0.66, 1.14), Color(0.34, 0.20, 0.12))
	_house_quad(house, Vector3(0.18, door_base + 0.58, face_z + 0.03), Vector2(0.07, 0.07), Color(0.90, 0.80, 0.35))  # poignée
	# Fenêtres.
	for sx: float in [-1.0, 1.0]:
		var wxp: float = sx * w * 0.28
		var wyp: float = wall_h * 0.62 + 0.2
		_house_quad(house, Vector3(wxp, wyp, face_z), Vector2(0.64, 0.64), trim_col)                    # cadre
		_house_quad(house, Vector3(wxp, wyp, face_z + 0.02), Vector2(0.46, 0.46), Color(0.40, 0.54, 0.62))  # vitre
		# Croisillon (deux fines barres claires).
		_house_quad(house, Vector3(wxp, wyp, face_z + 0.03), Vector2(0.46, 0.05), trim_col)
		_house_quad(house, Vector3(wxp, wyp, face_z + 0.03), Vector2(0.05, 0.46), trim_col)

	# Collision pleine (emprise), layer 1 comme les autres obstacles.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, OBSTACLE_HEIGHT, d)
	cs.shape = box
	cs.position = Vector3(0, OBSTACLE_HEIGHT * 0.5, 0)
	body.add_child(cs)
	house.add_child(body)


func _house_quad(parent: Node3D, pos: Vector3, size: Vector2, col: Color) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	q.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(q)


func _flat_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color  = col
	m.roughness     = 0.95
	m.diffuse_mode  = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## INTÉRIEUR DE MAISON (biome Village) — on entre par une porte, on ne doit pas
## se retrouver dans une caverne. Plancher de lattes, murs plâtrés à plinthe,
## tapis central et mobilier simple (table, caisses, tonneaux). Les
## blocs-falaises de l'anneau restent derrière pour la collision, retintés en
## mur intérieur.
func _build_house_interior() -> void:
	var sz: Vector2i = _map.get_map_cell_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sz) + 8081

	var wood_a := Color(0.55, 0.38, 0.24)
	var wood_b := Color(0.48, 0.33, 0.21)

	# Plancher : lattes alternées sur tout l'intérieur (l'anneau de murs occupe
	# 2 cases). Un quad par latte, alterné pour lire le sens du parquet.
	for cz in range(2, sz.y - 2):
		var plank := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(float(sz.x - 4), 0.06, 0.92)
		plank.mesh = pm
		plank.position = Vector3(float(sz.x) * 0.5, 0.03, float(cz) + 0.5)
		plank.material_override = _flat_mat(wood_a if cz % 2 == 0 else wood_b)
		plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(plank)

	# Murs intérieurs : plâtre clair + plinthe bois, sur les 4 côtés.
	var plaster := _flat_mat(Color(0.88, 0.83, 0.72))
	var skirt   := _flat_mat(Color(0.42, 0.30, 0.20))
	var lo := 2.0
	var hx := float(sz.x) - 2.0
	var hz := float(sz.y) - 2.0
	for side in [
		{"pos": Vector3(float(sz.x) * 0.5, 0.0, lo), "size": Vector3(float(sz.x) - 4.0, 1.0, 0.25)},
		{"pos": Vector3(float(sz.x) * 0.5, 0.0, hz), "size": Vector3(float(sz.x) - 4.0, 1.0, 0.25)},
		{"pos": Vector3(lo, 0.0, float(sz.y) * 0.5), "size": Vector3(0.25, 1.0, float(sz.y) - 4.0)},
		{"pos": Vector3(hx, 0.0, float(sz.y) * 0.5), "size": Vector3(0.25, 1.0, float(sz.y) - 4.0)},
	]:
		var sv: Vector3 = side["size"]
		var pv: Vector3 = side["pos"]
		# Pan de mur
		var wall := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(sv.x, 3.2, sv.z)
		wall.mesh = wm
		wall.position = pv + Vector3(0, 1.6, 0)
		wall.material_override = plaster
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(wall)
		# Plinthe
		var sk := MeshInstance3D.new()
		var skm := BoxMesh.new()
		skm.size = Vector3(sv.x + 0.06, 0.28, sv.z + 0.06)
		sk.mesh = skm
		sk.position = pv + Vector3(0, 0.14, 0)
		sk.material_override = skirt
		add_child(sk)

	# Tapis central
	var rug := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(float(sz.x) * 0.42, 0.02, float(sz.y) * 0.42)
	rug.mesh = rm
	rug.position = Vector3(float(sz.x) * 0.5, 0.08, float(sz.y) * 0.5)
	rug.material_override = _flat_mat(Color(0.58, 0.24, 0.24))
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rug)

	# Mobilier : caisses/tonneaux le long des murs (bloquant déjà via l'anneau).
	var placed := 0
	var attempts := 0
	while placed < 10 and attempts < 200:
		attempts += 1
		var cell := Vector2i(rng.randi_range(4, sz.x - 5), rng.randi_range(4, sz.y - 5))
		if not _map.is_valid_spawn_cell(cell):
			continue
		var crate := MeshInstance3D.new()
		var cm := BoxMesh.new()
		var h := rng.randf_range(0.55, 0.9)
		cm.size = Vector3(rng.randf_range(0.6, 0.9), h, rng.randf_range(0.6, 0.9))
		crate.mesh = cm
		crate.position = Vector3(cell.x + 0.5, h * 0.5 + 0.06, cell.y + 0.5)
		crate.rotation.y = rng.randf() * TAU
		crate.material_override = _flat_mat(
			Color(0.62, 0.45, 0.28) if rng.randf() < 0.6 else Color(0.45, 0.35, 0.28))
		crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(crate)
		placed += 1


## Habillage de l'arène de grotte avec les modules texturés du cave-kit
## (Kenney Modular Cave Kit) — grille native de 4 unités : dalles de sol sur
## tout l'intérieur + panneaux muraux sur le pourtour intérieur, face tournée
## vers le centre. Les blocs-falaises existants sont CONSERVÉS derrière (ils
## portent la collision + bouchent les rares interstices de coin, la grille
## de 4 u ne tombant pas juste sur les 32×22 tuiles de l'arène). Remplace le
## rendu "cubes d'herbe rocheuse" peu convaincant (retour joueurs : grottes
## pas belles). NOTE : échelle native (1 module = 4 u), transforms à vérifier
## à l'œil dans l'éditeur.
func _build_cave_kit_arena() -> void:
	var sz: Vector2i = _map.get_map_cell_size()

	# Sol : dalles 4×4 pas de 4, posées juste au-dessus du sol baké (arène
	# plate à y=0). Le débord des bords se glisse sous les murs.
	for cx in range(4, sz.x, 4):
		for cz in range(4, sz.y, 4):
			var floor_t := KitProps.instance_textured(KitProps.CAVE_KIT_DIR, KitProps.CAVE_FLOOR)
			floor_t.position = Vector3(float(cx), 0.03, float(cz))
			add_child(floor_t)

	# Murs : pourtour intérieur (l'anneau de blocs occupe 2 cases). Face du
	# panneau (native +Z) tournée vers l'intérieur, corps vers l'extérieur.
	var lo := 2                 # bord intérieur de l'anneau
	var hi_x := sz.x - 2
	var hi_z := sz.y - 2
	for cx in range(4, hi_x, 4):
		_place_cave_wall(float(cx), float(lo),   0.0)      # mur nord  → face +Z
		_place_cave_wall(float(cx), float(hi_z), PI)       # mur sud   → face -Z
	for cz in range(4, hi_z, 4):
		_place_cave_wall(float(lo),   float(cz), PI * 0.5)  # mur ouest → face +X
		_place_cave_wall(float(hi_x), float(cz), -PI * 0.5) # mur est   → face -X


func _place_cave_wall(x: float, z: float, rot_y: float) -> void:
	var w := KitProps.instance_textured(KitProps.CAVE_KIT_DIR, KitProps.CAVE_WALL)
	w.position   = Vector3(x, 0.0, z)
	w.rotation.y = rot_y
	add_child(w)


## Décor de grotte (remplace l'herbe/fleurs retirées) : grappes de champignons
## (touche de vie/lumière) + quelques petits rochers gris, semés sur des cases
## marchables. Les cristaux lumineux (_build_cave_crystals) complètent l'ambiance.
func _build_cave_decor() -> void:
	var sz: Vector2i = _map.get_map_cell_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sz) + 321
	var placed := 0
	var attempts := 0
	while placed < 16 and attempts < 320:
		attempts += 1
		var cell := Vector2i(rng.randi_range(4, sz.x - 5), rng.randi_range(4, sz.y - 5))
		if not _map.is_valid_spawn_cell(cell):
			continue
		if rng.randf() < 0.6:
			var f: String = KitProps.MUSHROOMS[rng.randi() % KitProps.MUSHROOMS.size()]
			var m := KitProps.instance(f)
			m.scale = Vector3.ONE * rng.randf_range(1.6, 2.8)
			m.rotation.y = rng.randf() * TAU
			m.position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
			add_child(m)
		else:
			_add_kit_rock_small(cell)
		placed += 1


## Grappes de cristaux lumineux (arène de grotte uniquement) — spikes
## émissifs bleu/violet dispersés sur le sol, + un léger halo : donne une
## atmosphère de caverne façon donjon plutôt qu'une salle de blocs nue.
func _build_cave_crystals() -> void:
	var sz: Vector2i = _map.get_map_cell_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sz) + 555
	var cols: Array[Color] = [
		Color(0.35, 0.55, 1.0), Color(0.60, 0.40, 1.0), Color(0.30, 0.85, 0.90),
	]
	var placed := 0
	var attempts := 0
	while placed < 12 and attempts < 200:
		attempts += 1
		var cell := Vector2i(rng.randi_range(4, sz.x - 5), rng.randi_range(4, sz.y - 5))
		if not _map.is_valid_spawn_cell(cell):
			continue
		var col: Color = cols[rng.randi() % cols.size()]
		var cluster := Node3D.new()
		cluster.position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
		add_child(cluster)
		for i in rng.randi_range(2, 4):
			var mi := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius    = 0.0
			cone.bottom_radius = rng.randf_range(0.10, 0.18)
			cone.height        = rng.randf_range(0.5, 1.1)
			mi.mesh = cone
			var off := Vector3(rng.randf_range(-0.3, 0.3), cone.height * 0.5, rng.randf_range(-0.3, 0.3))
			mi.position = off
			mi.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf(), rng.randf_range(-0.2, 0.2))
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 0.8
			mat.roughness = 0.2
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cluster.add_child(mi)
		# Halo lumineux discret sur ~1 grappe sur 2 (coût maîtrisé)
		if rng.randf() < 0.5:
			var light := OmniLight3D.new()
			light.light_color  = col
			light.light_energy = 0.7
			light.omni_range   = 3.5
			light.position.y   = 0.6
			cluster.add_child(light)
		placed += 1


## Arbres à baies (BerryTree) dispersés sur des cases marchables des biomes
## végétaux — cassables à l'attaque, ils lâchent des Baies (cf. BerryTree /
## BerryPickup). Rocailleux exclu (pas de végétation). Placés après les
## collisions d'obstacles pour ne pas gêner le pathfinding des cases libres.
func _build_berry_trees() -> void:
	if _map.theme == MapGenerator.MapTheme.ROCKY or _map.theme == MapGenerator.MapTheme.VOLCANO:
		return   # rocailleux / volcan : pas de végétation à baies
	var sz: Vector2i = _map.get_map_cell_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sz) * 7 + 13
	var target := rng.randi_range(4, 8)
	var berries: Array = _berries_for_theme(_map.theme)
	# Cases du pont (lac) à éviter — un arbre bloquant y barrerait le passage.
	var bridge: Dictionary = {}
	if _map.has_method("get_bridge_cells"):
		for bc: Vector2i in _map.get_bridge_cells():
			bridge[bc] = true
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 25:
		attempts += 1
		var cell := Vector2i(rng.randi_range(6, sz.x - 7), rng.randi_range(6, sz.y - 7))
		if not _map.is_valid_spawn_cell(cell):
			continue
		if bridge.has(cell):
			continue
		var berry: String = berries[rng.randi() % berries.size()]
		var tree := BerryTree.new()
		tree.position = _map.cell_to_world3(cell)
		add_child(tree)
		# Taille UNIFORME (pas de variation aléatoire) — tous identiques.
		tree.setup(1.0, hash(cell),
			_BERRY_TREE_DIR % berry, _BERRY_ITEM_DIR % berry)
		placed += 1


# Baies Essentials par biome — liste CENTRALISÉE dans PokePools.gd.
const _BERRY_TREE_DIR := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/berrytree_%s.png"
const _BERRY_ITEM_DIR := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Items/%s.png"

## Liste des baies (noms Essentials) plausibles pour le biome.
func _berries_for_theme(theme: int) -> Array:
	return PokePools.BERRIES_BY_THEME.get(theme, ["CHERIBERRY", "ORANBERRY"])


# ─────────────────────────────────────────────────────────────────
# SOL — bake des couches 2D en une texture plaquée au sol
# ─────────────────────────────────────────────────────────────────

func _bake_ground_plane() -> void:
	var sz: Vector2i = _map.get_map_cell_size()
	var img := Image.create(sz.x * TILE_PX, sz.y * TILE_PX, false, Image.FORMAT_RGBA8)
	var src := Billboard3D.get_tileset_image(TILESET_PATH)
	if src == null:
		push_error("MapRender3D: tileset introuvable (%s)" % TILESET_PATH)
		return

	_bake_layer(img, src, _map._ground, false, sz)
	_bake_layer(img, src, _map._water, true, sz)
	# Sol COMPOSITE : repeint les cases d'herbe en mélangeant les variantes du
	# biome. À faire AVANT _blend_terrain_edges, qui recompose ensuite les
	# frontières herbe/chemin/eau par-dessus.
	_bake_ground_variants(img, src, sz)
	# Transitions ORGANIQUES entre types de sol (herbe/chemin/eau) — retour
	# joueurs : bords de tuiles "coupés au couteau". Appliqué APRÈS sol+eau
	# mais AVANT les décors, qui doivent rester nets par-dessus.
	_blend_terrain_edges(img, src, sz)
	_bake_tall_grass_flat(img, src, sz)
	_bake_flat_decors(img, src, sz)
	_map.ground_avg_color = _average_color(img)
	_map.path_avg_color   = _path_average_color(img, sz)
	# DEBUG (-- dump_ground) : écrit la texture de sol bakée dans
	# user://ground_dump.png — le seul moyen de juger le sol composite et les
	# transitions sans lancer le jeu en fenêtré.
	if OS.get_cmdline_user_args().has("dump_ground"):
		img.save_png("user://ground_dump.png")
		print("MapRender3D: sol baké écrit (thème=%s, palette=%s)" % [
			MapGenerator.MapTheme.keys()[_map.theme], _map._ground_tiles])

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GroundPlane"
	mesh_inst.mesh = _build_heightfield_mesh(sz)

	# Sol SATURÉ/assombri via shader (cf. GrassPatch.ground_material) — la
	# texture bakée sortait trop claire et délavée par rapport aux sprites.
	# Mode "peint" (retour joueurs : décor trop "dalle plate") — validé sur
	# Prairie/Forêt, désormais étendu à TOUS les biomes. Volcan : sol de cendre
	# recoloré sombre (tint + strength) — la tuile de base resterait trop claire.
	var g_tint := Color.WHITE
	var g_ts   := 0.0
	if _map.theme == MapGenerator.MapTheme.VOLCANO:
		g_tint = Color(0.34, 0.20, 0.18)
		g_ts   = 0.80
	mesh_inst.material_override = GrassPatch.ground_material(
		ImageTexture.create_from_image(img), 1.45, 0.88, 1.0, g_tint, g_ts, 1.0)
	# Ombre portée ACTIVE : c'est elle qui donne son relief au sol (les collines
	# du heightfield s'ombrent elles-mêmes ; sans ça le terrain se lit plat).
	#
	# Elle a un temps été coupée parce qu'elle dessinait une bande sombre
	# RECTANGULAIRE tout autour de la zone. La cause réelle n'était pas l'ombre
	# mais la marche de 1,2 u sous la dalle : le tablier de plaine était un plan
	# géant glissé DESSOUS. Depuis qu'il est un anneau affleurant à y=-0.02 (cf.
	# BiomeAmbiance._build_ground_apron), la dalle n'a plus de vide à ombrer et
	# le cadre a disparu — on peut rendre le relief sans le rectangle.
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_inst)


## Couleur moyenne d'une image, pondérée par l'alpha — les cases sans tuile
## sont transparentes et tireraient la moyenne vers le noir si on les comptait.
## Passe par une réduction 24×24 : moyenner les millions de pixels du bake à la
## main coûterait une seconde à chaque génération, pour le même résultat.
## Couleur moyenne des seules cases de CHEMIN, échantillonnée au centre de
## chacune sur le bake. Sert au sentier de terre prolongé hors de la map (cf.
## BiomeAmbiance._build_exit_trails) : il doit être exactement de la couleur du
## chemin jouable pour se lire comme SON prolongement, pas comme un décor à
## côté. Mesurée et non codée en dur — les variantes de tuile de chemin
## changent d'un biome à l'autre (terre, pierre…).
func _path_average_color(img: Image, sz: Vector2i) -> Color:
	var acc := Vector3.ZERO
	var n := 0
	for r in sz.y:
		for c in sz.x:
			if _map._grid[r][c] != MapGenerator.Terrain.PATH:
				continue
			var px: Color = img.get_pixel(c * TILE_PX + TILE_PX / 2, r * TILE_PX + TILE_PX / 2)
			if px.a < 0.5:
				continue
			acc += Vector3(px.r, px.g, px.b)
			n += 1
	if n == 0:
		return _map.ground_avg_color   # arène/map sans chemin : pas de sentier à teinter
	acc /= float(n)
	return Color(acc.x, acc.y, acc.z)


func _average_color(img: Image) -> Color:
	var small := img.duplicate()
	small.resize(24, 24, Image.INTERPOLATE_BILINEAR)
	var acc := Vector3.ZERO
	var wsum := 0.0
	for y in 24:
		for x in 24:
			var px: Color = small.get_pixel(x, y)
			acc  += Vector3(px.r, px.g, px.b) * px.a
			wsum += px.a
	if wsum <= 0.001:
		return Color(0.42, 0.64, 0.32)
	acc /= wsum
	return Color(acc.x, acc.y, acc.z)


## Grille de sommets (W+1)×(H+1) déplacés verticalement selon le relief
## procédural (MapGenerator._height_grid, collines douces) — remplace le
## PlaneMesh plat d'origine. UV alignées 1:1 sur la texture de sol bakée
## (même mapping qu'un simple plan de taille W×H aurait donné).
func _build_heightfield_mesh(sz: Vector2i) -> ArrayMesh:
	var W := sz.x
	var H := sz.y

	# Hauteur par coin de case = moyenne des cases adjacentes — donne une
	# grille de sommets qui raccorde proprement les cases entre elles.
	var corner_h: Array = []
	corner_h.resize(H + 1)
	for cy in range(H + 1):
		var row := PackedFloat32Array()
		row.resize(W + 1)
		for cx in range(W + 1):
			row[cx] = _corner_height(cx, cy, W, H)
		corner_h[cy] = row

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cy in H:
		for cx in W:
			var h00: float = corner_h[cy][cx]
			var h10: float = corner_h[cy][cx + 1]
			var h01: float = corner_h[cy + 1][cx]
			var h11: float = corner_h[cy + 1][cx + 1]

			var p00 := Vector3(cx,     h00, cy)
			var p10 := Vector3(cx + 1, h10, cy)
			var p01 := Vector3(cx,     h01, cy + 1)
			var p11 := Vector3(cx + 1, h11, cy + 1)

			var u0 := float(cx) / float(W)
			var u1 := float(cx + 1) / float(W)
			var v0 := float(cy) / float(H)
			var v1 := float(cy + 1) / float(H)

			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)

	st.generate_normals()
	return st.commit()


func _corner_height(cx: int, cy: int, W: int, H: int) -> float:
	var sum := 0.0
	var count := 0
	for cell: Vector2i in [Vector2i(cx - 1, cy - 1), Vector2i(cx, cy - 1), Vector2i(cx - 1, cy), Vector2i(cx, cy)]:
		if cell.x < 0 or cell.x >= W or cell.y < 0 or cell.y >= H:
			continue
		sum += _map.get_height_at_cell(cell)
		count += 1
	return sum / float(count) if count > 0 else 0.0


# ─────────────────────────────────────────────────────────────────
# EAU 3D — surface animée par-dessus le fond baké (le pack Kenney n'a que
# des tuiles de rivière directionnelles, pas de mare/lac). Construction et
# shader partagés avec l'étang du Hub : cf. WaterSurface.gd (maillage
# subdivisé, houle visible, écume animée sur le contour des rives).
# ─────────────────────────────────────────────────────────────────

const WATER_SURFACE_Y := 0.06   # au-dessus du sol baké (visible en transparence = "fond du lac")


## Pont du biome Lac : planches de bois posées au-dessus de l'eau le long des
## cases de pont (MapGenerator.get_bridge_cells), avec de petits poteaux —
## passage vers l'île centrale.
func _build_bridge() -> void:
	if not _map.has_method("get_bridge_cells"):
		return
	var cells: Array = _map.get_bridge_cells()
	if cells.is_empty():
		return
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.52, 0.36, 0.20)
	deck_mat.roughness = 0.9
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.40, 0.27, 0.15)
	post_mat.roughness = 0.9

	for cell: Vector2i in cells:
		var base := Vector3(cell.x + 0.5, WATER_SURFACE_Y + 0.06, cell.y + 0.5)
		var deck := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(1.02, 0.10, 1.02)
		deck.mesh = db
		deck.position = base
		deck.material_override = deck_mat
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(deck)
		for sx in [-0.46, 0.46]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.08, 0.42, 0.08)
			post.mesh = pb
			post.position = base + Vector3(sx, 0.24, 0)
			post.material_override = post_mat
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(post)


func _build_water_surface() -> void:
	if not is_instance_valid(_map._water):
		return
	var cells: Array = _map._water.get_used_cells()
	if cells.is_empty():
		return
	var colors := _water_colors_for_theme()
	# Volcan : la "surface d'eau" est de la LAVE — émissive (glow) et haute.
	var emission := 1.6 if _map.theme == MapGenerator.MapTheme.VOLCANO else 0.0
	var mi := WaterSurface.build(cells, colors["shallow"], colors["deep"],
		colors.get("foam", Color(0.93, 0.97, 0.95)), emission)
	mi.position = Vector3(0, WATER_SURFACE_Y, 0)
	add_child(mi)


## Teintes eau (peu profond/profond/écume) par thème — cohérent avec les
## teintes de brouillard/ambiance déjà utilisées par BiomeAmbiance.
func _water_colors_for_theme() -> Dictionary:
	match _map.theme:
		MapGenerator.MapTheme.SWAMP:
			# Écume verdâtre — pas de blanc éclatant dans la vase. Alphas BAS :
			# ces flaques sont MARCHABLES, on doit voir le fond au travers pour
			# les lire comme des flaques (retour joueurs), pas comme un lac.
			return {"shallow": Color(0.42, 0.46, 0.30, 0.48), "deep": Color(0.20, 0.26, 0.18, 0.62),
				"foam": Color(0.62, 0.68, 0.48)}
		MapGenerator.MapTheme.ROCKY:
			return {"shallow": Color(0.30, 0.58, 0.62, 0.70), "deep": Color(0.12, 0.30, 0.38, 0.86)}
		MapGenerator.MapTheme.MEADOW:
			return {"shallow": Color(0.35, 0.68, 0.72, 0.68), "deep": Color(0.14, 0.36, 0.46, 0.85)}
		MapGenerator.MapTheme.AUTUMN:
			# Reflets ambrés — l'eau renvoie la lumière dorée du ciel d'automne
			return {"shallow": Color(0.46, 0.56, 0.48, 0.68), "deep": Color(0.20, 0.30, 0.28, 0.86),
				"foam": Color(0.90, 0.88, 0.72)}
		MapGenerator.MapTheme.LAKE:
			# Grand lac : eau claire et bleue, écume blanche franche
			return {"shallow": Color(0.34, 0.72, 0.86, 0.66), "deep": Color(0.10, 0.34, 0.56, 0.88),
				"foam": Color(0.95, 0.98, 1.00)}
		MapGenerator.MapTheme.VOLCANO:
			# LAVE : rouge-orange incandescent, "écume" = croûte jaune vif sur
			# les veines. Opaque (on ne voit pas au travers). Émission ajoutée
			# dans _build_water_surface.
			return {"shallow": Color(1.0, 0.55, 0.12, 0.98), "deep": Color(0.75, 0.16, 0.05, 1.0),
				"foam": Color(1.0, 0.90, 0.35)}
		_:  # FOREST
			return {"shallow": Color(0.28, 0.58, 0.60, 0.42), "deep": Color(0.12, 0.32, 0.40, 0.58)}


## Jonctions terre/eau : une frange d'herbe (edge_grass.png, déjà utilisée
## pour l'étang du Hub) sur chaque bord terre→eau du contour des mares —
## les mares sont des blobs de bruit, pas des rectangles, donc on détecte le
## contour case par case (4-voisinage) plutôt que de supposer une forme
## rectangulaire comme HubMap._ring_edge_overlay. Adoucit la coupure entre
## la texture d'herbe bakée et la surface d'eau 3D.
const WATER_EDGE_FILE := "res://assets/nature/edge_grass.png"
const _WATER_EDGE_DIRS := [
	{"delta": Vector2i(0, -1), "off": Vector3(0.5, 0.0, 0.0), "rot": 0.0},
	{"delta": Vector2i(0, 1),  "off": Vector3(0.5, 0.0, 1.0), "rot": 180.0},
	{"delta": Vector2i(-1, 0), "off": Vector3(0.0, 0.0, 0.5), "rot": 90.0},
	{"delta": Vector2i(1, 0),  "off": Vector3(1.0, 0.0, 0.5), "rot": -90.0},
]

func _build_water_edges() -> void:
	if not is_instance_valid(_map._water):
		return
	# Volcan : pas de frange d'herbe verte autour de la lave (le bord est déjà
	# fondu en cendre sombre par _blend_terrain_edges).
	if _map.theme == MapGenerator.MapTheme.VOLCANO:
		return
	var tex: Texture2D = load(WATER_EDGE_FILE)
	if tex == null:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture  = tex
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	mat.roughness        = 1.0

	for cell: Vector2i in _map._water.get_used_cells():
		for d: Dictionary in _WATER_EDGE_DIRS:
			var neighbor: Vector2i = cell + d["delta"]
			if _map._water.get_cell_source_id(neighbor) != -1:
				continue   # bord entre deux cases d'eau — pas de frange
			_place_water_edge(Vector3(cell.x, WATER_SURFACE_Y, cell.y) + (d["off"] as Vector3), d["rot"], mat)


func _place_water_edge(pos: Vector3, rot_y_deg: float, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	mi.mesh = plane
	mi.position = pos
	mi.rotation_degrees = Vector3(-90, rot_y_deg, 0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Transitions ORGANIQUES herbe↔chemin et herbe↔eau : au lieu de flouter la
## texture (qui donnait un bord net juste adouci), on RECOMPOSE chaque pixel
## des cases de bordure en choisissant entre la tuile d'herbe et la tuile de
## l'autre matériau, via un seuil BRUITÉ sur un champ de présence lissé
## (bilinéaire entre centres de cases). Résultat : la frontière serpente/se
## déchiquette au lieu de suivre les arêtes carrées de la grille. Utilise les
## tuiles existantes (aucun asset requis). L'intérieur des zones homogènes
## n'est pas touché — seule la bande de bordure (rayon 2) est recomposée.
# Deux octaves : une GRANDE longueur d'onde (méandres larges — casse les
# longs segments qui restaient droits) + une fine (jitter/déchiquetage local).
const _EDGE_NOISE_FREQ_LOW  := 0.035  # méandres larges
const _EDGE_NOISE_FREQ_HI   := 0.16   # jitter fin
const _EDGE_AMP_LOW  := 0.38
const _EDGE_AMP_HI   := 0.22
# Largeur de la bande où les COULEURS se fondent (dans l'espace du champ) —
# au-delà d'un simple choix binaire net, un petit dégradé herbe↔sol.
const _EDGE_COLOR_BAND := 0.20

## ── SOL COMPOSITE ────────────────────────────────────────────────────────
## Chaque biome déclare une PALETTE de sols (cf. MapGenerator._ground_tiles) au
## lieu d'une tuile unique. On les fond PAR PIXEL selon un bruit basse fréquence :
## de larges plaques d'herbe dense, d'herbe sèche, de sable… qui se fondent les
## unes dans les autres.
##
## Par pixel et non par case : un tirage par case redonnerait des frontières
## alignées sur la grille — exactement le défaut « damier » qu'on cherche à
## éviter. Une 2e octave, plus fine, déchiquette la jointure pour qu'elle ne se
## lise pas comme un dégradé mou.
## Modèle : un sol de BASE (pal[0]) recouvert, pour chaque variante, d'un masque
## de plaques tiré de son propre bruit. Chaque variante a donc son seuil et sa
## propre répartition, indépendante des autres.
##
## Une première version répartissait les variantes le long d'UN seul bruit
## (position continue dans la palette) : le simplex ne dépassant guère ±0.6, la
## variante du MILIEU couvrait tout et la base n'apparaissait qu'aux extrêmes —
## l'inverse du but. Avec des masques, "base + plaques" est explicite.
const _VAR_NOISE_FREQ := 0.008   # plaques larges (≈ 8 cases)
const _VAR_NOISE_FREQ_HI := 0.06 # 2e octave : déchiquette le contour des plaques
const _VAR_AMP_HI := 0.30
## Seuil d'apparition d'une plaque et largeur de son fondu. Seuil haut = plaques
## rares et franches ; bande étroite = contour net plutôt que dégradé mou.
const _VAR_TH   := 0.19
const _VAR_BAND := 0.13

var _var_noise: Array = []      # Array[FastNoiseLite] — un par variante (k ≥ 1)
var _var_noise_hi: FastNoiseLite = null


func _bake_ground_variants(img: Image, src: Image, sz: Vector2i) -> void:
	if _map._ground_tiles.size() < 2:
		return   # sol uni : rien à mélanger
	var grid: Array = _map._grid
	for r in sz.y:
		var row: PackedByteArray = grid[r]
		for c in sz.x:
			# Seul le SOL est composite : les chemins et l'eau ont leurs propres
			# tuiles, et leurs bords sont gérés par _blend_terrain_edges.
			var t: int = row[c]
			if t == MapGenerator.Terrain.PATH or t == MapGenerator.Terrain.WATER:
				continue
			for py in TILE_PX:
				for px in TILE_PX:
					img.set_pixel(c * TILE_PX + px, r * TILE_PX + py,
						_ground_color_at(src, c * TILE_PX + px, r * TILE_PX + py, px, py))


## Couleur du sol composite pour le pixel (gx,gy) de la texture bakée, (px,py)
## étant sa position DANS sa tuile. Sert aussi à _blend_terrain_edges : sans
## ça, les bords de chemin/eau seraient recomposés sur le sol de BASE et les
## plaques de variantes s'y interrompraient net.
func _ground_color_at(src: Image, gx: int, gy: int, px: int, py: int) -> Color:
	var pal: Array = _map._ground_tiles
	if pal.size() < 2:
		var a: Vector2i = _map._ground_tile
		return src.get_pixel(a.x * TILE_PX + px, a.y * TILE_PX + py)

	if _var_noise.is_empty():
		# Graine de la MAP (pas de la taille) : deux zones de mêmes dimensions
		# doivent avoir des plaques différentes. Déterministe → identique sur
		# tous les pairs en multijoueur.
		for k in pal.size():
			var nz := FastNoiseLite.new()
			nz.frequency = _VAR_NOISE_FREQ
			nz.seed = _map.map_seed ^ (0x5A17 + k * 0x9E37)   # décorrélées entre variantes
			_var_noise.append(nz)
		_var_noise_hi = FastNoiseLite.new()
		_var_noise_hi.frequency = _VAR_NOISE_FREQ_HI
		_var_noise_hi.seed = _map.map_seed ^ 0x2B93

	var base: Vector2i = pal[0]
	var col: Color = src.get_pixel(base.x * TILE_PX + px, base.y * TILE_PX + py)
	var jitter := _var_noise_hi.get_noise_2d(float(gx), float(gy)) * _VAR_AMP_HI
	for k in range(1, pal.size()):
		var n: float = (_var_noise[k] as FastNoiseLite).get_noise_2d(float(gx), float(gy)) + jitter
		var w := smoothstep(_VAR_TH, _VAR_TH + _VAR_BAND, n)
		if w <= 0.0:
			continue
		var a: Vector2i = pal[k]
		col = col.lerp(src.get_pixel(a.x * TILE_PX + px, a.y * TILE_PX + py), w)
	return col


func _blend_terrain_edges(img: Image, src: Image, sz: Vector2i) -> void:
	var grid: Array = _map._grid
	var noise_lo := FastNoiseLite.new()
	noise_lo.frequency = _EDGE_NOISE_FREQ_LOW
	noise_lo.seed = hash(sz) ^ 0x1234
	var noise_hi := FastNoiseLite.new()
	noise_hi.frequency = _EDGE_NOISE_FREQ_HI
	noise_hi.seed = hash(sz) ^ 0x7ABC

	for r in range(1, sz.y - 1):
		var row: PackedByteArray = grid[r]
		for c in range(1, sz.x - 1):
			var t: int = row[c]
			if t == MapGenerator.Terrain.TREE:
				continue
			# Matériau "autre" présent dans le voisinage (rayon 2) : eau
			# prioritaire (rives), sinon chemin. Rien → case interne, on saute.
			var other := _dominant_other(grid, sz, c, r)
			if other == -1:
				continue
			var other_atlas: Vector2i = _atlas_for_terrain(other, c, r)

			var x0 := c * TILE_PX
			var y0 := r * TILE_PX
			for py in TILE_PX:
				for px in TILE_PX:
					# Coordonnée en espace-cases du pixel, recentrée sur les
					# centres de cases pour le champ bilinéaire.
					var fx := float(c) + (float(px) + 0.5) / float(TILE_PX) - 0.5
					var fy := float(r) + (float(py) + 0.5) / float(TILE_PX) - 0.5
					var field := _terrain_field(grid, sz, fx, fy, other)
					var n := noise_lo.get_noise_2d(float(x0 + px), float(y0 + py)) * _EDGE_AMP_LOW \
						+ noise_hi.get_noise_2d(float(x0 + px), float(y0 + py)) * _EDGE_AMP_HI
					var w := field + n
					# Bande de mélange de COULEUR autour du seuil (pas un choix
					# binaire) : petit dégradé herbe↔sol qui adoucit la jointure.
					var blend := smoothstep(0.5 - _EDGE_COLOR_BAND, 0.5 + _EDGE_COLOR_BAND, w)
					# Sol composite (cf. _ground_color_at) et non la tuile de base :
					# sinon les plaques de variantes s'arrêteraient net le long
					# des chemins et des rives, en liseré de sol d'origine.
					var col_grass: Color = _ground_color_at(src, x0 + px, y0 + py, px, py)
					var col_other: Color = src.get_pixel(
						other_atlas.x * TILE_PX + px, other_atlas.y * TILE_PX + py)
					img.set_pixel(x0 + px, y0 + py, col_grass.lerp(col_other, blend))


## Matériau non-herbe dominant autour de (c,r) dans un rayon de 2 cases —
## WATER prioritaire (rives), sinon PATH, sinon -1 (case interne à ignorer).
func _dominant_other(grid: Array, sz: Vector2i, c: int, r: int) -> int:
	var has_water := false
	var has_path  := false
	var self_t: int = grid[r][c]
	for dy in range(-2, 3):
		var ry := r + dy
		if ry < 0 or ry >= sz.y: continue
		for dx in range(-2, 3):
			var rx := c + dx
			if rx < 0 or rx >= sz.x: continue
			var nt: int = grid[ry][rx]
			if nt == MapGenerator.Terrain.WATER: has_water = true
			elif nt == MapGenerator.Terrain.PATH: has_path = true
	# Il faut une VRAIE frontière : la case courante + un voisin diffèrent.
	if has_water and self_t != MapGenerator.Terrain.WATER:
		return MapGenerator.Terrain.WATER
	if has_path and self_t != MapGenerator.Terrain.PATH:
		return MapGenerator.Terrain.PATH
	# Case de chemin/eau elle-même en bordure d'herbe → traite aussi ce sens.
	if self_t == MapGenerator.Terrain.PATH:
		return MapGenerator.Terrain.PATH
	if self_t == MapGenerator.Terrain.WATER:
		return MapGenerator.Terrain.WATER
	return -1


## Champ de présence (0..1) du matériau `kind`, interpolé bilinéairement
## entre les 4 centres de cases entourant (fx,fy) — donne un dégradé continu
## à travers la frontière, base du seuil bruité.
func _terrain_field(grid: Array, sz: Vector2i, fx: float, fy: float, kind: int) -> float:
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var m00 := _is_kind(grid, sz, x0,     y0,     kind)
	var m10 := _is_kind(grid, sz, x0 + 1, y0,     kind)
	var m01 := _is_kind(grid, sz, x0,     y0 + 1, kind)
	var m11 := _is_kind(grid, sz, x0 + 1, y0 + 1, kind)
	return lerpf(lerpf(m00, m10, tx), lerpf(m01, m11, tx), ty)


func _is_kind(grid: Array, sz: Vector2i, x: int, y: int, kind: int) -> float:
	if x < 0 or x >= sz.x or y < 0 or y >= sz.y:
		return 0.0
	return 1.0 if grid[y][x] == kind else 0.0


## Atlas de tuile pour un terrain donné (chemin = variante déterministe par
## case, pour rester cohérent avec _apply_to_tilemap).
func _atlas_for_terrain(kind: int, c: int, r: int) -> Vector2i:
	if kind == MapGenerator.Terrain.WATER:
		# Volcan : le "bord d'eau" est une rive de LAVE — on fond vers le sol
		# de cendre (pas la tuile d'eau bleue) ; la lave 3D émissive recouvre.
		if _map.theme == MapGenerator.MapTheme.VOLCANO:
			return _map._ground_tile
		return _map._water_tile
	var pt: Array = _map._path_tiles
	if pt.is_empty():
		return _map._ground_tile
	return pt[hash(Vector2i(c, r)) % pt.size()]


func _bake_layer(img: Image, src: Image, layer: TileMapLayer, blend: bool, sz: Vector2i) -> void:
	if not is_instance_valid(layer):
		return
	for cell: Vector2i in layer.get_used_cells():
		if cell.x < 0 or cell.x >= sz.x or cell.y < 0 or cell.y >= sz.y:
			continue
		_bake_tile(img, src, layer.get_cell_atlas_coords(cell), cell, blend)


func _bake_tile(img: Image, src: Image, atlas: Vector2i, cell: Vector2i, blend: bool) -> void:
	var src_rect := Rect2i(atlas.x * TILE_PX, atlas.y * TILE_PX, TILE_PX, TILE_PX)
	var dst := Vector2i(cell.x * TILE_PX, cell.y * TILE_PX)
	if blend:
		img.blend_rect(src, src_rect, dst)
	else:
		img.blit_rect(src, src_rect, dst)


## Layer TallGrass — herbe ET fleurs se dressent maintenant en 3D (cf.
## _build_grass / _build_flowers), rien à cuire à plat depuis ce layer.
func _bake_tall_grass_flat(img: Image, src: Image, sz: Vector2i) -> void:
	if not is_instance_valid(_map._tall_grass):
		return
	for cell: Vector2i in _map._tall_grass.get_used_cells():
		if cell.x < 0 or cell.x >= sz.x or cell.y < 0 or cell.y >= sz.y:
			continue
		var atlas: Vector2i = _map._tall_grass.get_cell_atlas_coords(cell)
		if _is_grass_3d(atlas) or _is_flower_3d(atlas):
			continue
		_bake_tile(img, src, atlas, cell, true)


## Décors du layer Objects encore bakés à plat dans la texture du sol.
## (Les nénuphars y étaient — ils sont désormais de VRAIS meshes 3D
## destructibles posés sur l'eau, cf. _build_swamp_flora.)
func _bake_flat_decors(img: Image, src: Image, sz: Vector2i) -> void:
	for cell: Vector2i in _map._objects.get_used_cells():
		if cell.x < 0 or cell.x >= sz.x or cell.y < 0 or cell.y >= sz.y:
			continue
		var atlas: Vector2i = _map._objects.get_cell_atlas_coords(cell)
		if _is_flat_decor(atlas):
			pass   # nénuphars : rendus en 3D — rien à baker ici pour l'instant


func _is_flat_decor(atlas: Vector2i) -> bool:
	if atlas == _map.tile_nenuphar or atlas == _map.tile_petit_nenuphar:
		return true
	for nf: Vector2i in _map.tiles_nenuphars_fleur:
		if atlas == nf:
			return true
	return false


## ── FLORE DE MARÉCAGE 3D destructible ────────────────────────────────────
## Nénuphars : vrais meshes du pack COMPLET (lily_large/small, déjà importés
## par Godot) posés sur la surface de l'eau, à la place de l'ancien bake à
## plat dans la texture — enveloppés dans un BreakableProp (2 coups, poof, la
## tuile _objects est libérée).
## Roseaux : touffes de bambou (crops_bambooStage*) sur les BERGES (cases de
## boue adjacentes à l'eau, choisies par MapGenerator._reed_cells), cassables
## aussi. Tout est déterministe par hash de case — identique sur tous les pairs.
const _FULL_KIT := "res://assets/kenney_nature-kit/Models/GLTF format/"

func _build_swamp_flora() -> void:
	# Nénuphars (toutes les cases _objects portant une tuile de nénuphar)
	for cell: Vector2i in _map._objects.get_used_cells():
		var atlas: Vector2i = _map._objects.get_cell_atlas_coords(cell)
		if not _is_flat_decor(atlas):
			continue
		var big: bool = atlas != _map.tile_petit_nenuphar
		var lily := KitProps.instance_textured(_FULL_KIT,
			"lily_large.glb" if big else "lily_small.glb")
		var h := absi(hash(cell))
		lily.rotation.y = float(h % 628) * 0.01
		lily.scale = Vector3.ONE * (1.1 if big else 0.8) * (0.85 + float(h % 100) * 0.004)
		var wrap := BreakableProp.new()
		wrap.position = Vector3(cell.x + 0.5, WATER_SURFACE_Y + 0.015, cell.y + 0.5)
		wrap.add_child(lily)
		wrap.setup(lily, _map, [cell])
		add_child(wrap)
		_prop_by_cell[cell] = wrap

	# Roseaux de berge (cf. MapGenerator._decor_swamp)
	if not _map.has_method("get_reed_cells"):
		return
	for cell: Vector2i in _map.get_reed_cells():
		var h2 := absi(hash(cell) ^ 0x51ED)
		var clump := Node3D.new()
		# 2-3 tiges par touffe, décalées — une tige seule lit comme un poteau.
		for i in 2 + h2 % 2:
			var reed := KitProps.instance_textured(_FULL_KIT,
				"crops_bambooStageA.glb" if (h2 + i) % 2 == 0 else "crops_bambooStageB.glb")
			reed.position = Vector3(
				lerpf(-0.28, 0.28, float((h2 >> (i * 3)) % 8) / 7.0), 0.0,
				lerpf(-0.28, 0.28, float((h2 >> (i * 3 + 3)) % 8) / 7.0))
			reed.rotation.y = float((h2 >> i) % 628) * 0.01
			reed.scale = Vector3.ONE * (0.85 + float((h2 >> i) % 60) * 0.005)
			clump.add_child(reed)
		var wrap2 := BreakableProp.new()
		wrap2.position = Vector3(cell.x + 0.5, _map.get_height_at_cell(cell), cell.y + 0.5)
		wrap2.add_child(clump)
		wrap2.setup(clump, _map, [])   # pas de tuile ni collision à libérer
		add_child(wrap2)


# ─────────────────────────────────────────────────────────────────
# HERBES & FLEURS 3D — vrais meshes du pack Kenney, en MultiMeshInstance3D
# ─────────────────────────────────────────────────────────────────
# Chaque variante (haute herbe, petite herbe, chaque couleur de fleur) est
# un modèle du pack, dressé au sol avec une légère ondulation de vent
# (shader dédié, cf. KitProps.get_wind_shader). Regroupé en MultiMeshInstance3D par
# (case → fichier tiré au hasard) pour un coût de rendu quasi constant même
# sur une zone couverte d'herbe — même principe de perf que l'ancien système
# de croix de quads, juste avec de vrais volumes à la place.

func _build_grass() -> void:
	if _map.arena_mode or _map.theme == MapGenerator.MapTheme.VOLCANO:
		return   # grotte / volcan (cendre nue) : pas d'herbe
	# Haute herbe (tile_tg) : TOUFFES BUISSONNEUSES pixel-art (cf. GrassPatch,
	# style de la référence utilisateur — brins arqués, variante à cœur creux),
	# c'est la zone de FURTIVITÉ (joueur éclairci, ennemis invisibles).
	# Petite herbe : touffes basses Kenney, purement décoratives.
	_build_tall_grass_tufts()
	_build_kit_flora_layer(_map.tile_petite_herbe, ["grass.glb", "grass_leafs.glb", "plant_flatShort.glb"], 1.5, _grass_tints_for_theme())


## Une touffe billboard par case de haute herbe (léger jitter/échelle) —
## ~70 % pleines, ~30 % à cœur creux, teintées par biome. 2 MultiMesh.
func _build_tall_grass_tufts() -> void:
	if not is_instance_valid(_map._tall_grass):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_map.get_map_cell_size()) * 13 + 5
	var full: Array = []
	var hollow: Array = []
	for cell: Vector2i in _map._tall_grass.get_used_cells():
		if _map._tall_grass.get_cell_atlas_coords(cell) != _map.tile_tg:
			continue
		var px := float(cell.x) + rng.randf_range(0.35, 0.65)
		var pz := float(cell.y) + rng.randf_range(0.35, 0.65)
		var y: float = _map.get_height_at_cell(cell) if _map.has_method("get_height_at_cell") else 0.0
		var xf := Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.9, 1.2)),
			Vector3(px, y, pz))
		if rng.randf() < 0.3:
			hollow.append(xf)
		else:
			full.append(xf)
	var tint: Color = _PIXEL_GRASS_TINTS.get(_map.theme, Color(0.9, 1.0, 0.85))
	if not full.is_empty():
		add_child(GrassPatch.build_tufts(full, tint, false))
	if not hollow.is_empty():
		add_child(GrassPatch.build_tufts(hollow, tint, true))


## ── Touffes d'herbe PIXEL-ART (cf. GrassPatch) — la « texture » du sol :
## dispersées sur les cases d'herbe NUES (le sol baké seul faisait très
## plat), en un seul MultiMesh ondulant au vent. La haute herbe garde ses
## meshes Kenney (_build_grass), c'est la couche de remplissage en dessous.
const _PIXEL_GRASS_TINTS := {
	MapGenerator.MapTheme.FOREST: Color(0.88, 1.0, 0.85),
	MapGenerator.MapTheme.MEADOW: Color(1.0, 1.1, 0.9),
	MapGenerator.MapTheme.SWAMP:  Color(0.72, 0.82, 0.68),
	MapGenerator.MapTheme.AUTUMN: Color(1.5, 1.05, 0.5),
	MapGenerator.MapTheme.ROCKY:  Color(1.1, 1.0, 0.68),
	MapGenerator.MapTheme.LAKE:   Color(0.92, 1.08, 0.88),
}
const _PIXEL_GRASS_MAX := 5000   # plafond d'instances (perf)

func _build_pixel_grass() -> void:
	if _map.arena_mode or _map.theme == MapGenerator.MapTheme.VOLCANO:
		return   # grotte / volcan : sol nu, pas de tapis d'herbe
	var sz: Vector2i = _map.get_map_cell_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sz) * 31 + 7
	var bridge: Dictionary = {}
	if _map.has_method("get_bridge_cells"):
		for bc: Vector2i in _map.get_bridge_cells():
			bridge[bc] = true

	var transforms: Array = []
	for r in range(2, sz.y - 2):
		for c in range(2, sz.x - 2):
			if transforms.size() >= _PIXEL_GRASS_MAX:
				break
			var cell := Vector2i(c, r)
			if _map._ground.get_cell_source_id(cell)     == -1: continue
			if _map._water.get_cell_source_id(cell)      != -1: continue
			if _map._objects.get_cell_source_id(cell)    != -1: continue
			if _map._tall_grass.get_cell_source_id(cell) != -1: continue
			if _map._grid[r][c] != MapGenerator.Terrain.GRASS:  continue
			if bridge.has(cell):                                continue
			if rng.randf() > 0.45: continue   # densité : ~1 case sur 2
			for t in rng.randi_range(1, 2):
				var px := float(c) + rng.randf_range(0.15, 0.85)
				var pz := float(r) + rng.randf_range(0.15, 0.85)
				var y: float = _map.get_height_at_cell(cell) if _map.has_method("get_height_at_cell") else 0.0
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), Vector3(px, y, pz))
				transforms.append(xf)

	if transforms.is_empty():
		return
	var tint: Color = _PIXEL_GRASS_TINTS.get(_map.theme, Color(0.9, 1.0, 0.85))
	add_child(GrassPatch.build(transforms, tint))


## Teintes de l'herbe par thème — clés = noms des matériaux glTF Kenney
## ("grass" pour les touffes, "leafsGreen" pour plant_flatShort/Tall).
func _grass_tints_for_theme() -> Dictionary:
	match _map.theme:
		MapGenerator.MapTheme.AUTUMN:
			return {"grass": Color(0.78, 0.62, 0.24), "leafsGreen": Color(0.72, 0.52, 0.20)}
		MapGenerator.MapTheme.SWAMP:
			return {"grass": Color(0.36, 0.44, 0.26), "leafsGreen": Color(0.32, 0.40, 0.24)}
		MapGenerator.MapTheme.ROCKY:
			return {"grass": Color(0.48, 0.54, 0.30), "leafsGreen": Color(0.44, 0.50, 0.28)}
		_:  # FOREST / MEADOW : verts d'origine du pack
			return {}


## Fleurs (3 grandes variantes de couleur + petites fleurs) : mêmes meshes
## du pack que l'herbe, une couche par variante de couleur (pas de mélange
## de teintes dans un même MultiMesh). Le kit n'a pas de fleur blanche
## dédiée : on réutilise la forme "jaune" en reteintant son matériau pétale.
func _build_flowers() -> void:
	if _map.arena_mode or _map.theme == MapGenerator.MapTheme.VOLCANO:
		return   # grotte / volcan : pas de fleurs
	_build_kit_flora_layer(_map.tile_fleur_rouge, ["flower_redA.glb", "flower_redB.glb", "flower_redC.glb"], 2.1)
	_build_kit_flora_layer(_map.tile_fleur_violette, ["flower_purpleA.glb", "flower_purpleB.glb", "flower_purpleC.glb"], 2.1)
	_build_kit_flora_layer(_map.tile_fleur_blanche,
		["flower_yellowA.glb", "flower_yellowB.glb", "flower_yellowC.glb"], 2.1,
		{"colorYellow": Color(0.94, 0.94, 0.92)})
	for atlas: Vector2i in _map.tiles_petites_fleurs:
		_build_kit_flora_layer(atlas, ["plant_flatShort.glb", "plant_flatTall.glb", "grass_leafs.glb"], 1.5)


## Peuple une variante d'atlas du layer TallGrass avec des meshes du pack —
## une case → un fichier tiré au hasard dans `pool` (déterministe par case),
## un MultiMeshInstance3D par fichier effectivement utilisé.
func _build_kit_flora_layer(atlas: Vector2i, pool: Array, scale_mult: float, tints: Dictionary = {}) -> void:
	if not is_instance_valid(_map._tall_grass):
		return
	# Regroupe les cases par fichier choisi — un seul MultiMesh par fichier.
	var by_file: Dictionary = {}   # file -> Array[Vector2i]
	for cell: Vector2i in _map._tall_grass.get_used_cells():
		if _map._tall_grass.get_cell_atlas_coords(cell) != atlas:
			continue
		var seed_val := hash(cell) + atlas.x * 131 + atlas.y
		var file: String = pool[abs(seed_val) % pool.size()]
		if not by_file.has(file):
			by_file[file] = []
		by_file[file].append(cell)

	for file: String in by_file:
		_build_flora_multimesh(file, by_file[file], scale_mult, tints)


## TAPIS DE FEUILLES (biome Automne) — rendu des cases posées par
## MapGenerator._gen_leaf_litter. Deux teintes (feuille tombée / feuille
## pourrie) réparties par hachage de case : un tapis monochrome se lisait comme
## un aplat orange plutôt que comme de la litière.
##
## Les cases PIÉGÉES ne sont volontairement PAS distinguées : tout l'intérêt est
## qu'on ne puisse pas les repérer (cf. _gen_leaf_litter). Le mesh vient du kit
## (`grass_leafs.glb`, matériau "grass" — nom relevé dans le glb, pas deviné).
const _LEAF_TINTS: Array[Color] = [
	Color(0.82, 0.42, 0.12),   # feuille tombée, orange franc
	Color(0.58, 0.31, 0.14),   # feuille pourrie, brun
]

func _build_leaf_litter() -> void:
	if not _map.has_method("get_leaf_cells"):
		return
	var cells: Array = _map.get_leaf_cells()
	if cells.is_empty():
		return
	var by_tint: Array = [[], []]
	for cell: Vector2i in cells:
		by_tint[abs(hash(cell)) % 2].append(cell)
	for i in 2:
		if (by_tint[i] as Array).is_empty():
			continue
		_build_flora_multimesh("grass_leafs.glb", by_tint[i], 1.7,
			{"grass": _LEAF_TINTS[i]})


func _build_flora_multimesh(file: String, cells: Array, scale_mult: float, tints: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data  = true   # custom_data.x = phase de vent par instance
	mm.mesh             = KitProps.prepare_mesh(file, tints, true)
	mm.instance_count   = cells.size()

	for i in cells.size():
		var cell: Vector2i = cells[i]
		var seed_val := hash(cell) + 91
		var jitter := float(abs(seed_val) % 1000) / 1000.0
		var s := scale_mult * lerpf(0.82, 1.2, jitter)
		var basis := Basis.from_euler(Vector3(0, jitter * TAU, 0)).scaled(Vector3.ONE * s)
		var origin := Vector3(
			cell.x + 0.5 + lerpf(-0.16, 0.16, jitter),
			_map.get_height_at_cell(cell),
			cell.y + 0.5 + lerpf(-0.16, 0.16, fmod(jitter * 7.0, 1.0))
		)
		mm.set_instance_transform(i, Transform3D(basis, origin))
		mm.set_instance_custom_data(i, Color(jitter * TAU, 0.0, 0.0, 0.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # ombres d'herbe/fleurs = bruit visuel
	add_child(mmi)


func _is_grass_3d(atlas: Vector2i) -> bool:
	return atlas == _map.tile_tg or atlas == _map.tile_petite_herbe


func _is_flower_3d(atlas: Vector2i) -> bool:
	if atlas == _map.tile_fleur_rouge or atlas == _map.tile_fleur_violette or atlas == _map.tile_fleur_blanche:
		return true
	for f: Vector2i in _map.tiles_petites_fleurs:
		if atlas == f:
			return true
	return false


# ─────────────────────────────────────────────────────────────────
# RELIEF — falaises en VRAIS blocs empilés du pack Kenney (chantier 2)
# ─────────────────────────────────────────────────────────────────

const KIT_CLIFF_FULL    := "cliff_block_rock.glb"          # 1×1×1 — dessus herbe / flancs roche
const KIT_CLIFF_HALF    := "cliff_blockHalf_rock.glb"      # 1×0.5×1 — palier de finition
const KIT_CLIFF_QUARTER := "cliff_blockQuarter_rock.glb"   # 1×0.25×1 — palier de finition fin

## Chaque case de chaque formation (MapGenerator._cliff_formations, remplies
## par _place_cliff_rect / l'arène) reçoit un vrai empilement de blocs
## 1×1×1 du pack Kenney (+ un demi/quart de bloc pour finir exactement à la
## hauteur procédurale) — silhouette "par étages" plutôt qu'un seul volume
## lisse ; dessus herbe / flancs roche déjà intégrés au modèle, reteintés
## par thème. Tous les blocs de la map sont regroupés en MultiMeshInstance3D
## par variante — coût quasi constant même pour les murs de l'arène.
## L'entrée de grotte est une plaque d'arche SOMBRE plaquée sur la face sud
## du mur (celle que la caméra voit) — l'ancienne variante "bloc creusé"
## avait son ouverture orientée côté caché, invisible en jeu.
func _build_cliff_formations() -> void:
	var colors := _cliff_colors_for_theme()
	# Grotte : les blocs (dessus "herbe" vert par thème ROCKY) servent de
	# fond/collision derrière les panneaux cave-kit — retintés roche sombre
	# pour supprimer tout vert (retour joueurs : pas de vert dans les grottes).
	if _map.arena_mode:
		if str(_map.get("interior_style")) == "house":
			# Intérieur de maison : l'anneau se lit comme un mur plâtré, pas
			# comme de la roche.
			colors = {"grass": Color(0.80, 0.75, 0.65), "dirt": Color(0.70, 0.65, 0.56)}
		else:
			colors = {"grass": Color(0.28, 0.26, 0.29), "dirt": Color(0.24, 0.22, 0.25)}
	var full_entries: Array    = []   # [{"cell":Vector2i,"y":float}, ...]
	var half_entries: Array    = []
	var quarter_entries: Array = []

	for formation: Dictionary in _map._cliff_formations:
		var rect: Rect2i = formation["rect"]
		var h: float     = formation["height"]
		var full_levels := int(h)
		var frac := h - float(full_levels)

		for cy in rect.size.y:
			for cx in rect.size.x:
				var cell := Vector2i(rect.position.x + cx, rect.position.y + cy)
				var y := 0.0
				for lvl in full_levels:
					full_entries.append({"cell": cell, "y": y})
					y += 1.0
				if frac > 0.35:
					half_entries.append({"cell": cell, "y": y})
				elif frac > 0.05:
					quarter_entries.append({"cell": cell, "y": y})

		_add_cliff_collision(rect, h)

	_build_cliff_multimesh(KIT_CLIFF_FULL, full_entries, colors)
	_build_cliff_multimesh(KIT_CLIFF_HALF, half_entries, colors)
	_build_cliff_multimesh(KIT_CLIFF_QUARTER, quarter_entries, colors)

	for cell: Vector2i in _map.get_cave_cells():
		_add_cave_entrance(cell)


## Arche de grotte (cave-kit `gate-rock.glb`, texturée) à la case d'entrée,
## plaquée contre la face sud du mur (celle que voit la caméra). Remplace
## l'ancienne plaque `cliff_cave_rock` (retour joueurs : grottes pas belles).
## NOTE : l'échelle/orientation est un premier jet — à affiner à l'œil dans
## l'éditeur (le module Kenney fait ~4 u de base, orienté ouverture +Z).
func _add_cave_entrance(cell: Vector2i) -> void:
	var gate := KitProps.instance_textured(KitProps.CAVE_KIT_DIR, KitProps.CAVE_GATE_ROCK)
	gate.scale = Vector3(0.5, 0.5, 0.5)
	gate.position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
	add_child(gate)


## Collision pleine sur toute la formation — plus simple/robuste qu'une
## shape par bloc empilé, comportement identique pour le joueur.
func _add_cliff_collision(rect: Rect2i, h: float) -> void:
	var w := float(rect.size.x)
	var d := float(rect.size.y)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, h, d)
	cs.shape = sh
	cs.position = Vector3(rect.position.x + w * 0.5, h * 0.5, rect.position.y + d * 0.5)
	body.add_child(cs)
	add_child(body)


func _build_cliff_multimesh(file: String, entries: Array, colors: Dictionary) -> void:
	if entries.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh             = KitProps.prepare_mesh(file, colors, false)
	mm.instance_count   = entries.size()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var cell: Vector2i = e["cell"]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cell.x + 0.5, e["y"], cell.y + 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


## Couleurs plates (dessus/flancs) des blocs de falaise selon le thème
## courant — clés "grass"/"dirt" = noms des matériaux glTF du modèle Kenney.
## L'arène de grotte force theme=ROCKY (cf. MapGenerator._generate_arena),
## donc ses murs suivent automatiquement la teinte rocailleuse.
func _cliff_colors_for_theme() -> Dictionary:
	match _map.theme:
		MapGenerator.MapTheme.SWAMP:
			return {"grass": Color(0.36, 0.40, 0.28), "dirt": Color(0.34, 0.32, 0.26)}
		MapGenerator.MapTheme.MEADOW:
			return {"grass": Color(0.42, 0.64, 0.32), "dirt": Color(0.62, 0.56, 0.46)}
		MapGenerator.MapTheme.ROCKY:
			return {"grass": Color(0.44, 0.48, 0.34), "dirt": Color(0.58, 0.50, 0.42)}
		MapGenerator.MapTheme.AUTUMN:
			return {"grass": Color(0.72, 0.56, 0.24), "dirt": Color(0.52, 0.42, 0.32)}
		MapGenerator.MapTheme.VOLCANO:
			# Basalte sombre teinté de braise — pas de vert.
			return {"grass": Color(0.30, 0.20, 0.18), "dirt": Color(0.26, 0.18, 0.16)}
		_:  # FOREST
			return {"grass": Color(0.30, 0.50, 0.26), "dirt": Color(0.46, 0.42, 0.36)}


## Gros caillou 2×2 — mesh du pack Kenney (rock_largeX) plutôt qu'un volume
## texturé plat, silhouette bien plus organique pour un coût similaire.
func _add_rock_box(top_left: Vector2i, w: int, d: int, cells: Array) -> void:
	var seed_val := hash(top_left)
	var file: String = KitProps.ROCKS_LARGE[abs(seed_val) % KitProps.ROCKS_LARGE.size()]
	var jitter := float(abs(seed_val) % 1000) / 1000.0
	var rock := KitProps.instance(file)
	rock.scale = Vector3.ONE * KIT_ROCK_LARGE_SCALE * lerpf(0.85, 1.15, jitter)
	rock.rotation.y = jitter * TAU
	rock.position = Vector3(top_left.x + w * 0.5, 0.0, top_left.y + d * 0.5)
	add_child(rock)

	for c: Vector2i in cells:
		_prop_by_cell[c] = rock


## Petit rocher/caillou 1×1 (décor générique + variantes rocailleuses) —
## mesh du pack Kenney (rock_smallX), variété par case via seed.
func _add_kit_rock_small(cell: Vector2i) -> void:
	var seed_val := hash(cell) + 7
	var file: String = KitProps.ROCKS_SMALL[abs(seed_val) % KitProps.ROCKS_SMALL.size()]
	var jitter := float(abs(seed_val) % 1000) / 1000.0
	var rock := KitProps.instance(file)
	rock.scale = Vector3.ONE * KIT_ROCK_SMALL_SCALE * lerpf(0.8, 1.25, jitter)
	rock.rotation.y = jitter * TAU
	rock.position = Vector3(cell.x + 0.5, _map.get_height_at_cell(cell), cell.y + 0.5)
	add_child(rock)
	_prop_by_cell[cell] = rock


# ─────────────────────────────────────────────────────────────────
# PROPS — billboards (mêmes règles d'emprise que le 2D)
# ─────────────────────────────────────────────────────────────────

func _build_props() -> void:
	var handled: Dictionary = {}
	for cell: Vector2i in _map._objects.get_used_cells():
		if handled.has(cell):
			continue
		var atlas: Vector2i = _map._objects.get_cell_atlas_coords(cell)

		# Coffres : rendus/gérés par le nœud Chest (CombatArena)
		if atlas == _map.tile_chest_closed or atlas == _map.tile_chest_open:
			continue
		# Falaises + entrée de grotte : volumes gérés par _build_cliff_formations
		if _map._is_cliff_tile(atlas) or atlas == _map.tile_grotte_haut or atlas == _map.tile_grotte_bas:
			continue
		# Nénuphars : bakés à plat dans la texture du sol
		if _is_flat_decor(atlas):
			continue

		# Arbre 3×3 → mesh du pack Kenney (pool + teinte selon le thème),
		# sinon billboard si la variante n'est pas couverte.
		var toff: Vector2i = _map._tree_offset(atlas)
		if toff != Vector2i(-1, -1):
			var tl := cell - toff
			_mark_block(handled, tl, 3, 3)
			var tree_origin: Vector2i = _map._objects.get_cell_atlas_coords(tl)
			# Volcan : arbres MORTS nus (procéduraux) au lieu des meshes
			# feuillus du pack — le kit Kenney n'a pas d'arbre sans feuilles.
			if _map.theme == MapGenerator.MapTheme.VOLCANO:
				_add_dead_tree(tl)
				continue
			var tree_cfg := _kit_tree_config(tree_origin)
			if not (tree_cfg["pool"] as Array).is_empty():
				_add_kit_tree(tl, tree_cfg["pool"], tree_cfg["tints"])
			else:
				_add_prop_sprite(tree_origin, tl, 3, 3, [])
			continue

		# Gros caillou 2×2 → mesh du pack Kenney (rock_largeX)
		if _map._in_block(atlas, _map.tile_gros_caillou_orig, 2, 2):
			var tl2: Vector2i = cell - (atlas - _map.tile_gros_caillou_orig)
			_mark_block(handled, tl2, 2, 2)
			_add_rock_box(tl2, 2, 2, _block_cells(tl2, 2, 2))
			continue

		# Arbre coupable (CS Coupe) 1×3 vertical — retiré dynamiquement par
		# cut_tree_group, donc toutes ses cases pointent vers le même nœud
		if (atlas.x == _map.tile_coupe_gauche.x or atlas.x == _map.tile_coupe_droit.x) \
				and atlas.y >= 12 and atlas.y <= 14:
			var top := cell - Vector2i(0, atlas.y - 12)
			_mark_block(handled, top, 1, 3)
			_add_prop_sprite(Vector2i(atlas.x, 12), top, 1, 3, _block_cells(top, 1, 3))
			continue

		# Champignon 3×1 vertical — cosmétique, cassable à l'attaque
		var crow: int = _map._champi_row(atlas)
		if crow != -1:
			var top2 := cell - Vector2i(0, crow)
			_mark_block(handled, top2, 1, 3)
			_add_prop_sprite(_map.tile_champi_origin, top2, 1, 3, _block_cells(top2, 1, 3), true)
			continue

		# Petit rocher/caillou décoratif 1×1 → mesh du pack Kenney (rock_smallX)
		if atlas == _map.tile_rocher or atlas in _map.tiles_cailloux:
			_add_kit_rock_small(cell)
			continue

		# Décor/objet 1×1 (souches, rondins…) — cosmétique, cassable à
		# l'attaque, SAUF le rocher CS Force (gating gameplay : il se casse
		# uniquement via la CS, cf. break_rock_at).
		_add_prop_sprite(atlas, cell, 1, 1, [cell], atlas != _map.tile_boulder)


func _mark_block(handled: Dictionary, top_left: Vector2i, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			handled[top_left + Vector2i(dx, dy)] = true


func _block_cells(top_left: Vector2i, w: int, h: int) -> Array:
	var result: Array = []
	for dy in h:
		for dx in w:
			result.append(top_left + Vector2i(dx, dy))
	return result


## Billboard découpé du tileset, pieds ancrés au centre de la rangée du bas
## de son emprise. `cells` : cases dont le retrait (CS) doit supprimer ce prop.
## `breakable` : décor purement cosmétique cassable à l'attaque (souches,
## rondins, champignons…) — enveloppé dans un BreakableProp (groupe
## "breakables", secousse + poof, libère tuiles et collision à la casse).
func _add_prop_sprite(origin: Vector2i, top_left: Vector2i, cw: int, ch: int,
		cells: Array, breakable: bool = false) -> void:
	var spr := Billboard3D.make_tile_sprite(TILESET_PATH, origin, cw, ch, 1.0)
	var anchor := Vector3(top_left.x + cw * 0.5, 0.0, top_left.y + ch - 0.5)
	var node: Node3D = spr
	if breakable:
		var wrap := BreakableProp.new()
		wrap.position = anchor
		spr.position  = Vector3.ZERO
		wrap.add_child(spr)
		wrap.setup(spr, _map, cells)
		node = wrap
	else:
		spr.position = anchor
	add_child(node)
	for c: Vector2i in cells:
		_prop_by_cell[c] = node


# ─────────────────────────────────────────────────────────────────
# ARBRES 3D — meshes du pack Kenney Nature Kit (cf. KIT_TREES_* plus haut)
# ─────────────────────────────────────────────────────────────────

## Variante d'atlas → {pool: Array[String], tints: Dictionary} selon le
## thème courant — c'est ici que chaque biome prend sa palette d'arbres :
##   AUTOMNE → variantes _fall (feuillages orange/jaune du pack) ;
##   MARÉCAGE → l'"arbre mort" devient un feuillu au feuillage moribond
##     (teinte olive-brun) au lieu de l'ancien billboard plat ;
##   autres → verts par défaut du pack. Pool vide = billboard (non couvert).
func _kit_tree_config(origin: Vector2i) -> Dictionary:
	# Feuillages SATURÉS : les verts par défaut du pack Kenney sont pâles —
	# on reteinte vers des verts francs (référence : mockups utilisateur).
	var lush := {"leafsGreen": Color(0.22, 0.55, 0.16), "leafsDark": Color(0.14, 0.40, 0.14)}
	if origin == _map.tile_tree_origin:
		if _map.theme == MapGenerator.MapTheme.AUTUMN:
			return {"pool": KitProps.TREES_FALL, "tints": {}}
		return {"pool": KitProps.TREES_ROUND, "tints": lush}
	if origin == _map.tile_sapin_origin:
		return {"pool": KitProps.TREES_PINE, "tints": lush}
	if origin == _map.tile_arbre_mort_orig:
		return {"pool": KitProps.TREES_ROUND, "tints": {
			"leafsGreen": Color(0.34, 0.36, 0.22),   # feuillage moribond
			"woodBark":   Color(0.36, 0.30, 0.26),   # écorce détrempée
		}}
	return {"pool": [], "tints": {}}


## Arbre MORT nu procédural (biome Volcan) : tronc conique + 3-6 branches
## anguleuses sans feuilles, bois carbonisé sombre. Le pack Kenney n'a pas
## d'arbre sans feuilles — on le construit à la main pour un vrai squelette
## calciné. Ancrage identique au billboard 3×3 (centre x, rangée du bas z) ;
## la collision vient de la tuile _objects, indépendante du visuel.
const _DEAD_WOOD := Color(0.13, 0.10, 0.09)

func _add_dead_tree(top_left: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(top_left) + 991

	var mat := StandardMaterial3D.new()
	mat.albedo_color  = _DEAD_WOOD.lerp(Color(0.22, 0.13, 0.10), rng.randf())
	mat.roughness     = 1.0
	mat.diffuse_mode  = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var tree := Node3D.new()
	tree.position = Vector3(top_left.x + 1.5, 0.0, top_left.y + 2.5)
	tree.rotation.y = rng.randf() * TAU

	var trunk_h := rng.randf_range(2.6, 3.8)
	var trunk := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.bottom_radius = rng.randf_range(0.20, 0.28)
	tcyl.top_radius    = 0.07
	tcyl.height        = trunk_h
	tcyl.radial_segments = 6
	trunk.mesh = tcyl
	trunk.material_override = mat
	trunk.position = Vector3(0, trunk_h * 0.5, 0)
	trunk.rotation = Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	tree.add_child(trunk)

	# Branches nues : cylindres fins, dressés et inclinés vers l'extérieur.
	var n := rng.randi_range(3, 6)
	for i in n:
		var br := MeshInstance3D.new()
		var bcyl := CylinderMesh.new()
		var blen := rng.randf_range(0.8, 1.6)
		bcyl.bottom_radius = rng.randf_range(0.05, 0.09)
		bcyl.top_radius    = 0.02
		bcyl.height        = blen
		bcyl.radial_segments = 5
		br.mesh = bcyl
		br.material_override = mat
		# Point d'attache le long du tronc (moitié haute) + inclinaison.
		var ay := trunk_h * rng.randf_range(0.45, 0.95)
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(0.5, 1.1)   # ~30-63° depuis la verticale
		br.position = Vector3(0, ay, 0)
		br.rotation = Vector3(sin(yaw) * tilt, yaw, cos(yaw) * tilt)
		# Le cylindre pousse le long de son axe Y local : on le décale pour
		# que sa base parte du tronc, pas son centre.
		br.translate_object_local(Vector3(0, blen * 0.5, 0))
		tree.add_child(br)

	add_child(tree)


## Même ancrage que le billboard 3×3 (centre en x, rangée du bas en z) —
## la collision (rangée du tronc) reste calculée indépendamment du visuel.
## Chaque variante du pool a sa propre hauteur native (cf. KitProps.TREE_NATIVE_HEIGHT)
## — on normalise sur une hauteur cible commune avant de jouer avec la variété.
func _add_kit_tree(top_left: Vector2i, pool: Array, tints: Dictionary = {}) -> void:
	var seed_val := hash(top_left)
	var file: String = pool[abs(seed_val) % pool.size()]
	var jitter := float(abs(seed_val) % 1000) / 1000.0

	var tree := KitProps.instance(file, tints)
	var native_h: float = KitProps.TREE_NATIVE_HEIGHT.get(file, 1.5)
	var target_h := KIT_TREE_TARGET_HEIGHT * lerpf(0.82, 1.18, jitter)
	tree.scale = Vector3.ONE * (target_h / native_h)
	tree.position = Vector3(top_left.x + 1.5, 0.0, top_left.y + 2.5)
	tree.rotation.y = jitter * TAU
	add_child(tree)


# ─────────────────────────────────────────────────────────────────
# COLLISIONS 3D — mêmes règles que l'ancien _build_map_collision 2D
# ─────────────────────────────────────────────────────────────────

func _build_collisions() -> void:
	_obstacle_body = StaticBody3D.new()
	_obstacle_body.name = "Obstacles"
	_obstacle_body.collision_layer = 1
	_obstacle_body.collision_mask  = 0
	add_child(_obstacle_body)

	for cell: Vector2i in _map._objects.get_used_cells():
		var atlas: Vector2i = _map._objects.get_cell_atlas_coords(cell)
		if _map._is_decor_tile(atlas): continue
		# Falaises : collision par formation (cf. _add_cliff_collision)
		if _map._is_cliff_tile(atlas): continue
		# Arbres 3×3 : seule la rangée du tronc bloque (canopée traversable)
		var toff: Vector2i = _map._tree_offset(atlas)
		if toff != Vector2i(-1, -1) and toff.y < 2:
			continue

		var csize: Vector2 = _map._col_size(atlas) / float(TILE_PX)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(csize.x, OBSTACLE_HEIGHT, csize.y)
		cs.shape = sh
		cs.position = Vector3(cell.x + 0.5, OBSTACLE_HEIGHT * 0.5, cell.y + 0.5)
		_obstacle_body.add_child(cs)
		_collision_by_cell[cell] = cs

	_build_water_collision()


## L'eau garde sa couche physique dédiée (WATER_LAYER = 4) : seule la CS Surf
## permet de l'ignorer (cf. CombatArena._compute_cs_unlocks). Les cases sont
## fusionnées par segments horizontaux pour limiter le nombre de shapes.
func _build_water_collision() -> void:
	var water_body := StaticBody3D.new()
	water_body.name = "WaterCollision"
	water_body.collision_layer = _map.WATER_LAYER
	water_body.collision_mask  = 0
	add_child(water_body)

	var rows: Dictionary = {}
	for cell: Vector2i in _map._water.get_used_cells():
		# Flaques peu profondes (FOREST/SWAMP) : traversables à pied, aucune
		# collision — seule l'eau "profonde" (LAKE) bloque le passage.
		if _map.is_shallow_cell(cell):
			continue
		if not rows.has(cell.y):
			rows[cell.y] = []
		rows[cell.y].append(cell.x)

	for y: int in rows:
		var xs: Array = rows[y]
		xs.sort()
		var run_start: int = xs[0]
		var prev: int      = xs[0]
		for i in range(1, xs.size() + 1):
			var x: int = xs[i] if i < xs.size() else prev + 2   # sentinelle : clôt le dernier run
			if x != prev + 1:
				_add_water_run(run_start, prev, y, water_body)
				run_start = x
			prev = x


func _add_water_run(x0: int, x1: int, y: int, body: StaticBody3D) -> void:
	var run_len := float(x1 - x0 + 1)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	# Boîte un peu plus étroite que la tuile — même marge de passage que les
	# shapes 10px de la version 2D (on peut longer le bord de l'eau).
	sh.size = Vector3(maxf(run_len - 0.35, 0.5), 0.8, 0.625)
	cs.shape = sh
	cs.position = Vector3(float(x0 + x1 + 1) * 0.5, 0.4, float(y) + 0.5)
	body.add_child(cs)


func _build_border_walls() -> void:
	var sz: Vector2i = _map.get_map_cell_size()
	var W := float(sz.x)
	var H := float(sz.y)
	for wall: Rect2 in [
		Rect2(-0.5, -0.5, W + 1, 0.5),
		Rect2(-0.5, H,    W + 1, 0.5),
		Rect2(-0.5, -0.5, 0.5,   H + 1),
		Rect2(W,    -0.5, 0.5,   H + 1),
	]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask  = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(wall.size.x, BORDER_WALL_H, wall.size.y)
		cs.shape = sh
		cs.position = Vector3(wall.get_center().x, BORDER_WALL_H * 0.5, wall.get_center().y)
		body.add_child(cs)
		add_child(body)


# ─────────────────────────────────────────────────────────────────
# API — retrait dynamique (CS Coupe / CS Force)
# ─────────────────────────────────────────────────────────────────

## Supprime le visuel et la collision 3D d'une case (rocher cassé, arbre
## coupé). Un prop multi-cases (arbre coupable 1×3) n'est libéré qu'une fois.
func clear_cell(cell: Vector2i) -> void:
	if _collision_by_cell.has(cell):
		var cs: CollisionShape3D = _collision_by_cell[cell]
		if is_instance_valid(cs):
			cs.queue_free()
		_collision_by_cell.erase(cell)

	if _prop_by_cell.has(cell):
		var prop: Node = _prop_by_cell[cell]
		var shared: Array = []
		for key: Vector2i in _prop_by_cell:
			if _prop_by_cell[key] == prop:
				shared.append(key)
		for key: Vector2i in shared:
			_prop_by_cell.erase(key)
		if is_instance_valid(prop):
			prop.queue_free()
