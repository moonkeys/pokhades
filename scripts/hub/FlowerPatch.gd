class_name FlowerPatch
extends Node3D

## Petit champ de fleurs groupées avec balancement animé (vent) — même
## principe que SunflowerField.gd, généralisé à n'importe quelle liste de
## sprites de fleurs (plusieurs couleurs mélangées dans un même champ).

const SPRITES_DIR := "res://assets/nature/sprites/"

var _t: float = 0.0
var _flowers: Array = []


func setup(files: Array[String], count: int, width: float, spread: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var file: String = files[rng.randi() % files.size()]
		var offset := Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		_spawn_flower(file, width, offset, rng.randf() * TAU)


func _spawn_flower(file: String, width: float, local_pos: Vector3, phase: float) -> void:
	var root := Node3D.new()
	root.position = local_pos
	root.set_meta("phase", phase)
	add_child(root)
	_flowers.append(root)

	var spr := Billboard3D.make_sprite_from_file_sized(SPRITES_DIR + file, width)
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spr)


func _process(delta: float) -> void:
	_t += delta
	for f: Node3D in _flowers:
		if not is_instance_valid(f):
			continue
		var phase: float = f.get_meta("phase", 0.0)
		f.rotation.z = sin(_t * 1.6 + phase) * 0.08
