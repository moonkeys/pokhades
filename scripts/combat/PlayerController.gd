extends CharacterBody2D

const SPEED := 150.0
const ATTACK_RANGE := 100.0
const ATTACK_COOLDOWN := 0.7
const ATTACK_POWER := 40
const DISPLAY_SIZE := 64.0

var pokemon_instance: PokemonInstance
var _attack_timer: float = 0.0
var _attack_flash: float = 0.0
var _current_anim: String = "idle"
var _has_directional: bool = false
var _evolving: bool = false

signal hp_changed(ratio: float)
signal cooldown_changed(ratio: float)
signal xp_changed(ratio: float, level: int)
signal leveled_up(level: int)
signal evolved(name_fr: String)
signal died

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	var cam := Camera2D.new()
	add_child(cam)


func setup(instance: PokemonInstance) -> void:
	pokemon_instance = instance
	_add_placeholder(Color(1.0, 0.55, 0.0))
	PMDSprites.get_walk_sprites(instance.data.id, self, _on_pmd_loaded)


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
	var fw: int = result.frame_size.x
	var s := DISPLAY_SIZE / float(max(fw, 1))
	sprite.scale = Vector2(s, s)
	sprite.play("idle")
	_remove_placeholder()


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
				sprite.scale = Vector2(s, s)
				sprite.play("idle")
				_remove_placeholder()
		http.queue_free()
	)
	http.request(url)


func _remove_placeholder() -> void:
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


func _draw() -> void:
	var fill_alpha := 0.03 + _attack_flash * 0.10
	var ring_alpha := 0.18 + _attack_flash * 0.55
	draw_circle(Vector2.ZERO, ATTACK_RANGE, Color(1.0, 0.9, 0.0, fill_alpha))
	draw_arc(Vector2.ZERO, ATTACK_RANGE, 0.0, TAU, 48, Color(1.0, 0.85, 0.0, ring_alpha), 2.0)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pokemon_instance) or pokemon_instance.is_fainted():
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	_attack_flash = max(0.0, _attack_flash - delta * 4.0)
	cooldown_changed.emit(1.0 - (_attack_timer / ATTACK_COOLDOWN))
	queue_redraw()

	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	).normalized()

	velocity = dir * SPEED
	_update_animation(dir)
	move_and_slide()

	if _attack_timer <= 0.0 and not _evolving:
		if Input.is_action_pressed("ui_accept"):
			_attack()
		else:
			_try_auto_attack()


func _update_animation(dir: Vector2) -> void:
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


func _try_auto_attack() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= ATTACK_RANGE:
			_attack()
			return


func _attack() -> void:
	_attack_flash = 1.0
	_attack_timer = ATTACK_COOLDOWN
	var move_type: String = pokemon_instance.data.types[0] if not pokemon_instance.data.types.is_empty() else "normal"

	var lunge_pos := Vector2.ZERO
	var hit_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= ATTACK_RANGE:
			var dmg := DamageCalculator.calculate(
				pokemon_instance, enemy.pokemon_instance, ATTACK_POWER, move_type
			)
			enemy.take_damage(dmg)
			lunge_pos += enemy.global_position
			hit_count += 1

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
	var tw := create_tween()
	tw.tween_property(sprite, "position", dir * 14.0, 0.07).set_ease(Tween.EASE_OUT)
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
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(0.9, 0.3, 0.3, 0.0), 0.55).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "position", Vector2(0.0, 18.0), 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: died.emit())


# ── Expérience & Évolution ───────────────────────────────────────────

func gain_xp(amount: int) -> void:
	var leveled_up_flag := pokemon_instance.add_xp(amount)
	xp_changed.emit(pokemon_instance.xp_ratio(), pokemon_instance.level)
	if leveled_up_flag:
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

	# Flash de lumière blanche en boucle
	var flash_tween := create_tween().set_loops()
	flash_tween.tween_property(sprite, "modulate", Color(4.0, 4.0, 4.0), 0.12)
	flash_tween.tween_property(sprite, "modulate", Color(0.8, 0.8, 1.0), 0.12)

	# Récupère les données de la nouvelle forme
	PokemonAPI.get_pokemon(new_id, func(api_data: Dictionary) -> void:
		if not is_instance_valid(self):
			return
		if api_data.is_empty():
			flash_tween.kill()
			sprite.modulate = Color.WHITE
			_evolving = false
			return

		var new_data := PokemonData.from_api(api_data)
		pokemon_instance.evolve_to(new_data)
		hp_changed.emit(pokemon_instance.hp_ratio())

		# Charge le nouveau sprite
		PMDSprites.get_walk_sprites(new_id, self, func(result: Dictionary) -> void:
			if not is_instance_valid(self):
				return
			flash_tween.kill()

			_has_directional = false
			if not result.is_empty():
				_has_directional = true
				sprite.sprite_frames = result.frames
				var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
				sprite.scale = Vector2(s, s)
			else:
				_load_fallback_sprite(new_data.sprite_url)

			sprite.modulate = Color.WHITE
			_current_anim = ""
			sprite.play("idle")
			_evolving = false
			evolved.emit(new_data.name_fr)
		)
	)
