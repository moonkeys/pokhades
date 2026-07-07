class_name GoldOrb
extends Node3D

## Orbe d'or lâché à la mort d'un ennemi — s'éparpille brièvement puis file
## vers le membre d'équipe le plus proche et disparaît. PUREMENT VISUEL :
## l'or est toujours crédité en fin de salle (cf. CombatArena._on_room_cleared),
## l'orbe donne juste le ressenti "je récolte" façon Hades.

const HOME_DELAY   := 0.35   # temps d'éparpillement avant de filer au joueur
const ACCEL        := 26.0
const MAX_SPEED    := 16.0
const PICKUP_DIST  := 0.6
const LIFETIME_MAX := 3.0    # filet de sécurité (aucun joueur valide)

var _velocity: Vector3
var _age: float = 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 8
	sphere.rings = 4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color     = Color(1.0, 0.84, 0.25)
	mat.emission_enabled = true
	mat.emission          = Color(1.0, 0.72, 0.15)
	mat.emission_energy_multiplier = 1.2
	mat.metallic  = 0.4
	mat.roughness = 0.3
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Impulsion d'éparpillement initiale
	var ang := randf() * TAU
	_velocity = Vector3(cos(ang) * 2.2, randf_range(2.0, 3.4), sin(ang) * 2.2)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME_MAX:
		queue_free()
		return

	if _age < HOME_DELAY:
		# Phase d'éparpillement : petite parabole
		_velocity.y -= 9.0 * delta
		position += _velocity * delta
		position.y = maxf(position.y, 0.15)
		return

	var target := _nearest_player()
	if target == null:
		queue_free()
		return
	var goal: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var to_goal := goal - global_position
	if to_goal.length() < PICKUP_DIST:
		Sfx.play("coin", -10.0, 0.18)   # beaucoup d'orbes → discret, pitch très varié
		queue_free()
		return
	_velocity = _velocity.move_toward(to_goal.normalized() * MAX_SPEED, ACCEL * delta)
	position += _velocity * delta


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p):
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
