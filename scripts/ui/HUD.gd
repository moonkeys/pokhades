extends CanvasLayer

# ── Palette Pokéchill ─────────────────────────────────────────────────
const C_HP_HIGH   := Color(0.22, 0.68, 0.24)
const C_HP_MED    := Color(0.90, 0.68, 0.08)
const C_HP_LOW    := Color(0.88, 0.20, 0.14)
const C_XP        := Color(0.25, 0.55, 0.95)
const C_XP_BG     := Color(0.66, 0.58, 0.44)
const C_PANEL_BG  := Color(0.91, 0.85, 0.70)
const C_PANEL_BDR := Color(0.62, 0.50, 0.32)
const C_BAR_BG    := Color(0.70, 0.62, 0.48)
const C_COOLDOWN  := Color(0.76, 0.53, 0.17)
const C_OVERLAY   := Color(0.91, 0.85, 0.70, 0.93)
const C_SLOT_ACT  := Color(0.76, 0.53, 0.17)
const C_SLOT_BG   := Color(0.88, 0.82, 0.67)
const C_SLOT_BDR  := Color(0.62, 0.50, 0.32)
const C_FAINTED   := Color(0.55, 0.50, 0.42)
const C_TEXT      := Color(0.18, 0.13, 0.06)
const C_TEXT_MUTED := Color(0.48, 0.38, 0.22)

const SLOT_H   := 60
const SLOT_W   := 150
const SLOT_GAP := 4

const TYPE_COLORS: Dictionary = {
	"normal":   Color(0.62, 0.62, 0.58), "fire":     Color(0.95, 0.42, 0.12),
	"water":    Color(0.22, 0.52, 0.90), "electric": Color(0.96, 0.82, 0.08),
	"grass":    Color(0.28, 0.70, 0.24), "ice":      Color(0.56, 0.86, 0.90),
	"fighting": Color(0.74, 0.20, 0.16), "poison":   Color(0.60, 0.26, 0.66),
	"ground":   Color(0.86, 0.70, 0.36), "flying":   Color(0.64, 0.60, 0.92),
	"psychic":  Color(0.94, 0.22, 0.48), "bug":      Color(0.62, 0.70, 0.08),
	"rock":     Color(0.70, 0.60, 0.28), "ghost":    Color(0.44, 0.32, 0.60),
	"dragon":   Color(0.44, 0.20, 0.94), "dark":     Color(0.36, 0.26, 0.20),
	"steel":    Color(0.70, 0.70, 0.78), "fairy":    Color(0.94, 0.52, 0.72),
}

var _hp_bar:       ProgressBar
var _hp_fill:      StyleBoxFlat
var _hp_numbers:   Label
var _cooldown_bar: ProgressBar
var _ready_label:  Label
var _xp_bar:       ProgressBar
var _level_label:  Label
var _wave_label:   Label
var _kill_label:   Label
var _pokemon_name: Label

var _player_instance:  PokemonInstance
var _team_slots:       Array = []
var _follow_label:     Label = null

var _move_bar_panel:   Panel = null
var _move_slots:       Array = []
var _active_move_idx:  int   = 0


func _ready() -> void:
	_build_top_bar()
	_build_player_panel()


# ── Construction UI ──────────────────────────────────────────────────

func _build_player_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(12, 588)
	panel.size = Vector2(320, 128)
	_apply_panel_style(panel, C_PANEL_BG, C_PANEL_BDR, 10)
	add_child(panel)

	_pokemon_name = _label("PIKACHU", 12, 8, 192, 26, 19, C_TEXT, true)
	panel.add_child(_pokemon_name)

	_level_label = _label("NIV.10", 224, 8, 88, 22, 16, C_COOLDOWN, false, false, true)
	panel.add_child(_level_label)

	var pv := _label("PV", 12, 40, 32, 20, 14, C_TEXT_MUTED)
	panel.add_child(pv)

	_hp_bar = _progress_bar(48, 42, 176, 16)
	_hp_fill = _style_fill(C_HP_HIGH, 7)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_hp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 7))
	panel.add_child(_hp_bar)

	_hp_numbers = _label("-- / --", 230, 39, 84, 22, 13, C_TEXT_MUTED)
	panel.add_child(_hp_numbers)

	var atq := _label("ATQ", 12, 68, 34, 18, 13, C_COOLDOWN)
	panel.add_child(atq)

	_cooldown_bar = _progress_bar(48, 70, 176, 12)
	_cooldown_bar.add_theme_stylebox_override("fill", _style_fill(C_COOLDOWN, 5))
	_cooldown_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 5))
	panel.add_child(_cooldown_bar)

	_ready_label = _label("PRÊT !", 230, 66, 78, 18, 13, C_HP_HIGH)
	_ready_label.visible = true
	panel.add_child(_ready_label)

	var exp_lbl := _label("EXP", 12, 104, 34, 16, 13, C_XP)
	panel.add_child(exp_lbl)

	_xp_bar = _progress_bar(48, 106, 264, 10)
	_xp_bar.add_theme_stylebox_override("fill", _style_fill(C_XP, 4))
	_xp_bar.add_theme_stylebox_override("background", _style_bg(C_XP_BG, 4))
	panel.add_child(_xp_bar)


func _build_top_bar() -> void:
	var wave_panel := Panel.new()
	wave_panel.position = Vector2(470, 8)
	wave_panel.size = Vector2(340, 44)
	_apply_panel_style(wave_panel, C_OVERLAY, C_PANEL_BDR, 14)
	add_child(wave_panel)

	_wave_label = _label("Chargement...", 0, 8, 340, 28, 18, C_TEXT, false, true)
	wave_panel.add_child(_wave_label)

	var kill_panel := Panel.new()
	kill_panel.position = Vector2(930, 8)
	kill_panel.size = Vector2(340, 44)
	_apply_panel_style(kill_panel, C_OVERLAY, C_PANEL_BDR, 14)
	add_child(kill_panel)

	_kill_label = _label("0 / 100 vaincus", 0, 8, 340, 28, 16, C_TEXT_MUTED, false, true)
	kill_panel.add_child(_kill_label)

	var follow_panel := Panel.new()
	follow_panel.position = Vector2(170, 8)
	follow_panel.size = Vector2(140, 44)
	_apply_panel_style(follow_panel, C_OVERLAY, C_PANEL_BDR, 14)
	add_child(follow_panel)

	_follow_label = _label("[F] SUIVI", 0, 8, 140, 28, 14, C_HP_HIGH, false, true)
	follow_panel.add_child(_follow_label)


# ── Sidebar équipe ────────────────────────────────────────────────────

func setup_team(instances: Array, active_idx: int) -> void:
	for slot in _team_slots:
		slot["panel"].queue_free()
	_team_slots.clear()

	for i in instances.size():
		var slot: Dictionary = _create_team_slot(i)
		_team_slots.append(slot)
		var inst: PokemonInstance = instances[i]
		slot["name_lbl"].text = inst.data.name_fr.to_upper() if inst.data else "???"
		slot["hp_bar"].value  = inst.hp_ratio()
		slot["lv_lbl"].text   = "NIV.%d" % inst.level

	set_active_slot(active_idx)


func _create_team_slot(idx: int) -> Dictionary:
	var panel := Panel.new()
	panel.position = Vector2(8, 8 + idx * (SLOT_H + SLOT_GAP))
	panel.size = Vector2(SLOT_W, SLOT_H)
	_apply_panel_style(panel, C_SLOT_BG, C_SLOT_BDR, 8)
	add_child(panel)

	# Portrait
	var portrait_bg := ColorRect.new()
	portrait_bg.position = Vector2(5, 5)
	portrait_bg.size = Vector2(42, 50)
	portrait_bg.color = Color(0.74, 0.66, 0.50)
	panel.add_child(portrait_bg)

	var portrait_tex := TextureRect.new()
	portrait_tex.position = Vector2(5, 5)
	portrait_tex.size = Vector2(42, 50)
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(portrait_tex)

	# Nom
	var name_lbl := _label("???", 52, 3, SLOT_W - 58, 18, 13, C_TEXT)
	panel.add_child(name_lbl)

	# Barre HP
	var hp_bar := _progress_bar(52, 23, SLOT_W - 60, 9)
	var hp_fill := _style_fill(C_HP_HIGH, 4)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 4))
	hp_bar.value = 1.0
	panel.add_child(hp_bar)

	# Niveau
	var lv_lbl := _label("NIV.1", 52, 35, SLOT_W - 60, 14, 11, C_COOLDOWN)
	panel.add_child(lv_lbl)

	# Mini barre XP
	var xp_bar := _progress_bar(52, 50, SLOT_W - 60, 5)
	xp_bar.add_theme_stylebox_override("fill", _style_fill(C_XP, 2))
	xp_bar.add_theme_stylebox_override("background", _style_bg(C_XP_BG, 2))
	xp_bar.value = 0.0
	panel.add_child(xp_bar)

	return {
		"panel":        panel,
		"portrait_bg":  portrait_bg,
		"portrait_tex": portrait_tex,
		"name_lbl":     name_lbl,
		"hp_bar":       hp_bar,
		"hp_fill":      hp_fill,
		"lv_lbl":       lv_lbl,
		"xp_bar":       xp_bar,
	}


func set_active_slot(idx: int) -> void:
	for i in _team_slots.size():
		var slot: Dictionary = _team_slots[i]
		var s := StyleBoxFlat.new()
		s.bg_color = C_SLOT_BG
		s.set_corner_radius_all(8)
		s.shadow_color = Color(0, 0, 0, 0.18)
		s.shadow_size = 3
		if i == idx:
			s.border_color = C_SLOT_ACT
			s.set_border_width_all(3)
		else:
			s.border_color = C_SLOT_BDR
			s.set_border_width_all(1)
		slot["panel"].add_theme_stylebox_override("panel", s)


# ── API publique ──────────────────────────────────────────────────────

func setup_player(instance: PokemonInstance) -> void:
	_player_instance    = instance
	_pokemon_name.text  = instance.data.name_fr.to_upper()
	_hp_numbers.text    = "%d / %d" % [instance.current_hp, instance.max_hp]
	_hp_bar.value       = 1.0
	_cooldown_bar.value = 1.0
	_xp_bar.value       = instance.xp_ratio()
	_level_label.text   = "NIV.%d" % instance.level


func update_hp(ratio: float) -> void:
	_hp_bar.value = ratio
	if _player_instance:
		_hp_numbers.text = "%d / %d" % [_player_instance.current_hp, _player_instance.max_hp]
	if ratio > 0.5:
		_hp_fill.bg_color = C_HP_HIGH
	elif ratio > 0.2:
		_hp_fill.bg_color = C_HP_MED
	else:
		_hp_fill.bg_color = C_HP_LOW


func update_cooldown(ratio: float) -> void:
	_cooldown_bar.value = ratio
	if _ready_label:
		_ready_label.visible = ratio >= 1.0


func update_xp(ratio: float, level: int) -> void:
	_xp_bar.value     = ratio
	_level_label.text = "NIV.%d" % level


func update_team_hp(idx: int, ratio: float) -> void:
	if idx >= _team_slots.size():
		return
	var slot: Dictionary = _team_slots[idx]
	slot["hp_bar"].value = ratio
	if ratio <= 0.0:
		slot["hp_fill"].bg_color = C_FAINTED
	elif ratio > 0.5:
		slot["hp_fill"].bg_color = C_HP_HIGH
	elif ratio > 0.2:
		slot["hp_fill"].bg_color = C_HP_MED
	else:
		slot["hp_fill"].bg_color = C_HP_LOW


func update_team_portrait(idx: int, texture: Texture2D) -> void:
	if idx >= _team_slots.size():
		return
	_team_slots[idx]["portrait_tex"].texture = texture


func update_team_level(idx: int, level: int) -> void:
	if idx >= _team_slots.size():
		return
	_team_slots[idx]["lv_lbl"].text = "NIV.%d" % level


func update_team_xp(idx: int, ratio: float) -> void:
	if idx >= _team_slots.size():
		return
	_team_slots[idx]["xp_bar"].value = ratio


# ── Barre de capacités ────────────────────────────────────────────────

func setup_moves(moves: Array) -> void:
	if is_instance_valid(_move_bar_panel):
		_move_bar_panel.queue_free()
	_move_slots.clear()

	_move_bar_panel = Panel.new()
	_move_bar_panel.position = Vector2(338, 590)
	_move_bar_panel.size     = Vector2(930, 126)
	_apply_panel_style(_move_bar_panel, C_PANEL_BG, C_PANEL_BDR, 10)
	add_child(_move_bar_panel)

	var slot_w := 220
	var gap    := 10

	for i in 4:
		var move: MoveData = null
		if i < moves.size() and moves[i] != null:
			move = moves[i] as MoveData

		var sp := Panel.new()
		sp.position = Vector2(6 + i * (slot_w + gap), 6)
		sp.size     = Vector2(slot_w, 114)
		var accent: Color = TYPE_COLORS.get(move.type, C_PANEL_BDR) if move else C_PANEL_BDR
		_style_move_panel(sp, i == _active_move_idx, accent)
		_move_bar_panel.add_child(sp)

		# Touche (badge foncé)
		var key_bg := ColorRect.new()
		key_bg.position = Vector2(6, 6)
		key_bg.size     = Vector2(30, 30)
		key_bg.color    = Color(0.14, 0.11, 0.07, 0.92)
		sp.add_child(key_bg)
		var key_lbl := _label(str(i + 1), 6, 6, 30, 30, 16, Color(0.94, 0.88, 0.72), false, true)
		sp.add_child(key_lbl)

		if move:
			# Nom
			var name_lbl := _label(move.display_name, 42, 4, slot_w - 50, 34, 15, C_TEXT)
			sp.add_child(name_lbl)

			# Type badge (fond coloré)
			var t_col: Color = TYPE_COLORS.get(move.type, C_PANEL_BDR)
			var tbg    := ColorRect.new()
			tbg.position = Vector2(42, 42)
			tbg.size     = Vector2(76, 20)
			tbg.color    = t_col
			sp.add_child(tbg)
			sp.add_child(_label(move.type.to_upper(), 42, 42, 76, 20, 11, Color.WHITE, false, true))

			# Catégorie
			var cat := "PHY" if move.damage_class == "
			physical" else \
					   ("SPÉ" if move.damage_class == "special" else "EFF")
			sp.add_child(_label(cat, 124, 43, 36, 18, 11, C_TEXT_MUTED, false, true))

			# Puissance (dots + chiffre)
			if move.power > 0:
				var filled := clampi(int(ceil(float(move.power) / 30.0)), 0, 5)
				var dots   := ""
				for d in 5:
					dots += "●" if d < filled else "○"
				sp.add_child(_label(dots, 42, 68, 118, 22, 14, t_col))
				sp.add_child(_label(str(move.power), 162, 67, 48, 24, 14, C_TEXT_MUTED,
								false, false, true))
			else:
				sp.add_child(_label("Effet", 42, 70, slot_w - 52, 22, 12, C_TEXT_MUTED))
		else:
			sp.add_child(_label("— vide —", 42, 44, slot_w - 52, 28, 13,
							Color(0.55, 0.50, 0.40), false, true))

		_move_slots.append({"panel": sp, "move": move})

	set_active_move(_active_move_idx)


func set_active_move(idx: int) -> void:
	_active_move_idx = idx
	for i in _move_slots.size():
		var slot: Dictionary = _move_slots[i]
		var move: MoveData = slot.get("move")
		var accent: Color = TYPE_COLORS.get(move.type, C_PANEL_BDR) if move else C_PANEL_BDR
		_style_move_panel(slot["panel"], i == idx, accent)


func _style_move_panel(p: Panel, active: bool, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.87, 0.81, 0.66) if active else Color(0.83, 0.77, 0.62, 0.75)
	s.border_color = accent if active else C_PANEL_BDR
	s.set_border_width_all(3 if active else 1)
	s.set_corner_radius_all(8)
	s.shadow_color = Color(0, 0, 0, 0.14)
	s.shadow_size  = 3
	p.add_theme_stylebox_override("panel", s)


func set_follow_mode(active: bool) -> void:
	if _follow_label:
		if active:
			_follow_label.text = "[F] SUIVI"
			_follow_label.add_theme_color_override("font_color", C_HP_HIGH)
		else:
			_follow_label.text = "[F] INDÉP."
			_follow_label.add_theme_color_override("font_color", C_TEXT_MUTED)


func set_wave(text: String) -> void:
	if _wave_label:
		_wave_label.text = text


func set_kills(current: int, total: int) -> void:
	if _kill_label:
		_kill_label.text = "%d / %d vaincus" % [current, total]


func show_levelup(level: int) -> void:
	var lbl := Label.new()
	lbl.text = "Niveau %d !" % level
	lbl.position = Vector2(520, 540)
	lbl.size = Vector2(240, 40)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", C_COOLDOWN)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)

	var tween := create_tween()
	tween.tween_property(lbl, "position:y", 480.0, 1.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 1.8).set_delay(0.5)
	tween.tween_callback(lbl.queue_free)


func show_evolution(name_fr: String) -> void:
	var overlay := ColorRect.new()
	overlay.size  = Vector2(1280, 720)
	overlay.color = Color(0.91, 0.85, 0.70, 0)
	add_child(overlay)

	var lbl := Label.new()
	lbl.text     = "%s évolue !" % name_fr.to_upper()
	lbl.position = Vector2(290, 308)
	lbl.size     = Vector2(700, 60)
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", C_COOLDOWN)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate.a = 0.0
	add_child(lbl)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.88, 0.25)
	tween.parallel().tween_property(lbl, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.6)
	tween.tween_property(overlay, "color:a", 0.0, 0.55)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.55)
	tween.tween_callback(func():
		overlay.queue_free()
		lbl.queue_free()
	)


# ── Helpers ────────────────────────────────────────────────────────────

func _apply_panel_style(panel: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2 if border != Color.TRANSPARENT else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.18)
	s.shadow_size = 4
	panel.add_theme_stylebox_override("panel", s)


func _style_fill(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	return s


func _style_bg(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	return s


func _progress_bar(x: float, y: float, w: float, h: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = Vector2(x, y)
	bar.size     = Vector2(w, h)
	bar.max_value = 1.0
	bar.value     = 0.0
	bar.step      = 0.001
	bar.show_percentage = false
	return bar


func _label(
	text: String, x: float, y: float, w: float, h: float,
	font_size: int, color: Color,
	bold: bool = false, centered: bool = false, right_align: bool = false
) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.size     = Vector2(w, h)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if centered:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif right_align:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return lbl
