class_name StarterSelectionScreen
extends CanvasLayer

signal starter_chosen(pokemon_id: int)

# ── Casting des starters ──────────────────────────────────────────────
const STARTERS: Array[Dictionary] = [
	{"id": 25,  "name_fr": "Pikachu",      "role": "L'Icône absolue",
	 "desc": "Refuse toute Poké Ball. Le symbole vivant de la résistance."},
	{"id": 570, "name_fr": "Zorua",        "role": "L'Espion des ombres",
	 "desc": "Méfiant envers les humains. Protège les siens depuis l'obscurité."},
	{"id": 359, "name_fr": "Absol",        "role": "Le Loup solitaire",
	 "desc": "Rejeté et incompris. Se bat pour ceux que le monde a abandonnés."},
	{"id": 725, "name_fr": "Flamiaou",     "role": "L'Indépendant",
	 "desc": "Fier et indomptable. Aucun dresseur ne peut briser son esprit."},
	{"id": 656, "name_fr": "Grenousse",    "role": "Le Sélectif",
	 "desc": "N'obéit qu'à ceux qu'il juge dignes. Sinon, il disparaît."},
	{"id": 390, "name_fr": "Ouisticram",   "role": "Le Combattant blessé",
	 "desc": "Exploité puis abandonné. Se bat désormais pour protéger les siens."},
	{"id": 674, "name_fr": "Pandespiègle", "role": "Le Garnement loyal",
	 "desc": "Look de rebelle, cœur de chevalier. Défend toujours les plus faibles."},
	{"id": 559, "name_fr": "Baggiguane",   "role": "Le Provocateur",
	 "desc": "Monte une bande de rue. Son arrogance cache une loyauté d'acier."},
	{"id": 447, "name_fr": "Riolu",        "role": "L'Empathique",
	 "desc": "Ressent la douleur des Pokémon emprisonnés. Se bat par empathie."},
]

# ── Palette rébellion ─────────────────────────────────────────────────
const C_BG       := Color(0.17, 0.15, 0.11)
const C_ACCENT   := Color(0.76, 0.53, 0.17)
const C_GOLD     := Color(0.76, 0.53, 0.17)
const C_TEXT     := Color(0.18, 0.13, 0.06)
const C_DIM      := Color(0.48, 0.38, 0.22)
const C_CARD_NRM := Color(0.88, 0.82, 0.67)
const C_CARD_SEL := Color(0.96, 0.90, 0.75)
const C_BDR_NRM  := Color(0.60, 0.50, 0.33)
const C_BDR_SEL  := Color(0.76, 0.53, 0.17)
const C_DETAIL   := Color(0.85, 0.78, 0.62)
const C_STAT_BG  := Color(0.80, 0.72, 0.55)
const C_XP       := Color(0.25, 0.55, 0.95)
const C_HP_COL   := Color(0.22, 0.68, 0.24)

# ── État ─────────────────────────────────────────────────────────────
var _selected_id:  int         = 25
var _loaded_data:  Dictionary  = {}   # int -> PokemonData
var _portraits:    Dictionary  = {}   # int -> Texture2D
var _card_panels:  Dictionary  = {}   # int -> Panel
var _card_tex:     Dictionary  = {}   # int -> TextureRect
var _card_ph:      Dictionary  = {}   # int -> ColorRect
var _detail_root:  Control     = null
var _btn_start:    Button      = null
var _large_tex:    TextureRect = null


func _ready() -> void:
	_build_ui()
	_fetch_all()


# ── Construction de l'UI ──────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # fond décoratif — ne bloque pas les clics
	add_child(bg)

	# Titre
	var title_bar := Panel.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(1280, 84)
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style(title_bar, Color(0.14, 0.11, 0.07), C_ACCENT, 0)
	add_child(title_bar)
	var t1: Label = _lbl("★  LA RÉBELLION  ★", 0, 4, 1280, 44, 34, Color(0.94, 0.88, 0.72), true)
	title_bar.add_child(t1)
	var t2: Label = _lbl(
		"Choisissez le Pokémon qui mènera la révolte — celui qui refusera de vivre enchaîné.",
		0, 52, 1280, 24, 14, C_DIM, true)
	title_bar.add_child(t2)

	# Panneau gauche — grille 3×3
	var left := Panel.new()
	left.position = Vector2(8, 92)
	left.size     = Vector2(454, 576)
	left.mouse_filter = Control.MOUSE_FILTER_PASS   # laisse passer vers les cartes enfants
	_panel_style(left, Color(0.84, 0.77, 0.61), C_BDR_NRM, 8)
	add_child(left)
	for idx in STARTERS.size():
		_build_card(left, idx)

	# Panneau droit — détail
	var right := Panel.new()
	right.position = Vector2(470, 92)
	right.size     = Vector2(802, 576)
	right.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_style(right, C_DETAIL, C_BDR_NRM, 8)
	add_child(right)
	_detail_root = Control.new()
	_detail_root.position = Vector2(0, 0)
	_detail_root.size     = Vector2(802, 576)
	_detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_detail_root)

	# Bouton Commencer
	_btn_start = Button.new()
	_btn_start.position = Vector2(880, 670)
	_btn_start.size     = Vector2(392, 48)
	_btn_start.text     = "COMMENCER LA RÉBELLION  ▶"
	_btn_start.disabled = false   # toujours actif — pas besoin des données API pour démarrer
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_ACCENT
	sn.set_corner_radius_all(8)
	sn.set_border_width_all(0)
	var sh := StyleBoxFlat.new()
	sh.bg_color = C_ACCENT.lightened(0.15)
	sh.set_corner_radius_all(8)
	sh.set_border_width_all(0)
	var sd := StyleBoxFlat.new()
	sd.bg_color = Color(0.60, 0.54, 0.42)
	sd.set_corner_radius_all(8)
	_btn_start.add_theme_stylebox_override("normal",   sn)
	_btn_start.add_theme_stylebox_override("hover",    sh)
	_btn_start.add_theme_stylebox_override("disabled", sd)
	_btn_start.add_theme_color_override("font_color", Color(0.96, 0.90, 0.75))
	_btn_start.add_theme_color_override("font_disabled_color", Color(0.70, 0.64, 0.52))
	_btn_start.add_theme_font_size_override("font_size", 18)
	_btn_start.pressed.connect(func() -> void: starter_chosen.emit(_selected_id))
	add_child(_btn_start)

	_refresh_detail()


func _build_card(parent: Panel, idx: int) -> void:
	var col: int  = idx % 3
	var row: int  = idx / 3
	var card_w: int = 138
	var card_h: int = 178
	var gap:    int = 6
	var px: int = 8 + col * (card_w + gap)
	var py: int = 8 + row * (card_h + gap)

	var s:       Dictionary = STARTERS[idx]
	var sid:     int        = int(s.get("id", 0))
	var name_fr: String     = str(s.get("name_fr", ""))
	var role:    String     = str(s.get("role", ""))

	var card := Panel.new()
	card.position = Vector2(px, py)
	card.size     = Vector2(card_w, card_h)
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # capture les clics directement sur la carte
	_card_panels[sid] = card

	if sid == _selected_id:
		_panel_style(card, C_CARD_SEL, C_BDR_SEL, 7)
	else:
		_panel_style(card, C_CARD_NRM, C_BDR_NRM, 7)

	# Placeholder coloré centré en haut
	var ph := ColorRect.new()
	ph.position = Vector2(29, 6)
	ph.size     = Vector2(80, 80)
	ph.color    = Color(0.22, 0.22, 0.40)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_ph[sid] = ph
	card.add_child(ph)

	# TextureRect portrait (caché jusqu'au chargement)
	var tex := TextureRect.new()
	tex.position     = Vector2(29, 6)
	tex.size         = Vector2(80, 80)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tex.visible = false
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_tex[sid] = tex
	card.add_child(tex)

	var nm: Label = _lbl(name_fr.to_upper(), 4, 90, card_w - 8, 20, 13, C_TEXT, true)
	card.add_child(nm)

	var rl: Label = _lbl(role, 4, 114, card_w - 8, 46, 10, C_DIM, true)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(rl)

	var lv: Label = _lbl("NIV. 5", 4, 160, card_w - 8, 16, 11, C_GOLD, true)
	card.add_child(lv)

	# Clic géré via gui_input (plus fiable que flat Button dans une CanvasLayer)
	var capture_id: int = sid
	parent.add_child(card)   # doit être dans le scène tree avant de connecter gui_input
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mbe := event as InputEventMouseButton
			if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
				_select(capture_id)
				get_viewport().set_input_as_handled()
	)


# ── Sélection ─────────────────────────────────────────────────────────

func _select(id: int) -> void:
	_selected_id = id
	for s: Dictionary in STARTERS:
		var sid: int = int(s.get("id", 0))
		if _card_panels.has(sid):
			var p: Panel = _card_panels[sid] as Panel
			if sid == id:
				_panel_style(p, C_CARD_SEL, C_BDR_SEL, 7)
			else:
				_panel_style(p, C_CARD_NRM, C_BDR_NRM, 7)
	_refresh_detail()


# ── Panneau détail ────────────────────────────────────────────────────

func _refresh_detail() -> void:
	for ch: Node in _detail_root.get_children():
		ch.queue_free()
	_large_tex = null

	if not _loaded_data.has(_selected_id):
		var wait_lbl: Label = _lbl("Chargement des données…", 0, 272, 802, 30, 17, C_DIM, true)
		_detail_root.add_child(wait_lbl)
		return

	var pd: PokemonData  = _loaded_data[_selected_id]
	var sd: Dictionary   = _get_starter_dict(_selected_id)

	# ── Portrait + nom/rôle côte à côte ──
	var p_bg := ColorRect.new()
	p_bg.position = Vector2(16, 16)
	p_bg.size     = Vector2(148, 148)
	p_bg.color    = C_STAT_BG
	_detail_root.add_child(p_bg)

	_large_tex = TextureRect.new()
	_large_tex.position     = Vector2(16, 16)
	_large_tex.size         = Vector2(148, 148)
	_large_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_large_tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	if _portraits.has(_selected_id):
		var portrait_tex: Texture2D = _portraits[_selected_id] as Texture2D
		_large_tex.texture = portrait_tex
	_detail_root.add_child(_large_tex)

	# Nom
	var name_lbl: Label = _lbl(pd.name_fr.to_upper(), 178, 16, 608, 38, 28, C_GOLD)
	_detail_root.add_child(name_lbl)

	# Rôle
	var role: String     = str(sd.get("role", ""))
	var role_lbl: Label  = _lbl("« %s »" % role, 178, 58, 608, 24, 16, C_ACCENT)
	_detail_root.add_child(role_lbl)

	# Types
	var tx: int = 178
	for t: String in pd.types:
		var badge := Panel.new()
		badge.position = Vector2(tx, 82)
		badge.size     = Vector2(70, 19)
		_panel_style_col(badge, _type_color(t), 4)
		_detail_root.add_child(badge)
		var tlbl: Label = _lbl(t.to_upper(), 0, 2, 70, 15, 11, Color.WHITE, true)
		badge.add_child(tlbl)
		tx += 76

	# Description
	var desc: String     = str(sd.get("desc", ""))
	var desc_lbl: Label  = _lbl(desc, 178, 108, 608, 60, 13, C_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_root.add_child(desc_lbl)

	# ── Séparateur ──
	_sep(16, 174, 770)

	# ── Stats (2 colonnes × 3 lignes) ──
	var stat_names:  Array[String] = ["PV base", "Attaque", "Défense", "Atq. Sp.", "Déf. Sp.", "Vitesse"]
	var stat_values: Array[int]    = [pd.hp, pd.attack, pd.defense,
									  pd.sp_attack, pd.sp_defense, pd.speed]
	var stat_max:    Array[int]    = [125, 190, 190, 190, 190, 190]
	var col_w: int = 383
	for si in 6:
		var ci: int = si % 2
		var ri: int = si / 2
		var sx: int = 16 + ci * col_w
		var sy: int = 184 + ri * 38

		var sl: Label = _lbl(stat_names[si], sx, sy + 2, 78, 16, 12, C_DIM)
		_detail_root.add_child(sl)
		var sv: Label = _lbl(str(stat_values[si]), sx + 82, sy + 2, 40, 16, 14, C_TEXT)
		_detail_root.add_child(sv)

		var sb := ProgressBar.new()
		sb.position        = Vector2(sx + 122, sy + 5)
		sb.size            = Vector2(col_w - 124, 12)
		sb.max_value       = stat_max[si]
		sb.value           = stat_values[si]
		sb.show_percentage = false
		var fill_s := StyleBoxFlat.new()
		fill_s.bg_color = C_HP_COL if si == 0 else C_XP
		fill_s.set_corner_radius_all(3)
		var bg_s := StyleBoxFlat.new()
		bg_s.bg_color = C_STAT_BG
		sb.add_theme_stylebox_override("fill",       fill_s)
		sb.add_theme_stylebox_override("background", bg_s)
		_detail_root.add_child(sb)

	# ── Séparateur ──
	_sep(16, 302, 770)

	# ── Attaques connues au niveau 5 ──
	var mhdr: Label = _lbl("── Attaques disponibles au niveau 5 ──", 16, 310, 770, 20, 13, C_DIM)
	_detail_root.add_child(mhdr)

	var moves_at_5: Array[String] = []
	for lm: Dictionary in pd.level_up_moves:
		var lv: int = int(lm.get("level", 99))
		if lv <= 5:
			var mn: String = str(lm.get("name", "")).replace("-", " ").capitalize()
			if mn not in moves_at_5:
				moves_at_5.append(mn)
		if moves_at_5.size() >= 4:
			break

	if moves_at_5.is_empty():
		# Fallback : premières attaques disponibles quelle que soit le niveau
		for lm: Dictionary in pd.level_up_moves:
			var mn: String = str(lm.get("name", "")).replace("-", " ").capitalize()
			if mn not in moves_at_5:
				moves_at_5.append(mn)
			if moves_at_5.size() >= 4:
				break

	if moves_at_5.is_empty():
		var no_m: Label = _lbl("Aucune attaque connue", 16, 332, 770, 22, 13, C_DIM)
		_detail_root.add_child(no_m)
	else:
		var mx: int = 16
		for mn: String in moves_at_5:
			var mp := Panel.new()
			mp.position = Vector2(mx, 332)
			mp.size     = Vector2(182, 26)
			_panel_style(mp, Color(0.08, 0.10, 0.22), C_BDR_NRM, 5)
			_detail_root.add_child(mp)
			var mlbl: Label = _lbl(mn, 6, 4, 170, 18, 12, C_TEXT)
			mp.add_child(mlbl)
			mx += 188


# ── Chargement API ────────────────────────────────────────────────────

func _fetch_all() -> void:
	for s: Dictionary in STARTERS:
		var sid: int = int(s.get("id", 0))
		PokemonAPI.get_pokemon(sid, func(api_data: Dictionary) -> void:
			if api_data.is_empty():
				return
			var pd: PokemonData = PokemonData.from_api(api_data)
			_loaded_data[sid] = pd
			if sid == _selected_id:
				_refresh_detail()
			if not pd.sprite_url.is_empty():
				_fetch_portrait(sid, pd.sprite_url)
		)


func _fetch_portrait(sid: int, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				return
			img.resize(128, 128, Image.INTERPOLATE_NEAREST)
			var new_tex: Texture2D = ImageTexture.create_from_image(img)
			_portraits[sid] = new_tex
			# Mise à jour carte
			if _card_tex.has(sid):
				var ct: TextureRect = _card_tex[sid] as TextureRect
				ct.texture = new_tex
				ct.visible = true
				if _card_ph.has(sid):
					var cp: ColorRect = _card_ph[sid] as ColorRect
					cp.visible = false
			# Mise à jour grand portrait si sélectionné
			if sid == _selected_id and is_instance_valid(_large_tex):
				_large_tex.texture = new_tex
	)
	http.request(url)


# ── Utilitaires ───────────────────────────────────────────────────────

func _get_starter_dict(sid: int) -> Dictionary:
	for s: Dictionary in STARTERS:
		if int(s.get("id", 0)) == sid:
			return s
	return {}


func _sep(x: int, y: int, w: int) -> void:
	var line := ColorRect.new()
	line.position = Vector2(x, y)
	line.size     = Vector2(w, 1)
	line.color    = C_BDR_NRM
	_detail_root.add_child(line)


func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _panel_style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _panel_style_col(p: Panel, bg: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


static func _type_color(t: String) -> Color:
	match t:
		"fire":     return Color(0.95, 0.40, 0.10)
		"water":    return Color(0.20, 0.45, 0.95)
		"grass":    return Color(0.20, 0.70, 0.20)
		"electric": return Color(0.96, 0.80, 0.08)
		"poison":   return Color(0.65, 0.20, 0.75)
		"flying":   return Color(0.50, 0.72, 0.92)
		"bug":      return Color(0.50, 0.72, 0.12)
		"rock":     return Color(0.72, 0.60, 0.38)
		"ground":   return Color(0.88, 0.72, 0.40)
		"ice":      return Color(0.55, 0.88, 0.92)
		"fighting": return Color(0.88, 0.22, 0.22)
		"psychic":  return Color(0.95, 0.28, 0.52)
		"ghost":    return Color(0.42, 0.28, 0.62)
		"dragon":   return Color(0.38, 0.22, 0.90)
		"dark":     return Color(0.32, 0.22, 0.22)
		"steel":    return Color(0.68, 0.68, 0.78)
		"fairy":    return Color(0.92, 0.52, 0.72)
		_:          return Color(0.62, 0.62, 0.62)
