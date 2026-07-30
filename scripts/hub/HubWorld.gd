extends Node3D

# ── PNJ (pokemon_id → sprite PMD chargé async) ───────────────────────
# Positions sur le layout compact 56×34 (cf. HubMap : plaza 21-35 × 13-23,
# chemin vertical x26-30, bande horizontale z15-19, étang autour de (9.5, 26.5))
const NPC_DEFS: Array[Dictionary] = [
	# Le meneur de la rébellion — Léviator, le serpent furieux qui brise ses
	# chaînes : symbole d'un Pokémon sauvage et rebelle. Ouvre la Chronique
	# (récit + objectif + rang). Planté au centre de la plaza.
	{"id": "story",     "pid": 130, "pos": Vector3(22.0, 0, 14.5), "accent": Color(0.90, 0.24, 0.20)},  # Léviator — meneur
	# Courrier de la rébellion — Roucarnage porte les rumeurs : missions de
	# libération facultatives (cf. RumorBoardScreen / MissionManager).
	{"id": "rumors",    "pid": 18,  "pos": Vector3(34.0, 0, 15.5), "accent": Color(0.85, 0.72, 0.40)},  # Roucarnage — tableau des rumeurs
	{"id": "start",     "pid": 149, "pos": Vector3(28.0, 0, 7.0),  "accent": Color(0.85, 0.38, 0.10)},  # Dragonite — haut du chemin
	{"id": "shop",      "pid": 113, "pos": Vector3(9.0,  0, 13.5), "accent": Color(0.92, 0.60, 0.72)},  # Chansey — chemin ouest
	{"id": "pokedex",   "pid": 137, "pos": Vector3(15.5, 0, 20.5), "accent": Color(0.40, 0.58, 0.95)},  # Porygon — vers l'étang
	{"id": "upgrades",  "pid": 65,  "pos": Vector3(46.0, 0, 13.5), "accent": Color(0.68, 0.35, 0.92)},  # Alakazam — chemin est
	{"id": "gromago",   "pid": 1000, "pos": Vector3(32.5, 0, 11.5), "accent": Color(0.92, 0.78, 0.25)},  # Gromago (#1000) — bazar d'objets, NE de la plaza
	# Tuteur de CT — de retour au hub (retour joueurs : vendeur de CT avec
	# large choix d'attaques à effets réels, cf. MoveShopScreen).
	{"id": "moves",     "pid": 122, "pos": Vector3(40.0, 0, 20.5), "accent": Color(0.90, 0.42, 0.55)},  # Mr. Mime — bande horizontale, vers l'est
]

# Pokémon décoratifs — déambulent autour de leur position de départ
const AMBIENT_DEFS: Array[Dictionary] = [
	{"pid": 35,  "pos": Vector3(19.0, 0, 26.0), "radius": 2.4},   # Clefairy — près du feu ouest
	{"pid": 133, "pos": Vector3(42.0, 0, 26.0), "radius": 2.4},   # Eevee — près du feu est
	{"pid": 43,  "pos": Vector3(44.0, 0, 21.0), "radius": 2.0},   # Oddish
	{"pid": 60,  "pos": Vector3(13.5, 0, 29.5), "radius": 1.6},   # Poliwag — berge de l'étang
	{"pid": 39,  "pos": Vector3(40.0, 0, 9.0),  "radius": 2.6},   # Jigglypuff
	{"pid": 58,  "pos": Vector3(4.5,  0, 9.5),  "radius": 0.0},   # Growlithe — garde de la tour (immobile)
]

const INTERACT_RADIUS := 4.5
const PLAYER_START     := Vector3(28.0, 0, 21.0)

const MAP_W := 80.0
const MAP_H := 34.0

# ── Caméra (angle fixe façon Octopath, suit le joueur) ──────────────────
# Réglages ALIGNÉS sur l'arène de combat (CombatArena) : même vue aérienne
# dézoomée (hauteur 16 / recul 32, même angle 26,5° et même FOV) et même
# lissage de suivi — le Hub et le combat partagent désormais la même base.
const CAM_HEIGHT := 16.0
const CAM_BACK   := 32.0
const CAM_FOV    := 28.0
const CAM_FOLLOW := 8.0    # vitesse de rattrapage du suivi (cf. CombatArena)

# ── Palette header ────────────────────────────────────────────────────
const C_HDR      := Color(0.11, 0.08, 0.05, 0.94)
const C_HDR_LINE := Color(0.62, 0.50, 0.32)
const C_GOLD     := Color(0.76, 0.53, 0.17)
const C_TEXT_LT  := Color(0.94, 0.88, 0.72)
const C_TEXT_DIM := Color(0.58, 0.50, 0.36)

var _player:      HubPlayer = null
var _remote_avatars: Dictionary = {}   # peer_id → HubPlayer (hub partagé)
var _npcs:        Array     = []
var _near_npc:    HubNPC    = null
var _blocked:     bool      = false
var _subscreen:   CanvasLayer = null

var _cam:         Camera3D  = null
var _cam_target:  Vector3   = Vector3.ZERO

## HubMapBg (HubMap) — source du relief pour joueur/PNJ
var _terrain: Node3D = null
var _clouds:  Array  = []   # [{node, speed}, ...] — nuages dérivants

# UI
var _ui:         CanvasLayer = null
var _prompt_lbl: Label     = null
var _gold_lbl:   Label      = null
var _team_lbl:   Label      = null
var _run_lbl:    Label      = null


func _ready() -> void:
	Sfx.stop_music()   # coupe la musique de victoire/boss au retour au hub
	_terrain = get_node_or_null("HubMapBg")
	_build_environment()
	_build_backdrop()
	_register_key()
	_build_npcs()
	_build_ambient()
	_build_freed_pokemon()
	_build_sunflowers()
	_build_butterflies()
	_build_player()
	_build_camera()
	_build_ui()
	_build_multiplayer_avatars()
	# La rébellion a pu progresser pendant la run (Pokémon libérés, dresseur
	# vaincu) : on réévalue au retour au hub et on félicite si un chapitre a été
	# franchi. evaluate() est idempotent — sûr à rappeler à chaque entrée.
	var advanced := StoryManager.evaluate()
	MissionManager.ensure_board()   # tableau des rumeurs prêt dès l'entrée
	if GameManager.is_first_run and GameManager.unlocked_pokemon.is_empty():
		_open_starter_selection()
	else:
		# Retour au hub (post-run, achat, etc.) = point de sauvegarde naturel.
		GameManager.save_game()
		if advanced:
			_show_coming_soon("Nouveau chapitre — %s" % StoryManager.chapter()["title"])


# ── Environnement (ciel, lumière, ambiance) ─────────────────────────────

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color        = Color(0.42, 0.62, 0.88)
	sky_mat.sky_horizon_color    = Color(0.85, 0.78, 0.66)
	sky_mat.ground_bottom_color  = Color(0.30, 0.28, 0.24)
	sky_mat.ground_horizon_color = Color(0.85, 0.78, 0.66)
	sky.sky_material = sky_mat
	e.sky = sky

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.22   # aligné sur BiomeAmbiance._BASE_AMBIANCE
	e.fog_enabled     = true
	e.fog_light_color = Color(0.68, 0.66, 0.60)
	e.fog_density     = 0.014
	e.fog_sun_scatter = 0.12
	e.glow_enabled    = true
	e.glow_intensity  = 0.20
	e.glow_bloom      = 0.05
	e.tonemap_mode    = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.74       # aligné sur BiomeAmbiance._BASE_AMBIANCE
	e.adjustment_enabled    = true
	e.adjustment_saturation = 1.3   # couleurs franches (cf. BiomeAmbiance)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)   # même direction d'ombres qu'en run
	sun.light_color    = Color(1.0, 0.90, 0.75)
	sun.light_energy   = 0.52       # aligné sur BiomeAmbiance._BASE_AMBIANCE
	sun.shadow_enabled = true
	# Ombres STABLES en mouvement : une seule tranche orthogonale bornée à la
	# portée de vue réelle (caméra fixe) — fini le tremblement des bords
	# d'ombre dû au recalage des tranches PSSM à chaque déplacement.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 44.0   # resserré sur la vue réelle → texels fins, plus de "respiration" des bords
	sun.shadow_blur = 1.8
	add_child(sun)


## Décor lointain en trois couches (même principe que BiomeAmbiance côté
## combat) — l'horizon ne montre jamais de vide, sensation de monde qui
## continue au-delà de la lisière :
##   1. anneau dense d'arbres Kenney + affleurements de falaises étagées,
##      juste derrière la bordure jouable ;
##   2. collines lointaines brumeuses ;
##   3. nuages billboard qui dérivent lentement (cf. _process).
func _build_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var center := Vector3(MAP_W * 0.5, 0, MAP_H * 0.5)
	var fog := Color(0.68, 0.66, 0.60)   # cf. _build_environment (fog_light_color)

	# TABLIER DE SOL sous le mur et jusqu'à l'horizon — avant, on voyait le
	# CIEL sous les troncs dès que la caméra plongeait : la clairière flottait
	# dans le vide. Anneau de 4 quads (pas un plan sous la map, cf. la leçon
	# des biomes : un plan dessous fait une marche), teinté à l'herbe du hub
	# via la compensation de shader mesurée (BiomeAmbiance._apron_tint).
	var hub_grass := Color(0.74, 0.84, 0.55)
	var span := maxf(MAP_W, MAP_H) * 14.0
	var apron_mat := GrassPatch.ground_material(
		BiomeAmbiance._grass_tex(), 1.45, 0.88, span,
		BiomeAmbiance._apron_tint(hub_grass), 1.0)
	var hx := MAP_W * 0.5
	var hz := MAP_H * 0.5
	var hs := span * 0.5
	for band: Dictionary in [
		{"size": Vector2(2.0 * hs, hs - hz), "at": Vector2(0.0, -(hs + hz) * 0.5)},
		{"size": Vector2(2.0 * hs, hs - hz), "at": Vector2(0.0,  (hs + hz) * 0.5)},
		{"size": Vector2(hs - hx, 2.0 * hz), "at": Vector2(-(hs + hx) * 0.5, 0.0)},
		{"size": Vector2(hs - hx, 2.0 * hz), "at": Vector2( (hs + hx) * 0.5, 0.0)},
	]:
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = band["size"]
		quad.mesh = plane
		quad.position = Vector3(center.x + (band["at"] as Vector2).x, -0.06,
			center.z + (band["at"] as Vector2).y)
		quad.material_override = apron_mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)

	# MUR DE FORÊT — même recette que les biomes : anneaux BATCHÉS en
	# MultiMesh (l'ancienne version posait ~370 MeshInstance3D individuels,
	# 370 draw calls) et ESTOMPÉS progressivement vers le brouillard — c'est
	# l'étagement des teintes qui donne la profondeur, un mur uniforme lit
	# comme un décor de théâtre. Plus dense aussi : on est au cœur des bois.
	for ring in 7:
		var n := 96 + ring * 18
		var rx := MAP_W * 0.5 + 2.0 + ring * 4.4
		var rz := MAP_H * 0.5 + 1.6 + ring * 4.0
		var haze := minf(0.85, ring * 0.13)
		var tints := {
			"leafsGreen": Color(0.22, 0.55, 0.16).lerp(fog, haze),
			"leafsDark":  Color(0.14, 0.40, 0.14).lerp(fog, haze),
			"woodBark":   Color(0.36, 0.30, 0.26).lerp(fog, haze),
		}
		var by_file: Dictionary = {}   # fichier -> {"t": transforms, "p": phases}
		for i in n:
			var ang := (TAU / float(n)) * i + rng.randf_range(-0.05, 0.05)
			var pos := center + Vector3(
				cos(ang) * (rx + rng.randf_range(-1.4, 2.2)),
				0,
				sin(ang) * (rz + rng.randf_range(-1.4, 2.2)))
			var pool: Array = KitProps.TREES_ROUND if rng.randf() < 0.6 else KitProps.TREES_PINE
			var file: String = pool[rng.randi() % pool.size()]
			var native_h: float = KitProps.TREE_NATIVE_HEIGHT.get(file, 1.7)
			var sc := (rng.randf_range(3.4, 5.8) + ring * 0.6) / native_h
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * sc)
			if not by_file.has(file):
				by_file[file] = {"t": [], "p": []}
			by_file[file]["t"].append(Transform3D(basis, pos))
			by_file[file]["p"].append(rng.randf_range(0.0, TAU))
		for file: String in by_file:
			var mmi := KitProps.build_multimesh(file, by_file[file]["t"], by_file[file]["p"], tints)
			add_child(mmi)

	# 3) Nuages dérivants — HAUTS, petits et discrets pour ne pas former de
	# grande bande translucide au premier plan (et pas de scintillement de tri
	# de transparence). Ils restent bien au-dessus du champ de vision.
	for i in 5:
		var spr := Sprite3D.new()
		spr.texture = BiomeAmbiance._get_cloud_texture()
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # pas de "respiration" du nuage étiré quand la caméra bouge
		spr.shaded    = false
		spr.modulate  = Color(1, 1, 1, rng.randf_range(0.30, 0.45))
		spr.pixel_size = rng.randf_range(0.05, 0.09)
		spr.scale = Vector3(2.6, 1.0, 1.0)
		spr.render_priority = i   # ordre de rendu fixe — pas de bascule de tri (clignotement)
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # billboard : ombre qui "nagerait" avec la caméra
		spr.position = center + Vector3(
			rng.randf_range(-MAP_W * 0.9, MAP_W * 0.9),
			rng.randf_range(48.0, 66.0),
			rng.randf_range(-MAP_H * 0.9, -MAP_H * 0.1)   # au fond, jamais devant la caméra
		)
		add_child(spr)
		_clouds.append({"node": spr, "speed": rng.randf_range(0.25, 0.7)})


## Affleurement de falaise étagé ("wedding cake") — même principe que
## BiomeAmbiance._add_cliff_tier, teintes vertes/brunes accordées au hub.
func _add_backdrop_cliff(rng: RandomNumberGenerator, pos: Vector3, ang: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var back_dir := Vector3(cos(ang), 0, sin(ang))
	var levels := rng.randi_range(2, 3)
	var w := rng.randf_range(6.0, 10.0)
	var d := rng.randf_range(5.0, 8.0)
	var y := 0.0
	var back := 0.0
	for lvl in levels:
		var h := rng.randf_range(2.5, 4.5)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, d)
		mi.mesh = box
		mi.position = Vector3(0, y + h * 0.5, 0) + back_dir * back
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.48, 0.38).lerp(Color(0.34, 0.40, 0.34), float(lvl) / float(levels))
		mat.roughness = 1.0
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		y += h
		back += rng.randf_range(1.2, 2.4)
		w *= 0.72
		d *= 0.72


## Coupe l'ombre portée de tous les MeshInstance3D sous `node` (décor de fond,
## dont les arbres KitProps) — une ombre géante hors zone de jeu créerait une
## bande sombre mouvante en travers de la scène.
func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)


## Touches : source unique de vérité dans Controls.CATALOG.
func _register_key() -> void:
	Controls.apply()


# ── Construction ──────────────────────────────────────────────────────

func _build_npcs() -> void:
	for def: Dictionary in NPC_DEFS:
		var npc := HubNPC.new()
		npc.position = def["pos"]
		npc.terrain  = _terrain
		add_child(npc)
		npc.setup(def["id"], def["pid"], def["accent"])
		_npcs.append(npc)


func _build_ambient() -> void:
	for def: Dictionary in AMBIENT_DEFS:
		var npc := HubNPC.new()
		npc.position = def["pos"]
		npc.terrain  = _terrain
		add_child(npc)
		npc.setup("ambient", def["pid"], Color(0, 0, 0, 0))
		var r: float = def.get("radius", 2.5)
		if r > 0.0:
			npc.start_wandering(def["pos"], r, randf_range(0.9, 1.4))


## Points de déambulation des Pokémon LIBÉRÉS (GameManager.unlocked_pokemon),
## répartis dans les zones ouvertes du hub — chemins, plaza, clairière à l'est
## (ex-enclos, cf. HubMap.EAST_CLEARING). Retour joueurs : « l'enclos c'est
## moche, je veux qu'ils se baladent partout dans le hub, mais de manière
## logique » — donc à la main plutôt qu'un tirage géométrique, pour rester à
## bonne distance de l'eau, des tentes, du grand arbre et de l'enclos (celui
## des tournesols, qui lui reste) — même logique de curation que AMBIENT_DEFS.
const FREED_ROAM_SPOTS: Array[Dictionary] = [
	{"pos": Vector3(28.0, 0, 4.5),  "radius": 2.0},   # haut du chemin vertical
	{"pos": Vector3(22.0, 0, 19.0), "radius": 2.5},   # plaza, côté ouest
	{"pos": Vector3(38.0, 0, 17.0), "radius": 2.0},   # plaza, côté est
	{"pos": Vector3(28.0, 0, 29.0), "radius": 2.0},   # bas du chemin vertical
	{"pos": Vector3(12.0, 0, 17.0), "radius": 2.3},   # chemin ouest
	{"pos": Vector3(50.0, 0, 17.0), "radius": 2.5},   # chemin est, avant la clairière
	{"pos": Vector3(62.0, 0, 23.0), "radius": 3.0},   # clairière est, ouest
	{"pos": Vector3(72.0, 0, 24.0), "radius": 3.2},   # clairière est, centre
	{"pos": Vector3(66.0, 0, 29.0), "radius": 2.8},   # clairière est, sud
	{"pos": Vector3(55.0, 0, 30.0), "radius": 2.2},   # sud-est, avant la clairière
]

## Sous-ensemble tournant : jusqu'à FREED_ROAM_SPOTS.size() espèces
## débloquées, tirées à chaque chargement du hub (pas de minimum forcé en
## tout début de partie). npc_id "reserve" (≠ "ambient") : contrairement à la
## faune décorative, ces PNJ sont INTERACTIFS — cf. _process (portée
## d'interaction) et NpcDialogue.LINES["reserve"].
func _build_freed_pokemon() -> void:
	var pool: Array = GameManager.unlocked_pokemon.duplicate()
	if pool.is_empty():
		return
	pool.shuffle()
	var count := mini(pool.size(), FREED_ROAM_SPOTS.size())

	for i in count:
		var spot: Dictionary = FREED_ROAM_SPOTS[i]
		var pos: Vector3 = spot["pos"]
		var npc := HubNPC.new()
		npc.position = pos
		npc.terrain  = _terrain
		add_child(npc)
		npc.setup("reserve", pool[i], Color(0.70, 0.85, 0.60))
		npc.start_wandering(pos, spot["radius"], randf_range(0.9, 1.3))
		_npcs.append(npc)


## Positions synchronisées avec l'enclos de barrières posé par
## HubMap._place_sunflower_fences (rect 29-38 × 24-29, portillon au nord).
func _build_sunflowers() -> void:
	for pos: Vector3 in [Vector3(31.5, 0, 26.5), Vector3(35.5, 0, 26.5)]:
		var field := SunflowerField.new()
		field.position = pos
		add_child(field)


## Papillons qui voltigent dans les zones vertes — vie ambiante discrète.
func _build_butterflies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for anchor: Vector3 in [
		Vector3(14.0, 0, 8.0),  Vector3(44.0, 0, 21.5), Vector3(19.0, 0, 25.5),
		Vector3(37.0, 0, 9.0),  Vector3(47.0, 0, 27.0), Vector3(11.0, 0, 21.0),
		Vector3(33.5, 0, 26.5),   # au-dessus des tournesols
	]:
		var b := Butterfly.new()
		b.anchor  = anchor
		b.terrain = _terrain
		add_child(b)


func _build_player() -> void:
	_player = HubPlayer.new()
	_player.position = PLAYER_START
	_player.terrain  = _terrain
	add_child(_player)


## Hub PARTAGÉ en multijoueur : une copie (HubPlayer.setup_remote) par autre
## joueur connecté (cf. HubPlayer._remote_process, même schéma que les
## copies de TeamMember en combat) — tout le monde se balade ensemble entre
## deux runs. Se resynchronise si des joueurs rejoignent/partent pendant
## qu'on est dans le hub (cf. Net.players_changed).
func _build_multiplayer_avatars() -> void:
	if not Net.active:
		return
	Net.players_changed.connect(_sync_remote_avatars)
	_sync_remote_avatars()


func _sync_remote_avatars() -> void:
	if not Net.active:
		for peer: int in _remote_avatars:
			if is_instance_valid(_remote_avatars[peer]):
				_remote_avatars[peer].queue_free()
		_remote_avatars.clear()
		return

	var local_id := Net.local_id()
	for peer: int in _remote_avatars.keys():
		if not Net.players.has(peer):
			if is_instance_valid(_remote_avatars[peer]):
				_remote_avatars[peer].queue_free()
			_remote_avatars.erase(peer)

	for peer: int in Net.players:
		if peer == local_id or _remote_avatars.has(peer):
			continue
		var p: Dictionary = Net.players[peer]
		var avatar := HubPlayer.new()
		avatar.setup_remote(peer, int(p["pid"]))
		avatar.position = PLAYER_START + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		avatar.terrain  = _terrain
		add_child(avatar)
		_remote_avatars[peer] = avatar


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	# Caméra reculée (~36 u) : on remonte le plan near pour retrouver de la
	# précision de profondeur — sinon les plans quasi coplanaires du sol
	# (chemins/lit d'eau à quelques millimètres) se battent (z-fighting =
	# clignotement). Rien n'est plus proche que ~10 u de la caméra.
	_cam.near = 1.0
	_cam.far  = 300.0
	add_child(_cam)
	_cam_target = _player.position
	_update_camera(true, 0.0)


func _update_camera(snap: bool, delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var t := 1.0 if snap else minf(1.0, CAM_FOLLOW * delta)
	_cam_target = _cam_target.lerp(_player.position, t)
	var offset := Vector3(0, CAM_HEIGHT, CAM_BACK)
	_cam.position = _cam_target + offset
	_cam.look_at(_cam_target + Vector3(0, 0.9, 0), Vector3.UP)


## Bandeau du Hub — pills flottants (même langage que le HUD de run) :
## les BAIES en premier et en GROS à gauche, équipe au centre-gauche,
## compteur de runs à droite. Prompt d'interaction en pill bas-centre.
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)

	# ── Pill Baies (l'info n°1 : grosse, dorée, toujours au même endroit) ──
	var gold_pill := _mk_pill(Vector2(12, 10), Vector2(210, 48), true)
	_gold_lbl = _mk_lbl("◆ 0", 16, 8, 180, 32, 24, C_GOLD)
	gold_pill.add_child(_gold_lbl)

	# ── Pill Équipe (élargie pour le poids de build, cf. compute_team_weight) ──
	var team_pill := _mk_pill(Vector2(236, 10), Vector2(250, 48), false)
	_team_lbl = _mk_lbl("Équipe —", 16, 14, 222, 22, 14, C_TEXT_LT)
	_team_lbl.clip_text = true
	_team_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	team_pill.add_child(_team_lbl)

	# ── Pill Run ──
	var run_pill := _mk_pill(Vector2(1128, 10), Vector2(140, 48), false)
	_run_lbl = _mk_lbl("Run #0", 16, 12, 110, 26, 16, C_TEXT_DIM)
	run_pill.add_child(_run_lbl)

	_prompt_lbl = _mk_lbl("", 240, 662, 800, 46, 18, C_GOLD)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_lbl.visible = false
	_ui.add_child(_prompt_lbl)

	_refresh_labels()


## Petit panneau arrondi translucide (pill) — accent or si `highlight`.
func _mk_pill(pos: Vector2, sz: Vector2, highlight: bool) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size     = sz
	var st := StyleBoxFlat.new()
	st.bg_color     = Color(0.10, 0.075, 0.045, 0.88)
	st.border_color = Color(0.92, 0.72, 0.25) if highlight else Color(0.55, 0.42, 0.22)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size  = 4
	p.add_theme_stylebox_override("panel", st)
	_ui.add_child(p)
	return p


## Crée un Label stylé — SANS parent : l'appelant l'ajoute où il veut
## (pill, _ui direct…).
func _mk_lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _refresh_labels() -> void:
	if not is_instance_valid(_gold_lbl):
		return
	var new_text := "◆ %d Baies" % GameManager.gold
	if _gold_lbl.text != new_text:
		_gold_lbl.text = new_text
		# Pop du compteur quand le solde change (achat/gain visible d'un coup d'œil)
		_gold_lbl.pivot_offset = Vector2(30, 16)
		_gold_lbl.scale = Vector2(1.25, 1.25)
		var tw := create_tween()
		tw.tween_property(_gold_lbl, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT)
	var ts := GameManager.hub_team.size()
	var mx := GameManager.get_max_team_size()
	var w   := GameManager.compute_team_weight()
	var cap := GameManager.build_weight_cap
	_team_lbl.text = "Équipe %d / %d  ·  Poids %d / %d" % [ts, mx, w, cap]
	_team_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.35, 0.30) if w > cap else Color(0.92, 0.88, 0.72))
	_run_lbl.text  = "Run #%d" % GameManager.run_count


# ── Process / interaction ─────────────────────────────────────────────

func _process(delta: float) -> void:
	# Nuages — dérive lente avec rebouclage
	for c: Dictionary in _clouds:
		var spr: Sprite3D = c["node"]
		if is_instance_valid(spr):
			spr.position.x += c["speed"] * delta
			if spr.position.x > MAP_W * 1.6:
				spr.position.x -= MAP_W * 2.2

	if not is_instance_valid(_player):
		return

	# Écrasement de l'herbe/des fleurs sous le joueur (cf.
	# KitProps._WIND_SHADER, même mécanisme qu'en combat).
	RenderingServer.global_shader_parameter_set("trample_pos", _player.global_position)

	_player.move_tick(delta, _blocked)
	for peer: int in _remote_avatars:
		var avatar: HubPlayer = _remote_avatars[peer]
		if is_instance_valid(avatar):
			avatar.move_tick(delta, false)
	_update_camera(false, delta)

	if _blocked:
		return

	# Relance ÉCLAIR : Entrée depuis le hub lance directement la run —
	# mort → Entrée → on repart, sans marcher jusqu'au PNJ.
	if Input.is_action_just_pressed("ui_accept") and not GameManager.hub_team.is_empty():
		_start_run()
		return

	# Détection PNJ interactif le plus proche
	var best_npc:  HubNPC = null
	var best_dist: float  = INTERACT_RADIUS

	for npc: HubNPC in _npcs:
		if not is_instance_valid(npc) or npc.npc_id == "ambient":
			continue
		var d := _player.position.distance_to(npc.position)
		if d < best_dist:
			best_dist = d
			best_npc  = npc

	for npc: HubNPC in _npcs:
		if is_instance_valid(npc):
			npc.set_in_range(npc == best_npc)

	if best_npc != _near_npc:
		_near_npc = best_npc
		_update_prompt(best_npc)

	if best_npc != null and Input.is_action_just_pressed("hub_interact"):
		_interact(best_npc)


func _update_prompt(npc: HubNPC) -> void:
	if not is_instance_valid(_prompt_lbl):
		return
	if npc == null:
		_prompt_lbl.visible = false
		return

	var role: String
	match npc.npc_id:
		"story":     role = "Chronique de la Rébellion"
		"rumors":    role = "Tableau des Rumeurs"
		"reserve":   role = "Pokémon libéré"
		"start":     role = "Lancer la Run"
		"shop":      role = "Boutique"
		"pokedex":   role = "Pokédex & Équipe"
		"upgrades":  role = "Améliorations"
		"gromago":   role = "Bazar d'objets"
		"moves":     role = "Tuteur de Capacités"
		_:           role = "Parler"

	var display_name := npc.npc_name if not npc.npc_name.is_empty() else "…"
	_prompt_lbl.text    = "[ E ]   %s   –   %s" % [display_name, role]
	_prompt_lbl.visible = true

	# Pill sombre + or, même langage que le prompt d'interaction en run
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.10, 0.075, 0.045, 0.90)
	s.border_color = Color(0.92, 0.72, 0.25)
	s.set_border_width_all(2)
	s.set_corner_radius_all(20)
	_prompt_lbl.add_theme_stylebox_override("normal", s)


## PNJ à SERVICE (menu associé, cf. _open_npc_screen) — mêmes clés que le
## match ci-dessous. Retour joueurs : « les PNJ à service ne doivent parler
## qu'une fois, puis ouvrir directement le menu » — un PNJ décoratif (pas
## dans cette liste, ex. "reserve") continue lui de parler à chaque fois.
const _SERVICE_NPCS := ["start", "story", "rumors", "shop", "pokedex", "upgrades", "gromago", "moves"]

## Petit échange (2-3 phrases, cf. NpcDialogue) AVANT d'ouvrir le menu associé
## au PNJ — retour joueurs : « je veux pouvoir avoir un petit dialogue avec
## chaque PNJ ». Le menu ne s'ouvre qu'une fois le dialogue refermé.
func _interact(npc: HubNPC) -> void:
	_blocked = true
	var is_service := npc.npc_id in _SERVICE_NPCS
	if is_service and GameManager.has_seen_npc_intro(npc.npc_id):
		_open_npc_screen(npc)
		return
	var dlg := NpcDialogueScreen.new()
	add_child(dlg)
	var display_name := npc.npc_name if not npc.npc_name.is_empty() else "…"
	dlg.setup(display_name, npc.pokemon_id, npc.accent, NpcDialogue.lines_for(npc.npc_id))
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)
	dlg.finished.connect(func() -> void:
		if is_service:
			GameManager.mark_npc_intro_seen(npc.npc_id)
		_open_npc_screen(npc)
	)


func _open_npc_screen(npc: HubNPC) -> void:
	var screen: CanvasLayer = null

	match npc.npc_id:
		"start":
			_open_run_menu()
			return
		"story":
			screen = StoryScreen.new()
		"rumors":
			screen = RumorBoardScreen.new()
		"shop":
			screen = ShopScreen.new()
		"pokedex":
			screen = PokedexScreen.new()
		"upgrades":
			screen = UpgradeShopScreen.new()
		"gromago":
			screen = GromagoShopScreen.new()
		"moves":
			screen = MoveShopScreen.new()

	if screen == null:
		_blocked = false
		return

	screen.layer = 10
	add_child(screen)
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)
	_subscreen = screen

	# Bandeau du hub tenu à jour PENDANT que l'écran est ouvert (il est visible
	# juste au-dessus) : sans ça, "Équipe x/6 · Poids y/40" restait celui d'avant
	# tant qu'on n'avait pas refermé le Pokédex (retour joueurs).
	if screen.has_signal("team_changed"):
		screen.team_changed.connect(_refresh_labels)
		# Le sprite incarné suit le PREMIER de l'équipe : s'il change pendant
		# qu'on compose dans le Pokédex, il se met à jour en direct, comme le
		# bandeau (retour joueurs).
		screen.team_changed.connect(_refresh_player_sprite)

	# Réclamer une rumeur verse des Baies/Éclats : le bandeau se met à jour en
	# direct, sans attendre la fermeture du tableau.
	if screen.has_signal("reward_claimed"):
		screen.reward_claimed.connect(_refresh_labels)

	if screen.has_signal("closed"):
		screen.closed.connect(func() -> void:
			Sfx.play_file(Sfx.SE_MENU_CLOSE, -6.0)
			screen.queue_free()
			_subscreen = null
			_blocked   = false
			_refresh_labels()
			# Fermeture d'un menu du hub (Boutique/Pokédex/Améliorations/
			# Gromago) = point de sauvegarde naturel après tout achat.
			GameManager.save_game()
		, CONNECT_ONE_SHOT)


# ── Actions ───────────────────────────────────────────────────────────

## Petit menu Solo / Multijoueur en parlant au PNJ de départ.
func _open_run_menu() -> void:
	var menu := CanvasLayer.new()
	menu.layer = 25
	add_child(menu)
	_subscreen = menu

	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(veil)

	var close_menu := func() -> void:
		menu.queue_free()
		_subscreen = null
		_blocked   = false

	# Ce menu était bâti à la main (StyleBoxFlat maison, boutons posés en
	# absolu sur le CanvasLayer) : il jurait avec le reste du hub et n'avait ni
	# Échap ni navigation aux flèches. Il passe à UiKit comme tous les autres
	# écrans — et ça règle la navigation par la même occasion : les boutons
	# vivent maintenant dans un Panel, alors que la résolution du voisin par les
	# flèches remonte l'arbre des Control et ne pouvait pas franchir le
	# CanvasLayer, qui n'en est pas un.
	menu.add_child(MenuNav.make(close_menu))

	var panel := UiKit.main_panel(Vector2(400, 180), Vector2(480, 400))
	menu.add_child(panel)
	UiKit.banner(panel, "Prêt à partir ?")

	var defs: Array = [
		{"txt": "🗡  Partir seul",             "green": true},
		{"txt": "⚔  Multijoueur (jusqu'à 6)", "green": true},
		{"txt": "🧪  Tester un biome",         "green": false},
		{"txt": "✕  Annuler",                  "green": false},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		var b := UiKit.button(d["txt"], Vector2(400, 58), d["green"])
		b.position = Vector2(40, 96 + i * 72)
		panel.add_child(b)
		var idx := i
		b.pressed.connect(func() -> void:
			close_menu.call()
			match idx:
				0: _start_run()
				1: _open_multiplayer_lobby()
				2: _open_biome_test()
		)

	# Sans bouton focalisé, la navigation clavier de Godot est inerte : les
	# flèches n'ont aucun point de départ à partir duquel résoudre le voisin.
	MenuNav.focus_first(panel)


## Menu de test de biome (Dracolosse) — choisir un biome lance une run solo
## forcée dessus (cf. RunManager.test_biome_override).
func _open_biome_test() -> void:
	_blocked = true
	var screen := BiomeTestScreen.new()
	add_child(screen)
	_subscreen = screen
	screen.biome_chosen.connect(func(theme: int) -> void:
		_subscreen = null
		screen.queue_free()
		_start_run(theme)
	, CONNECT_ONE_SHOT)
	screen.closed.connect(func() -> void:
		screen.queue_free()
		_subscreen = null
		_blocked   = false
	, CONNECT_ONE_SHOT)


func _open_multiplayer_lobby() -> void:
	_blocked = true
	var lobby := MultiplayerLobbyScreen.new()
	add_child(lobby)
	_subscreen = lobby
	lobby.closed.connect(func() -> void:
		lobby.queue_free()
		_subscreen = null
		_blocked   = false
	, CONNECT_ONE_SHOT)


## `force_biome` >= 0 : run de TEST forcée sur ce biome (menu Dracolosse) —
## on saute le contrôle de poids pour ne rien bloquer. -1 : run normale.
func _start_run(force_biome: int = -1) -> void:
	if GameManager.hub_team.is_empty():
		_show_coming_soon("Parle d'abord à Ko\npour composer ton équipe !")
		return
	if force_biome < 0:
		# Système de poids/build (simple) : Pokémon + objets tenus + CT
		# équipées ne doivent pas dépasser le plafond — sinon la run ne
		# démarre pas (cap augmentable à la Boutique d'Améliorations).
		var w   := GameManager.compute_team_weight()
		var cap := GameManager.build_weight_cap
		if w > cap:
			_show_coming_soon("Poids d'équipe trop élevé !\n%d / %d — allège ta compo\nou augmente le plafond\n(Boutique d'Améliorations)." % [w, cap])
			return
	RunManager.inst().test_biome_override = force_biome
	GameManager.run_count += 1
	# start_run() ICI, AVANT le changement de scène : MapGenerator (enfant de
	# CombatArena) génère la 1re zone dans SON _ready(), qui s'exécute AVANT
	# celui de CombatArena (Godot appelle les enfants d'abord) — le reset doit
	# donc être fait par l'appelant, pas par l'arène elle-même, sous peine de
	# lire un rooms_cleared resté à sa valeur de la run précédente.
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")


func _open_starter_selection() -> void:
	_blocked = true
	var screen := StarterSelectionScreen.new()
	screen.layer = 30
	add_child(screen)
	screen.starter_chosen.connect(func(pokemon_id: int) -> void:
		GameManager.selected_starter_id = pokemon_id
		GameManager.unlock_pokemon(pokemon_id)
		GameManager.hub_team       = [pokemon_id]
		GameManager.is_first_run   = false
		GameManager.save_game()
		screen.queue_free()
		_blocked = false
		_refresh_labels()
		if is_instance_valid(_player):
			PMDSprites.get_walk_sprites(pokemon_id, _player, _player._on_sprites)
	, CONNECT_ONE_SHOT)
	# MODE TEST — même flux, mais tout débloqué (cf. GameManager.enable_test_mode)
	screen.test_mode_chosen.connect(func(pokemon_id: int) -> void:
		GameManager.enable_test_mode(pokemon_id)
		screen.queue_free()
		_blocked = false
		_refresh_labels()
		if is_instance_valid(_player):
			PMDSprites.get_walk_sprites(pokemon_id, _player, _player._on_sprites)
	, CONNECT_ONE_SHOT)


## Recharge le sprite incarné si le PREMIER de l'équipe a changé. Mémorise le
## dernier pid appliqué : team_changed est émis à CHAQUE rafraîchissement du
## Pokédex (poids, objet, slots…) — sans ce garde, on relancerait le chargement
## de planche PMD des dizaines de fois pendant une simple session de menu.
var _player_sprite_pid: int = -1

func _refresh_player_sprite() -> void:
	if GameManager.hub_team.is_empty() or not is_instance_valid(_player):
		return
	var pid: int = GameManager.hub_team[0]
	if pid == _player_sprite_pid:
		return
	_player_sprite_pid = pid
	PMDSprites.get_walk_sprites(pid, _player, _player._on_sprites)


func _show_coming_soon(msg: String) -> void:
	_blocked = true
	var canvas := CanvasLayer.new()
	canvas.layer = 25
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.03, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var lbl := Label.new()
	lbl.text = msg
	lbl.position = Vector2(340, 290)
	lbl.size     = Vector2(600, 100)
	lbl.add_theme_font_size_override("font_size", UiKit.scaled_font(22))
	lbl.add_theme_color_override("font_color", Color(0.91, 0.85, 0.70))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	canvas.add_child(lbl)

	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		canvas.queue_free()
		_blocked = false
	)
