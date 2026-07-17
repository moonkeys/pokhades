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
var _tint:    Color = Color.WHITE
var _map:     Node  = null


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
## `ball` : rend une VRAIE pokéball qui tournoie (sprite Essentials) au lieu de
## l'orbe lumineuse — pour les lancers des dresseurs de village.
static func launch_point(parent: Node, from: Vector3, point: Vector3, tint: Color,
		on_hit: Callable, speed: float = 14.0, ball: bool = false) -> void:
	if not is_instance_valid(parent):
		return
	var p := Projectile.new()
	p._use_point  = true
	p._target_pos = point + Vector3(0, 0.8, 0)
	p._on_hit = on_hit
	p._speed  = speed
	p._ball   = ball
	p.position = from + Vector3(0, 0.9, 0)
	p._build(tint)
	parent.add_child(p)


var _ball: bool = false


func _build(tint: Color) -> void:
	_tint = tint   # retenu pour l'impact sur un tronc (cf. _process)
	if _ball:
		_build_pokeball()
		return
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


## VRAIE pokéball (planche Essentials, 8 frames) qui tournoie en vol — au lieu
## d'un simple point rouge (retour joueurs).
func _build_pokeball() -> void:
	var s := Sprite3D.new()
	s.texture        = load(PokeballFX.TEX_BALL)
	s.hframes        = 8
	s.frame          = 0
	s.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size     = 0.030
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.no_depth_test  = true
	s.shaded         = false
	add_child(s)
	# Rotation continue du strip (la ball tournoie pendant tout le vol)
	var tw := s.create_tween().set_loops()
	tw.tween_method(func(f: float) -> void:
		if is_instance_valid(s):
			s.frame = int(f) % 8
	, 0.0, 8.0, 0.4)


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("combat_map")


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME or (not _use_point and not is_instance_valid(_target)):
		queue_free()
		return
	# Couvert (biome Forêt) : un tronc traversé ABSORBE le tir — `on_hit` n'est
	# pas appelé, le coup est perdu. Testé sur la position courante plutôt qu'en
	# raycast : le pas de déplacement (≈ 0.23 u à vitesse 14 en 60 fps) est bien
	# plus fin qu'une case, donc aucun tronc ne peut être enjambé.
	if is_instance_valid(_map) and _map.has_method("blocks_projectile") \
			and _map.blocks_projectile(global_position):
		CombatVFX.spawn_impact(get_parent(), global_position, _tint)
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
