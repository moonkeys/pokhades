class_name ShopScreen
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

var _gold_lbl: Label = null
var _feedback_lbl: Label = null


func _ready() -> void:
	_build()


func _build() -> void:
	# Fond
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Panel principal
	var panel := Panel.new()
	panel.position = Vector2(80, 40)
	panel.size     = Vector2(1120, 640)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	# Header
	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1120, 72)
	_style_color(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	var title: Label = _lbl("◈  BOUTIQUE DE MIRA", 24, 14, 700, 44, 24, C_GOLD_LT)
	panel.add_child(title)

	_gold_lbl = _lbl("◆ %d or" % GameManager.gold, 860, 18, 220, 36, 20, C_GOLD_LT, true)
	panel.add_child(_gold_lbl)

	# Bouton fermer
	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 576)
	close.size     = Vector2(180, 44)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)

	# Feedback achat
	_feedback_lbl = _lbl("", 220, 578, 680, 36, 15, C_OWNED, true)
	panel.add_child(_feedback_lbl)

	# Grille des items (2 rangées × 3 colonnes)
	var iw: int = 320
	var ih: int = 210
	var gap: int = 24
	var area_w: int = 3 * iw + 2 * gap
	var sx: int = (1120 - area_w) / 2

	for idx in GameManager.SHOP_CATALOG.size():
		var def: Dictionary = GameManager.SHOP_CATALOG[idx]
		var col: int = idx % 3
		var row: int = idx / 3
		var cx: int = sx + col * (iw + gap)
		var cy: int = 90 + row * (ih + gap)
		_build_item(panel, def, cx, cy, iw, ih)


func _build_item(parent: Panel, def: Dictionary, x: int, y: int, w: int, h: int) -> void:
	var accent: Color = def["sym_color"]

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	_style(card, Color(0.86, 0.80, 0.65), C_BORDER, 10)
	parent.add_child(card)

	# Accent top bar
	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size     = Vector2(w, 8)
	_style_color(bar, accent, 10, true)
	card.add_child(bar)

	# Symbole + nom sur la même ligne
	var sym: Label = _lbl(def["sym"], 14, 16, 46, 40, 34, accent)
	card.add_child(sym)
	var nm: Label = _lbl(def["name"], 60, 22, w - 74, 28, 17, C_TEXT)
	card.add_child(nm)

	# Description
	var desc: Label = _lbl(def["desc"], 12, 62, w - 24, 72, 13, C_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	# Prix + bouton
	var price_lbl: Label = _lbl("◆ %d or" % def["price"], 12, 140, 140, 28, 15, C_GOLD)
	card.add_child(price_lbl)

	var btn := Button.new()
	btn.text     = "Acheter"
	btn.position = Vector2(w - 120, 138)
	btn.size     = Vector2(108, 32)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", C_TEXT)
	_btn_buy(btn, accent)
	var item_id: String = def["id"]
	var item_name: String = def["name"]
	var price: int = def["price"]
	btn.pressed.connect(func() -> void: _buy(item_id, item_name, price))
	card.add_child(btn)


func _buy(id: String, name: String, price: int) -> void:
	if GameManager.spend_gold(price):
		GameManager.owned_items.append(id)
		_gold_lbl.text = "◆ %d or" % GameManager.gold
		_show_feedback("✓  %s acheté !" % name, true)
	else:
		_show_feedback("✗  Pas assez d'or (%d requis)" % price, false)


func _show_feedback(msg: String, success: bool) -> void:
	_feedback_lbl.text = msg
	_feedback_lbl.add_theme_color_override("font_color",
		C_OWNED if success else Color(0.80, 0.20, 0.20))
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(_feedback_lbl):
			_feedback_lbl.text = ""
	)


# ── Helpers ─────────────────────────────────────────────────────────

func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
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


func _btn_buy(btn: Button, accent: Color) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_GOLD.lightened(0.15); sn.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_GOLD.lightened(0.30)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = C_GOLD.darkened(0.10)
	btn.add_theme_stylebox_override("pressed", sp)


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.74, 0.66, 0.52); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.82, 0.74, 0.60)
	btn.add_theme_stylebox_override("hover", sh)
