extends CharacterBody2D

const SPEED        := 150.0
const ATTACK_RANGE    := 65.0
const ATTACK_COOLDOWN := 0.7
const DISPLAY_SIZE    := 28.0

# Projection iso 30° — inverse pour garder les sprites debout (billboard)
# sin(30°)/cos(30°) = tan(30°) ≈ 0.5774

# IA compagnon
const AI_SPEED        := 120.0
const AI_SEEK_RADIUS  := 300.0   # cherche un ennemi dans ce rayon
const AI_FOLLOW_DIST  := 90.0    # se rapproche du leader si plus loin que ça
const REPATH_INTERVAL  := 0.4

var pokemon_instance: PokemonInstance
var team_index: int  = 0
var is_active:  bool = false
var _leader: Node2D = null        # membre actif à suivre (compagnons seulement)

var _attack_timer:       float = 0.0
var _attack_flash:       float = 0.0
var _current_anim:       String = "idle"
var _has_directional:    bool = false
var _evolving:           bool = false
var _selected_move_idx:  int  = 0   # capacité active (touches 1-4)

# Pathfinding (contournement d'obstacles, mode compagnon)
var _map:               MapBase = null
var _path_repath_timer: float   = 0.0
var _path_waypoint:     Vector2 = Vector2.ZERO

signal hp_changed(ratio: float)
signal cooldown_changed(ratio: float)
signal xp_changed(ratio: float, level: int)
signal leveled_up(level: int)
signal evolved(name_fr: String)
signal portrait_ready(idx: int, texture: Texture2D)
signal move_selected(idx: int)
signal died

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(instance: PokemonInstance, idx: int, active: bool) -> void:
	add_to_group("players")
	pokemon_instance = instance
	team_index = idx
	is_active  = active
	var col := Color(1.0, 0.55, 0.0) if active else Color(0.35, 0.55, 1.0)
	_add_placeholder(col)
	PMDSprites.get_walk_sprites(instance.data.id, self, _on_pmd_loaded)
	_map = get_tree().get_first_node_in_group("combat_map") as MapBase
	if active:
		_register_move_keys()


func _register_move_keys() -> void:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4]
	for i in 4:
		var action := "use_move_%d" % (i + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = keys[i]
			InputMap.action_add_event(action, ev)


func _add_placeholder(color: Color) -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(32, 32)
	rect.position = Vector2(-16, -16)
	rect.color = color
	rect.name = "Placeholder"
	add_child(rect)


func _on_pmd_loaded(result: Dictionary) -> void:
	if result.is_empty():
		_load_fallback_sprite(pokemon_instance.data.sprite_url)
		return
	_has_directional = true
	sprite.sprite_frames = result.frames
	var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
	sprite.transform = _billboard_tf(s)
	sprite.play("idle")
	_remove_placeholder()
	if result.frames.has_animation("walk_down") and result.frames.get_frame_count("walk_down") > 0:
		portrait_ready.emit(team_index, result.frames.get_frame_texture("walk_down", 0))


func _load_fallback_sprite(url: String) -> void:
	if url.is_empty():
		_remove_placeholder()
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		if result == OK and code == 200:
			var img := Image.new()
			if img.load_png_from_buffer(body) == OK:
				var tex := ImageTexture.create_from_image(img)
				var frames := SpriteFrames.new()
				for anim in ["idle", "walk_down", "walk_up", "walk_left", "walk_right",
						"walk_downright", "walk_upright", "walk_upleft", "walk_downleft"]:
					frames.add_animation(anim)
					frames.set_animation_loop(anim, true)
					frames.add_frame(anim, tex)
				sprite.sprite_frames = frames
				var s := DISPLAY_SIZE / float(max(img.get_width(), img.get_height()))
				sprite.transform = _billboard_tf(s)
				sprite.play("idle")
				_remove_placeholder()
				portrait_ready.emit(team_index, tex)
		http.queue_free()
	)
	http.request(url)


func _remove_placeholder() -> void:
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


func _billboard_tf(s: float) -> Transform2D:
	return Transform2D(Vector2(s, 0), Vector2(0, s), Vector2.ZERO)


func _draw() -> void:
	if not is_active:
		return
	draw_circle(Vector2.ZERO, ATTACK_RANGE, Color(1.0, 0.9, 0.0, 0.03 + _attack_flash * 0.10))
	draw_arc(Vector2.ZERO, ATTACK_RANGE, 0.0, TAU, 48, Color(1.0, 0.85, 0.0, 0.18 + _attack_flash * 0.55), 2.0)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pokemon_instance) or pokemon_instance.is_fainted():
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_attack_flash = max(0.0, _attack_flash - delta * 4.0)
	queue_redraw()

	if is_active:
		_player_process()
		cooldown_changed.emit(1.0 - (_attack_timer / ATTACK_COOLDOWN))
	else:
		_companion_process(delta)


# ── Mode joueur ───────────────────────────────────────────────────────

func _player_process() -> void:
	# Sélection de capacité 1-4
	for i in 4:
		if Input.is_action_just_pressed("use_move_%d" % (i + 1)):
			if i < pokemon_instance.equipped_moves.size():
				_selected_move_idx = i
				move_selected.emit(_selected_move_idx)
			break

	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	).normalized()

	velocity = dir * SPEED
	_update_anim(dir)
	move_and_slide()

	if _attack_timer <= 0.0 and not _evolving:
		if Input.is_action_pressed("ui_accept"):
			_attack()
		else:
			_try_auto_attack()


# ── IA compagnon ──────────────────────────────────────────────────────

func _companion_process(delta: float) -> void:
	var nearest := _nearest_enemy(AI_SEEK_RADIUS)

	if nearest:
		var dist := global_position.distance_to(nearest.global_position)
		if dist <= ATTACK_RANGE:
			velocity = Vector2.ZERO
			_update_anim(Vector2.ZERO)
			if _attack_timer <= 0.0 and not _evolving:
				_attack()
		else:
			var steer_pos := _get_steer_target(nearest.global_position, delta)
			var dir := (steer_pos - global_position).normalized()
			velocity = dir * AI_SPEED
			_update_anim(dir)
			move_and_slide()
	elif is_instance_valid(_leader):
		var dist_leader := global_position.distance_to(_leader.global_position)
		if dist_leader > AI_FOLLOW_DIST:
			var steer_pos := _get_steer_target(_leader.global_position, delta)
			var dir := (steer_pos - global_position).normalized()
			velocity = dir * AI_SPEED
			_update_anim(dir)
			move_and_slide()
		else:
			velocity = Vector2.ZERO
			_update_anim(Vector2.ZERO)
	else:
		velocity = Vector2.ZERO
		_update_anim(Vector2.ZERO)


## Renvoie le point vers lequel diriger le compagnon : ligne droite si la vue
## est dégagée, sinon le prochain point de détour via la grille A* de la map.
func _get_steer_target(target_pos: Vector2, delta: float) -> Vector2:
	_path_repath_timer -= delta
	if _has_clear_line_of_sight(target_pos):
		_path_repath_timer = 0.0
		return target_pos

	if not is_instance_valid(_map):
		return target_pos

	if _path_repath_timer <= 0.0:
		_path_repath_timer = REPATH_INTERVAL
		_path_waypoint = _map.get_next_path_point(global_position, target_pos)

	if global_position.distance_to(_path_waypoint) < 10.0:
		return target_pos

	return _path_waypoint


func _has_clear_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.collision_mask = 1
	query.exclude        = [self]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _nearest_enemy(max_dist: float) -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var min_d := max_dist
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d < min_d:
			min_d = d
			nearest = enemy
	return nearest


# ── Animation ─────────────────────────────────────────────────────────

func _update_anim(dir: Vector2) -> void:
	if not sprite.sprite_frames or _evolving:
		return
	var anim: String
	if dir.length() < 0.1:
		anim = "idle"
	else:
		var sector := int(round(fposmod(dir.angle(), TAU) / (TAU / 8.0))) % 8
		match sector:
			0: anim = "walk_right"
			1: anim = "walk_downright"
			2: anim = "walk_down"
			3: anim = "walk_downleft"
			4: anim = "walk_left"
			5: anim = "walk_upleft"
			6: anim = "walk_up"
			_: anim = "walk_upright"

	if not _has_directional and dir.x != 0:
		sprite.flip_h = dir.x < 0

	if anim != _current_anim:
		_current_anim = anim
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


# ── Attaque ───────────────────────────────────────────────────────────

func _try_auto_attack() -> void:
	if _nearest_enemy(ATTACK_RANGE):
		_attack()


func _attack() -> void:
	_attack_flash = 1.0
	_attack_timer = ATTACK_COOLDOWN

	var move_type:  String
	var move_power: int
	var moves: Array = pokemon_instance.equipped_moves
	if not moves.is_empty():
		var idx  := clampi(_selected_move_idx, 0, moves.size() - 1)
		var move: MoveData = moves[idx]
		if move and move.power > 0:
			move_type  = move.type
			move_power = move.power
		else:
			move_type  = pokemon_instance.get_attack_type()
			move_power = pokemon_instance.get_attack_power()
	else:
		move_type  = pokemon_instance.get_attack_type()
		move_power = pokemon_instance.get_attack_power()

	var lunge_pos := Vector2.ZERO
	var hit_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= ATTACK_RANGE:
			var dmg := DamageCalculator.calculate(pokemon_instance, enemy.pokemon_instance, move_power, move_type)
			enemy.take_damage(dmg)
			lunge_pos += enemy.global_position
			hit_count += 1

	if not _evolving:
		if hit_count > 0:
			_play_attack_lunge(lunge_pos / hit_count)
		else:
			sprite.modulate = Color(2.2, 2.2, 2.2)
			get_tree().create_timer(0.1).timeout.connect(func():
				if is_instance_valid(self) and not _evolving:
					sprite.modulate = Color.WHITE
			)


func _play_attack_lunge(target_pos: Vector2) -> void:
	var dir := (target_pos - global_position).normalized()
	var offset := dir * 14.0
	var tw := create_tween()
	tw.tween_property(sprite, "position", offset, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.14).set_ease(Tween.EASE_IN)
	sprite.modulate = Color(2.2, 2.2, 2.2)
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self) and not _evolving:
			sprite.modulate = Color.WHITE
	)


func take_damage(amount: int) -> void:
	pokemon_instance.take_damage(amount)
	if not _evolving:
		sprite.modulate = Color(2.0, 0.3, 0.3)
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(self) and not _evolving:
				sprite.modulate = Color.WHITE
		)
	hp_changed.emit(pokemon_instance.hp_ratio())
	if pokemon_instance.is_fainted():
		_play_faint_anim()


func _play_faint_anim() -> void:
	set_physics_process(false)
	remove_from_group("players")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(0.9, 0.3, 0.3, 0.0), 0.55).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "position", Vector2(0.0, 18.0), 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: died.emit())


# ── XP & Évolution ───────────────────────────────────────────────────

func gain_xp(amount: int) -> void:
	var leveled := pokemon_instance.add_xp(amount)
	xp_changed.emit(pokemon_instance.xp_ratio(), pokemon_instance.level)
	if leveled:
		leveled_up.emit(pokemon_instance.level)
		hp_changed.emit(pokemon_instance.hp_ratio())
		_check_evolution()


func _check_evolution() -> void:
	var evo: Variant = GameManager.EVOLUTIONS.get(pokemon_instance.data.id)
	if evo == null:
		return
	if pokemon_instance.level >= evo["level"]:
		_start_evolution(evo["evolves_to"])


func _start_evolution(new_id: int) -> void:
	_evolving = true
	var tween := create_tween().set_loops()
	tween.tween_property(sprite, "modulate", Color(4.0, 4.0, 4.0), 0.12)
	tween.tween_property(sprite, "modulate", Color(0.8, 0.8, 1.0), 0.12)

	PokemonAPI.get_pokemon(new_id, func(api_data: Dictionary) -> void:
		if not is_instance_valid(self):
			return
		if api_data.is_empty():
			tween.kill()
			sprite.modulate = Color.WHITE
			_evolving = false
			return
		var new_data := PokemonData.from_api(api_data)
		pokemon_instance.evolve_to(new_data)
		hp_changed.emit(pokemon_instance.hp_ratio())

		PMDSprites.get_walk_sprites(new_id, self, func(result: Dictionary) -> void:
			if not is_instance_valid(self):
				return
			tween.kill()
			_has_directional = false
			if not result.is_empty():
				_has_directional = true
				sprite.sprite_frames = result.frames
				var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
				sprite.transform = _billboard_tf(s)
				if result.frames.has_animation("walk_down") and result.frames.get_frame_count("walk_down") > 0:
					portrait_ready.emit(team_index, result.frames.get_frame_texture("walk_down", 0))
			else:
				_load_fallback_sprite(new_data.sprite_url)
			sprite.modulate = Color.WHITE
			_current_anim = ""
			sprite.play("idle")
			_evolving = false
			evolved.emit(new_data.name_fr)
		)
	)
