class_name StarterSelectionScreen
extends CanvasLayer

signal starter_chosen(pokemon_id: int)
signal test_mode_chosen(pokemon_id: int)   # « MODE TEST » : tout débloqué

const BG_PATH := "res://assets/ui/starter_bg.jpeg"

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

# ── Palette rébellion (bois / parchemin / or) ─────────────────────────
const C_BG        := Color(0.20, 0.16, 0.12)        # fallback fond
const C_WOOD_DK   := Color(0.18, 0.11, 0.05)        # bois très sombre
const C_WOOD      := Color(0.32, 0.20, 0.09)        # bois moyen
const C_WOOD_LT   := Color(0.48, 0.31, 0.14)        # bois clair (liseré)
const C_GOLD      := Color(0.90, 0.64, 0.16)        # or vif
const C_GOLD_LT   := Color(0.99, 0.92, 0.72)        # or clair / texte titre
const C_PARCH     := Color(0.87, 0.78, 0.60)        # parchemin
const C_PARCH_DK  := Color(0.78, 0.68, 0.49)        # parchemin foncé
const C_TEXT      := Color(0.16, 0.10, 0.03)        # texte sombre
const C_DIM       := Color(0.42, 0.32, 0.18)        # texte secondaire
const C_CARD      := Color(0.30, 0.19, 0.09, 0.94)  # caisse normale
const C_CARD_SEL  := Color(0.42, 0.27, 0.11, 0.98)  # caisse sélectionnée
const C_BAR_BG    := Color(0.30, 0.22, 0.11)        # fond barre stat

# Couleurs par stat (icône + barre)
const STAT_COLORS: Array[Color] = [
	Color(0.85, 0.24, 0.18),  # PV       rouge
	Color(0.88, 0.52, 0.14),  # Attaque  orange
	Color(0.80, 0.62, 0.18),  # Défense  or
	Color(0.62, 0.36, 0.80),  # Atq. Sp. violet
	Color(0.26, 0.56, 0.86),  # Déf. Sp. bleu
	Color(0.20, 0.74, 0.78),  # Vitesse  cyan
]
const STAT_NAMES: Array[String] = ["PV base", "Attaque", "Défense", "Atq. Sp.", "Déf. Sp.", "Vitesse"]

# ── État ─────────────────────────────────────────────────────────────
var _selected_id:  int         = 25
var _loaded_data:  Dictionary  = {}   # int -> PokemonData
var _portraits:    Dictionary  = {}   # int -> Texture2D
var _card_panels:  Dictionary  = {}   # int -> Panel
var _card_tex:     Dictionary  = {}   # int -> TextureRect
var _card_ph:      Dictionary  = {}   # int -> ColorRect
var _card_icons:   Dictionary  = {}   # int -> bool (icônes déjà posées)

var _detail_root:   Control          = null
var _center_sprite: AnimatedSprite2D = null
var _btn_start:     Button           = null


func _ready() -> void:
	_build_ui()
	_fetch_all()
	_load_center_sprite(_selected_id)


# ══════════════════════════════════════════════════════════════════════
# CONSTRUCTION UI
# ══════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_build_background()
	_build_title()
	_build_left_board()
	_build_center_showcase()
	_build_right_scroll()
	_build_start_button()
	_refresh_detail()


func _build_background() -> void:
	if ResourceLoader.exists(BG_PATH):
		var tr := TextureRect.new()
		tr.texture = load(BG_PATH)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var flat := ColorRect.new()
		flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		flat.color = C_BG
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flat)

	# Vignette sombre haut/bas pour lisibilité titre et bouton
	var top_grad := ColorRect.new()
	top_grad.position = Vector2(0, 0)
	top_grad.size     = Vector2(1280, 96)
	top_grad.color    = Color(0, 0, 0, 0.32)
	top_grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_grad)


func _build_title() -> void:
	# Chaînes décoratives
	var chains := _TitleChains.new()
	chains.position = Vector2(0, 0)
	chains.size     = Vector2(1280, 90)
	chains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chains)

	# Plaque bois
	var banner := _wood_panel(Vector2(388, 12), Vector2(504, 66), C_WOOD, 10)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	# Liseré or intérieur
	var inner := _wood_panel(Vector2(394, 18), Vector2(492, 54), Color(0.24, 0.15, 0.06), 8)
	inner.add_theme_stylebox_override("panel", _liseré_style(Color(0.24, 0.15, 0.06), C_GOLD, 8))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)

	add_child(_lbl("★  LA RÉBELLION  ★", 388, 22, 504, 32, 26, C_GOLD_LT, true, true))
	add_child(_lbl("Choisissez le Pokémon qui mènera la révolte — celui qui refusera de vivre enchaîné.",
		340, 82, 600, 20, 12, Color(0.92, 0.86, 0.74), true))


func _build_left_board() -> void:
	# Board sombre derrière la grille
	var board := _wood_panel(Vector2(16, 110), Vector2(470, 598), C_WOOD_DK, 12)
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(board)

	for idx in STARTERS.size():
		_build_card(idx)


func _build_card(idx: int) -> void:
	var col: int = idx % 3
	var row: int = idx / 3
	const CARD_W := 140
	const CARD_H := 182
	const GAP    := 10
	var px: int = 30 + col * (CARD_W + GAP)
	var py: int = 124 + row * (CARD_H + GAP)

	var s:       Dictionary = STARTERS[idx]
	var sid:     int        = int(s.get("id", 0))
	var name_fr: String     = str(s.get("name_fr", ""))
	var role:    String     = str(s.get("role", ""))

	var card := Panel.new()
	card.position = Vector2(px, py)
	card.size     = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_style(card, sid == _selected_id)
	_card_panels[sid] = card
	add_child(card)

	# Cadre intérieur sombre du portrait (style niche de caisse)
	var niche := ColorRect.new()
	niche.position = Vector2(16, 10)
	niche.size     = Vector2(108, 92)
	niche.color    = Color(0.12, 0.08, 0.04)
	niche.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(niche)

	var ph := ColorRect.new()
	ph.position = Vector2(18, 12)
	ph.size     = Vector2(104, 88)
	ph.color    = Color(0.20, 0.16, 0.12)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_ph[sid] = ph
	card.add_child(ph)

	var tex := TextureRect.new()
	tex.position     = Vector2(18, 8)
	tex.size         = Vector2(104, 92)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tex.visible      = false
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_tex[sid] = tex
	card.add_child(tex)

	# Nom
	card.add_child(_lbl(name_fr.to_upper(), 4, 104, CARD_W - 8, 20, 13, C_GOLD_LT, true, true))
	# Rôle (centré, 2 lignes max)
	var rl := _lbl(role, 4, 126, CARD_W - 8, 30, 10, Color(0.82, 0.74, 0.60), true)
	rl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	rl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_child(rl)
	# Ruban NIV. 5
	var ribbon := _wood_panel(Vector2(34, 159), Vector2(72, 18), C_WOOD, 4)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ribbon)
	card.add_child(_lbl("NIV. 5", 34, 159, 72, 18, 11, C_GOLD, true))

	# Clic
	var capture_id := sid
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mbe := event as InputEventMouseButton
			if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
				_select(capture_id)
				get_viewport().set_input_as_handled()
	)


func _build_center_showcase() -> void:
	# Sprite PMD animé (sans ombre)
	_center_sprite = AnimatedSprite2D.new()
	_center_sprite.position = Vector2(730, 430)
	_center_sprite.scale    = Vector2(5.0, 5.0)
	add_child(_center_sprite)


func _build_right_scroll() -> void:
	# Parchemin
	var scroll := _wood_panel(Vector2(898, 104), Vector2(366, 446), C_PARCH, 14)
	scroll.add_theme_stylebox_override("panel", _liseré_style(C_PARCH, C_WOOD, 14, 4))
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	_detail_root = Control.new()
	_detail_root.position = Vector2(898, 104)
	_detail_root.size     = Vector2(366, 446)
	_detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail_root)


func _build_start_button() -> void:
	# Bouton principal VERT du kit (même langage que « Continuer » en run)
	_btn_start = UiKit.button("COMMENCER LA RÉBELLION  ▶", Vector2(366, 50))
	_btn_start.position = Vector2(898, 660)
	_btn_start.add_theme_font_size_override("font_size", UiKit.scaled_font(18))
	_btn_start.pressed.connect(func() -> void: starter_chosen.emit(_selected_id))
	add_child(_btn_start)

	# Bouton « MODE TEST » — juste au-dessus : démarre avec tout débloqué
	# (roster large, CS, emplacements max, Baies) pour tester en conditions.
	# Accent bleu conservé (c'est un outil de dev, pas une action de jeu).
	var btn_test := Button.new()
	btn_test.position = Vector2(898, 606)
	btn_test.size     = Vector2(366, 44)
	btn_test.text     = "🧪  MODE TEST  (tout débloqué)"
	var tn := _liseré_style(Color(0.16, 0.22, 0.30), Color(0.45, 0.72, 0.92), 10, 3)
	var th := _liseré_style(Color(0.22, 0.30, 0.40), Color(0.65, 0.86, 1.0), 10, 3)
	btn_test.add_theme_stylebox_override("normal", tn)
	btn_test.add_theme_stylebox_override("hover",  th)
	btn_test.add_theme_stylebox_override("pressed", tn)
	btn_test.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	btn_test.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_test.add_theme_font_size_override("font_size", UiKit.scaled_font(16))
	UiKit.juice(btn_test)   # même vie que les boutons du kit
	btn_test.pressed.connect(func() -> void: test_mode_chosen.emit(_selected_id))
	add_child(btn_test)


# ══════════════════════════════════════════════════════════════════════
# SÉLECTION
# ══════════════════════════════════════════════════════════════════════

func _select(id: int) -> void:
	if id == _selected_id: return
	_selected_id = id
	for s: Dictionary in STARTERS:
		var sid := int(s.get("id", 0))
		if _card_panels.has(sid):
			_apply_card_style(_card_panels[sid] as Panel, sid == id)
	_refresh_detail()
	_load_center_sprite(id)


## Navigation clavier : flèches = déplacement dans la grille 3×3 des
## starters, Entrée/Espace = COMMENCER LA RÉBELLION avec la sélection.
func _unhandled_input(event: InputEvent) -> void:
	var idx := _selected_index()
	if event.is_action_pressed("ui_right"):
		_select_index(idx + 1)
	elif event.is_action_pressed("ui_left"):
		_select_index(idx - 1)
	elif event.is_action_pressed("ui_down"):
		_select_index(idx + 3)
	elif event.is_action_pressed("ui_up"):
		_select_index(idx - 3)
	elif event.is_action_pressed("ui_accept"):
		starter_chosen.emit(_selected_id)
	else:
		return
	get_viewport().set_input_as_handled()


func _selected_index() -> int:
	for i in STARTERS.size():
		if int(STARTERS[i].get("id", 0)) == _selected_id:
			return i
	return 0


func _select_index(i: int) -> void:
	_select(int(STARTERS[clampi(i, 0, STARTERS.size() - 1)].get("id", 0)))


func _apply_card_style(card: Panel, selected: bool) -> void:
	if selected:
		card.add_theme_stylebox_override("panel", _liseré_style(C_CARD_SEL, C_GOLD, 8, 3))
	else:
		card.add_theme_stylebox_override("panel", _liseré_style(C_CARD, C_WOOD_LT, 8, 2))


# ══════════════════════════════════════════════════════════════════════
# SPRITE CENTRAL PMD
# ══════════════════════════════════════════════════════════════════════

func _load_center_sprite(id: int) -> void:
	PMDSprites.get_walk_sprites(id, self, func(result: Dictionary) -> void:
		if result.is_empty() or id != _selected_id: return
		if not is_instance_valid(_center_sprite): return
		var frames: SpriteFrames = result.get("frames")
		if frames == null: return
		_center_sprite.sprite_frames = frames
		if frames.has_animation("idle"):
			_center_sprite.play("idle")
		elif frames.has_animation("walk_down"):
			_center_sprite.play("walk_down")
	)


# ══════════════════════════════════════════════════════════════════════
# PANNEAU DÉTAIL (parchemin)
# ══════════════════════════════════════════════════════════════════════

func _refresh_detail() -> void:
	for ch in _detail_root.get_children():
		ch.queue_free()

	if not _loaded_data.has(_selected_id):
		_detail_root.add_child(_lbl("Chargement des données…", 0, 200, 366, 30, 16, C_DIM, true))
		return

	var pd: PokemonData = _loaded_data[_selected_id]
	var sd: Dictionary  = _get_starter_dict(_selected_id)

	# Nom
	_detail_root.add_child(_lbl(pd.name_fr.to_upper(), 0, 18, 366, 38, 30, C_GOLD, true, true))

	# Logos de type, centrés
	var pill_w := 120.0
	var pill_gap := 12.0
	var total_w := pd.types.size() * pill_w + (pd.types.size() - 1) * pill_gap
	var px := (366 - total_w) / 2.0
	for t: String in pd.types:
		var pill := TypeIcon.make_pill(t, pill_w, 30.0, 15)
		pill.position = Vector2(px, 60)
		_detail_root.add_child(pill)
		px += pill_w + pill_gap

	# Flavor (centré, multi-lignes)
	var desc := str(sd.get("desc", ""))
	var dl := _lbl("« %s »" % desc, 24, 102, 318, 64, 13, C_DIM, true)
	dl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	dl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_root.add_child(dl)

	# Séparateur
	_sep(28, 174, 310)

	# Stats — 6 lignes pleine largeur
	var values: Array[int] = [pd.hp, pd.attack, pd.defense, pd.sp_attack, pd.sp_defense, pd.speed]
	var maxes:  Array[int] = [140, 190, 190, 190, 190, 190]
	for i in 6:
		var sy := 188 + i * 40
		var col := STAT_COLORS[i]

		# Pastille colorée (code couleur par stat)
		var ic := _wood_panel(Vector2(28, sy + 2), Vector2(18, 18), col, 5)
		ic.add_theme_stylebox_override("panel", _liseré_style(col, col.darkened(0.35), 5, 2))
		_detail_root.add_child(ic)

		# Nom stat
		_detail_root.add_child(_lbl(STAT_NAMES[i], 56, sy + 2, 88, 20, 13, C_TEXT))

		# Valeur (sans ombre — sinon effet "doublé")
		_detail_root.add_child(_lbl(str(values[i]), 146, sy + 2, 40, 20, 14, C_TEXT, true))

		# Barre
		var bar := ProgressBar.new()
		bar.position = Vector2(192, sy + 4)
		bar.size     = Vector2(150, 16)
		bar.max_value = maxes[i]
		bar.value     = values[i]
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(4)
		var bg := StyleBoxFlat.new()
		bg.bg_color = C_BAR_BG
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		_detail_root.add_child(bar)


# ══════════════════════════════════════════════════════════════════════
# CHARGEMENT API (cartes)
# ══════════════════════════════════════════════════════════════════════

func _fetch_all() -> void:
	for s: Dictionary in STARTERS:
		var sid := int(s.get("id", 0))
		PokemonAPI.get_pokemon(sid, func(api_data: Dictionary) -> void:
			if api_data.is_empty(): return
			var pd := PokemonData.from_api(api_data)
			_loaded_data[sid] = pd
			_add_card_type_icons(sid, pd.types)
			if sid == _selected_id:
				_refresh_detail()
			if not pd.sprite_url.is_empty():
				_fetch_portrait(sid, pd.sprite_url)
		)


func _add_card_type_icons(sid: int, types: Array) -> void:
	if _card_icons.has(sid) or not _card_panels.has(sid): return
	_card_icons[sid] = true
	var card: Panel = _card_panels[sid]
	# Bandeau pilule(s) superposé au bas du portrait (niche : x16-124, y10-102)
	var n := types.size()
	var pill_w := 104.0 / n - (2.0 if n > 1 else 0.0)
	var px := 16.0
	for t in types:
		var pill := TypeIcon.make_pill(str(t), pill_w, 16.0, 9)
		pill.position = Vector2(px, 84)
		card.add_child(pill)
		px += pill_w + 2.0


func _fetch_portrait(sid: int, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK: return
			img.resize(96, 96, Image.INTERPOLATE_NEAREST)
			var new_tex: Texture2D = ImageTexture.create_from_image(img)
			_portraits[sid] = new_tex
			if _card_tex.has(sid):
				var ct: TextureRect = _card_tex[sid]
				ct.texture = new_tex
				ct.visible = true
				if _card_ph.has(sid):
					(_card_ph[sid] as ColorRect).visible = false
	)
	http.request(url)


# ══════════════════════════════════════════════════════════════════════
# DÉCORATIONS DESSINÉES
# ══════════════════════════════════════════════════════════════════════

class _TitleChains extends Control:
	func _draw() -> void:
		# Deux chaînes descendant des coins haut vers la plaque (x≈420 et x≈860)
		for cx in [430.0, 850.0]:
			var y := 0.0
			while y < 14.0:
				draw_circle(Vector2(cx, y + 4), 4.5, Color(0.14, 0.10, 0.06))
				draw_circle(Vector2(cx, y + 4), 3.0, Color(0.34, 0.28, 0.20))
				y += 9.0


# ══════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════

func _get_starter_dict(sid: int) -> Dictionary:
	for s: Dictionary in STARTERS:
		if int(s.get("id", 0)) == sid:
			return s
	return {}


func _sep(x: int, y: int, w: int) -> void:
	var line := ColorRect.new()
	line.position = Vector2(x, y)
	line.size     = Vector2(w, 2)
	line.color    = C_WOOD_LT
	_detail_root.add_child(line)


func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false, shadow: bool = false) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wood_panel(pos: Vector2, sz: Vector2, bg: Color, radius: int) -> Panel:
	var p := Panel.new()
	p.position = pos; p.size = sz
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = C_WOOD_DK
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size  = 5
	p.add_theme_stylebox_override("panel", s)
	return p


func _liseré_style(bg: Color, border: Color, radius: int, width: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.40)
	s.shadow_size  = 4
	return s
