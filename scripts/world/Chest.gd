class_name Chest
extends Area2D

signal opened(item: Dictionary)

const ITEM_POOL: Array[Dictionary] = [
	{"api_name": "choice-band",  "effect": "atk", "mult": 1.5},
	{"api_name": "choice-scarf", "effect": "spd", "mult": 1.5},
	{"api_name": "choice-specs", "effect": "atk", "mult": 1.4},
	{"api_name": "life-orb",     "effect": "atk", "mult": 1.3},
	{"api_name": "expert-belt",  "effect": "atk", "mult": 1.2},
	{"api_name": "black-belt",   "effect": "def", "mult": 1.3},
	{"api_name": "leftovers",    "effect": "hp",  "mult": 0.30},
	{"api_name": "shell-bell",   "effect": "hp",  "mult": 0.20},
	{"api_name": "lum-berry",    "effect": "hp",  "mult": 0.40},
	{"api_name": "power-herb",   "effect": "spd", "mult": 1.2},
]

var _item:       Dictionary   = {}
var _opened:     bool         = false
var _layer:      TileMapLayer = null
var _cell:       Vector2i     = Vector2i.ZERO
var _source_id:  int          = 0
var _open_atlas: Vector2i     = Vector2i(91, 61)
var _pulse:      float        = 0.0


func setup(objects_layer: TileMapLayer, cell: Vector2i, src_id: int,
		forced: Dictionary = {}) -> void:
	_layer     = objects_layer
	_cell      = cell
	_source_id = src_id

	var pool_entry: Dictionary = forced.duplicate() if not forced.is_empty() \
		else ITEM_POOL[randi() % ITEM_POOL.size()].duplicate()
	_item = pool_entry

	PokemonAPI.get_item(pool_entry["api_name"], func(data: Dictionary) -> void:
		if data.is_empty():
			return
		_item["name_fr"]    = data.get("name_fr", pool_entry["api_name"])
		_item["sprite_url"] = data.get("sprite_url", "")
		var url: String = _item.get("sprite_url", "")
		if not url.is_empty():
			_fetch_icon(url)
	)

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 14.0
	cs.shape  = sh
	add_child(cs)

	collision_layer = 0
	collision_mask  = 1
	body_entered.connect(_on_body_entered)


func _fetch_icon(url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			return
		_item["icon"] = ImageTexture.create_from_image(img)
	)
	http.request(url)


func _process(delta: float) -> void:
	if _opened:
		return
	_pulse += delta * 2.5
	queue_redraw()


func _draw() -> void:
	if _opened:
		return
	var p := sin(_pulse) * 0.5 + 0.5
	draw_circle(Vector2.ZERO, 6.0 + p * 3.0, Color(1.0, 0.85, 0.2, 0.25 + p * 0.2))


func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not (body.is_in_group("players") and body.get("is_active") == true):
		return
	_opened = true
	if is_instance_valid(_layer):
		_layer.set_cell(_cell, _source_id, _open_atlas)
	_reveal_item()
	opened.emit(_item)


## Fait flotter l'icône de l'objet + son nom au-dessus du coffre,
## avec une montée douce puis un fondu, façon "loot révélé".
func _reveal_item() -> void:
	var holder := Node2D.new()
	holder.position = Vector2(0, -10)
	holder.z_index  = 4096   # au-dessus de tout le reste
	add_child(holder)

	# ── Icône de l'objet ───────────────────────────────────────────
	var icon_tex: Texture2D = _item.get("icon", null)
	if icon_tex != null and icon_tex.get_height() > 0:
		var spr := Sprite2D.new()
		spr.texture = icon_tex
		var s := 20.0 / float(icon_tex.get_height())   # hauteur cible ~20px
		spr.scale = Vector2(s, s)
		spr.position = Vector2(0, -2)
		holder.add_child(spr)

	# ── Nom de l'objet ─────────────────────────────────────────────
	var name_str: String = _item.get("name_fr", _item.get("api_name", "Objet"))
	var lbl := Label.new()
	lbl.text = str(name_str)
	lbl.size = Vector2(160, 18)
	lbl.position = Vector2(-80, -34)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	lbl.add_theme_color_override("font_outline_color", Color(0.15, 0.10, 0.02))
	lbl.add_theme_constant_override("outline_size", 4)
	holder.add_child(lbl)

	# ── Animation : montée + fondu ─────────────────────────────────
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", -34.0, 2.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, 0.8) \
		.set_delay(1.8)
	tw.chain().tween_callback(holder.queue_free)
