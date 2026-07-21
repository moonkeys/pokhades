@tool
class_name MapGenerator
extends MapBase  # MUST extend MapBase — CombatArena.gd cast: get_node("Map") as MapBase

enum Terrain { GRASS = 0, PATH = 1, WATER = 2, TREE = 3 }
enum GatingType { NONE = 0, SURF = 1, COUPE = 2, FORCE = 3 }
enum MapTheme { FOREST = 0, SWAMP = 1, MEADOW = 2, ROCKY = 3, AUTUMN = 4, LAKE = 5, VOLCANO = 6, VILLAGE = 7 }
## Forme de la zone jouable — casse la silhouette rectangulaire par défaut.
## Chaque forme est un CHAMP DE DISTANCE SIGNÉ (cf. _shape_sdf) déformé par un
## bruit (_shape_noise) : aucun bord n'est droit, même le "RECT" est une boîte
## aux coins arrondis et au contour ondulant. Le masque est appliqué deux fois :
## par _carve_border (avant les chemins, pour que ceux-ci puissent le percer) et
## par _carve_shape_mask (après, en épargnant les chemins déjà tracés).
enum MapShape { RECT = 0, CIRCLE = 1, L_SHAPE = 2, HOURGLASS = 3, CRESCENT = 4 }

## Couche physique dédiée à l'eau — séparée des autres obstacles pour que
## seule la CS Surf puisse l'ignorer (cf. CombatArena._apply_cs_unlocks).
const WATER_LAYER := 4

## ─────────────────────────────────────────────────────────────────
## EXPORTS SPÉCIFIQUES AU GÉNÉRATEUR PROCÉDURAL
## (tile_*, source_id, flower_density, entry_tile, exit_A/B/C, etc.
##  sont hérités de MapBase — ne pas re-déclarer ici)
## ─────────────────────────────────────────────────────────────────
@export_group("Map — Taille")
@export var map_size:     Vector2i = Vector2i(68, 38)
@export var map_seed:     int      = 0
@export var random_size:  bool     = true
## Réduits par rapport à l'original (60-96 × 35-56) — retour joueurs : les
## zones étaient trop grandes/vides, on resserre pour un rythme plus dense.
@export var map_size_min: Vector2i = Vector2i(48, 28)
@export var map_size_max: Vector2i = Vector2i(74, 42)

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
@export var gating_type:   GatingType = GatingType.NONE
## Si vrai, la CS découle du thème (Forêt→Coupe, Marécage→Surf, sinon Force).
@export var random_gating: bool       = true

@export_group("Thème")
## Si vrai, un thème est tiré au sort à chaque génération.
@export var random_theme: bool  = true
@export var theme:        MapTheme = MapTheme.FOREST

@export_group("Arène (grotte)")
## Mode arène : petite salle fermée de falaises, pas de chemins ni de coffre gardé.
@export var arena_mode: bool     = false
## Habillage de l'arène de demi-boss : "cave" (grotte, modules cave-kit) ou
## "house" (intérieur de maison — biome Village : on entre par une porte, on
## ne doit pas se retrouver dans une caverne). Posé par CombatArena._load_cave
## AVANT add_child (donc avant _ready/_generate). cf. MapRender3D.
@export var interior_style: String = "cave"
@export var arena_size: Vector2i = Vector2i(32, 22)

@export_group("Tiles Sol — Variantes")
## Sols secondaires mélangés au sol principal du biome. Coordonnées relevées en
## scannant le tileset (tuiles PLEINES, texture homogène, sans motif répétitif
## visible au carrelage) — ne pas en inventer sans vérifier le rendu carrelé.
## Le mélange se fait PAR PIXEL au bake (cf. MapRender3D._ground_color_at), pas
## par case : les transitions serpentent au lieu de suivre la grille.
@export var tile_herbe_dense: Vector2i = Vector2i(71, 33)  # vert soutenu
@export var tile_herbe_pale:  Vector2i = Vector2i(14, 33)  # vert pâle
@export var tile_herbe_seche: Vector2i = Vector2i(13, 20)  # herbe sèche / olive
@export var tile_terre_seche: Vector2i = Vector2i(15, 20)  # kaki nu
@export var tile_sable:       Vector2i = Vector2i(6,  45)  # sable

@export_group("Tiles Thème — Forêt")
@export var tile_sapin_origin:    Vector2i = Vector2i(1,  9)   # sapin 3×3 (centre 2,10)
@export var tile_arbre_mort_orig: Vector2i = Vector2i(64, 9)   # arbre mort 3×3 (centre 65,10)
@export var tile_champi_origin:   Vector2i = Vector2i(4,  12)  # champignon 3×1 vertical
@export var tile_souche_sombre:   Vector2i = Vector2i(3,  12)
@export var tile_souche_claire:   Vector2i = Vector2i(6,  12)

@export_group("Tiles Thème — Marécage")
@export var tile_eau_sale:        Vector2i = Vector2i(67, 26)  # eau sale (centre du 3×3)
@export var tile_sol_boueux:      Vector2i = Vector2i(23, 16)  # sol boueux (centre du 3×3)
@export var tile_nenuphar:        Vector2i = Vector2i(67, 30)
@export var tile_petit_nenuphar:  Vector2i = Vector2i(66, 30)
@export var tiles_nenuphars_fleur: Array[Vector2i] = [
	Vector2i(68, 28), Vector2i(68, 29), Vector2i(68, 30)
]

@export_group("Tiles Thème — Rocailleux")
@export var tile_cliff_origin:     Vector2i = Vector2i(52, 32)  # falaise 3×3 (centre 53,33)
@export var tile_gros_caillou_orig: Vector2i = Vector2i(22, 41) # gros caillou 2×2
@export var tiles_cailloux: Array[Vector2i] = [
	Vector2i(64, 38), Vector2i(65, 38), Vector2i(66, 38)
]
@export var tile_grotte_haut:  Vector2i = Vector2i(26, 37)
@export var tile_grotte_bas:   Vector2i = Vector2i(26, 38)
@export var tile_chemin_pierre_orig: Vector2i = Vector2i(46, 15)  # chemin pierre 2×4

@export_group("Tiles Gating")
@export var tile_bush:         Vector2i = Vector2i(3,  20)
@export var tile_boulder:      Vector2i = Vector2i(22, 38)
## Arbre coupable (CS Coupe) — 3 tiles de haut, approche par le SUD (col 7) ou le NORD (col 8)
@export var tile_coupe_gauche: Vector2i = Vector2i(7,  12)  # approche par le sud
@export var tile_coupe_droit:  Vector2i = Vector2i(8,  12)  # approche par le nord

## ─────────────────────────────────────────────────────────────────
## ÉTAT INTERNE
## ─────────────────────────────────────────────────────────────────
var _grid: Array = []
var _rng:  RandomNumberGenerator = RandomNumberGenerator.new()

## Cellules d'eau MARCHABLES (Terrain.WATER quand même, pour le rendu/
## reconnaissance existants, mais SANS collision — cf. MapRender3D.
## _build_water_collision). Peuplé par _apply_theme selon "water_mode"
## ("deep" = LAKE, seule vraie eau profonde ; "shallow" = FOREST/SWAMP,
## flaques marchables ; "none" = MEADOW/ROCKY/AUTUMN, pas d'eau du tout —
## retour joueurs : l'eau profonde partout cassait le rythme).
var _shallow_cells: Dictionary = {}
var _water_mode: String = "deep"
## Demi-axes (x, y) des mares creusées par _ensure_water_pools.
var pool_radius: Vector2i = Vector2i(3, 2)

## Cases de BERGE choisies pour les touffes de roseaux (Marécage) — rendues en
## bambous 3D destructibles par MapRender3D._build_swamp_flora.
var _reed_cells: Array[Vector2i] = []

func get_reed_cells() -> Array[Vector2i]:
	return _reed_cells
var _map_shape: MapShape = MapShape.RECT
## Bruit qui déforme le contour de la forme (cf. _shape_sdf) — c'est LUI qui
## enlève le côté "géométrique" : sans lui un cercle est un cercle parfait.
var _shape_noise: FastNoiseLite = null
## Paramètres de la forme courante, tirés une fois par génération dans
## _init_shape (miroirs du L, côté du trou du croissant…).
var _shape_flip_x: bool = false
var _shape_flip_y: bool = false

func is_shallow_cell(cell: Vector2i) -> bool:
	return _shallow_cells.has(cell)


## Mécanique de terrain du MARÉCAGE : la boue colle aux pattes.
## Multiplicateur de vitesse pour un Pokémon situé en `pos` — 1.0 partout, sauf
## dans les flaques marchables du marécage. Les mêmes cases `_shallow_cells`
## existent aussi en forêt (simples flaques décoratives) : seul le marécage
## ralentit, c'est SA signature (les corridors y sont larges, cf. path_width —
## ils doivent peser, pas se traverser au sprint).
##
## Porté par la map (et pas par TeamMember) : la connaissance du terrain reste
## d'un seul côté, joueur et IA n'ont qu'à multiplier (cf. TeamMember).
const MUD_SPEED_MULT := 0.55

## La case sous `pos` est-elle de la BOUE nue (Marécage) ? — le sol de base du
## biome, hors chemins (fermes) et hors eau. Sert aux empreintes de pas (cf.
## TeamMember/EnemyAI._update_puddle_steps).
func is_mud_cell(pos: Vector3) -> bool:
	if theme != MapTheme.SWAMP:
		return false
	var cell := world3_to_cell(pos)
	if cell.y < 0 or cell.y >= _grid.size():
		return false
	var row: PackedByteArray = _grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return false
	return row[cell.x] == Terrain.GRASS


func terrain_speed_mult(pos: Vector3) -> float:
	if theme != MapTheme.SWAMP:
		return 1.0
	return MUD_SPEED_MULT if _shallow_cells.has(world3_to_cell(pos)) else 1.0


## Cases de haute herbe de la zone (Prairie uniquement) — mémorisées à la
## génération pour que l'IA puisse CHOISIR d'aller s'y embusquer (cf.
## EnemyAI._pick_ambush_spot), au lieu de ne se cacher que par hasard.
var _tg_cells: Array[Vector2i] = []

func get_tall_grass_cells() -> Array[Vector2i]:
	return _tg_cells

## Case de haute herbe la plus proche de `pos` dans un rayon de `max_dist`
## (unités monde), ou Vector3.INF s'il n'y en a pas.
##
## Balayage linéaire des nappes : elles se comptent en dizaines de cases, et
## l'appelant met le résultat en cache (une fois par ennemi, pas par frame).
func nearest_tall_grass(pos: Vector3, max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_d := max_dist * max_dist
	for cell: Vector2i in _tg_cells:
		var w := cell_to_world3(cell)
		var d := Vector2(w.x - pos.x, w.z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = w
	return best


## Mécanique de terrain de la FORÊT : les troncs coupent la ligne de tir.
## Un projectile qui traverse une case d'arbre est absorbé (cf. Projectile).
## Le combat à distance y demande donc de se déplacer pour dégager son angle,
## au lieu de tirer à travers le décor — c'est ce qui donne son sens à la
## densité d'arbres élevée du biome.
##
## Vaut pour TOUS les tirs, joueur comme ennemis : c'est du couvert, pas un
## malus de camp.
func blocks_projectile(pos: Vector3) -> bool:
	if theme != MapTheme.FOREST:
		return false
	var cell := world3_to_cell(pos)
	if cell.y < 0 or cell.y >= _grid.size():
		return false
	var row: PackedByteArray = _grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return false
	return row[cell.x] == Terrain.TREE

## Cellule d'eau (ou de LAVE en biome Volcan) — utilisé par CombatArena pour
## la brûlure au contact de la lave.
func is_water_cell(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= _grid.size():
		return false
	var row: PackedByteArray = _grid[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return false
	return row[cell.x] == Terrain.WATER
var _flower_mat: ShaderMaterial = null

## Couleur MOYENNE du sol effectivement baké (posée par MapRender3D.
## _bake_ground_plane). Le tablier de plaine lointaine (cf. BiomeAmbiance.
## _build_ground_apron) s'y accorde : la dalle jouable est un rectangle W×H, et
## dès que sa teinte diffère un tant soit peu de la plaine autour, on lit son
## contour rectangulaire au lieu de la silhouette organique (retour joueurs).
## Mesurée plutôt que codée en dur dans les palettes : le sol baké mélange
## herbe, chemins et décors plats, donc aucune constante ne peut suivre.
var ground_avg_color: Color = Color(0.42, 0.64, 0.32)

## Couleur MOYENNE des cases de chemin (posée par MapRender3D). Consommée par
## BiomeAmbiance._build_exit_trails, qui prolonge le sentier hors de la map.
var path_avg_color: Color = Color(0.62, 0.50, 0.34)


## Fisher-Yates seedé sur `_rng` — Array.shuffle() natif utilise TOUJOURS
## le RNG global du moteur (pas notre graine), donc en multijoueur chaque
## pair mélangeait ses listes de cases candidates différemment : coffres,
## herbes hautes, grottes et obstacles CS n'apparaissaient pas au même
## endroit selon le joueur (retour joueurs). Remplace TOUS les .shuffle()
## de ce fichier — même résultat sur tous les pairs pour une même graine.
func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## Cases accessibles à pied depuis l'entrée sans franchir d'eau (cf.
## _compute_reachable). Empêche de faire spawn un ennemi sur une île
## accessible uniquement à la nage (CS Surf) — il serait impossible à
## vaincre sans la CS, bloquant la progression.
var _reachable: Dictionary = {}

## Obstacles CS, exposés à CombatArena pour l'interaction en run.
var _force_boulders: Dictionary = {}   # case rocher → case d'approche
var _coupe_trees:     Array     = []   # [{"cells": Array[Vector2i], "approach": Vector2i}, ...]
var _cell_collision:  Dictionary = {}  # case → CollisionShape2D (cf. _build_map_collision)
var _cell_shadow:     Dictionary = {}  # case → Sprite2D (ombre blob associée)

## Formations de falaises posées par _place_cliff_rect / l'arène —
## consommées par MapRender3D pour instancier les volumes 3D avec leur
## hauteur procédurale : [{"rect": Rect2i, "height": float, "cave": bool}, ...]
var _cliff_formations: Array = []
## Emprises de maisons (biome Village) — Array[Rect2i], rendues en bâtiments
## procéduraux par MapRender3D._build_village_houses. Les cases sont marquées
## Terrain.TREE (bloquantes, pas de spawn dedans) mais SANS tuile _objects
## (donc pas de rendu d'arbre) ; la collision est posée par le rendu.
var _village_houses: Array = []

func get_village_houses() -> Array:
	return _village_houses


## La case (c,r) est-elle sur l'emprise d'une maison ? (village)
func _cell_in_house(c: int, r: int) -> bool:
	for rect: Rect2i in _village_houses:
		if rect.has_point(Vector2i(c, r)):
			return true
	return false

## ── TAPIS DE FEUILLES (biome Automne) ────────────────────────────────────
## Mécanique de terrain de l'Automne : le sol est jonché de feuilles, et
## CERTAINES cachent un collet. Le tapis est dense (on en traverse tout le
## temps) mais les pièges sont rares : c'est ce déséquilibre qui crée la
## tension — on ne peut pas éviter les feuilles, seulement accepter le risque.
## Le contraire (un piège sous chaque tas) n'aurait produit qu'un slalom.
##
## Pas de tuile de tilemap : les feuilles sont rendues directement en meshes
## par MapRender3D._build_leaf_litter. Ça évite de polluer le layer TallGrass,
## dont l'atlas sert à reconnaître les cachettes (cf. is_tall_grass_3d).
var _leaf_cells: Dictionary = {}   # case → true
var _leaf_traps: Dictionary = {}   # case → true tant que le piège n'a pas sauté

## Proportion de cases de feuilles qui cachent un collet.
const LEAF_TRAP_RATIO := 0.09

func get_leaf_cells() -> Array:
	return _leaf_cells.keys()

func is_leaf_cell(cell: Vector2i) -> bool:
	return _leaf_cells.has(cell)

## Déclenche le piège de `cell` s'il y en a un — le CONSOMME et renvoie true.
## Renvoie false s'il n'y a rien (ou plus rien) : un collet ne sert qu'une fois.
func spring_trap(cell: Vector2i) -> bool:
	if not _leaf_traps.has(cell):
		return false
	_leaf_traps.erase(cell)
	return true


## Cases du pont du biome Lac (planches posées par MapRender3D au-dessus de
## l'eau) — cases marchables reliant la rive sud à l'île centrale.
var _bridge_cells: Array = []   # Array[Vector2i]

## Couche de rendu HD-2D (sol baké + billboards + volumes + collisions 3D).
## Les TileMapLayers restent le modèle de données mais sont cachés en jeu.
var _render3d: MapRender3D = null

## Ambiance (ciel/fog/lumière/backdrop) affichée UNIQUEMENT dans l'éditeur —
## en jeu, c'est CombatArena qui possède l'unique BiomeAmbiance de la scène
## (elle gère aussi la variante grotte et les transitions de zone) ; en
## avoir une seconde ici entrerait en conflit avec elle (un seul
## WorldEnvironment "actif" à la fois dans Godot).
var _editor_ambiance: BiomeAmbiance = null

## ── État du thème courant (rempli par _apply_theme) ──────────────
var _ground_tile:  Vector2i = Vector2i(56, 33)
## Palette de sol du biome courant — [principal, variante…]. Consommée par
## MapRender3D._ground_color_at, qui les fond entre elles par bruit. Une seule
## entrée = sol uni (comportement d'origine).
var _ground_tiles: Array[Vector2i] = [Vector2i(56, 33)]
var _water_tile:   Vector2i = Vector2i(46, 26)
var _path_tiles:   Array[Vector2i] = [Vector2i(2, 16)]   # variantes — tirées au hasard par case
var _tree_origins: Array    = [Vector2i(1, 0)]   # 3×3, tirés au hasard par arbre
var _tg_threshold: float    = 0.65

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
	if not Engine.is_editor_hint():
		_build_pathfinding_grid()
		add_to_group("combat_map")


## Reconstruit la couche de rendu HD-2D (sol baké + billboards + volumes +
## collisions 3D) à partir de l'état courant des TileMapLayers — appelé à la
## fin de _generate()/_generate_arena(), donc AUSSI dans l'éditeur : ouvrir
## une scène de map (ex: scenes/world/ForestMap.tscn) et cliquer
## "⟳ Regénérer la map" montre directement le rendu 3D final dans le
## viewport 3D de l'éditeur, sans avoir à lancer le jeu.
func _refresh_render3d() -> void:
	_ground.visible     = false
	_water.visible      = false
	_tall_grass.visible = false
	_objects.visible    = false
	if is_instance_valid(_render3d):
		remove_child(_render3d)
		_render3d.queue_free()
	_render3d = MapRender3D.new()
	_render3d.name = "Render3D"
	add_child(_render3d)
	_render3d.build(self)
	if Engine.is_editor_hint():
		_refresh_editor_ambiance()


## Ciel/fog/lumière/backdrop du thème courant — éditeur seulement (cf. note
## sur _editor_ambiance). `arena_mode` sert de proxy pour "grotte" en preview.
func _refresh_editor_ambiance() -> void:
	if not is_instance_valid(_editor_ambiance):
		_editor_ambiance = BiomeAmbiance.new()
		_editor_ambiance.name = "EditorAmbiance"
		add_child(_editor_ambiance)
	_editor_ambiance.apply_theme(theme, map_size, arena_mode, self)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
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
## GÉNÉRATION — override de MapBase._generate()
## Le bouton "⟳ Regénérer la map" hérité de MapBase appelle _generate(),
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

	# Multijoueur : graine dérivée de la graine de run partagée + profondeur
	# → tous les pairs génèrent exactement la même map, sans RPC.
	if not Engine.is_editor_hint() and Net.in_run:
		map_seed = Net.zone_seed(RunManager.inst().rooms_cleared)
	_rng.seed = map_seed if map_seed != 0 else randi()

	if arena_mode:
		_generate_arena()
		return

	if random_size:
		map_size = Vector2i(
			_rng.randi_range(map_size_min.x, map_size_max.x),
			_rng.randi_range(map_size_min.y, map_size_max.y)
		)
	_compute_portals()

	print("MapGenerator: seed=%d  taille=%s" % [_rng.seed, map_size])

	_apply_theme()

	# Silhouette de la zone — tirée AVANT _carve_border, qui la consomme.
	_init_shape()

	_init_grid()
	_shallow_cells.clear()
	if _water_mode != "none":
		_gen_water_noise()
		_ensure_water_pools()
	if _water_mode == "shallow":
		_mark_shallow_water()
	_gen_tree_noise()
	_carve_border()
	_carve_paths()
	# Plus de lissage par automate : les splines sont déjà lisses (il éroderait
	# leurs portions fines). _smooth_path_mask n'est plus appelé nulle part.
	if theme == MapTheme.LAKE:
		_carve_lake()   # après les chemins : le grand lac central prime
	# Après les chemins : rogne la silhouette sans jamais couper une route
	# déjà tracée (cf. _carve_shape_mask, qui épargne Terrain.PATH).
	_carve_shape_mask()
	# Après la forme ET le lac : les deux peuvent isoler des îlots marchables.
	_seal_orphan_pockets()
	if theme == MapTheme.VILLAGE:
		_place_houses()
	_apply_to_tilemap()
	_gen_tall_grass()
	_gen_leaf_litter()
	_gen_decorations()
	_place_chest_gated()
	# Le placement du coffre peut creuser une nouvelle douve (île CS Surf) —
	# rejoue les jointures boue/eau pour qu'elle s'intègre proprement.
	if theme == MapTheme.SWAMP:
		_apply_blob(_ground, tile_sol_boueux - Vector2i(1, 1),
			func(t: int) -> bool: return t != Terrain.WATER and t != Terrain.PATH)
		_apply_blob(_water, tile_eau_sale - Vector2i(1, 1),
			func(t: int) -> bool: return t == Terrain.WATER)
	# Pont du lac : passe de nettoyage FINALE — quoi qu'aient posé les décors,
	# coffres ou douves, on garantit un passage dégagé et marchable vers l'île.
	if theme == MapTheme.LAKE:
		_clear_bridge_obstructions()
	_compute_reachable()
	_clear_portal_zones()
	_objects.y_sort_enabled = true
	_compute_height_field()
	print("MapGenerator: génération terminée.")
	if OS.get_cmdline_user_args().has("dump_map"):
		_debug_dump_grid()
	_refresh_render3d()


## DEBUG (--  dump_map) : silhouette de la zone en ASCII dans la console.
func _debug_dump_grid() -> void:
	var walk := 0
	var lines := "\nDUMP forme=%s taille=%s\n" % [MapShape.keys()[_map_shape], map_size]
	for r in map_size.y:
		var line := ""
		for c in map_size.x:
			match _grid[r][c]:
				Terrain.TREE:  line += "#"
				Terrain.WATER: line += "~"
				Terrain.PATH:  line += "+"; walk += 1
				_:             line += "."; walk += 1
		lines += line + "\n"
	print(lines + "marchable=%d/%d (%d%%)" % [
		walk, map_size.x * map_size.y, walk * 100 / (map_size.x * map_size.y)])


## ─────────────────────────────────────────────────────────────────
## ARÈNE — petite salle fermée de falaises (grotte de demi-boss)
## ─────────────────────────────────────────────────────────────────

func _generate_arena() -> void:
	map_size     = arena_size
	theme        = MapTheme.ROCKY
	random_theme = false
	gating_type  = GatingType.NONE
	_apply_theme()
	_compute_portals()

	var W := map_size.x
	var H := map_size.y
	print("MapGenerator: ARÈNE  taille=%s" % map_size)

	_init_grid()

	# Sol rocheux partout
	for r in H:
		for c in W:
			_ground.set_cell(Vector2i(c, r), source_id, _ground_tile)

	# Murs de falaise (2 cases d'épaisseur) tout autour
	var cliff_center := tile_cliff_origin + Vector2i(1, 1)   # (53,33)
	for r in H:
		for c in W:
			if c < 2 or c >= W - 2 or r < 2 or r >= H - 2:
				_objects.set_cell(Vector2i(c, r), source_id, cliff_center)
				_grid[r][c] = Terrain.TREE
	# Volumes 3D correspondants : anneau décomposé en 4 rectangles de hauteur
	# uniforme — une grotte fermée doit avoir des parois régulières.
	var arena_wall_h := 2.4
	for rect: Rect2i in [
		Rect2i(0, 0, W, 2),                  # haut
		Rect2i(0, H - 2, W, 2),              # bas
		Rect2i(0, 2, 2, H - 4),              # gauche
		Rect2i(W - 2, 2, 2, H - 4),          # droite
	]:
		_cliff_formations.append({"rect": rect, "height": arena_wall_h, "cave": false})

	# Couverture centrale : rochers/gros cailloux (évite l'entrée et le centre).
	# PAS dans une MAISON (village) : le décor y est du mobilier (caisses,
	# tapis…), pas des rochers — cf. MapRender3D._build_house_interior.
	var center := Vector2i(W / 2, H / 2)
	var cover: Array[Vector2i] = []
	if interior_style != "house":
		for r in range(4, H - 4):
			for c in range(4, W - 4):
				var cell := Vector2i(c, r)
				if _cell_dist(cell, entry_tile) < 5: continue
				if _cell_dist(cell, center) < 4:     continue
				cover.append(cell)
	_seeded_shuffle(cover)
	var placed := 0
	for cell: Vector2i in cover:
		if placed >= 6: break
		if _objects.get_cell_source_id(cell) != -1: continue
		if _rng.randf() < 0.5 and _can_place_block(cell, 2, 2):
			for dy in 2:
				for dx in 2:
					_objects.set_cell(cell + Vector2i(dx, dy), source_id,
						tile_gros_caillou_orig + Vector2i(dx, dy))
		else:
			_objects.set_cell(cell, source_id,
				tiles_cailloux[_rng.randi() % tiles_cailloux.size()])
		placed += 1

	_compute_reachable()
	_objects.y_sort_enabled = true
	print("MapGenerator: arène générée.")
	_refresh_render3d()


## ─────────────────────────────────────────────────────────────────
## 0 — THÈME
## ─────────────────────────────────────────────────────────────────

func _apply_theme() -> void:
	if random_theme:
		# En jeu : la suite des biomes est pilotée par RunManager (enchaînement
		# logique par profondeur). En éditeur (aperçu) : tirage aléatoire.
		if not Engine.is_editor_hint():
			theme = RunManager.inst().current_biome()
		else:
			theme = [MapTheme.FOREST, MapTheme.SWAMP, MapTheme.MEADOW, MapTheme.ROCKY, MapTheme.AUTUMN, MapTheme.LAKE, MapTheme.VOLCANO, MapTheme.VILLAGE][_rng.randi() % 8]
	var cfg := _theme_config(theme)
	_ground_tile    = cfg["ground_tile"]
	# Palette de sol : par défaut le seul sol principal (sol uni, comportement
	# d'origine) — un biome n'a de sol composite que s'il déclare "ground_tiles".
	_ground_tiles.assign(cfg.get("ground_tiles", [cfg["ground_tile"]]))
	_water_tile     = cfg["water_tile"]
	_path_tiles.assign(cfg["path_tiles"])   # Array générique → Array[Vector2i]
	_tree_origins   = cfg["tree_origins"]
	_tg_threshold   = cfg["tg_threshold"]
	tree_density    = cfg["tree_density"]
	water_threshold = cfg["water_threshold"]
	min_water_pools = cfg["min_water_pools"]
	flower_density  = cfg["flower_density"]
	path_width      = cfg["path_width"]
	# "deep" (LAKE, seule eau qui bloque/gate) / "shallow" (FOREST, SWAMP —
	# flaques marchables, sans collision) / "none" (MEADOW/ROCKY/AUTUMN — pas
	# d'eau du tout) — retour joueurs : l'eau profonde partout cassait le
	# rythme hors du biome Lac.
	_water_mode = cfg.get("water_mode", "deep")
	pool_radius = cfg.get("pool_radius", Vector2i(3, 2))
	height_amplitude = cfg.get("height_amp", 0.55)
	height_terrace   = cfg.get("height_terrace", 0.0)
	# VARIATION intra-biome : un acte enchaîne 5+ salles du MÊME biome —
	# chaque salle jitterle ses densités (par graine) pour que deux forêts
	# consécutives ne se ressemblent pas (clairsemée, touffue, marécageuse…).
	tree_density    *= _rng.randf_range(0.65, 1.45)
	flower_density  *= _rng.randf_range(0.5, 1.6)
	# Borne basse à 0.32 et non 0.5 : l'ancien clamp ÉCRASAIT toute config de
	# biome sous 0.5 — le marécage (0.47) recevait moins d'eau que configuré,
	# silencieusement, depuis le début.
	water_threshold  = clampf(water_threshold + _rng.randf_range(-0.05, 0.04), 0.32, 0.95)
	if random_gating:
		gating_type = cfg["gating"]
	print("MapGenerator: thème=%s  gating=%s" % [
		MapTheme.keys()[theme], GatingType.keys()[gating_type]])


func _theme_config(t: MapTheme) -> Dictionary:
	match t:
		MapTheme.FOREST:
			return {
				"ground_tile": tile_grass,
				"ground_tiles": [tile_grass, tile_herbe_dense, tile_herbe_pale],
				"water_tile":   tile_water,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_sapin_origin, tile_tree_origin],
				"tree_density":    0.50,
				"water_threshold": 0.62,
				"min_water_pools": 1,
				"tg_threshold":    0.42,
				"flower_density":  0.03,
				"path_width":      3,
				"height_amp":      0.80,   # sous-bois vallonné
				"gating":          GatingType.COUPE,
				"water_mode":      "shallow",
			}
		MapTheme.SWAMP:
			return {
				"ground_tile": tile_sol_boueux,
				# Boue + herbes malades : le sol composite vaut aussi ici — les
				# jointures 2D (_apply_blob) sont de toute façon recomposées au
				# bake par _blend_terrain_edges.
				"ground_tiles": [tile_sol_boueux, tile_herbe_seche, tile_terre_seche],
				"water_tile":   tile_eau_sale,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_arbre_mort_orig, tile_tree_origin],
				# Allégé par rapport à l'original : trop dense/obstrué, ne laissait
				# quasiment aucun espace marchable hors des 3 chemins principaux.
				"tree_density":    0.14,
				"water_threshold": 0.40,   # abaissé : de vraies étendues, pas des taches
				"min_water_pools": 6,
				"pool_radius":     Vector2i(6, 4),   # vraies étendues, pas des flaques de poche
				"tg_threshold":    0.52,
				"flower_density":  0.02,
				"path_width":      4,   # corridors plus larges — marécage plus praticable
				# Plus d'eau profonde en marécage (flaques marchables) → CS Surf
				# n'a plus lieu d'être ; Coupe-Brindille reste thématique.
				"height_amp":      0.18,   # plaine d'eau quasi étale
				"gating":          GatingType.COUPE,
				"water_mode":      "shallow",
			}
		MapTheme.MEADOW:
			return {
				"ground_tile": tile_grass,
				"ground_tiles": [tile_grass, tile_herbe_dense, tile_herbe_seche],
				"water_tile":   tile_water,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_tree_origin],
				"tree_density":    0.12,
				"water_threshold": 0.58,
				"min_water_pools": 1,
				"tg_threshold":    0.40,
				"flower_density":  0.16,
				"path_width":      3,
				"height_amp":      0.95,   # collines franches — LE biome des prairies ondulantes
				"gating":          GatingType.FORCE,
				"water_mode":      "none",
			}
		MapTheme.ROCKY:
			return {
				"ground_tile": tile_grass,
				"ground_tiles": [tile_grass, tile_terre_seche, tile_sable],
				"water_tile":   tile_water,
				# Chemin pierre — 8 variantes (bloc 2×4) tirées au hasard par
				# case pour casser la répétition d'une tuile unique.
				"path_tiles":   _stone_path_variants(),
				"tree_origins": [tile_tree_origin],
				"tree_density":    0.20,
				"water_threshold": 0.60,
				"min_water_pools": 1,
				"tg_threshold":    0.55,
				"flower_density":  0.02,
				"path_width":      3,
				"height_amp":      1.35,   # le plus accidenté, assorti aux falaises
				"height_terrace":  0.42,   # mesas — le lissage compresse la plage, pas plus de ±0.9 réel
				"gating":          GatingType.FORCE,
				"water_mode":      "none",
			}
		MapTheme.AUTUMN:
			return {
				# Automne : forêt claire aux feuillages orange (variantes _fall
				# du pack Kenney, cf. MapRender3D._kit_tree_pool), herbe dorée,
				# lumière rasante — cf. le preset BiomeAmbiance assorti.
				"ground_tile": tile_grass,
				"ground_tiles": [tile_grass, tile_herbe_seche, tile_terre_seche],
				"water_tile":   tile_water,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_tree_origin],
				"tree_density":    0.34,
				"water_threshold": 0.60,
				"min_water_pools": 1,
				"tg_threshold":    0.46,
				"flower_density":  0.06,
				"path_width":      3,
				"height_amp":      0.90,   # coteaux boisés
				"height_terrace":  0.30,   # coteaux en terrasses douces
				"gating":          GatingType.COUPE,
				"water_mode":      "none",
			}
		MapTheme.LAKE:
			return {
				# Lac : grand plan d'eau central (carvé par _carve_lake), rives
				# herbeuses, île reliée par un pont. Peu d'arbres pour dégager
				# la vue sur l'eau. Gating Surf (thématique).
				"ground_tile": tile_grass,
				# Sable dans la palette : les plages se forment naturellement là
				# où le bruit de sol l'emporte, souvent près des rives.
				"ground_tiles": [tile_grass, tile_herbe_pale, tile_sable],
				"water_tile":   tile_water,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_tree_origin],
				"tree_density":    0.10,
				"water_threshold": 0.72,   # quasi pas de mares de bruit — le lac suffit
				"min_water_pools": 0,
				"tg_threshold":    0.50,
				"flower_density":  0.05,
				"path_width":      3,
				"height_amp":      0.30,   # rives basses : l'eau doit rester le sujet
				"gating":          GatingType.SURF,
				"water_mode":      "deep",
			}
		MapTheme.VOLCANO:
			return {
				# Volcan : sol de cendre sombre, coulées de LAVE (rendues orange
				# émissif à la place de l'eau, cf. MapRender3D), arbres brûlés,
				# terrain chaotique. La lave bloque (deep) — brûlure au contact
				# gérée côté combat. Pas de Surf sur la lave (gating FORCE).
				"ground_tile": tile_sol_boueux,
				# Cendre : les variantes claires ressortent en nuances de gris
				# une fois passées sous la teinte sombre du sol (cf. MapRender3D).
				"ground_tiles": [tile_sol_boueux, tile_terre_seche, tile_sable],
				"water_tile":   tile_water,
				"path_tiles":   [tile_chemin_terre],
				"tree_origins": [tile_arbre_mort_orig],   # arbres morts/brûlés
				"tree_density":    0.22,
				"water_threshold": 0.50,   # coulées de lave bien présentes
				"min_water_pools": 3,
				"tg_threshold":    0.65,   # quasi pas de haute herbe
				"flower_density":  0.0,
				"path_width":      3,
				"height_amp":      1.15,   # flancs de volcan
				"height_terrace":  0.38,   # coulées en gradins
				"gating":          GatingType.FORCE,
				"water_mode":      "deep",
			}
		MapTheme.VILLAGE:
			return {
				# Village : pelouses + ROUTES PAVÉES (variantes de chemin pierre),
				# maisons procédurales (cf. _place_houses / MapRender3D), quelques
				# arbres ornementaux. Pas d'eau. Routes larges pour circuler entre
				# les bâtiments.
				"ground_tile": tile_grass,
				# Pelouses inégales + terre battue piétinée entre les maisons.
				"ground_tiles": [tile_grass, tile_herbe_dense, tile_terre_seche],
				"water_tile":   tile_water,
				"path_tiles":   _stone_path_variants(),
				"tree_origins": [tile_tree_origin],
				"tree_density":    0.06,
				"water_threshold": 0.99,   # aucune mare
				"min_water_pools": 0,
				"tg_threshold":    0.62,
				"flower_density":  0.10,
				"path_width":      4,       # rues larges
				"height_amp":      0.40,   # on bâtit sur du plat
				"gating":          GatingType.FORCE,
				"water_mode":      "none",
			}
	return {}


func _stone_path_variants() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in 4:
		for dx in 2:
			result.append(tile_chemin_pierre_orig + Vector2i(dx, dy))
	return result


## ─────────────────────────────────────────────────────────────────
## 1 — INIT
## ─────────────────────────────────────────────────────────────────

func _init_grid() -> void:
	var W := map_size.x
	var H := map_size.y
	_cliff_formations.clear()
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


## Marque toutes les cellules WATER générées comme "peu profondes" —
## conservent leur rendu/tuile eau, mais MapRender3D leur retire toute
## collision (cf. _build_water_collision) et _compute_reachable les traverse
## librement, comme une flaque marchable plutôt qu'un obstacle.
func _mark_shallow_water() -> void:
	for r in _grid.size():
		var row: PackedByteArray = _grid[r]
		for c in row.size():
			if row[c] == Terrain.WATER:
				_shallow_cells[Vector2i(c, r)] = true


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
	_seeded_shuffle(candidates)
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
		# Ellipse de rayon `pool_radius` (par biome — le marécage creuse GRAND,
		# cf. _theme_config) au lieu du 7×5 fixe : ses "mares" étaient des
		# flaques de poche (retour joueurs : « plus de zones d'eau et plus
		# grandes »).
		var prx := pool_radius.x
		var pry := pool_radius.y
		for dy in range(-pry, pry + 1):
			for dx in range(-prx, prx + 1):
				var fx := float(dx) / float(prx + 1)
				var fy := float(dy) / float(pry + 1)
				if fx * fx + fy * fy > 1.0: continue
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

## Mure tout ce qui est hors de la silhouette (cf. _outside_shape). Remplace
## l'ancien cadre rectangulaire de 4 cases, qui donnait à TOUTES les zones un
## contour extérieur parfaitement droit quelle que soit la forme tirée — le
## masque de forme ne rognait alors que l'intérieur, et la silhouette réelle
## restait un rectangle (retour joueurs : « trop carré »).
## Appelé AVANT _carve_paths : les chemins percent ensuite le mur pour rejoindre
## les portails, qui vivent sur le bord de la grille.
func _carve_border() -> void:
	for r in map_size.y:
		for c in map_size.x:
			if _outside_shape(c, r):
				_grid[r][c] = Terrain.TREE


## Tire la silhouette de la zone et prépare le bruit qui en déformera le bord.
## À appeler AVANT _carve_border (qui consomme _shape_sdf).
func _init_shape() -> void:
	# Le rectangle n'est plus qu'une silhouette parmi cinq (et même lui est
	# arrondi + ondulé) — retour joueurs : les zones étaient trop carrées.
	var roll := _rng.randf()
	if roll < 0.20:   _map_shape = MapShape.RECT
	elif roll < 0.45: _map_shape = MapShape.CIRCLE
	elif roll < 0.70: _map_shape = MapShape.L_SHAPE
	elif roll < 0.85: _map_shape = MapShape.HOURGLASS
	else:             _map_shape = MapShape.CRESCENT
	_shape_flip_x = _rng.randf() < 0.5
	_shape_flip_y = _rng.randf() < 0.5

	_shape_noise = FastNoiseLite.new()
	_shape_noise.seed = _rng.randi()
	_shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Basse fréquence = grandes ondulations (golfes et caps), pas un bord
	# grignoté case par case qui ressemblerait juste à du bruit.
	_shape_noise.frequency = 0.045
	_shape_noise.fractal_octaves = 3
	print("MapGenerator: forme=%s" % MapShape.keys()[_map_shape])


## La case (c,r) est-elle EN DEHORS de la zone jouable ?
## Deux conditions : le cadre dur de 3 cases (garantit qu'aucune case marchable
## ne touche le bord de la grille, quel que soit le warp du bruit) et le champ
## de distance de la forme.
func _outside_shape(c: int, r: int) -> bool:
	if c < 3 or c >= map_size.x - 3 or r < 3 or r >= map_size.y - 3:
		return true
	return _shape_sdf(c, r) > 0.0


## Champ de distance signé de la silhouette, en coordonnées NORMALISÉES
## (u,v ∈ [-1,1] aux bords de la grille) : < 0 dedans, > 0 dehors. Le bruit est
## ajouté au résultat, ce qui décale le contour vers l'intérieur ou l'extérieur
## selon l'endroit — d'où des bords sinueux plutôt que des arcs parfaits.
func _shape_sdf(c: int, r: int) -> float:
	var u := (float(c) + 0.5 - float(map_size.x) * 0.5) / (float(map_size.x) * 0.5)
	var v := (float(r) + 0.5 - float(map_size.y) * 0.5) / (float(map_size.y) * 0.5)
	if _shape_flip_x: u = -u
	if _shape_flip_y: v = -v
	var p := Vector2(u, v)

	# Extents calibrés pour que le bord BRUITÉ tombe à l'intérieur du cadre dur
	# de 3 cases. Si la forme déborde du cadre, c'est le cadre qu'on voit sur
	# les flancs — donc une ligne parfaitement droite, exactement le défaut
	# qu'on cherche à supprimer. Ne pas gonfler ces valeurs sans revérifier.
	var d := 0.0
	match _map_shape:
		MapShape.RECT:
			# Boîte aux coins TRÈS arrondis — plus proche du galet que du carré.
			d = _round_box(p, Vector2(0.44, 0.36), 0.36)
		MapShape.CIRCLE:
			# Ellipse inscrite (la grille étant large, un "cercle" normalisé
			# donne un disque étiré, ce qui remplit correctement la zone).
			d = p.length() - 0.82
		MapShape.L_SHAPE:
			# Deux barres épaisses en équerre : l'union de leurs SDF donne un L
			# dont l'angle rentrant est arrondi, pas un coin net.
			d = minf(
				_round_box(p - Vector2(-0.38, 0.0), Vector2(0.20, 0.52), 0.24),
				_round_box(p - Vector2(0.0, 0.34), Vector2(0.52, 0.18), 0.24))
		MapShape.HOURGLASS:
			# Sablier : la demi-largeur croît avec |v| → étranglement au centre,
			# qui force le joueur à passer par un goulet.
			d = maxf(absf(u) - (0.28 + 0.52 * absf(v)), absf(v) - 0.78)
		MapShape.CRESCENT:
			# Disque moins un disque décalé sur le côté : un croissant. Le trou
			# est latéral (jamais en haut/bas) pour ne pas isoler les portails,
			# qui vivent sur les bords haut et bas de la grille.
			d = maxf(p.length() - 0.84,
				-(p - Vector2(0.58, 0.0)).length() + 0.46)

	return d + _shape_noise.get_noise_2d(float(c), float(r)) * 0.16


## Dispose des MAISONS (biome Village) : rectangles posés sur des zones
## d'herbe, JAMAIS sur un chemin (les rues doivent rester dégagées), avec une
## marge entre bâtiments et loin des portails. Les cases sont marquées TREE
## (bloquantes/pas de spawn) mais sans tuile d'objet — le rendu s'en charge.
func _place_houses() -> void:
	_village_houses.clear()
	var W := map_size.x
	var H := map_size.y
	var target := clampi((W * H) / 130, 4, 12)
	var attempts := 0
	while _village_houses.size() < target and attempts < target * 40:
		attempts += 1
		var bw := _rng.randi_range(4, 6)
		var bd := _rng.randi_range(4, 5)
		var ox := _rng.randi_range(4, W - 5 - bw)
		var oy := _rng.randi_range(4, H - 5 - bd)
		var rect := Rect2i(ox, oy, bw, bd)
		if not _house_area_free(rect):
			continue
		# Doit border une rue (au moins une case PATH dans l'anneau autour) —
		# une maison inaccessible depuis la route n'a pas de sens.
		if not _house_touches_road(rect):
			continue
		for r in range(oy, oy + bd):
			for c in range(ox, ox + bw):
				_grid[r][c] = Terrain.TREE
		_village_houses.append(rect)


## Emprise + marge de 1 case entièrement en herbe (ni chemin, ni autre
## maison, ni bord, ni portail).
func _house_area_free(rect: Rect2i) -> bool:
	var W := map_size.x
	var H := map_size.y
	for r in range(rect.position.y - 1, rect.end.y + 1):
		for c in range(rect.position.x - 1, rect.end.x + 1):
			if c < 3 or c >= W - 3 or r < 3 or r >= H - 3:
				return false
			if _grid[r][c] != Terrain.GRASS:
				return false
			if _is_near_portal(c, r, 5):
				return false
	return true


func _house_touches_road(rect: Rect2i) -> bool:
	var W := map_size.x
	var H := map_size.y
	for r in range(rect.position.y - 2, rect.end.y + 2):
		for c in range(rect.position.x - 2, rect.end.x + 2):
			if c < 0 or c >= W or r < 0 or r >= H:
				continue
			if _grid[r][c] == Terrain.PATH:
				return true
	return false


## Mure les poches marchables coupées du reste de la zone. Les silhouettes
## concaves (croissant surtout) découpent des îlots isolés dans les golfes du
## bord bruité : sans ça, on voit des clairières inatteignables au loin, et
## _get_walkable_cells pourrait y poser un coffre ou un obstacle CS.
##
## Le remplissage traverse l'EAU (elle n'est pas Terrain.TREE) : les îles
## accessibles seulement à la nage sont VOULUES (gating CS Surf, cf. le biome
## Lac) et ne doivent surtout pas être murées.
func _seal_orphan_pockets() -> void:
	var reached: Dictionary = {}
	var stack: Array[Vector2i] = [entry_tile]
	reached[entry_tile] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.x >= map_size.x or nb.y < 0 or nb.y >= map_size.y:
				continue
			if reached.has(nb) or _grid[nb.y][nb.x] == Terrain.TREE:
				continue
			reached[nb] = true
			stack.append(nb)

	var sealed := 0
	for r in map_size.y:
		for c in map_size.x:
			if _grid[r][c] == Terrain.TREE:
				continue
			if reached.has(Vector2i(c, r)):
				continue
			_grid[r][c] = Terrain.TREE
			sealed += 1
	if sealed > 0:
		print("MapGenerator: %d cases de poches isolées murées." % sealed)


## SDF d'une boîte aux coins arrondis (demi-extents `half`, rayon `rad`).
## Formule standard : distance au rectangle rétréci de `rad`, moins `rad`.
func _round_box(p: Vector2, half: Vector2, rad: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
		+ minf(maxf(q.x, q.y), 0.0) - rad


## Re-mure ce qui est hors silhouette APRÈS le tracé des chemins et le carvage
## du lac, qui peuvent avoir rouvert des cases hors forme. Épargne les chemins
## déjà tracés (sinon on couperait la route vers une sortie), l'eau, et un rayon
## de sécurité autour des portails.
func _carve_shape_mask() -> void:
	for r in map_size.y:
		for c in map_size.x:
			if _grid[r][c] == Terrain.PATH or _grid[r][c] == Terrain.WATER: continue
			if _is_near_portal(c, r, 6): continue
			if _outside_shape(c, r):
				_grid[r][c] = Terrain.TREE


## ─────────────────────────────────────────────────────────────────
## 5 — CHEMINS (BFS + waypoints pour casser le motif trident)
## ─────────────────────────────────────────────────────────────────

func _carve_paths() -> void:
	# Chemins COURBES (splines Catmull-Rom) qui serpentent, à largeur variable
	# et bords irréguliers — cf. _build_path_curve/_carve_curved_path. Étendu
	# du seul essai Forêt à TOUS les biomes (style "aucun côté rectiligne").
	for ex: Vector2i in [exit_A, exit_B, exit_C]:
		_carve_curved_path(_build_path_curve(Vector2(entry_tile), Vector2(ex)))


## Spline lisse entre `from` et `to` (coordonnées de cases), via des waypoints
## intermédiaires décalés PERPENDICULAIREMENT à l'axe — donne un tracé qui
## serpente naturellement au lieu d'un couloir droit. Tangentes Catmull-Rom
## (moyenne des voisins) pour une courbe continue sans cassure.
## Longueur (en cases) du tronçon d'approche RECTILIGNE devant chaque portail.
const PORTAL_APPROACH := 5.0

func _build_path_curve(from: Vector2, to: Vector2) -> Curve2D:
	# ANCRES D'APPROCHE : le chemin doit aborder les portails perpendiculairement
	# au bord de la map. Sans elles, le serpentin arrivait au portail sous un
	# angle quelconque, alors que le sentier prolongé au-delà (cf.
	# BiomeAmbiance._build_exit_trails) est une bande droite en Z : les deux ne
	# se raccordaient pas, et l'allée se lisait comme cassée en deux (retour
	# joueurs). Les portails sont sur les rangées 0 (sorties) et H-5 (entrée),
	# d'où une approche verticale.
	var from_a := from + Vector2(0.0, -PORTAL_APPROACH)   # on quitte l'entrée vers le nord
	var to_a   := to   + Vector2(0.0,  PORTAL_APPROACH)   # on aborde la sortie par le sud

	# Le serpentin ne court qu'ENTRE les ancres — les tronçons d'approche
	# restent droits.
	var seg_len := from_a.distance_to(to_a)
	var dir  := (to_a - from_a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var n := clampi(int(seg_len / 12.0), 2, 5)   # + de waypoints = + sinueux

	var pts: Array[Vector2] = [from, from_a]
	for i in range(1, n + 1):
		var t := float(i) / float(n + 1)
		var amp := _rng.randf_range(-1.0, 1.0) * seg_len * 0.16   # amplitude du serpentin
		pts.append(from_a.lerp(to_a, t) + perp * amp)
	pts.append(to_a)
	pts.append(to)

	var curve := Curve2D.new()
	curve.bake_interval = 0.5   # échantillonnage dense → pas de trous au stamp
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var tang := (next - prev) * 0.25            # tangente Catmull-Rom
		curve.add_point(pts[i], -tang, tang)
	return curve


## Rastérise une spline dans _grid en PATH, avec largeur qui "respire" le long
## du tracé et bords déchiquetés (bruit) — plus de corridor à largeur constante
## et bord net. Stampe le long des points bakés (denses), donc pas de SDF O(n²).
func _carve_curved_path(curve: Curve2D) -> void:
	var W := map_size.x
	var H := map_size.y
	var edge_noise := FastNoiseLite.new()
	edge_noise.frequency = 0.12
	edge_noise.seed = _rng.randi()

	var base_w := maxf(1.6, float(path_width) * 0.7)
	for p: Vector2 in curve.get_baked_points():
		var width := base_w + edge_noise.get_noise_2d(p.x, p.y) * 1.4
		var wi := int(ceil(width)) + 1
		var pc := Vector2i(int(p.x), int(p.y))
		for dy in range(-wi, wi + 1):
			for dx in range(-wi, wi + 1):
				var cell := pc + Vector2i(dx, dy)
				if cell.x < 2 or cell.x >= W - 2 or cell.y < 2 or cell.y >= H - 2:
					continue
				# Bord irrégulier : rayon perturbé par un bruit local haute freq.
				var edge := edge_noise.get_noise_2d(cell.x * 3.0, cell.y * 3.0) * 0.9
				if p.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) < width + edge:
					# Eau MARCHABLE (Forêt/Marécage) : le chemin passe À GUÉ au
					# lieu de la combler — le tracé restait la 1re cause de
					# disparition des mares (la moitié des cases d'eau du
					# marécage y passait, mesuré à la sonde). La connexité ne
					# souffre pas : ces cases se traversent à pied.
					if _water_mode == "shallow" and _grid[cell.y][cell.x] == Terrain.WATER:
						continue
					_grid[cell.y][cell.x] = Terrain.PATH


## ─────────────────────────────────────────────────────────────────
## 5b — LAC (biome LAKE) : grand plan d'eau central + île + pont
## ─────────────────────────────────────────────────────────────────

## Creuse un grand lac elliptique au centre, une île marchable au milieu, et
## un pont (corridor marchable de 2 cases) reliant la rive sud à l'île. Les
## rives latérales restent en terre ferme : on contourne le lac pour rejoindre
## les sorties nord. Appelé après _carve_paths (le lac prime sur les chemins).
func _carve_lake() -> void:
	_bridge_cells.clear()
	var W := map_size.x
	var H := map_size.y
	var cx := float(W) * 0.5
	var cy := float(H) * 0.5
	var lake_rx := float(W) * 0.30
	var lake_rz := float(H) * 0.30
	var isle_rx := maxf(3.0, float(W) * 0.06)
	var isle_rz := maxf(2.5, float(H) * 0.06)

	for r in range(5, H - 5):
		for c in range(5, W - 5):
			if _is_near_portal(c, r, 5):
				continue
			var dx := (float(c) + 0.5 - cx) / lake_rx
			var dz := (float(r) + 0.5 - cy) / lake_rz
			if dx * dx + dz * dz > 1.0:
				continue
			# Île centrale = terre ferme
			var idx := (float(c) + 0.5 - cx) / isle_rx
			var idz := (float(r) + 0.5 - cy) / isle_rz
			if idx * idx + idz * idz <= 1.0:
				_grid[r][c] = Terrain.GRASS
			else:
				_grid[r][c] = Terrain.WATER

	# Pont : corridor marchable de 2 cases de large, de l'île vers la rive sud
	var bx := int(cx)
	for r in range(int(cy), H - 5):
		var dx := (float(bx) + 0.5 - cx) / lake_rx
		var dz := (float(r) + 0.5 - cy) / lake_rz
		var over_water := dx * dx + dz * dz <= 1.0
		for w in 2:
			var col: int = bx + w
			if col < 3 or col >= W - 3:
				continue
			if _grid[r][col] == Terrain.WATER:
				_grid[r][col] = Terrain.GRASS
				if over_water:
					_bridge_cells.append(Vector2i(col, r))
		# Sorti du lac par le sud → pont terminé
		if not over_water and r > int(cy):
			break
	_rebuild_bridge_set()


## Cases du pont (planches 3D par MapRender3D) — API publique.
func get_bridge_cells() -> Array:
	return _bridge_cells


## Lookup O(1) : cette case fait-elle partie du pont ? Sert à interdire tout
## objet (rondin, rocher, souche…) dessus — sinon un décor bloquant peut
## barrer l'unique passage vers l'île. Reconstruit à chaque _carve_lake.
var _bridge_set: Dictionary = {}

func _is_bridge_cell(cell: Vector2i) -> bool:
	return _bridge_set.has(cell)

func _rebuild_bridge_set() -> void:
	_bridge_set.clear()
	for cell: Vector2i in _bridge_cells:
		_bridge_set[cell] = true


## Rend chaque case de pont dégagée et marchable : retire tout objet/eau,
## repose le sol d'herbe et marque la case GRASS. Appelée en toute fin de
## génération pour survivre aux placements ultérieurs (coffres, douves…).
func _clear_bridge_obstructions() -> void:
	for cell: Vector2i in _bridge_cells:
		_objects.erase_cell(cell)
		_water.erase_cell(cell)
		_ground.set_cell(cell, source_id, _ground_tile)
		if cell.y >= 0 and cell.y < _grid.size() and cell.x >= 0 and cell.x < _grid[cell.y].size():
			_grid[cell.y][cell.x] = Terrain.GRASS


## ─────────────────────────────────────────────────────────────────
## 6 — GRILLE → TILEMAPLAYERS
## ─────────────────────────────────────────────────────────────────

func _apply_to_tilemap() -> void:
	var W := map_size.x
	var H := map_size.y
	for r in H:
		for c in W:
			# Emprises de maisons (village) : cases marquées TREE pour bloquer
			# spawn/herbe/décor, mais SANS y stamper d'arbre (le bâtiment les
			# recouvre) — sinon des arbres poussent dans les maisons.
			if _grid[r][c] == Terrain.TREE and not _cell_in_house(c, r) and _can_stamp_tree(c, r):
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
					_water.set_cell(cell, source_id, _water_tile)
				Terrain.PATH:
					_ground.set_cell(cell, source_id, _path_tiles[_rng.randi() % _path_tiles.size()])
				_:
					if _ground.get_cell_source_id(cell) == -1:
						_ground.set_cell(cell, source_id, _ground_tile)

	# Marécage : jointures centre+bords entre boue/eau sale et le reste du
	# terrain — sinon la tuile centre plaquée partout fait une coupure nette
	# moche aux bords de l'eau et des chemins.
	if theme == MapTheme.SWAMP:
		_apply_blob(_ground, tile_sol_boueux - Vector2i(1, 1),
			func(t: int) -> bool: return t != Terrain.WATER and t != Terrain.PATH)
		_apply_blob(_water, tile_eau_sale - Vector2i(1, 1),
			func(t: int) -> bool: return t == Terrain.WATER)


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


# Override de MapBase._stamp_tree — pose aussi le sol sous l'arbre.
# L'origine 3×3 est tirée au hasard parmi les arbres du thème.
func _stamp_tree(cx: int, cy: int) -> void:
	var origin: Vector2i = _tree_origins[_rng.randi() % _tree_origins.size()]
	for dy in 3:
		for dx in 3:
			_ground.set_cell(Vector2i(cx + dx, cy + dy), source_id, _ground_tile)
	for dy in 3:
		for dx in 3:
			_objects.set_cell(
				Vector2i(cx + dx, cy + dy),
				source_id,
				origin + Vector2i(dx, dy)
			)


## ─────────────────────────────────────────────────────────────────
## 7 — HAUTE HERBE
## ─────────────────────────────────────────────────────────────────

func _gen_tall_grass() -> void:
	_tg_cells.clear()
	# EXCLUSIVES À LA PRAIRIE : c'est SA mécanique de terrain. Avant, toutes les
	# zones en avaient, ce qui n'avantageait que l'IA (ennemis embusqués) sans
	# rien apporter au joueur, et privait la prairie de toute identité. Chaque
	# biome a désormais sa propre mécanique (boue du marécage, troncs de la
	# forêt, pièges sous les feuilles d'automne…).
	if theme != MapTheme.MEADOW:
		return
	# PEU de nappes mais GROSSES (9-14 cases chacune) : des zones de
	# furtivité franches et lisibles, pas un saupoudrage de touffes isolées.
	# Croissance organique par frontière aléatoire depuis une graine.
	var W := map_size.x
	var H := map_size.y
	# _tg_threshold module le nombre de nappes par biome (seuil bas = biome
	# herbeux = un peu plus de nappes).
	var patches := clampi(int(float(W * H) / 550.0 * (1.45 - _tg_threshold)), 3, 7)
	for p in patches:
		var start := Vector2i(-1, -1)
		for attempt in 40:
			var cand := Vector2i(_rng.randi_range(5, W - 6), _rng.randi_range(5, H - 6))
			if _tg_cell_ok(cand):
				start = cand
				break
		if start == Vector2i(-1, -1):
			continue
		var target := _rng.randi_range(9, 14)
		var placed: Dictionary = {start: true}
		var frontier: Array[Vector2i] = [start]
		_tall_grass.set_cell(start, source_id, tile_tg)
		_tg_cells.append(start)
		while placed.size() < target and not frontier.is_empty():
			var base: Vector2i = frontier[_rng.randi() % frontier.size()]
			var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			_seeded_shuffle(dirs)
			var grown := false
			for d: Vector2i in dirs:
				var nb: Vector2i = base + d
				if placed.has(nb) or not _tg_cell_ok(nb):
					continue
				placed[nb] = true
				frontier.append(nb)
				_tall_grass.set_cell(nb, source_id, tile_tg)
				_tg_cells.append(nb)
				grown = true
				break
			if not grown:
				frontier.erase(base)


## Jonche le sol de feuilles (Automne) et arme un collet sous certaines.
## Bruit basse fréquence plutôt que nappes en blob (cf. _gen_tall_grass) : on
## veut un TAPIS étendu et irrégulier — des amas nets se contourneraient, ce qui
## viderait la mécanique de son sens.
func _gen_leaf_litter() -> void:
	_leaf_cells.clear()
	_leaf_traps.clear()
	if theme != MapTheme.AUTUMN:
		return

	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.11
	var candidates: Array[Vector2i] = []
	for r in range(3, map_size.y - 3):
		for c in range(3, map_size.x - 3):
			if _grid[r][c] != Terrain.GRASS:
				continue          # ni chemin (il doit rester lisible), ni eau, ni arbre
			if _is_near_portal(c, r, 5):
				continue          # pas de piège à l'arrivée/au départ : injouable
			if noise.get_noise_2d(float(c), float(r)) < -0.05:
				continue
			var cell := Vector2i(c, r)
			_leaf_cells[cell] = true
			candidates.append(cell)

	# Pièges tirés au sort dans le tapis, via le RNG SEEDÉ (et non .shuffle(),
	# qui utilise le RNG global du moteur) : les mêmes collets doivent être aux
	# mêmes cases sur tous les pairs en multijoueur.
	_seeded_shuffle(candidates)
	var n := int(float(candidates.size()) * LEAF_TRAP_RATIO)
	for i in mini(n, candidates.size()):
		_leaf_traps[candidates[i]] = true
	print("MapGenerator: tapis de feuilles — %d cases, %d collets." % [
		_leaf_cells.size(), _leaf_traps.size()])


## Une case peut-elle accueillir de la haute herbe ?
func _tg_cell_ok(cell: Vector2i) -> bool:
	if cell.x < 4 or cell.x >= map_size.x - 4 or cell.y < 4 or cell.y >= map_size.y - 4:
		return false
	if _grid[cell.y][cell.x] != Terrain.GRASS:
		return false
	if _objects.get_cell_source_id(cell) != -1:
		return false
	if _water.get_cell_source_id(cell) != -1:
		return false
	if _is_near_portal(cell.x, cell.y, 5):
		return false
	return not _is_bridge_cell(cell)


## ─────────────────────────────────────────────────────────────────
## 8 — DÉCORATIONS (override de MapBase._gen_decorations)
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
			if _is_bridge_cell(cell):                      continue   # rien sur le pont
			var roll := _rng.randf()
			if roll < flower_density:
				_tall_grass.set_cell(cell, source_id, flowers[_rng.randi() % flowers.size()])
			elif roll < flower_density + herb_density:
				_tall_grass.set_cell(cell, source_id, tile_petite_herbe)
			elif roll < flower_density + herb_density + rock_density:
				_objects.set_cell(cell, source_id, tile_rocher)

	_gen_logs()
	_gen_theme_decorations()


## ── Décorations propres au thème ─────────────────────────────────
func _gen_theme_decorations() -> void:
	match theme:
		MapTheme.FOREST: _decor_forest()
		MapTheme.SWAMP:  _decor_swamp()
		MapTheme.ROCKY:  _decor_rocky()
		MapTheme.MEADOW: _decor_meadow()
		MapTheme.AUTUMN: _decor_forest()   # souches/champignons/affleurements — mêmes habitants qu'en forêt
		MapTheme.LAKE:   _decor_meadow()   # rives dégagées, quelques affleurements — la vedette est le lac


## Formations de falaise (variété procédurale : taille aléatoire, 9-slice) —
## réutilisé par TOUS les thèmes pour donner du relief même hors rocailleux
## (juste moins de formations, plus petites, sans grotte). `with_cave` :
## la première formation reçoit une entrée de grotte dans sa base.
func _place_cliff_outcrops(cells: Array, max_count: int, with_cave: bool,
		w_min: int, w_max: int, h_min: int, h_max: int) -> void:
	var placed := 0
	var cave_done := not with_cave
	for cell: Vector2i in cells:
		if placed >= max_count: break
		if _is_near_portal(cell.x, cell.y, 8): continue
		var w: int = _rng.randi_range(w_min, w_max)
		var h: int = _rng.randi_range(h_min, h_max)
		if not _can_place_block(cell, w, h): continue
		_place_cliff_rect(cell, w, h, not cave_done)
		cave_done = true
		placed += 1


func _decor_forest() -> void:
	var cells := _get_walkable_cells(5)
	_seeded_shuffle(cells)
	# Plus d'affleurements rocheux : les falaises sont la signature des biomes
	# Montagne/Volcan, partout ailleurs elles lisaient comme des blocs posés là
	# (retour joueurs — même décision que _decor_meadow).
	var stumps := [tile_souche_sombre, tile_souche_claire]
	var champi := 0
	var stump  := 0
	for cell: Vector2i in cells:
		if champi >= 12 and stump >= 14: break
		if _objects.get_cell_source_id(cell)    != -1: continue
		if _tall_grass.get_cell_source_id(cell) != -1: continue
		if _grid[cell.y][cell.x] == Terrain.PATH:      continue
		if _is_near_portal(cell.x, cell.y, 4):         continue
		var roll := _rng.randf()
		if champi < 12 and roll < 0.05 and _champi_fits(cell):
			# Champignon 3×1 vertical : base (4,14) → sommet (4,12)
			for k in 3:
				_objects.set_cell(cell + Vector2i(0, -k), source_id,
					tile_champi_origin + Vector2i(0, 2 - k))
			champi += 1
		elif stump < 14 and roll < 0.12:
			_objects.set_cell(cell, source_id, stumps[_rng.randi() % stumps.size()])
			stump += 1


func _decor_swamp() -> void:
	var cells := _get_walkable_cells(6)
	_seeded_shuffle(cells)
	# Pas de bancs rocheux : falaises réservées à Montagne/Volcan (cf. _decor_forest).

	var lily := tiles_nenuphars_fleur.duplicate()
	lily.append(tile_nenuphar)
	lily.append(tile_petit_nenuphar)
	for cell: Vector2i in _water.get_used_cells():
		if _objects.get_cell_source_id(cell) != -1: continue
		if _rng.randf() < 0.12:
			_objects.set_cell(cell, source_id, lily[_rng.randi() % lily.size()])

	# CHAMPIGNONS GÉANTS destructibles (mêmes tuiles/mécanique qu'en forêt :
	# billboard 1×3 enveloppé dans un BreakableProp par MapRender3D — secousse
	# à l'attaque, poof, collision libérée). Ils poussent où c'est humide : le
	# marécage en reçoit PLUS que la forêt (14 vs 12) et n'avait jusqu'ici
	# aucun décor destructible — que des nénuphars intouchables.
	var champi := 0
	for cell: Vector2i in cells:
		if champi >= 14: break
		if _objects.get_cell_source_id(cell) != -1: continue
		if _rng.randf() < 0.06 and _champi_fits(cell):
			for k in 3:
				_objects.set_cell(cell + Vector2i(0, -k), source_id,
					tile_champi_origin + Vector2i(0, 2 - k))
			champi += 1


	# ROSEAUX sur les berges : boue nue ADJACENTE à l'eau — c'est là que les
	# quenouilles poussent, et ça souligne le contour des mares. Cases choisies
	# au RNG seedé (identiques sur tous les pairs) ; le rendu 3D est fait par
	# MapRender3D._build_swamp_flora.
	_reed_cells.clear()
	for rcell: Vector2i in cells:
		if _reed_cells.size() >= 46: break
		if _objects.get_cell_source_id(rcell) != -1: continue
		if _grid[rcell.y][rcell.x] != Terrain.GRASS: continue
		var bank := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := rcell + d
			if nb.y >= 0 and nb.y < map_size.y and nb.x >= 0 and nb.x < map_size.x \
					and _grid[nb.y][nb.x] == Terrain.WATER:
				bank = true
				break
		if bank and _rng.randf() < 0.5:
			_reed_cells.append(rcell)


func _decor_meadow() -> void:
	# PAS de falaises : une prairie est une plaine. Les affleurements rocheux
	# posés ici se lisaient comme de gros blocs beiges plantés au milieu de
	# l'herbe (retour joueurs). Ils restent la signature du biome Rocailleux
	# (cf. _decor_rocky) — c'est ce qui distingue les deux.
	# Fleurs déjà denses via flower_density — pas d'autre décor thématique.
	pass


func _decor_rocky() -> void:
	var cells := _get_walkable_cells(7)
	_seeded_shuffle(cells)

	# 1) Falaises — formations rocheuses allongées (taille variable, 9-slice
	#    centre+bords). La première reçoit une entrée de grotte dans sa base.
	_place_cliff_outcrops(cells, 3, true, 3, 7, 3, 5)

	# 2) Gros cailloux 2×2 (parfois groupés en amas) + petits cailloux épars
	var small := 0
	var big   := 0
	for cell: Vector2i in cells:
		if small >= 26 and big >= 9: break
		if _objects.get_cell_source_id(cell)    != -1: continue
		if _tall_grass.get_cell_source_id(cell) != -1: continue
		if _grid[cell.y][cell.x] == Terrain.PATH:      continue
		if _is_near_portal(cell.x, cell.y, 4):         continue
		var roll := _rng.randf()
		if big < 9 and roll < 0.05 and _can_place_block(cell, 2, 2):
			for dy in 2:
				for dx in 2:
					_objects.set_cell(cell + Vector2i(dx, dy), source_id,
						tile_gros_caillou_orig + Vector2i(dx, dy))
			big += 1
			# Amas : tente un second gros caillou collé pour un bloc plus imposant
			var neighbor := cell + Vector2i(2, 0)
			if big < 9 and _rng.randf() < 0.4 and _can_place_block(neighbor, 2, 2):
				for dy in 2:
					for dx in 2:
						_objects.set_cell(neighbor + Vector2i(dx, dy), source_id,
							tile_gros_caillou_orig + Vector2i(dx, dy))
				big += 1
		elif small < 26 and roll < 0.14:
			_objects.set_cell(cell, source_id,
				tiles_cailloux[_rng.randi() % tiles_cailloux.size()])
			small += 1


## Pose une falaise rectangulaire w×h via 9-slice (coins/bords/centre tirés
## du bloc 3×3 d'atlas `tile_cliff_origin`). Permet des formations allongées
## bien plus grandes qu'un simple 3×3. Si `with_cave`, creuse une entrée de
## grotte (1×2) dans la colonne centrale de la base.
func _place_cliff_rect(top_left: Vector2i, w: int, h: int, with_cave: bool) -> void:
	for dy in h:
		var row_class: int = 0 if dy == 0 else (2 if dy == h - 1 else 1)
		for dx in w:
			var col_class: int = 0 if dx == 0 else (2 if dx == w - 1 else 1)
			_objects.set_cell(top_left + Vector2i(dx, dy), source_id,
				tile_cliff_origin + Vector2i(col_class, row_class))
	if with_cave:
		var mid := w / 2
		_objects.set_cell(top_left + Vector2i(mid, h - 2), source_id, tile_grotte_haut)
		_objects.set_cell(top_left + Vector2i(mid, h - 1), source_id, tile_grotte_bas)
	# Hauteur procédurale du volume 3D — variété par formation (cf. MapRender3D).
	# Une formation avec grotte reste au moins à 2.0 : garantit une arche
	# d'entrée sur 2 étages de blocs pleins (cf. MapRender3D._build_cliff_formations),
	# jamais un simple passage bas d'un seul bloc.
	_cliff_formations.append({
		"rect":   Rect2i(top_left, Vector2i(w, h)),
		"height": _rng.randf_range(2.0, 2.6) if with_cave else _rng.randf_range(1.5, 2.6),
		"cave":   with_cave,
	})


func _champi_fits(cell: Vector2i) -> bool:
	for k in range(1, 3):
		var c := cell + Vector2i(0, -k)
		if c.y < 4: return false
		if _objects.get_cell_source_id(c) != -1: return false
		if _water.get_cell_source_id(c)   != -1: return false
		if _grid[c.y][c.x] == Terrain.PATH: return false
	return true


func _can_place_block(cell: Vector2i, w: int, h: int) -> bool:
	var W := map_size.x
	var H := map_size.y
	for dy in h:
		for dx in w:
			var c := cell + Vector2i(dx, dy)
			if c.x < 4 or c.x >= W - 4 or c.y < 4 or c.y >= H - 4: return false
			if _grid[c.y][c.x] == Terrain.PATH:  return false   # ne bloque pas un chemin
			if _objects.get_cell_source_id(c) != -1: return false
			if _water.get_cell_source_id(c)   != -1: return false
			if _ground.get_cell_source_id(c)  == -1: return false
	return true


# Override de MapBase._gen_logs — positions aléatoires.
func _gen_logs() -> void:
	var candidates := _get_walkable_cells(6)
	_seeded_shuffle(candidates)
	var placed := 0
	for pos: Vector2i in candidates:
		if placed >= 4: break
		var right := pos + Vector2i(1, 0)
		if _is_bridge_cell(pos) or _is_bridge_cell(right): continue   # pas de rondin sur le pont
		if _objects.get_cell_source_id(pos)   != -1: continue
		if _objects.get_cell_source_id(right) != -1: continue
		if _water.get_cell_source_id(pos)     != -1: continue
		if _grid[pos.y][pos.x] == Terrain.PATH:        continue
		if right.x < map_size.x and _grid[right.y][right.x] == Terrain.PATH: continue
		_objects.set_cell(pos,   source_id, tile_rondin_g)
		_objects.set_cell(right, source_id, tile_rondin_d)
		placed += 1


## ─────────────────────────────────────────────────────────────────
## 9 — COFFRE AVEC GATING
## ─────────────────────────────────────────────────────────────────

func _place_chest_gated() -> void:
	# Entre 0 et 1 coffre par zone : ~1 zone sur 3 n'en a pas — la récompense
	# redevient un événement, pas un dû.
	if _rng.randf() < 0.35:
		return
	match gating_type:
		GatingType.NONE:  _place_chest_free()
		GatingType.SURF:  _place_chest_surf()
		GatingType.COUPE: _place_chest_coupe()
		GatingType.FORCE: _place_chest_force()


func _place_chest_free() -> void:
	var candidates := _get_walkable_cells(10)
	_seeded_shuffle(candidates)
	for cell: Vector2i in candidates:
		if _is_near_portal(cell.x, cell.y, 8): continue
		_objects.set_cell(cell, source_id, tile_chest_closed)
		return
	push_warning("MapGenerator: aucun emplacement pour coffre libre.")


## Île marchable de 6 cases (bloc 3×2) entourée d'une douve de 2 cases —
## assez grande pour se déplacer une fois arrivé à la nage, au lieu d'un
## coffre planté sur une tuile unique entourée d'eau de tous côtés.
const _ISLAND_CELLS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


func _place_chest_surf() -> void:
	_create_water_island_chest()


func _create_water_island_chest() -> void:
	var candidates := _get_walkable_cells(14)
	_seeded_shuffle(candidates)
	for center: Vector2i in candidates:
		if _is_near_portal(center.x, center.y, 10): continue
		if not _can_place_island(center): continue
		_carve_water_island(center)
		_objects.set_cell(center, source_id, tile_chest_closed)
		return
	_place_chest_free()


func _can_place_island(center: Vector2i) -> bool:
	var W := map_size.x
	var H := map_size.y
	for dy in range(-2, 4):
		for dx in range(-3, 4):
			var c := center + Vector2i(dx, dy)
			if c.x < 4 or c.x >= W - 4 or c.y < 4 or c.y >= H - 4: return false
	return true


func _carve_water_island(center: Vector2i) -> void:
	# 1) Douve : inonde toute la zone (île + marge)
	for dy in range(-2, 4):
		for dx in range(-3, 4):
			var cell := center + Vector2i(dx, dy)
			_water.set_cell(cell, source_id, _water_tile)
			_ground.erase_cell(cell)
			_objects.erase_cell(cell)
			_tall_grass.erase_cell(cell)
			_grid[cell.y][cell.x] = Terrain.WATER
	# 2) Recreuse l'île marchable (6 cases) par-dessus la douve
	for off: Vector2i in _ISLAND_CELLS:
		var cell := center + off
		_water.erase_cell(cell)
		_ground.set_cell(cell, source_id, _ground_tile)
		_grid[cell.y][cell.x] = Terrain.GRASS


## Arbre coupable 1×3 (haut → tronc) + alcôve scellée par des rochers sur
## les côtés et le fond — sinon le coffre est contournable sans jamais
## couper l'arbre. La seule issue est la colonne d'arbre.
## Variante SUD  (col 7) : coffre au nord, arbre au sud,  approche depuis le bas.
## Variante NORD (col 8) : coffre au sud,  arbre au nord, approche depuis le haut.
func _place_chest_coupe() -> void:
	var candidates := _get_walkable_cells(14)
	_seeded_shuffle(candidates)
	for chest: Vector2i in candidates:
		if _is_near_portal(chest.x, chest.y, 10): continue
		var tree_s: Array[Vector2i] = [chest + Vector2i(0, 1), chest + Vector2i(0, 2), chest + Vector2i(0, 3)]
		if _try_place_coupe_pocket(chest, tree_s, chest + Vector2i(0, 4), chest + Vector2i(0, -1), tile_coupe_gauche):
			return
		var tree_n: Array[Vector2i] = [chest + Vector2i(0, -3), chest + Vector2i(0, -2), chest + Vector2i(0, -1)]
		if _try_place_coupe_pocket(chest, tree_n, chest + Vector2i(0, -4), chest + Vector2i(0, 1), tile_coupe_droit):
			return
	_place_chest_free()


## Tente de sceller le coffre dans une alcôve : rochers sur les flancs et
## le fond, colonne d'arbre coupable (3 cases) comme seule issue vers
## `approach`. `tree_origin` choisit la variante d'art (sud/nord).
func _try_place_coupe_pocket(chest: Vector2i, tree_cells: Array[Vector2i],
		approach: Vector2i, back_wall: Vector2i, tree_origin: Vector2i) -> bool:
	var perp := Vector2i(1, 0)
	var flank_rows: Array[Vector2i] = [chest, back_wall]
	flank_rows.append_array(tree_cells)
	var wall_cells: Array[Vector2i] = []
	for row: Vector2i in flank_rows:
		wall_cells.append(row + perp)
		wall_cells.append(row - perp)

	if not _can_place_coupe_pocket(approach, tree_cells, wall_cells, back_wall):
		return false

	for cell: Vector2i in wall_cells:
		_clear_cell(cell)
		_objects.set_cell(cell, source_id, tile_rocher)
	_clear_cell(back_wall)
	_objects.set_cell(back_wall, source_id, tile_rocher)
	for i in 3:
		_clear_cell(tree_cells[i])
		_objects.set_cell(tree_cells[i], source_id, tree_origin + Vector2i(0, i))
	_clear_cell(chest)
	_objects.set_cell(chest, source_id, tile_chest_closed)
	_coupe_trees.append({"cells": tree_cells.duplicate(), "approach": approach})
	return true


func _can_place_coupe_pocket(approach: Vector2i, tree_cells: Array[Vector2i],
		wall_cells: Array[Vector2i], back_wall: Vector2i) -> bool:
	var W := map_size.x
	var H := map_size.y
	if approach.x < 5 or approach.x >= W - 5 or approach.y < 5 or approach.y >= H - 5:
		return false
	if _water.get_cell_source_id(approach)   != -1: return false
	if _objects.get_cell_source_id(approach) != -1: return false
	if _ground.get_cell_source_id(approach)  == -1: return false
	for cell: Vector2i in tree_cells:
		if cell.x < 5 or cell.x >= W - 5 or cell.y < 5 or cell.y >= H - 5: return false
		if _water.get_cell_source_id(cell) != -1: return false
	if back_wall.x < 5 or back_wall.x >= W - 5 or back_wall.y < 5 or back_wall.y >= H - 5:
		return false
	if _water.get_cell_source_id(back_wall) != -1: return false
	for cell: Vector2i in wall_cells:
		if cell.x < 5 or cell.x >= W - 5 or cell.y < 5 or cell.y >= H - 5: return false
		if _water.get_cell_source_id(cell) != -1: return false
	return true


func _place_chest_force() -> void:
	var candidates := _get_walkable_cells(10)
	_seeded_shuffle(candidates)
	for center: Vector2i in candidates:
		if _is_near_portal(center.x, center.y, 8): continue
		if not _can_place_ring(center, 1): continue
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var bcell := center + d
			_objects.set_cell(bcell, source_id, tile_boulder)
			_force_boulders[bcell] = center + d * 2
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
		var toff := _tree_offset(atlas)
		if toff != Vector2i(-1, -1):
			var top_left := c - toff
			for dy in 3:
				for dx in 3:
					_objects.erase_cell(top_left + Vector2i(dx, dy))
		else:
			_objects.erase_cell(c)
	_tall_grass.erase_cell(c)
	_water.erase_cell(c)
	if _ground.get_cell_source_id(c) == -1:
		_ground.set_cell(c, source_id, _ground_tile)


## ─────────────────────────────────────────────────────────────────
## API PUBLIQUE — ENNEMIS
## ─────────────────────────────────────────────────────────────────

func get_enemy_spawn_positions(count: int, player_pos: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var candidates := _get_walkable_cells(min_enemy_distance)
	_seeded_shuffle(candidates)
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
	# Emprise de maison (village) : TREE dans la grille sans tuile d'objet —
	# rien ne doit y spawn.
	if cell.y >= 0 and cell.y < _grid.size():
		var grow: PackedByteArray = _grid[cell.y]
		if cell.x >= 0 and cell.x < grow.size() and grow[cell.x] == Terrain.TREE:
			return false
	if not _reachable.get(cell, false):  return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _objects.get_cell_source_id(cell + Vector2i(dx, dy)) != -1:
				return false
	return true


## BFS 4-directions depuis l'entrée, bloqué uniquement par l'eau (seul
## terrain réellement infranchissable sans CS — les arbres ne bloquent
## que leur case de tronc, le reste de leur emprise est traversable).
## Toute case non atteinte est une île CS Surf ou une poche isolée :
## aucun ennemi ne doit y spawn (impossible à vaincre sans la CS).
func _compute_reachable() -> void:
	_reachable.clear()
	var W := map_size.x
	var H := map_size.y
	if entry_tile.x < 0 or entry_tile.x >= W or entry_tile.y < 0 or entry_tile.y >= H:
		return
	var queue: Array[Vector2i] = [entry_tile]
	_reachable[entry_tile] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n := cur + d
			if n.x < 0 or n.x >= W or n.y < 0 or n.y >= H: continue
			if n in _reachable: continue
			if _grid[n.y][n.x] == Terrain.WATER and not _shallow_cells.has(n): continue
			_reachable[n] = true
			queue.append(n)


## ─────────────────────────────────────────────────────────────────
## RELIEF — collines douces (bruit + lissage), plaqué à plat sous l'eau,
## les obstacles et les zones d'entrée/sortie. Purement du rendu/mouvement —
## ne touche pas à la grille Terrain ni au pathfinding (toujours en 2D X/Z).
## ─────────────────────────────────────────────────────────────────

## Amplitude de relief PAR BIOME (clé "height_amp" du _theme_config, repli sur
## la valeur historique 0.55). Chaque région a son modelé : la Montagne ondule
## fort, le marécage est une plaine d'eau quasi étale, le Lac garde des rives
## basses pour que l'eau reste lisible (retour joueurs : « plus de relief,
## sauf lac, plus ou moins selon le biome »).
var height_amplitude: float = 0.55
## Hauteur d'un PALIER de terrasse (0 = collines lisses, pas de paliers).
## Quantifie le relief en PLATEAUX plats reliés par de courtes rampes — le
## modelé "mesa" de la Montagne/du Volcan (retour joueurs : « du relief qui
## fait des plateformes en hauteur »). Les rampes restent franchissables :
## les personnages se collent au sol, pas de saut requis.
var height_terrace: float = 0.0
const HEIGHT_NOISE_FREQ    := 0.045  # basse fréquence → collines larges et douces
const HEIGHT_SMOOTH_PASSES := 2

## Hauteur du sol par case (0.0 = plat) — nul par défaut (arène : volontairement
## sans relief, terrain stable pour un combat de boss). Rempli par
## _compute_height_field() en fin de génération d'une map normale.
var _height_grid: Array = []   # Array[PackedFloat32Array]


func _compute_height_field() -> void:
	var W := map_size.x
	var H := map_size.y
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed       = _rng.randi()
	noise.frequency  = HEIGHT_NOISE_FREQ
	noise.domain_warp_enabled  = true
	noise.domain_warp_amplitude = 18.0
	noise.domain_warp_frequency = HEIGHT_NOISE_FREQ * 0.6

	# Second calque, très basse fréquence : porte le relief à grande échelle
	# (une colline ou un creux par map) sous le détail fin du calque
	# principal — sans ça, le bruit fractal donnait un relief "haché", des
	# bosses de taille uniforme, sans grandes formes qui structurent la map.
	var macro := FastNoiseLite.new()
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro.seed        = _rng.randi()
	macro.frequency   = HEIGHT_NOISE_FREQ * 0.28
	macro.fractal_octaves = 1

	var field: Array = []
	field.resize(H)
	for r in H:
		var row := PackedFloat32Array()
		row.resize(W)
		for c in W:
			if _is_height_flat_cell(c, r):
				row[c] = 0.0
				continue
			var detail := noise.get_noise_2d(float(c), float(r))
			var macro_h := macro.get_noise_2d(float(c), float(r))
			row[c] = (macro_h * 0.65 + detail * 0.35) * height_amplitude
		field[r] = row

	# Lissage (moyenne 3×3) — pentes douces façon collines, pas de bruit
	# haute fréquence — puis on reverrouille à plat les cases occupées/eau/
	# portails : jamais de dénivelé sous un obstacle ou une zone de passage.
	for i in HEIGHT_SMOOTH_PASSES:
		field = _smooth_height_field(field, W, H)
	# TERRASSEMENT (après lissage — avant, la moyenne 3×3 refondrait les
	# marches en pentes) : chaque hauteur est rabattue sur un palier, avec une
	# étroite bande de transition en S entre deux niveaux — plateaux plats,
	# rampes courtes et franchissables.
	if height_terrace > 0.0:
		for r in H:
			var row2: PackedFloat32Array = field[r]
			for c in W:
				var lvl := floorf(row2[c] / height_terrace)
				var frac := row2[c] / height_terrace - lvl
				row2[c] = (lvl + smoothstep(0.30, 0.70, frac)) * height_terrace
	for r in H:
		for c in W:
			if _is_height_flat_cell(c, r):
				field[r][c] = 0.0

	_height_grid = field
	if OS.get_cmdline_user_args().has("dump_map"):
		var levels: Dictionary = {}
		for r2 in H:
			for c2 in W:
				levels[snappedf(field[r2][c2], 0.05)] = levels.get(snappedf(field[r2][c2], 0.05), 0) + 1
		var ks := levels.keys()
		ks.sort()
		print("PROBE relief: %d niveaux distincts, min=%.2f max=%.2f" % [ks.size(), ks[0], ks[ks.size()-1]])


## Toute case occupée par un objet (falaise, arbre, rocher, chest…), sous
## l'eau, ou proche d'un portail/de l'entrée — reste toujours plate.
func _is_height_flat_cell(c: int, r: int) -> bool:
	if _grid[r][c] == Terrain.WATER:
		return true
	# PLUS de verrou générique sur les cases d'objet : il poinçonnait un
	# CRATÈRE à zéro sous chaque arbre/rocher — discret à amplitude 0.55,
	# il criblait les collines de trous dès qu'on l'a montée (retour joueurs :
	# « les collines ne sont pas lisses, on ne peut pas aller dessus »).
	# Les décors sont désormais POSÉS à la hauteur du terrain (cf. MapRender3D).
	# Restent plats : les FALAISES (architecture massive à parois verticales)
	# et les MAISONS du village (on ne bâtit pas sur un dévers).
	for f: Dictionary in _cliff_formations:
		if (f["rect"] as Rect2i).grow(1).has_point(Vector2i(c, r)):
			return true
	for hr: Rect2i in _village_houses:
		if hr.grow(1).has_point(Vector2i(c, r)):
			return true
	if _is_near_portal(c, r, 5):
		return true
	# Marge d'une case autour de l'eau : berge plate pour un raccord propre
	# avec les franges d'herbe posées sur le contour des mares (cf. MapRender3D).
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var ny := r + dy
			var nx := c + dx
			if ny < 0 or ny >= map_size.y or nx < 0 or nx >= map_size.x: continue
			if _grid[ny][nx] == Terrain.WATER: return true
	return false


func _smooth_height_field(src: Array, W: int, H: int) -> Array:
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


# Override de MapBase.get_height_at_cell — relief procédural par case.
func get_height_at_cell(cell: Vector2i) -> float:
	if _height_grid.is_empty(): return 0.0
	if cell.y < 0 or cell.y >= _height_grid.size(): return 0.0
	var row: PackedFloat32Array = _height_grid[cell.y]
	if cell.x < 0 or cell.x >= row.size(): return 0.0
	return row[cell.x]


# Override de MapBase.get_height_at_world — interpolation bilinéaire pour un
# suivi fluide du relief (acteurs/caméra), pas de "marches" entre les cases.
## Hauteur pour ANCRER un sprite billboard sans que le sol le rogne : max
## entre le sol sous les pieds et le sol vers la caméra (+Z), échantillonné sur
## ~1,4 u. Sur une pente montant vers la caméra, le mesh de sol devant le
## personnage passait DEVANT le bas du sprite (depth test) et le coupait
## (retour joueurs). En posant les pieds au niveau du sol le plus haut visible,
## le bas ne s'enfonce plus. Plat = identique à get_height_at_world (0 lift).
func ground_anchor_y(pos: Vector3) -> float:
	var h := get_height_at_world(pos)
	for dz in [0.7, 1.4]:
		h = maxf(h, get_height_at_world(pos + Vector3(0, 0, dz)))
	return h


func get_height_at_world(pos: Vector3) -> float:
	if _height_grid.is_empty(): return 0.0
	var H := _height_grid.size()
	var W: int = (_height_grid[0] as PackedFloat32Array).size()
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
	var top    := lerpf(row0[x0], row0[x1], tx)
	var bottom := lerpf(row1[x0], row1[x1], tx)
	return lerpf(top, bottom, ty)


# Override de MapBase.is_valid_spawn — prend en compte la taille variable.
func is_valid_spawn(world_pos: Vector2) -> bool:
	return is_valid_spawn_cell(world_to_cell(world_pos))


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return _ground.local_to_map(_ground.to_local(world_pos))


## Override — retourne la taille réelle générée (variable).
func get_map_pixel_size() -> Vector2:
	return Vector2(map_size.x * 16, map_size.y * 16)


## Override — taille de la map en cellules (variable).
func get_map_cell_size() -> Vector2i:
	return map_size


## Cellules d'entrée de grotte (base 26,38) — pour spawner les déclencheurs.
func get_cave_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _objects.get_used_cells():
		if _objects.get_cell_atlas_coords(cell) == tile_grotte_bas:
			result.append(cell)
	return result


## ─────────────────────────────────────────────────────────────────
## API PUBLIQUE — OBSTACLES CS (interaction en run, cf. CombatArena)
## ─────────────────────────────────────────────────────────────────

## Case rocher (monde) → case d'approche (là où le joueur doit se tenir
## pour déclencher l'interaction CS Force).
func get_force_boulder_approaches() -> Dictionary:
	return _force_boulders


## Liste des arbres coupables restants : [{"cells": Array[Vector2i], "approach": Vector2i}, ...]
func get_coupe_tree_approaches() -> Array:
	return _coupe_trees.duplicate()


## Casse le rocher CS Force à `cell` — efface la tuile et sa collision.
func break_rock_at(cell: Vector2i) -> void:
	if not _force_boulders.has(cell):
		return
	_objects.erase_cell(cell)
	_clear_cell_collision(cell)
	_force_boulders.erase(cell)


## Coupe l'arbre CS Coupe dont les 3 cases sont `cells` — efface les tuiles
## et leur collision, dégageant l'accès au coffre.
func cut_tree_group(cells: Array) -> void:
	for c: Vector2i in cells:
		_objects.erase_cell(c)
		_clear_cell_collision(c)
	_coupe_trees = _coupe_trees.filter(func(entry: Dictionary) -> bool:
		return entry["cells"] != cells
	)


func _clear_cell_collision(cell: Vector2i) -> void:
	# Rendu HD-2D : le visuel et la collision de la case vivent dans MapRender3D.
	if is_instance_valid(_render3d):
		_render3d.clear_cell(cell)
	# Nettoyage 2D — ne concerne plus que l'aperçu éditeur / anciens restes.
	if _cell_collision.has(cell):
		var cs: CollisionShape2D = _cell_collision[cell]
		if is_instance_valid(cs):
			cs.queue_free()
		_cell_collision.erase(cell)
	if _cell_shadow.has(cell):
		var shadow: Sprite2D = _cell_shadow[cell]
		if is_instance_valid(shadow):
			shadow.queue_free()
		_cell_shadow.erase(cell)


func get_entry_world_pos() -> Vector2:
	return _ground.to_global(_ground.map_to_local(entry_tile))


func get_exit_world_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for ex: Vector2i in [exit_A, exit_B, exit_C]:
		result.append(_ground.to_global(_ground.map_to_local(ex)))
	return result


## ─────────────────────────────────────────────────────────────────
## HAUTE HERBE — AREAS (override MapBase — filtre sur tile_tg seulement)
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
## COLLISION (override MapBase — tronc d'arbre uniquement)
## ─────────────────────────────────────────────────────────────────

func _build_map_collision() -> void:
	_ground.collision_enabled     = false
	_water.collision_enabled      = false
	_tall_grass.collision_enabled = false
	_objects.collision_enabled    = false

	_cell_collision.clear()
	_cell_shadow.clear()

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	add_child(body)

	# Ombres "blob" — un léger disque sombre sous chaque objet solide,
	# inséré juste avant _objects dans l'arbre pour dessiner en-dessous.
	var obj_idx := _objects.get_index()
	var shadows := Node2D.new()
	shadows.name = "Shadows"
	add_child(shadows)
	move_child(shadows, obj_idx)

	for cell: Vector2i in _objects.get_used_cells():
		var atlas := _objects.get_cell_atlas_coords(cell)
		if _is_decor_tile(atlas): continue
		# Arbres 3×3 : collision seulement sur la rangée du tronc (oy == 2).
		# Le feuillage (oy 0-1) n'a pas de hitbox → le joueur passe "sous" la canopée.
		var toff := _tree_offset(atlas)
		if toff != Vector2i(-1, -1) and toff.y < 2:
			continue
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		var csize := _col_size(atlas)
		sh.size     = csize
		cs.position = _objects.map_to_local(cell)
		cs.shape    = sh
		body.add_child(cs)
		_cell_collision[cell] = cs

		var shadow := ShadowTexture.make_shadow_sprite(csize * 0.85)
		shadow.position = cs.position + Vector2(0, csize.y * 0.32)
		shadows.add_child(shadow)
		_cell_shadow[cell] = shadow

	# L'eau est sur sa propre couche physique : seule la CS Surf permet de
	# l'ignorer (cf. CombatArena), sans affecter les autres obstacles.
	var water_body := StaticBody2D.new()
	water_body.collision_layer = WATER_LAYER
	water_body.collision_mask  = 0
	add_child(water_body)

	for cell: Vector2i in _water.get_used_cells():
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size     = Vector2(10, 10)
		cs.position = _water.map_to_local(cell)
		cs.shape    = sh
		water_body.add_child(cs)

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

## Système de blob 9-slice générique (coins/bords/centre — bloc 3×3 d'atlas
## à `origin`). Repeint toutes les cases de `_grid` où `is_member(terrain)`
## est vrai ET qui ont au moins un voisin cardinal hors-groupe, avec la
## tuile de bordure adaptée. Les cases intérieures (entourées du même
## groupe) gardent la tuile centre déjà posée par l'appelant.
func _apply_blob(layer: TileMapLayer, origin: Vector2i, is_member: Callable) -> void:
	var W := map_size.x
	var H := map_size.y
	for r in H:
		for c in W:
			if not is_member.call(_grid[r][c]):
				continue
			var bn: bool = r == 0     or not is_member.call(_grid[r - 1][c])
			var bs: bool = r == H - 1 or not is_member.call(_grid[r + 1][c])
			var bw: bool = c == 0     or not is_member.call(_grid[r][c - 1])
			var be: bool = c == W - 1 or not is_member.call(_grid[r][c + 1])
			if not (bn or bs or bw or be):
				continue
			var row_class := _blob_axis_class(bn, bs)
			var col_class := _blob_axis_class(bw, be)
			layer.set_cell(Vector2i(c, r), source_id, origin + Vector2i(col_class, row_class))


## 0 si le bord négatif (haut/gauche) est bloqué, 2 si c'est le positif
## (bas/droite), 1 sinon (intérieur sur cet axe).
func _blob_axis_class(blocked_neg: bool, blocked_pos: bool) -> int:
	if blocked_neg: return 0
	if blocked_pos: return 2
	return 1


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
			if _is_bridge_cell(cell):                   continue   # le pont reste dégagé
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


## Tous les arbres 3×3 possibles (par origine atlas), tous thèmes confondus.
func _all_tree_origins() -> Array:
	return [tile_tree_origin, tile_sapin_origin, tile_arbre_mort_orig]


## Retourne l'offset (0-2, 0-2) si `atlas` appartient à un arbre 3×3, sinon (-1,-1).
func _tree_offset(atlas: Vector2i) -> Vector2i:
	for o: Vector2i in _all_tree_origins():
		var ox := atlas.x - o.x
		var oy := atlas.y - o.y
		if ox >= 0 and ox < 3 and oy >= 0 and oy < 3:
			return Vector2i(ox, oy)
	return Vector2i(-1, -1)


# Override de MapBase._col_size
func _col_size(atlas: Vector2i) -> Vector2:
	if atlas == tile_rocher:                              return Vector2(8, 8)
	if atlas == tile_rondin_g or atlas == tile_rondin_d: return Vector2(12, 6)
	# Arbres coupables (CS Coupe) — tous bloquants jusqu'à la coupe
	if (atlas.x == 7 or atlas.x == 8) and atlas.y >= 12 and atlas.y <= 14:
		return Vector2(12, 14)
	# Champignon — seule la base bloque (cf. _is_theme_decor : sommet/milieu traversables)
	if _champi_row(atlas) == 2:
		return Vector2(10, 10)
	# Gros caillou 2×2 (rocailleux) — chaque quart bloque
	if _in_block(atlas, tile_gros_caillou_orig, 2, 2):
		return Vector2(14, 14)
	# Falaise — bloc rocheux plein (formations agrandies, voir _col_size_cliff)
	if _is_cliff_tile(atlas):
		return Vector2(16, 16)
	return Vector2(10, 10)


# Override de MapBase._is_decor_tile — décors traversables (pas de hitbox)
func _is_decor_tile(a: Vector2i) -> bool:
	if a == tile_fleur_rouge or a == tile_fleur_violette or a == tile_fleur_blanche:
		return true
	if a == tile_petite_herbe or a == tile_chest_closed:
		return true
	for f: Vector2i in tiles_petites_fleurs:
		if a == f: return true
	if _is_theme_decor(a):
		return true
	return false


## Décors thématiques traversables (souches, cailloux, nénuphars).
## Les champignons NE sont PAS traversables sur leur base — voir _champi_row.
func _is_theme_decor(a: Vector2i) -> bool:
	# Champignon 3×1 : sommet + milieu traversables (comme la canopée d'un
	# arbre), la base bloque — gérée séparément via _col_size / _champi_row.
	var champi_row := _champi_row(a)
	if champi_row == 0 or champi_row == 1:
		return true
	if a == tile_souche_sombre or a == tile_souche_claire: return true
	if a == tile_nenuphar or a == tile_petit_nenuphar:     return true
	if a == tile_grotte_haut or a == tile_grotte_bas:      return true
	for nf: Vector2i in tiles_nenuphars_fleur:
		if a == nf: return true
	for cc: Vector2i in tiles_cailloux:
		if a == cc: return true
	return false


## Ligne du champignon 3×1 si `a` en fait partie : 0=sommet, 1=milieu, 2=base. Sinon -1.
func _champi_row(a: Vector2i) -> int:
	if a.x == tile_champi_origin.x and a.y >= tile_champi_origin.y and a.y <= tile_champi_origin.y + 2:
		return a.y - tile_champi_origin.y
	return -1


## Vrai si `a` est dans le bloc w×h dont le coin haut-gauche est `origin`.
func _in_block(a: Vector2i, origin: Vector2i, w: int, h: int) -> bool:
	return a.x >= origin.x and a.x < origin.x + w \
		and a.y >= origin.y and a.y < origin.y + h


## Vrai si `a` est l'une des 9 variantes (coins/bords/centre) de la falaise.
## Les formations falaise peuvent être agrandies (_place_cliff_rect) mais
## réutilisent toujours ces 9 tuiles d'atlas.
func _is_cliff_tile(a: Vector2i) -> bool:
	return _in_block(a, tile_cliff_origin, 3, 3)
