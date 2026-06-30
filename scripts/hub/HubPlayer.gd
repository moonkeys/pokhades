class_name HubPlayer
extends CharacterBody2D

const SPEED        := 130.0
const DISPLAY_SIZE := 32.0

var _sprite:    AnimatedSprite2D = null
var _anim:      String = "idle"
var _has_dirs:  bool   = false


func _ready() -> void:
	# Hitbox joueur
	collision_layer = 2
	collision_mask  = 1   # collide avec les murs (layer 1 = static world)
	var cs := CollisionShape2D.new()
	var sh := CapsuleShape2D.new()
	sh.radius = 8.0
	sh.height = 18.0
	cs.position = Vector2(0, 4)
	cs.shape    = sh
	add_child(cs)

	# Ombre
	var shadow := ColorRect.new()
	shadow.name     = "Shadow"
	shadow.size     = Vector2(32, 12)
	shadow.position = Vector2(-16, 6)
	shadow.color    = Color(0, 0, 0, 0.22)
	add_child(shadow)

	_sprite = AnimatedSprite2D.new()
	add_child(_sprite)

	# Placeholder
	var ph := ColorRect.new()
	ph.name     = "Placeholder"
	ph.size     = Vector2(32, 40)
	ph.position = Vector2(-16, -36)
	ph.color    = Color(1.0, 0.55, 0.0)
	add_child(ph)

	var pid := GameManager.selected_starter_id
	if pid > 0:
		PMDSprites.get_walk_sprites(pid, self, _on_sprites)


func _on_sprites(result: Dictionary) -> void:
	if result.is_empty():
		return
	_sprite.sprite_frames = result.frames
	var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
	_sprite.scale = Vector2(s, s)
	_has_dirs = true
	_sprite.play("idle")
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()


func move_tick(delta: float, blocked: bool) -> void:
	if blocked:
		velocity = Vector2.ZERO
		if is_instance_valid(_sprite) and _sprite.sprite_frames:
			if _sprite.sprite_frames.has_animation("idle") and _sprite.animation != "idle":
				_sprite.play("idle")
		return

	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up",   "ui_down")
	).normalized()

	velocity = dir * SPEED
	move_and_slide()
	_update_anim(dir)


func _update_anim(dir: Vector2) -> void:
	if not is_instance_valid(_sprite) or not _sprite.sprite_frames:
		return

	var target: String
	if dir.length() < 0.05:
		target = "idle"
	elif not _has_dirs:
		target = "walk_down" if dir.y >= 0 else "walk_up"
		if is_instance_valid(_sprite):
			_sprite.flip_h = dir.x < 0
	else:
		var sector := int(round(fposmod(dir.angle(), TAU) / (TAU / 8.0))) % 8
		match sector:
			0: target = "walk_right"
			1: target = "walk_downright"
			2: target = "walk_down"
			3: target = "walk_downleft"
			4: target = "walk_left"
			5: target = "walk_upleft"
			6: target = "walk_up"
			_: target = "walk_upright"

	if target == _anim:
		return
	_anim = target
	if _sprite.sprite_frames.has_animation(_anim):
		_sprite.play(_anim)
