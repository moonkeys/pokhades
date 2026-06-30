class_name ExitPortal
extends Area2D

signal chosen(data: Dictionary)

var _data:      Dictionary = {}
var _triggered: bool       = false
var _pulse:     float      = 0.0


func setup(data: Dictionary) -> void:
	_data = data

	# Hitbox de détection joueur
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 64.0
	cs.shape  = sh
	add_child(cs)

	collision_layer = 8   # layer dédié (n'interfère pas avec murs/ennemis)
	collision_mask  = 1   # détecte layer 1 (CharacterBody2D par défaut)

	# Label zone
	var lbl_z := Label.new()
	lbl_z.text     = "→ %s" % data.get("zone_name", "?")
	lbl_z.position = Vector2(-52, -76)
	lbl_z.add_theme_font_size_override("font_size", 12)
	lbl_z.modulate = Color(1.0, 0.95, 0.4)
	add_child(lbl_z)

	# Label bonus
	var lbl_b := Label.new()
	lbl_b.text     = data.get("bonus_label", "")
	lbl_b.position = Vector2(-52, -60)
	lbl_b.add_theme_font_size_override("font_size", 11)
	lbl_b.modulate = Color(0.5, 1.0, 0.55)
	add_child(lbl_b)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_pulse += delta * 3.0
	queue_redraw()


func _draw() -> void:
	var p   := (sin(_pulse) * 0.5 + 0.5)   # 0..1
	var r   := 28.0 + p * 6.0
	var col := Color(0.25, 0.9, 0.45, 0.35 + p * 0.25)
	draw_circle(Vector2.ZERO, r, col)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.4, 1.0, 0.6, 0.85 + p * 0.15), 3.0)
	# Flèche vers le haut
	var ay := -r - 8.0
	draw_line(Vector2(0, ay), Vector2(0, ay - 14), Color(0.6, 1.0, 0.7, 0.9), 2.5)
	draw_line(Vector2(0, ay - 14), Vector2(-6, ay - 7), Color(0.6, 1.0, 0.7, 0.9), 2.5)
	draw_line(Vector2(0, ay - 14), Vector2( 6, ay - 7), Color(0.6, 1.0, 0.7, 0.9), 2.5)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	# Seul le membre actif déclenche la sortie
	var is_active_player: bool = body.is_in_group("players") and body.get("is_active") == true
	if not is_active_player:
		return
	_triggered = true
	chosen.emit(_data)
