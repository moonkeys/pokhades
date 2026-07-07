class_name HubNPC
extends Node3D

const FOOT_LIFT := 0.06

var npc_id:     String = ""
var npc_name:   String = ""   # rempli async par l'API (nom FR du Pokémon)
var pokemon_id: int    = 1
var accent:     Color  = Color(0.76, 0.53, 0.17)

var _sprite:     AnimatedSprite3D = null
var _name_label: Label3D          = null
var _exclaim:    Label3D          = null
var _in_range:   bool             = false
var _anim_t:     float            = 0.0

## Relief du hub (HubMap) — assigné par HubWorld ; les PNJ (fixes comme
## déambulants) restent collés aux collines douces. Null = sol plat.
var terrain: Node3D = null

# ── Déambulation (plan X/Z) ──────────────────────────────────────────────
var _should_wander: bool    = false
var _wander_center: Vector3
var _wander_radius: float   = 3.0
var _wander_speed:  float   = 1.1
var _wander_target: Vector3
var _wander_timer:  float   = 0.0
var _wander_pause:  bool    = true


func setup(p_id: String, p_pid: int, p_accent: Color) -> void:
	npc_id     = p_id
	pokemon_id = p_pid
	accent     = p_accent
	_build()
	PMDSprites.get_walk_sprites(p_pid, self, _on_sprites)


func start_wandering(center: Vector3, radius: float = 3.0, speed: float = 1.1) -> void:
	_should_wander = true
	_wander_center = center
	_wander_radius = radius
	_wander_speed  = speed
	_wander_target = center
	_wander_timer  = randf_range(0.5, 2.0)
	_wander_pause  = true


func _pick_wander_target() -> void:
	var angle := randf() * TAU
	var dist  := randf_range(0.5, _wander_radius)
	_wander_target = _wander_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_wander_timer  = randf_range(2.5, 5.5)
	_wander_pause  = false


func _build() -> void:
	_sprite = AnimatedSprite3D.new()
	Billboard3D.setup_sprite(_sprite)
	add_child(_sprite)

	_name_label = Label3D.new()
	_name_label.text        = ""
	_name_label.position    = Vector3(0, 1.55, 0)
	_name_label.font_size   = 44
	_name_label.pixel_size  = 0.006
	_name_label.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.modulate    = Color(0.94, 0.88, 0.72)
	_name_label.outline_size = 10
	_name_label.outline_modulate = Color(0, 0, 0, 0.75)
	_name_label.no_depth_test = true
	add_child(_name_label)

	_exclaim = Label3D.new()
	_exclaim.text        = "!"
	_exclaim.visible     = false
	_exclaim.position    = Vector3(0, 1.75, 0)
	_exclaim.font_size   = 56
	_exclaim.pixel_size  = 0.006
	_exclaim.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	_exclaim.modulate    = Color(1.0, 0.92, 0.10)
	_exclaim.outline_size = 10
	_exclaim.outline_modulate = Color(0, 0, 0, 0.7)
	_exclaim.no_depth_test = true
	add_child(_exclaim)


func _on_sprites(result: Dictionary) -> void:
	if result.is_empty() or not is_instance_valid(_sprite):
		return
	_sprite.sprite_frames = result.frames
	# Même taille qu'en combat (1,75 u) — cohérence de zoom Hub/Combat
	Billboard3D.size_to_width(_sprite, result, Billboard3D.CHAR_WIDTH, FOOT_LIFT)
	_sprite.play("idle")

	# Récupère le nom français du Pokémon depuis l'API
	PokemonAPI.get_pokemon(pokemon_id, func(data: Dictionary) -> void:
		if data.is_empty():
			return
		var fr: String = data.get("name_fr", "")
		if not fr.is_empty():
			npc_name = fr.capitalize()
			if is_instance_valid(_name_label):
				_name_label.text = npc_name
	)


func _process(delta: float) -> void:
	if _should_wander:
		_wander_timer -= delta
		if _wander_pause:
			if _wander_timer <= 0.0:
				_pick_wander_target()
		else:
			position = position.move_toward(_wander_target, _wander_speed * delta)
			if position.distance_to(_wander_target) < 0.15 or _wander_timer <= 0.0:
				_wander_pause = true
				_wander_timer = randf_range(1.0, 3.0)

	# Colle au relief (fixes comme déambulants) — les cibles de déambulation
	# sont en y=0, on réajuste après le déplacement.
	if is_instance_valid(terrain):
		position.y = terrain.get_height_at_world(position)

	if not _in_range or not is_instance_valid(_exclaim):
		return
	_anim_t += delta * 3.0
	_exclaim.position.y = 1.75 + sin(_anim_t) * 0.08


func set_in_range(v: bool) -> void:
	if v == _in_range:
		return
	_in_range = v
	if is_instance_valid(_exclaim):
		_exclaim.visible = v
