extends Node2D

const ZOOM  := 2.0     # zoom caméra combat (tiles 32px à l'écran)

var _map_w: float = 1280.0
var _map_h: float = 720.0


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
var _map:           Zone1          = null
var _entry_barrier: StaticBody2D   = null
var _exit_portals:  Array          = []

@onready var hud          = $HUD

@onready var player_spawn: Marker2D = $PlayerSpawnPoint

const TEAM_SCENE  := preload("res://scenes/combat/TeamMember.tscn")
const ENEMY_SCENE := preload("res://scenes/combat/EnemyPokemon.tscn")


func _ready() -> void:
	y_sort_enabled = true
	_register_switch_key()
	_map = get_node_or_null("Map") as Zone1
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
	for eid: int in (POOL_FLYERS + POOL_ELEM + POOL_SEMI_BOSS + POOL_BOSSES):
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
	_unlock_zone_rewards()
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
		enemy.died.connect(_on_enemy_died)
		_alive += 1


func _random_valid_spawn() -> Vector2:
	# Cherche une position libre (ni arbre, ni eau, ni bord)
	for _attempt in 40:
		var tx := randi_range(10, Zone1.W - 10)
		var ty := randi_range(10, Zone1.H - 10)
		var pos := Vector2(tx * 16.0 + 8.0, ty * 16.0 + 8.0)
		if is_instance_valid(_map) and _map.is_valid_spawn(pos):
			return pos
	# Fallback : milieu de la zone jouable
	return Vector2(640, 360)


# ── Signaux ───────────────────────────────────────────────────────────

func _on_enemy_died(xp_reward: int) -> void:
	_alive  -= 1
	_killed += 1
	hud.set_kills(_killed, _room_total)

	for member in _team:
		if is_instance_valid(member) and not member.pokemon_instance.is_fainted():
			member.gain_xp(xp_reward)

	if _alive <= 0:
		await get_tree().create_timer(1.0).timeout
		_on_room_cleared()


func _on_team_member_died(idx: int) -> void:
	hud.update_team_hp(idx, 0.0)

	if idx != _active_index:
		return  # un compagnon est KO, l'équipe continue

	# Le membre actif est KO → cherche un remplaçant
	var next := _find_next_alive()
	if next == -1:
		_game_over()
	else:
		_set_active(next)


func _find_next_alive() -> int:
	for i in _team.size():
		var idx := (_active_index + 1 + i) % _team.size()
		if not _team[idx].pokemon_instance.is_fainted():
			return idx
	return -1


func _unlock_zone_rewards() -> void:
	# Recrute 1 à 2 Pokémon aléatoires parmi les ennemis de la zone
	var pool: Array[int] = POOL_RODENTS + POOL_BUGS + POOL_FLYERS
	pool.shuffle()
	var count: int = 1 if GameManager.run_count <= 2 else 2
	for i in mini(count, pool.size()):
		GameManager.unlock_pokemon(pool[i])
	# Le boss de la vague 10 rejoint toujours
	var boss_pool: Array[int] = POOL_BOSSES.duplicate()
	boss_pool.shuffle()
	GameManager.unlock_pokemon(boss_pool[0])


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
		add_child(chest)


func _on_chest_opened(item: Dictionary) -> void:
	_apply_item(item)


func _apply_item(item: Dictionary) -> void:
	if _active_index >= _team.size():
		return
	var m = _team[_active_index]
	if not is_instance_valid(m):
		return
	var inst: PokemonInstance = m.pokemon_instance
	if inst.is_fainted():
		return
	var label: String = item.get("label", "Objet")
	var mult: float   = item.get("mult", 1.0)
	match item.get("effect", ""):
		"atk": inst.attack_mult  *= mult
		"def": inst.defense_mult *= mult
		"spd": inst.speed_mult   *= mult
		"hp":
			var add_hp := int(inst.max_hp * mult)
			inst.current_hp = mini(inst.max_hp, inst.current_hp + add_hp)
			var r := inst.hp_ratio()
			hud.update_team_hp(_active_index, r)
			hud.update_hp(r)
	hud.set_wave("✦ %s trouvé !" % label)


func _game_over() -> void:
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
		_map            = new_scene.instantiate() as Zone1
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
		await get_tree().create_timer(0.8).timeout
		_spawn_room_enemies()
	)
