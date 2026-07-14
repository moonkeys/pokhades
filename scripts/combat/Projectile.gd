class_name Projectile
extends Node3D

## Projectile d'attaque À DISTANCE (attaques spéciales — cf. TeamMember /
## EnemyAI) : orbe lumineuse teintée par le type qui file vers sa cible
## (légèrement autoguidée) et déclenche `on_hit` à l'impact. Autonome :
## se détruit à l'impact, si la cible disparaît, ou après LIFETIME.

const LIFETIME  := 3.0
const HIT_DIST  := 0.55

var _target:  Node3D
var _target_pos: Vector3 = Vector3.ZERO
var _use_point:  bool    = false   # vise un POINT fixe (esquivable) au lieu d'une cible vivante
var _on_hit:  Callable
var _speed:   float = 14.0
var _age:     float = 0.0


## Lance un projectile de `from` vers `target` ; `on_hit` est appelé à
## l'impact (le lanceur y met dégâts + VFX — le projectile ne connaît rien
## au combat).
static func launch(parent: Node, from: Vector3, target: Node3D, tint: Color,
		on_hit: Callable, speed: float = 14.0) -> void:
	if not is_instance_valid(parent) or not is_instance_valid(target):
		return
	var p := Projectile.new()
	p._target = target
	p._on_hit = on_hit
	p._speed  = speed
	p.position = from + Vector3(0, 0.9, 0)
	p._build(tint)
	parent.add_child(p)


## Variante ESQUIVABLE : vise un POINT fixe (ex : position du joueur au moment
## du lancer) et non la cible vivante — s'écarter permet de l'éviter. Le
## `on_hit` (à l'arrivée sur le point) décide de l'effet (capture si le joueur
## est encore là, sinon coup dans le vide).
static func launch_point(parent: Node, from: Vector3, point: Vector3, tint: Color,
		on_hit: Callable, speed: float = 14.0) -> void:
	if not is_instance_valid(parent):
		return
	var p := Projectile.new()
	p._use_point  = true
	p._target_pos = point + Vector3(0, 0.8, 0)
	p._on_hit = on_hit
	p._speed  = speed
	p.position = from + Vector3(0, 0.9, 0)
	p._build(tint)
	parent.add_child(p)


func _build(tint: Color) -> void:
	# Orbe : deux disques doux superposés (cœur clair + halo teinté)
	var halo := Sprite3D.new()
	halo.texture    = CombatVFX._get_soft_texture()
	halo.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded     = false
	halo.modulate   = tint
	halo.pixel_size = 0.011
	add_child(halo)
	var core := Sprite3D.new()
	core.texture    = CombatVFX._get_soft_texture()
	core.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	core.shaded     = false
	core.modulate   = Color(1.0, 1.0, 0.95)
	core.pixel_size = 0.005
	core.position.z = 0.01
	add_child(core)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME or (not _use_point and not is_instance_valid(_target)):
		queue_free()
		return
	var goal: Vector3 = _target_pos if _use_point else _target.global_position + Vector3(0, 0.8, 0)
	var to := goal - global_position
	if to.length() <= maxf(HIT_DIST, _speed * delta):
		if _on_hit.is_valid():
			_on_hit.call()
		queue_free()
		return
	global_position += to.normalized() * _speed * delta
