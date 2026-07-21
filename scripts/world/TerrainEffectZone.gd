class_name TerrainEffectZone
extends Area3D

## Zone d'effet de terrain générique (boue, ralentissement, futurs effets) —
## découplée de tout controller précis : elle ne connaît ni HubPlayer, ni
## le joueur d'exploration/combat. Toute cible doit rejoindre le groupe
## `trigger_group` et implémenter `_on_terrain_effect_entered`/`_exited`
## (duck typing) pour réagir. Pensée pour être posée telle quelle dans le
## Hub, une map d'exploration ou une arène de combat.

signal effect_entered(body: Node3D)
signal effect_exited(body: Node3D)

## 1.0 = vitesse normale, 0.55 = boue (ralentit de ~45%), etc.
@export var speed_multiplier: float = 0.55
@export var trigger_group: String = "terrain_effect_targets"


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(trigger_group):
		return
	effect_entered.emit(body)
	if body.has_method("_on_terrain_effect_entered"):
		body._on_terrain_effect_entered(self)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(trigger_group):
		return
	effect_exited.emit(body)
	if body.has_method("_on_terrain_effect_exited"):
		body._on_terrain_effect_exited(self)
