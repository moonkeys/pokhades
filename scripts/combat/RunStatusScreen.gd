class_name RunStatusScreen
extends CanvasLayer

signal bonus_chosen(bonus_id: String)

const C_BG     := Color(0.08, 0.06, 0.03, 0.90)
const C_CARD   := Color(0.14, 0.11, 0.07, 0.95)
const C_GOLD   := Color(0.88, 0.72, 0.25)
const C_TEXT   := Color(0.94, 0.88, 0.72)
const C_DIM    := Color(0.58, 0.50, 0.36)
const C_HP_OK  := Color(0.30, 0.85, 0.40)
const C_HP_LOW := Color(0.90, 0.55, 0.15)
const C_HP_KO  := Color(0.75, 0.20, 0.20)
const C_BOOST  := Color(0.45, 0.90, 0.55)
const C_BONUS  := Color(0.22, 0.17, 0.09)


func setup(team: Array, gold_earned: int, bonuses: Array) -> void:
	layer = 22

	var root := _bg_panel()

	# ── Titre ────────────────────────────────────────────────────────────
	_label(root, "✦  Salle libérée  ✦",
		Vector2(640, 52), 28, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_label(root, "+%d Or" % gold_earned,
		Vector2(640, 90), 18, C_GOLD.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)

	# ── Cartes membres ───────────────────────────────────────────────────
	var live_members: Array = []
	for m in team:
		if is_instance_valid(m):
			live_members.append(m)

	var card_w  := 350.0
	var card_h  := 130.0
	var cols    := 2
	var pad_x   := (1280.0 - cols * card_w) / (cols + 1)
	var start_y := 135.0

	for i in live_members.size():
		var m = live_members[i]
		var inst: PokemonInstance = m.pokemon_instance
		var col := i % cols
		var row := i / cols
		var cx  := pad_x + col * (card_w + pad_x)
		var cy  := start_y + row * (card_h + 16)
		_build_card(root, inst, Vector2(cx, cy), card_w, card_h)

	# ── Bonus à choisir ──────────────────────────────────────────────────
	_label(root, "Choisissez un bonus", Vector2(640, 558), 17, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)

	var btn_w  := 360.0
	var total  := bonuses.size()
	var gap    := (1280.0 - total * btn_w) / (total + 1)

	for i in total:
		var bonus: Dictionary = bonuses[i]
		var label_str: String = bonus.get("bonus_label", "Continuer")
		var bid:       String = bonus.get("bonus", "heal_half")

		var btn := Button.new()
		btn.text     = label_str
		btn.position = Vector2(gap + i * (btn_w + gap), 590)
		btn.size     = Vector2(btn_w, 60)
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color",         C_TEXT)
		btn.add_theme_color_override("font_hover_color",   C_GOLD)
		btn.add_theme_color_override("font_pressed_color", C_GOLD)

		var sn := StyleBoxFlat.new()
		sn.bg_color     = C_BONUS
		sn.border_color = C_GOLD
		sn.set_border_width_all(2)
		sn.set_corner_radius_all(12)
		var sh := StyleBoxFlat.new()
		sh.bg_color     = Color(0.30, 0.24, 0.12)
		sh.border_color = C_GOLD.lightened(0.3)
		sh.set_border_width_all(2)
		sh.set_corner_radius_all(12)
		btn.add_theme_stylebox_override("normal",  sn)
		btn.add_theme_stylebox_override("hover",   sh)
		btn.add_theme_stylebox_override("pressed", sh)

		var capture_bid: String = bid
		btn.pressed.connect(func() -> void: bonus_chosen.emit(capture_bid))
		root.add_child(btn)


func _bg_panel() -> Control:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg


func _build_card(parent: Node, inst: PokemonInstance, pos: Vector2,
		w: float, h: float) -> void:
	var card := Panel.new()
	card.position = pos
	card.size     = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color = C_CARD
	st.border_color = C_GOLD.darkened(0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)

	var fainted := inst.is_fainted()

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture             = inst.portrait_texture
		tex.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position            = Vector2(4, 4)
		tex.size                = Vector2(90, 90)
		tex.modulate.a          = 0.5 if fainted else 1.0
		card.add_child(tex)

	var tx := 104.0
	var name_col := C_HP_KO if fainted else C_TEXT
	_label(card, inst.data.name_fr.capitalize() + ("  [KO]" if fainted else ""),
		Vector2(tx, 8), 17, name_col)
	_label(card, "Niv. %d" % inst.level, Vector2(tx, 30), 14, C_DIM)

	var bar_x   := tx
	var bar_y   := 52.0
	var bar_w   := w - tx - 12.0
	var bar_h   := 12.0
	var ratio   := inst.hp_ratio()
	var bar_col := C_HP_OK if ratio > 0.5 else (C_HP_LOW if ratio > 0.2 else C_HP_KO)
	_draw_bar(card, Vector2(bar_x, bar_y), bar_w, bar_h, ratio, bar_col)
	_label(card, "%d / %d PV" % [inst.current_hp, inst.max_hp],
		Vector2(tx, 67), 12, C_DIM)

	var boosts: Array[String] = []
	if inst.attack_mult  > 1.05: boosts.append("ATQ ×%.1f" % inst.attack_mult)
	if inst.defense_mult > 1.05: boosts.append("DEF ×%.1f" % inst.defense_mult)
	if inst.speed_mult   > 1.05: boosts.append("VIT ×%.1f" % inst.speed_mult)
	if inst.max_hp_mult  > 1.05: boosts.append("PV ×%.1f" % inst.max_hp_mult)
	if not boosts.is_empty():
		_label(card, "✦ " + "  ".join(boosts), Vector2(tx, 86), 12, C_BOOST)


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
