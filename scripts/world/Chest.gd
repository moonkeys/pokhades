class_name Chest
extends Area3D

## Coffre en run — HD-2D (phase 2) : Area3D + billboard du sprite de coffre
## découpé du tileset (le tile du layer Objects, caché à l'exécution, reste
## mis à jour pour la cohérence du modèle de données). Portée d'interaction
## et récompenses inchangées.

signal opened(item: Dictionary)
signal player_in_range(in_range: bool)

const TILESET_PATH := "res://assets/tilesets/tileset pokemon.png"

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
var _player_near: bool        = false

var _sprite:    Sprite3D       = null
var _halo:      MeshInstance3D = null
var _halo_mat:  StandardMaterial3D = null


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

	# Visuel — billboard du coffre fermé (le tile 2D est caché en jeu)
	var closed_atlas := _layer.get_cell_atlas_coords(_cell) if is_instance_valid(_layer) \
		and _layer.get_cell_source_id(_cell) != -1 else Vector2i(88, 61)
	_sprite = Billboard3D.make_tile_sprite(TILESET_PATH, closed_atlas, 1, 1, 1.0)
	add_child(_sprite)

	# Halo doré pulsant au sol (remplace l'ancien _draw 2D)
	_halo = MeshInstance3D.new()
	var disc := TorusMesh.new()
	disc.inner_radius = 0.30
	disc.outer_radius = 0.52
	_halo.mesh = disc
	_halo.scale = Vector3(1.0, 0.05, 1.0)
	_halo.position.y = 0.03
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.30)
	_halo_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)

	# Zone d'interaction : petite boîte DEVANT le coffre (face sud) — on ne
	# peut l'ouvrir qu'en se tenant juste devant, au contact, pas depuis les
	# côtés ni derrière (l'ancienne sphère englobait tout le tour).
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.9, 1.2, 0.8)
	cs.shape  = sh
	cs.position = Vector3(0, 0.5, 0.75)
	add_child(cs)

	collision_layer = 0
	collision_mask  = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _fetch_icon(url: String) -> void:
	# setup() est appelé avant add_child(chest) et le cache disque PokeAPI rend
	# le callback synchrone : il faut attendre d'être dans l'arbre pour que
	# HTTPRequest fonctionne.
	if not is_inside_tree():
		await tree_entered
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
	if is_instance_valid(_halo):
		var p := sin(_pulse) * 0.5 + 0.5
		_halo_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.20 + p * 0.22)
		var s := 1.0 + p * 0.28
		_halo.scale = Vector3(s, 0.05, s)
	if _player_near and Input.is_action_just_pressed("interact"):
		_open()


func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not (body.is_in_group("players") and body.get("is_active") == true):
		return
	_player_near = true
	player_in_range.emit(true)


func _on_body_exited(body: Node) -> void:
	if not (body.is_in_group("players") and body.get("is_active") == true):
		return
	_player_near = false
	player_in_range.emit(false)


func _open() -> void:
	if _opened:
		return
	_opened = true
	_player_near = false
	player_in_range.emit(false)
	Sfx.play("chest")
	if is_instance_valid(_layer):
		_layer.set_cell(_cell, _source_id, _open_atlas)
	if is_instance_valid(_sprite):
		var tex := Billboard3D.crop_tile(TILESET_PATH, _open_atlas, 1, 1)
		if tex != null:
			_sprite.texture = tex
	if is_instance_valid(_halo):
		_halo.visible = false
	_reveal_item()
	opened.emit(_item)


## Fait flotter l'icône de l'objet + son nom au-dessus du coffre,
## avec une montée douce puis un fondu, façon "loot révélé".
func _reveal_item() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0, 0.8, 0)
	add_child(holder)

	# ── Icône de l'objet ───────────────────────────────────────────
	var icon_tex: Texture2D = _item.get("icon", null)
	var icon: Sprite3D = null
	if icon_tex != null and icon_tex.get_height() > 0:
		icon = Sprite3D.new()
		icon.texture = icon_tex
		icon.pixel_size = 0.9 / float(icon_tex.get_height())   # hauteur cible ~0.9 unité
		icon.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		icon.shaded     = false
		holder.add_child(icon)

	# ── Nom de l'objet ─────────────────────────────────────────────
	var name_str: String = _item.get("name_fr", _item.get("api_name", "Objet"))
	var lbl := Label3D.new()
	lbl.text = str(name_str)
	lbl.position = Vector3(0, 0.85, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 48
	lbl.pixel_size = 0.008
	lbl.modulate = Color(1.0, 0.95, 0.6)
	lbl.outline_modulate = Color(0.15, 0.10, 0.02)
	lbl.outline_size = 14
	holder.add_child(lbl)

	# ── Animation : montée + fondu ─────────────────────────────────
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", 2.4, 2.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if icon != null:
		tw.tween_property(icon, "modulate:a", 0.0, 0.8).set_delay(1.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(1.8)
	tw.chain().tween_callback(holder.queue_free)
