class_name BerryPickup
extends Node3D

## Baie lâchée au sol par un arbre à baies brisé (cf. BerryTree). Ramassée
## par le Pokémon contrôlé → crédite des Baies (GameManager.gold, monnaie
## PERSISTANTE : la récolte d'une run enrichit durablement les boutiques du
## hub). S'attire magnétiquement vers le joueur si l'amélioration « Aimant à
## Baies » est achetée (GameManager.berry_magnet).

const ICON := "res://assets/items/aguav-berry.png"
const VALUE := 3                # Baies par baie ramassée
const PICKUP_DIST  := 1.1
const MAGNET_RANGE := 7.0
const MAGNET_SPEED := 12.0
const LIFETIME_MAX := 25.0     # filet de sécurité si jamais ramassée

## Icône affichée — le sprite d'item de la baie associée à l'arbre (Essentials).
## Défini par BerryTree avant l'ajout à la scène ; défaut = aguav.
var icon_path: String = ICON

var _t: float = 0.0
var _spawn_hop: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	var tex: Texture2D = load(icon_path)
	if tex == null:
		tex = load(ICON)
	var spr := Sprite3D.new()
	spr.texture        = tex
	spr.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded         = false
	spr.pixel_size     = 0.7 / float(maxi(tex.get_height(), 1))
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.position.y     = 0.35
	add_child(spr)
	# Petit saut d'éjection à l'apparition
	_spawn_hop = randf_range(1.5, 2.6)
	position += Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))


func _process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME_MAX:
		queue_free()
		return

	var target := _active_player()

	# Éjection initiale (petite parabole) puis flottement
	if _spawn_hop > 0.0:
		_spawn_hop -= 9.0 * delta
		position.y = maxf(_base_y, position.y + _spawn_hop * delta)

	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < PICKUP_DIST:
			GameManager.add_gold(VALUE)
			Sfx.play("coin", -6.0, 0.15)
			_popup_text()
			queue_free()
			return
		# Attraction magnétique si l'amélioration est achetée
		if GameManager.berry_magnet and dist < MAGNET_RANGE:
			var step: float = MAGNET_SPEED * delta * clampf(1.5 - dist / MAGNET_RANGE, 0.3, 1.5)
			global_position += to.normalized() * step

	# Léger balancement idle
	get_child(0).position.y = 0.35 + sin(_t * 3.0) * 0.05


func _active_player() -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p.get("is_active") == true:
			return p
	# à défaut, le plus proche joueur
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		var d: float = global_position.distance_to(p.global_position)
		if d < bd: bd = d; best = p
	return best


func _popup_text() -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var lbl := Label3D.new()
	lbl.text = "+%d Baie" % VALUE
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.pixel_size = 0.009
	lbl.modulate = Color(0.75, 0.95, 0.45)
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.10, 0.14, 0.05)
	lbl.position = global_position + Vector3(0, 1.0, 0)
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y + 0.8, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tw.chain().tween_callback(lbl.queue_free)
