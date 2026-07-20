extends Node

const _BASE_URL := "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite"
const _CACHE_DIR := "user://cache/pmd/"
## Cache EMBARQUÉ dans le build (res://, donc dans le .pck à l'export) —
## rempli une fois pour toutes par tools/download_all_assets.gd et committé au
## dépôt. Lu AVANT le cache utilisateur : le jeu tourne hors ligne dès le
## premier lancement, sans passer par le réseau ni écrire sur le disque de
## l'utilisateur pour ce qui est déjà fourni. res:// est en lecture seule à
## l'export — toutes les ÉCRITURES continuent de cibler _CACHE_DIR.
const _BUNDLED_DIR := "res://data/pmd/"

# Rangées de la feuille par direction (cardinales d'abord — source de
# fallback — puis diagonales). Générique : préfixé par l'action ("walk_down",
# "attack_down", "hurt_down"…).
const _DIR_ROW_SUFFIX := {
	"down": 0, "right": 2, "up": 4, "left": 6,
	"downright": 1, "upright": 3, "upleft": 5, "downleft": 7,
}

const _DIAG_FALLBACK_SUFFIX := {
	"downright": "right",
	"upright":   "right",
	"upleft":    "left",
	"downleft":  "left",
}

## Actions supplémentaires chargées en arrière-plan après la marche —
## injectées dans le MÊME SpriteFrames (partagé par référence : les sprites
## déjà affichés gagnent les animations dès qu'elles arrivent).
## Nom SpriteCollab → préfixe d'animation Godot. Shoot/Charge servent aux
## attaques spéciales (cf. TeamMember : chaîne de repli shoot→charge→attack).
const _EXTRA_ACTIONS := {"Attack": "attack", "Hurt": "hurt", "Shoot": "shoot", "Charge": "charge", "Sleep": "sleep"}

const _FPS_DEFAULT := 8.0

var _cache: Dictionary = {}    # str(dex_id) → {"frames": SpriteFrames, "frame_size": Vector2i}
var _pending: Dictionary = {}  # str(dex_id) → Array[Callable]
var _actions_loaded: Dictionary = {}   # str(dex_id) → true (Attack/Hurt déjà demandés)


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


# ── Chargement en deux étapes : XML puis PNG (avec cache disque) ──

func _load_xml(dex_id: int) -> void:
	var path := _read_path(dex_id, "AnimData.xml")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var xml_text := f.get_as_text()
		f.close()
		print("PMD: XML depuis cache disque id=%d" % dex_id)
		_load_png(dex_id, _parse_xml(xml_text))
		return

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
		var xml_text: String = body.get_string_from_utf8()
		_write_cache_text(path, xml_text)
		var info := _parse_xml(xml_text)
		print("PMD: XML parsé id=%d  frame=%dx%d  frames=%d  fps=%.1f" % [dex_id, info.frame_w, info.frame_h, info.num_frames, info.fps])
		_load_png(dex_id, info)
	)
	http.request(url)


func _load_png(dex_id: int, info: Dictionary) -> void:
	var path := _read_path(dex_id, "Walk-Anim.png")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var bytes := f.get_buffer(f.get_length())
		f.close()
		print("PMD: PNG depuis cache disque id=%d" % dex_id)
		_finish_png(dex_id, bytes, info)
		return

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
		_write_cache_bytes(path, body)
		_finish_png(dex_id, body, info)
	)
	http.request(url)


func _finish_png(dex_id: int, bytes: PackedByteArray, info: Dictionary) -> void:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		print("PMD: échec décodage PNG id=%d" % dex_id)
		_resolve(dex_id, {})
		return
	var texture := ImageTexture.create_from_image(img)
	var frames := _build_frames(texture, info, img.get_height())
	var fw: int = info.get("frame_w", 32)
	var fh: int = info.get("frame_h", 32)
	# Ligne "walk_down" (row 0), 1ère frame — sert de référence pour la position des pieds.
	var foot_row := _find_foot_row(img, Rect2i(0, 0, fw, fh))
	_resolve(dex_id, {
		"frames": frames,
		"frame_size": Vector2i(fw, fh),
		"foot_row": foot_row,   # rangée (depuis le haut de la frame) du pixel opaque le plus bas
	})


## Scanne une frame et retourne la rangée (0 = haut de la frame) du pixel
## opaque le plus bas — les feuilles PMD ont souvent une marge vide en bas,
## donc la hauteur de frame seule ne suffit pas à positionner les "pieds".
func _find_foot_row(img: Image, rect: Rect2i) -> int:
	if rect.position.x < 0 or rect.position.y < 0 \
			or rect.position.x + rect.size.x > img.get_width() \
			or rect.position.y + rect.size.y > img.get_height():
		return rect.size.y - 1
	var lowest := -1
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if img.get_pixel(x, y).a > 0.05:
				lowest = y
	if lowest == -1:
		return rect.size.y - 1
	return lowest - rect.position.y


# ── Cache disque (user://) — évite de retélécharger d'une session à l'autre ──

func _cache_path(dex_id: int, filename: String) -> String:
	return "%s%04d/%s" % [_CACHE_DIR, dex_id, filename]


## Chemin à LIRE : le bundle embarqué (res://) s'il a ce fichier, sinon le
## cache utilisateur (user://, éventuellement vide → l'appelant retombera sur
## le réseau).
func _read_path(dex_id: int, filename: String) -> String:
	var bundled := "%s%04d/%s" % [_BUNDLED_DIR, dex_id, filename]
	if FileAccess.file_exists(bundled):
		return bundled
	return _cache_path(dex_id, filename)


func _write_cache_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()


func _write_cache_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return
	f.store_buffer(bytes)
	f.close()


func _resolve(dex_id: int, result: Dictionary) -> void:
	var key := str(dex_id)
	if not result.is_empty():
		_cache[key] = result
	var callbacks: Array = _pending.get(key, [])
	_pending.erase(key)
	for cb in callbacks:
		if cb.is_valid(): cb.call(result)
	# La marche est prête : charge Attaque/Dégâts en arrière-plan (best
	# effort — un Pokémon sans feuille Attack garde juste le lunge existant).
	if not result.is_empty():
		_load_extra_actions(dex_id)


# ── Actions supplémentaires (Attack, Hurt) — ajoutées au même SpriteFrames ──

func _load_extra_actions(dex_id: int) -> void:
	var key := str(dex_id)
	if _actions_loaded.has(key):
		return
	_actions_loaded[key] = true
	var xml_path := _read_path(dex_id, "AnimData.xml")
	if not FileAccess.file_exists(xml_path):
		return
	var f := FileAccess.open(xml_path, FileAccess.READ)
	var xml := f.get_as_text()
	f.close()
	for action: String in _EXTRA_ACTIONS:
		_load_action(dex_id, xml, action, _EXTRA_ACTIONS[action])


func _load_action(dex_id: int, xml: String, action: String, prefix: String) -> void:
	var info := _parse_anim_block(xml, action)
	if info.is_empty():
		return
	# <CopyOf> : l'anim référence la feuille d'une autre action
	var sheet_action := action
	if info.has("copy_of"):
		sheet_action = info["copy_of"]
		info = _parse_anim_block(xml, sheet_action)
		if info.is_empty():
			return

	var path := _read_path(dex_id, "%s-Anim.png" % sheet_action)
	if FileAccess.file_exists(path):
		var fp := FileAccess.open(path, FileAccess.READ)
		var bytes := fp.get_buffer(fp.get_length())
		fp.close()
		_finish_action(dex_id, bytes, info, prefix)
		return

	var padded := "%04d" % dex_id
	var url := "%s/%s/%s-Anim.png" % [_BASE_URL, padded, sheet_action]
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _h, body):
		http.queue_free()
		if result != OK or code != 200:
			return   # feuille absente pour ce Pokémon — pas grave
		_write_cache_bytes(path, body)
		_finish_action(dex_id, body, info, prefix)
	)
	http.request(url)


func _finish_action(dex_id: int, bytes: PackedByteArray, info: Dictionary, prefix: String) -> void:
	var key := str(dex_id)
	if not _cache.has(key):
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	var texture := ImageTexture.create_from_image(img)
	var frames: SpriteFrames = _cache[key]["frames"]
	_add_direction_anims(frames, texture, info, prefix, img.get_height(), false)


# ── Construction du SpriteFrames ──────────────────────────────────

func _build_frames(texture: Texture2D, info: Dictionary, sheet_h: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	_add_direction_anims(frames, texture, info, "walk", sheet_h, true)

	# Idle = boucle lente sur les frames walk_down (animation "respiration")
	var fw: int = info.get("frame_w", 32)
	var fh: int = info.get("frame_h", 32)
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


## Découpe les 8 directions d'une feuille PMD en animations "<prefix>_<dir>"
## dans `frames` — partagé entre la marche (loop) et les actions Attack/Hurt
## (one-shot). Diagonales absentes → copie du cardinal le plus proche.
func _add_direction_anims(frames: SpriteFrames, texture: Texture2D, info: Dictionary,
		prefix: String, sheet_h: int, looping: bool) -> void:
	var fw: int = info.get("frame_w", 32)
	var fh: int = info.get("frame_h", 32)
	var nf: int = info.get("num_frames", 4)
	var fps: float = info.get("fps", _FPS_DEFAULT)

	for suffix: String in _DIR_ROW_SUFFIX:
		var anim_name := "%s_%s" % [prefix, suffix]
		var y: int = _DIR_ROW_SUFFIX[suffix] * fh
		if not frames.has_animation(anim_name):
			frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, looping)
		if y + fh > sheet_h:
			# Rangée absente : pour les diagonales, copier le cardinal le plus proche
			var src := "%s_%s" % [prefix, _DIAG_FALLBACK_SUFFIX.get(suffix, "down")]
			if frames.has_animation(src) and frames.get_frame_count(src) > 0:
				for i in frames.get_frame_count(src):
					frames.add_frame(anim_name, frames.get_frame_texture(src, i))
			continue
		for col in nf:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, y, fw, fh)
			frames.add_frame(anim_name, atlas)


# ── Parsing XML minimaliste ────────────────────────────────────────

func _parse_xml(xml: String) -> Dictionary:
	var result := _parse_anim_block(xml, "Walk")
	if result.is_empty() or result.has("copy_of"):
		# Pas de bloc Walk exploitable — valeurs globales/défaut
		result = {"frame_w": 32, "frame_h": 32, "num_frames": 4, "fps": _FPS_DEFAULT}
		result.frame_w = _xml_int(xml, "<FrameWidth>", "</FrameWidth>", 0, result.frame_w)
		result.frame_h = _xml_int(xml, "<FrameHeight>", "</FrameHeight>", 0, result.frame_h)
	return result


## Bloc <Anim> nommé `name` : {frame_w, frame_h, num_frames, fps} ou
## {"copy_of": autre} si l'anim référence la feuille d'une autre action,
## ou {} si absente. Utilisé pour Walk (chargement initial) et pour les
## actions supplémentaires (Attack/Hurt).
func _parse_anim_block(xml: String, name: String) -> Dictionary:
	var name_idx := xml.find("<Name>%s</Name>" % name)
	if name_idx == -1:
		return {}
	var anim_start := xml.rfind("<Anim>", name_idx)
	var anim_end   := xml.find("</Anim>", name_idx)
	if anim_start == -1 or anim_end == -1:
		return {}
	var block := xml.substr(anim_start, anim_end - anim_start + 7)

	# <CopyOf> : l'anim n'a pas de feuille propre
	var copy_s := block.find("<CopyOf>")
	if copy_s != -1:
		var copy_e := block.find("</CopyOf>")
		if copy_e > copy_s:
			return {"copy_of": block.substr(copy_s + 8, copy_e - copy_s - 8).strip_edges()}

	var result := {"frame_w": 32, "frame_h": 32, "num_frames": 4, "fps": _FPS_DEFAULT}
	# Dimensions globales en fallback, écrasées par celles du bloc
	result.frame_w = _xml_int(xml, "<FrameWidth>", "</FrameWidth>", 0, result.frame_w)
	result.frame_h = _xml_int(xml, "<FrameHeight>", "</FrameHeight>", 0, result.frame_h)
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
