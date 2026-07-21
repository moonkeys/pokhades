class_name DoorSelectionScreen
extends CanvasLayer

signal door_chosen(door_data: Dictionary)

const C_BG      := Color(0.05, 0.04, 0.02, 0.90)
const C_TEXT_LT := Color(0.94, 0.88, 0.72)
const C_DIM     := Color(0.55, 0.48, 0.36)
const C_GOLD    := Color(0.76, 0.53, 0.17)

var _wave: int = 0

# Palettes des portes
const DOOR_DEFS: Array[Dictionary] = [
	{
		"id":         "rodents",
		"label":      "Forêt Calme",
		"symbol":     "F",
		"desc":       "Petits rongeurs des\nherbes hautes.",
		"diff":       1,
		"accent":     Color(0.28, 0.56, 0.20),
		"header_top": Color(0.22, 0.46, 0.14),
		"reward_lbl": "+ Or",
		"reward_amt": 30,
	},
	{
		"id":         "bugs",
		"label":      "Nid d'Insectes",
		"symbol":     "I",
		"desc":       "Colonie d'insectes\nvenimeux.",
		"diff":       2,
		"accent":     Color(0.48, 0.38, 0.10),
		"header_top": Color(0.36, 0.28, 0.06),
		"reward_lbl": "+ Or & XP",
		"reward_amt": 45,
	},
	{
		"id":         "flyers",
		"label":      "Cimes Venteuses",
		"symbol":     "V",
		"desc":       "Éclaireurs rapides\nvolant en formation.",
		"diff":       2,
		"accent":     Color(0.22, 0.48, 0.72),
		"header_top": Color(0.14, 0.36, 0.60),
		"reward_lbl": "+ Or & XP",
		"reward_amt": 45,
	},
	{
		"id":         "elementals",
		"label":      "Sanctuaire",
		"symbol":     "E",
		"desc":       "Élémentaires anciens\naux pouvoirs variés.",
		"diff":       3,
		"accent":     Color(0.62, 0.22, 0.72),
		"header_top": Color(0.48, 0.12, 0.58),
		"reward_lbl": "Capacité bonus",
		"reward_amt": 60,
	},
	{
		"id":         "elite",
		"label":      "Salle d'Élite",
		"symbol":     "!",
		"desc":       "Pokémon puissants\naux évolutions rares.",
		"diff":       3,
		"accent":     Color(0.80, 0.30, 0.20),
		"header_top": Color(0.65, 0.18, 0.10),
		"reward_lbl": "Capacité bonus",
		"reward_amt": 70,
	},
	{
		"id":         "rest",
		"label":      "Oasis",
		"symbol":     "O",
		"desc":       "Aucun combat. Repos\net soin de l'équipe.",
		"diff":       0,
		"accent":     Color(0.20, 0.56, 0.70),
		"header_top": Color(0.12, 0.42, 0.58),
		"reward_lbl": "Soin 35% PV",
		"reward_amt": 0,
	},
]


func setup(wave_num: int) -> void:
	_wave = wave_num


func _ready() -> void:
	var doors := _pick_doors()
	_build(doors)


func _pick_doors() -> Array[Dictionary]:
	var available: Array[Dictionary] = DOOR_DEFS.duplicate(true)
	available.shuffle()
	# Toujours inclure "Oasis" si wave >= 3 (sinon probabiliste)
	var has_rest := false
	var result:   Array[Dictionary] = []
	for d in available:
		if d["id"] == "rest":
			has_rest = true
	if not has_rest and _wave >= 3 and randf() < 0.45:
		result.append(DOOR_DEFS[5].duplicate())  # rest
		for d in available:
			if d["id"] != "rest" and result.size() < 3:
				result.append(d.duplicate())
	else:
		for d in available:
			if result.size() < 3:
				result.append(d.duplicate())
	return result


func _build(doors: Array[Dictionary]) -> void:
	# Fond sombre avec vignette
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Header
	var hdr_bg := ColorRect.new()
	hdr_bg.position = Vector2(0, 0)
	hdr_bg.size     = Vector2(1280, 90)
	hdr_bg.color    = Color(0.10, 0.08, 0.04, 0.95)
	add_child(hdr_bg)

	var sep := ColorRect.new()
	sep.position = Vector2(0, 88)
	sep.size     = Vector2(1280, 2)
	sep.color    = Color(0.62, 0.50, 0.32)
	add_child(sep)

	var wave_lbl := _mk_lbl("— Vague %d terminée —" % _wave, 0, 10, 1280, 34, 22, C_GOLD, true)
	add_child(wave_lbl)

	var hint := _mk_lbl("Choisissez votre prochain défi", 0, 50, 1280, 28, 16, C_DIM, true)
	add_child(hint)

	# Cartes des portes
	var n         := doors.size()
	var card_w    := 310
	var card_h    := 440
	var gap       := 40
	var total_w   := n * card_w + (n - 1) * gap
	var sx        := (1280 - total_w) / 2
	var card_y    := (720 - card_h) / 2 + 30

	for i in n:
		_build_card(doors[i], sx + i * (card_w + gap), card_y, card_w, card_h)


func _build_card(data: Dictionary, x: int, y: int, w: int, h: int) -> void:
	var accent: Color    = data["accent"]
	var hdr_c:  Color    = data["header_top"]
	var diff:   int      = data["diff"]

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	_style_card(card, accent)
	add_child(card)

	# Bande de couleur en haut
	var header := Panel.new()
	header.position = Vector2(0, 0)
	header.size     = Vector2(w, 110)
	_style_flat(header, hdr_c, 16, true)
	card.add_child(header)

	# Symbole de la porte (grand caractère)
	var sym := _mk_lbl(data["symbol"], 0, 14, w, 70, 62, Color(1, 1, 1, 0.88), true)
	header.add_child(sym)

	# Nom
	var title := _mk_lbl(data["label"], 12, 120, w - 24, 36, 20, accent.lightened(0.1), true)
	card.add_child(title)

	# Description
	var desc := _mk_lbl(data["desc"], 16, 164, w - 32, 70, 15, C_DIM, true)
	card.add_child(desc)

	# Séparateur
	var line := ColorRect.new()
	line.position = Vector2(20, 244)
	line.size     = Vector2(w - 40, 1)
	line.color    = accent.darkened(0.1)
	card.add_child(line)

	# Difficulté
	var diff_lbl: String
	match diff:
		0: diff_lbl = "Sans combat"
		1: diff_lbl = "●○○  Normal"
		2: diff_lbl = "●●○  Difficile"
		3: diff_lbl = "●●●  Dangereux"
		_: diff_lbl = ""
	var diff_col := Color(0.75, 0.26, 0.18) if diff >= 3 else (
		Color(0.70, 0.50, 0.10) if diff == 2 else Color(0.32, 0.58, 0.22))
	var dl := _mk_lbl(diff_lbl, 0, 258, w, 26, 15, diff_col, true)
	card.add_child(dl)

	# Récompense
	var rew_str: String = data["reward_lbl"]
	if data["reward_amt"] > 0:
		rew_str = rew_str + "  (+%d Or)" % data["reward_amt"]
	var rl := _mk_lbl(rew_str, 0, 292, w, 24, 14, Color(0.36, 0.68, 0.36), true)
	card.add_child(rl)

	# Bouton
	var btn := Button.new()
	btn.text     = "Choisir"
	btn.position = Vector2(w / 2 - 90, h - 74)
	btn.size     = Vector2(180, 52)
	btn.add_theme_font_size_override("font_size", UiKit.scaled_font(19))
	btn.add_theme_color_override("font_color", C_TEXT_LT)
	_style_btn(btn, accent)
	var cap := data.duplicate()
	btn.pressed.connect(func() -> void: door_chosen.emit(cap))
	card.add_child(btn)


# ── Helpers UI ────────────────────────────────────────────────────────

func _mk_lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, col: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.50))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _style_card(p: Panel, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color      = Color(0.16, 0.13, 0.08)
	s.border_color  = accent.darkened(0.05)
	s.set_border_width_all(3)
	s.set_corner_radius_all(16)
	s.shadow_color  = Color(0, 0, 0, 0.55)
	s.shadow_size   = 12
	p.add_theme_stylebox_override("panel", s)


func _style_flat(p: Panel, bg: Color, radius: int, top_only: bool = false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if top_only:
		s.corner_radius_top_left  = radius
		s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _style_btn(btn: Button, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = accent
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size  = 4
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = accent.lightened(0.22)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = accent.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
