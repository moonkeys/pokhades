class_name NpcDialogueScreen
extends CanvasLayer
## Petit dialogue à PLUSIEURS PHRASES avec un PNJ — Hub ET salle-Boutique en
## run (même classe, cf. HubWorld._interact / CombatArena._open_boutique_shop).
## Portrait animé (sprite PMD « idle », comme le Pokédex) + texte en machine à
## écrire ; [E]/Entrée avance d'une phrase (ou termine l'affichage en cours),
## Échap saute tout le dialogue. BLOQUANT (contrairement à ChampionDialogueScreen,
## qui ne doit pas retarder un combat) : le menu associé n'ouvre qu'après.

signal finished

const PORTRAIT_SIZE := 128
const CHAR_INTERVAL := 0.022   # machine à écrire : s/caractère

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

	var panel := UiKit.main_panel(Vector2(140, 460), Vector2(1000, 210))
	root.add_child(panel)
	UiKit.pop_in(panel)

	# Portrait : sprite PMD animé (« idle »), même technique que le Pokédex
	# (PokedexScreen._add_idle_sprite) — un AnimatedSprite2D se centre sur sa
	# position, ce qui règle le cadrage sans y penser.
	var port_frame := UiKit.dark_card(panel, Vector2(20, 20), Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE + 40))
	_add_idle_sprite(port_frame, pokemon_id, PORTRAIT_SIZE - 16,
		Vector2(PORTRAIT_SIZE * 0.5, PORTRAIT_SIZE * 0.5))
	var name_col := accent if accent.a > 0.01 else UiKit.GOLD
	UiKit.label(port_frame, display_name.to_upper(), Vector2(0, PORTRAIT_SIZE - 4),
		14, name_col, PORTRAIT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)

	var text_area := UiKit.dark_card(panel, Vector2(170, 20), Vector2(810, PORTRAIT_SIZE + 40))
	_lbl = UiKit.label(text_area, "", Vector2(20, 16), 18, UiKit.CREAM, 770,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	_lbl.size = Vector2(770, PORTRAIT_SIZE + 8)
	_lbl.clip_text = true
	_lbl.visible_characters = 0

	_hint = UiKit.label(panel, "", Vector2(170, PORTRAIT_SIZE + 46), 13,
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
