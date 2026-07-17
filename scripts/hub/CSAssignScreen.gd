class_name CSAssignScreen
extends CanvasLayer

signal closed

const C_BG      := Color(0.10, 0.08, 0.05, 0.90)
const C_PANEL   := Color(0.91, 0.85, 0.70)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.18, 0.13, 0.06)
const C_DIM     := Color(0.48, 0.38, 0.22)
const C_GOLD    := Color(0.76, 0.53, 0.17)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)
const C_OWNED   := Color(0.22, 0.60, 0.28)

var _gold_lbl:     Label = null
var _feedback_lbl: Label = null
var _section_root: Control = null
var _name_cache:   Dictionary = {}   # pid -> nom FR (résolu async)


func _ready() -> void:
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(80, 40)
	panel.size     = Vector2(1120, 640)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1120, 72)
	_style_color(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	panel.add_child(_lbl("⛰  MAÎTRE DES CS", 24, 14, 700, 44, 24, C_GOLD_LT))
	_gold_lbl = _lbl("◆ %d or" % GameManager.gold, 860, 18, 220, 36, 20, C_GOLD_LT, true)
	panel.add_child(_gold_lbl)

	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 576)
	close.size     = Vector2(180, 44)
	close.add_theme_font_size_override("font_size", UiKit.scaled_font(16))
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)

	_feedback_lbl = _lbl("", 220, 578, 680, 36, 15, C_OWNED, true)
	panel.add_child(_feedback_lbl)

	_section_root = Control.new()
	_section_root.position = Vector2(0, 0)
	_section_root.size     = Vector2(1120, 560)
	panel.add_child(_section_root)

	# Pré-résout les noms de l'équipe pour les boutons d'attribution
	for pid in GameManager.hub_team:
		_resolve_name(pid)

	_rebuild_sections()


func _rebuild_sections() -> void:
	for c in _section_root.get_children():
		c.queue_free()

	var y := 88.0
	for def: Dictionary in GameManager.CS_CATALOG:
		_build_cs_section(def, y)
		y += 168.0
	MenuNav.focus_first(self)   # les boutons viennent d'être recréés : le focus est à reposer


func _build_cs_section(def: Dictionary, y: float) -> void:
	var cs_id: String = def["id"]
	var accent: Color = def["sym_color"]

	var card := Panel.new()
	card.position = Vector2(24, y)
	card.size     = Vector2(1072, 152)
	_style(card, Color(0.86, 0.80, 0.65), C_BORDER, 10)
	_section_root.add_child(card)

	var bar := Panel.new()
	bar.size = Vector2(1072, 8)
	_style_color(bar, accent, 10, true)
	card.add_child(bar)

	card.add_child(_lbl(def["sym"], 16, 14, 46, 40, 30, accent))
	card.add_child(_lbl(def["name"], 64, 16, 240, 28, 18, C_TEXT))
	var desc: Label = _lbl(def["desc"], 16, 48, 540, 50, 13, C_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	if not GameManager.owns_cs(cs_id):
		var price: int = def["price"]
		card.add_child(_lbl("◆ %d or" % price, 16, 100, 140, 28, 15, C_GOLD))
		var buy := Button.new()
		buy.text     = "Acheter"
		buy.position = Vector2(900, 100)
		buy.size     = Vector2(150, 38)
		buy.add_theme_font_size_override("font_size", UiKit.scaled_font(15))
		buy.add_theme_color_override("font_color", C_TEXT)
		_btn_buy(buy)
		buy.pressed.connect(func() -> void: _buy(cs_id, def["name"], price))
		card.add_child(buy)
		return

	var holder_pid: int = GameManager.get_cs_holder(cs_id)
	var holder_str: String = "Aucun Pokémon" if holder_pid == 0 else _name_cache.get(holder_pid, "Pokémon #%d" % holder_pid)
	card.add_child(_lbl("Détenue par : %s" % holder_str, 580, 16, 480, 24, 14, C_OWNED))

	if GameManager.hub_team.is_empty():
		card.add_child(_lbl("Compose ton équipe avant d'assigner une CS.", 580, 48, 480, 24, 12, C_DIM))
		return

	var bx := 580.0
	var by := 80.0
	var bw := 150.0
	var cols := 3
	for i in GameManager.hub_team.size():
		var pid: int = GameManager.hub_team[i]
		var col := i % cols
		var row := i / cols
		var btn := Button.new()
		var is_holder := holder_pid == pid
		var nm: String = _name_cache.get(pid, "Pokémon #%d" % pid)
		btn.text     = ("✓ " + nm) if is_holder else nm
		btn.position = Vector2(bx + col * (bw + 10), by + row * 36)
		btn.size     = Vector2(bw, 30)
		btn.add_theme_font_size_override("font_size", UiKit.scaled_font(12))
		btn.add_theme_color_override("font_color", C_TEXT)
		if is_holder:
			_btn_owned(btn)
		else:
			_btn_neutral(btn)
		var captured_pid: int = pid
		btn.pressed.connect(func() -> void: _assign(cs_id, captured_pid, def["name"], nm))
		card.add_child(btn)


func _buy(id: String, name: String, price: int) -> void:
	if GameManager.spend_gold(price):
		GameManager.owned_items.append(id)
		_gold_lbl.text = "◆ %d or" % GameManager.gold
		_show_feedback("✓  %s acheté ! Choisis maintenant qui la porte." % name, true)
		_rebuild_sections()
	else:
		_show_feedback("✗  Pas assez d'or (%d requis)" % price, false)


func _assign(cs_id: String, pid: int, cs_name: String, pkmn_name: String) -> void:
	GameManager.assign_cs(cs_id, pid)
	_show_feedback("✓  %s confiée à %s !" % [cs_name, pkmn_name], true)
	_rebuild_sections()


func _resolve_name(pid: int) -> void:
	if _name_cache.has(pid):
		return
	PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
		if data.is_empty():
			return
		_name_cache[pid] = str(data.get("name_fr", "Pokémon #%d" % pid)).capitalize()
		_rebuild_sections()
	)


func _show_feedback(msg: String, success: bool) -> void:
	_feedback_lbl.text = msg
	_feedback_lbl.add_theme_color_override("font_color",
		C_OWNED if success else Color(0.80, 0.20, 0.20))
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(_feedback_lbl):
			_feedback_lbl.text = ""
	)


# ── Helpers (calqués sur ShopScreen.gd) ────────────────────────────────

func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.20); s.shadow_size = 5
	p.add_theme_stylebox_override("panel", s)


func _style_color(p: Panel, bg: Color, radius: int, top_only: bool = false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if top_only:
		s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _btn_buy(btn: Button) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_GOLD.lightened(0.15); sn.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_GOLD.lightened(0.30)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = C_GOLD.darkened(0.10)
	btn.add_theme_stylebox_override("pressed", sp)


func _btn_owned(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = C_OWNED.lightened(0.10); s.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.74, 0.66, 0.52); s.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.82, 0.74, 0.60)
	btn.add_theme_stylebox_override("hover", sh)
