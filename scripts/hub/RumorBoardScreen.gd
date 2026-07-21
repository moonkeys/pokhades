class_name RumorBoardScreen
extends CanvasLayer
## Tableau des rumeurs — missions de libération FACULTATIVES entre les runs
## (cf. MissionManager). Trois rumeurs affichées : récit, avancement, récompense
## et bouton « Réclamer » actif une fois la mission accomplie. Réclamer verse la
## récompense et fait apparaître une nouvelle rumeur EN PLACE. Même kit visuel
## que tous les écrans du hub (UiKit) et navigable au clavier (MenuNav).

signal closed
## Une récompense a été réclamée → le hub rafraîchit son bandeau (Baies/Éclats).
signal reward_claimed

const C_DIM   := Color(0.62, 0.55, 0.42)
const C_GOLD  := Color(0.95, 0.76, 0.31)
const C_CREAM := Color(0.96, 0.90, 0.78)
const C_GOOD  := Color(0.42, 0.82, 0.48)
const C_BAR_BG := Color(0, 0, 0, 0.45)

const CARD_W := 620.0
const CARD_H := 132.0
const CARD_X := 30.0
const CARD_Y0 := 76.0
const CARD_GAP := 12.0

var _panel: Panel = null


func _ready() -> void:
	MissionManager.ensure_board()
	add_child(MenuNav.make(func() -> void: closed.emit()))
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_panel = UiKit.main_panel(Vector2(320, 60), Vector2(680, 600))
	add_child(_panel)
	UiKit.banner(_panel, "Tableau des Rumeurs")
	UiKit.pop_in(_panel)
	UiKit.label(_panel, "Missions de libération — facultatives, elles récompensent la rébellion.",
		Vector2(30, 58), 13, C_DIM, 620, HORIZONTAL_ALIGNMENT_LEFT, true)

	_build_cards()

	var close := UiKit.button("✕  Fermer", Vector2(200, 44), false)
	close.position = Vector2(240, 534)
	close.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(close)


## Reconstruit uniquement les cartes (après une réclamation), en laissant le
## reste du panneau intact — le focus est ensuite recollé par _ensure_focus.
func _build_cards() -> void:
	for c in _panel.get_children():
		if c is Control and (c as Control).name.begins_with("Rumor"):
			c.queue_free()

	var n := MissionManager.slot_count()
	if n == 0:
		var lbl := UiKit.label(_panel, "Toutes les rumeurs ont été suivies. Reviens plus tard…",
			Vector2(30, 120), 15, C_DIM, 620, HORIZONTAL_ALIGNMENT_CENTER, true)
		lbl.name = "RumorEmpty"
		return

	for i in n:
		_build_card(i)


func _build_card(i: int) -> void:
	var view := MissionManager.slot(i)
	var d: Dictionary = view["def"]
	var done: bool = view["done"]

	var card := UiKit.dark_card(_panel, Vector2(CARD_X, CARD_Y0 + i * (CARD_H + CARD_GAP)),
		Vector2(CARD_W, CARD_H))
	card.name = "RumorCard%d" % i

	UiKit.label(card, str(d["title"]), Vector2(16, 12), 17, C_CREAM, 400)
	var reward := "+%d Baies" % int(d["gold"])
	if int(d["shards"]) > 0:
		reward += "  ·  +%d Éclat%s" % [int(d["shards"]), "s" if int(d["shards"]) > 1 else ""]
	UiKit.label(card, "🏅 " + reward, Vector2(360, 14), 13, C_GOLD, 244, HORIZONTAL_ALIGNMENT_RIGHT)

	UiKit.label(card, str(d["rumor"]), Vector2(16, 40), 13, C_DIM, 590,
		HORIZONTAL_ALIGNMENT_LEFT, true)

	# Barre d'avancement + compteur.
	var frac := float(view["current"]) / maxf(1.0, float(view["target"]))
	var col := C_GOOD if done else C_GOLD
	_bar(card, 16, 100, 420, frac, col)
	var cnt: String = "✔ Prêt !" if done else "%d / %d" % [view["current"], view["target"]]
	UiKit.label(card, cnt, Vector2(444, 92), 14, col, 160, HORIZONTAL_ALIGNMENT_LEFT)

	# Bouton Réclamer — actif seulement une fois la mission accomplie.
	var btn := UiKit.button("Réclamer", Vector2(150, 40), true)
	btn.position = Vector2(CARD_W - 166, 84)
	btn.disabled = not done
	var idx := i
	btn.pressed.connect(func() -> void: _claim(idx))
	card.add_child(btn)


func _claim(i: int) -> void:
	var got := MissionManager.claim(i)
	if got.is_empty():
		return
	Sfx.play_file(Sfx.SE_BUY_ITEM, -4.0)
	reward_claimed.emit()
	_build_cards()
	call_deferred("_ensure_focus")


func _ensure_focus() -> void:
	if get_viewport() != null and get_viewport().gui_get_focus_owner() == null:
		MenuNav.focus_first(self)


func _bar(parent: Control, x: float, y: float, w: float, frac: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.position = Vector2(x, y)
	bg.size = Vector2(w, 10)
	bg.color = C_BAR_BG
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(x, y)
	fill.size = Vector2(maxf(2.0, w * clampf(frac, 0.0, 1.0)), 10)
	fill.color = col
	parent.add_child(fill)
