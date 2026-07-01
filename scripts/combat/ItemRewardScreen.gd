class_name ItemRewardScreen
extends CanvasLayer

signal member_chosen(team_index: int)

const C_BG     := Color(0.08, 0.06, 0.03, 0.90)
const C_CARD   := Color(0.14, 0.11, 0.07, 0.95)
const C_GOLD   := Color(0.88, 0.72, 0.25)
const C_TEXT   := Color(0.94, 0.88, 0.72)
const C_DIM    := Color(0.58, 0.50, 0.36)
const C_HP_OK  := Color(0.30, 0.85, 0.40)
const C_HP_LOW := Color(0.90, 0.55, 0.15)
const C_HP_KO  := Color(0.75, 0.20, 0.20)


func setup(item: Dictionary, team: Array) -> void:
	layer = 24

	var root := _bg_panel()

	var name_str: String = item.get("name_fr", item.get("api_name", "Objet"))
	_label(root, "✦  %s  ✦" % name_str, Vector2(640, 46), 26, C_GOLD,
		HORIZONTAL_ALIGNMENT_CENTER)

	var icon_tex: Texture2D = item.get("icon", null)
	if icon_tex != null and icon_tex.get_height() > 0:
		var tex := TextureRect.new()
		tex.texture      = icon_tex
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position     = Vector2(608, 78)
		tex.size         = Vector2(64, 64)
		root.add_child(tex)

	_label(root, _describe_item(item), Vector2(640, 150), 15, C_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "À qui donner cet objet ?", Vector2(640, 188), 17, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)

	var live: Array = []
	for m in team:
		if is_instance_valid(m):
			live.append(m)

	var card_w  := 280.0
	var card_h  := 168.0
	var cols    := mini(live.size(), 4) if live.size() > 0 else 1
	var pad_x   := (1280.0 - cols * card_w) / (cols + 1)
	var start_y := 232.0

	for i in live.size():
		var m = live[i]
		var inst: PokemonInstance = m.pokemon_instance
		var col := i % cols
		var row := i / cols
		var cx  := pad_x + col * (card_w + pad_x)
		var cy  := start_y + row * (card_h + 16)
		_build_card(root, inst, m.team_index, Vector2(cx, cy), card_w, card_h)


func _describe_item(item: Dictionary) -> String:
	var mult: float = item.get("mult", 1.0)
	match item.get("effect", ""):
		"atk": return "Objet tenu — Attaque ×%.1f en permanence" % mult
		"def": return "Objet tenu — Défense ×%.1f en permanence" % mult
		"spd": return "Objet tenu — Vitesse ×%.1f en permanence" % mult
		"hp":  return "Consommable — soigne %d%% des PV max immédiatement" % int(mult * 100)
	return ""


func _bg_panel() -> Control:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg


func _build_card(parent: Node, inst: PokemonInstance, team_idx: int, pos: Vector2,
		w: float, h: float) -> void:
	var card := Panel.new()
	card.position = pos
	card.size     = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color      = C_CARD
	st.border_color  = C_GOLD.darkened(0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)

	var fainted := inst.is_fainted()

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture      = inst.portrait_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position     = Vector2(8, 8)
		tex.size         = Vector2(56, 56)
		tex.modulate.a   = 0.5 if fainted else 1.0
		card.add_child(tex)

	var tx := 72.0
	var name_col := C_HP_KO if fainted else C_TEXT
	_label(card, inst.data.name_fr.capitalize() + ("  [KO]" if fainted else ""),
		Vector2(tx, 8), 15, name_col)
	_label(card, "Niv. %d" % inst.level, Vector2(tx, 28), 12, C_DIM)

	var bar_x   := tx
	var bar_y   := 48.0
	var bar_w   := w - tx - 10.0
	var bar_h   := 10.0
	var ratio   := inst.hp_ratio()
	var bar_col := C_HP_OK if ratio > 0.5 else (C_HP_LOW if ratio > 0.2 else C_HP_KO)
	_draw_bar(card, Vector2(bar_x, bar_y), bar_w, bar_h, ratio, bar_col)
	_label(card, "%d / %d PV" % [inst.current_hp, inst.max_hp],
		Vector2(tx, 60), 11, C_DIM)

	var held_str: String = "Aucun objet"
	if not inst.held_item.is_empty():
		held_str = "Tient : %s" % str(inst.held_item.get("name_fr",
			inst.held_item.get("api_name", "?")))
	_label(card, held_str, Vector2(8, 78), 11, C_DIM)

	var btn := Button.new()
	btn.position = Vector2(8, h - 38)
	btn.size     = Vector2(w - 16, 30)
	btn.disabled = fainted
	btn.text     = "K.O." if fainted else ("Remplacer" if not inst.held_item.is_empty() else "Donner")
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color",         C_TEXT)
	btn.add_theme_color_override("font_hover_color",   C_GOLD)
	btn.add_theme_color_override("font_pressed_color", C_GOLD)

	var sn := StyleBoxFlat.new()
	sn.bg_color     = Color(0.22, 0.17, 0.09)
	sn.border_color = C_GOLD
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(8)
	var sh := StyleBoxFlat.new()
	sh.bg_color     = Color(0.30, 0.24, 0.12)
	sh.border_color = C_GOLD.lightened(0.3)
	sh.set_border_width_all(2)
	sh.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)

	var captured_idx: int = team_idx
	btn.pressed.connect(func() -> void: member_chosen.emit(captured_idx))
	card.add_child(btn)


func _draw_bar(parent: Node, pos: Vector2, w: float, h: float,
		ratio: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.color    = Color(0.18, 0.14, 0.08)
	bg.position = pos
	bg.size     = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color    = col
	fill.position = pos + Vector2(1, 1)
	fill.size     = Vector2(maxf(0.0, (w - 2) * ratio), h - 2)
	parent.add_child(fill)


func _label(parent: Node, text: String, pos: Vector2,
		font_size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = Vector2(600, 40)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		l.position.x -= 300
		l.size.x      = 1280
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l
