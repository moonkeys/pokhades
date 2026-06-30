class_name HubNPC
extends Node2D

const DISPLAY_SIZE := 28.0

var npc_id:     String = ""
var npc_name:   String = ""   # rempli async par l'API (nom FR du Pokémon)
var pokemon_id: int    = 1
var accent:     Color  = Color(0.76, 0.53, 0.17)

var _sprite:     AnimatedSprite2D = null
var _name_label: Label            = null
var _in_range:   bool             = false
var _exclaim:    Label            = null
var _anim_t:     float            = 0.0

# ── Déambulation ──────────────────────────────────────────────────────
var _should_wander: bool    = false
var _wander_center: Vector2
var _wander_radius: float   = 48.0
var _wander_speed:  float   = 18.0
var _wander_target: Vector2
var _wander_timer:  float   = 0.0
var _wander_pause:  bool    = true


func setup(p_id: String, p_pid: int, p_accent: Color) -> void:
	npc_id     = p_id
	pokemon_id = p_pid
	accent     = p_accent
	_build()
	PMDSprites.get_walk_sprites(p_pid, self, _on_sprites)


func start_wandering(center: Vector2, radius: float = 48.0, speed: float = 18.0) -> void:
	_should_wander = true
	_wander_center = center
	_wander_radius = radius
	_wander_speed  = speed
	_wander_target = center
	_wander_timer  = randf_range(0.5, 2.0)
	_wander_pause  = true


func _pick_wander_target() -> void:
	var angle := randf() * TAU
	var dist  := randf_range(8.0, _wander_radius)
	_wander_target = _wander_center + Vector2(cos(angle) * dist, sin(angle) * dist * 0.55)
	_wander_timer  = randf_range(2.5, 5.5)
	_wander_pause  = false


func _build() -> void:
	var ph := ColorRect.new()
	ph.name     = "Placeholder"
	ph.size     = Vector2(20, 20)
	ph.position = Vector2(-10, -20)
	ph.color    = accent.lightened(0.30) if accent.a > 0.0 else Color(0.60, 0.55, 0.45)
	add_child(ph)

	_sprite = AnimatedSprite2D.new()
	_sprite.position = Vector2(0, -10)
	add_child(_sprite)

	_name_label = Label.new()
	_name_label.text     = ""
	_name_label.position = Vector2(-40, -44)
	_name_label.size     = Vector2(80, 16)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.72))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.70))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)

	_exclaim = Label.new()
	_exclaim.text     = "!"
	_exclaim.visible  = false
	_exclaim.position = Vector2(-6, -62)
	_exclaim.size     = Vector2(14, 20)
	_exclaim.add_theme_font_size_override("font_size", 16)
	_exclaim.add_theme_color_override("font_color", Color(1.0, 0.92, 0.10))
	_exclaim.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	_exclaim.add_theme_constant_override("shadow_offset_x", 1)
	_exclaim.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_exclaim)


func _on_sprites(result: Dictionary) -> void:
	if result.is_empty():
		return
	_sprite.sprite_frames = result.frames
	var s := DISPLAY_SIZE / float(max(result.frame_size.x, 1))
	_sprite.scale = Vector2(s, s)
	_sprite.play("idle")
	var ph := get_node_or_null("Placeholder")
	if ph:
		ph.queue_free()

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
			z_index  = int(position.y)
			if position.distance_to(_wander_target) < 3.0 or _wander_timer <= 0.0:
				_wander_pause = true
				_wander_timer = randf_range(1.0, 3.0)

	if not _in_range or not is_instance_valid(_exclaim):
		return
	_anim_t += delta * 3.0
	_exclaim.position.y = -62.0 + sin(_anim_t) * 4.0


func set_in_range(v: bool) -> void:
	if v == _in_range:
		return
	_in_range = v
	if is_instance_valid(_exclaim):
		_exclaim.visible = v
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0, 3), 12, Color(0, 0, 0, 0.22))
	if _in_range:
		draw_arc(Vector2.ZERO, 20, 0, TAU, 48, Color(1.0, 0.92, 0.10, 0.80), 2.0)
