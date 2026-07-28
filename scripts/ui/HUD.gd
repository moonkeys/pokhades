extends CanvasLayer

## HUD de run — refonte "clarté d'abord" (même API publique que l'ancien).
## Hiérarchie visuelle :
##   • bandeau FIN en haut : zone/événements (gauche), kills + ₽ (droite) ;
##   • mini-cartes compagnons discrètes sous le bandeau (haut-gauche) ;
##   • grand panneau du Pokémon CONTRÔLÉ en bas-gauche (portrait, PV avec
##     barre fantôme, EXP) ;
##   • 4 keycaps de capacités en bas, cooldown intégré en overlay ;
##   • pips de dash au-dessus des keycaps ;
##   • toasts empilés en haut-droite (level up / évolution / recrutement) ;
##   • vignette rouge pulsante quand le Pokémon contrôlé est bas en PV.

# ── Palette alignée sur UiKit (bois & parchemin) — le HUD reste
# translucide pour ne pas masquer le combat, mais parle exactement le même
# langage que les menus (mockups utilisateur). ──
const C_PANEL   := Color(0.22, 0.14, 0.09, 0.88)     # bois sombre (UiKit.WOOD_DARK)
const C_PANEL_2 := Color(0.33, 0.22, 0.14, 0.92)     # bois (UiKit.WOOD)
const C_BORDER  := Color(0.55, 0.38, 0.22)           # liseré brun (UiKit.BROWN_CARD)
const C_GOLD    := Color(0.95, 0.76, 0.31)           # UiKit.GOLD
const C_TEXT    := Color(0.96, 0.92, 0.80)           # crème
const C_DIM     := Color(0.62, 0.55, 0.42)
const C_HP_HIGH := Color(0.28, 0.82, 0.34)
const C_HP_MED  := Color(0.95, 0.72, 0.10)
const C_HP_LOW  := Color(0.92, 0.20, 0.14)
const C_GHOST   := Color(0.95, 0.92, 0.85, 0.85)     # barre fantôme (dégâts récents)
const C_XP      := Color(0.30, 0.58, 0.95)
const C_KO      := Color(0.45, 0.38, 0.30)

const LOW_HP_THRESHOLD := 0.25

# ── Overlays de barre de PV (assets Essentials — Party screen) ─────────
# overlay_hp.png : 96×24, 3 bandes de 8px (vert/jaune/rouge, de haut en
# bas) — on ne montre que la portion [0, ratio*96] pour l'effet de vidage.
# overlay_hp_back.png : le cadre (fond) de la barre, sans remplissage.
const HP_OVERLAY_PATH := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/UI/Party/overlay_hp.png"
const HP_BACK_PATH     := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/UI/Party/overlay_hp_back.png"
const HP_OVERLAY_NATIVE_W := 96.0
const HP_OVERLAY_ROW_H    := 8.0
static var _hp_overlay_tex: Texture2D = null
static var _hp_back_tex:    Texture2D = null

# ── État ──────────────────────────────────────────────────────────────
var _player_instance: PokemonInstance = null

var _wave_label:   Label = null
var _kill_label:   Label = null
var _money_label:  Label = null
var _follow_label: Label = null

var _portrait_tex: TextureRect = null
var _name_label:   Label       = null
var _level_label:  Label       = null
var _type_holder:  Control     = null
var _hp_fill:      TextureRect = null   # overlay_hp.png (3 teintes), croqué selon le ratio
var _hp_ghost:     ColorRect   = null
var _hp_numbers:   Label       = null
var _xp_fill:      ColorRect   = null

const HP_BAR_W := 208.0
const TEAM_BAR_W := 96.0

var _team_cards: Array = []   # [{root, portrait, fill, ghost, lvl, name}]
var _active_slot_idx: int = 0

var _move_slots: Array = []   # [{panel, cd_overlay, has_move}]
var _active_move_idx: int = 0

var _dash_pips: Array = []    # Array[ColorRect]

var _prompt_panel: Panel = null
var _prompt_label: Label = null

var _toast_stack: Array = []  # toasts actifs (pour empiler verticalement)

var _vignette: TextureRect = null
var _low_hp:   bool = false
var _pulse_t:  float = 0.0

# Barres fantômes : cibles à rattraper lentement  [ {fill_w cible} par barre ]
var _ghost_targets: Dictionary = {}   # ColorRect (ghost) -> largeur cible


func _ready() -> void:
	_build_top_band()
	_build_player_panel()
	_build_prompt()
	_build_vignette()


func _process(delta: float) -> void:
	# Barres fantômes : descendent en retard vers la vraie valeur — on "voit"
	# le morceau de vie qui vient de partir.
	for ghost in _ghost_targets.keys():
		if not is_instance_valid(ghost):
			_ghost_targets.erase(ghost)
			continue
		var target: float = _ghost_targets[ghost]
		if ghost.size.x > target:
			ghost.size.x = maxf(target, ghost.size.x - delta * 140.0)
		else:
			ghost.size.x = target
	# Vignette basse-vie : pulse doux
	if _low_hp and is_instance_valid(_vignette):
		_pulse_t += delta * 3.0
		_vignette.modulate.a = 0.55 + sin(_pulse_t) * 0.25


# ══════════════════════════════════════════════════════════════════════
# BANDEAU HAUT
# ══════════════════════════════════════════════════════════════════════

func _build_top_band() -> void:
	var band := Panel.new()
	band.position = Vector2(0, 0)
	band.size     = Vector2(1280, 42)
	var st := StyleBoxFlat.new()
	st.bg_color = C_PANEL
	st.border_color = C_BORDER
	st.border_width_bottom = 2
	band.add_theme_stylebox_override("panel", st)
	add_child(band)

	_wave_label = _lbl("…", 16, 6, 720, 30, 17, C_TEXT)
	band.add_child(_wave_label)

	_kill_label = _lbl("⊕ 0 / 0", 940, 6, 130, 30, 16, C_GOLD)
	band.add_child(_kill_label)

	_money_label = _lbl("₽ 0", 1080, 6, 110, 30, 16, C_GOLD)
	band.add_child(_money_label)

	_follow_label = _lbl("[F] Suivi", 1196, 8, 80, 26, 12, C_DIM)
	band.add_child(_follow_label)


func set_wave(text: String) -> void:
	if not is_instance_valid(_wave_label):
		return
	if _wave_label.text == text:
		return
	_wave_label.text = text
	# Petit "pop" à chaque nouveau message — l'œil est attiré sans gros bandeau
	_wave_label.pivot_offset = Vector2(0, 15)
	var tw := create_tween()
	_wave_label.scale = Vector2(1.12, 1.12)
	tw.tween_property(_wave_label, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)


func set_kills(current: int, total: int) -> void:
	if is_instance_valid(_kill_label):
		_kill_label.text = "⊕ %d / %d" % [current, total]


func update_money(amount: int) -> void:
	if not is_instance_valid(_money_label):
		return
	_money_label.text = "₽ %d" % amount
	_money_label.pivot_offset = Vector2(20, 15)
	var tw := create_tween()
	_money_label.scale = Vector2(1.2, 1.2)
	tw.tween_property(_money_label, "scale", Vector2.ONE, 0.2)


func set_follow_mode(active: bool) -> void:
	if is_instance_valid(_follow_label):
		_follow_label.text = "[F] Suivi" if active else "[F] Libre"
		_follow_label.add_theme_color_override("font_color", C_GOLD if active else C_DIM)


# ══════════════════════════════════════════════════════════════════════
# COMPAGNONS — mini-cartes discrètes (haut-gauche)
# ══════════════════════════════════════════════════════════════════════

func setup_team(instances: Array, active_idx: int) -> void:
	for card in _team_cards:
		if is_instance_valid(card.get("root")):
			card["root"].queue_free()
	_team_cards.clear()
	_active_slot_idx = active_idx

	for i in instances.size():
		var inst: PokemonInstance = instances[i]
		var root := Panel.new()
		root.position = Vector2(8, 52 + i * 46)
		root.size     = Vector2(178, 42)
		_panel_style(root, i == active_idx)
		add_child(root)

		var pframe := ColorRect.new()
		pframe.position = Vector2(4, 4)
		pframe.size     = Vector2(34, 34)
		pframe.color    = Color(0, 0, 0, 0.45)
		root.add_child(pframe)

		var portrait := TextureRect.new()
		portrait.position = Vector2(4, 4)
		portrait.size     = Vector2(34, 34)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if is_instance_valid(inst.portrait_texture):
			portrait.texture = inst.portrait_texture
		root.add_child(portrait)

		var nm := _lbl(inst.data.name_fr.capitalize(), 44, 3, 100, 16, 11, C_TEXT)
		root.add_child(nm)
		var lvl := _lbl("N.%d" % inst.level, 146, 3, 30, 16, 10, C_DIM)
		root.add_child(lvl)

		# Barre PV fine + fantôme (cadre + remplissage Essentials)
		var bg := _make_hp_back(Vector2(TEAM_BAR_W + 2, 8))
		bg.position = Vector2(44, 22)
		root.add_child(bg)
		var ghost := ColorRect.new()
		ghost.position = Vector2(45, 23)
		ghost.size     = Vector2(TEAM_BAR_W * inst.hp_ratio(), 6)
		ghost.color    = C_GHOST
		root.add_child(ghost)
		var fill := _make_hp_fill(TEAM_BAR_W / HP_OVERLAY_NATIVE_W, 6.0)
		fill.position = Vector2(45, 23)
		_update_hp_fill(fill, inst.hp_ratio())
		root.add_child(fill)

		# Barre XP ultra-fine sous les PV
		var xpb := ColorRect.new()
		xpb.position = Vector2(45, 33)
		xpb.size     = Vector2(TEAM_BAR_W * inst.xp_ratio(), 3)
		xpb.color    = C_XP
		root.add_child(xpb)

		_team_cards.append({
			"root": root, "portrait": portrait, "fill": fill, "ghost": ghost,
			"lvl": lvl, "name": nm, "xp": xpb,
		})


func set_active_slot(idx: int) -> void:
	_active_slot_idx = idx
	for i in _team_cards.size():
		var root: Panel = _team_cards[i].get("root")
		if is_instance_valid(root):
			_panel_style(root, i == idx)


func update_team_hp(idx: int, ratio: float) -> void:
	if idx >= _team_cards.size():
		return
	var card: Dictionary = _team_cards[idx]
	var fill: TextureRect = card.get("fill")
	if not is_instance_valid(fill):
		return
	_update_hp_fill(fill, ratio)
	_ghost_targets[card["ghost"]] = fill.size.x
	# KO = carte grisée ; ranimé (rappel) = carte rendue à pleine opacité.
	# Avant, on ne grisait qu'à 0 sans jamais restaurer → le Pokémon soigné
	# restait affiché comme mort (retour joueurs).
	(card["root"] as Panel).modulate = Color(1, 1, 1, 0.45 if ratio <= 0.0 else 1.0)


func update_team_portrait(idx: int, texture: Texture2D) -> void:
	if idx < _team_cards.size() and is_instance_valid(_team_cards[idx].get("portrait")):
		_team_cards[idx]["portrait"].texture = texture
	if idx == _active_slot_idx and is_instance_valid(_portrait_tex):
		_portrait_tex.texture = texture


func update_team_level(idx: int, level: int) -> void:
	if idx < _team_cards.size() and is_instance_valid(_team_cards[idx].get("lvl")):
		_team_cards[idx]["lvl"].text = "N.%d" % level


func update_team_xp(idx: int, ratio: float) -> void:
	if idx < _team_cards.size() and is_instance_valid(_team_cards[idx].get("xp")):
		_team_cards[idx]["xp"].size.x = TEAM_BAR_W * clampf(ratio, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════════
# PANNEAU DU POKÉMON CONTRÔLÉ (bas-gauche) + CAPACITÉS + DASH
# ══════════════════════════════════════════════════════════════════════

func _build_player_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(8, 576)
	panel.size     = Vector2(324, 136)
	_panel_style(panel, true)
	add_child(panel)

	var pframe := ColorRect.new()
	pframe.position = Vector2(8, 8)
	pframe.size     = Vector2(76, 76)
	pframe.color    = Color(0, 0, 0, 0.45)
	panel.add_child(pframe)

	_portrait_tex = TextureRect.new()
	_portrait_tex.position = Vector2(8, 8)
	_portrait_tex.size     = Vector2(76, 76)
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(_portrait_tex)

	_name_label = _lbl("???", 96, 6, 160, 22, 16, C_TEXT)
	panel.add_child(_name_label)
	_level_label = _lbl("Niv. 1", 258, 8, 60, 20, 13, C_GOLD)
	panel.add_child(_level_label)

	_type_holder = Control.new()
	_type_holder.position = Vector2(96, 30)
	panel.add_child(_type_holder)

	# PV : gros, lisible — cadre Essentials + fantôme + remplissage 3 teintes
	var hp_bg := _make_hp_back(Vector2(HP_BAR_W + 4, 18))
	hp_bg.position = Vector2(96, 56)
	panel.add_child(hp_bg)
	_hp_ghost = ColorRect.new()
	_hp_ghost.position = Vector2(98, 58)
	_hp_ghost.size     = Vector2(HP_BAR_W, 14)
	_hp_ghost.color    = C_GHOST
	panel.add_child(_hp_ghost)
	_hp_fill = _make_hp_fill(HP_BAR_W / HP_OVERLAY_NATIVE_W, 14.0)
	_hp_fill.position = Vector2(98, 58)
	panel.add_child(_hp_fill)
	_hp_numbers = _lbl("-- / --", 96, 76, HP_BAR_W, 16, 11, C_DIM)
	_hp_numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_hp_numbers)

	# EXP fine tout en bas du panneau
	var xp_bg := ColorRect.new()
	xp_bg.position = Vector2(8, 118)
	xp_bg.size     = Vector2(308, 6)
	xp_bg.color    = Color(0, 0, 0, 0.55)
	panel.add_child(xp_bg)
	_xp_fill = ColorRect.new()
	_xp_fill.position = Vector2(9, 119)
	_xp_fill.size     = Vector2(0, 4)
	_xp_fill.color    = C_XP
	panel.add_child(_xp_fill)

	# Pips de dash (rechargés = or, vides = sombres)
	for i in 3:
		var pip := ColorRect.new()
		pip.position = Vector2(96 + i * 18, 96)
		pip.size     = Vector2(12, 12)
		pip.rotation_degrees = 45.0
		pip.pivot_offset = Vector2(6, 6)
		pip.color    = C_GOLD
		pip.visible  = false
		panel.add_child(pip)
		_dash_pips.append(pip)


func setup_player(instance: PokemonInstance) -> void:
	_player_instance = instance
	if is_instance_valid(instance.portrait_texture):
		_portrait_tex.texture = instance.portrait_texture
	_name_label.text  = instance.data.name_fr.capitalize()
	_level_label.text = "Niv. %d" % instance.level
	for c in _type_holder.get_children():
		c.queue_free()
	var t: String = instance.data.types[0] if not instance.data.types.is_empty() else "normal"
	_type_holder.add_child(TypeIcon.make_pill(t, 74.0, 20.0, 11))
	update_hp(instance.hp_ratio())
	update_xp(instance.xp_ratio(), instance.level)


func update_hp(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_hp_fill):
		_update_hp_fill(_hp_fill, ratio)
		_ghost_targets[_hp_ghost] = _hp_fill.size.x
	if is_instance_valid(_hp_numbers) and _player_instance != null:
		_hp_numbers.text = "%d / %d" % [_player_instance.current_hp, _player_instance.max_hp]
	# Vignette d'alerte quand le Pokémon contrôlé est bas
	var was := _low_hp
	_low_hp = ratio > 0.0 and ratio <= LOW_HP_THRESHOLD
	if is_instance_valid(_vignette):
		if _low_hp and not was:
			_vignette.visible = true
		elif not _low_hp:
			_vignette.visible = false


func update_xp(ratio: float, level: int) -> void:
	if is_instance_valid(_xp_fill):
		_xp_fill.size.x = 306.0 * clampf(ratio, 0.0, 1.0)
	if is_instance_valid(_level_label):
		_level_label.text = "Niv. %d" % level


func update_dash(charges: int, max_charges: int) -> void:
	for i in _dash_pips.size():
		var pip: ColorRect = _dash_pips[i]
		if not is_instance_valid(pip):
			continue
		pip.visible = i < max_charges
		pip.color   = C_GOLD if i < charges else Color(0.22, 0.18, 0.12)


# ── Capacités : 4 keycaps, cooldown en overlay sur la sélection ────────

func setup_moves(moves: Array) -> void:
	for slot in _move_slots:
		if is_instance_valid(slot.get("panel")):
			slot["panel"].queue_free()
	_move_slots.clear()

	const SLOT_W := 172
	const SLOT_H := 64
	const GAP    := 6
	const START_X := 344

	for i in 4:
		var move: MoveData = null
		if i < moves.size() and moves[i] != null:
			move = moves[i] as MoveData
		var t_col: Color = TypeIcon.color_for(move.type) if move else Color(0.3, 0.26, 0.2)

		var panel := Panel.new()
		panel.position = Vector2(START_X + i * (SLOT_W + GAP), 648)
		panel.size     = Vector2(SLOT_W, SLOT_H)
		var st := StyleBoxFlat.new()
		st.bg_color     = C_PANEL_2 if move else Color(0.09, 0.07, 0.05, 0.72)
		st.border_color = t_col if move else C_BORDER * Color(1, 1, 1, 0.4)
		st.set_border_width_all(2)
		st.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", st)
		add_child(panel)

		# Keycap "1-4"
		var key := _lbl(str(i + 1), 8, 6, 20, 20, 14, C_GOLD if move else C_DIM)
		panel.add_child(key)

		if move:
			var nm := _lbl(move.display_name, 30, 6, SLOT_W - 38, 20, 13, C_TEXT)
			nm.clip_text = true
			panel.add_child(nm)
			var info := _lbl("%s · %d" % [TypeIcon.label_fr(move.type), move.power],
				30, 32, SLOT_W - 38, 18, 11, t_col.lightened(0.25))
			panel.add_child(info)
		else:
			panel.add_child(_lbl("—", 30, 18, 40, 24, 14, C_DIM))

		# Overlay de cooldown : voile sombre qui se vide de bas en haut
		var cd := ColorRect.new()
		cd.position = Vector2(2, 2)
		cd.size     = Vector2(SLOT_W - 4, 0)
		cd.color    = Color(0, 0, 0, 0.55)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cd)

		# Croix "indisponible" — la cadence à elle seule ne dit pas TOUT
		# (verrou d'anim en cours, ex.) : retour joueurs « le cooldown n'est
		# pas toujours visible ». Cachée par défaut ; affichée par
		# update_cooldown() dès que la capacité SÉLECTIONNÉE ne peut pas
		# s'enchaîner MAINTENANT, quelle qu'en soit la raison.
		var cross := _lbl("✕", 0, 0, SLOT_W, SLOT_H, 26, Color(0.95, 0.30, 0.28), true)
		cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cross.visible = false
		panel.add_child(cross)

		_move_slots.append({"panel": panel, "cd": cd, "cross": cross, "has_move": move != null})

	set_active_move(_active_move_idx)


func set_active_move(idx: int) -> void:
	_active_move_idx = idx
	for i in _move_slots.size():
		var panel: Panel = _move_slots[i].get("panel")
		if not is_instance_valid(panel):
			continue
		var active: bool = i == idx and _move_slots[i]["has_move"]
		panel.modulate = Color(1, 1, 1, 1.0) if active else Color(0.82, 0.82, 0.82, 0.92)
		panel.position.y = 642.0 if active else 648.0


## `ready` = la capacité SÉLECTIONNÉE peut-elle s'enchaîner MAINTENANT
## (TeamMember.active_move_ready — cadence ET verrous d'anim/statut) ? Séparé
## du ratio de cadence : un plein voile de cooldown peut être discret
## (attaques rapides), d'où la croix qui rend l'indisponibilité toujours
## lisible, quelle qu'en soit la cause.
func update_cooldown(ratio: float, ready: bool = true) -> void:
	if _active_move_idx >= _move_slots.size():
		return
	var slot: Dictionary = _move_slots[_active_move_idx]
	var cd: ColorRect = slot.get("cd")
	if is_instance_valid(cd):
		var h := (1.0 - clampf(ratio, 0.0, 1.0)) * 60.0
		cd.size.y = h
		cd.position.y = 2 + (60.0 - h)
	var cross: Label = slot.get("cross")
	if is_instance_valid(cross):
		cross.visible = not ready


# ══════════════════════════════════════════════════════════════════════
# PROMPT D'INTERACTION (bas-centre, au-dessus des keycaps)
# ══════════════════════════════════════════════════════════════════════

func _build_prompt() -> void:
	_prompt_panel = Panel.new()
	_prompt_panel.position = Vector2(440, 590)
	_prompt_panel.size     = Vector2(400, 40)
	_prompt_panel.visible  = false
	var st := StyleBoxFlat.new()
	st.bg_color = C_PANEL_2
	st.border_color = C_GOLD
	st.set_border_width_all(2)
	st.set_corner_radius_all(20)
	_prompt_panel.add_theme_stylebox_override("panel", st)
	add_child(_prompt_panel)
	_prompt_label = _lbl("", 0, 8, 400, 24, 14, C_GOLD, true)
	_prompt_panel.add_child(_prompt_label)


func set_interact_prompt(show_it: bool, text: String = "") -> void:
	if not is_instance_valid(_prompt_panel):
		return
	if show_it and not _prompt_panel.visible:
		_prompt_panel.visible = true
		_prompt_panel.pivot_offset = Vector2(200, 20)
		_prompt_panel.scale = Vector2(0.85, 0.85)
		var tw := create_tween()
		tw.tween_property(_prompt_panel, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_OUT)
	elif not show_it:
		_prompt_panel.visible = false
	if show_it:
		_prompt_label.text = text


# ══════════════════════════════════════════════════════════════════════
# TOASTS (haut-droite) — level up / évolution / recrutement
# ══════════════════════════════════════════════════════════════════════

func show_levelup(level: int) -> void:
	_toast("▲  Niveau %d !" % level, C_GOLD)


func show_evolution(name_fr: String) -> void:
	_toast("✦  Évolution : %s !" % name_fr.capitalize(), Color(0.72, 0.55, 0.95))


func show_unlock(name_fr: String) -> void:
	_toast("★  %s rejoint la rébellion !" % name_fr.capitalize(), Color(0.35, 0.80, 0.90))


func _toast(text: String, accent: Color) -> void:
	var panel := Panel.new()
	panel.size = Vector2(300, 40)
	var st := StyleBoxFlat.new()
	st.bg_color = C_PANEL_2
	st.border_color = accent
	st.border_width_left = 4
	st.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)

	var l := _lbl(text, 12, 8, 280, 24, 14, C_TEXT)
	panel.add_child(l)

	_toast_stack.append(panel)
	_restack_toasts()

	panel.modulate.a = 0.0
	panel.position.x = 1300   # entre en glissant depuis la droite
	var slot := _toast_stack.size() - 1
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "position:x", 972.0, 0.22).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.4)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void:
		_toast_stack.erase(panel)
		panel.queue_free()
		_restack_toasts()
	)


func _restack_toasts() -> void:
	for i in _toast_stack.size():
		var p: Panel = _toast_stack[i]
		if is_instance_valid(p):
			p.position.y = 52.0 + i * 48.0


# ══════════════════════════════════════════════════════════════════════
# VIGNETTE BASSE-VIE
# ══════════════════════════════════════════════════════════════════════

static var _vignette_tex: GradientTexture2D = null

func _build_vignette() -> void:
	if _vignette_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.85, 0.05, 0.05, 0.0))
		grad.set_color(1, Color(0.85, 0.05, 0.05, 0.55))
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient  = grad
		_vignette_tex.fill      = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to   = Vector2(0.5, 0.0)
		_vignette_tex.width     = 256
		_vignette_tex.height    = 144
	_vignette = TextureRect.new()
	_vignette.texture = _vignette_tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)


# ══════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════

func _hp_color(ratio: float) -> Color:
	if ratio > 0.5: return C_HP_HIGH
	if ratio > 0.25: return C_HP_MED
	return C_HP_LOW


## Crée le TextureRect de fond (cadre vide, sans remplissage) d'une barre de
## PV — taille cible en pixels écran.
func _make_hp_back(target_size: Vector2) -> TextureRect:
	if _hp_back_tex == null:
		_hp_back_tex = load(HP_BACK_PATH)
	var tr := TextureRect.new()
	tr.texture         = _hp_back_tex
	tr.expand_mode     = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode    = TextureRect.STRETCH_SCALE
	tr.texture_filter  = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size            = target_size
	return tr


## Crée le TextureRect de remplissage — sa largeur ET la région croquée
## dans l'atlas rétrécissent ENSEMBLE avec `ratio` (troncature, pas
## d'écrasement de l'image) ; la bande verte/jaune/rouge est choisie
## automatiquement. `native_to_screen` = échelle appliquée à la largeur
## native de 96px pour obtenir la largeur affichée à plein PV ;
## `target_height` = hauteur fixe affichée (la bande source fait 8px de haut).
func _make_hp_fill(native_to_screen: float, target_height: float = 8.0) -> TextureRect:
	if _hp_overlay_tex == null:
		_hp_overlay_tex = load(HP_OVERLAY_PATH)
	var tr := TextureRect.new()
	tr.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode   = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.set_meta("native_to_screen", native_to_screen)
	tr.size.y = target_height
	_update_hp_fill(tr, 1.0)
	return tr


## Recroque + redimensionne un TextureRect créé par _make_hp_fill() pour
## refléter `ratio` (0..1).
func _update_hp_fill(tr: TextureRect, ratio: float) -> void:
	if not is_instance_valid(tr):
		return
	ratio = clampf(ratio, 0.0, 1.0)
	var row := 0
	if ratio <= 0.25: row = 2
	elif ratio <= 0.5: row = 1
	var at := AtlasTexture.new()
	at.atlas  = _hp_overlay_tex
	at.region = Rect2(0, row * HP_OVERLAY_ROW_H,
		maxf(1.0, HP_OVERLAY_NATIVE_W * ratio), HP_OVERLAY_ROW_H)
	tr.texture = at
	var scale: float = tr.get_meta("native_to_screen", 1.0)
	tr.size.x = HP_OVERLAY_NATIVE_W * ratio * scale


func _panel_style(p: Panel, active: bool) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color     = C_PANEL
	st.border_color = C_GOLD if active else C_BORDER
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size  = 4
	p.add_theme_stylebox_override("panel", st)


func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, col: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# ── Annonce de zone : le nom s'affiche en GRAND au centre, fondu + glow ──
var _zone_announce: Control = null

func announce_zone(zone_name: String) -> void:
	if is_instance_valid(_zone_announce):
		_zone_announce.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_zone_announce = root

	# Deux labels superposés : un flou doré derrière (le "glow", même texte
	# grossi et translucide) + le titre net par-dessus.
	for cfg: Dictionary in [
		{"fs": 58, "col": Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35), "outline": 0},
		{"fs": 52, "col": C_TEXT, "outline": 10},
	]:
		var l := Label.new()
		l.text = zone_name
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.offset_top = -140.0   # légèrement au-dessus du centre
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", UiKit.scaled_font(cfg["fs"]))
		l.add_theme_color_override("font_color", cfg["col"])
		if int(cfg["outline"]) > 0:
			l.add_theme_constant_override("outline_size", int(cfg["outline"]))
			l.add_theme_color_override("font_outline_color", Color(0.14, 0.09, 0.05, 0.9))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)

	root.modulate.a = 0.0
	root.scale = Vector2.ONE * 1.06
	root.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.6)
	tw.chain().tween_property(root, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)


# ── QTE de capture (dresseurs de village) — barre centrale ────────────
# Affichée quand le membre ACTIF est capturé : marteler ← → pour remplir la
# barre d'évasion avant que les PV ne tombent. Masquée sinon.
var _capture_qte: Control = null
var _capture_fill: ColorRect = null

func capture_qte(capturing: bool, escape: float, active: bool) -> void:
	# On n'affiche le QTE que pour NOTRE Pokémon actif (les alliés piégés se
	# libèrent en passant dessus — pas de QTE à distance).
	if not capturing or not active:
		if is_instance_valid(_capture_qte):
			_capture_qte.queue_free()
			_capture_qte = null
			_capture_fill = null
		return
	if not is_instance_valid(_capture_qte):
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		_capture_qte = root

		var panel := Panel.new()
		panel.size = Vector2(420, 92)
		panel.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 210, 96)
		panel.add_theme_stylebox_override("panel", UiKit.style(C_PANEL_2, C_BORDER, 12, 3))
		root.add_child(panel)

		var lbl := Label.new()
		lbl.text = "Capturé !  Martèle  ◄  ►  pour t'échapper !"
		lbl.position = Vector2(0, 12)
		lbl.size = Vector2(420, 28)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", UiKit.scaled_font(15))
		lbl.add_theme_color_override("font_color", C_GOLD)
		panel.add_child(lbl)

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.10, 0.07, 0.05)
		bar_bg.position = Vector2(24, 52)
		bar_bg.size = Vector2(372, 24)
		panel.add_child(bar_bg)

		_capture_fill = ColorRect.new()
		_capture_fill.color = C_HP_HIGH
		_capture_fill.position = Vector2(26, 54)
		_capture_fill.size = Vector2(0, 20)
		panel.add_child(_capture_fill)
	if is_instance_valid(_capture_fill):
		_capture_fill.size.x = 368.0 * clampf(escape, 0.0, 1.0)


# ── Notifications BAS-DROITE (évolution, K.O., capture…) — style UiKit ──
# Pile séparée des toasts haut-droite (level up/unlock) : elle porte les
# événements d'ÉQUIPE et monte depuis le coin bas-droit, au-dessus de rien
# (panneau Pokémon en bas-gauche, keycaps au centre — le coin est libre).
var _notif_stack: Array = []

func notify(text: String, accent: Color = C_GOLD) -> void:
	var vp := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.size = Vector2(330, 44)
	panel.add_theme_stylebox_override("panel",
		UiKit.style(Color(0.89, 0.76, 0.53, 0.96), accent, 8, 3))   # parchemin UiKit.TAN
	add_child(panel)

	var l := _lbl(text, 12, 10, 306, 24, 14, Color(0.28, 0.17, 0.08))   # UiKit.TEXT_DARK
	panel.add_child(l)

	_notif_stack.append(panel)
	_restack_notifs()

	panel.modulate.a = 0.0
	panel.position.x = vp.x + 20.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "position:x", vp.x - 344.0, 0.24).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.0)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(func() -> void:
		_notif_stack.erase(panel)
		panel.queue_free()
		_restack_notifs()
	)


func _restack_notifs() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in _notif_stack.size():
		var p: Panel = _notif_stack[i]
		if is_instance_valid(p):
			# i=0 le plus bas ; les suivantes s'empilent au-dessus
			p.position.y = vp.y - 64.0 - (_notif_stack.size() - 1 - i) * 52.0
