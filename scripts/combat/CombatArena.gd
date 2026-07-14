extends Node3D

const WATER_LAYER := 4  # cf. MapGenerator.WATER_LAYER — collision dédiée à l'eau

# ── Caméra HD-2D (angle fixe façon Octopath, comme le Hub) ────────────────
# Même pitch que HubWorld (hauteur:recul = 1:2) mais bien plus reculée : le
# combat temps réel a besoin de voir ~30 tuiles de large (l'ancienne caméra
# 2D en montrait 40 à zoom 2).
const CAM_HEIGHT := 16.0
const CAM_BACK   := 32.0
const CAM_FOV    := 28.0
const CAM_MARGIN := 6.0    # clamp du point visé à l'intérieur de la map

var _map_cells: Vector2i = Vector2i(80, 45)

# ── CS (Capacités Spéciales) — calculées une fois au spawn de l'équipe ──
var _cs_surf_unlocked:  bool = false   # Surf : effet d'équipe (cf. _compute_cs_unlocks)
var _cs_triggers: Array = []   # [{"area":Area3D, "cs_id":String, "prompt":String, "on_use":Callable, "at":Vector3}, ...]
## {} si aucun ; sinon {"cs_id":String, "prompt":String, "on_use":Callable}
## Le prompt/l'interaction ne sont actifs que si le membre CONTRÔLÉ (actif)
## est justement le porteur de cette CS — recalculé chaque frame (cf.
## _refresh_cs_prompt) pour réagir immédiatement à un changement de Pokémon
## actif même sans bouger.
var _near_obstacle: Dictionary = {}
var _near_vendor:   bool = false   # à portée du marchand ([E] pour parler)
var _near_boon:     bool = false   # à portée du don de fin de zone ([E])
var _near_chest_prompt: String = ""   # "" si aucun coffre à portée


# ── Pools ennemis — CENTRALISÉS dans PokePools.gd (le fichier à éditer
# pour changer le casting) ; alias locaux pour garder le code lisible. ──
const POOL_RODENTS       := PokePools.RODENTS
const POOL_BUGS          := PokePools.BUGS
const POOL_FLYERS        := PokePools.FLYERS
const POOL_ELEM          := PokePools.ELEM
const POOL_SEMI_BOSS     := PokePools.SEMI_BOSS
const POOL_CAVE_ELITE    := PokePools.CAVE_ELITE
const POOL_CAVE_DEMIBOSS := PokePools.CAVE_DEMIBOSS
const POOL_BIOME         := PokePools.BIOME

const PLAYER_LEVEL:    int = 10
const SEMI_BOSS_LEVEL: int = 13
const BOSS_LEVEL:      int = 18

# Décalages de spawn pour les membres de l'équipe (unités monde = tuiles)
const SPAWN_OFFSETS: Array = [
	Vector3(0,     0, 0),
	Vector3(4.25,  0, 1.4),
	Vector3(-4.25, 0, 1.4),
	Vector3(0,     0, -4.25),
	Vector3(4.25,  0, -1.4),
	Vector3(-4.25, 0, -1.4),
]

var _team:         Array   = []
var _active_index: int    = 0
var _killed: int = 0
var _alive:  int = 0
var _room_total: int = 0   # nombre total d'ennemis dans la salle courante
var _cache: Dictionary = {}
var _cam: Camera3D = null
var _cam_pos: Vector3 = Vector3.ZERO
var _follow_mode: bool = true

# Ambiance par biome (chantiers 1 & 3 : environment/fog/brume + backdrop/nuages)
var _ambiance: BiomeAmbiance = null

# Système de portes
var _map:           MapBase        = null
var _entry_barrier: StaticBody3D   = null
var _exit_portals:  Array          = []

# ── Grotte (arène de demi-boss) ──────────────────────────────────────
const CAVE_PATH       := "res://scenes/world/CaveArena.tscn"
const CAVE_BOSS_COUNT := 2

var _cave_active:     bool    = false
var _cave_portals:    Array   = []          # déclencheurs grotte / portail retour
var _saved_map:       MapBase = null        # map rocailleuse détachée
var _saved_nodes:     Array   = []          # ennemis + coffres + barrière détachés
var _saved_alive:     int     = 0
var _saved_killed:    int     = 0
var _saved_room_total: int    = 0
var _saved_team_pos:  Array   = []          # positions équipe avant la grotte

# ── Boutique : salle non-combat occasionnelle (vendeur Perrserker) ────
const BOUTIQUE_VENDOR_PID   := PokePools.BOUTIQUE_VENDOR
const BOUTIQUE_SLEEPER_PID  := PokePools.BOUTIQUE_SLEEPER
const BOUTIQUE_WANDERER_PID := PokePools.BOUTIQUE_WANDERER
const BOUTIQUE_MOVE_PRICE   := 110   # ₽ pour apprendre une attaque puissante

var _boutique_active: bool  = false
var _boutique_nodes:  Array = []            # PNJ + déclencheur du vendeur
var _boutique_offers: Array = []            # offre d'attaque par membre vivant
var _boutique_live:   Array = []            # membres vivants (alignés sur _boutique_offers)
var _boutique_screen: BoutiqueScreen = null

# ── Don de fin de zone (façon Hades) ──────────────────────────────────
var _boon_node:   Area3D = null             # item flottant au centre
var _boon_type:   int    = -1               # RunManager.BONUS_SKILL / BONUS_STAT
var _boon_screen: BoutiqueScreen = null     # écran de récompense (skill/stat)

var _pause_screen: PauseMenuScreen = null

@onready var hud          = $HUD

const TEAM_SCENE  := preload("res://scenes/combat/TeamMember.tscn")
const ENEMY_SCENE := preload("res://scenes/combat/EnemyPokemon.tscn")

# ── Multijoueur ───────────────────────────────────────────────────────
# _mp = run multijoueur : l'HÔTE simule les ennemis et fait autorité (spawns,
# dégâts, salle nettoyée, sorties) ; chaque joueur contrôle UN Pokémon (pas
# de switch) et fait autorité sur ses propres PV/position, rediffusés à tous.
var _mp: bool = false
var _net_enemy_counter: int = 0
var _net_pos_accum: float = 0.0
const NET_POS_HZ := 10.0


func _ready() -> void:
	Engine.time_scale = 1.0   # sécurité : un hitstop coupé par un changement de scène pourrait l'avoir laissé à 0
	add_to_group("combat_arena")   # cible des appels add_camera_shake (cf. CombatVFX)
	_mp = Net.in_run
	if _mp:
		Net.server_closed.connect(func() -> void:
			Net.reset()
			get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
		)
	_register_switch_key()
	_map = get_node_or_null("Map") as MapBase
	_refresh_map_bounds()
	RunManager.inst().start_run()
	GameManager.run_money = 0   # les Pokédollars ne survivent pas à la run

	_ambiance = BiomeAmbiance.new()
	_ambiance.name = "Ambiance"
	add_child(_ambiance)
	_apply_ambiance()

	# Pré-découpe des planches d'animation d'attaque — pendant le chargement,
	# pas au premier coup en plein combat (à-coup).
	AttackAnim.warm()

	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_cam_pos = _map.cell_to_world3(_map.entry_tile) if is_instance_valid(_map) \
		else Vector3(_map_cells.x * 0.5, 0, _map_cells.y * 0.5)
	_update_camera()
	_preload_all()


## Configure l'ambiance (environment, fog, lumière, backdrop) selon le thème
## de la map courante — pendant à _theme_config()/_apply_theme() côté tuiles.
func _apply_ambiance() -> void:
	if not is_instance_valid(_ambiance):
		return
	_ambiance.apply_theme(_current_theme(), _map_cells, _cave_active, _map)


func _register_switch_key() -> void:
	if not InputMap.has_action("switch_pokemon"):
		InputMap.add_action("switch_pokemon")
		var ev := InputEventKey.new()
		ev.keycode = KEY_TAB
		InputMap.action_add_event("switch_pokemon", ev)

	if not InputMap.has_action("toggle_follow"):
		InputMap.add_action("toggle_follow")
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_F
		InputMap.action_add_event("toggle_follow", ev2)

	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev3 := InputEventKey.new()
		ev3.keycode = KEY_E
		InputMap.action_add_event("interact", ev3)

	# Fiche d'équipe en temps réel (stats effectives, objets, attaques)
	if not InputMap.has_action("team_stats"):
		InputMap.add_action("team_stats")
		var ev_tab := InputEventKey.new()
		ev_tab.keycode = KEY_TAB
		InputMap.action_add_event("team_stats", ev_tab)

	# Touche dédiée aux CS (Coupe/Surf/Force) — distincte de [E] (coffres)
	if not InputMap.has_action("cs_use"):
		InputMap.add_action("cs_use")
		var ev4 := InputEventKey.new()
		ev4.keycode = KEY_A
		InputMap.action_add_event("cs_use", ev4)


## Échap ouvre le menu pause — sauf si un autre écran (Boutique, don, etc.)
## est déjà ouvert (ils gèrent Échap eux-mêmes via MenuNav) ou si la run
## est terminée (game over / victoire déjà en cours).
var _stats_overlay: TeamStatsOverlay = null

func _unhandled_input(event: InputEvent) -> void:
	# Tab : fiche d'équipe en direct (le jeu CONTINUE derrière — pas de pause)
	if event.is_action_pressed("team_stats"):
		if is_instance_valid(_stats_overlay):
			_stats_overlay.queue_free()
			_stats_overlay = null
		else:
			_stats_overlay = TeamStatsOverlay.new()
			add_child(_stats_overlay)
			_stats_overlay.setup(_team)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_instance_valid(_pause_screen):
		return
	if _boutique_active or is_instance_valid(_boutique_screen) or is_instance_valid(_boon_screen):
		return
	if _game_over_triggered or _victory_triggered:
		return
	_pause_screen = PauseMenuScreen.new()
	add_child(_pause_screen)
	_pause_screen.closed.connect(func() -> void:
		_pause_screen.queue_free()
		_pause_screen = null
	, CONNECT_ONE_SHOT)
	get_viewport().set_input_as_handled()


## Biome Volcan : longer une coulée de lave brûle (statut "burn" → DOT géré
## par TeamMember._tick_status). La lave bloque déjà le passage (collision
## WATER_LAYER) ; on brûle en la côtoyant de trop près.
func _update_lava_burn() -> void:
	if not is_instance_valid(_map) or _current_theme() != MapGenerator.MapTheme.VOLCANO:
		return
	if not _map.has_method("is_water_cell"):
		return
	for m in _team:
		if not is_instance_valid(m) or m.pokemon_instance == null:
			continue
		var cell: Vector2i = _map.world3_to_cell(m.global_position)
		for d: Vector2i in [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _map.is_water_cell(cell + d):
				m.pokemon_instance.apply_status("burn", StatusFx.duration("burn"))
				break


func _process(delta: float) -> void:
	if _team.size() > 0 and is_instance_valid(_team[_active_index]):
		_cam_pos = _cam_pos.lerp(_team[_active_index].global_position, 8.0 * delta)
	_shake = maxf(0.0, _shake - delta * 2.2)
	_update_camera()
	if not _mp or multiplayer.is_server():
		_rescue_stray_enemies(delta)
	_update_surf_state()
	_update_surf_mount()
	_update_lava_burn()

	# Multijoueur (hôte) : diffusion groupée des positions d'ennemis — un
	# seul RPC non-fiable pour toute la meute, à NET_POS_HZ.
	if _mp and multiplayer.is_server():
		_net_pos_accum += delta
		if _net_pos_accum >= 1.0 / NET_POS_HZ:
			_net_pos_accum = 0.0
			var names: PackedStringArray = []
			var poss:  PackedVector3Array = []
			for e in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e) and e.get_parent() == self:
					names.append(String(e.name))
					poss.append(e.global_position)
			if names.size() > 0:
				_net_enemy_positions.rpc(names, poss)

	# Rotation + flottement du don s'il est présent
	if is_instance_valid(_boon_node):
		var spin := _boon_node.get_node_or_null("Spin")
		if spin:
			(spin as Node3D).rotate_y(delta * 1.6)
		_boon_node.position.y += sin(Time.get_ticks_msec() * 0.003) * delta * 0.4

	if Input.is_action_just_pressed("switch_pokemon"):
		_cycle_active()

	if Input.is_action_just_pressed("toggle_follow"):
		_follow_mode = not _follow_mode
		_update_leaders()
		hud.set_follow_mode(_follow_mode)

	_refresh_cs_prompt()
	if Input.is_action_just_pressed("interact"):
		if _near_vendor and not is_instance_valid(_boutique_screen):
			_open_boutique_shop()
		elif _near_boon and not is_instance_valid(_boon_screen):
			_open_boon()
		elif _near_recruit and not is_instance_valid(_recruit_screen):
			_open_recruit_dialog()
	if not _near_obstacle.is_empty() and Input.is_action_just_pressed("cs_use"):
		var cb: Callable = _near_obstacle["on_use"]
		var used_cs: String = _near_obstacle.get("cs_id", "")
		var at: Vector3 = _near_obstacle.get("at", _team[_active_index].global_position if _active_index < _team.size() else Vector3.ZERO)
		_near_obstacle = {}
		_refresh_interact_prompt()
		if cb.is_valid():
			cb.call()
		_play_cs_effect(used_cs, at)
		_spawn_cs_triggers()


## ── Anti-blocage (bug signalé) : certains ennemis spawnaient loin et
## restaient coincés (île, cul-de-sac A*), rendant la salle infinissable.
## Balayage périodique : tout ennemi à plus de RESCUE_DIST du Pokémon
## contrôlé est rapatrié sur une case valide près de l'équipe.
const RESCUE_DIST     := 40.0
const RESCUE_INTERVAL := 8.0
var _rescue_timer: float = 0.0

func _rescue_stray_enemies(delta: float) -> void:
	_rescue_timer += delta
	if _rescue_timer < RESCUE_INTERVAL:
		return
	_rescue_timer = 0.0
	if _team.is_empty() or not is_instance_valid(_map):
		return
	if _active_index >= _team.size() or not is_instance_valid(_team[_active_index]):
		return
	var anchor: Node3D = _team[_active_index]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(anchor.global_position) < RESCUE_DIST:
			continue
		var dest := _valid_cell_near(anchor.global_position, 8.0, 14.0)
		if dest != Vector2i(-1, -1):
			enemy.global_position = _map.cell_to_world3(dest)
			CombatVFX.spawn_death_poof(self, enemy.global_position, Color(0.75, 0.72, 0.9))


## Case de spawn valide dans un anneau [r_min, r_max] autour de `origin`,
## ou (-1,-1) après épuisement des essais.
func _valid_cell_near(origin: Vector3, r_min: float, r_max: float) -> Vector2i:
	for _attempt in 30:
		var ang := randf() * TAU
		var r := randf_range(r_min, r_max)
		var cell := _map.world3_to_cell(origin + Vector3(cos(ang) * r, 0, sin(ang) * r))
		if _map.is_valid_spawn_cell(cell):
			return cell
	return Vector2i(-1, -1)


func _refresh_map_bounds() -> void:
	if is_instance_valid(_map):
		_map_cells = _map.get_map_cell_size()
	else:
		_map_cells = Vector2i(80, 45)


## Secousse de caméra (dégâts subis, ennemis vaincus) — intensité cumulable
## plafonnée, décroissance dans _process. Appelée via le groupe
## "combat_arena" depuis TeamMember/EnemyAI (cf. CombatVFX).
var _shake: float = 0.0

func add_camera_shake(intensity: float) -> void:
	_shake = minf(0.45, _shake + intensity)


# ── Hit-pause (hitstop) ───────────────────────────────────────────────
# Bref gel global à l'impact d'un coup : donne du "poids" aux frappes. On
# passe par Engine.time_scale = 0 et un timer NON affecté par le time_scale
# (ignore_time_scale) pour restaurer la vitesse. Les requêtes concurrentes
# ne font que prolonger la fin (jamais raccourcir).
var _hitstop_gen: int = 0

func request_hitstop(duration: float) -> void:
	_hitstop_gen += 1
	var my_gen := _hitstop_gen
	Engine.time_scale = 0.0
	# process_always=true, process_in_physics=false, ignore_time_scale=true :
	# le timer s'écoule en temps réel malgré le time_scale à 0.
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func() -> void:
		# Ne restaure que si aucune requête plus récente n'est arrivée entre-temps
		# (sinon on couperait un gel prolongé). Le dernier gel gagne.
		if my_gen == _hitstop_gen:
			Engine.time_scale = 1.0
	)


## Caméra à angle fixe façon Octopath (comme HubWorld._update_camera), point
## visé clampé pour ne pas cadrer le vide au-delà des bords de la map.
func _update_camera() -> void:
	if not is_instance_valid(_cam):
		return
	var target := _cam_pos
	target.x = clampf(target.x, CAM_MARGIN, float(_map_cells.x) - CAM_MARGIN)
	target.z = clampf(target.z, CAM_MARGIN, float(_map_cells.y) - CAM_MARGIN)
	# Suit légèrement le relief (collines douces) sous le point visé — la
	# caméra "respire" avec le terrain au lieu de rester à plat en permanence.
	target.y = _map.get_height_at_world(target) if is_instance_valid(_map) else 0.0
	var shake_off := Vector3.ZERO
	if _shake > 0.001:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake
	_cam.position = target + Vector3(0, CAM_HEIGHT, CAM_BACK) + shake_off
	_cam.look_at(target + Vector3(0, 0.9, 0), Vector3.UP)


# ── Chargement ────────────────────────────────────────────────────────

func _preload_all() -> void:
	# Équipe résolue : forme de départ après Super Bonbons (peut être évoluée)
	# — on précharge la FORME FINALE, pas la base.
	var team_ids: Array = []
	if _mp:
		# Multijoueur : un Pokémon par joueur (choisi au lobby), niveau de
		# base — pas de Super Bonbons ni d'objets du hub (équité entre pairs).
		for id in Net.player_order():
			team_ids.append(int(Net.players[id]["pid"]))
	else:
		for base_pid: int in GameManager.get_run_team():
			var eff := GameManager.get_effective_start(base_pid, PLAYER_LEVEL)
			team_ids.append(int(eff["id"]))
	var priority_seen: Dictionary = {}

	# Phase 1 (bloquante) : équipe + salle 0 (rodents + bugs + faune du biome
	# courant) → zone démarre dès que c'est prêt
	var first_room: Array = []
	first_room.append_array(POOL_RODENTS)
	first_room.append_array(POOL_BUGS)
	first_room.append_array(POOL_BIOME.get(_current_theme(), []))
	var priority_ids: Array = team_ids.duplicate()
	for eid: int in first_room:
		if not priority_seen.has(eid):
			priority_seen[eid] = true
			priority_ids.append(eid)
	for id in priority_ids:
		priority_seen[id] = true

	var total: int   = priority_ids.size()
	var counter: Array = [0]
	for id in priority_ids:
		PokemonAPI.get_pokemon(id, func(data: Dictionary) -> void:
			if not is_instance_valid(self): return
			if not data.is_empty():
				_cache[str(int(data["id"]))] = PokemonData.from_api(data)
			counter[0] += 1
			if counter[0] >= total:
				_preload_moves()
		)

	# Phase 2 (arrière-plan) : pools des salles suivantes + faunes des AUTRES
	# biomes (le thème change à chaque transition de zone — ils doivent être
	# en cache avant que le joueur franchisse un portail)
	var background: Array = []
	background.append_array(POOL_FLYERS)
	background.append_array(POOL_ELEM)
	background.append_array(POOL_SEMI_BOSS)
	background.append_array(PokePools.all_champion_ids())   # compos du Dresseur Final
	background.append_array(POOL_CAVE_ELITE)
	background.append_array(POOL_CAVE_DEMIBOSS)
	for t in POOL_BIOME:
		background.append_array(POOL_BIOME[t])
	# TOUTE la chaîne d'évolution de chaque espèce des viviers — les actes
	# 2+ font apparaître les formes évoluées (cf. _pool_for_room) : sans ce
	# préchargement, elles manquaient au cache et les vagues sortaient
	# VIDES (salle insoluble, cf. bug "plus d'ennemis en fin de run").
	var with_evos: Array = background.duplicate()
	for eid: int in background:
		var cur: int = eid
		while GameManager.EVOLUTIONS.has(cur):
			cur = int(GameManager.EVOLUTIONS[cur]["evolves_to"])
			with_evos.append(cur)
	for eid: int in with_evos:
		if not priority_seen.has(eid):
			priority_seen[eid] = true
			PokemonAPI.get_pokemon(eid, func(data: Dictionary) -> void:
				if not is_instance_valid(self): return
				if not data.is_empty():
					_cache[str(int(data["id"]))] = PokemonData.from_api(data)
			)


func _preload_moves() -> void:
	# Déduplique par id pour ne charger chaque Pokémon qu'une fois
	var unique: Dictionary = {}
	for key in _cache:
		var pd: PokemonData = _cache[key]
		unique[pd.id] = pd

	# Collecte tous les noms de moves uniques à fetcher (level ≤ PLAYER_LEVEL + 20, max 10 par Pokémon)
	# move_owners : name → Array of {pd, level}
	var move_owners: Dictionary = {}
	for pd_id in unique:
		var pd: PokemonData = unique[pd_id]
		var count := 0
		for lm: Dictionary in pd.level_up_moves:
			if int(lm["level"]) <= PLAYER_LEVEL + 20 and count < 10:
				var mname: String = lm["name"]
				if not move_owners.has(mname):
					move_owners[mname] = []
				move_owners[mname].append({"pd": pd, "level": int(lm["level"])})
				count += 1

	# Injecte les capacités permanentes achetées au hub pour tous les Pokémon
	for pm_name in GameManager.purchased_move_names:
		if not move_owners.has(pm_name):
			move_owners[pm_name] = []
		for pd_id in unique:
			move_owners[pm_name].append({"pd": unique[pd_id], "level": 0})

	var all_names: Array = move_owners.keys()
	if all_names.is_empty():
		_start_zone()
		return

	var total   := all_names.size()
	var counter := [0]

	for raw_name in all_names:
		var mname: String   = raw_name
		var entries: Array  = move_owners[mname]

		PokemonAPI.get_move(mname, func(move_data: Dictionary) -> void:
			var power_v: Variant = move_data.get("power")
			var power: int = int(power_v) if power_v != null else 0
			# Les CT de statut (puissance 0) sont désormais chargées elles
			# aussi — leur "effet" réel (soin, altération garantie) vient de
			# MoveShopScreen.MOVE_LIST, cf. boucle ci-dessous.
			if not move_data.is_empty():
				var ct_effect: Dictionary = {}
				for m: Dictionary in MoveShopScreen.MOVE_LIST:
					if str(m.get("api", "")) == mname:
						ct_effect = m.get("effect", {})
						break
				for entry: Dictionary in entries:
					var pd: PokemonData = entry["pd"]
					var lv: int         = entry["level"]
					var md := MoveData.new()
					md.api_name     = mname
					var fr: String  = move_data.get("name_fr", "")
					md.display_name = fr if not fr.is_empty() else mname.replace("-", " ").capitalize()
					md.type         = move_data.get("type", "normal")
					md.power        = power
					md.damage_class = move_data.get("damage_class", "physical")
					md.level_learned = lv
					md.effect       = ct_effect
					pd.preloaded_moves.append(md)
			counter[0] += 1
			if counter[0] >= total:
				# Trie les moves de chaque Pokémon par niveau croissant
				for pd_id in unique:
					var pd: PokemonData = unique[pd_id]
					pd.preloaded_moves.sort_custom(func(a: MoveData, b: MoveData) -> bool:
						return a.level_learned < b.level_learned
					)
				_start_zone()
		)


# ── Démarrage de zone ─────────────────────────────────────────────────

func _start_zone() -> void:
	_refresh_map_bounds()
	_alive      = 0
	_killed     = 0
	_room_total = 0
	_spawn_team()
	hud.announce_zone(_zone_label())   # le nom de la zone en grand, fondu + glow
	# Salle-boutique : pas de combat — le vendeur Perrserker et ses PNJ, puis
	# on repart par un portail de sortie (cf. _enter_boutique).
	if _is_shop_room(RunManager.inst().rooms_cleared):
		_enter_boutique()
		return
	_spawn_entry_barrier()
	_spawn_chests()
	# Grotte : déclencheur posé seulement une fois la salle nettoyée
	# (cf. _show_run_status) — pas de détour d'élite en plein combat.
	_spawn_cs_triggers()
	# Les maisons/tunnels de sortie sont visibles DÈS L'ENTRÉE dans la salle
	# (retour joueurs) — mais fermées (pas de halo, pas de trigger) tant que
	# la salle n'est pas nettoyée (cf. _open_exit_doors dans _on_room_cleared).
	_spawn_exit_doors_closed()
	hud.set_wave(_zone_label())
	hud.set_kills(0, 0)
	await get_tree().create_timer(1.2).timeout
	await _net_zone_barrier()
	_spawn_room_enemies()


func _spawn_team() -> void:
	if _mp:
		_spawn_team_mp()
		return
	var team_ids: Array[int] = GameManager.get_run_team()
	# Spawn juste au-dessus de l'entrée (pas au centre de la map)
	var spawn_center: Vector3
	if is_instance_valid(_map):
		spawn_center = _map.cell_to_world3(_map.entry_tile + Vector2i(0, -4))
	else:
		spawn_center = Vector3(_map_cells.x * 0.5, 0, _map_cells.y * 0.5)

	for i in team_ids.size():
		var base_pid: int = team_ids[i]
		var eff := GameManager.get_effective_start(base_pid, PLAYER_LEVEL)
		var id: int  = int(eff["id"])
		var data: PokemonData = _cache.get(str(id))
		if not data:
			push_error("Pokémon introuvable pour id=%d" % id)
			continue

		var instance := PokemonInstance.new(data, int(eff["level"]))
		instance.init_moves()
		# Objet tenu assigné à ce Pokémon (clé = id de base, avant évolution)
		var held: String = GameManager.get_assigned_item(base_pid)
		if held != "":
			instance.equip_catalog_item(held)
		var member   = TEAM_SCENE.instantiate()
		add_child(member)
		member.global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]

		var is_active := i == 0
		member.setup(instance, i, is_active)
		_team.append(member)
		_wire_team_member(member, i)

	# Centre la caméra immédiatement sur le premier membre
	_cam_pos = _team[0].global_position
	_update_camera()

	# Leader initial pour les compagnons
	_update_leaders()

	# Initialise le HUD équipe
	var instances: Array = []
	for m in _team:
		instances.append(m.pokemon_instance)
	hud.setup_team(instances, 0)
	hud.setup_player(_team[0].pokemon_instance)
	hud.setup_moves(_team[0].pokemon_instance.equipped_moves)
	_connect_move_signal(0)
	_apply_hub_items()
	_compute_cs_unlocks(team_ids)


## Branche un TeamMember sur le HUD (les lambdas capturent l'index par
## valeur). Partagé entre le spawn initial et le recrutement en run.
func _wire_team_member(member, idx: int) -> void:
	member.hp_changed.connect(func(ratio: float) -> void:
		hud.update_team_hp(idx, ratio)
		if idx == _active_index:
			hud.update_hp(ratio)
	)
	member.cooldown_changed.connect(func(ratio: float) -> void:
		if idx == _active_index:
			hud.update_cooldown(ratio)
	)
	member.xp_changed.connect(func(ratio: float, lv: int) -> void:
		hud.update_team_level(idx, lv)
		hud.update_team_xp(idx, ratio)
		if idx == _active_index:
			hud.update_xp(ratio, lv)
	)
	member.leveled_up.connect(func(lv: int) -> void:
		if idx == _active_index:
			hud.show_levelup(lv)
	)
	member.evolved.connect(func(name_fr: String) -> void:
		hud.notify("✦  %s a évolué !" % name_fr.capitalize(), Color(0.72, 0.55, 0.95))
	)
	member.portrait_ready.connect(func(midx: int, tex: Texture2D) -> void:
		hud.update_team_portrait(midx, tex)
		if midx < _team.size() and is_instance_valid(_team[midx]):
			_team[midx].pokemon_instance.portrait_texture = tex
	)
	member.died.connect(_on_team_member_died.bind(idx))
	member.dash_changed.connect(func(charges: int, max_c: int) -> void:
		if idx == _active_index:
			hud.update_dash(charges, max_c)
	)


## Multijoueur : un TeamMember par joueur connecté, dans l'ordre stable du
## registre (identique sur tous les pairs → mêmes noms de nœuds "P<peer>",
## indispensable pour cibler les RPC). Seul le membre du joueur LOCAL est
## contrôlé (is_active) ; les autres sont des copies pilotées à distance.
## Pas de compagnons IA, pas de switch, pas d'objets du hub.
func _spawn_team_mp() -> void:
	var spawn_center: Vector3
	if is_instance_valid(_map):
		spawn_center = _map.cell_to_world3(_map.entry_tile + Vector2i(0, -4))
	else:
		spawn_center = Vector3(_map_cells.x * 0.5, 0, _map_cells.y * 0.5)

	var order := Net.player_order()
	var local_peer := Net.local_id()

	for i in order.size():
		var peer: int = order[i]
		var pid: int  = int(Net.players[peer]["pid"])
		var data: PokemonData = _cache.get(str(pid))
		if not data:
			push_error("MP: Pokémon introuvable pour pid=%d (joueur %s)" % [pid, str(Net.players[peer]["name"])])
			continue

		var instance := PokemonInstance.new(data, PLAYER_LEVEL)
		instance.init_moves()
		var chosen_item: String = str(Net.players[peer].get("item", ""))
		if chosen_item != "":
			instance.equip_catalog_item(chosen_item)
		var member = TEAM_SCENE.instantiate()
		member.name = "P%d" % peer
		add_child(member)
		member.global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]

		var is_local := peer == local_peer
		member.setup(instance, i, is_local)
		if not is_local:
			member.remote_peer = peer
		else:
			_active_index = i
		_team.append(member)

		var idx := i
		member.hp_changed.connect(func(ratio: float) -> void:
			hud.update_team_hp(idx, ratio)
			if idx == _active_index:
				hud.update_hp(ratio)
		)
		member.cooldown_changed.connect(func(ratio: float) -> void:
			if idx == _active_index:
				hud.update_cooldown(ratio)
		)
		member.xp_changed.connect(func(ratio: float, lv: int) -> void:
			hud.update_team_level(idx, lv)
			hud.update_team_xp(idx, ratio)
			if idx == _active_index:
				hud.update_xp(ratio, lv)
		)
		member.leveled_up.connect(func(lv: int) -> void:
			if idx == _active_index:
				hud.show_levelup(lv)
		)
		member.evolved.connect(func(name_fr: String) -> void:
			hud.notify("✦  %s a évolué !" % name_fr.capitalize(), Color(0.72, 0.55, 0.95))
		)
		member.portrait_ready.connect(func(midx: int, tex: Texture2D) -> void:
			hud.update_team_portrait(midx, tex)
			_team[midx].pokemon_instance.portrait_texture = tex
		)
		member.died.connect(_on_team_member_died.bind(idx))
		member.dash_changed.connect(func(charges: int, max_c: int) -> void:
			if idx == _active_index:
				hud.update_dash(charges, max_c)
		)

	if _team.is_empty():
		push_error("MP: aucun membre spawné — retour au hub.")
		Net.reset()
		get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
		return

	_cam_pos = _team[_active_index].global_position
	_update_camera()

	var instances: Array = []
	for m in _team:
		instances.append(m.pokemon_instance)
	hud.setup_team(instances, _active_index)
	hud.setup_player(_team[_active_index].pokemon_instance)
	hud.setup_moves(_team[_active_index].pokemon_instance.equipped_moves)
	_connect_move_signal(_active_index)
	# Applique le masque de collision eau (CS Surf) — sans quoi les membres
	# garderaient le masque par défaut et marcheraient sur l'eau.
	_compute_cs_unlocks([] as Array[int])


## Quelles CS l'équipe peut utiliser — désormais basé UNIQUEMENT sur la
## possession (achat), plus d'assignation à un Pokémon précis : n'importe
## quel membre peut s'en servir (touche A près d'un obstacle).
func _compute_cs_unlocks(_team_ids: Array[int]) -> void:
	_cs_surf_unlocked = GameManager.owns_cs("cs_surf")
	_apply_water_mask()


# ── Surf : posséder la CS ne suffit pas — il faut MONTER (touche A au bord
# de l'eau) pour que l'équipe puisse traverser ; on démonte automatiquement
# en revenant s'éloigner sur la terre ferme. ──────────────────────────────
var _surf_active: bool = false

## L'eau bloque tant qu'on n'a pas activé le surf (touche A au bord).
func _apply_water_mask() -> void:
	for m in _team:
		if is_instance_valid(m):
			m.collision_mask = 1 if _surf_active else (1 | WATER_LAYER)


func _mount_surf() -> void:
	_surf_active = true
	_apply_water_mask()
	Sfx.play("dash", -6.0)


## La case du corps est-elle de l'eau ?
func _is_on_water(body: Node3D) -> bool:
	if not is_instance_valid(_map) or not _map.has_method("world3_to_cell") \
			or _map.get("_water") == null:
		return false
	var cell: Vector2i = _map.world3_to_cell(body.global_position)
	return _map._water.get_cell_source_id(cell) != -1


## Le membre actif touche-t-il le bord de l'eau (sa case ou une voisine) ?
func _active_near_water() -> bool:
	if _active_index >= _team.size() or not is_instance_valid(_team[_active_index]):
		return false
	if not is_instance_valid(_map) or not _map.has_method("world3_to_cell") \
			or _map.get("_water") == null:
		return false
	var cell: Vector2i = _map.world3_to_cell(_team[_active_index].global_position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _map._water.get_cell_source_id(cell + Vector2i(dx, dy)) != -1:
				return true
	return false


## Démontage automatique : toute l'équipe au sec et l'actif éloigné du bord.
func _update_surf_state() -> void:
	if not _surf_active:
		return
	for m in _team:
		if is_instance_valid(m) and _is_on_water(m):
			return   # quelqu'un surfe encore — ne pas re-bloquer l'eau sous lui
	if _active_near_water():
		return       # encore au bord : on reste prêt à repartir
	_surf_active = false
	_apply_water_mask()


func _apply_hub_items() -> void:
	for item_id: String in GameManager.owned_items:
		match item_id:
			"x_attack":
				for m in _team:
					m.pokemon_instance.attack_mult *= 1.2
			"x_defend":
				for m in _team:
					m.pokemon_instance.defense_mult *= 1.2
			"x_speed":
				for m in _team:
					m.pokemon_instance.speed_mult *= 1.2
			"boost_hp":
				for m in _team:
					m.pokemon_instance.apply_hp_boost(1.2)
	# Les items sont consommés à l'entrée en run
	GameManager.owned_items.clear()


# ── Gestion de l'équipe ───────────────────────────────────────────────

func _cycle_active() -> void:
	if _mp:
		return   # multijoueur : un Pokémon par joueur, pas de switch
	var old_idx := _active_index
	var next    := (old_idx + 1) % _team.size()

	# Cherche le prochain membre en vie
	var attempts := 0
	while _team[next].pokemon_instance.is_fainted() and attempts < _team.size():
		next = (next + 1) % _team.size()
		attempts += 1

	if next == old_idx:
		return  # tous KO ou 1 seul membre

	_set_active(next)


func _set_active(idx: int) -> void:
	_team[_active_index].is_active = false
	_active_index = idx
	_team[idx].is_active = true
	_update_leaders()

	hud.setup_player(_team[idx].pokemon_instance)
	hud.setup_moves(_team[idx].pokemon_instance.equipped_moves)
	hud.set_active_slot(idx)
	hud.update_dash(_team[idx]._dash_charges, _team[idx].dash_max_charges)
	_connect_move_signal(idx)


func _connect_move_signal(idx: int) -> void:
	for m in _team:
		if not is_instance_valid(m):
			continue
		for conn: Dictionary in m.move_selected.get_connections():
			var cb: Callable = conn["callable"]
			if m.move_selected.is_connected(cb):
				m.move_selected.disconnect(cb)
	if is_instance_valid(_team[idx]):
		_team[idx].move_selected.connect(func(midx: int) -> void: hud.set_active_move(midx))


func _update_leaders() -> void:
	var leader: Node3D = _team[_active_index] if _follow_mode else null
	for i in _team.size():
		if i != _active_index:
			_team[i]._leader = leader


# ── Combat — salle unique ─────────────────────────────────────────────

# Structure de run en ACTES — déléguée à RunManager (5 combats → Boutique →
# Boss par acte ; le boss du dernier acte est le Dresseur Final).
func _is_boss_room(room: int) -> bool:
	return RunManager.inst().is_boss_room(room)

func _is_final_boss_room(room: int) -> bool:
	return RunManager.inst().is_final_boss_room(room)


# ── Vagues : les ennemis d'une salle arrivent en 1 à 4 vagues — moins
# d'adversaires simultanés, surtout en début de run (le "tout d'un coup"
# rendait la salle 1 létale). File consommée par _on_enemy_died.
var _wave_queue: Array = []   # vagues restantes : Array[Array[spawn_spec]]
var _wave_num:   int   = 0
var _waves_total: int  = 0
var _current_trainer: TrainerNPC = null   # dresseur visible pendant un combat de boss


func _spawn_room_enemies() -> void:
	var room  := RunManager.inst().rooms_cleared
	var act   := RunManager.inst().act_of(room)
	# Courbe lissée : effectif +1/salle (plafond qui MONTE avec l'acte, pas
	# figé — sinon la difficulté stagne dès l'acte 2, cf. retour joueurs),
	# niveau +1.5/salle +3/acte, et un champion d'élite qui incarne
	# visiblement la montée en danger.
	var lv    := PLAYER_LEVEL + int(room * 1.5) + act * 3
	var pool  := _pool_for_room(room)

	# 5 à 9 VAGUES par salle de combat (retour joueurs) — tirage SEEDÉ (dérivé
	# de la graine de zone en multi → même nb de vagues chez tous les pairs).
	# L'effectif par vague grandit avec la salle/l'acte (1→3), plafonné, pour
	# que le rythme « vague après vague » reste tenable.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = (Net.zone_seed(room) if Net.in_run else randi()) ^ 0x5A5A
	var wave_count := wrng.randi_range(5, 9)
	var per_wave   := clampi(1 + int(room / 3) + act, 1, 3)
	var count := mini(wave_count * per_wave, 24)

	_wave_queue.clear()
	_wave_num    = 0
	_waves_total = 1

	if _is_boss_room(room):
		# ── BOSS D'ACTE = COMBAT DE DRESSEUR : la compo COMPLÈTE du champion
		# de l'acte (cf. RunManager.champion_for_act, jamais le même deux fois
		# par run) — TOUJOURS 6 vagues, une par Pokémon de l'équipe, l'AS en
		# dernier (anneau doré). Chaque vague envoie la forme ÉVOLUÉE de son
		# Pokémon comme "boss", escortée de sbires à la forme DE BASE de la
		# même lignée (ex : Steelix + des Onix) — un vrai combat de dresseur
		# expérimenté, pas un simple face-à-face 1v1. (`act` déjà calculé en
		# haut de fonction, cf. mise à l'échelle de la difficulté.)
		var comp: Dictionary = RunManager.inst().champion_for_act(act)
		var comp_ids: Array = comp["ids"]
		_waves_total = comp_ids.size()
		for w in _waves_total:
			var is_ace := w == _waves_total - 1
			var boss_id: int   = GameManager.final_evolution_of(int(comp_ids[w]))
			var minion_id: int = GameManager.base_species_of(boss_id)
			var boss_lv := BOSS_LEVEL + room + w * 2
			var specs: Array = [
				{"pool": [boss_id], "count": 1, "lv": boss_lv,
					"champion": not is_ace, "boss": is_ace},
			]
			# Sbires = la forme de base de la même lignée, en escorte (aucun
			# sbire si le boss est déjà une forme sans évolution possible).
			# Effectif croissant avec l'acte (retour joueurs : les combats de
			# boss manquaient de monde).
			if minion_id != boss_id:
				specs.append({"pool": [minion_id], "count": 3 + act,
					"lv": maxi(1, boss_lv - 6), "champion": false, "boss": false})
			_wave_queue.append(specs)
		_room_total = 0
		for specs: Array in _wave_queue:
			for s: Dictionary in specs:
				_room_total += int(s["count"])
		hud.set_kills(0, _room_total)

		# Le champion s'adresse au joueur avant l'arrivée de ses Pokémon (même
		# kit visuel que les menus) — texte en machine à écrire, non bloquant :
		# il se ferme tout seul PENDANT que le combat démarre déjà.
		var dlg := ChampionDialogueScreen.new()
		get_tree().root.add_child(dlg)
		dlg.setup(str(comp["name"]), str(comp["type"]))
		_spawn_champion_trainer(comp)

		# Musique de combat de dresseur — en boucle tant que le boss tient
		Sfx.play_music(Sfx.BGM_BOSS)

		var title := "DRESSEUR FINAL" if _is_final_boss_room(room) else "CHAMPION"
		hud.set_wave("☠☠ %s %s (%s) — son équipe de %d t'attend !"
			% [title, str(comp["name"]).to_upper(), comp["type"], _waves_total])
		get_tree().call_group("combat_arena", "add_camera_shake", 0.15)
		await get_tree().create_timer(1.8).timeout   # temps de lire l'annonce
		if _game_over_triggered or _victory_triggered:
			return
		_spawn_next_wave()
		return

	# Champions : 1 dès la salle 3, 2 dès la salle 6, +1 par acte au-delà du
	# premier — tirés de la faune du biome (l'"alpha" local), +4 niveaux,
	# dans la DERNIÈRE vague.
	var champions := 0
	if room >= 5:   champions = 2
	elif room >= 2: champions = 1
	if champions > 0:
		champions += act
	var champ_pool: Array = []
	if champions > 0:
		var biome: Array = POOL_BIOME.get(_current_theme(), [])
		champ_pool = biome if not biome.is_empty() else Array(pool)

	# Répartit l'effectif sur les 5-9 vagues tirées ci-dessus.
	_waves_total = clampi(wave_count, 1, maxi(1, count))
	var base := count / _waves_total
	var rem  := count % _waves_total
	for w in _waves_total:
		var n := base + (1 if w < rem else 0)
		var specs: Array = [{"pool": Array(pool), "count": n, "lv": lv, "champion": false, "boss": false}]
		if w == _waves_total - 1 and champions > 0:
			specs.append({"pool": champ_pool, "count": champions, "lv": lv + 4, "champion": true, "boss": false})
		_wave_queue.append(specs)

	_room_total = count + champions
	hud.set_kills(0, _room_total)
	_spawn_next_wave()


func _spawn_next_wave() -> void:
	if _wave_queue.is_empty():
		return
	var specs: Array = _wave_queue.pop_front()
	_wave_num += 1
	for spec: Dictionary in specs:
		var typed_pool: Array[int] = []
		for eid: int in spec["pool"]:
			typed_pool.append(eid)
		_spawn_from_pool(typed_pool, spec["count"], spec["lv"], spec["champion"], spec["boss"])
	var lv0: int = (specs[0] as Dictionary)["lv"]
	if _waves_total > 1:
		hud.set_wave("%s · Vague %d/%d · Niv. %d" % [_zone_label(), _wave_num, _waves_total, lv0])
	else:
		hud.set_wave("%s · %d ennemis · Niv. %d" % [_zone_label(), _room_total, lv0])

	# Filet anti-blocage : si RIEN n'a pu apparaître (_alive est réservé de
	# façon synchrone par _spawn_from_pool), la salle serait insoluble — on
	# enchaîne au lieu d'attendre une mort qui ne viendra jamais.
	if _alive <= 0 and (not _mp or multiplayer.is_server()):
		push_warning("CombatArena: vague %d vide (aucun spawn possible) — on enchaîne." % _wave_num)
		_room_total = maxi(0, _room_total - _wave_size_estimate(specs))
		hud.set_kills(_killed, _room_total)
		if not _wave_queue.is_empty():
			_spawn_next_wave()
		else:
			_on_room_cleared()


func _wave_size_estimate(specs: Array) -> int:
	var n := 0
	for spec: Dictionary in specs:
		n += int(spec["count"])
	return n


## Instancie le dresseur champion dans l'arène (planté près de la sortie
## nord), visible pendant tout le combat — cf. TrainerNPC.flee_to() pour
## sa fuite une fois sa compo vaincue.
func _spawn_champion_trainer(comp: Dictionary) -> void:
	if is_instance_valid(_current_trainer):
		_current_trainer.queue_free()
		_current_trainer = null
	var sprite_path := PokePools.champion_sprite_path(str(comp["name"]))
	if sprite_path == "" or not is_instance_valid(_map):
		return
	var trainer := TrainerNPC.new()
	add_child(trainer)
	trainer.position = _map.cell_to_world3(_map.exit_B)
	trainer.setup(sprite_path)
	_current_trainer = trainer


## "Forêt — Salle 3" : le nom du biome courant + le numéro de salle — la
## progression se lit d'un coup d'œil au HUD.
func _zone_label() -> String:
	var names := {
		MapGenerator.MapTheme.FOREST: "Forêt",
		MapGenerator.MapTheme.SWAMP:  "Marécage",
		MapGenerator.MapTheme.MEADOW: "Prairie",
		MapGenerator.MapTheme.ROCKY:  "Éboulis",
		MapGenerator.MapTheme.AUTUMN: "Bois d'automne",
		MapGenerator.MapTheme.LAKE:   "Lac",
		MapGenerator.MapTheme.VOLCANO: "Volcan",
	}
	return "%s — %s" % [names.get(_current_theme(), "Zone"), RunManager.inst().get_zone_name()]


func _pool_for_room(room: int) -> Array[int]:
	var pool: Array[int] = []
	pool.append_array(POOL_RODENTS)
	pool.append_array(POOL_BUGS)
	if room >= 2: pool.append_array(POOL_FLYERS)
	if room >= 3: pool.append_array(POOL_ELEM)
	if room >= 4: pool.append_array(POOL_SEMI_BOSS)
	# Faune du biome courant, en double pondération — la population locale
	# domine la composition sans exclure les espèces communes.
	var biome: Array = POOL_BIOME.get(_current_theme(), [])
	for i in 2:
		for eid: int in biome:
			pool.append(eid)

	# Les seuils ci-dessus étaient tous franchis dès la salle 4 (bien avant
	# la fin de l'acte 1, cf. RunManager.ROOMS_PER_ACT) : la composition ne
	# variait plus jamais après ça, la run "s'aplatissait" dès l'acte 2
	# (retour joueurs). On fait évoluer une partie croissante du vivier
	# vers sa forme FINALE selon l'acte — déterministe (pas de RNG ici, pour
	# rester identique sur tous les pairs en multijoueur) : acte 1 = tel
	# quel, acte 2 = un ennemi sur deux évolué, acte 3+ = tous évolués.
	var act := RunManager.inst().act_of(room)
	if act == 1:
		for i in pool.size():
			if i % 2 == 0:
				pool[i] = GameManager.final_evolution_of(pool[i])
	elif act >= 2:
		for i in pool.size():
			pool[i] = GameManager.final_evolution_of(pool[i])
	return pool


## Thème (MapGenerator.MapTheme) de la map courante — FOREST par défaut si
## la map n'expose pas de thème (scènes legacy).
func _current_theme() -> int:
	var theme_v: Variant = _map.get("theme") if is_instance_valid(_map) else null
	return int(theme_v) if theme_v != null else MapGenerator.MapTheme.FOREST


func _on_room_cleared() -> void:
	var room := RunManager.inst().rooms_cleared
	# Vaincre le boss de la salle VICTORY_ROOM = victoire de run — le jeu
	# n'avait jusqu'ici qu'une fin par défaite.
	if _is_final_boss_room(room):
		_run_victory()
		return

	# Courbe adoucie (retour joueurs : "trop riche dès le biome 3") — la
	# salle 15 rapportait 330 ₽, elle en rapporte maintenant 145.
	var gold := 25 + room * 8
	if _is_boss_room(room):
		# Butin de boss NETTEMENT plus généreux, croissant avec l'acte : ₽ ×4
		# + un gros lot de Baies + des Éclats de Champion (ressource), et un
		# badge de gloire à la première victoire (cf. _reward_boss).
		gold *= 4
		Sfx.play_music(Sfx.BGM_VICTORY)   # jusqu'au changement de zone
		if is_instance_valid(_current_trainer) and is_instance_valid(_map):
			_current_trainer.flee_to(_map.cell_to_world3(_map.exit_B))
			_current_trainer = null
		_reward_boss(room)
	if _mp:
		_net_room_cleared.rpc(gold)   # chaque client touche le même butin
	GameManager.add_run_money(gold)
	hud.update_money(GameManager.run_money)
	hud.set_wave("Salle libérée !  +%d ₽" % gold)
	hud.set_kills(_killed, _room_total)
	await get_tree().create_timer(0.8).timeout
	# Don façon Hades : un item apparaît au CENTRE (type annoncé par la porte
	# choisie pour entrer ici) ; les portes de sortie (déjà là mais fermées,
	# cf. _spawn_exit_doors_closed) s'OUVRENT en parallèle.
	_spawn_boon(RunManager.inst().current_zone_bonus)
	if _exit_portals.is_empty():
		_spawn_exit_portals()   # filet de sécurité si jamais rien n'a été posé
	else:
		_open_exit_doors()
	_spawn_cave_portals()


## Fin de run victorieuse : gros butin, jingle, retour au hub.
var _victory_triggered: bool = false

func _run_victory() -> void:
	if _victory_triggered or _game_over_triggered:
		return
	_victory_triggered = true
	# Multijoueur : la victoire n'est détectée que chez l'hôte (seul à
	# compter les morts d'ennemis) — il la diffuse à tous les clients.
	if _mp and multiplayer.is_server():
		_net_victory.rpc()
	var gold := 500 + RunManager.inst().rooms_cleared * 30
	GameManager.add_gold(gold)
	Sfx.play("victory")
	hud.set_wave("🏆 VICTOIRE !  Le boss est vaincu — +%d Baies" % gold)
	get_tree().call_group("combat_arena", "add_camera_shake", 0.2)
	await get_tree().create_timer(4.0).timeout
	if _mp:
		Net.reset()
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


@rpc("authority", "call_remote", "reliable")
func _net_victory() -> void:
	_run_victory()


# ── Récompense de boss + recrutement d'un Pokémon du dresseur ──────────
var _recruit_node: Area3D = null
var _recruit_pid:  int    = 0
var _near_recruit: bool   = false
var _recruit_screen: CanvasLayer = null

## Butin de boss : gros lot de Baies + Éclats de Champion (ressource
## persistante, cf. GameManager) croissant avec l'acte, badge de gloire à
## la première victoire, et — en solo, première victoire — un Pokémon du
## dresseur qui reste au sol pour être recruté (cf. _spawn_recruit).
func _reward_boss(room: int) -> void:
	var act := RunManager.inst().act_of(room)
	var champ: Dictionary = RunManager.inst().champion_for_act(act)
	var champ_name: String = str(champ.get("name", "Champion"))

	var berries := 120 + act * 80
	var shards  := 1 + act
	if _is_final_boss_room(room):
		berries += 300
		shards  += 3
	GameManager.add_gold(berries)
	GameManager.add_champion_shards(shards)
	var first := GameManager.record_champion_win(champ_name)
	GameManager.save_game()   # badges/éclats persistent tout de suite

	hud.notify("🏅 +%d Baies · +%d Éclat%s de Champion" % [berries, shards, "s" if shards > 1 else ""],
		Color(0.95, 0.78, 0.28))
	if first:
		hud.notify("🎖 Badge de %s obtenu !" % champ_name, Color(0.95, 0.82, 0.35))
		# Recrutement : seulement en solo (en multi chacun n'a qu'un Pokémon,
		# une recrue IA désynchroniserait la composition d'équipe).
		if not _mp:
			_spawn_recruit(champ)


## Fait apparaître un Pokémon du dresseur, endormi au sol (sprite « sleep »),
## près du centre — le joueur va lui parler avec [E] pour le recruter.
func _spawn_recruit(champ: Dictionary) -> void:
	if not is_instance_valid(_map):
		return
	if _team.size() >= GameManager.get_max_team_size():
		hud.notify("Équipe pleine — impossible de recruter", Color(0.80, 0.55, 0.30))
		return
	var ids: Array = champ.get("ids", [])
	if ids.is_empty():
		return
	# Forme de BASE d'un membre au hasard : recrutable + évoluera par le niveau.
	var pick: int = GameManager.base_species_of(int(ids[randi() % ids.size()]))
	_recruit_pid = pick
	_load_recruit(pick)   # espèce + attaques en cache pour le moment du recrutement

	var sz := _map.get_map_cell_size()
	var cell := Vector2i(sz.x / 2, sz.y / 2 + 2)
	var area := Area3D.new()
	area.position        = _map.cell_to_world3(cell)
	area.collision_layer = 0
	area.collision_mask  = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.5
	cs.shape = sh
	cs.position = Vector3(0, 0.6, 0)
	area.add_child(cs)

	var spr := AnimatedSprite3D.new()
	Billboard3D.setup_sprite(spr)
	spr.modulate = Color(0.72, 0.72, 0.82)   # grisé : assoupi
	spr.name = "RecruitSprite"
	area.add_child(spr)
	area.add_child(Billboard3D.make_blob_shadow(Vector2(1.0, 0.55)))
	PMDSprites.get_walk_sprites(pick, area, func(result: Dictionary) -> void:
		if not is_instance_valid(spr) or result.is_empty():
			return
		spr.sprite_frames = result.frames
		Billboard3D.size_to_width(spr, result, Billboard3D.CHAR_WIDTH)
		spr.play("sleep" if result.frames.has_animation("sleep") else "idle")
	)

	var zzz := Label3D.new()
	zzz.text      = "💤"
	zzz.position  = Vector3(0.45, 1.7, 0)
	zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.no_depth_test = true
	zzz.pixel_size = 0.01
	area.add_child(zzz)

	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("players") and body.get("is_active") == true:
			_near_recruit = true
			_refresh_interact_prompt()
	)
	area.body_exited.connect(func(body: Node) -> void:
		if body.is_in_group("players") and body.get("is_active") == true:
			_near_recruit = false
			_refresh_interact_prompt()
	)
	add_child(area)
	_recruit_node = area
	hud.notify("😴 Un Pokémon du dresseur gît au sol — va lui parler [E]", Color(0.55, 0.80, 0.95))


## Charge à la demande l'espèce du recrut ET ses attaques (init_moves lit
## preloaded_moves) — les formes de base de champion ne sont pas toujours
## dans le cache de préchargement de la zone.
func _load_recruit(pid: int) -> void:
	if _cache.has(str(pid)):
		_load_recruit_moves(pid)
		return
	PokemonAPI.get_pokemon(pid, func(d: Dictionary) -> void:
		if not is_instance_valid(self) or d.is_empty():
			return
		_cache[str(int(d["id"]))] = PokemonData.from_api(d)
		_load_recruit_moves(pid)
	)


func _load_recruit_moves(pid: int) -> void:
	var pd: PokemonData = _cache.get(str(pid))
	if pd == null or not pd.preloaded_moves.is_empty():
		return
	var count := 0
	for lm: Dictionary in pd.level_up_moves:
		if int(lm["level"]) > PLAYER_LEVEL + 20 or count >= 10:
			continue
		count += 1
		var nm: String  = lm["name"]
		var lvl: int    = int(lm["level"])
		PokemonAPI.get_move(nm, func(md: Dictionary) -> void:
			if not is_instance_valid(self) or md.is_empty():
				return
			var pw_v: Variant = md.get("power")
			var pw: int = int(pw_v) if pw_v != null else 0
			if pw <= 0:
				return
			var move := MoveData.new()
			move.api_name      = nm
			var fr: String     = md.get("name_fr", "")
			move.display_name  = fr if fr != "" else nm.replace("-", " ").capitalize()
			move.type          = md.get("type", "normal")
			move.power         = pw
			move.damage_class  = md.get("damage_class", "physical")
			move.level_learned = lvl
			pd.preloaded_moves.append(move)
			pd.preloaded_moves.sort_custom(func(a: MoveData, b: MoveData) -> bool:
				return a.level_learned < b.level_learned)
		)


## Petit dialogue Oui/Non (UiKit) — rejoindre l'équipe ou laisser dormir.
func _open_recruit_dialog() -> void:
	if is_instance_valid(_recruit_screen):
		return
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_recruit_screen = layer

	var data: PokemonData = _cache.get(str(_recruit_pid))
	var nm: String = data.name_fr.capitalize() if data else "Ce Pokémon"

	var panel := UiKit.main_panel(Vector2(390, 210), Vector2(500, 240))
	layer.add_child(panel)
	UiKit.pop_in(panel)
	UiKit.banner(panel, "RECRUTEMENT")
	UiKit.label(panel, "%s, K.O. mais encore vaillant, veut se joindre à toi.\nIl rejoindra l'équipe avec 1 PV." % nm,
		Vector2(30, 92), 15, UiKit.CREAM, 440, HORIZONTAL_ALIGNMENT_CENTER, true)

	var yes := UiKit.button("✔  L'accueillir", Vector2(200, 52))
	yes.position = Vector2(40, 168)
	panel.add_child(yes)
	yes.pressed.connect(func() -> void:
		_close_recruit_dialog()
		_do_recruit()
	)
	var no := UiKit.button("✖  Le laisser dormir", Vector2(200, 52), false)
	no.position = Vector2(260, 168)
	panel.add_child(no)
	no.pressed.connect(_close_recruit_dialog)
	MenuNav.focus_first(panel)


func _close_recruit_dialog() -> void:
	if is_instance_valid(_recruit_screen):
		Sfx.play_file(Sfx.SE_MENU_CLOSE, -6.0)
		_recruit_screen.queue_free()
	_recruit_screen = null


## Ajoute la recrue comme compagnon IA (1 PV), la débloque durablement, et
## réveille le sprite endormi sur place.
func _do_recruit() -> void:
	var pid := _recruit_pid
	var data: PokemonData = _cache.get(str(pid))
	if data == null:
		hud.notify("Chargement du Pokémon… réessaie dans un instant", Color(0.80, 0.55, 0.30))
		return
	if _team.size() >= GameManager.get_max_team_size():
		return
	var idx := _team.size()
	var instance := PokemonInstance.new(data, PLAYER_LEVEL + RunManager.inst().rooms_cleared)
	instance.init_moves()
	instance.current_hp = 1   # rejoint à 1 PV (cf. cahier des charges)

	var spawn_ref: Vector3 = _team[_active_index].global_position if _active_index < _team.size() else Vector3.ZERO
	var member = TEAM_SCENE.instantiate()
	add_child(member)
	member.global_position = spawn_ref + SPAWN_OFFSETS[idx % SPAWN_OFFSETS.size()]
	member.setup(instance, idx, false)   # compagnon IA
	_team.append(member)
	_wire_team_member(member, idx)
	_update_leaders()

	var instances: Array = []
	for m in _team:
		instances.append(m.pokemon_instance)
	hud.setup_team(instances, _active_index)

	GameManager.unlock_pokemon(pid)
	GameManager.save_game()
	Sfx.play_file(Sfx.SE_MOVE_LEARNT)
	hud.notify("★ %s rejoint l'équipe !" % data.name_fr.capitalize(), Color(0.35, 0.80, 0.55))

	# Le sprite endormi se réveille (petit sursaut) puis disparaît — la
	# recrue « active » est le TeamMember qui vient de spawn à côté.
	if is_instance_valid(_recruit_node):
		var spr := _recruit_node.get_node_or_null("RecruitSprite")
		if spr is AnimatedSprite3D and spr.sprite_frames:
			spr.modulate = Color.WHITE
			if spr.sprite_frames.has_animation("idle"):
				spr.play("idle")
		var tw := _recruit_node.create_tween()
		tw.tween_property(_recruit_node, "position:y", _recruit_node.position.y + 1.2, 0.4).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_recruit_node, "scale", Vector3.ZERO, 0.4)
		tw.tween_callback(_recruit_node.queue_free)
	_recruit_node = null
	_near_recruit = false
	_refresh_interact_prompt()


const SPAWN_TELEGRAPH_TIME := 0.55

func _spawn_from_pool(pool: Array[int], count: int, lv: int, champion: bool = false, boss: bool = false) -> void:
	if pool.is_empty():
		return
	if _mp and not multiplayer.is_server():
		return   # seuls les ennemis de l'hôte font autorité — les clients reçoivent _net_spawn_enemy
	for i in count:
		var id: int = pool[randi() % pool.size()]
		# Espèce pas (encore) en cache — replie vers sa forme de BASE (chargée
		# en phase 1) plutôt que de sauter le spawn : une vague entièrement
		# sautée laissait la salle insoluble (_alive restait à 0, rien à tuer).
		if not _cache.has(str(id)):
			id = GameManager.base_species_of(id)
		if not _cache.has(str(id)):
			continue
		# Spawn TÉLÉPHONÉ : un anneau grandit au sol pendant ~0,5 s avant que
		# l'ennemi n'apparaisse — la vague se lit, plus de pop-in brutal.
		# _alive est réservé tout de suite : la salle ne peut pas se "nettoyer"
		# pendant que des apparitions sont en cours.
		_alive += 1
		var pos := _random_valid_spawn()
		var captured_id := id
		# Salle de dresseur : le Pokémon sort d'une POKÉBALL lancée par le
		# champion (flash, spin, burst d'ouverture — cf. PokeballFX) au lieu
		# de l'anneau de télégraphie générique.
		if _is_boss_room(RunManager.inst().rooms_cleared) and not _cave_active:
			PokeballFX.play_send(self, pos, func() -> void:
				if _game_over_triggered or _victory_triggered or not is_instance_valid(self):
					return
				_materialize_enemy(captured_id, lv, pos, champion, boss)
			)
			continue
		_spawn_telegraph_ring(pos, 1.6 if boss else (1.2 if champion else 0.9),
			SPAWN_TELEGRAPH_TIME)
		get_tree().create_timer(SPAWN_TELEGRAPH_TIME).timeout.connect(func() -> void:
			if _game_over_triggered or _victory_triggered or not is_instance_valid(self):
				return
			_materialize_enemy(captured_id, lv, pos, champion, boss)
		)


## Apparition effective d'un ennemi (après la télégraphie).
func _materialize_enemy(id: int, lv: int, pos: Vector3, champion: bool, boss: bool) -> void:
	var data: PokemonData = _cache[str(id)]
	var instance := PokemonInstance.new(data, lv)
	instance.init_moves()
	var enemy = ENEMY_SCENE.instantiate()
	if _mp:
		_net_enemy_counter += 1
		enemy.name = "E%d" % _net_enemy_counter
	add_child(enemy)
	enemy.global_position = pos
	enemy.setup(instance, champion, boss)
	enemy.died.connect(_on_enemy_died.bind(id, data.is_base_form))
	CombatVFX.spawn_death_poof(self, pos, Color(0.85, 0.88, 0.95))   # nuage d'arrivée
	if _mp:
		var ename := String(enemy.name)
		enemy.died.connect(func(xp: int, attacker_peer: int) -> void:
			_net_enemy_died.rpc(ename, xp, attacker_peer)
		)
		_net_spawn_enemy.rpc(ename, id, lv, pos, champion, boss)


## Anneau d'annonce au sol (spawn d'ennemi) — grandit puis disparaît.
func _spawn_telegraph_ring(pos: Vector3, radius: float, dur: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.1, radius - 0.14)
	torus.outer_radius = radius
	ring.mesh = torus
	ring.position = pos + Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.15, 0.05, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.35, 0.75, 0.55)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(1.0, 0.05, 1.0), dur * 0.85).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3(0.05, 0.05, 0.05), dur * 0.15).set_ease(Tween.EASE_IN)
	tw.tween_callback(ring.queue_free)


func _random_valid_spawn() -> Vector3:
	# Cherche une position libre (ni arbre, ni eau, ni bord) — taille réelle de la map
	var sz := Vector2i(MapBase.W, MapBase.H)
	if is_instance_valid(_map):
		sz = _map.get_map_cell_size()
	for _attempt in 40:
		var cell := Vector2i(
			randi_range(6, maxi(7, sz.x - 6)),
			randi_range(6, maxi(7, sz.y - 6))
		)
		if is_instance_valid(_map) and _map.is_valid_spawn_cell(cell):
			return _map.cell_to_world3(cell)
	# Fallback : centre de la map
	return Vector3(sz.x * 0.5, 0, sz.y * 0.5)


# ── Signaux ───────────────────────────────────────────────────────────

func _on_enemy_died(xp_reward: int, attacker_peer: int, pid: int, is_base_form: bool) -> void:
	_alive  -= 1
	_killed += 1
	hud.set_kills(_killed, _room_total)

	if _mp:
		# Multijoueur : l'XP ne va qu'à l'auteur RÉEL du coup fatal (cf.
		# EnemyAI.take_damage/_last_attacker_peer) — avant, CHAQUE mort
		# créditait le Pokémon actif de TOUS les pairs, peu importe qui
		# avait fait le kill (retour joueurs : l'XP était donnée à tout
		# le monde au lieu d'être répartie selon les kills de chacun).
		_net_kills.rpc(_killed, _room_total)
		if attacker_peer == Net.local_id():
			var mine = _team[_active_index] if _active_index < _team.size() else null
			if is_instance_valid(mine) and not mine.pokemon_instance.is_fainted():
				mine.gain_xp(xp_reward)
	else:
		for member in _team:
			if is_instance_valid(member) and not member.pokemon_instance.is_fainted():
				member.gain_xp(xp_reward)

	if GameManager.record_defeat(pid, is_base_form):
		var name_fr := (_cache[str(pid)] as PokemonData).name_fr if _cache.has(str(pid)) else "Pokémon"
		hud.show_unlock(name_fr)

	if _alive <= 0:
		# Vagues restantes ? La salle n'est pas finie : annonce + suite.
		if not _cave_active and not _wave_queue.is_empty():
			hud.set_wave("⚔ Vague %d/%d…" % [_wave_num + 1, _waves_total])
			await get_tree().create_timer(1.4).timeout
			if _game_over_triggered or _victory_triggered:
				return
			_spawn_next_wave()
			return
		await get_tree().create_timer(1.0).timeout
		if _cave_active:
			_on_cave_cleared()
		else:
			_on_room_cleared()


func _on_team_member_died(idx: int) -> void:
	hud.update_team_hp(idx, 0.0)
	if idx < _team.size() and is_instance_valid(_team[idx]):
		hud.notify("✖  %s est K.O. !" % _team[idx].pokemon_instance.data.name_fr.capitalize(),
			Color(0.80, 0.33, 0.25))

	# Filet de sécurité : si toute l'équipe est KO, on quitte quel que soit
	# l'index qui vient de mourir (évite un blocage si _active_index est périmé).
	if _is_team_wiped():
		_game_over()
		return

	if idx != _active_index:
		return  # un compagnon est KO, l'équipe continue

	# Multijoueur : pas de remplaçant — ton Pokémon est KO, tu spectates
	# jusqu'à la victoire de la salle ou la défaite générale (wipe ci-dessus).
	if _mp:
		hud.set_wave("☠ KO — les autres continuent le combat !")
		return

	# Le membre actif est KO → cherche un remplaçant
	var next := _find_next_alive()
	if next == -1:
		_game_over()
	else:
		_set_active(next)


func _is_team_wiped() -> bool:
	for m in _team:
		if is_instance_valid(m) and not m.pokemon_instance.is_fainted():
			return false
	return true


func _find_next_alive() -> int:
	for i in _team.size():
		var idx := (_active_index + 1 + i) % _team.size()
		if not _team[idx].pokemon_instance.is_fainted():
			return idx
	return -1


func _apply_bonus(bonus_id: String) -> void:
	for i in _team.size():
		var m = _team[i]
		if not is_instance_valid(m):
			continue
		var inst: PokemonInstance = m.pokemon_instance
		# Un membre K.O. ne profite d'AUCUN don sauf "revive" — sinon ses PV
		# remontent au-dessus de 0 sans passer par revive() (qui seul le
		# réactive vraiment : groupe "players", physics, anim), et il compte
		# comme vivant pour _is_team_wiped() alors qu'il ne l'est pas.
		if bonus_id != "revive" and inst.is_fainted():
			continue
		match bonus_id:
			"heal_full":
				inst.current_hp = inst.max_hp
				hud.update_team_hp(i, 1.0)
				if i == _active_index:
					hud.update_hp(1.0)
			"heal_half":
				var add_hp: int = inst.max_hp / 2
				inst.current_hp = mini(inst.max_hp, inst.current_hp + add_hp)
				var ratio: float = inst.hp_ratio()
				hud.update_team_hp(i, ratio)
				if i == _active_index:
					hud.update_hp(ratio)
			"boost_hp":
				inst.apply_hp_boost(1.2)
				var r: float = inst.hp_ratio()
				hud.update_team_hp(i, r)
				if i == _active_index:
					hud.update_hp(r)
			"boost_atk":
				inst.attack_mult *= 1.2
			"boost_def":
				inst.defense_mult *= 1.2
			"boost_spd":
				inst.speed_mult *= 1.2
			"dash_plus":
				m.dash_max_charges += 1
				m._dash_charges = m.dash_max_charges   # recharge immédiate à l'obtention
				if i == _active_index:
					hud.update_dash(m._dash_charges, m.dash_max_charges)
			"revive":
				m.revive(0.5)
				var rr: float = inst.hp_ratio()
				hud.update_team_hp(i, rr)
				if i == _active_index:
					hud.update_hp(rr)
			"atk_rate":
				m.cooldown_mult *= 0.85
			"xp_up":
				m.xp_mult *= 1.25


## Capacités proposées par la Boutique et les dons (pas de fetch PokeAPI au
## moment du choix : la récompense doit être instantanée).
const STRONG_MOVES: Array[Dictionary] = [
	{"api": "flamethrower", "label": "Lance-Flammes", "type": "fire",     "power": 90,  "class": "special"},
	{"api": "thunderbolt",  "label": "Tonnerre",      "type": "electric", "power": 90,  "class": "special"},
	{"api": "ice-beam",     "label": "Laser Glace",   "type": "ice",      "power": 90,  "class": "special"},
	{"api": "surf",         "label": "Surf",          "type": "water",    "power": 90,  "class": "special"},
	{"api": "earthquake",   "label": "Séisme",        "type": "ground",   "power": 100, "class": "physical"},
	{"api": "psychic",      "label": "Psyko",         "type": "psychic",  "power": 90,  "class": "special"},
	{"api": "shadow-ball",  "label": "Ball'Ombre",    "type": "ghost",    "power": 80,  "class": "special"},
	{"api": "energy-ball",  "label": "Éco-Sphère",    "type": "grass",    "power": 90,  "class": "special"},
	{"api": "brick-break",  "label": "Casse-Brique",  "type": "fighting", "power": 75,  "class": "physical"},
	{"api": "rock-slide",   "label": "Éboulement",    "type": "rock",     "power": 75,  "class": "physical"},
]


# ── Boutique : salle non-combat (vendeur Perrserker) ──────────────────
# Une salle sur ~5 (hors 1res salles et salles de boss) est une boutique :
# aucun ennemi, trois PNJ d'ambiance (Maushold endormi, Ramoloss qui
# déambule, Perrserker marchand) et un étal où dépenser ses Pokédollars ₽
# en attaques puissantes ou en Baies. On repart par un portail de sortie.

## La Boutique est désormais STRUCTURELLE : l'avant-dernière salle de chaque
## acte, juste avant le boss (respiration + préparation, façon Hades).
func _is_shop_room(room: int) -> bool:
	return RunManager.inst().is_shop_room(room)


func _enter_boutique() -> void:
	_boutique_active = true
	_clear_boutique_nodes()
	# Offres d'attaque — une par membre vivant, tirée à l'entrée puis figée.
	_boutique_live = []
	_boutique_offers = []
	for m in _team:
		if not is_instance_valid(m):
			continue
		_boutique_live.append(m)
		_boutique_offers.append(_roll_move_offers(m.pokemon_instance))
	_spawn_boutique_npcs()
	_spawn_exit_portals()   # on peut repartir librement, sans acheter
	hud.set_kills(0, 0)
	hud.set_wave("🛍 Boutique — parle au Perrserker (marchand)")


## Tire jusqu'à 3 attaques puissantes compatibles (movepool + non déjà connues)
## proposées au choix. [] si aucune. Le joueur choisira ensuite laquelle
## apprendre et quelle attaque remplacer (cf. BoutiqueScreen).
func _roll_move_offers(inst: PokemonInstance) -> Array:
	var owned: Array = []
	for md: MoveData in inst.equipped_moves:
		owned.append(md.api_name)
	var candidates: Array = STRONG_MOVES.filter(func(mv: Dictionary) -> bool:
		return not owned.has(mv["api"]) and inst.data.can_learn(mv["api"])
	)
	candidates.shuffle()
	var out: Array = []
	for pick: Dictionary in candidates:
		if out.size() >= 3:
			break
		out.append({
			"api": pick["api"], "label": pick["label"], "type": pick["type"],
			"power": pick["power"], "class": pick["class"],
			"price": BOUTIQUE_MOVE_PRICE,
		})
	return out


func _spawn_boutique_npcs() -> void:
	if not is_instance_valid(_map):
		return
	var sz := _map.get_map_cell_size()
	var cx := sz.x / 2
	var cy := sz.y / 2

	# Perrserker marchand (au centre) + étal déclencheur
	var vendor := HubNPC.new()
	add_child(vendor)
	vendor.setup("boutique_vendor", BOUTIQUE_VENDOR_PID, Color(0.85, 0.60, 0.20))
	vendor.position = _map.cell_to_world3(Vector2i(cx, cy))
	_boutique_nodes.append(vendor)
	_spawn_vendor_trigger(Vector2i(cx, cy))

	# Maushold endormi (fixe) + « Zzz »
	var sleeper := HubNPC.new()
	add_child(sleeper)
	sleeper.setup("boutique_sleeper", BOUTIQUE_SLEEPER_PID, Color(0.72, 0.72, 0.82))
	sleeper.position = _map.cell_to_world3(Vector2i(maxi(3, cx - 4), cy + 2))
	_boutique_nodes.append(sleeper)
	var zzz := Label3D.new()
	zzz.text        = "Zzz"
	zzz.position    = Vector3(0.3, 1.6, 0)
	zzz.font_size   = 40
	zzz.pixel_size  = 0.007
	zzz.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	zzz.modulate    = Color(0.75, 0.85, 1.0)
	zzz.outline_size = 8
	zzz.outline_modulate = Color(0, 0, 0, 0.7)
	zzz.no_depth_test = true
	sleeper.add_child(zzz)

	# Ramoloss qui déambule lentement
	var wanderer := HubNPC.new()
	add_child(wanderer)
	wanderer.setup("boutique_wanderer", BOUTIQUE_WANDERER_PID, Color(0.90, 0.60, 0.72))
	var wcenter := _map.cell_to_world3(Vector2i(mini(sz.x - 3, cx + 4), maxi(3, cy - 2)))
	wanderer.position = wcenter
	_boutique_nodes.append(wanderer)
	wanderer.start_wandering(wcenter, 2.4, 0.7)


func _spawn_vendor_trigger(cell: Vector2i) -> void:
	var area := Area3D.new()
	area.position        = _map.cell_to_world3(cell) + Vector3(0, 0, 1.1)
	area.collision_layer = 0
	area.collision_mask  = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size  = Vector3(1.6, 1.6, 1.4)
	cs.shape = sh
	cs.position = Vector3(0, 0.8, 0)
	area.add_child(cs)
	var lbl := Label3D.new()
	lbl.text      = "🛍 Boutique"
	lbl.position  = Vector3(0, 2.5, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size  = 44
	lbl.pixel_size = 0.009
	lbl.modulate = Color(0.95, 0.82, 0.35)
	lbl.outline_modulate = Color(0.12, 0.08, 0.02)
	lbl.outline_size = 12
	area.add_child(lbl)
	# On PARLE au marchand avec [E] (comme les coffres) — plus d'ouverture
	# automatique au contact, qui surprenait en plein déplacement.
	area.body_entered.connect(func(body: Node) -> void:
		if not (body.is_in_group("players") and body.get("is_active") == true):
			return
		_near_vendor = true
		_refresh_interact_prompt()
	)
	area.body_exited.connect(func(body: Node) -> void:
		if body.is_in_group("players") and body.get("is_active") == true:
			_near_vendor = false
			_refresh_interact_prompt()
	)
	add_child(area)
	_boutique_nodes.append(area)


func _open_boutique_shop() -> void:
	if is_instance_valid(_boutique_screen):
		return
	_boutique_screen = BoutiqueScreen.new()
	add_child(_boutique_screen)
	_boutique_screen.learn_move.connect(_learn_boutique_move)
	_boutique_screen.buy_berries.connect(_buy_boutique_berries)
	_boutique_screen.buy_potion.connect(_buy_boutique_potion)
	_boutique_screen.closed.connect(func() -> void:
		if is_instance_valid(_boutique_screen):
			_boutique_screen.queue_free()
		_boutique_screen = null
	)
	_boutique_screen.setup(_boutique_live, _boutique_offers)


## Apprend l'attaque `option_index` (parmi les 3 proposées) au membre
## `member_index`, en REMPLAÇANT son attaque `replace_index` (-1 = ajouter sur
## un emplacement libre). Débite les ₽.
func _learn_boutique_move(member_index: int, option_index: int, replace_index: int) -> void:
	if member_index < 0 or member_index >= _boutique_offers.size():
		return
	var options: Array = _boutique_offers[member_index]
	if option_index < 0 or option_index >= options.size():
		return
	var offer: Dictionary = options[option_index]
	var member = _boutique_live[member_index]
	if not is_instance_valid(member):
		return
	if not GameManager.spend_run_money(int(offer["price"])):
		return
	var inst: PokemonInstance = member.pokemon_instance

	var md := MoveData.new()
	md.api_name      = offer["api"]
	md.display_name  = offer["label"]
	md.type          = offer["type"]
	md.power         = int(offer["power"])
	md.damage_class  = offer["class"]
	md.level_learned = 0

	if replace_index >= 0 and replace_index < inst.equipped_moves.size():
		inst.equipped_moves[replace_index] = md
	elif inst.equipped_moves.size() < GameManager.move_slot_count:
		inst.equipped_moves.append(md)
	else:
		inst.equipped_moves[inst.equipped_moves.size() - 1] = md

	# HUD des capacités si c'est le membre actif
	if _active_index < _team.size() and _team[_active_index] == member:
		hud.setup_moves(inst.equipped_moves)

	# Attaque apprise → cet achat est consommé pour ce Pokémon (une fois/visite)
	_boutique_offers[member_index] = []
	Sfx.play_file(Sfx.SE_MOVE_LEARNT)
	hud.update_money(GameManager.run_money)
	if is_instance_valid(_boutique_screen):
		_boutique_screen.refresh()


func _buy_boutique_berries(price: int, amount: int) -> void:
	if not GameManager.spend_run_money(price):
		return
	GameManager.add_gold(amount)
	Sfx.play_file(Sfx.SE_BUY_ITEM)
	hud.update_money(GameManager.run_money)
	if is_instance_valid(_boutique_screen):
		_boutique_screen.refresh()


## Achat d'une Potion (soin) ou d'un Rappel (résurrection) sur le membre
## `member_index` — cf. BoutiqueScreen.HEAL_ITEMS. Un Rappel est le SEUL
## moyen de ranimer un membre K.O. (passe par TeamMember.revive() pour le
## réactiver vraiment : groupe "players", physics, anim — pas juste ses PV).
func _buy_boutique_potion(member_index: int, item_id: String) -> void:
	if member_index < 0 or member_index >= _boutique_live.size():
		return
	var item := {}
	for it: Dictionary in BoutiqueScreen.HEAL_ITEMS:
		if it["id"] == item_id:
			item = it
			break
	if item.is_empty():
		return
	var member = _boutique_live[member_index]
	if not is_instance_valid(member):
		return
	var inst: PokemonInstance = member.pokemon_instance
	var is_revive: bool = item.get("revive", false)
	if is_revive != inst.is_fainted():
		return   # Rappel seulement sur K.O. ; Potion seulement sur un membre vivant
	if not is_revive and inst.hp_ratio() >= 1.0:
		return
	if not GameManager.spend_run_money(int(item["price"])):
		return

	if is_revive:
		member.revive(float(item["heal"]))
	else:
		var heal: float = float(item["heal"])
		if heal < 0.0:
			inst.current_hp = inst.max_hp
		else:
			inst.current_hp = mini(inst.max_hp, inst.current_hp + int(heal))

	var ratio := inst.hp_ratio()
	hud.update_team_hp(member_index, ratio)
	if member_index == _active_index:
		hud.update_hp(ratio)
	Sfx.play_file(Sfx.SE_BUY_ITEM)
	hud.update_money(GameManager.run_money)
	if is_instance_valid(_boutique_screen):
		_boutique_screen.refresh()


func _clear_boutique_nodes() -> void:
	for n in _boutique_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_boutique_nodes.clear()
	_near_vendor = false
	_refresh_interact_prompt()


# ── Don de fin de zone (façon Hades) ──────────────────────────────────

var _boon_live:   Array = []
var _boon_offers: Array = []

## Fait apparaître un « don » flottant au centre de la map nettoyée. Son type
## (attaque / stats) est celui annoncé par la porte choisie pour entrer ici.
func _spawn_boon(bonus_type: int) -> void:
	_clear_boon()
	if not is_instance_valid(_map):
		return
	_boon_type = bonus_type
	var sz := _map.get_map_cell_size()
	var cell := Vector2i(sz.x / 2, sz.y / 2)

	var area := Area3D.new()
	area.position        = _map.cell_to_world3(cell) + Vector3(0, 0.9, 0)
	area.collision_layer = 0
	area.collision_mask  = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.2
	cs.shape  = sh
	area.add_child(cs)

	# Visuel : losange émissif tournant, coloré selon le type
	var col := Color(0.72, 0.55, 0.92) if bonus_type == RunManager.BONUS_SKILL else Color(0.95, 0.78, 0.28)
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 1.0, 0.7)
	mi.mesh = prism
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	mi.material_override = mat
	mi.name = "Spin"
	area.add_child(mi)

	var lbl := Label3D.new()
	lbl.text      = "★ %s ★" % RunManager.inst().bonus_type_label(bonus_type)
	lbl.position  = Vector3(0, 1.4, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size  = 44
	lbl.pixel_size = 0.009
	lbl.modulate   = col.lightened(0.3)
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0.08, 0.06, 0.04)
	area.add_child(lbl)

	# Récompense récupérée avec [E] — même langage d'interaction que les
	# coffres et le marchand.
	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("players") and body.get("is_active") == true:
			_near_boon = true
			_refresh_interact_prompt()
	)
	area.body_exited.connect(func(body: Node) -> void:
		if body.is_in_group("players") and body.get("is_active") == true:
			_near_boon = false
			_refresh_interact_prompt()
	)
	add_child(area)
	_boon_node = area


func _clear_boon() -> void:
	if is_instance_valid(_boon_node):
		_boon_node.queue_free()
	_boon_node = null
	_near_boon = false
	_refresh_interact_prompt()
	if is_instance_valid(_boon_screen):
		_boon_screen.queue_free()
	_boon_screen = null
	_boon_type = -1


func _open_boon() -> void:
	if is_instance_valid(_boon_screen):
		return
	_boon_screen = BoutiqueScreen.new()
	add_child(_boon_screen)
	if _boon_type == RunManager.BONUS_SKILL:
		_boon_live = []
		_boon_offers = []
		for m in _team:
			if not is_instance_valid(m):
				continue
			_boon_live.append(m)
			var offs := _roll_move_offers(m.pokemon_instance)
			for o: Dictionary in offs:
				o["price"] = 0   # don gratuit
			_boon_offers.append(offs)
		_boon_screen.learn_move.connect(_claim_boon_skill)
		_boon_screen.setup(_boon_live, _boon_offers, "skill")
	else:
		_boon_screen.boon_stat.connect(_claim_boon_stat)
		_boon_screen.setup(_team, [], "stat")
	# « Continuer » ferme sans réclamer — le don reste dispo (on peut y revenir).
	_boon_screen.closed.connect(func() -> void:
		if is_instance_valid(_boon_screen):
			_boon_screen.queue_free()
		_boon_screen = null
	)


func _claim_boon_skill(member_index: int, option_index: int, replace_index: int) -> void:
	if member_index < 0 or member_index >= _boon_offers.size():
		return
	var options: Array = _boon_offers[member_index]
	if option_index < 0 or option_index >= options.size():
		return
	var member = _boon_live[member_index]
	if not is_instance_valid(member):
		return
	var offer: Dictionary = options[option_index]
	var inst: PokemonInstance = member.pokemon_instance

	var md := MoveData.new()
	md.api_name      = offer["api"]
	md.display_name  = offer["label"]
	md.type          = offer["type"]
	md.power         = int(offer["power"])
	md.damage_class  = offer["class"]
	md.level_learned = 0

	if replace_index >= 0 and replace_index < inst.equipped_moves.size():
		inst.equipped_moves[replace_index] = md
	elif inst.equipped_moves.size() < GameManager.move_slot_count:
		inst.equipped_moves.append(md)
	else:
		inst.equipped_moves[inst.equipped_moves.size() - 1] = md

	if _active_index < _team.size() and _team[_active_index] == member:
		hud.setup_moves(inst.equipped_moves)
	Sfx.play("victory", -6.0)
	_consume_boon()


func _claim_boon_stat(stat_id: String) -> void:
	_apply_bonus(stat_id)   # applique le boost à TOUTE l'équipe
	Sfx.play("victory", -6.0)
	_consume_boon()


## Don réclamé : on ferme l'écran et on retire l'item du centre.
func _consume_boon() -> void:
	if is_instance_valid(_boon_screen):
		_boon_screen.queue_free()
	_boon_screen = null
	if is_instance_valid(_boon_node):
		_boon_node.queue_free()
	_boon_node = null
	_boon_type = -1
	hud.set_wave("★ Don récupéré !")


var _chests: Array = []   # coffres de la zone courante (purgés à chaque zone)

func _spawn_chests() -> void:
	# Purge des coffres de la zone précédente — ils sont enfants de l'arène
	# (pas de la map) et s'accumulaient de zone en zone (fuite → lag croissant).
	for c in _chests:
		if is_instance_valid(c):
			c.queue_free()
	_chests.clear()
	if not is_instance_valid(_map):
		return
	for cell: Vector2i in _map.get_chest_cells():
		var chest := Chest.new()
		chest.position = _map.cell_to_world3(cell)
		chest.setup(_map.get_objects_layer(), cell, _map.source_id)
		chest.opened.connect(_on_chest_opened)
		_wire_chest_prompt(chest)
		add_child(chest)
		_chests.append(chest)


## Affiche/masque le prompt "[E] Ouvrir" au HUD quand le joueur entre/sort
## de la portée d'interaction d'un coffre. Le prompt HUD est partagé avec
## les obstacles CS — cf. _refresh_interact_prompt() pour l'arbitrage.
func _wire_chest_prompt(chest: Chest) -> void:
	chest.player_in_range.connect(func(in_range: bool) -> void:
		_near_chest_prompt = "Appuyer sur [E] pour ouvrir le coffre" if in_range else ""
		_refresh_interact_prompt()
	)


## Un seul prompt HUD à la fois : priorité au coffre s'il y a superposition
## (cas rare), sinon l'obstacle CS actuellement éligible, sinon rien.
func _refresh_interact_prompt() -> void:
	if not _near_chest_prompt.is_empty():
		hud.set_interact_prompt(true, _near_chest_prompt)
	elif _near_vendor:
		hud.set_interact_prompt(true, "Appuyer sur [E] pour parler au marchand")
	elif _near_boon:
		hud.set_interact_prompt(true, "Appuyer sur [E] pour récupérer la récompense")
	elif _near_recruit:
		hud.set_interact_prompt(true, "Appuyer sur [E] pour parler au Pokémon endormi")
	elif not _near_obstacle.is_empty():
		hud.set_interact_prompt(true, _near_obstacle["prompt"])
	else:
		hud.set_interact_prompt(false)


## Déclencheurs d'interaction CS (arbre à couper / rocher à casser) —
## toujours présents sur la carte ; l'éligibilité (bon Pokémon contrôlé)
## est réévaluée chaque frame par _refresh_cs_prompt().
func _spawn_cs_triggers() -> void:
	for entry: Dictionary in _cs_triggers:
		if is_instance_valid(entry.get("area")): entry["area"].queue_free()
	_cs_triggers.clear()
	_near_obstacle = {}
	_refresh_interact_prompt()
	if not is_instance_valid(_map):
		return

	for entry: Dictionary in _map.get_coupe_tree_approaches():
		var cells: Array = entry["cells"]
		var approach: Vector2i = entry["approach"]
		# Position de l'obstacle (1re case du groupe d'arbre) pour l'effet visuel
		var at_cell: Vector2i = cells[0] if not cells.is_empty() else approach
		_register_cs_trigger(approach, "cs_coupe", "[A]  Couper l'arbre (CS Coupe)", at_cell,
			func() -> void: _map.cut_tree_group(cells)
		)

	var boulders: Dictionary = _map.get_force_boulder_approaches()
	for bcell: Vector2i in boulders:
		var approach: Vector2i = boulders[bcell]
		var captured_bcell: Vector2i = bcell
		_register_cs_trigger(approach, "cs_force", "[A]  Casser le rocher (CS Force)", bcell,
			func() -> void: _map.break_rock_at(captured_bcell)
		)


# ── Effets visuels des CS (sprites Pokémon Essentials) ──────────────────
# Charsets RPG Maker XP standard : base_surf (4 col walk × 4 lignes direction,
# frames 64px) ; Object tree/rock (4×4, chaque ligne = une frame d'animation
# répétée sur les 4 colonnes — on ne lit qu'une colonne, de haut en bas).
const _CS_SURF := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/base_surf.png"
const _CS_ROCK := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/Object rock.png"
const _CS_TREE := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/Object tree 1.png"

## Crope une frame (col,row) d'une planche de personnage → Sprite3D billboard.
func _cs_frame_sprite(path: String, frame_px: int, col: int, row: int, world_h: float) -> Sprite3D:
	var spr := Sprite3D.new()
	var img := _cs_frame_image(path, frame_px, col, row)
	if img == null:
		return spr
	spr.texture        = ImageTexture.create_from_image(img)
	spr.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded         = false
	spr.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size     = world_h / float(frame_px)
	return spr


## Cache des planches CS décompressées — _update_surf_mount change de frame
## plusieurs fois par seconde en nage : sans cache, chaque frame rechargeait
## et décompressait TOUTE la planche (coût par frame inutile).
var _cs_sheet_cache: Dictionary = {}   # path -> Image décompressée

func _cs_sheet_image(path: String) -> Image:
	if _cs_sheet_cache.has(path):
		return _cs_sheet_cache[path]
	var tex: Texture2D = load(path)
	var img: Image = null
	if tex != null:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
	_cs_sheet_cache[path] = img
	return img


func _cs_frame_image(path: String, frame_px: int, col: int, row: int) -> Image:
	var img := _cs_sheet_image(path)
	if img == null:
		return null
	return img.get_region(Rect2i(col * frame_px, row * frame_px, frame_px, frame_px))


## Effet à l'usage d'une CS Coupe/Force : anime les 4 frames verticales
## (intact → secoué → en train de céder → débris) de la planche Essentials,
## puis fait apparaître le nuage de débris et sursauter/s'effacer le sprite.
func _play_cs_effect(cs_id: String, at: Vector3) -> void:
	if cs_id == "cs_coupe":
		await _play_cs_break_anim(_CS_TREE, at + Vector3(0, 0.9, 0), 1.8, Color(0.35, 0.65, 0.30), "hit", -2.0)
	elif cs_id == "cs_force":
		await _play_cs_break_anim(_CS_ROCK, at + Vector3(0, 0.7, 0), 1.4, Color(0.55, 0.50, 0.44), "death", -3.0)


const _CS_BREAK_FRAME_TIME := 0.12

func _play_cs_break_anim(path: String, pos: Vector3, world_h: float, poof_color: Color, sfx: String, sfx_db: float) -> void:
	var spr := _cs_frame_sprite(path, 32, 0, 0, world_h)
	spr.position = pos
	add_child(spr)

	for row in [1, 2, 3]:
		await get_tree().create_timer(_CS_BREAK_FRAME_TIME).timeout
		if not is_instance_valid(spr):
			return
		var img := _cs_frame_image(path, 32, 0, row)
		if img != null:
			spr.texture = ImageTexture.create_from_image(img)

	CombatVFX.spawn_death_poof(self, pos, poof_color)
	Sfx.play(sfx, sfx_db)
	_cs_pop_and_fade(spr)


func _cs_pop_and_fade(spr: Sprite3D) -> void:
	spr.scale = Vector3.ONE * 0.5
	var tw := spr.create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector3.ONE * 1.2, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position:y", spr.position.y + 0.6, 0.5)
	tw.tween_property(spr, "modulate:a", 0.0, 0.5).set_delay(0.15)
	tw.chain().tween_callback(spr.queue_free)


## Monture de surf sous le Pokémon contrôlé quand il est au-dessus de l'eau
## (CS Surf possédée). Appelée chaque frame par _process — suit la direction
## de déplacement (ligne du charset) et anime le cycle de nage (colonnes).
var _surf_mount: Sprite3D = null
var _surf_row:   int      = 0     # 0=bas 1=gauche 2=droite 3=haut (charset RPG Maker)
var _surf_anim_t: float   = 0.0
const _SURF_FPS := 6.0

func _update_surf_mount() -> void:
	var show := false
	var pos := Vector3.ZERO
	var body: CharacterBody3D = null
	if _surf_active and _active_index < _team.size() and is_instance_valid(_team[_active_index]) \
			and is_instance_valid(_map) and _map.has_method("world3_to_cell"):
		body = _team[_active_index]
		var cell: Vector2i = _map.world3_to_cell(body.global_position)
		if _map.get("_water") != null and _map._water.get_cell_source_id(cell) != -1:
			show = true
			pos = body.global_position

	if not show:
		if is_instance_valid(_surf_mount):
			_surf_mount.queue_free()
			_surf_mount = null
		return

	var moving := Vector2(body.velocity.x, body.velocity.z).length() > 0.1
	if moving:
		var dir := Vector2(body.velocity.x, body.velocity.z)
		if absf(dir.x) > absf(dir.y):
			_surf_row = 2 if dir.x > 0 else 1
		else:
			_surf_row = 3 if dir.y < 0 else 0
		_surf_anim_t += get_process_delta_time()
	var col := int(_surf_anim_t * _SURF_FPS) % 4 if moving else 0

	if not is_instance_valid(_surf_mount):
		_surf_mount = _cs_frame_sprite(_CS_SURF, 64, col, _surf_row, 2.0)
		add_child(_surf_mount)
		_surf_mount.set_meta("frame", Vector2i(col, _surf_row))
	elif _surf_mount.get_meta("frame", Vector2i(-1, -1)) != Vector2i(col, _surf_row):
		var img := _cs_frame_image(_CS_SURF, 64, col, _surf_row)
		if img != null:
			_surf_mount.texture = ImageTexture.create_from_image(img)
		_surf_mount.set_meta("frame", Vector2i(col, _surf_row))
	_surf_mount.global_position = pos + Vector3(0, 0.15, 0)


func _register_cs_trigger(approach: Vector2i, cs_id: String, prompt: String, at_cell: Vector2i, on_use: Callable) -> void:
	var area := Area3D.new()
	area.position         = _map.cell_to_world3(approach)
	area.collision_layer  = 0
	area.collision_mask   = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size  = Vector3(1.0, 1.5, 1.0)
	cs.shape = sh
	cs.position = Vector3(0, 0.75, 0)
	area.add_child(cs)
	add_child(area)
	_cs_triggers.append({
		"area": area, "cs_id": cs_id, "prompt": prompt, "on_use": on_use,
		"at": _map.cell_to_world3(at_cell),
	})


## Recalculé chaque frame : le joueur doit à la fois se tenir dans la zone
## ET contrôler (Pokémon actif) le porteur de la bonne CS. Réagit donc
## immédiatement à un changement de Pokémon actif [TAB], même sans bouger.
func _refresh_cs_prompt() -> void:
	if _active_index >= _team.size() or not is_instance_valid(_team[_active_index]):
		_clear_cs_prompt()
		return
	var active_body: Node = _team[_active_index]
	for entry: Dictionary in _cs_triggers:
		var area: Area3D = entry["area"]
		if not is_instance_valid(area): continue
		if active_body in area.get_overlapping_bodies() and GameManager.owns_cs(entry["cs_id"]):
			if _near_obstacle.get("prompt", "") != entry["prompt"]:
				_near_obstacle = entry
				_refresh_interact_prompt()
			return
	# Surf : au bord de l'eau avec la CS mais pas encore monté → [A] pour surfer
	if _cs_surf_unlocked and not _surf_active and _active_near_water():
		var prompt := "[A]  Surfer (CS Surf)"
		if _near_obstacle.get("prompt", "") != prompt:
			_near_obstacle = {
				"prompt": prompt, "cs_id": "cs_surf",
				"on_use": _mount_surf,
				"at": (active_body as Node3D).global_position,
			}
			_refresh_interact_prompt()
		return
	_clear_cs_prompt()


func _clear_cs_prompt() -> void:
	if not _near_obstacle.is_empty():
		_near_obstacle = {}
		_refresh_interact_prompt()


func _on_chest_opened(item: Dictionary) -> void:
	_show_item_reward(item)


## Affiche l'écran de choix : le joueur décide quel membre reçoit l'objet
## (description + effet visibles), avant que l'effet ne soit appliqué.
func _show_item_reward(item: Dictionary, on_done: Callable = Callable()) -> void:
	var screen := ItemRewardScreen.new()
	add_child(screen)
	screen.setup(item, _team)
	screen.member_chosen.connect(func(idx: int) -> void:
		_apply_item_to_member(item, idx)
		screen.queue_free()
		if on_done.is_valid():
			on_done.call()
	, CONNECT_ONE_SHOT)


func _apply_item_to_member(item: Dictionary, idx: int) -> void:
	if idx < 0 or idx >= _team.size():
		return
	var m = _team[idx]
	if not is_instance_valid(m):
		return
	var inst: PokemonInstance = m.pokemon_instance
	if inst.is_fainted():
		return
	inst.equip_item(item)
	var r := inst.hp_ratio()
	hud.update_team_hp(idx, r)
	if idx == _active_index:
		hud.update_hp(r)
	var label: String = item.get("name_fr", item.get("api_name", "Objet"))
	hud.set_wave("✦ %s → %s !" % [label, inst.data.name_fr.capitalize()])


var _game_over_triggered: bool = false

func _game_over() -> void:
	if _game_over_triggered:
		return
	_game_over_triggered = true
	Sfx.play("defeat")
	hud.set_wave("DÉFAITE...")
	var consolation_gold := RunManager.inst().rooms_cleared * 15
	if consolation_gold > 0:
		GameManager.add_gold(consolation_gold)
		hud.set_wave("DÉFAITE...  +%d Baies de consolation" % consolation_gold)
	await get_tree().create_timer(2.5).timeout

	if _mp:
		# En multi, l'HÔTE choisit la suite (réessayer / retour au hub) pour
		# tout le groupe — cf. Net.request_retry / request_return_hub.
		var screen := MpDefeatScreen.new()
		add_child(screen)
		return

	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


# ── Système de portes ─────────────────────────────────────────────────

func _spawn_entry_barrier() -> void:
	if is_instance_valid(_entry_barrier):
		_entry_barrier.queue_free()
	if not is_instance_valid(_map):
		return

	var barrier := StaticBody3D.new()
	barrier.name            = "EntryBarrier"
	barrier.collision_layer = 1
	barrier.collision_mask  = 0
	barrier.position        = _map.cell_to_world3(_map.entry_tile)

	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size  = Vector3(5.0, 1.4, 1.0)
	cs.shape = sh
	cs.position = Vector3(0, 0.7, 0)
	barrier.add_child(cs)

	# Visuel — poutre de bois sombre en travers de l'entrée
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 0.7, 0.55)
	mi.mesh = box
	mi.position = Vector3(0, 0.45, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.18, 0.08)
	mat.roughness    = 0.9
	mi.material_override = mat
	barrier.add_child(mi)

	add_child(barrier)
	_entry_barrier = barrier


func _spawn_exit_portals() -> void:
	# get_exits() tire au hasard (biomes/dons) : en multijoueur, seule la
	# version de l'HÔTE fait foi — elle est diffusée à tous les clients.
	# Portes ACTIVES d'emblée (boutique, ou filet de sécurité) — cf.
	# _spawn_exit_doors_closed pour les salles de combat (fermées au départ).
	var exits_data := RunManager.inst().get_exits(2)
	if _mp and multiplayer.is_server():
		_net_exits.rpc(exits_data)
	_spawn_exit_portals_from(exits_data)
	hud.set_wave("Choisissez une sortie ↑")


## Portes visibles DÈS L'ENTRÉE dans la salle mais INERTES (pas de halo, pas
## de trigger) — cf. _open_exit_doors, appelé une fois la salle nettoyée.
## Une seule porte si la salle suivante est la boutique (même destination,
## pas besoin de la dupliquer) ; style "tunnel" en biome Montagne.
func _spawn_exit_doors_closed() -> void:
	var room  := RunManager.inst().rooms_cleared
	var count := 1 if RunManager.inst().is_shop_room(room + 1) else 2
	var style := "tunnel" if RunManager.inst().current_biome() == MapGenerator.MapTheme.ROCKY else "house"
	var exits_data := RunManager.inst().get_exits(count)
	for e: Dictionary in exits_data:
		e["active"] = false
		e["style"]  = style
	if _mp and multiplayer.is_server():
		_net_exits.rpc(exits_data)
	_spawn_exit_portals_from(exits_data)


## Ouvre les portes déjà posées (fin de salle) — pas de respawn, juste
## réveil visuel + activation du trigger sur chaque ExitPortal existant.
func _open_exit_doors() -> void:
	_advancing = false   # nouveau choix possible
	for p in _exit_portals:
		if is_instance_valid(p):
			p.open()
	hud.set_wave("Choisissez une sortie ↑")
	if _mp and multiplayer.is_server():
		_net_open_exits.rpc()


@rpc("authority", "call_remote", "reliable")
func _net_open_exits() -> void:
	for p in _exit_portals:
		if is_instance_valid(p):
			p.open()


func _spawn_exit_portals_from(exits_data: Array) -> void:
	_advancing = false   # nouvelles portes → nouveau choix possible
	for p in _exit_portals:
		if is_instance_valid(p): p.queue_free()
	_exit_portals.clear()

	if not is_instance_valid(_map):
		get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
		return

	var exit_tiles := [_map.exit_A, _map.exit_B, _map.exit_C]

	for i in exits_data.size():
		var data: Dictionary = exits_data[i]
		var tile: Vector2i   = exit_tiles[i]
		var portal           := ExitPortal.new()
		portal.position      = _map.cell_to_world3(tile)
		portal.setup(data)
		portal.chosen.connect(_on_exit_chosen)
		add_child(portal)
		_exit_portals.append(portal)


func _on_exit_chosen(data: Dictionary) -> void:
	# Multijoueur : le premier joueur qui touche une porte décide pour tout
	# le monde — la décision transite par l'hôte (anti-course), qui diffuse.
	if _mp:
		if multiplayer.is_server():
			_host_advance(data)
		else:
			_net_request_advance.rpc_id(1, data)
		return
	_do_advance(data)


var _advancing: bool = false

func _host_advance(data: Dictionary) -> void:
	if _advancing:
		return
	_advancing = true
	_net_advance.rpc(data)
	_do_advance(data)


func _do_advance(data: Dictionary) -> void:
	Sfx.stop_music()   # la musique de victoire s'arrête au changement de zone
	for p in _exit_portals:
		if is_instance_valid(p): p.queue_free()
	_exit_portals.clear()

	# Boutique quittée : referme l'écran et retire les PNJ (enfants de l'arène,
	# ils survivraient sinon au changement de map).
	if _boutique_active:
		_boutique_active = false
		_clear_boutique_nodes()
		if is_instance_valid(_boutique_screen):
			_boutique_screen.queue_free()
			_boutique_screen = null

	# Recrue de boss non-prise : elle ne suit pas dans la zone suivante.
	if is_instance_valid(_recruit_node):
		_recruit_node.queue_free()
	_recruit_node = null
	_recruit_pid  = 0
	_near_recruit = false
	if is_instance_valid(_recruit_screen):
		_recruit_screen.queue_free()
		_recruit_screen = null

	# La porte choisie fixe le biome ET le type de don de la zone suivante.
	# (Plus de bonus appliqué à la porte : le don s'obtient au centre de la
	# zone une fois nettoyée — cf. _spawn_boon.)
	_clear_boon()
	RunManager.inst().advance(data.get("biome", -1), data.get("bonus_type", -1))
	_transition_to_next_zone()


func _transition_to_next_zone() -> void:
	# Fondu au noir
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 99
	var fade_rect := ColorRect.new()
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)

	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		# Charger la nouvelle zone
		if is_instance_valid(_map):
			_map.queue_free()
		var zone_path  := RunManager.inst().current_zone_path()
		var new_scene  := load(zone_path) as PackedScene
		_map            = new_scene.instantiate() as MapBase
		_map.name       = "Map"
		add_child(_map)
		move_child(_map, 0)
		_refresh_map_bounds()
		_apply_ambiance()

		# Réinitialiser le combat
		if is_instance_valid(_entry_barrier):
			_entry_barrier.queue_free()
		_entry_barrier = null
		_alive      = 0
		_killed     = 0
		_room_total = 0

		# Repositionner l'équipe à l'entrée (PAS de soin : les PV se conservent
		# d'une zone à l'autre — la gestion des PV fait partie du risque de run).
		var spawn_center := _map.cell_to_world3(_map.entry_tile + Vector2i(0, -4))
		for i in _team.size():
			if is_instance_valid(_team[i]):
				_team[i].global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]

		hud.set_wave(_zone_label())
		hud.set_kills(0, 0)
		hud.announce_zone(_zone_label())   # le nom de la zone en grand, fondu + glow

		# Fondu depuis le noir
		var tw2 := create_tween()
		tw2.tween_property(fade_rect, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
		tw2.tween_callback(func() -> void: fade_layer.queue_free())

		await get_tree().process_frame
		# Salle-boutique : détour non-combat (vendeur Perrserker)
		if _is_shop_room(RunManager.inst().rooms_cleared):
			_enter_boutique()
			return
		_spawn_entry_barrier()
		_spawn_chests()
		# Grotte : ouverte seulement après nettoyage (cf. _show_run_status)
		_spawn_cs_triggers()
		await get_tree().create_timer(0.8).timeout
		await _net_zone_barrier()
		_spawn_room_enemies()
	)


# ── Grotte : arène de demi-boss (détour bonus) ────────────────────────

func _spawn_cave_portals() -> void:
	for p in _cave_portals:
		if is_instance_valid(p): p.queue_free()
	_cave_portals.clear()
	if _cave_active or not is_instance_valid(_map):
		return
	for cell: Vector2i in _map.get_cave_cells():
		var area := Area3D.new()
		# L'entrée est dessinée sur la face sud du volume de falaise (plein) :
		# le déclencheur est décalé devant la paroi, là où le joueur peut se tenir.
		area.position        = _map.cell_to_world3(cell) + Vector3(0, 0, 0.85)
		area.collision_layer = 0
		area.collision_mask  = 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size  = Vector3(1.1, 1.6, 0.9)
		cs.shape = sh
		cs.position = Vector3(0, 0.8, 0)
		area.add_child(cs)
		var lbl := Label3D.new()
		lbl.text      = "⛰ Grotte"
		lbl.position  = Vector3(0, 2.4, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size  = 44
		lbl.pixel_size = 0.009
		lbl.modulate = Color(0.95, 0.85, 0.5)
		lbl.outline_modulate = Color(0.12, 0.08, 0.02)
		lbl.outline_size = 12
		area.add_child(lbl)
		var entrance := cell
		area.body_entered.connect(func(body: Node) -> void:
			if _cave_active: return
			if not (body.is_in_group("players") and body.get("is_active") == true): return
			# Multijoueur : TOUT LE GROUPE entre ensemble (les maps/états
			# doivent rester en lockstep) — le premier joueur au seuil
			# demande à l'hôte, qui diffuse l'entrée à tous.
			if _mp and not multiplayer.is_server():
				_request_enter_cave.rpc_id(1, entrance)
			else:
				_host_enter_cave(entrance)
		)
		add_child(area)
		_cave_portals.append(area)


@rpc("any_peer", "call_remote", "reliable")
func _request_enter_cave(entrance: Vector2i) -> void:
	if multiplayer.is_server():
		_host_enter_cave(entrance)


func _host_enter_cave(entrance: Vector2i) -> void:
	if _cave_active:
		return
	if _mp:
		_net_enter_cave.rpc(entrance)
	_enter_cave(entrance)


@rpc("authority", "call_remote", "reliable")
func _net_enter_cave(entrance: Vector2i) -> void:
	_enter_cave(entrance)


func _enter_cave(_entrance: Vector2i) -> void:
	if _cave_active:
		return
	_cave_active = true
	_clear_boon()   # le don de zone ne suit pas dans la grotte
	_fade_transition(func() -> void:
		_save_overworld()
		_load_cave()
		_spawn_cave_bosses()
	)


var _saved_wave_queue: Array = []
var _saved_wave_num:   int   = 0
var _saved_waves_total: int  = 0

func _save_overworld() -> void:
	_saved_alive      = _alive
	_saved_killed     = _killed
	_saved_room_total = _room_total
	_saved_wave_queue  = _wave_queue.duplicate(true)
	_saved_wave_num    = _wave_num
	_saved_waves_total = _waves_total
	_wave_queue.clear()
	_saved_team_pos.clear()
	for m in _team:
		_saved_team_pos.append(m.global_position if is_instance_valid(m) else Vector3.ZERO)

	# Détache (gèle) tout l'overworld : ennemis, coffres, barrière, map.
	# Les COQUILLES réseau sont exclues : sur un client lent, les premiers
	# ennemis de grotte (envoyés par l'hôte) peuvent arriver AVANT ce gel —
	# les stocker les ferait disparaître de la grotte et réapparaître en
	# fantômes au retour dans l'overworld.
	_saved_nodes.clear()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get_parent() == self and not ("net_shell" in e and e.net_shell):
			remove_child(e)
			_saved_nodes.append(e)
	var chests: Array = []
	for child in get_children():
		if child is Chest:
			chests.append(child)
	for c in chests:
		remove_child(c)
		_saved_nodes.append(c)
	if is_instance_valid(_entry_barrier):
		remove_child(_entry_barrier)
		_saved_nodes.append(_entry_barrier)
	# Les PORTES DE SORTIE de l'overworld aussi : la grotte ne s'ouvre
	# qu'une fois la salle nettoyée, donc elles existent toujours à ce
	# moment-là — sans ça elles restaient plantées DANS la grotte (bug
	# "plusieurs zones de sortie après la cave" + risque de changer de
	# zone depuis l'intérieur). Restaurées avec le reste au retour.
	for p in _exit_portals:
		if is_instance_valid(p) and p.get_parent() == self:
			remove_child(p)
			_saved_nodes.append(p)

	# Déclencheurs de grotte consommés
	for p in _cave_portals:
		if is_instance_valid(p): p.queue_free()
	_cave_portals.clear()

	_saved_map = _map
	remove_child(_saved_map)


func _load_cave() -> void:
	var scene := load(CAVE_PATH) as PackedScene
	_map      = scene.instantiate() as MapBase
	_map.name = "CaveMap"
	add_child(_map)
	move_child(_map, 0)
	_refresh_map_bounds()
	_apply_ambiance()   # variante grotte : sombre, brumeuse, sans horizon
	_alive = 0
	_killed = 0
	_room_total = 0

	var spawn_center := _map.cell_to_world3(_map.entry_tile + Vector2i(0, -2))
	for i in _team.size():
		if is_instance_valid(_team[i]):
			_team[i].global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]
	_cam_pos = spawn_center


var _cave_demiboss_pid: int = 0   # espèce du demi-boss (débloquée à sa défaite)

func _spawn_cave_bosses() -> void:
	# Multijoueur : seuls les ennemis de l'HÔTE font autorité — les clients
	# reçoivent leurs coquilles via _net_spawn_enemy comme pour toute salle.
	if _mp and not multiplayer.is_server():
		hud.set_wave("☠ Demi-boss — bats-le pour le recruter !")
		return
	var rooms := RunManager.inst().rooms_cleared
	var lv := SEMI_BOSS_LEVEL + rooms * 3
	# 1 demi-boss à aura rouge (espèce non évoluée à débloquer) + 3 sbires
	# nettement plus faibles.
	_cave_demiboss_pid = _spawn_cave_demiboss(lv + 4)
	_spawn_from_pool(POOL_CAVE_ELITE, 3, maxi(PLAYER_LEVEL, lv - 5))
	_room_total = _alive
	hud.set_kills(0, _room_total)
	if _mp:
		_net_kills.rpc(0, _room_total)
	if _alive > 0:
		var boss_name := "le demi-boss"
		if _cave_demiboss_pid > 0 and _cache.has(str(_cave_demiboss_pid)):
			boss_name = (_cache[str(_cave_demiboss_pid)] as PokemonData).name_fr.capitalize()
		hud.set_wave("☠ Demi-boss : %s  —  bats-le pour le recruter !" % boss_name)
	else:
		_on_cave_cleared()   # sécurité : pool non chargé → récompense directe


## Spawne le demi-boss : espèce non évoluée du pool, stats renforcées (mur à
## aura rouge), au centre de l'arène. Retourne son pid (0 si échec).
func _spawn_cave_demiboss(lv: int) -> int:
	var pool: Array[int] = []
	for pid: int in POOL_CAVE_DEMIBOSS:
		if _cache.has(str(pid)):
			pool.append(pid)
	if pool.is_empty():
		return 0
	var id: int = pool[randi() % pool.size()]
	var data: PokemonData = _cache[str(id)]
	var instance := PokemonInstance.new(data, lv)
	instance.init_moves()
	# Renforts de demi-boss : gros sac de PV + frappe plus fort
	instance.apply_hp_boost(2.4)
	instance.attack_mult *= 1.4

	var enemy = ENEMY_SCENE.instantiate()
	if _mp:
		_net_enemy_counter += 1
		enemy.name = "E%d" % _net_enemy_counter
	add_child(enemy)
	var sz := _map.get_map_cell_size()
	enemy.global_position = _map.cell_to_world3(Vector2i(sz.x / 2, sz.y / 2))
	enemy.setup(instance, false, false, true)   # demi_boss = true
	enemy.died.connect(_on_enemy_died.bind(id, data.is_base_form))
	_alive += 1
	if _mp:
		var ename := String(enemy.name)
		enemy.died.connect(func(xp: int, attacker_peer: int) -> void:
			_net_enemy_died.rpc(ename, xp, attacker_peer)
		)
		_net_spawn_enemy.rpc(ename, id, lv, enemy.global_position, false, false, true)
	return id


func _on_cave_cleared() -> void:
	# Multijoueur : seul l'hôte détecte le nettoyage (_alive ne vit que chez
	# lui) — il informe les clients, qui déroulent la même récompense
	# localement (or/soins chacun chez soi, même coffre, même sortie).
	if _mp and multiplayer.is_server():
		_net_cave_cleared.rpc(_cave_demiboss_pid)
	var gold := 100 + RunManager.inst().rooms_cleared * 12
	GameManager.add_gold(gold)
	for i in _team.size():
		var m = _team[i]
		if is_instance_valid(m) and not m.pokemon_instance.is_fainted():
			m.pokemon_instance.current_hp = m.pokemon_instance.max_hp
			hud.update_team_hp(i, 1.0)
	if _active_index < _team.size():
		hud.update_hp(1.0)

	# Déblocage direct de l'espèce du demi-boss (pas de seuil de victoires) —
	# la récompense clé de l'arène : recruter un Pokémon rare non évolué.
	if _cave_demiboss_pid > 0 and _cave_demiboss_pid not in GameManager.unlocked_pokemon:
		GameManager.unlock_pokemon(_cave_demiboss_pid)
		var nm := (_cache[str(_cave_demiboss_pid)] as PokemonData).name_fr.capitalize() \
			if _cache.has(str(_cave_demiboss_pid)) else "Pokémon"
		hud.show_unlock(nm)
		hud.set_wave("★ %s rejoint ton Pokédex !  +%d ₽" % [nm, gold])
	else:
		hud.set_wave("⛰ Arène vaincue !  +%d ₽" % gold)
	Sfx.play("victory")
	await get_tree().create_timer(1.4).timeout
	_spawn_cave_reward()


func _spawn_cave_reward() -> void:
	if not is_instance_valid(_map):
		_exit_cave()
		return
	var sz   := _map.get_map_cell_size()
	var cell := Vector2i(sz.x / 2, sz.y / 2)
	var chest := Chest.new()
	chest.position = _map.cell_to_world3(cell)
	# Objet garanti puissant (meilleur du pool)
	chest.setup(_map.get_objects_layer(), cell, _map.source_id,
		{"api_name": "choice-band", "effect": "atk", "mult": 1.5})
	chest.opened.connect(func(item: Dictionary) -> void:
		_show_item_reward(item, _spawn_cave_return_portal)
	, CONNECT_ONE_SHOT)
	_wire_chest_prompt(chest)
	add_child(chest)
	hud.set_wave("✦ Coffre doré — approche-toi !")


## Nettoyage de cave reçu de l'hôte (clients) — même récompense localement.
@rpc("authority", "call_remote", "reliable")
func _net_cave_cleared(demiboss_pid: int) -> void:
	if not _cave_active:
		return
	_cave_demiboss_pid = demiboss_pid
	_on_cave_cleared()


func _spawn_cave_return_portal() -> void:
	if not is_instance_valid(_map):
		_request_exit_cave()
		return
	var sz   := _map.get_map_cell_size()
	var tile := Vector2i(sz.x / 2, 3)
	var portal := ExitPortal.new()
	portal.position = _map.cell_to_world3(tile)
	portal.setup({"zone_name": "Retour", "bonus_label": ""})
	portal.chosen.connect(func(_d: Dictionary) -> void: _request_exit_cave(), CONNECT_ONE_SHOT)
	add_child(portal)
	_cave_portals.append(portal)
	hud.set_wave("↑ Sortie de la grotte")


## Multijoueur : la sortie de grotte est GROUPÉE (comme l'entrée) — le
## premier joueur sur le portail fait sortir tout le monde, via l'hôte.
func _request_exit_cave() -> void:
	if _mp and not multiplayer.is_server():
		_rpc_request_exit_cave.rpc_id(1)
	elif _mp:
		_net_exit_cave.rpc()
		_exit_cave()
	else:
		_exit_cave()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_exit_cave() -> void:
	if multiplayer.is_server() and _cave_active and not _cave_exiting:
		_net_exit_cave.rpc()
		_exit_cave()


@rpc("authority", "call_remote", "reliable")
func _net_exit_cave() -> void:
	_exit_cave()


var _cave_exiting: bool = false   # anti double-sortie (2 joueurs sur 2 portails)

func _exit_cave() -> void:
	if not _cave_active or _cave_exiting:
		return
	_cave_exiting = true
	_fade_transition(func() -> void:
		_teardown_cave()
		_restore_overworld()
	)


func _teardown_cave() -> void:
	for p in _cave_portals:
		if is_instance_valid(p): p.queue_free()
	_cave_portals.clear()
	for child in get_children():
		if child is Chest:
			child.queue_free()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get_parent() == self:
			e.queue_free()
	if is_instance_valid(_map):
		_map.queue_free()
	_map = null


func _restore_overworld() -> void:
	_map = _saved_map
	_saved_map = null
	if is_instance_valid(_map):
		add_child(_map)
		move_child(_map, 0)
		_refresh_map_bounds()
	for n in _saved_nodes:
		if is_instance_valid(n):
			add_child(n)
	_saved_nodes.clear()

	_alive      = _saved_alive
	_killed     = _saved_killed
	_room_total = _saved_room_total
	_wave_queue  = _saved_wave_queue
	_wave_num    = _saved_wave_num
	_waves_total = _saved_waves_total
	hud.set_kills(_killed, _room_total)

	for i in _team.size():
		if is_instance_valid(_team[i]) and i < _saved_team_pos.size():
			_team[i].global_position = _saved_team_pos[i]
			if i == _active_index:
				_cam_pos = _saved_team_pos[i]

	_cave_active  = false
	_cave_exiting = false
	_apply_ambiance()   # retour à l'ambiance du biome de la zone
	hud.set_wave(_zone_label())   # grotte consommée


func _fade_transition(mid: Callable) -> void:
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 99
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0, 0, 0, 0)
	fade_layer.add_child(rect)
	add_child(fade_layer)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(mid)
	tw.tween_property(rect, "color:a", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: fade_layer.queue_free())


# ══════════════════════════════════════════════════════════════════════
# MULTIJOUEUR — RPC côté arène (spawns/positions/HUD diffusés par l'hôte,
# demandes d'avancée remontées par les clients). Les nœuds portent les
# mêmes noms sur tous les pairs ("P<peer>" joueurs, "E<n>" ennemis).
# ══════════════════════════════════════════════════════════════════════

## Hôte → clients : un ennemi vient d'apparaître — instancie sa "coquille"
## locale (même nom, mêmes données préchargées, pas d'IA ni de collision).
@rpc("authority", "call_remote", "reliable")
func _net_spawn_enemy(ename: String, pid: int, lv: int, pos: Vector3,
		champion: bool, boss: bool, demi: bool = false) -> void:
	var data: PokemonData = _cache.get(str(pid))
	if data == null:
		push_warning("MP: données absentes pour l'ennemi pid=%d — coquille ignorée." % pid)
		return
	var instance := PokemonInstance.new(data, lv)
	instance.init_moves()
	var enemy = ENEMY_SCENE.instantiate()
	enemy.name = ename
	add_child(enemy)
	enemy.global_position = pos
	enemy.setup(instance, champion, boss, demi)
	enemy.set_net_shell()
	# Salle de dresseur : même langage visuel que l'hôte (burst de pokéball)
	if _is_boss_room(RunManager.inst().rooms_cleared) and not _cave_active:
		PokeballFX.play_burst(self, pos)


## Hôte → clients : positions groupées de tous les ennemis vivants.
@rpc("authority", "call_remote", "unreliable")
func _net_enemy_positions(names: PackedStringArray, poss: PackedVector3Array) -> void:
	for i in names.size():
		var e := get_node_or_null(NodePath(names[i]))
		if e != null and "net_target" in e:
			e.net_target = poss[i]


## Hôte → clients : mort d'un ennemi — anim de chute locale + XP pour NOTRE
## Pokémon SEULEMENT SI C'EST NOUS qui avons fait le kill (cf.
## attacker_peer, EnemyAI.take_damage) — pas systématiquement à chaque mort.
@rpc("authority", "call_remote", "reliable")
func _net_enemy_died(ename: String, xp: int, attacker_peer: int) -> void:
	var e := get_node_or_null(NodePath(ename))
	if e != null and e.has_method("_play_death_anim"):
		e._play_death_anim()
	if attacker_peer != Net.local_id():
		return
	var mine = _team[_active_index] if _active_index < _team.size() else null
	if is_instance_valid(mine) and not mine.pokemon_instance.is_fainted():
		mine.gain_xp(xp)


## Hôte → clients : compteur de kills de la salle (le décompte fait foi chez lui).
@rpc("authority", "call_remote", "reliable")
func _net_kills(killed: int, total: int) -> void:
	_killed     = killed
	_room_total = total
	hud.set_kills(killed, total)


## Hôte → clients : salle nettoyée — même butin pour tout le monde, puis le
## don au centre ; les portes arrivent juste après via _net_exits.
@rpc("authority", "call_remote", "reliable")
func _net_room_cleared(gold: int) -> void:
	GameManager.add_run_money(gold)
	hud.update_money(GameManager.run_money)
	hud.set_wave("Salle libérée !  +%d ₽" % gold)
	await get_tree().create_timer(0.8).timeout
	_spawn_boon(RunManager.inst().current_zone_bonus)


## Hôte → clients : les portes de sortie tirées par l'hôte (biomes + dons).
@rpc("authority", "call_remote", "reliable")
func _net_exits(exits_data: Array) -> void:
	_spawn_exit_portals_from(exits_data)


## Client → hôte : « je suis entré dans cette porte » — l'hôte tranche
## (premier arrivé) et rediffuse la décision à tout le monde.
@rpc("any_peer", "call_remote", "reliable")
func _net_request_advance(data: Dictionary) -> void:
	if multiplayer.is_server():
		_host_advance(data)


## Hôte → clients : transition actée vers la zone suivante.
@rpc("authority", "call_remote", "reliable")
func _net_advance(data: Dictionary) -> void:
	_do_advance(data)


# ── Barrière de chargement de zone (multijoueur) ──────────────────────
# L'hôte ne lance pas les ennemis tant que chaque client n'a pas signalé
# que SA zone est prête (préchargement API + map générée) — sinon les
# premiers _net_spawn_enemy arriveraient avant que les clients puissent
# instancier les coquilles. Clé par profondeur pour survivre aux zones
# successives sans course entre clear() et signalements précoces.

var _zone_ready: Dictionary = {}   # "depth:peer" → true


func _net_zone_barrier() -> void:
	if not _mp:
		return
	var depth := RunManager.inst().rooms_cleared
	if multiplayer.is_server():
		var deadline := Time.get_ticks_msec() + 20000   # filet : 20 s max
		while Time.get_ticks_msec() < deadline:
			var ok := true
			for id in Net.players:
				if id != 1 and not _zone_ready.has("%d:%d" % [depth, id]):
					ok = false
					break
			if ok:
				return
			await get_tree().create_timer(0.2).timeout
	else:
		_net_zone_ready.rpc_id(1, depth)


@rpc("any_peer", "call_remote", "reliable")
func _net_zone_ready(depth: int) -> void:
	if multiplayer.is_server():
		_zone_ready["%d:%d" % [depth, multiplayer.get_remote_sender_id()]] = true
