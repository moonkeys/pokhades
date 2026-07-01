extends Node2D

const ZOOM  := 2.0     # zoom caméra combat (tiles 32px à l'écran)
const WATER_LAYER := 4  # cf. MapGenerator.WATER_LAYER — collision dédiée à l'eau

var _map_w: float = 1280.0
var _map_h: float = 720.0

# ── CS (Capacités Spéciales) — calculées une fois au spawn de l'équipe ──
var _cs_surf_unlocked:  bool = false   # Surf : effet d'équipe (cf. _compute_cs_unlocks)
var _cs_holder_idx: Dictionary = {}    # "cs_coupe"/"cs_force" -> team_index du porteur (-1 si aucun)
var _cs_triggers: Array = []   # [{"area":Area2D, "cs_id":String, "prompt":String, "on_use":Callable}, ...]
## {} si aucun ; sinon {"cs_id":String, "prompt":String, "on_use":Callable}
## Le prompt/l'interaction ne sont actifs que si le membre CONTRÔLÉ (actif)
## est justement le porteur de cette CS — recalculé chaque frame (cf.
## _refresh_cs_prompt) pour réagir immédiatement à un changement de Pokémon
## actif même sans bouger.
var _near_obstacle: Dictionary = {}
var _near_chest_prompt: String = ""   # "" si aucun coffre à portée


# ── Pools ennemis — Zone 1 ───────────────────────────────────────────
# Rongeurs (Normal)  — vagues 1+
const POOL_RODENTS:   Array[int] = [399, 19, 263, 161, 819]
# Insectes (Insecte) — vagues 1+
const POOL_BUGS:      Array[int] = [10, 13, 265, 824, 851]
# Éclaireurs (Normal/Vol) — vagues 3+
const POOL_FLYERS:    Array[int] = [16, 396, 661, 519]
# Premiers élémentaires — vagues 4+
const POOL_ELEM:      Array[int] = [403, 261, 191, 43]
# Semi-boss (évolutions) — vagues 5+
const POOL_SEMI_BOSS: Array[int] = [20, 400, 17, 404, 402, 262, 55, 162]
# Boss de zone — vague 10
const POOL_BOSSES:    Array[int] = [143, 123, 128, 24, 22, 862]
# Élite de grotte — allure plus imposante, réservés aux arènes de demi-boss
const POOL_CAVE_ELITE: Array[int] = [217, 229, 359, 297, 342]

const PLAYER_LEVEL:    int = 10
const SEMI_BOSS_LEVEL: int = 13
const BOSS_LEVEL:      int = 18

# Décalages de spawn pour les membres de l'équipe
const SPAWN_OFFSETS: Array = [
	Vector2(0,    0),
	Vector2(68,  22),
	Vector2(-68, 22),
	Vector2(0,  -68),
	Vector2(68, -22),
	Vector2(-68,-22),
]

var _team:         Array   = []
var _active_index: int    = 0
var _killed: int = 0
var _alive:  int = 0
var _room_total: int = 0   # nombre total d'ennemis dans la salle courante
var _cache: Dictionary = {}
var _cam_pos: Vector2 = Vector2.ZERO
var _follow_mode: bool = true

# Système de portes
var _map:           MapBase        = null
var _entry_barrier: StaticBody2D   = null
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

@onready var hud          = $HUD

@onready var player_spawn: Marker2D = $PlayerSpawnPoint

const TEAM_SCENE  := preload("res://scenes/combat/TeamMember.tscn")
const ENEMY_SCENE := preload("res://scenes/combat/EnemyPokemon.tscn")


func _ready() -> void:
	y_sort_enabled = true
	_register_switch_key()
	_map = get_node_or_null("Map") as MapBase
	_refresh_map_bounds()
	RunManager.inst().start_run()
	_cam_pos = player_spawn.global_position
	_apply_canvas_transform()
	_preload_all()


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


func _process(delta: float) -> void:
	if _team.size() > 0 and is_instance_valid(_team[_active_index]):
		_cam_pos = _cam_pos.lerp(_team[_active_index].global_position, 8.0 * delta)
	_apply_canvas_transform()

	if Input.is_action_just_pressed("switch_pokemon"):
		_cycle_active()

	if Input.is_action_just_pressed("toggle_follow"):
		_follow_mode = not _follow_mode
		_update_leaders()
		hud.set_follow_mode(_follow_mode)

	_refresh_cs_prompt()
	if not _near_obstacle.is_empty() and Input.is_action_just_pressed("interact"):
		var cb: Callable = _near_obstacle["on_use"]
		_near_obstacle = {}
		_refresh_interact_prompt()
		if cb.is_valid():
			cb.call()
		_spawn_cs_triggers()


func _refresh_map_bounds() -> void:
	if is_instance_valid(_map):
		var sz := _map.get_map_pixel_size()
		_map_w = sz.x
		_map_h = sz.y
	else:
		_map_w = 1280.0
		_map_h = 720.0


func _apply_canvas_transform() -> void:
	var vp      := get_viewport().get_visible_rect().size
	var half_vw := vp.x * 0.5 / ZOOM
	var half_vh := vp.y * 0.5 / ZOOM
	var cx := clampf(_cam_pos.x, half_vw, _map_w - half_vw)
	var cy := clampf(_cam_pos.y, half_vh, _map_h - half_vh)
	# Transform : scale + translation pour centrer sur (cx, cy)
	var t := Transform2D()
	t.x      = Vector2(ZOOM, 0)
	t.y      = Vector2(0, ZOOM)
	t.origin = Vector2(vp.x * 0.5 - cx * ZOOM, vp.y * 0.5 - cy * ZOOM)
	get_viewport().canvas_transform = t


# ── Chargement ────────────────────────────────────────────────────────

func _preload_all() -> void:
	var team_ids: Array = GameManager.get_run_team()
	var priority_seen: Dictionary = {}

	# Phase 1 (bloquante) : équipe + salle 0 uniquement (rodents + bugs)
	# → ~10-15 Pokémon, zone démarre dès que c'est prêt
	var priority_ids: Array = team_ids.duplicate()
	for eid: int in (POOL_RODENTS + POOL_BUGS):
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

	# Phase 2 (arrière-plan) : pools des salles suivantes
	# Ils seront mis en cache avant que le joueur les atteigne
	for eid: int in (POOL_FLYERS + POOL_ELEM + POOL_SEMI_BOSS + POOL_BOSSES + POOL_CAVE_ELITE):
		if not priority_seen.has(eid):
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
			if power > 0 and not move_data.is_empty():
				for entry: Dictionary in entries:
					var pd: PokemonData = entry["pd"]
					var lv: int         = entry["level"]
					var md := MoveData.new()
					md.api_name     = mname
					md.display_name = mname.replace("-", " ").capitalize()
					md.type         = move_data.get("type", "normal")
					md.power        = power
					md.damage_class = move_data.get("damage_class", "physical")
					md.level_learned = lv
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
	_spawn_entry_barrier()
	_spawn_chests()
	_spawn_cave_portals()
	_spawn_cs_triggers()
	hud.set_wave(RunManager.inst().get_zone_name())
	hud.set_kills(0, 0)
	await get_tree().create_timer(1.2).timeout
	_spawn_room_enemies()


func _spawn_team() -> void:
	var team_ids: Array[int] = GameManager.get_run_team()
	# Spawn juste au-dessus de l'entrée (pas au centre de la map)
	var spawn_center: Vector2
	if is_instance_valid(_map):
		var et := _map.entry_tile
		spawn_center = Vector2(et.x * 16.0 + 8.0, (et.y - 4) * 16.0 + 8.0)
	else:
		spawn_center = player_spawn.global_position

	for i in team_ids.size():
		var id: int  = team_ids[i]
		var data: PokemonData = _cache.get(str(id))
		if not data:
			push_error("Pokémon introuvable pour id=%d" % id)
			continue

		var instance := PokemonInstance.new(data, PLAYER_LEVEL)
		instance.init_moves()
		var member   = TEAM_SCENE.instantiate()
		add_child(member)
		member.global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]

		var is_active := i == 0
		member.setup(instance, i, is_active)
		_team.append(member)

		# Connexions HUD — les lambdas capturent 'i' par valeur via idx
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
			if idx == _active_index:
				hud.show_evolution(name_fr)
		)
		member.portrait_ready.connect(func(midx: int, tex: Texture2D) -> void:
			hud.update_team_portrait(midx, tex)
			_team[midx].pokemon_instance.portrait_texture = tex
		)
		member.died.connect(_on_team_member_died.bind(idx))

	# Centre la caméra immédiatement sur le premier membre
	_cam_pos = _team[0].global_position
	_apply_canvas_transform()

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


## Détermine une fois pour la run quelles CS l'équipe peut utiliser, en
## fonction du Pokémon assigné (cf. GameManager.assign_cs) — basé sur la
## composition d'équipe au lancement, insensible aux évolutions en cours de run.
func _compute_cs_unlocks(team_ids: Array[int]) -> void:
	_cs_surf_unlocked = GameManager.owns_cs("cs_surf") and GameManager.get_cs_holder("cs_surf") in team_ids

	# Coupe/Force : seul le membre CONTRÔLÉ compte — on retrouve son index
	# d'équipe (résiste à l'évolution, basée sur la composition au lancement).
	_cs_holder_idx.clear()
	for cs_id in ["cs_coupe", "cs_force"]:
		var idx := -1
		if GameManager.owns_cs(cs_id):
			idx = team_ids.find(GameManager.get_cs_holder(cs_id))
		_cs_holder_idx[cs_id] = idx

	# CS Surf : toute l'équipe ignore la couche physique de l'eau (elle
	# "surfe" ensemble), sinon comportement normal (bloquée par l'eau).
	for m in _team:
		if is_instance_valid(m):
			m.collision_mask = 1 if _cs_surf_unlocked else (1 | WATER_LAYER)


## Vrai si le membre actuellement CONTRÔLÉ (actif) est le porteur de `cs_id`.
func _active_holds_cs(cs_id: String) -> bool:
	return _cs_holder_idx.get(cs_id, -1) == _active_index


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
	var leader: Node2D = _team[_active_index] if _follow_mode else null
	for i in _team.size():
		if i != _active_index:
			_team[i]._leader = leader


# ── Combat — salle unique ─────────────────────────────────────────────

func _spawn_room_enemies() -> void:
	var room  := RunManager.inst().rooms_cleared
	var count := 4 + room * 2
	var lv    := PLAYER_LEVEL + room * 2
	var pool  := _pool_for_room(room)
	_spawn_from_pool(pool, count, lv)
	_room_total = _alive
	hud.set_kills(0, _room_total)
	hud.set_wave("%s — %d ennemis" % [RunManager.inst().get_zone_name(), _room_total])


func _pool_for_room(room: int) -> Array[int]:
	var pool: Array[int] = []
	pool.append_array(POOL_RODENTS)
	pool.append_array(POOL_BUGS)
	if room >= 2: pool.append_array(POOL_FLYERS)
	if room >= 3: pool.append_array(POOL_ELEM)
	if room >= 4: pool.append_array(POOL_SEMI_BOSS)
	return pool


func _on_room_cleared() -> void:
	var gold := 30 + RunManager.inst().rooms_cleared * 20
	GameManager.add_gold(gold)
	hud.set_wave("Salle libérée !  +%d Or" % gold)
	hud.set_kills(_killed, _room_total)
	await get_tree().create_timer(0.8).timeout
	_show_run_status(gold)


func _show_run_status(gold: int) -> void:
	var screen := RunStatusScreen.new()
	add_child(screen)

	# Propose 2 bonus aléatoires depuis le pool global de RunManager
	var pool: Array = RunManager.BONUSES.duplicate()
	pool.shuffle()
	var offers: Array = []
	for i in mini(2, pool.size()):
		var b := pool[i] as Dictionary
		offers.append({"bonus": b.get("id", "heal_half"), "bonus_label": b.get("label", "")})

	screen.setup(_team, gold, offers)
	screen.bonus_chosen.connect(func(bid: String) -> void:
		_apply_bonus(bid)
		screen.queue_free()
		_spawn_exit_portals()
	, CONNECT_ONE_SHOT)


func _spawn_from_pool(pool: Array[int], count: int, lv: int) -> void:
	if pool.is_empty():
		return
	for i in count:
		var id: int = pool[randi() % pool.size()]
		var cache_key: String = str(id)
		if not _cache.has(cache_key):
			continue
		var data: PokemonData = _cache[cache_key]
		var instance := PokemonInstance.new(data, lv)
		instance.init_moves()
		var enemy = ENEMY_SCENE.instantiate()
		add_child(enemy)
		enemy.global_position = _random_valid_spawn()
		enemy.setup(instance)
		enemy.died.connect(_on_enemy_died.bind(id, data.is_base_form))
		_alive += 1


func _random_valid_spawn() -> Vector2:
	# Cherche une position libre (ni arbre, ni eau, ni bord) — taille réelle de la map
	var sz := Vector2i(MapBase.W, MapBase.H)
	if is_instance_valid(_map):
		sz = _map.get_map_cell_size()
	for _attempt in 40:
		var tx := randi_range(6, maxi(7, sz.x - 6))
		var ty := randi_range(6, maxi(7, sz.y - 6))
		var pos := Vector2(tx * 16.0 + 8.0, ty * 16.0 + 8.0)
		if is_instance_valid(_map) and _map.is_valid_spawn(pos):
			return pos
	# Fallback : centre de la map
	return Vector2(sz.x * 8.0, sz.y * 8.0)


# ── Signaux ───────────────────────────────────────────────────────────

func _on_enemy_died(xp_reward: int, pid: int, is_base_form: bool) -> void:
	_alive  -= 1
	_killed += 1
	hud.set_kills(_killed, _room_total)

	for member in _team:
		if is_instance_valid(member) and not member.pokemon_instance.is_fainted():
			member.gain_xp(xp_reward)

	if GameManager.record_defeat(pid, is_base_form):
		var name_fr := (_cache[str(pid)] as PokemonData).name_fr if _cache.has(str(pid)) else "Pokémon"
		hud.show_unlock(name_fr)

	if _alive <= 0:
		await get_tree().create_timer(1.0).timeout
		if _cave_active:
			_on_cave_cleared()
		else:
			_on_room_cleared()


func _on_team_member_died(idx: int) -> void:
	hud.update_team_hp(idx, 0.0)

	# Filet de sécurité : si toute l'équipe est KO, on quitte quel que soit
	# l'index qui vient de mourir (évite un blocage si _active_index est périmé).
	if _is_team_wiped():
		_game_over()
		return

	if idx != _active_index:
		return  # un compagnon est KO, l'équipe continue

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


func _spawn_chests() -> void:
	if not is_instance_valid(_map):
		return
	for cell: Vector2i in _map.get_chest_cells():
		var chest := Chest.new()
		chest.position = Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
		chest.setup(_map.get_objects_layer(), cell, _map.source_id)
		chest.opened.connect(_on_chest_opened)
		_wire_chest_prompt(chest)
		add_child(chest)


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
		_register_cs_trigger(approach, "cs_coupe", "Appuyer sur [E] pour couper l'arbre (CS Coupe)",
			func() -> void: _map.cut_tree_group(cells)
		)

	var boulders: Dictionary = _map.get_force_boulder_approaches()
	for bcell: Vector2i in boulders:
		var approach: Vector2i = boulders[bcell]
		var captured_bcell: Vector2i = bcell
		_register_cs_trigger(approach, "cs_force", "Appuyer sur [E] pour casser le rocher (CS Force)",
			func() -> void: _map.break_rock_at(captured_bcell)
		)


func _register_cs_trigger(approach: Vector2i, cs_id: String, prompt: String, on_use: Callable) -> void:
	var area := Area2D.new()
	area.position         = Vector2(approach.x * 16.0 + 8.0, approach.y * 16.0 + 8.0)
	area.collision_layer  = 0
	area.collision_mask   = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size  = Vector2(16, 16)
	cs.shape = sh
	area.add_child(cs)
	add_child(area)
	_cs_triggers.append({"area": area, "cs_id": cs_id, "prompt": prompt, "on_use": on_use})


## Recalculé chaque frame : le joueur doit à la fois se tenir dans la zone
## ET contrôler (Pokémon actif) le porteur de la bonne CS. Réagit donc
## immédiatement à un changement de Pokémon actif [TAB], même sans bouger.
func _refresh_cs_prompt() -> void:
	if _active_index >= _team.size() or not is_instance_valid(_team[_active_index]):
		_clear_cs_prompt()
		return
	var active_body: Node = _team[_active_index]
	for entry: Dictionary in _cs_triggers:
		var area: Area2D = entry["area"]
		if not is_instance_valid(area): continue
		if active_body in area.get_overlapping_bodies() and _active_holds_cs(entry["cs_id"]):
			if _near_obstacle.get("prompt", "") != entry["prompt"]:
				_near_obstacle = entry
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
	hud.set_wave("DÉFAITE...")
	var consolation_gold := RunManager.inst().rooms_cleared * 15
	if consolation_gold > 0:
		GameManager.add_gold(consolation_gold)
	await get_tree().create_timer(2.5).timeout
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


# ── Système de portes ─────────────────────────────────────────────────

func _spawn_entry_barrier() -> void:
	if is_instance_valid(_entry_barrier):
		_entry_barrier.queue_free()
	if not is_instance_valid(_map):
		return
	var ep  := _map.entry_tile
	var pos := Vector2(ep.x * 16.0 + 8.0, ep.y * 16.0 + 8.0)

	var barrier := StaticBody2D.new()
	barrier.name            = "EntryBarrier"
	barrier.collision_layer = 1
	barrier.collision_mask  = 0
	barrier.position        = pos

	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size  = Vector2(80, 16)
	cs.shape = sh
	barrier.add_child(cs)

	# Visuel — barre de bois sombre
	var rect := ColorRect.new()
	rect.size     = Vector2(80, 14)
	rect.position = Vector2(-40, -7)
	rect.color    = Color(0.28, 0.18, 0.08, 0.92)
	barrier.add_child(rect)

	add_child(barrier)
	_entry_barrier = barrier


func _spawn_exit_portals() -> void:
	for p in _exit_portals:
		if is_instance_valid(p): p.queue_free()
	_exit_portals.clear()

	if not is_instance_valid(_map):
		get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
		return

	var exits_data := RunManager.inst().get_exits(2)
	var exit_tiles := [_map.exit_A, _map.exit_B, _map.exit_C]

	hud.set_wave("Choisissez une sortie ↑")

	for i in exits_data.size():
		var data: Dictionary = exits_data[i]
		var tile: Vector2i   = exit_tiles[i]
		var portal           := ExitPortal.new()
		portal.position      = Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)
		portal.setup(data)
		portal.chosen.connect(_on_exit_chosen)
		add_child(portal)
		_exit_portals.append(portal)


func _on_exit_chosen(data: Dictionary) -> void:
	for p in _exit_portals:
		if is_instance_valid(p): p.queue_free()
	_exit_portals.clear()

	_apply_bonus(data.get("bonus", ""))
	RunManager.inst().advance(data.get("zone_idx", 0))
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

		# Réinitialiser le combat
		if is_instance_valid(_entry_barrier):
			_entry_barrier.queue_free()
		_entry_barrier = null
		_alive      = 0
		_killed     = 0
		_room_total = 0

		# Repositionner l'équipe à l'entrée + mini-soin
		var et := _map.entry_tile
		var spawn_center := Vector2(et.x * 16.0 + 8.0, (et.y - 4) * 16.0 + 8.0)
		for i in _team.size():
			if is_instance_valid(_team[i]):
				_team[i].global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]
				if not _team[i].pokemon_instance.is_fainted():
					_team[i].pokemon_instance.heal_percent(0.20)

		hud.set_wave(RunManager.inst().get_zone_name())
		hud.set_kills(0, 0)

		# Fondu depuis le noir
		var tw2 := create_tween()
		tw2.tween_property(fade_rect, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
		tw2.tween_callback(func() -> void: fade_layer.queue_free())

		await get_tree().process_frame
		_spawn_entry_barrier()
		_spawn_chests()
		_spawn_cave_portals()
		_spawn_cs_triggers()
		await get_tree().create_timer(0.8).timeout
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
		var area := Area2D.new()
		area.position        = Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
		area.collision_layer = 0
		area.collision_mask  = 1
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size  = Vector2(14, 14)
		cs.shape = sh
		area.add_child(cs)
		var lbl := Label.new()
		lbl.text     = "⛰ Grotte"
		lbl.position = Vector2(-26, -34)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.02))
		lbl.add_theme_constant_override("outline_size", 4)
		area.add_child(lbl)
		var entrance := cell
		area.body_entered.connect(func(body: Node) -> void:
			if _cave_active: return
			if not (body.is_in_group("players") and body.get("is_active") == true): return
			_enter_cave(entrance)
		)
		add_child(area)
		_cave_portals.append(area)


func _enter_cave(_entrance: Vector2i) -> void:
	if _cave_active:
		return
	_cave_active = true
	_fade_transition(func() -> void:
		_save_overworld()
		_load_cave()
		_spawn_cave_bosses()
	)


func _save_overworld() -> void:
	_saved_alive      = _alive
	_saved_killed     = _killed
	_saved_room_total = _room_total
	_saved_team_pos.clear()
	for m in _team:
		_saved_team_pos.append(m.global_position if is_instance_valid(m) else Vector2.ZERO)

	# Détache (gèle) tout l'overworld : ennemis, coffres, barrière, map
	_saved_nodes.clear()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get_parent() == self:
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
	_alive = 0
	_killed = 0
	_room_total = 0

	var et := _map.entry_tile
	var spawn_center := Vector2(et.x * 16.0 + 8.0, (et.y - 2) * 16.0 + 8.0)
	for i in _team.size():
		if is_instance_valid(_team[i]):
			_team[i].global_position = spawn_center + SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]
	_cam_pos = spawn_center


func _spawn_cave_bosses() -> void:
	var rooms := RunManager.inst().rooms_cleared
	# 2 demi-boss renforcés (allure imposante) — costauds mais pas injustes.
	_spawn_from_pool(POOL_CAVE_ELITE, CAVE_BOSS_COUNT, SEMI_BOSS_LEVEL + rooms * 3)
	_room_total = _alive
	hud.set_kills(0, _room_total)
	if _alive > 0:
		hud.set_wave("⛰ Arène d'élite — %d adversaires !" % _room_total)
	else:
		_on_cave_cleared()   # sécurité : pool non chargé → récompense directe


func _on_cave_cleared() -> void:
	var gold := 150 + RunManager.inst().rooms_cleared * 30
	GameManager.add_gold(gold)
	for i in _team.size():
		var m = _team[i]
		if is_instance_valid(m) and not m.pokemon_instance.is_fainted():
			m.pokemon_instance.current_hp = m.pokemon_instance.max_hp
			hud.update_team_hp(i, 1.0)
	if _active_index < _team.size():
		hud.update_hp(1.0)
	hud.set_wave("⛰ Arène vaincue !  +%d Or" % gold)
	await get_tree().create_timer(0.8).timeout
	_spawn_cave_reward()


func _spawn_cave_reward() -> void:
	if not is_instance_valid(_map):
		_exit_cave()
		return
	var sz   := _map.get_map_cell_size()
	var cell := Vector2i(sz.x / 2, sz.y / 2)
	var chest := Chest.new()
	chest.position = Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
	# Objet garanti puissant (meilleur du pool)
	chest.setup(_map.get_objects_layer(), cell, _map.source_id,
		{"api_name": "choice-band", "effect": "atk", "mult": 1.5})
	chest.opened.connect(func(item: Dictionary) -> void:
		_show_item_reward(item, _spawn_cave_return_portal)
	, CONNECT_ONE_SHOT)
	_wire_chest_prompt(chest)
	add_child(chest)
	hud.set_wave("✦ Coffre doré — approche-toi !")


func _spawn_cave_return_portal() -> void:
	if not is_instance_valid(_map):
		_exit_cave()
		return
	var sz   := _map.get_map_cell_size()
	var tile := Vector2i(sz.x / 2, 3)
	var portal := ExitPortal.new()
	portal.position = Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)
	portal.setup({"zone_name": "Retour", "bonus_label": ""})
	portal.chosen.connect(func(_d: Dictionary) -> void: _exit_cave(), CONNECT_ONE_SHOT)
	add_child(portal)
	_cave_portals.append(portal)
	hud.set_wave("↑ Sortie de la grotte")


func _exit_cave() -> void:
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
	hud.set_kills(_killed, _room_total)

	for i in _team.size():
		if is_instance_valid(_team[i]) and i < _saved_team_pos.size():
			_team[i].global_position = _saved_team_pos[i]
			if i == _active_index:
				_cam_pos = _saved_team_pos[i]

	_cave_active = false
	hud.set_wave(RunManager.inst().get_zone_name())   # grotte consommée


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
