class_name MoveShopScreen
extends CanvasLayer

signal closed

const C_BG     := Color(0.10, 0.08, 0.05, 0.90)
const C_PANEL  := Color(0.91, 0.85, 0.70)
const C_BORDER := Color(0.62, 0.50, 0.32)
const C_TEXT   := Color(0.18, 0.13, 0.06)
const C_DIM    := Color(0.48, 0.38, 0.22)
const C_GOLD   := Color(0.76, 0.53, 0.17)
const C_GOLD_LT:= Color(0.94, 0.88, 0.72)
const C_GOOD   := Color(0.20, 0.68, 0.35)

const MOVE_LIST: Array[Dictionary] = [
	# Capacités utilitaires / HM-like
	{"api": "cut",          "label": "Coupe",           "type": "normal",   "price": 60},
	{"api": "strength",     "label": "Force",           "type": "normal",   "price": 80},
	{"api": "surf",         "label": "Surf",            "type": "water",    "price": 120},
	{"api": "waterfall",    "label": "Chute d'Eau",     "type": "water",    "price": 90},
	# Attaques physiques
	{"api": "earthquake",   "label": "Séisme",          "type": "ground",   "price": 150},
	{"api": "iron-tail",    "label": "Kro-Kqueue",      "type": "steel",    "price": 120},
	{"api": "aerial-ace",   "label": "Jackpot Aérien",  "type": "flying",   "price": 80},
	{"api": "rock-slide",   "label": "Rockblast",       "type": "rock",     "price": 90},
	{"api": "brick-break",  "label": "Destructor",      "type": "fighting", "price": 90},
	{"api": "shadow-claw",  "label": "Griffe d'Ombre",  "type": "ghost",    "price": 100},
	# Attaques spéciales
	{"api": "flamethrower", "label": "Lance-Flammes",   "type": "fire",     "price": 100},
	{"api": "ice-beam",     "label": "Laser Glace",     "type": "ice",      "price": 100},
	{"api": "thunderbolt",  "label": "Tonnerre",        "type": "electric", "price": 100},
	{"api": "psychic",      "label": "Psyko",           "type": "psychic",  "price": 100},
	{"api": "shadow-ball",  "label": "Ball'Ombre",      "type": "ghost",    "price": 120},
	{"api": "dragon-pulse", "label": "Dracochoc",       "type": "dragon",   "price": 150},
	# Buffs / statut
	{"api": "swords-dance", "label": "Danse-Lames",     "type": "normal",   "price": 200},
	{"api": "calm-mind",    "label": "Méditation",      "type": "psychic",  "price": 200},
	{"api": "protect",      "label": "Protection",      "type": "normal",   "price": 120},
	{"api": "recover",      "label": "Récupération",    "type": "normal",   "price": 180},
]


func _ready() -> void:
	layer = 10
	_build()


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

	_lbl(panel, "✦  TUTEUR DE CAPACITÉS", 24, 14, 700, 44, 22, C_GOLD_LT)
	_lbl(panel, "◆ %d Baies" % GameManager.gold, 900, 22, 230, 28, 16, C_GOLD)
	_lbl(panel, "Capacités achetées disponibles dès le départ de chaque run",
		24, 54, 800, 20, 12, C_DIM)

	# Les CS (Capacités Spéciales) ont fusionné ici — l'ancien PNJ "Maître
	# des CS" a été retiré du hub, son écran s'ouvre par ce bouton.
	var cs_btn := Button.new()
	cs_btn.text     = "⛰  CS / Capacités Spéciales"
	cs_btn.position = Vector2(620, 16)
	cs_btn.size     = Vector2(260, 40)
	cs_btn.add_theme_font_size_override("font_size", 15)
	cs_btn.add_theme_color_override("font_color", C_GOLD_LT)
	_btn_neutral(cs_btn)
	cs_btn.pressed.connect(_open_cs_screen)
	panel.add_child(cs_btn)

	# Grille 4×5
	var cols   := 4
	var card_w := 270.0
	var card_h := 86.0
	var gap_x  := 12.0
	var gap_y  := 10.0
	var ox     := 18.0
	var oy     := 80.0

	for i in MOVE_LIST.size():
		var m: Dictionary = MOVE_LIST[i]
		var col := i % cols
		var row := i / cols
		var cx  := ox + col * (card_w + gap_x)
		var cy  := oy + row * (card_h + gap_y)
		_build_move_card(panel, m, cx, cy, card_w, card_h)

	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 598)
	close.size     = Vector2(160, 36)
	close.add_theme_font_size_override("font_size", 15)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


func _build_move_card(parent: Node, m: Dictionary, x: float, y: float,
		w: float, h: float) -> void:
	var api:    String  = m["api"]
	var label:  String  = m["label"]
	var mtype:  String  = m.get("type", "normal")
	var price:  int     = m["price"]
	var bought: bool    = api in GameManager.purchased_move_names

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	_style(card,
		Color(0.85, 0.78, 0.63) if bought else Color(0.78, 0.70, 0.55),
		C_GOLD if not bought else C_GOOD, 8)
	parent.add_child(card)

	# Logo de type
	var tpill := TypeIcon.make_pill(mtype, 78.0, 24.0, 12)
	tpill.position = Vector2(6, 5)
	card.add_child(tpill)

	# Nom
	_lbl(card, label, 92, 8, w - 98, 24, 14, C_TEXT)

	if bought:
		_lbl(card, "✓ Apprise", 64, 34, w - 70, 20, 12, C_GOOD)
		_lbl(card, "Disponible pour toute l'équipe", 6, 58, w - 12, 18, 10, C_DIM)
	else:
		_lbl(card, "%d Baies" % price, 64, 34, 80, 20, 12, C_DIM)

		var can_buy := GameManager.gold >= price
		var btn := Button.new()
		btn.text     = "Apprendre"
		btn.position = Vector2(w - 108, 28)
		btn.size     = Vector2(100, 28)
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
		var cap_api := api; var cap_price := price
		btn.pressed.connect(func() -> void: _buy_move(cap_api, cap_price))
		card.add_child(btn)

		_lbl(card, "Toute l'équipe l'apprend dès la run", 6, 64, w - 12, 16, 10, C_DIM)


## Ouvre l'écran d'attribution des CS par-dessus le tuteur (même flux de
## fermeture : le bouton "Fermer" de l'écran CS ramène simplement ici).
func _open_cs_screen() -> void:
	var cs := CSAssignScreen.new()
	cs.layer = layer + 1
	add_child(cs)
	cs.closed.connect(func() -> void: cs.queue_free(), CONNECT_ONE_SHOT)


func _buy_move(api: String, price: int) -> void:
	if not GameManager.spend_gold(price):
		return
	if api not in GameManager.purchased_move_names:
		GameManager.purchased_move_names.append(api)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_build()


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
		s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.74, 0.66, 0.52); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.82, 0.74, 0.60)
	btn.add_theme_stylebox_override("hover", sh)
