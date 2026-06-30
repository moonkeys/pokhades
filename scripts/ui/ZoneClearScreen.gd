class_name ZoneClearScreen
extends CanvasLayer

signal bonus_picked(bonus_id: String)

const C_BG     := Color(0.10, 0.08, 0.05, 0.88)
const C_PANEL  := Color(0.91, 0.85, 0.70)
const C_BORDER := Color(0.62, 0.50, 0.32)
const C_GOLD   := Color(0.76, 0.53, 0.17)
const C_TEXT   := Color(0.18, 0.13, 0.06)
const C_DIM    := Color(0.48, 0.38, 0.22)

const ALL_BONUSES: Array[Dictionary] = [
	{"id": "heal_full",  "name": "Soin Complet",    "icon": "❤",  "color": Color(0.82, 0.18, 0.18), "desc": "Toute l'équipe récupère l'intégralité de ses PV."},
	{"id": "heal_half",  "name": "Premiers Soins",   "icon": "✚",  "color": Color(0.70, 0.35, 0.70), "desc": "Toute l'équipe récupère 50 % de ses PV manquants."},
	{"id": "boost_hp",   "name": "Vigueur",           "icon": "◆",  "color": Color(0.18, 0.70, 0.35), "desc": "PV maximum +20 % pour toute l'équipe (permanent dans la run)."},
	{"id": "boost_atk",  "name": "Puissance Brute",   "icon": "▲",  "color": Color(0.90, 0.50, 0.10), "desc": "Attaque +20 % pour toute l'équipe (permanent dans la run)."},
	{"id": "boost_def",  "name": "Carapace",           "icon": "▣",  "color": Color(0.30, 0.50, 0.90), "desc": "Défense +20 % pour toute l'équipe (permanent dans la run)."},
	{"id": "boost_spd",  "name": "Célérité",           "icon": "★",  "color": Color(0.90, 0.85, 0.10), "desc": "Vitesse +20 % — vos Pokémon enchaînent les attaques plus vite."},
]

var _selected_id: String = ""
var _card_panels: Array  = []
var _confirm_btn: Button = null
var _offered: Array[Dictionary] = []


func _ready() -> void:
	layer = 20
	var pool: Array[Dictionary] = ALL_BONUSES.duplicate()
	pool.shuffle()
	for i in 3:
		_offered.append(pool[i])
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Titre
	var title: Label = _lbl("★  ZONE 1 LIBÉRÉE  ★", 44, C_GOLD, root)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 22)
	title.size     = Vector2(1280, 66)

	var sub: Label = _lbl("Choisissez votre récompense pour la prochaine zone", 21, C_DIM, root)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 96)
	sub.size     = Vector2(1280, 34)

	# 3 cartes centrées
	var card_w: int  = 340
	var card_h: int  = 430
	var gap: int     = 45
	var total_w: int = card_w * 3 + gap * 2
	var start_x: int = (1280 - total_w) / 2

	for i in 3:
		var bonus: Dictionary = _offered[i]
		var cx: int = start_x + i * (card_w + gap)
		_build_card(root, bonus, cx, 140, card_w, card_h, i)

	# Bouton confirmer
	_confirm_btn = Button.new()
	_confirm_btn.text    = "CONFIRMER ▶"
	_confirm_btn.position = Vector2(880, 628)
	_confirm_btn.size     = Vector2(300, 50)
	_confirm_btn.visible  = false
	_confirm_btn.add_theme_font_size_override("font_size", 22)
	_confirm_btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	var sb_cn := StyleBoxFlat.new()
	sb_cn.bg_color                   = C_GOLD
	sb_cn.corner_radius_top_left     = 6
	sb_cn.corner_radius_top_right    = 6
	sb_cn.corner_radius_bottom_left  = 6
	sb_cn.corner_radius_bottom_right = 6
	_confirm_btn.add_theme_stylebox_override("normal", sb_cn)
	var sb_ch := StyleBoxFlat.new()
	sb_ch.bg_color                   = C_GOLD.lightened(0.15)
	sb_ch.corner_radius_top_left     = 6
	sb_ch.corner_radius_top_right    = 6
	sb_ch.corner_radius_bottom_left  = 6
	sb_ch.corner_radius_bottom_right = 6
	_confirm_btn.add_theme_stylebox_override("hover", sb_ch)
	_confirm_btn.pressed.connect(func() -> void:
		bonus_picked.emit(_selected_id)
	)
	root.add_child(_confirm_btn)


func _build_card(parent: Control, bonus: Dictionary, x: int, y: int, w: int, h: int, idx: int) -> void:
	var accent: Color = bonus["color"]

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	var sb_c := StyleBoxFlat.new()
	sb_c.bg_color                   = C_PANEL
	sb_c.border_color               = C_BORDER
	sb_c.border_width_left          = 2
	sb_c.border_width_right         = 2
	sb_c.border_width_top           = 2
	sb_c.border_width_bottom        = 2
	sb_c.corner_radius_top_left     = 10
	sb_c.corner_radius_top_right    = 10
	sb_c.corner_radius_bottom_left  = 10
	sb_c.corner_radius_bottom_right = 10
	card.add_theme_stylebox_override("panel", sb_c)
	parent.add_child(card)
	_card_panels.append(card)

	# Barre d'accent en haut
	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size     = Vector2(w, 10)
	var sb_bar := StyleBoxFlat.new()
	sb_bar.bg_color                   = accent
	sb_bar.corner_radius_top_left     = 10
	sb_bar.corner_radius_top_right    = 10
	bar.add_theme_stylebox_override("panel", sb_bar)
	card.add_child(bar)

	# Icône
	var icon_lbl: Label = _lbl(bonus["icon"], 62, accent, card)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(0, 28)
	icon_lbl.size     = Vector2(w, 88)

	# Nom
	var name_lbl: Label = _lbl(bonus["name"], 26, C_TEXT, card)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0, 126)
	name_lbl.size     = Vector2(w, 40)

	# Séparateur
	var sep := ColorRect.new()
	sep.color    = C_BORDER
	sep.position = Vector2(24, 166)
	sep.size     = Vector2(w - 48, 1)
	card.add_child(sep)

	# Description
	var desc_lbl: Label = _lbl(bonus["desc"], 16, C_DIM, card)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(20, 176)
	desc_lbl.size     = Vector2(w - 40, 120)

	# Bouton choisir
	var btn := Button.new()
	btn.text     = "CHOISIR"
	btn.position = Vector2(24, h - 66)
	btn.size     = Vector2(w - 48, 48)
	btn.add_theme_font_size_override("font_size", 19)
	btn.add_theme_color_override("font_color", C_TEXT)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color                   = accent.darkened(0.3)
	sb_n.border_color               = accent
	sb_n.border_width_left          = 2
	sb_n.border_width_right         = 2
	sb_n.border_width_top           = 2
	sb_n.border_width_bottom        = 2
	sb_n.corner_radius_top_left     = 6
	sb_n.corner_radius_top_right    = 6
	sb_n.corner_radius_bottom_left  = 6
	sb_n.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", sb_n)
	var sb_h := StyleBoxFlat.new()
	sb_h.bg_color                   = accent.darkened(0.1)
	sb_h.corner_radius_top_left     = 6
	sb_h.corner_radius_top_right    = 6
	sb_h.corner_radius_bottom_left  = 6
	sb_h.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("hover", sb_h)
	var bid: String = bonus["id"]
	btn.pressed.connect(func() -> void:
		_select_bonus(bid, idx)
	)
	card.add_child(btn)


func _select_bonus(bonus_id: String, selected_idx: int) -> void:
	_selected_id         = bonus_id
	_confirm_btn.visible = true

	for i in _card_panels.size():
		var card: Panel = _card_panels[i] as Panel
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color                   = C_PANEL
		sb.corner_radius_top_left     = 10
		sb.corner_radius_top_right    = 10
		sb.corner_radius_bottom_left  = 10
		sb.corner_radius_bottom_right = 10
		if i == selected_idx:
			sb.border_color              = C_GOLD
			sb.border_width_left         = 3
			sb.border_width_right        = 3
			sb.border_width_top          = 3
			sb.border_width_bottom       = 3
		else:
			sb.border_color              = C_BORDER
			sb.border_width_left         = 2
			sb.border_width_right        = 2
			sb.border_width_top          = 2
			sb.border_width_bottom       = 2
		card.add_theme_stylebox_override("panel", sb)


func _lbl(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
