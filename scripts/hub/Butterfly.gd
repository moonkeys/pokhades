class_name Butterfly
extends Node3D

## Papillon low-poly — deux ailes en quads qui battent, voltige autour d'un
## point d'ancrage (vie ambiante du Hub, spawné au runtime par HubWorld).

const COLORS: Array[Color] = [
	Color(0.98, 0.92, 0.98),   # blanc rosé
	Color(1.0, 0.85, 0.35),    # jaune
	Color(0.95, 0.55, 0.70),   # rose
	Color(0.60, 0.75, 0.98),   # bleu clair
]

var anchor: Vector3 = Vector3.ZERO
## Source du relief — tout nœud exposant get_height_at_world() : HubMap
## (Node3D) au Hub, MapGenerator (Node2D, données) en combat. Duck-typé.
var terrain: Node = null

var _wing_l: MeshInstance3D = null
var _wing_r: MeshInstance3D = null
var _t: float = 0.0
var _target: Vector3
var _retarget_timer: float = 0.0


func _ready() -> void:
	var col: Color = COLORS[randi() % COLORS.size()]
	_wing_l = _make_wing(col, -1.0)
	_wing_r = _make_wing(col, 1.0)
	add_child(_wing_l)
	add_child(_wing_r)
	_t = randf() * TAU
	_target = anchor
	position = anchor + Vector3(randf_range(-1, 1), randf_range(0.4, 1.0), randf_range(-1, 1))


func _make_wing(col: Color, side: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.12)
	mi.mesh = quad
	mi.position = Vector3(side * 0.075, 0, 0)
	# Aile à plat (quad horizontal) — pivotera autour de l'axe Z pour battre
	mi.rotation_degrees = Vector3(-90, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _process(delta: float) -> void:
	_t += delta

	# Battement d'ailes (rapide) + bob vertical (lent)
	var flap := sin(_t * 18.0) * 0.9
	if is_instance_valid(_wing_l):
		_wing_l.rotation.z = flap
		_wing_r.rotation.z = -flap

	# Voltige : cap vers une cible proche de l'ancre, re-tirée régulièrement
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or position.distance_to(_target) < 0.2:
		var ground: float = terrain.get_height_at_world(anchor) if is_instance_valid(terrain) else 0.0
		_target = anchor + Vector3(
			randf_range(-2.2, 2.2),
			ground + randf_range(0.5, 1.4),
			randf_range(-2.2, 2.2)
		)
		_retarget_timer = randf_range(1.5, 3.5)
	position = position.move_toward(_target, 0.9 * delta)
	position.y += sin(_t * 3.0) * 0.15 * delta

	# Oriente le corps vers la direction de vol
	var dir := _target - position
	dir.y = 0.0
	if dir.length() > 0.05:
		rotation.y = atan2(dir.x, dir.z)
