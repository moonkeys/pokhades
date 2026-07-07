class_name GromagoShopScreen
extends CanvasLayer

## Boutique d'objets de Gromago (hub) — achat d'objets tenus et de Super
## Bonbons contre des Baies. Les objets achetés vont dans l'inventaire
## persistant (GameManager.item_inventory) et s'assignent ensuite à un
## Pokémon dans l'écran "Pokédex & Équipe". Achat multi-exemplaires libre.

signal closed

const C_BG     := Color(0.04, 0.03, 0.02, 0.82)
const C_PANEL  := Color(0.10, 0.075, 0.045, 0.96)
const C_BORDER := Color(0.62, 0.50, 0.32)
const C_TEXT   := Color(0.96, 0.92, 0.80)
const C_DIM    := Color(0.62, 0.55, 0.42)
const C_GOLD   := Color(0.92, 0.72, 0.25)
const C_GOLD_LT:= Color(0.94, 0.88, 0.72)
const C_GOOD   := Color(0.38, 0.82, 0.45)


func _ready() -> void:
	layer = 10
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(60, 40)
	panel.size     = Vector2(1160, 640)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1160, 72)
	_style_col(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	_lbl(panel, "🛍  BAZAR DE GROMAGO", 24, 14, 700, 44, 22, C_GOLD_LT)
	_lbl(panel, "◆ %d Baies" % GameManager.gold, 900, 22, 230, 28, 16, C_GOLD)
	_lbl(panel, "Objets à assigner à un Pokémon dans « Pokédex & Équipe »",
		24, 54, 820, 20, 12, C_DIM)

	# Grille 3×N
	var cols   := 3
	var card_w := 366.0
	var card_h := 100.0
	var gap_x  := 12.0
	var gap_y  := 10.0
	var ox     := 18.0
	var oy     := 82.0

	var items := ItemCatalog.ITEMS
	for i in items.size():
		var it: Dictionary = items[i]
		var col := i % cols
		var row := i / cols
		var cx  := ox + col * (card_w + gap_x)
		var cy  := oy + row * (card_h + gap_y)
		_build_item_card(panel, it, cx, cy, card_w, card_h)

	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 598)
	close.size     = Vector2(160, 36)
	close.add_theme_font_size_override("font_size", 15)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


func _build_item_card(parent: Node, it: Dictionary, x: float, y: float,
		w: float, h: float) -> void:
	var api:   String = it["api"]
	var owned: int    = GameManager.get_item_count(api)

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	var accent := C_GOLD if it["kind"] == "held" else Color(0.85, 0.40, 0.55)
	_style(card, Color(0.16, 0.12, 0.07), accent, 8)
	parent.add_child(card)

	# Icône
	var tex := ItemCatalog.icon(api)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture        = tex
		icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position       = Vector2(8, 8)
		icon.size           = Vector2(48, 48)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(icon)

	_lbl(card, it["name"], 64, 8, w - 130, 22, 15, C_TEXT)
	_lbl(card, it["desc"], 64, 34, w - 74, 40, 11, C_DIM)

	# Compteur possédé
	if owned > 0:
		_lbl(card, "×%d" % owned, w - 56, 8, 48, 22, 16, C_GOOD)

	# Prix + bouton achat
	_lbl(card, "%d Baies" % int(it["price"]), 64, 76, 120, 18, 12, C_GOLD)

	var can_buy := GameManager.gold >= int(it["price"])
	var btn := Button.new()
	btn.text     = "Acheter"
	btn.position = Vector2(w - 116, 68)
	btn.size     = Vector2(104, 26)
	btn.disabled = not can_buy
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", C_GOLD if can_buy else C_DIM)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.22, 0.17, 0.09)
	sn.border_color = C_GOLD if can_buy else C_BORDER
	sn.set_border_width_all(2); sn.set_corner_radius_all(6)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.24, 0.12)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover",  sh)
	var cap_api := api
	btn.pressed.connect(func() -> void: _buy(cap_api))
	card.add_child(btn)


func _buy(api: String) -> void:
	if GameManager.buy_item(api):
		Sfx.play("coin", -4.0)
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child is MenuNav:
			continue
		child.queue_free()
	await get_tree().process_frame
	_build()
	MenuNav.focus_first(self)


# ── Helpers UI ────────────────────────────────────────────────────────

func _lbl(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2); s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _style_col(p: Panel, bg: Color, radius: int, top_only: bool = false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if top_only:
		s.corner_radius_top_left = radius
		s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.30, 0.24, 0.12)
	s.border_color = C_BORDER
	s.set_border_width_all(1); s.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
