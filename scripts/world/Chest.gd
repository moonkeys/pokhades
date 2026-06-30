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


func setup(objects_layer: TileMapLayer, cell: Vector2i, src_id: int) -> void:
	_layer     = objects_layer
	_cell      = cell
	_source_id = src_id

	var pool_entry: Dictionary = ITEM_POOL[randi() % ITEM_POOL.size()].duplicate()
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
	opened.emit(_item)
