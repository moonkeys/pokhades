class_name TeamBuilderScreen
extends CanvasLayer

signal closed

const C_BG      := Color(0.10, 0.08, 0.05, 0.90)
const C_PANEL   := Color(0.91, 0.85, 0.70)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.18, 0.13, 0.06)
const C_DIM     := Color(0.48, 0.38, 0.22)
const C_GOLD    := Color(0.76, 0.53, 0.17)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)
const C_SLOT_ON := Color(0.76, 0.53, 0.17)
const C_SLOT_OFF:= Color(0.82, 0.74, 0.58)
const C_IN_TEAM := Color(0.22, 0.60, 0.28)
const C_LOCKED  := Color(0.55, 0.48, 0.38)

# pokemon_data cache: id → { name_fr, types, sprite_url, loaded }
var _pdata: Dictionary = {}
var _portraits: Dictionary = {}   # id → Texture2D

var _roster_root: Control   = null
var _team_root:   Control   = null
var _info_lbl:    Label     = null
var _slot_panels: Array     = []  # panels de l'équipe actuelle


func _ready() -> void:
	_build()
	_load_unlocked_data()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Panel principal
	var panel := Panel.new()
	panel.position = Vector2(60, 30)
	panel.size     = Vector2(1160, 660)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	# Header
	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1160, 72)
	_style_col(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	_lbl_to(panel, "◉  GESTION D'ÉQUIPE", 24, 14, 700, 44, 24, C_GOLD_LT)

	var max_str := "Taille max : %d  (déblocage à %d Pokémon)" % [
		GameManager.get_max_team_size(),
		GameManager.get_next_unlock_threshold()
	]
	_info_lbl = _lbl_to(panel, max_str, 24, 80, 1112, 24, 13, C_DIM)

	# ── Colonne gauche : équipe actuelle ──────────────────────────────
	var lhdr := _lbl_to(panel, "ÉQUIPE ACTUELLE", 20, 112, 320, 22, 14, C_GOLD)
	lhdr = lhdr  # silence warning

	_team_root = Control.new()
	_team_root.position = Vector2(20, 138)
	_team_root.size     = Vector2(320, 480)
	panel.add_child(_team_root)
	_refresh_team_slots()

	# Séparateur vertical
	var sep := ColorRect.new()
	sep.position = Vector2(354, 100)
	sep.size     = Vector2(2, 530)
	sep.color    = C_BORDER
	panel.add_child(sep)

	# ── Colonne droite : Pokémon libérés ─────────────────────────────
	_lbl_to(panel, "POKÉMON LIBÉRÉS  (%d)" % GameManager.unlocked_pokemon.size(),
		374, 112, 760, 22, 14, C_GOLD)

	_roster_root = Control.new()
	_roster_root.position = Vector2(374, 138)
	_roster_root.size     = Vector2(762, 490)
	_roster_root.clip_contents = true
	panel.add_child(_roster_root)

	# Bouton fermer
	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 600)
	close.size     = Vector2(180, 44)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)

	_rebuild_roster()


# ── Équipe actuelle ───────────────────────────────────────────────────

func _refresh_team_slots() -> void:
	for ch in _team_root.get_children():
		ch.queue_free()
	_slot_panels.clear()

	var max_n := GameManager.get_max_team_size()
	var sw    := 310
	var sh    := 68
	var gap   := 8

	for i in max_n:
		var sp := Panel.new()
		sp.position = Vector2(0, i * (sh + gap))
		sp.size     = Vector2(sw, sh)

		if i < GameManager.hub_team.size():
			var pid: int = GameManager.hub_team[i]
			_style(sp, C_SLOT_ON.lightened(0.35), C_SLOT_ON, 8)

			# Portrait placeholder
			var ph := ColorRect.new()
			ph.position = Vector2(6, 6)
			ph.size     = Vector2(56, 56)
			ph.color    = Color(0.74, 0.66, 0.50)
			sp.add_child(ph)

			if _portraits.has(pid):
				var tex_r := TextureRect.new()
				tex_r.position    = Vector2(6, 6)
				tex_r.size        = Vector2(56, 56)
				tex_r.texture     = _portraits[pid]
				tex_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sp.add_child(tex_r)

			var name_str := _get_name(pid)
			_lbl_to(sp, name_str, 68, 10, sw - 80, 22, 14, C_TEXT)
			_lbl_to(sp, "Pokémon #%d" % pid, 68, 34, sw - 150, 18, 12, C_DIM)

			# Bouton retirer
			var rem := Button.new()
			rem.text     = "✕"
			rem.position = Vector2(sw - 40, 20)
			rem.size     = Vector2(32, 28)
			rem.add_theme_font_size_override("font_size", 13)
			rem.add_theme_color_override("font_color", Color(0.70, 0.20, 0.18))
			_btn_neutral(rem)
			var ri := i
			rem.pressed.connect(func() -> void: _remove_from_team(ri))
			sp.add_child(rem)
		else:
			# Slot vide
			_style(sp, Color(0.80, 0.72, 0.56), C_BORDER, 8)
			_lbl_to(sp, "— Slot libre —", 0, 22, sw, 24, 14, Color(0.60, 0.52, 0.38), true)

		_team_root.add_child(sp)
		_slot_panels.append(sp)


func _remove_from_team(idx: int) -> void:
	if idx < GameManager.hub_team.size():
		GameManager.hub_team.remove_at(idx)
	_refresh_team_slots()
	_rebuild_roster()


# ── Roster des pokémon libérés ────────────────────────────────────────

func _rebuild_roster() -> void:
	for ch in _roster_root.get_children():
		ch.queue_free()

	if GameManager.unlocked_pokemon.is_empty():
		_lbl_to(_roster_root, "Aucun Pokémon libéré pour l'instant…\nTermine une run pour en recruter.",
			20, 20, 720, 80, 16, C_DIM)
		return

	var cw: int = 168
	var ch_h: int = 90
	var gap: int  = 10
	var cols: int = 4

	for i in GameManager.unlocked_pokemon.size():
		var pid: int = GameManager.unlocked_pokemon[i]
		var col: int = i % cols
		var row: int = i / cols
		var cx: int  = col * (cw + gap)
		var cy: int  = row * (ch_h + gap)
		_build_roster_card(_roster_root, pid, cx, cy, cw, ch_h)


func _build_roster_card(parent: Control, pid: int, x: int, y: int, w: int, h: int) -> void:
	var in_team: bool = pid in GameManager.hub_team

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	if in_team:
		_style(card, Color(0.82, 0.92, 0.82), C_IN_TEAM, 8)
	else:
		_style(card, Color(0.86, 0.80, 0.65), C_BORDER, 8)
	parent.add_child(card)

	# Portrait
	var ph := ColorRect.new()
	ph.position = Vector2(6, 8)
	ph.size     = Vector2(56, 56)
	ph.color    = Color(0.74, 0.66, 0.50)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ph)

	if _portraits.has(pid):
		var tr := TextureRect.new()
		tr.position    = Vector2(6, 8)
		tr.size        = Vector2(56, 56)
		tr.texture     = _portraits[pid]
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(tr)

	var name_str := _get_name(pid)
	_lbl_to(card, name_str, 66, 10, w - 72, 18, 13, C_TEXT)
	_lbl_to(card, "#%d" % pid, 66, 30, w - 72, 14, 11, C_DIM)

	if in_team:
		_lbl_to(card, "✓ équipe", 66, 48, w - 72, 16, 11, C_IN_TEAM)
	else:
		var can_add := GameManager.hub_team.size() < GameManager.get_max_team_size()
		var btn := Button.new()
		btn.text     = "Ajouter"
		btn.position = Vector2(62, 62)
		btn.size     = Vector2(w - 70, 22)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.disabled = not can_add
		_btn_add(btn, can_add)
		btn.pressed.connect(func() -> void: _add_to_team(pid))
		card.add_child(btn)


func _add_to_team(pid: int) -> void:
	if pid not in GameManager.hub_team and GameManager.hub_team.size() < GameManager.get_max_team_size():
		GameManager.hub_team.append(pid)
	_refresh_team_slots()
	_rebuild_roster()


# ── Chargement API ────────────────────────────────────────────────────

func _load_unlocked_data() -> void:
	for pid in GameManager.unlocked_pokemon:
		if not _pdata.has(pid):
			_pdata[pid] = {"name_fr": "Pokémon #%d" % pid, "loaded": false}
			var capture_id: int = pid
			PokemonAPI.get_pokemon(capture_id, func(data: Dictionary) -> void:
				if data.is_empty():
					return
				_pdata[capture_id]["name_fr"] = data.get("name_fr", "Pokémon #%d" % capture_id)
				_pdata[capture_id]["loaded"]  = true
				var url: String = data.get("sprite_url", "")
				if not url.is_empty():
					_fetch_portrait(capture_id, url)
				else:
					_rebuild_roster()
					_refresh_team_slots()
			)


func _fetch_portrait(pid: int, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			return
		img.resize(64, 64, Image.INTERPOLATE_NEAREST)
		_portraits[pid] = ImageTexture.create_from_image(img)
		_rebuild_roster()
		_refresh_team_slots()
	)
	http.request(url)


func _get_name(pid: int) -> String:
	if _pdata.has(pid):
		return _pdata[pid].get("name_fr", "Pokémon #%d" % pid)
	return "Pokémon #%d" % pid


# ── Helpers UI ─────────────────────────────────────────────────────────

func _lbl_to(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
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
	s.set_border_width_all(2 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.14); s.shadow_size = 3
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


func _btn_add(btn: Button, enabled: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = C_GOLD.lightened(0.20) if enabled else Color(0.70, 0.64, 0.50)
	s.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", s)
	if enabled:
		var sh := s.duplicate() as StyleBoxFlat
		sh.bg_color = C_GOLD.lightened(0.35)
		btn.add_theme_stylebox_override("hover", sh)
