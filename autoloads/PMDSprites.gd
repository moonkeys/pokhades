extends Node

const _BASE_URL := "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite"

# Rangées cardinales d'abord (fallback source), puis diagonales
const _DIR_ROWS := {
	"walk_down":      0,
	"walk_right":     2,
	"walk_up":        4,
	"walk_left":      6,
	"walk_downright": 1,
	"walk_upright":   3,
	"walk_upleft":    5,
	"walk_downleft":  7,
}

const _DIAG_FALLBACK := {
	"walk_downright": "walk_right",
	"walk_upright":   "walk_right",
	"walk_upleft":    "walk_left",
	"walk_downleft":  "walk_left",
}

const _FPS_DEFAULT := 8.0

var _cache: Dictionary = {}    # str(dex_id) → {"frames": SpriteFrames, "frame_size": Vector2i}
var _pending: Dictionary = {}  # str(dex_id) → Array[Callable]


## Le paramètre `_node` est conservé pour compatibilité mais ignoré.
## Les HTTPRequest sont attachés à PMDSprites (autoload) pour survivre
## aux changements de scène — c'est ce qui empêchait les sprites de charger.
func get_walk_sprites(dex_id: int, _node: Node, callback: Callable) -> void:
	var key := str(dex_id)
	if _cache.has(key):
		if callback.is_valid(): callback.call(_cache[key])
		return
	if _pending.has(key):
		_pending[key].append(callback)
		return
	_pending[key] = [callback]
	_load_xml(dex_id)


# ── Chargement en deux étapes : XML puis PNG ──────────────────────

func _load_xml(dex_id: int) -> void:
	var padded := "%04d" % dex_id
	var url := "%s/%s/AnimData.xml" % [_BASE_URL, padded]
	print("PMD: chargement XML id=%d → %s" % [dex_id, url])
	var http := HTTPRequest.new()
	add_child(http)   # attaché à PMDSprites (autoload permanent)
	http.request_completed.connect(func(result, code, _h, body):
		print("PMD: XML réponse id=%d  result=%d  code=%d  taille=%d" % [dex_id, result, code, body.size()])
		http.queue_free()
		if result != OK or code != 200:
			_resolve(dex_id, {})
			return
		var info := _parse_xml(body.get_string_from_utf8())
		print("PMD: XML parsé id=%d  frame=%dx%d  frames=%d  fps=%.1f" % [dex_id, info.frame_w, info.frame_h, info.num_frames, info.fps])
		_load_png(dex_id, info)
	)
	http.request(url)


func _load_png(dex_id: int, info: Dictionary) -> void:
	var padded := "%04d" % dex_id
	var url := "%s/%s/Walk-Anim.png" % [_BASE_URL, padded]
	print("PMD: chargement PNG id=%d → %s" % [dex_id, url])
	var http := HTTPRequest.new()
	add_child(http)   # attaché à PMDSprites (autoload permanent)
	http.request_completed.connect(func(result, code, _h, body):
		print("PMD: PNG réponse id=%d  result=%d  code=%d  taille=%d" % [dex_id, result, code, body.size()])
		http.queue_free()
		if result != OK or code != 200:
			_resolve(dex_id, {})
			return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			print("PMD: échec décodage PNG id=%d" % dex_id)
			_resolve(dex_id, {})
			return
		print("PMD: PNG OK id=%d  taille image=%dx%d" % [dex_id, img.get_width(), img.get_height()])
		var texture := ImageTexture.create_from_image(img)
		var frames := _build_frames(texture, info, img.get_height())
		_resolve(dex_id, {
			"frames": frames,
			"frame_size": Vector2i(info.get("frame_w", 32), info.get("frame_h", 32))
		})
	)
	http.request(url)


func _resolve(dex_id: int, result: Dictionary) -> void:
	var key := str(dex_id)
	if not result.is_empty():
		_cache[key] = result
	var callbacks: Array = _pending.get(key, [])
	_pending.erase(key)
	for cb in callbacks:
		if cb.is_valid(): cb.call(result)


# ── Construction du SpriteFrames ──────────────────────────────────

func _build_frames(texture: Texture2D, info: Dictionary, sheet_h: int) -> SpriteFrames:
	var fw: int = info.get("frame_w", 32)
	var fh: int = info.get("frame_h", 32)
	var nf: int = info.get("num_frames", 4)
	var fps: float = info.get("fps", _FPS_DEFAULT)

	var frames := SpriteFrames.new()

	for anim_name in _DIR_ROWS:
		var row: int = _DIR_ROWS[anim_name]
		var y := row * fh
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, true)
		if y + fh > sheet_h:
			# Rangée absente : pour les diagonales, copier le cardinal le plus proche
			var src: String = _DIAG_FALLBACK.get(anim_name, "walk_down")
			if frames.has_animation(src) and frames.get_frame_count(src) > 0:
				for i in frames.get_frame_count(src):
					frames.add_frame(anim_name, frames.get_frame_texture(src, i))
			elif anim_name != "walk_down" and frames.has_animation("walk_down") \
					and frames.get_frame_count("walk_down") > 0:
				for i in frames.get_frame_count("walk_down"):
					frames.add_frame(anim_name, frames.get_frame_texture("walk_down", i))
			continue
		for col in nf:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, y, fw, fh)
			frames.add_frame(anim_name, atlas)

	# Idle = boucle lente sur les frames walk_down (animation "respiration")
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 4.5)
	if frames.has_animation("walk_down") and frames.get_frame_count("walk_down") > 0:
		var wd_count := frames.get_frame_count("walk_down")
		for i in mini(wd_count, 4):
			frames.add_frame("idle", frames.get_frame_texture("walk_down", i))
	else:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(0, 0, fw, fh)
		frames.add_frame("idle", atlas)

	return frames


# ── Parsing XML minimaliste ────────────────────────────────────────

func _parse_xml(xml: String) -> Dictionary:
	var result := {"frame_w": 32, "frame_h": 32, "num_frames": 4, "fps": _FPS_DEFAULT}

	# Dimensions globales (fallback si Walk n'a pas les siennes)
	result.frame_w = _xml_int(xml, "<FrameWidth>", "</FrameWidth>", 0, result.frame_w)
	result.frame_h = _xml_int(xml, "<FrameHeight>", "</FrameHeight>", 0, result.frame_h)

	# Bloc Walk
	var walk_idx := xml.find("<Name>Walk</Name>")
	if walk_idx == -1:
		return result

	var anim_start := xml.rfind("<Anim>", walk_idx)
	var anim_end   := xml.find("</Anim>", walk_idx)
	if anim_start == -1 or anim_end == -1:
		return result
	var block := xml.substr(anim_start, anim_end - anim_start + 7)

	# Dimensions spécifiques à Walk (écrasent les globales)
	result.frame_w = _xml_int(block, "<FrameWidth>", "</FrameWidth>", 0, result.frame_w)
	result.frame_h = _xml_int(block, "<FrameHeight>", "</FrameHeight>", 0, result.frame_h)

	# Nombre de frames + FPS depuis <Durations>
	var dur_s := block.find("<Durations>")
	var dur_e := block.find("</Durations>")
	if dur_s != -1 and dur_e != -1:
		var dur_block := block.substr(dur_s, dur_e - dur_s)
		result.num_frames = dur_block.count("<Duration>")
		var d_open  := dur_block.find("<Duration>") + 10
		var d_close := dur_block.find("</Duration>")
		if d_open > 9 and d_close > d_open:
			var ticks := int(dur_block.substr(d_open, d_close - d_open).strip_edges())
			if ticks > 0:
				result.fps = 60.0 / float(ticks)

	return result


func _xml_int(text: String, open_tag: String, close_tag: String, from: int, default: int) -> int:
	var s := text.find(open_tag, from)
	if s == -1:
		return default
	s += open_tag.length()
	var e := text.find(close_tag, s)
	if e == -1:
		return default
	return int(text.substr(s, e - s).strip_edges())
