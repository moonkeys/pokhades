class_name SunflowerField
extends Node3D

## Champ de tournesols — vrais meshes 3D du kit nature (fleurs jaunes, même
## famille d'assets que KitProps.FLOWERS_YELLOW), avec un léger balancement
## animé.

const WIDTH := 1.1
const SPREAD := 1.4
const NATIVE_H := 0.30   # hauteur native approx. des fleurs du kit

var _t: float = 0.0
var _flowers: Array = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 3:
		var file: String = KitProps.FLOWERS_YELLOW[rng.randi() % KitProps.FLOWERS_YELLOW.size()]
		var offset := Vector3(rng.randf_range(-SPREAD, SPREAD), 0, rng.randf_range(-SPREAD, SPREAD))
		_spawn_flower(file, offset, rng.randf() * TAU)


func _spawn_flower(file: String, local_pos: Vector3, phase: float) -> void:
	var root := Node3D.new()
	root.position = local_pos
	root.set_meta("phase", phase)
	add_child(root)
	_flowers.append(root)

	var flower := KitProps.instance(file)
	flower.scale = Vector3.ONE * (WIDTH / NATIVE_H)
	root.add_child(flower)


func _process(delta: float) -> void:
	_t += delta
	for f: Node3D in _flowers:
		if not is_instance_valid(f):
			continue
		var phase: float = f.get_meta("phase", 0.0)
		f.rotation.z = sin(_t * 1.4 + phase) * 0.06
