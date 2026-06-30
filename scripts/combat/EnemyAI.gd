extends CharacterBody2D

const SPEED           := 55.0
const ATTACK_RANGE    := 45.0
const ATTACK_COOLDOWN := 1.8
const DISPLAY_SIZE    := 28.0

var pokemon_instance: PokemonInstance
var _attack_timer: float = 0.0
var _current_anim: String = "idle"
var _hp_bar: ProgressBar = null

signal died(xp_reward: int)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemies")
	_create_hp_bar()


func _create_hp_bar() -> void:
	var container := Node2D.new()
	container.position = Vector2(0, -44)
	add_child(container)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.size = Vector2(48, 5)
	_hp_bar.position = Vector2(-24, 0)
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.25, 0.25, 0.25)
	bg.set_corner_radius_all(2)
	_hp_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.15, 0.15)
	fill.set_corner_radius_all(2)
	_hp_bar.add_theme_stylebox_override("fill", fill)

	container.add_child(_hp_bar)


func _billboard_tf(s: float) -> Transform2D:
	return Transform2D(Vector2(s, 0), Vector2(0, s), Vector2.ZERO)


func setup(instance: PokemonInstance) -> void:
	pokemon_instance = instance
	_add_placeholder(Color(0.85, 0.1, 0.1))
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
	sprite.sprite_frames = result.frames
	var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
	sprite.transform = _billboard_tf(s)
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
				sprite.transform = _billboard_tf(s)
				sprite.play("idle")
				_remove_placeholder()
		http.queue_free()
	)
	http.request(url)


func _remove_placeholder() -> void:
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(pokemon_instance) or pokemon_instance.is_fainted():
		return

	_attack_timer = max(0.0, _attack_timer - delta)

	var target := _find_target()
	if not is_instance_valid(target):
		return

	var dist := global_position.distance_to(target.global_position)

	if dist > ATTACK_RANGE:
		var dir := (target.global_position - global_position).normalized()
		velocity = dir * SPEED
		_update_anim(velocity)
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		_update_anim(Vector2.ZERO)
		if _attack_timer <= 0.0:
			_do_attack(target)


func _get_attack_type() -> String:
	return pokemon_instance.get_attack_type()


# Cible le joueur dont ce Pokémon est super efficace — sinon le plus proche.
# Score = multiplicateur × 700 − distance  (SE = +700 px de préférence max)
func _find_target() -> CharacterBody2D:
	var attack_type := _get_attack_type()
	var best: CharacterBody2D = null
	var best_score := -INF

	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		if p.pokemon_instance == null or p.pokemon_instance.is_fainted():
			continue
		var mult := DamageCalculator.type_multiplier(attack_type, p.pokemon_instance.data.types)
		if mult <= 0.0:
			continue   # immunité — ne pas cibler
		var dist := global_position.distance_to(p.global_position)
		var score := mult * 700.0 - dist
		if score > best_score:
			best_score = score
			best = p

	# Fallback si tous les joueurs sont immunisés
	if best == null:
		var min_d := INF
		for p in get_tree().get_nodes_in_group("players"):
			if not is_instance_valid(p): continue
			if p.pokemon_instance == null or p.pokemon_instance.is_fainted(): continue
			var d := global_position.distance_to(p.global_position)
			if d < min_d:
				min_d = d
				best = p

	return best


func _update_anim(vel: Vector2) -> void:
	if not sprite.sprite_frames:
		return
	var anim: String
	if vel.length() < 10:
		anim = "idle"
	else:
		var sector := int(round(fposmod(vel.angle(), TAU) / (TAU / 8.0))) % 8
		match sector:
			0: anim = "walk_right"
			1: anim = "walk_downright"
			2: anim = "walk_down"
			3: anim = "walk_downleft"
			4: anim = "walk_left"
			5: anim = "walk_upleft"
			6: anim = "walk_up"
			_: anim = "walk_upright"

	if anim != _current_anim:
		_current_anim = anim
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


func _do_attack(target: CharacterBody2D) -> void:
	_attack_timer = ATTACK_COOLDOWN
	var move_type  := pokemon_instance.get_attack_type()
	var move_power := pokemon_instance.get_attack_power()
	var dmg := DamageCalculator.calculate(pokemon_instance, target.pokemon_instance, move_power, move_type)
	target.take_damage(dmg)
	_play_attack_lunge(target.global_position)


func _play_attack_lunge(target_pos: Vector2) -> void:
	var dir := (target_pos - global_position).normalized()
	var tw := create_tween()
	tw.tween_property(sprite, "position", dir * 10.0, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.14).set_ease(Tween.EASE_IN)
	sprite.modulate = Color(2.2, 2.2, 2.2)
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color.WHITE
	)


func take_damage(amount: int) -> void:
	pokemon_instance.take_damage(amount)
	if _hp_bar:
		_hp_bar.value = pokemon_instance.hp_ratio()
	sprite.modulate = Color(2.0, 0.3, 0.3)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(self):
			sprite.modulate = Color.WHITE
	)
	if pokemon_instance.is_fainted():
		_play_death_anim()


func _play_death_anim() -> void:
	set_physics_process(false)
	remove_from_group("enemies")
	if _hp_bar:
		_hp_bar.visible = false
	var xp_reward := pokemon_instance.level * GameManager.XP_MULTIPLIER
	# Chute : glisse vers le bas + fondu rouge
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(1.0, 0.2, 0.2, 0.0), 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "position", Vector2(0.0, 22.0), 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		died.emit(xp_reward)
		queue_free()
	)
