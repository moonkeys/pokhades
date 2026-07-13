class_name ShopScreen
extends CanvasLayer

## Boutique de Mira (hub) — habillage « bois & parchemin » (cf. UiKit).

signal closed

var _gold_lbl: Label = null
var _feedback_lbl: Label = null
var _panel: Panel = null


func _ready() -> void:
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_panel = UiKit.main_panel(Vector2(80, 40), Vector2(1120, 640))
	add_child(_panel)
	UiKit.banner(_panel, "Boutique de Mira")
	UiKit.pop_in(_panel)

	_gold_lbl = UiKit.label(_panel, "◆ %d Baies" % GameManager.gold,
		Vector2(0, 66), 18, UiKit.GOLD, 1120, HORIZONTAL_ALIGNMENT_CENTER)

	var close := UiKit.button("✕  Fermer", Vector2(180, 44), false)
	close.position = Vector2(24, 576)
	close.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(close)

	_feedback_lbl = UiKit.label(_panel, "", Vector2(220, 584), 15, UiKit.GREEN,
		680, HORIZONTAL_ALIGNMENT_CENTER)

	# Grille des items (2 rangées × 3 colonnes)
	var iw: int = 320
	var ih: int = 210
	var gap: int = 24
	var sx: int = (1120 - (3 * iw + 2 * gap)) / 2
	for idx in GameManager.SHOP_CATALOG.size():
		var def: Dictionary = GameManager.SHOP_CATALOG[idx]
		var cx: int = sx + (idx % 3) * (iw + gap)
		var cy: int = 96 + (idx / 3) * (ih + gap)
		_build_item(def, cx, cy, iw, ih)


func _build_item(def: Dictionary, x: int, y: int, w: int, h: int) -> void:
	var accent: Color = def["sym_color"]
	var card := UiKit.card(_panel, Vector2(x, y), Vector2(w, h))

	# Barre d'accent en tête de carte
	var bar := Panel.new()
	bar.position = Vector2(3, 3)
	bar.size     = Vector2(w - 6, 8)
	bar.add_theme_stylebox_override("panel", UiKit.style(accent, accent.darkened(0.3), 6, 1))
	card.add_child(bar)

	UiKit.icon_square(card, Vector2(14, 20), str(def["sym"]), 42.0)
	UiKit.label(card, str(def["name"]), Vector2(66, 28), 17, UiKit.TEXT_DARK, w - 80)
	var desc := UiKit.label(card, str(def["desc"]), Vector2(14, 70), 13,
		UiKit.TEXT_DARK.lightened(0.22), w - 28)
	desc.size.y = 66
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	UiKit.label(card, "◆ %d Baies" % int(def["price"]), Vector2(14, 148), 15,
		UiKit.GOLD.darkened(0.25), 150)

	var btn := UiKit.button("Acheter", Vector2(112, 36))
	btn.position = Vector2(w - 126, 144)
	var item_id: String = def["id"]
	var item_name: String = def["name"]
	var price: int = def["price"]
	btn.pressed.connect(func() -> void: _buy(item_id, item_name, price))
	card.add_child(btn)


func _buy(id: String, item_name: String, price: int) -> void:
	if GameManager.spend_gold(price):
		Sfx.play_file(Sfx.SE_BUY_ITEM)
		GameManager.owned_items.append(id)
		_gold_lbl.text = "◆ %d Baies" % GameManager.gold
		_show_feedback("✓  %s acheté !" % item_name, true)
	else:
		_show_feedback("✗  Pas assez de Baies (%d requises)" % price, false)


func _show_feedback(msg: String, success: bool) -> void:
	_feedback_lbl.text = msg
	_feedback_lbl.add_theme_color_override("font_color",
		UiKit.GREEN if success else UiKit.RED_SOFT)
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(_feedback_lbl):
			_feedback_lbl.text = ""
	)
