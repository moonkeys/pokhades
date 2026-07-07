class_name HubPlayer
extends CharacterBody3D

# Vitesse + dash ALIGNÉS sur le combat (TeamMember) : le Hub et l'arène
# partagent la même base de déplacement. Le dash à charges remplace l'ancien
# sprint maintenu.
const SPEED         := 9.4    # unités/s (cf. TeamMember.SPEED)
const DASH_SPEED    := 26.0
const DASH_TIME     := 0.16
const DASH_RECHARGE := 2.5    # secondes pour regagner une charge
const DASH_MAX      := 1
const FOOT_LIFT     := 0.06

var _sprite:   AnimatedSprite3D = null
var _anim:     String = "idle"
var _has_dirs: bool   = false

# Dash (esquive/burst) — même logique qu'en combat
var _dash_charges:  int     = DASH_MAX
var _dash_recharge: float   = 0.0
var _dash_timer:    float   = 0.0
var _dash_dir:      Vector3 = Vector3.ZERO

## Relief du hub (HubMap) — assigné par HubWorld pour coller le joueur aux
## collines douces. Null = sol plat (comportement d'origine).
var terrain: Node3D = null


func _ready() -> void:
	# Action "dash" (Maj) — enregistrée paresseusement comme en combat, pour
	# que le Hub fonctionne même sans être passé par une arène auparavant.
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev_dash := InputEventKey.new()
		ev_dash.keycode = KEY_SHIFT
		InputMap.action_add_event("dash", ev_dash)

	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.1
	cs.shape    = shape
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)

	_sprite = AnimatedSprite3D.new()
	Billboard3D.setup_sprite(_sprite)
	add_child(_sprite)

	var pid := GameManager.selected_starter_id
	if pid > 0:
		PMDSprites.get_walk_sprites(pid, self, _on_sprites)


func _on_sprites(result: Dictionary) -> void:
	if result.is_empty() or not is_instance_valid(_sprite):
		return
	_sprite.sprite_frames = result.frames
	# Même taille qu'en combat (1,75 u) pour un zoom cohérent entre les modes
	Billboard3D.size_to_width(_sprite, result, Billboard3D.CHAR_WIDTH, FOOT_LIFT)
	_has_dirs = true
	_sprite.play("idle")


func move_tick(delta: float, blocked: bool) -> void:
	# Recharge du dash même à l'arrêt / en dialogue (comme en combat)
	if _dash_charges < DASH_MAX:
		_dash_recharge += delta
		if _dash_recharge >= DASH_RECHARGE:
			_dash_recharge = 0.0
			_dash_charges += 1
	if _dash_timer > 0.0:
		_dash_timer -= delta

	if blocked:
		velocity = Vector3.ZERO
		if is_instance_valid(_sprite) and _sprite.sprite_frames:
			if _sprite.sprite_frames.has_animation("idle") and _sprite.animation != "idle":
				_sprite.play("idle")
		return

	var dir := Vector3(
		Input.get_axis("ui_left", "ui_right"),
		0.0,
		Input.get_axis("ui_up", "ui_down")
	)
	if dir.length() > 1.0:
		dir = dir.normalized()

	# Dash — burst dans la direction courante, consomme une charge (cf. combat)
	if Input.is_action_just_pressed("dash") and _dash_charges > 0 \
			and dir.length() > 0.1 and _dash_timer <= 0.0:
		_dash_charges -= 1
		_dash_timer = DASH_TIME
		_dash_dir   = dir.normalized()
		Sfx.play("dash", -6.0)
		if is_instance_valid(_sprite):
			_sprite.modulate = Color(1.7, 1.7, 2.2)   # flash bleuté pendant l'esquive
			get_tree().create_timer(DASH_TIME + 0.05).timeout.connect(func() -> void:
				if is_instance_valid(_sprite):
					_sprite.modulate = Color.WHITE
			)

	if _dash_timer > 0.0:
		velocity = _dash_dir * DASH_SPEED
	else:
		velocity = dir * SPEED
	move_and_slide()
	position.y = terrain.get_height_at_world(global_position) if is_instance_valid(terrain) else 0.0
	_update_anim(Vector2(dir.x, dir.z))


func _update_anim(dir: Vector2) -> void:
	if not is_instance_valid(_sprite) or not _sprite.sprite_frames:
		return

	var target := Billboard3D.dir_to_anim(dir)
	if not _has_dirs and target != "idle":
		# Fallback avant chargement complet des directions (rarement atteint,
		# les sprites sont en cache disque la plupart du temps).
		target = "walk_down" if dir.y >= 0 else "walk_up"

	if target == _anim:
		return
	_anim = target
	if _sprite.sprite_frames.has_animation(_anim):
		_sprite.play(_anim)
