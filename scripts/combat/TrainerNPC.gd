class_name TrainerNPC
extends Node3D

## Dresseur visible dans l'arène pendant un combat de boss (planche
## Characters/trainer_*.png, cf. PokePools.CHAMPION_SPRITE) — DÉAMBULE en
## retrait autour de son point d'arrivée pendant le combat (il vit, il ne
## reste pas figé), puis s'enfuit en courant vers la sortie une fois tous
## ses Pokémon vaincus (flee_to()).

const WIDTH := 1.6
const WALK_SPEED   := 6.5   # unités/s — allure de fuite
const WANDER_SPEED := 2.2   # allure de déambulation pendant le combat
const WANDER_RADIUS := 3.5  # rayon de patrouille autour du point d'ancrage

var _sprite: AnimatedSprite3D = null
var _fleeing: bool = false

var _anchor:        Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _walking:       bool    = false
var _wander_wait:   float   = 1.2


func setup(sprite_path: String) -> void:
	_anchor = global_position
	_sprite = AnimatedSprite3D.new()
	Billboard3D.setup_sprite(_sprite)
	add_child(_sprite)
	add_child(Billboard3D.make_blob_shadow(Vector2(1.1, 0.6)))

	var result := Billboard3D.make_trainer_frames(sprite_path)
	if result.is_empty():
		return
	_sprite.sprite_frames = result["frames"]
	Billboard3D.size_to_width(_sprite, result, WIDTH)
	_sprite.play("idle")


func _process(delta: float) -> void:
	if _fleeing or _sprite == null or _sprite.sprite_frames == null:
		return
	if _walking:
		var to := _wander_target - global_position
		to.y = 0.0
		if to.length() < 0.15:
			_walking = false
			_wander_wait = randf_range(1.2, 3.0)
			if _sprite.sprite_frames.has_animation("idle"):
				_sprite.play("idle")
			return
		global_position += to.normalized() * WANDER_SPEED * delta
	else:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			var ang := randf_range(0.0, TAU)
			_wander_target = _anchor + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.0, WANDER_RADIUS)
			var dir := _wander_target - global_position
			var anim := Billboard3D.dir_to_anim(Vector2(dir.x, dir.z))
			if _sprite.sprite_frames.has_animation(anim):
				_sprite.play(anim)
			_walking = true


## Anime la fuite en ligne droite vers `target_pos` (généralement une sortie
## de la salle), puis se libère une fois arrivé — le combat continue
## normalement pendant ce temps, ce n'est qu'un habillage visuel.
func flee_to(target_pos: Vector3) -> void:
	if _fleeing or _sprite == null:
		return
	_fleeing = true
	_walking = false
	var dir := (target_pos - global_position)
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	var anim := Billboard3D.dir_to_anim(Vector2(dir.x, dir.z))
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
	else:
		_sprite.play("walk_up")

	var dist := global_position.distance_to(target_pos)
	var dur := maxf(0.3, dist / WALK_SPEED)
	var tw := create_tween()
	tw.tween_property(self, "global_position", target_pos, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
