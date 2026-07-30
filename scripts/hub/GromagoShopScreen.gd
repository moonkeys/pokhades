class_name GromagoShopScreen
extends CanvasLayer

## Bazar de Gromago (objets tenus + Super Bonbons) — habillage « bois &
## parchemin » (cf. UiKit). Les objets s'assignent ensuite dans le Pokédex.

signal closed

var _panel:      Panel   = null
var _gold_lbl:   Label   = null
var _cards_root: Control = null


func _ready() -> void:
	layer = 10
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_panel = UiKit.main_panel(Vector2(60, 40), Vector2(1160, 640))
	add_child(_panel)
	UiKit.banner(_panel, "Bazar de Gromago")
	UiKit.pop_in(_panel)

	_gold_lbl = UiKit.label(_panel, "", Vector2(0, 64), 14, UiKit.GOLD, 1160,
		HORIZONTAL_ALIGNMENT_CENTER)

	_cards_root = Control.new()
	_cards_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(_cards_root)
	_refresh_cards()

	var close := UiKit.button("✕  Fermer", Vector2(160, 40), false)
	close.position = Vector2(24, 588)
	close.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(close)


## Retour joueurs : « le menu se ferme et se rouvre violemment après un
## achat ». _rebuild() détruisait TOUT l'écran (voile, cadre, bannière) pour
## le reconstruire à l'identique une frame plus tard — dont un _build()
## qui rejouait l'anim UiKit.pop_in à chaque achat. Un achat ne change que
## le solde et les compteurs "×N" : seule la grille de cartes + le libellé
## de Baies ont besoin d'être rafraîchis, le reste du décor reste en place.
func _refresh_cards() -> void:
	_gold_lbl.text = "◆ %d Baies    ·    Objets à assigner dans « Pokédex & Équipe »" % GameManager.gold

	for c in _cards_root.get_children():
		c.queue_free()

	# Grille 3×N
	var cols   := 3
	var card_w := 366.0
	var card_h := 100.0
	var items := ItemCatalog.ITEMS
	for i in items.size():
		var it: Dictionary = items[i]
		var cx := 18.0 + (i % cols) * (card_w + 12.0)
		var cy := 90.0 + (i / cols) * (card_h + 10.0)
		_build_item_card(it, cx, cy, card_w, card_h)


func _build_item_card(it: Dictionary, x: float, y: float, w: float, h: float) -> void:
	var api:   String = it["api"]
	var owned: int    = GameManager.get_item_count(api)
	var card := UiKit.card(_cards_root, Vector2(x, y), Vector2(w, h))

	var tex := ItemCatalog.icon(api)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture        = tex
		icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position       = Vector2(8, 8)
		icon.size           = Vector2(48, 48)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(icon)

	UiKit.label(card, str(it["name"]), Vector2(64, 8), 15, UiKit.TEXT_DARK, w - 130)
	var desc := UiKit.label(card, str(it["desc"]), Vector2(64, 32), 11,
		UiKit.TEXT_DARK.lightened(0.22), w - 74)
	desc.size.y = 38
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if owned > 0:
		UiKit.label(card, "×%d" % owned, Vector2(w - 52, 8), 16, UiKit.GREEN_DARK, 44)

	UiKit.label(card, "◆ %d" % int(it["price"]), Vector2(64, 72), 13, UiKit.GOLD.darkened(0.25), 100)

	var btn := UiKit.button("Acheter", Vector2(104, 30))
	btn.position = Vector2(w - 116, 62)
	btn.disabled = GameManager.gold < int(it["price"])
	var cap_api := api
	btn.pressed.connect(func() -> void: _buy(cap_api))
	card.add_child(btn)


func _buy(api: String) -> void:
	if GameManager.buy_item(api):
		Sfx.play_file(Sfx.SE_BUY_ITEM)
		_refresh_cards()
		MenuNav.focus_first(self)
