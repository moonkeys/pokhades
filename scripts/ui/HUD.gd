extends CanvasLayer

# ── Palette RPG parchemin ─────────────────────────────────────────────
const C_PARCH    := Color(0.86, 0.78, 0.60)        # fond parchemin (plus chaud/saturé)
const C_PARCH_DK := Color(0.76, 0.67, 0.48)        # parchemin foncé
const C_WOOD     := Color(0.20, 0.12, 0.04)         # bois très sombre
const C_WOOD_LT  := Color(0.36, 0.22, 0.08)         # bois moyen
const C_GOLD     := Color(0.88, 0.62, 0.10)         # or vif RPG
const C_GOLD_LT  := Color(0.98, 0.92, 0.70)         # or clair / texte
const C_TEXT     := Color(0.14, 0.09, 0.02)         # texte quasi-noir
const C_DIM      := Color(0.42, 0.32, 0.16)         # texte secondaire
const C_HP_HIGH  := Color(0.22, 0.80, 0.28)
const C_HP_MED   := Color(0.95, 0.72, 0.04)
const C_HP_LOW   := Color(0.92, 0.16, 0.10)
const C_ATQ      := Color(0.90, 0.56, 0.08)         # barre ATQ / cooldown
const C_XP       := Color(0.18, 0.48, 0.96)
const C_BAR_BG   := Color(0.30, 0.22, 0.10)         # fond de barre (sombre)
const C_FAINTED  := Color(0.40, 0.34, 0.26)
const C_EMPTY    := Color(0.50, 0.42, 0.30, 0.85)  # slot vide

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

# ── État interne ──────────────────────────────────────────────────────
var _player_instance:  PokemonInstance = null
var _player_type:      String          = "normal"

var _hp_fill:          StyleBoxFlat    = null
var _hp_numbers:       Label           = null
var _hp_bar:           ProgressBar     = null
var _cooldown_bar:     ProgressBar     = null
var _ready_label:      Label           = null
var _xp_bar:           ProgressBar     = null
var _level_label:      Label           = null
var _pokemon_name:     Label           = null
var _portrait_tex:     TextureRect     = null
var _player_panel:     Panel           = null
var _type_pill:        Control         = null

var _wave_label:       Label           = null
var _kill_label:       Label           = null
var _follow_label:     Label           = null

var _interact_prompt:  Panel           = null
var _interact_label:   Label           = null

var _team_slots:       Array           = []
var _move_slots:       Array           = []
var _active_slot_idx:  int             = 0
var _active_move_idx:  int             = 0
var _cooldown_ratio:   float           = 1.0
var _active_pp_bar:    ProgressBar     = null   # barre PP du slot actif


func _ready() -> void:
	_build_top()
	_build_player_panel()
	_build_interact_prompt()


# ══════════════════════════════════════════════════════════════════════
# CONSTRUCTION UI
# ══════════════════════════════════════════════════════════════════════

func _build_top() -> void:
	# ── Bannière scroll centrale ──────────────────────────────────────
	var banner := _ScrollBanner.new()
	banner.position = Vector2(420, 8)
	banner.size     = Vector2(440, 50)
	add_child(banner)

	_wave_label = _lbl("Chargement…", 0, 0, 440, 50, 17, C_TEXT, true)
	banner.add_child(_wave_label)

	# ── Compteur de kills (droite) ────────────────────────────────────
	var kill_panel := _wood_panel(Vector2(1086, 8), Vector2(186, 50))
	add_child(kill_panel)

	var pkball := _lbl("⊕", 8, 8, 28, 34, 22, C_GOLD)
	kill_panel.add_child(pkball)

	_kill_label = _lbl("0 / ? vaincus", 38, 12, 142, 28, 14, C_GOLD_LT)
	kill_panel.add_child(_kill_label)

	# ── Mode suivi (petit badge) ──────────────────────────────────────
	var follow_panel := _wood_panel(Vector2(1086, 62), Vector2(186, 32))
	add_child(follow_panel)
	_follow_label = _lbl("[F]  SUIVI", 0, 4, 186, 24, 13, C_GOLD_LT, true)
	follow_panel.add_child(_follow_label)


func _build_player_panel() -> void:
	# ── Panneau infos joueur (bas-gauche) 330×130 ──────────────────────
	_player_panel = _wood_panel(Vector2(4, 586), Vector2(330, 132))
	add_child(_player_panel)
	var panel := _player_panel

	# Cadre intérieur sombre pour le portrait (colonne gauche)
	var port_bg := ColorRect.new()
	port_bg.position = Vector2(3, 3)
	port_bg.size     = Vector2(86, 126)
	port_bg.color    = Color(0.16, 0.10, 0.04)
	panel.add_child(port_bg)

	# Placeholder parchemin (freed dès que le sprite charge)
	var ph := ColorRect.new()
	ph.name     = "PH_PLAYER"
	ph.position = Vector2(4, 4)
	ph.size     = Vector2(84, 124)
	ph.color    = Color(0.82, 0.74, 0.58)
	panel.add_child(ph)

	_portrait_tex = TextureRect.new()
	_portrait_tex.position    = Vector2(4, 4)
	_portrait_tex.size        = Vector2(84, 124)
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	panel.add_child(_portrait_tex)

	# Séparateur bois
	var sep := ColorRect.new()
	sep.position = Vector2(91, 3)
	sep.size     = Vector2(3, 126)
	sep.color    = C_WOOD
	panel.add_child(sep)

	# ── Colonne stats (x=98) ──
	const SX := 98.0

	# Nom Pokémon
	_pokemon_name = _lbl("???", SX, 4, 180, 24, 16, C_TEXT, false, true)
	panel.add_child(_pokemon_name)

	# Logo de type + Niveau sur la même ligne
	_type_pill = TypeIcon.make_pill("normal", 70.0, 19.0, 10)
	_type_pill.position = Vector2(SX, 28)
	panel.add_child(_type_pill)

	_level_label = _lbl("NIV. 1", SX + 78, 29, 94, 17, 12, C_GOLD)
	panel.add_child(_level_label)

	# Barre PV
	panel.add_child(_lbl("PV", SX, 50, 24, 16, 11, C_DIM))
	_hp_bar  = _progress_bar(SX + 24, 53, 148, 13)
	_hp_fill = _style_fill(C_HP_HIGH, 5)
	_hp_bar.add_theme_stylebox_override("fill",       _hp_fill)
	_hp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 5))
	panel.add_child(_hp_bar)
	_hp_numbers = _lbl("-- / --", SX + 24, 68, 148, 14, 10, C_DIM, true)
	panel.add_child(_hp_numbers)

	# Barre ATQ
	panel.add_child(_lbl("ATQ", SX, 85, 24, 14, 10, C_ATQ))
	_cooldown_bar = _progress_bar(SX + 24, 87, 120, 10)
	_cooldown_bar.add_theme_stylebox_override("fill",       _style_fill(C_ATQ, 4))
	_cooldown_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 4))
	panel.add_child(_cooldown_bar)
	_ready_label = _lbl("⚡ PRÊT !", SX + 148, 83, 80, 16, 11, C_HP_HIGH)
	panel.add_child(_ready_label)

	# Barre EXP
	panel.add_child(_lbl("EXP", SX, 101, 24, 12, 9, C_XP))
	_xp_bar = _progress_bar(SX + 24, 103, 204, 7)
	_xp_bar.add_theme_stylebox_override("fill",       _style_fill(C_XP, 3))
	_xp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 3))
	panel.add_child(_xp_bar)


# ══════════════════════════════════════════════════════════════════════
# SLOTS ÉQUIPE (gauche, empilés)
# ══════════════════════════════════════════════════════════════════════

func setup_team(instances: Array, active_idx: int) -> void:
	for slot in _team_slots:
		if is_instance_valid(slot.get("panel")):
			slot["panel"].queue_free()
	_team_slots.clear()

	const SLOT_H   := 56
	const SLOT_W   := 182
	const SLOT_GAP := 4

	for i in instances.size():
		var inst: PokemonInstance = instances[i]
		var panel := _wood_panel(Vector2(8, 8 + i * (SLOT_H + SLOT_GAP)), Vector2(SLOT_W, SLOT_H))
		add_child(panel)

		# Portrait miniature
		var ph := ColorRect.new()
		ph.name     = "PH"
		ph.position = Vector2(4, 4)
		ph.size     = Vector2(44, 48)
		ph.color    = Color(0.64, 0.56, 0.42)
		panel.add_child(ph)

		var ptex := TextureRect.new()
		ptex.position    = Vector2(3, 2)
		ptex.size        = Vector2(46, 52)
		ptex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ptex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		panel.add_child(ptex)

		# Nom
		var nm := _lbl(inst.data.name_fr.to_upper() if inst.data else "???",
			52, 3, SLOT_W - 58, 18, 12, C_TEXT, false, true)
		panel.add_child(nm)

		# Barre HP
		var hp_fill := _style_fill(C_HP_HIGH, 4)
		var hp_bar  := _progress_bar(52, 23, SLOT_W - 60, 10)
		hp_bar.add_theme_stylebox_override("fill",       hp_fill)
		hp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 4))
		hp_bar.value = inst.hp_ratio()
		panel.add_child(hp_bar)

		# Niveau
		var lv := _lbl("NIV.%d" % inst.level, 52, 36, 70, 14, 10, C_GOLD)
		panel.add_child(lv)

		# Mini XP
		var xp := _progress_bar(52, 48, SLOT_W - 60, 4)
		xp.add_theme_stylebox_override("fill",       _style_fill(C_XP, 2))
		xp.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 2))
		xp.value = inst.xp_ratio()
		panel.add_child(xp)

		_team_slots.append({
			"panel": panel, "portrait_tex": ptex, "portrait_bg": ph,
			"name_lbl": nm, "hp_bar": hp_bar, "hp_fill": hp_fill,
			"lv_lbl": lv, "xp_bar": xp,
		})

	set_active_slot(active_idx)


func set_active_slot(idx: int) -> void:
	_active_slot_idx = idx
	for i in _team_slots.size():
		var slot: Dictionary = _team_slots[i]
		var s := StyleBoxFlat.new()
		s.bg_color = C_PARCH
		s.set_corner_radius_all(8)
		if i == idx:
			s.border_color = C_GOLD
			s.set_border_width_all(3)
		else:
			s.border_color = C_WOOD
			s.set_border_width_all(2)
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size  = 4
		slot["panel"].add_theme_stylebox_override("panel", s)


# ══════════════════════════════════════════════════════════════════════
# SLOTS DE CAPACITÉS (bas, 4 colonnes)
# ══════════════════════════════════════════════════════════════════════

func setup_moves(moves: Array) -> void:
	if is_instance_valid(_active_pp_bar):
		_active_pp_bar = null
	for slot in _move_slots:
		if is_instance_valid(slot.get("panel")):
			slot["panel"].queue_free()
	_move_slots.clear()

	const TOTAL_W := 964
	const SLOT_H  := 130
	const GAP     := 4
	const SLOT_W  := (TOTAL_W - GAP * 3) / 4
	const START_X := 316

	for i in 4:
		var move: MoveData = null
		if i < moves.size() and moves[i] != null:
			move = moves[i] as MoveData

		var t_col: Color = TYPE_COLORS.get(move.type if move else "normal", C_WOOD_LT)
		# Slot actif : teinte type plus marquée (18%) ; inactif : légère (10%) ; vide : gris-brun
		var blend := 0.18 if (i == _active_move_idx and move != null) else 0.10
		var slot_bg: Color = C_PARCH.lerp(t_col, blend) if move else Color(0.58, 0.50, 0.38)

		var panel := Panel.new()
		panel.position = Vector2(START_X + i * (SLOT_W + GAP), 586)
		panel.size     = Vector2(SLOT_W, SLOT_H)
		_slot_style(panel, slot_bg, t_col if move else C_WOOD, i == _active_move_idx and move != null)
		add_child(panel)

		# Touche clavier — façon "keycap" : claire = active, grise = verrouillée
		var nbg := Panel.new()
		nbg.position = Vector2(5, 5)
		nbg.size     = Vector2(28, 28)
		var nb_style := StyleBoxFlat.new()
		if move:
			nb_style.bg_color     = C_GOLD if i == _active_move_idx else C_WOOD_LT
			nb_style.border_color = C_GOLD_LT
			nb_style.set_border_width_all(2)
		else:
			nb_style.bg_color     = Color(0.40, 0.36, 0.30)
			nb_style.border_color = Color(0.30, 0.27, 0.22)
			nb_style.set_border_width_all(2)
		nb_style.set_corner_radius_all(5)
		nbg.add_theme_stylebox_override("panel", nb_style)
		panel.add_child(nbg)
		var nb_col := (C_WOOD if i == _active_move_idx else C_TEXT) if move else Color(0.62, 0.58, 0.50)
		panel.add_child(_lbl(str(i + 1), 5, 5, 28, 28, 15, nb_col, true))

		var pp_bar: ProgressBar = null

		if move:
			# Nom + étoile
			panel.add_child(_lbl(move.display_name, 38, 4, SLOT_W - 52, 22, 14, C_TEXT, false, true))
			panel.add_child(_lbl("✦", SLOT_W - 20, 4, 18, 22, 12, C_GOLD))

			# Logo de type
			var tpill := TypeIcon.make_pill(move.type, 73.0, 18.0, 9)
			tpill.position = Vector2(38, 29)
			panel.add_child(tpill)

			# Badge catégorie
			var cat   := "PHY" if move.damage_class == "physical" else \
						 ("SPÉ" if move.damage_class == "special"  else "EFF")
			var cbg   := ColorRect.new()
			cbg.position = Vector2(112, 29)
			cbg.size     = Vector2(38, 18)
			cbg.color    = C_WOOD_LT
			panel.add_child(cbg)
			panel.add_child(_lbl(cat, 112, 29, 38, 18, 10, C_GOLD_LT, true))

			# Puissance
			if move.power > 0:
				panel.add_child(_lbl("Puissance  %d" % move.power, 38, 52, SLOT_W - 46, 18, 12, C_DIM))
			else:
				panel.add_child(_lbl("Puissance  —", 38, 52, SLOT_W - 46, 18, 12, C_DIM))

			# PP (barre + texte)
			panel.add_child(_lbl("PP", 38, 74, 24, 16, 11, C_DIM))
			pp_bar = _progress_bar(62, 77, SLOT_W - 72, 11)
			pp_bar.add_theme_stylebox_override("fill",       _style_fill(t_col, 4))
			pp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 4))
			pp_bar.value = 1.0
			panel.add_child(pp_bar)

			if i == _active_move_idx:
				_active_pp_bar = pp_bar
				_active_pp_bar.value = _cooldown_ratio

			# Dots cosmétiques (puissance relative)
			var filled := clampi(int(ceil(float(move.power) / 25.0)), 1, 8) if move.power > 0 else 4
			var dots   := ""
			for d in 8:
				dots += "●" if d < filled else "○"
			panel.add_child(_lbl(dots, 38, 92, SLOT_W - 46, 18, 11, t_col.lightened(0.1)))
		else:
			# Slot verrouillé — la touche ne fait rien tant qu'il n'est pas débloqué
			panel.add_child(_lbl("Verrouillé", 0, 46, SLOT_W, 22, 13, C_EMPTY, true))
			var lock_hint := _lbl("Débloquer chez le Tuteur", 4, 68, SLOT_W - 8, 32, 10, C_EMPTY, true)
			lock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add_child(lock_hint)

			# Ligne PP grisée (non fonctionnelle, juste cosmétique)
			pp_bar = _progress_bar(38, 90, SLOT_W - 46, 8)
			pp_bar.add_theme_stylebox_override("fill",       _style_fill(C_BAR_BG, 3))
			pp_bar.add_theme_stylebox_override("background", _style_bg(C_BAR_BG, 3))
			pp_bar.value = 0.0
			panel.add_child(pp_bar)
			pp_bar = null  # ne pas tracker la barre vide

		_move_slots.append({"panel": panel, "move": move, "pp_bar": pp_bar})

	set_active_move(_active_move_idx)


func set_active_move(idx: int) -> void:
	_active_move_idx = idx
	_active_pp_bar   = null
	for i in _move_slots.size():
		var slot: Dictionary = _move_slots[i]
		var move: MoveData   = slot.get("move")
		var t_col: Color     = TYPE_COLORS.get(move.type if move else "normal", C_WOOD_LT)
		var blend2 := 0.18 if (i == idx and move != null) else 0.10
		var bg2: Color = C_PARCH.lerp(t_col, blend2) if move else Color(0.58, 0.50, 0.38)
		_slot_style(slot["panel"], bg2, t_col if move else C_WOOD, i == idx and move != null)
		if i == idx and slot.get("pp_bar") != null:
			_active_pp_bar = slot["pp_bar"]
			_active_pp_bar.value = _cooldown_ratio


func _slot_style(p: Panel, bg: Color, border: Color, active: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if active:
		s.border_color = border.lightened(0.15)
		s.set_border_width_all(4)
		s.shadow_color = border
		s.shadow_size  = 6
	else:
		s.border_color = C_WOOD
		s.set_border_width_all(3)
		s.shadow_color = Color(0, 0, 0, 0.40)
		s.shadow_size  = 4
	s.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", s)


# ══════════════════════════════════════════════════════════════════════
# API PUBLIQUE
# ══════════════════════════════════════════════════════════════════════

func setup_player(instance: PokemonInstance) -> void:
	_player_instance     = instance
	_player_type         = instance.data.types[0] if not instance.data.types.is_empty() else "normal"
	_pokemon_name.text   = instance.data.name_fr.to_upper()
	_level_label.text    = "NIV. %d" % instance.level
	_hp_numbers.text     = "%d / %d" % [instance.current_hp, instance.max_hp]
	_hp_bar.value        = instance.hp_ratio()
	_cooldown_bar.value  = 1.0
	_xp_bar.value        = instance.xp_ratio()
	_ready_label.visible = true
	if is_instance_valid(_type_pill):
		var new_pill := TypeIcon.make_pill(_player_type, 70.0, 19.0, 10)
		new_pill.position = _type_pill.position
		_type_pill.get_parent().add_child(new_pill)
		_type_pill.queue_free()
		_type_pill = new_pill
	if is_instance_valid(_portrait_tex) and instance.portrait_texture != null:
		_portrait_tex.texture = instance.portrait_texture


func update_hp(ratio: float) -> void:
	if is_instance_valid(_hp_bar):
		_hp_bar.value = ratio
	if _player_instance:
		_hp_numbers.text = "%d / %d" % [_player_instance.current_hp, _player_instance.max_hp]
	if is_instance_valid(_hp_fill):
		_hp_fill.bg_color = C_HP_HIGH if ratio > 0.5 else (C_HP_MED if ratio > 0.2 else C_HP_LOW)


func update_cooldown(ratio: float) -> void:
	_cooldown_ratio = ratio
	if is_instance_valid(_cooldown_bar):
		_cooldown_bar.value = ratio
	if is_instance_valid(_ready_label):
		_ready_label.visible = ratio >= 1.0
	if is_instance_valid(_active_pp_bar):
		_active_pp_bar.value = ratio


func update_xp(ratio: float, level: int) -> void:
	if is_instance_valid(_xp_bar):
		_xp_bar.value = ratio
	if is_instance_valid(_level_label):
		_level_label.text = "NIV. %d" % level


func update_team_hp(idx: int, ratio: float) -> void:
	if idx >= _team_slots.size(): return
	var slot: Dictionary = _team_slots[idx]
	slot["hp_bar"].value = ratio
	var c := C_HP_HIGH if ratio > 0.5 else (C_HP_MED if ratio > 0.2 else (C_HP_LOW if ratio > 0.0 else C_FAINTED))
	(slot["hp_fill"] as StyleBoxFlat).bg_color = c


func update_team_portrait(idx: int, texture: Texture2D) -> void:
	if idx >= _team_slots.size(): return
	var slot: Dictionary = _team_slots[idx]
	var ptex: TextureRect = slot["portrait_tex"]
	ptex.texture = texture
	var ph: Node = (slot["panel"] as Panel).get_node_or_null("PH")
	if ph: ph.queue_free()
	if idx == _active_slot_idx and is_instance_valid(_portrait_tex):
		_portrait_tex.texture = texture
		if is_instance_valid(_player_panel):
			var ph2: Node = _player_panel.get_node_or_null("PH_PLAYER")
			if ph2: ph2.queue_free()


func update_team_level(idx: int, level: int) -> void:
	if idx >= _team_slots.size(): return
	_team_slots[idx]["lv_lbl"].text = "NIV.%d" % level


func update_team_xp(idx: int, ratio: float) -> void:
	if idx >= _team_slots.size(): return
	_team_slots[idx]["xp_bar"].value = ratio


func _build_interact_prompt() -> void:
	_interact_prompt = _wood_panel(Vector2(490, 510), Vector2(300, 38))
	_interact_prompt.visible = false
	add_child(_interact_prompt)
	_interact_label = _lbl("", 0, 7, 300, 24, 14, C_GOLD_LT, true, true)
	_interact_prompt.add_child(_interact_label)


## Affiche/masque le prompt d'interaction (ex : "Appuyer sur [E] pour ouvrir")
## quand le joueur est à portée d'un objet interactif (coffre, etc).
func set_interact_prompt(show: bool, text: String = "") -> void:
	if not is_instance_valid(_interact_prompt):
		return
	_interact_prompt.visible = show
	if show:
		_interact_label.text = text


func set_wave(text: String) -> void:
	if is_instance_valid(_wave_label):
		_wave_label.text = text


func set_kills(current: int, total: int) -> void:
	if is_instance_valid(_kill_label):
		_kill_label.text = "%d / %d vaincus" % [current, total]


func set_follow_mode(active: bool) -> void:
	if not is_instance_valid(_follow_label): return
	_follow_label.text = "[F]  SUIVI" if active else "[F]  INDÉP."
	_follow_label.add_theme_color_override("font_color",
		C_HP_HIGH if active else C_DIM)


func show_levelup(level: int) -> void:
	var lbl := Label.new()
	lbl.text = "Niveau %d !" % level
	lbl.position = Vector2(500, 480)
	lbl.size     = Vector2(280, 48)
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", C_GOLD)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.60))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", 420.0, 1.8).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.8).set_delay(0.6)
	tw.tween_callback(lbl.queue_free)


func show_evolution(name_fr: String) -> void:
	var overlay := ColorRect.new()
	overlay.size  = Vector2(1280, 720)
	overlay.color = Color(0.91, 0.85, 0.70, 0)
	add_child(overlay)
	var lbl := Label.new()
	lbl.text     = "%s évolue !" % name_fr.to_upper()
	lbl.position = Vector2(290, 308)
	lbl.size     = Vector2(700, 64)
	lbl.add_theme_font_size_override("font_size", 46)
	lbl.add_theme_color_override("font_color", C_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.modulate.a = 0.0
	add_child(lbl)
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.88, 0.25)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.6)
	tw.tween_property(overlay, "color:a", 0.0, 0.55)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func() -> void: overlay.queue_free(); lbl.queue_free())


## Bandeau discret (n'interrompt pas le combat) annonçant un nouveau Pokémon recrutable.
func show_unlock(name_fr: String) -> void:
	var panel := _wood_panel(Vector2(340, 110), Vector2(600, 56))
	panel.modulate.a = 0.0
	add_child(panel)

	var lbl := Label.new()
	lbl.text     = "⊕  %s rejoint la Rébellion !" % name_fr.to_upper()
	lbl.size     = Vector2(600, 56)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", C_GOLD_LT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)

	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


# ══════════════════════════════════════════════════════════════════════
# BANNIÈRE SCROLL (forme pointue gauche/droite)
# ══════════════════════════════════════════════════════════════════════

class _ScrollBanner extends Control:
	func _draw() -> void:
		var w  := size.x
		var h  := size.y
		var pt := 22.0   # longueur de la pointe

		# Fond parchemin (forme scroll)
		var pts := PackedVector2Array([
			Vector2(0,     h * 0.5),
			Vector2(pt,    0),
			Vector2(w - pt, 0),
			Vector2(w,     h * 0.5),
			Vector2(w - pt, h),
			Vector2(pt,    h),
		])
		draw_polygon(pts, PackedColorArray([Color(0.91, 0.85, 0.70)]))

		# Bord bois
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], Color(0.28, 0.18, 0.08), 2.0)

		# Ligne décorative intérieure
		var inset := 5.0
		var inner := PackedVector2Array([
			Vector2(inset,        h * 0.5),
			Vector2(pt + inset,   inset),
			Vector2(w - pt - inset, inset),
			Vector2(w - inset,   h * 0.5),
			Vector2(w - pt - inset, h - inset),
			Vector2(pt + inset,   h - inset),
		])
		for i in inner.size():
			draw_line(inner[i], inner[(i + 1) % inner.size()],
				Color(0.44, 0.30, 0.14, 0.50), 1.0)

		# Icône boussole
		draw_circle(Vector2(pt + 14, h * 0.5), 9, Color(0.28, 0.18, 0.08, 0.60))
		draw_circle(Vector2(pt + 14, h * 0.5), 6, Color(0.91, 0.85, 0.70))


# ══════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════

func _wood_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos; p.size = sz
	var s := StyleBoxFlat.new()
	s.bg_color     = C_PARCH
	s.border_color = C_WOOD
	s.set_border_width_all(4)
	s.set_corner_radius_all(8)
	# Double-bord : inner highlight doré
	s.border_color = C_WOOD
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size  = 7
	p.add_theme_stylebox_override("panel", s)
	# Liseré doré intérieur via contenu enfant (ajouté par l'appelant si besoin)
	return p


func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, col: Color, centered: bool = false,
		bold: bool = false, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.40))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if centered: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif right:  l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _progress_bar(x: float, y: float, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = Vector2(x, y); b.size = Vector2(w, h)
	b.max_value = 1.0; b.value = 0.0; b.step = 0.001
	b.show_percentage = false
	return b


func _style_fill(col: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = col; s.set_corner_radius_all(r); return s

func _style_bg(col: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = col; s.set_corner_radius_all(r); return s
