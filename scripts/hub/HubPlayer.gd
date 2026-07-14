class_name HubPlayer
extends CharacterBody3D

# Vitesse + dash ALIGNÉS sur le combat (TeamMember) : le Hub et l'arène
# partagent la même base de déplacement. Le dash à charges remplace l'ancien
# sprint maintenu.
const SPEED         := 9.4    # unités/s (cf. TeamMember.SPEED)
const DASH_SPEED    := 26.0
const DASH_TIME     := 0.16
const DASH_RECHARGE := 2.5    # secondes pour regagner une charge
const FOOT_LIFT     := 0.06

var _sprite:   AnimatedSprite3D = null
var _anim:     String = "idle"
var _has_dirs: bool   = false

# Dash (esquive/burst) — même logique qu'en combat ; le nombre de charges
# vient des achats du hub (GameManager.dash_charges_bought, 0 au départ).
var _dash_charges:  int     = GameManager.dash_charges_bought
var _dash_known_max: int    = GameManager.dash_charges_bought   # détecte un achat mid-session
var _dash_recharge: float   = 0.0
var _dash_timer:    float   = 0.0
var _dash_dir:      Vector3 = Vector3.ZERO

## Relief du hub (HubMap) — assigné par HubWorld pour coller le joueur aux
## collines douces. Null = sol plat (comportement d'origine).
var terrain: Node3D = null

# ── Multijoueur (hub partagé) ────────────────────────────────────────────
# remote_peer != 0 → cette instance est la copie locale d'un AUTRE joueur
# (cf. TeamMember, même schéma en combat) : pas d'input/collision active,
# on suit juste l'état diffusé par son propriétaire.
const NET_SEND_HZ := 12.0
var remote_peer: int = 0
var _spawn_pid:  int = -1   # pid forcé (avatars distants) ; -1 = déduire
var _net_target: Vector3 = Vector3.ZERO
var _net_anim:   String  = "idle"
var _net_flip:   bool    = false
var _net_accum:  float   = 0.0


## Appelé par HubWorld AVANT add_child() pour transformer cette instance en
## copie d'un joueur distant (cf. HubWorld._build_multiplayer_avatars).
func setup_remote(peer: int, pid: int) -> void:
	remote_peer = peer
	_spawn_pid  = pid
	_net_target = position


func _ready() -> void:
	# Touches : déclarées UNE fois dans Controls.CATALOG, appliquées au
	# démarrage par GameManager (filet de sécurité si on entre par le Hub).
	Controls.apply()

	# Les copies distantes n'ont pas de collision propre (suivent juste la
	# position diffusée par leur propriétaire, cf. _remote_process) — sinon
	# elles bloqueraient physiquement le joueur local.
	if remote_peer == 0:
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

	var pid := _spawn_pid
	if pid <= 0:
		pid = GameManager.selected_starter_id
		if Net.active and Net.players.has(Net.local_id()):
			pid = int(Net.players[Net.local_id()]["pid"])
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


## Copie distante : suit juste la dernière position/anim diffusée par son
## propriétaire (même schéma que TeamMember._remote_process en combat).
func _remote_process(delta: float) -> void:
	var to := _net_target - global_position
	global_position = global_position.lerp(_net_target, minf(1.0, delta * 12.0))
	if is_instance_valid(_sprite) and _sprite.sprite_frames:
		var anim := _net_anim if to.length() > 0.06 else "idle"
		if anim != _anim and _sprite.sprite_frames.has_animation(anim):
			_anim = anim
			_sprite.play(_anim)
		if not _has_dirs:
			_sprite.flip_h = _net_flip


## État de mouvement diffusé par le propriétaire — appliqué sur ses copies.
@rpc("any_peer", "call_remote", "unreliable")
func _net_state(pos: Vector3, anim: String, flip: bool) -> void:
	_net_target = pos
	_net_anim   = anim
	_net_flip   = flip


func move_tick(delta: float, blocked: bool) -> void:
	if remote_peer != 0:
		_remote_process(delta)
		return

	# Un achat (ou MODE TEST) débloque une charge INSTANTANÉMENT — sinon
	# _dash_charges ne rattrape le nouveau max qu'au fil de la recharge
	# lente (2.5s/charge), donnant l'impression fausse de n'avoir qu'1 dash
	# juste après avoir tout débloqué.
	if GameManager.dash_charges_bought > _dash_known_max:
		_dash_charges += GameManager.dash_charges_bought - _dash_known_max
		_dash_known_max = GameManager.dash_charges_bought

	# Recharge du dash même à l'arrêt / en dialogue (comme en combat)
	if _dash_charges < GameManager.dash_charges_bought:
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

	# Diffusion de notre position aux autres joueurs (hub multijoueur partagé)
	if Net.active:
		_net_accum += delta
		if _net_accum >= 1.0 / NET_SEND_HZ:
			_net_accum = 0.0
			_net_state.rpc(global_position, _anim, _sprite.flip_h if is_instance_valid(_sprite) else false)


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
