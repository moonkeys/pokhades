class_name TeamManagementScreen
extends CanvasLayer

signal continued

# ── Palette ───────────────────────────────────────────────────────────
const C_OVERLAY   := Color(0.10, 0.08, 0.05, 0.82)
const C_PANEL     := Color(0.91, 0.85, 0.70)
const C_BORDER    := Color(0.62, 0.50, 0.32)
const C_TEXT      := Color(0.18, 0.13, 0.06)
const C_DIM       := Color(0.48, 0.38, 0.22)
const C_GOLD      := Color(0.76, 0.53, 0.17)
const C_SLOT_NRM  := Color(0.82, 0.74, 0.56)
const C_SLOT_SEL  := Color(0.76, 0.53, 0.17)
const C_SLOT_EMPTY:= Color(0.74, 0.66, 0.50)
const C_TAB_NRM   := Color(0.78, 0.70, 0.53)
const C_TAB_ACT   := Color(0.76, 0.53, 0.17)
const C_AVAIL     := Color(0.84, 0.77, 0.60)
const C_CONTINUE  := Color(0.76, 0.53, 0.17)
const C_STAT_BG   := Color(0.84, 0.76, 0.58)
const C_HP_HIGH   := Color(0.22, 0.68, 0.24)
const C_HP_MED    := Color(0.90, 0.68, 0.08)
const C_HP_LOW    := Color(0.88, 0.20, 0.14)
const C_XP        := Color(0.25, 0.55, 0.95)

# ── État ──────────────────────────────────────────────────────────────
var _instances: Array  = []
var _wave: int         = 1
var _active: int       = 0     # onglet Pokémon sélectionné
var _selected_slot: int = -1   # slot équipé sélectionné (-1 = aucun)

# Références UI reconstruites lors du changement d'onglet
var _main_panel: Panel        = null
var _tab_buttons: Array       = []
var _content_root: Control    = null


func setup(instances: Array, wave: int) -> void:
	_instances = instances
	_wave      = wave
	_build()


# ── Construction initiale ─────────────────────────────────────────────

func _build() -> void:
	# Fond sombre
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = C_OVERLAY
	add_child(overlay)

	# Panel principal centré
	_main_panel = Panel.new()
	_main_panel.position = Vector2(44, 36)
	_main_panel.size     = Vector2(1192, 648)
	_style_panel(_main_panel, C_PANEL, C_BORDER, 12)
	add_child(_main_panel)

	# Titre
	var title := _lbl("GESTION D'ÉQUIPE  —  Vague %d" % _wave,
		0, 8, 1192, 36, 22, C_GOLD, true)
	_main_panel.add_child(title)

	# Séparateur titre
	var sep_h := ColorRect.new()
	sep_h.position = Vector2(10, 44)
	sep_h.size     = Vector2(1172, 1)
	sep_h.color    = C_BORDER
	_main_panel.add_child(sep_h)

	# Onglets gauche (160 px)
	_tab_buttons.clear()
	for i in _instances.size():
		_build_tab(i)

	# Séparateur vertical
	var sep_v := ColorRect.new()
	sep_v.position = Vector2(168, 50)
	sep_v.size     = Vector2(1, 588)
	sep_v.color    = C_BORDER
	_main_panel.add_child(sep_v)

	# Bouton Continuer (en bas à droite)
	var cont := Button.new()
	cont.position = Vector2(944, 600)
	cont.size     = Vector2(232, 38)
	cont.text     = "CONTINUER  ▶"
	_style_button(cont, C_CONTINUE, Color.WHITE)
	cont.pressed.connect(func(): continued.emit())
	_main_panel.add_child(cont)

	# Zone de contenu (droite)
	_content_root = Control.new()
	_content_root.position    = Vector2(176, 50)
	_content_root.size        = Vector2(1008, 600)
	_content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_panel.add_child(_content_root)

	_set_active_tab(0)


func _build_tab(idx: int) -> void:
	var inst: PokemonInstance = _instances[idx]

	var btn := Button.new()
	btn.position = Vector2(6, 50 + idx * 96)
	btn.size     = Vector2(156, 90)
	btn.text     = ""
	btn.flat     = true
	_style_button_raw(btn, C_TAB_NRM, C_BORDER, 6)
	_main_panel.add_child(btn)

	# Portrait
	if inst.portrait_texture != null:
		var tex := TextureRect.new()
		tex.position     = Vector2(6, 6)
		tex.size         = Vector2(46, 52)
		tex.texture      = inst.portrait_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)
	else:
		var ph := ColorRect.new()
		ph.position = Vector2(6, 6)
		ph.size     = Vector2(46, 52)
		ph.color    = _type_color(inst.data.types[0] if not inst.data.types.is_empty() else "normal").darkened(0.3)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(ph)

	var nm := _lbl(inst.data.name_fr.to_upper(), 58, 4, 90, 16, 12, C_TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(nm)

	# Mini barre HP
	var hp_bar := ProgressBar.new()
	hp_bar.position      = Vector2(58, 26)
	hp_bar.size          = Vector2(90, 7)
	hp_bar.max_value     = 1.0
	hp_bar.value         = inst.hp_ratio()
	hp_bar.show_percentage = false
	hp_bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var hpf := StyleBoxFlat.new()
	hpf.bg_color = _hp_color(inst.hp_ratio())
	hpf.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", hpf)
	var hpb := StyleBoxFlat.new()
	hpb.bg_color = Color(0.2, 0.2, 0.2)
	hp_bar.add_theme_stylebox_override("background", hpb)
	btn.add_child(hp_bar)

	var lv := _lbl("NIV. %d" % inst.level, 58, 36, 90, 16, 12, C_XP)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lv)

	# Types (mini-logos)
	var tx_off := 58
	for t: String in inst.data.types:
		var pill := TypeIcon.make_pill(t, 42.0, 14.0, 7)
		pill.position = Vector2(tx_off, 55)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(pill)
		tx_off += 44

	var i := idx
	btn.pressed.connect(func(): _set_active_tab(i))
	_tab_buttons.append(btn)


# ── Onglet actif ──────────────────────────────────────────────────────

func _set_active_tab(idx: int) -> void:
	_active        = idx
	_selected_slot = -1
	for i in _tab_buttons.size():
		_style_button_raw(
			_tab_buttons[i],
			C_TAB_ACT if i == idx else C_TAB_NRM,
			C_GOLD    if i == idx else C_BORDER,
			6
		)
	_refresh_content()


# ── Contenu principal (reconstruit à chaque changement) ───────────────

func _refresh_content() -> void:
	for ch in _content_root.get_children():
		ch.queue_free()

	var inst: PokemonInstance = _instances[_active]
	var x0 := 8
	var y  := 4

	# ── Nom + niveau ──
	var hdr := _lbl(
		"%s  —  NIV. %d" % [inst.data.name_fr.to_upper(), inst.level],
		x0, y, 980, 32, 20, C_GOLD
	)
	_content_root.add_child(hdr)
	y += 30

	# ── Types ──
	for t: String in inst.data.types:
		var pill := TypeIcon.make_pill(t, 84.0, 22.0, 12)
		pill.position = Vector2(x0, y)
		_content_root.add_child(pill)
		x0 += 90
	x0 = 8
	y += 24

	# ── Stats ──
	var stats_panel := Panel.new()
	stats_panel.position = Vector2(x0, y)
	stats_panel.size     = Vector2(984, 60)
	_style_panel_color(stats_panel, C_STAT_BG, C_BORDER, 6)
	_content_root.add_child(stats_panel)

	var stat_names:  Array[String] = ["PV", "ATQ", "DÉF", "ATQ.SP", "DÉF.SP", "VIT"]
	var stat_values: Array[int]    = [inst.max_hp, inst.data.attack, inst.data.defense,
						inst.data.sp_attack, inst.data.sp_defense, inst.data.speed]
	var stat_max:    Array[int]    = [400, 200, 200, 200, 200, 200]
	for si in stat_names.size():
		var sx: int = 12 + si * 162
		var sl: Label = _lbl(stat_names[si], sx, 4, 130, 16, 13, C_DIM)
		stats_panel.add_child(sl)
		var sv: Label = _lbl(str(stat_values[si]), sx, 22, 130, 26, 18, C_TEXT)
		stats_panel.add_child(sv)
		# mini barre stat
		var sb := ProgressBar.new()
		sb.position  = Vector2(sx, 44)
		sb.size      = Vector2(140, 6)
		sb.max_value = stat_max[si]
		sb.value     = stat_values[si]
		sb.show_percentage = false
		var sf := StyleBoxFlat.new()
		sf.bg_color = C_GOLD if si == 0 else C_XP
		sf.set_corner_radius_all(2)
		sb.add_theme_stylebox_override("fill", sf)
		var sbg := StyleBoxFlat.new()
		sbg.bg_color = Color(0.2, 0.2, 0.2)
		sb.add_theme_stylebox_override("background", sbg)
		stats_panel.add_child(sb)

	y += 68

	# ── Attaques équipées ──
	var eq_lbl := _lbl("── ATTAQUES ÉQUIPÉES (clic pour sélectionner) ──", x0, y, 984, 20, 14, C_DIM)
	_content_root.add_child(eq_lbl)
	y += 20

	for si in 4:
		_build_equipped_slot(x0, y, si, inst)
		y += 50

	y += 6

	# ── Attaques disponibles ──
	var avail_moves := _get_available_moves(inst)
	var avail_lbl_txt := "── ATTAQUES DISPONIBLES ──"
	if _selected_slot >= 0:
		avail_lbl_txt = "── CLIQUER UNE ATTAQUE POUR L'ÉQUIPER EN SLOT %d ──" % (_selected_slot + 1)
	var avail_hdr := _lbl(avail_lbl_txt, x0, y, 984, 20, 14,
		C_GOLD if _selected_slot >= 0 else C_DIM)
	_content_root.add_child(avail_hdr)
	y += 20

	if avail_moves.is_empty():
		var no_avail := _lbl("Aucune autre attaque disponible", x0, y, 984, 22, 14, C_DIM)
		_content_root.add_child(no_avail)
	else:
		var ax := x0
		var ay := y
		for md: MoveData in avail_moves:
			if ax + 200 > 984:
				ax  = x0
				ay += 44
			_build_avail_move(ax, ay, md, inst)
			ax += 204


func _build_equipped_slot(x: int, y: int, slot_idx: int, inst: PokemonInstance) -> void:
	var is_sel := _selected_slot == slot_idx
	var slot_p := Panel.new()
	slot_p.position = Vector2(x, y)
	slot_p.size     = Vector2(984, 44)
	_style_panel_color(
		slot_p,
		C_SLOT_SEL if is_sel else C_SLOT_NRM,
		C_GOLD if is_sel else C_BORDER,
		6
	)
	_content_root.add_child(slot_p)

	# Numéro de slot
	var num := _lbl("%d" % (slot_idx + 1), 6, 12, 22, 22, 15, C_DIM, true)
	slot_p.add_child(num)

	if slot_idx < inst.equipped_moves.size():
		var md: MoveData = inst.equipped_moves[slot_idx]

		# Logo de type
		var tpill := TypeIcon.make_pill(md.type, 84.0, 28.0, 13)
		tpill.position = Vector2(30, 8)
		slot_p.add_child(tpill)

		# Nom
		var nm := _lbl(md.display_name, 124, 11, 628, 22, 15, C_TEXT)
		slot_p.add_child(nm)

		# Puissance
		var pw := _lbl("PWR %d" % md.power, 820, 11, 120, 22, 14, C_DIM)
		slot_p.add_child(pw)

		# Classe (physique / spécial)
		var cls_color := Color(0.95, 0.55, 0.10) if md.damage_class == "physical" else Color(0.55, 0.30, 0.95)
		var cls := _lbl(md.damage_class.to_upper().left(4), 904, 11, 72, 22, 12, cls_color)
		slot_p.add_child(cls)
	else:
		var empty := _lbl("--- vide ---", 104, 11, 600, 22, 14, C_SLOT_EMPTY.lightened(0.5))
		slot_p.add_child(empty)

	# Bouton invisible pour la sélection
	var click := Button.new()
	click.flat = true
	click.position = Vector2(0, 0)
	click.size     = Vector2(984, 44)
	var flat_s := StyleBoxEmpty.new()
	click.add_theme_stylebox_override("normal", flat_s)
	click.add_theme_stylebox_override("hover",  flat_s)
	click.add_theme_stylebox_override("pressed",flat_s)
	var si := slot_idx
	click.pressed.connect(func():
		_selected_slot = si if _selected_slot != si else -1
		_refresh_content()
	)
	slot_p.add_child(click)


func _build_avail_move(x: int, y: int, md: MoveData, inst: PokemonInstance) -> void:
	var btn := Button.new()
	btn.position = Vector2(x, y)
	btn.size     = Vector2(200, 38)
	btn.text     = ""
	btn.flat     = true
	_style_button_raw(btn, C_AVAIL, C_BORDER, 5)
	_content_root.add_child(btn)

	# Logo de type (compact)
	var tpill := TypeIcon.make_pill(md.type, 54.0, 18.0, 8)
	tpill.position = Vector2(4, 4)
	tpill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tpill)

	var nm := _lbl(md.display_name, 64, 5, 104, 16, 12, C_TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(nm)

	var pw := _lbl("PWR %d" % md.power, 64, 22, 104, 14, 11, C_DIM)
	pw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pw)

	btn.pressed.connect(func(): _on_avail_clicked(md, inst))


func _on_avail_clicked(md: MoveData, inst: PokemonInstance) -> void:
	if _selected_slot < 0:
		# Pas de slot sélectionné — auto-équipe si < 4 moves
		if inst.equipped_moves.size() < 4:
			inst.equipped_moves.append(md)
		return

	# Swap : le move du slot sélectionné retourne dans "disponible"
	# (rien à faire car on filtre dynamiquement dans _get_available_moves)
	if _selected_slot < inst.equipped_moves.size():
		inst.equipped_moves[_selected_slot] = md
	else:
		# Slot vide
		inst.equipped_moves.append(md)

	_selected_slot = -1
	_refresh_content()


func _get_available_moves(inst: PokemonInstance) -> Array:
	var avail: Array = []
	for md: MoveData in inst.learned_moves:
		if md not in inst.equipped_moves:
			avail.append(md)
	return avail


# ── Helpers UI ────────────────────────────────────────────────────────

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


func _style_panel(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color    = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size  = 4
	p.add_theme_stylebox_override("panel", s)


func _style_panel_color(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color    = bg
	s.border_color = border
	s.set_border_width_all(1 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", s)


func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal",  s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover",   sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_font_size_override("font_size", 18)


func _style_button_raw(btn: Button, bg: Color, border: Color, radius: int) -> void:
	var s1 := StyleBoxFlat.new()
	s1.bg_color = bg; s1.border_color = border
	s1.set_border_width_all(1); s1.set_corner_radius_all(radius)
	btn.add_theme_stylebox_override("normal", s1)
	var s2 := StyleBoxFlat.new()
	s2.bg_color = bg.lightened(0.12); s2.border_color = border
	s2.set_border_width_all(1); s2.set_corner_radius_all(radius)
	btn.add_theme_stylebox_override("hover", s2)
	var s3 := StyleBoxFlat.new()
	s3.bg_color = bg.darkened(0.12); s3.border_color = border
	s3.set_border_width_all(1); s3.set_corner_radius_all(radius)
	btn.add_theme_stylebox_override("pressed", s3)


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5: return C_HP_HIGH
	if ratio > 0.2: return C_HP_MED
	return C_HP_LOW


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
