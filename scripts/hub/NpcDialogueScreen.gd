class_name NpcDialogueScreen
extends CanvasLayer
## Petit dialogue à PLUSIEURS PHRASES avec un PNJ — Hub ET salle-Boutique en
## run (même classe, cf. HubWorld._interact / CombatArena._open_boutique_shop).
## Portrait animé (sprite PMD « idle », comme le Pokédex) + texte en machine à
## écrire ; [E]/Entrée avance d'une phrase (ou termine l'affichage en cours),
## Échap saute tout le dialogue. BLOQUANT (contrairement à ChampionDialogueScreen,
## qui ne doit pas retarder un combat) : le menu associé n'ouvre qu'après.

signal finished

const ARTWORK_SIZE  := 190
const CHAR_INTERVAL := 0.022   # machine à écrire : s/caractère

## Illustration officielle PokeAPI (sprites GitHub, URL déterministe — pas
## besoin d'appel API pour la trouver). Mise en cache mémoire (statique,
## partagée par toutes les instances) pour ne la retélécharger qu'une fois
## par espèce et par session.
const ARTWORK_URL := "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/%d.png"
static var _artwork_cache: Dictionary = {}   # pid -> Texture2D (ou null si échec)

var _lines: Array = []
var _line_idx: int = 0
var _lbl: Label = null
var _hint: Label = null
var _full_text: String = ""
var _typed: bool = false
var _type_tween: Tween = null
var _done: bool = false


func setup(display_name: String, pokemon_id: int, accent: Color, lines: Array) -> void:
	layer  = 24
	_lines = lines if not lines.is_empty() else ["…"]

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var panel := UiKit.main_panel(Vector2(110, 420), Vector2(1060, 250))
	root.add_child(panel)
	UiKit.pop_in(panel)

	# Portrait : SANS cadre (retour joueurs — « on enlève le petit encadré
	# pour le sprite »), en grand format. Le sprite PMD animé « idle »
	# s'affiche tout de suite (comme avant) ; si le réseau répond, le beau
	# dessin officiel PokeAPI le remplace en douceur — repli silencieux sur
	# le PMD si hors ligne, pas de rupture de l'expérience.
	var art_holder := Control.new()
	art_holder.position     = Vector2(24, 14)
	art_holder.size         = Vector2(ARTWORK_SIZE, ARTWORK_SIZE)
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art_holder)
	_add_idle_sprite(art_holder, pokemon_id, ARTWORK_SIZE - 10,
		Vector2(ARTWORK_SIZE * 0.5, ARTWORK_SIZE * 0.5))
	_fetch_artwork(pokemon_id, art_holder)

	var name_col := accent if accent.a > 0.01 else UiKit.GOLD
	UiKit.label(panel, display_name.to_upper(), Vector2(24, ARTWORK_SIZE + 20),
		14, name_col, ARTWORK_SIZE, HORIZONTAL_ALIGNMENT_CENTER)

	var text_x := ARTWORK_SIZE + 48
	var text_w := 1060 - text_x - 24
	var text_area := UiKit.dark_card(panel, Vector2(text_x, 14), Vector2(text_w, ARTWORK_SIZE))
	_lbl = UiKit.label(text_area, "", Vector2(20, 16), 18, UiKit.CREAM, text_w - 40,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	_lbl.size = Vector2(text_w - 40, ARTWORK_SIZE - 8)
	_lbl.clip_text = true
	_lbl.visible_characters = 0

	_hint = UiKit.label(panel, "", Vector2(text_x, ARTWORK_SIZE + 20), 13,
		UiKit.CREAM.darkened(0.2), 600)
	var blink := create_tween().set_loops()
	blink.tween_property(_hint, "modulate:a", 1.0, 0.5)
	blink.tween_property(_hint, "modulate:a", 0.3, 0.5)

	_show_line(0)
	set_process_unhandled_input(true)


func _add_idle_sprite(parent: Control, pid: int, box: float, center: Vector2) -> void:
	var wref: WeakRef = weakref(parent)
	PMDSprites.get_walk_sprites(pid, parent, func(res: Dictionary) -> void:
		var par: Control = wref.get_ref()
		if res.is_empty() or par == null:
			return
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames  = res.frames
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var fs: Vector2i = res.frame_size
		var big := maxf(float(fs.x), float(fs.y))
		var s := 1.0 if big <= 0.0 else box / big
		spr.scale = Vector2.ONE * s
		var h := float(fs.y)
		var foot := float(res.get("foot_row", fs.y - 1))
		spr.position = center + Vector2(0.0, (h - foot) * 0.5 * s)
		par.add_child(spr)
		spr.play("idle")
	)


func _fetch_artwork(pid: int, holder: Control) -> void:
	if _artwork_cache.has(pid):
		var cached: Texture2D = _artwork_cache[pid]
		if cached != null:
			_show_artwork(holder, cached)
		return
	var http := HTTPRequest.new()
	add_child(http)
	var wref: WeakRef = weakref(holder)
	http.request_completed.connect(func(res: int, code: int, _h, body: PackedByteArray) -> void:
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200:
			_artwork_cache[pid] = null
			return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			_artwork_cache[pid] = null
			return
		var tex: Texture2D = ImageTexture.create_from_image(img)
		_artwork_cache[pid] = tex
		var h: Control = wref.get_ref()
		if h != null:
			_show_artwork(h, tex)
	)
	http.request(ARTWORK_URL % pid)


func _show_artwork(holder: Control, tex: Texture2D) -> void:
	for c in holder.get_children():
		c.queue_free()
	var rect := TextureRect.new()
	rect.texture         = tex
	rect.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(rect)


func _show_line(idx: int) -> void:
	_line_idx = idx
	_full_text = str(_lines[idx])
	_typed = false
	_lbl.visible_characters = 0
	if is_instance_valid(_type_tween):
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(_lbl, "visible_characters", _full_text.length(),
		_full_text.length() * CHAR_INTERVAL)
	_type_tween.tween_callback(_on_typed_done)
	_lbl.text = _full_text
	_hint.text = ""


func _on_typed_done() -> void:
	_typed = true
	_hint.text = "Appuyer pour fermer…" if _line_idx >= _lines.size() - 1 else "Appuyer pour continuer…"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if not _typed:
			_skip_typing()
		elif _line_idx < _lines.size() - 1:
			_show_line(_line_idx + 1)
		else:
			_close()


func _skip_typing() -> void:
	if is_instance_valid(_type_tween):
		_type_tween.kill()
	_lbl.visible_characters = _full_text.length()
	_on_typed_done()


func _close() -> void:
	if _done:
		return
	_done = true
	set_process_unhandled_input(false)
	finished.emit()
	queue_free()
