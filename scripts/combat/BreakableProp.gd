class_name BreakableProp
extends Node3D

## Décor billboard destructible (souches, rondins, champignons géants…) —
## purement cosmétique : le casser ne rapporte rien, mais les attaques le
## secouent puis le font disparaître (poof), et sa collision est libérée.
## Créé par MapRender3D._add_prop_sprite ; groupe "breakables", ciblé par
## TeamMember._attack au même titre que les arbres à baies.

const HP := 2

var _hp: int = HP
var _broken: bool = false
var _sprite: Node3D = null    # le billboard à secouer
var _map: Node = null         # MapGenerator — pour libérer tuiles + collision
var _cells: Array = []        # cases occupées par le prop


func setup(sprite: Node3D, map: Node, cells: Array) -> void:
	_sprite = sprite
	_map    = map
	_cells  = cells
	add_to_group("breakables")


## Reçoit un coup : secousse latérale ; au HP épuisé, disparaît.
func take_hit(_attacker_pos: Vector3) -> void:
	if _broken:
		return
	_hp -= 1
	if is_instance_valid(_sprite):
		var bx := _sprite.position.x
		var tw := create_tween()
		tw.tween_property(_sprite, "position:x", bx + 0.09, 0.05)
		tw.tween_property(_sprite, "position:x", bx - 0.06, 0.06)
		tw.tween_property(_sprite, "position:x", bx, 0.06)
	Sfx.play("hit", -10.0, 0.25)
	if _hp <= 0:
		_break()


func _break() -> void:
	_broken = true
	remove_from_group("breakables")
	var parent := get_parent()
	if is_instance_valid(parent):
		CombatVFX.spawn_death_poof(parent, global_position + Vector3(0, 0.4, 0),
			Color(0.78, 0.68, 0.52))
	Sfx.play("death", -10.0)
	# Libère les tuiles + collisions des cases occupées (le prop billboard
	# lui-même est enfant de ce nœud, détruit avec).
	if is_instance_valid(_map):
		for c: Vector2i in _cells:
			if _map.get("_objects") != null:
				_map._objects.erase_cell(c)
			if _map.has_method("_clear_cell_collision"):
				_map._clear_cell_collision(c)
	queue_free()
