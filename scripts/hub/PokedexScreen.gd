class_name PokedexScreen
extends CanvasLayer

signal closed

const C_BG      := Color(0.04, 0.03, 0.02, 0.82)
const C_PANEL   := Color(0.10, 0.075, 0.045, 0.96)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.96, 0.92, 0.80)
const C_DIM     := Color(0.62, 0.55, 0.42)
const C_GOLD    := Color(0.92, 0.72, 0.25)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)
const C_CARD    := Color(0.16, 0.12, 0.07, 0.95)
const C_CARD_SEL:= Color(0.26, 0.21, 0.12)
const C_GOOD    := Color(0.38, 0.82, 0.45)
const C_BAR_BG  := Color(0, 0, 0, 0.55)

const STAT_NAMES: Array[String] = ["PV", "Attaque", "Défense", "Atq. Sp.", "Déf. Sp.", "Vitesse"]
const STAT_COLORS: Array[Color] = [
	Color(0.80, 0.24, 0.18), Color(0.85, 0.52, 0.14), Color(0.78, 0.62, 0.18),
	Color(0.58, 0.34, 0.78), Color(0.24, 0.54, 0.84), Color(0.20, 0.70, 0.74),
]

var _sorted_ids:   Array  = []
var _selected_pid: int    = -1
var _loaded_data:  Dictionary = {}   # pid -> PokemonData
var _portraits:    Dictionary = {}   # pid -> Texture2D
var _card_panels:  Dictionary = {}   # pid -> Panel
var _card_tex:     Dictionary = {}   # pid -> TextureRect
var _card_ph:      Dictionary = {}   # pid -> ColorRect

var _detail_root:     Control = null
var _team_strip_root: Control = null


func _ready() -> void:
	# Union des Pokémon débloqués ET de ceux simplement "aperçus" en combat
	# (compteur de victoires en cours, pas encore au seuil de déblocage).
	var id_set: Dictionary = {}
	for pid in GameManager.unlocked_pokemon:
		id_set[pid] = true
	for pid in GameManager.defeat_counts:
		id_set[pid] = true
	_sorted_ids = id_set.keys()
	_sorted_ids.sort()
	if not _sorted_ids.is_empty():
		_selected_pid = _sorted_ids[0]
	_build()
	_fetch_all()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(100, 50)
	panel.size     = Vector2(1080, 620)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	# Header
	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1080, 72)
	_style_col(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	_lbl(panel, "⊕  POKÉDEX", 24, 14, 700, 44, 24, C_GOLD_LT)
	var count_str := "%d débloqués  •  %d aperçus" % [GameManager.unlocked_pokemon.size(), _sorted_ids.size()]
	_lbl(panel, count_str, 700, 22, 360, 28, 16, C_DIM, true)

	if _sorted_ids.is_empty():
		_lbl(panel,
			"Aucun Pokémon libéré pour l'instant.\n\nTermine une run pour en recruter !",
			0, 280, 1080, 80, 18, C_DIM, true)
	else:
		_build_team_strip(panel)
		_build_grid(panel)
		_build_detail_panel(panel)

	var prg_str := "%d Pokémon libérés  •  Équipe %d / 6 slots  •  Capacités %d / 4 slots" % [
		GameManager.unlocked_pokemon.size(),
		GameManager.team_slot_count,
		GameManager.move_slot_count,
	]
	_lbl(panel, prg_str, 0, 590, 1080, 20, 12, C_DIM, true)

	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(24, 580)
	close.size     = Vector2(160, 36)
	close.add_theme_font_size_override("font_size", 14)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


# ── Équipe actuelle (bande au-dessus de la grille) ──────────────────────

func _build_team_strip(panel: Panel) -> void:
	_lbl(panel, "ÉQUIPE ACTUELLE", 16, 84, 300, 18, 11, C_DIM)
	_team_strip_root = Control.new()
	_team_strip_root.position = Vector2(16, 102)
	_team_strip_root.size     = Vector2(456, 40)
	panel.add_child(_team_strip_root)
	_refresh_team_strip()


func _refresh_team_strip() -> void:
	if not is_instance_valid(_team_strip_root): return
	for c in _team_strip_root.get_children():
		c.queue_free()

	var max_n := GameManager.get_max_team_size()
	var sw  := 40.0
	var gap := 6.0
	for i in max_n:
		var slot := Panel.new()
		slot.position = Vector2(i * (sw + gap), 0)
		slot.size     = Vector2(sw, sw)

		if i < GameManager.hub_team.size():
			var pid: int = GameManager.hub_team[i]
			_style(slot, Color(0.13, 0.24, 0.13), C_GOOD, 6)
			if _portraits.has(pid):
				var tr := TextureRect.new()
				tr.position = Vector2(2, 2)
				tr.size     = Vector2(sw - 4, sw - 4)
				tr.texture  = _portraits[pid]
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.add_child(tr)
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			var capture_pid := pid
			slot.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton:
					var mbe := event as InputEventMouseButton
					if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
						_select(capture_pid)
						get_viewport().set_input_as_handled()
			)
		else:
			_style(slot, Color(0.16, 0.12, 0.07), C_BORDER, 6)

		_team_strip_root.add_child(slot)


# ── Grille (gauche, triée par n° de Pokédex) ───────────────────────────

func _build_grid(panel: Panel) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 144)
	scroll.size     = Vector2(456, 426)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	const CARD_W := 218
	const CARD_H := 76
	const GAP    := 8
	var cols := 2
	var rows := ceili(float(_sorted_ids.size()) / cols)

	var content := Control.new()
	content.custom_minimum_size = Vector2(456, rows * (CARD_H + GAP))
	scroll.add_child(content)

	for i in _sorted_ids.size():
		var pid: int = _sorted_ids[i]
		var col := i % cols
		var row := i / cols
		_build_entry(content, pid, col * (CARD_W + GAP), row * (CARD_H + GAP), CARD_W, CARD_H)


func _build_entry(parent: Control, pid: int, x: int, y: int, w: int, h: int) -> void:
	var unlocked := pid in GameManager.unlocked_pokemon

	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size     = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_style(card, pid == _selected_pid)
	_card_panels[pid] = card
	parent.add_child(card)

	var ph := ColorRect.new()
	ph.name     = "PH"
	ph.position = Vector2(6, 6)
	ph.size     = Vector2(56, 56)
	ph.color    = Color(0.20, 0.17, 0.12)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_ph[pid] = ph
	card.add_child(ph)

	var tex_r := TextureRect.new()
	tex_r.position     = Vector2(6, 6)
	tex_r.size         = Vector2(56, 56)
	tex_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_r.modulate     = Color.BLACK if not unlocked else Color.WHITE
	_card_tex[pid] = tex_r
	if _portraits.has(pid):
		tex_r.texture = _portraits[pid]
		ph.visible = false
	card.add_child(tex_r)

	if pid in GameManager.hub_team:
		var badge := _PokeballBadge.new()
		badge.size     = Vector2(20, 20)
		badge.position = Vector2(w - 24, 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)

	_lbl(card, "#%d" % pid, 68, 4, w - 74, 18, 11, C_GOLD)
	var name_lbl := _lbl(card, "…", 68, 20, w - 74, 22, 14, C_TEXT)
	name_lbl.name = "NameLbl"
	if _loaded_data.has(pid):
		name_lbl.text = (_loaded_data[pid] as PokemonData).name_fr.to_upper()

	if unlocked:
		var type_row := Control.new()
		type_row.name = "TypeRow"
		type_row.position = Vector2(68, 44)
		card.add_child(type_row)
		if _loaded_data.has(pid):
			_fill_type_row(type_row, (_loaded_data[pid] as PokemonData).types)
	else:
		var prog := _lbl(card, "%d / %d victoires" % [GameManager.get_defeat_count(pid), GameManager.UNLOCK_DEFEAT_THRESHOLD],
			68, 46, w - 74, 16, 10, C_DIM)
		prog.name = "ProgLbl"

	var capture_pid := pid
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mbe := event as InputEventMouseButton
			if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
				_select(capture_pid)
				get_viewport().set_input_as_handled()
	)


# ── Badge Pokéball (membre actuel de l'équipe) ──────────────────────────

class _PokeballBadge extends Control:
	func _draw() -> void:
		var s := size.x
		var c := Vector2(s, s) * 0.5
		var r := s * 0.5 - 1.0
		draw_colored_polygon(_half(c, r, true),  Color(0.85, 0.16, 0.12))
		draw_colored_polygon(_half(c, r, false), Color(0.97, 0.97, 0.95))
		draw_arc(c, r, 0, TAU, 28, Color(0.10, 0.08, 0.06), 1.6, true)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.10, 0.08, 0.06), 1.6)
		draw_circle(c, r * 0.32, Color(0.97, 0.97, 0.95))
		draw_arc(c, r * 0.32, 0, TAU, 16, Color(0.10, 0.08, 0.06), 1.3, true)

	func _half(c: Vector2, r: float, top: bool) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var a0 := -PI if top else 0.0
		var a1 := 0.0 if top else PI
		for i in 17:
			var t := a0 + (a1 - a0) * float(i) / 16.0
			pts.append(c + Vector2(cos(t), sin(t)) * r)
		return pts


func _fill_type_row(row: Control, types: Array) -> void:
	for c in row.get_children():
		c.queue_free()
	var tx := 0.0
	var pw := 54.0
	for t in types:
		var pill := TypeIcon.make_pill(str(t), pw, 17.0, 9)
		pill.position = Vector2(tx, 0)
		row.add_child(pill)
		tx += pw + 4.0


func _select(pid: int) -> void:
	if pid == _selected_pid: return
	_selected_pid = pid
	for id in _sorted_ids:
		if _card_panels.has(id):
			_apply_card_style(_card_panels[id] as Panel, id == pid)
	_refresh_detail()


func _apply_card_style(card: Panel, selected: bool) -> void:
	_style(card, C_CARD_SEL if selected else C_CARD, C_GOLD if selected else C_BORDER, 8)


# ── Panneau détail (droite) ─────────────────────────────────────────────

func _build_detail_panel(panel: Panel) -> void:
	var frame := Panel.new()
	frame.position = Vector2(488, 82)
	frame.size     = Vector2(576, 488)
	_style(frame, Color(0.16, 0.12, 0.07, 0.95), C_BORDER, 8)
	panel.add_child(frame)

	_detail_root = Control.new()
	_detail_root.position = Vector2(488, 82)
	_detail_root.size     = Vector2(576, 488)
	panel.add_child(_detail_root)

	_refresh_detail()


func _refresh_detail_locked(pd: PokemonData) -> void:
	_detail_root.add_child(_lbl_node("#%d  %s" % [_selected_pid, pd.name_fr.to_upper()],
		122, 14, 430, 30, 20, C_DIM))

	if not pd.is_base_form:
		_detail_root.add_child(_lbl_node(
			"Forme évoluée — non recrutable directement.\nLes évolutions se font en jouant une run, pas au recrutement.",
			16, 124, 544, 50, 13, C_DIM))
		return

	_detail_root.add_child(_lbl_node("Pas encore recruté", 122, 48, 430, 20, 13, C_DIM))

	var count: int     = GameManager.get_defeat_count(_selected_pid)
	var threshold: int  = GameManager.UNLOCK_DEFEAT_THRESHOLD
	var remaining: int  = maxi(0, threshold - count)

	_detail_root.add_child(_lbl_node(
		"%d / %d victoires" % [count, threshold], 16, 124, 250, 22, 16, C_TEXT))

	var bar := ProgressBar.new()
	bar.position = Vector2(16, 150)
	bar.size     = Vector2(544, 18)
	bar.max_value = threshold
	bar.value     = count
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = C_GOLD; fill.set_corner_radius_all(5)
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = C_BAR_BG; bbg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bbg)
	_detail_root.add_child(bar)

	var msg := "Encore %d victoire%s pour le recruter !" % [remaining, "s" if remaining > 1 else ""]
	_detail_root.add_child(_lbl_node(msg, 16, 178, 544, 24, 13, C_DIM))


## Ligne "objet tenu" : icône + nom de l'objet assigné à `pid`, bouton pour
## cycler parmi les objets possédés (dont « Aucun »), et bouton Super Bonbon.
func _build_item_row(pid: int, x: int, y: int) -> void:
	var held := GameManager.get_assigned_item(pid)

	# Icône (si un objet est tenu)
	if held != "":
		var tex := ItemCatalog.icon(held)
		if tex != null:
			var icon := TextureRect.new()
			icon.texture        = tex
			icon.position       = Vector2(x, y)
			icon.size           = Vector2(30, 30)
			icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_detail_root.add_child(icon)

	var item_name := "Aucun objet"
	if held != "":
		item_name = str(ItemCatalog.get_item(held).get("name", held))
	_detail_root.add_child(_lbl_node("Objet : " + item_name, x + 34, y + 4, 240, 22, 13, C_TEXT))

	# Bouton cycle d'objet
	var cap_pid := pid
	var cyc := Button.new()
	cyc.text     = "Changer"
	cyc.position = Vector2(x + 250, y)
	cyc.size     = Vector2(90, 30)
	cyc.add_theme_font_size_override("font_size", 12)
	_style_button(cyc, Color(0.34, 0.28, 0.16), C_GOLD_LT)
	cyc.pressed.connect(func() -> void:
		_cycle_item(cap_pid)
		_refresh_detail()
	)
	_detail_root.add_child(cyc)

	# Super Bonbon
	var candies := GameManager.get_item_count("rare-candy")
	var bonus := GameManager.get_start_level_bonus(pid)
	var candy_txt := "Bonbon (+%d) ×%d" % [ItemCatalog.CANDY_LEVELS, candies]
	if bonus > 0:
		candy_txt = "Niv.+%d  |  " % bonus + candy_txt
	var candy := Button.new()
	candy.text     = candy_txt
	candy.position = Vector2(x + 344, y)
	candy.size     = Vector2(184, 30)
	candy.disabled = candies <= 0 or bonus >= ItemCatalog.CANDY_MAX_BONUS
	candy.add_theme_font_size_override("font_size", 11)
	_style_button(candy, Color(0.60, 0.28, 0.42) if not candy.disabled else Color(0.55, 0.48, 0.38), Color.WHITE)
	candy.pressed.connect(func() -> void:
		if GameManager.use_candy(cap_pid):
			Sfx.play("levelup", -4.0)
			_refresh_detail()
	)
	_detail_root.add_child(candy)


## Passe à l'objet tenu suivant pour `pid` : parcourt [Aucun] + les objets
## tenus dont il reste des copies libres (ou celui déjà tenu).
func _cycle_item(pid: int) -> void:
	var held := GameManager.get_assigned_item(pid)
	var options: Array = [""]   # "Aucun"
	for it: Dictionary in ItemCatalog.held_items():
		var api: String = it["api"]
		if api == held or GameManager.get_item_count(api) > 0:
			options.append(api)
	var idx := options.find(held)
	var next: String = options[(idx + 1) % options.size()]
	if next == "":
		GameManager.unassign_item(pid)
	else:
		GameManager.assign_item(pid, next)


func _refresh_detail() -> void:
	if not is_instance_valid(_detail_root): return
	for ch in _detail_root.get_children():
		ch.queue_free()

	if _selected_pid < 0:
		return

	if not _loaded_data.has(_selected_pid):
		_detail_root.add_child(_lbl_node("Chargement…", 0, 220, 576, 30, 16, C_DIM, true))
		return

	var pd: PokemonData = _loaded_data[_selected_pid]
	var unlocked := _selected_pid in GameManager.unlocked_pokemon

	# Portrait (silhouette noire si non débloqué)
	var p_bg := ColorRect.new()
	p_bg.position = Vector2(16, 12)
	p_bg.size     = Vector2(96, 96)
	p_bg.color    = Color(0.20, 0.17, 0.12)
	_detail_root.add_child(p_bg)

	var tex := TextureRect.new()
	tex.position     = Vector2(16, 12)
	tex.size         = Vector2(96, 96)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.modulate     = Color.BLACK if not unlocked else Color.WHITE
	if _portraits.has(_selected_pid):
		tex.texture = _portraits[_selected_pid]
	_detail_root.add_child(tex)

	if not unlocked:
		_refresh_detail_locked(pd)
		return

	# Nom + types
	_detail_root.add_child(_lbl_node("#%d  %s" % [_selected_pid, pd.name_fr.to_upper()],
		122, 14, 300, 30, 20, C_GOLD))

	var type_row := Control.new()
	type_row.position = Vector2(122, 48)
	_detail_root.add_child(type_row)
	_fill_type_row(type_row, pd.types)

	# Ajout / retrait de l'équipe
	var in_team := _selected_pid in GameManager.hub_team
	var team_btn := Button.new()
	team_btn.position = Vector2(424, 14)
	team_btn.size     = Vector2(136, 36)
	if in_team:
		team_btn.text = "✕ Retirer"
		_style_button(team_btn, Color(0.78, 0.30, 0.24), Color.WHITE)
	else:
		var can_add := GameManager.hub_team.size() < GameManager.get_max_team_size()
		team_btn.text     = "+ Ajouter"
		team_btn.disabled = not can_add
		_style_button(team_btn, C_GOOD if can_add else Color(0.62, 0.56, 0.46), Color.WHITE)
	var capture_pid := _selected_pid
	team_btn.pressed.connect(func() -> void:
		if capture_pid in GameManager.hub_team:
			GameManager.hub_team.erase(capture_pid)
		elif GameManager.hub_team.size() < GameManager.get_max_team_size():
			GameManager.hub_team.append(capture_pid)
		_refresh_detail()
		_refresh_team_strip()
	)
	_detail_root.add_child(team_btn)

	# Objet tenu (assignable uniquement ici, cf. cahier des charges) + Super Bonbon
	_build_item_row(_selected_pid, 122, 82)

	# Stats
	var sy0 := 122
	for i in 6:
		var sy := sy0 + i * 24
		_detail_root.add_child(_lbl_node(STAT_NAMES[i], 16, sy, 76, 18, 12, C_TEXT))
		_detail_root.add_child(_lbl_node(str([pd.hp, pd.attack, pd.defense,
			pd.sp_attack, pd.sp_defense, pd.speed][i]), 92, sy, 34, 18, 12, C_TEXT, false, true))

		var bar := ProgressBar.new()
		bar.position = Vector2(132, sy + 2)
		bar.size     = Vector2(420, 13)
		bar.max_value = 190
		bar.value     = [pd.hp, pd.attack, pd.defense, pd.sp_attack, pd.sp_defense, pd.speed][i]
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = STAT_COLORS[i]; fill.set_corner_radius_all(4)
		var bbg := StyleBoxFlat.new()
		bbg.bg_color = C_BAR_BG; bbg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bbg)
		_detail_root.add_child(bar)

	# Séparateur
	var sep := ColorRect.new()
	sep.position = Vector2(16, 272)
	sep.size     = Vector2(544, 2)
	sep.color    = C_BORDER
	_detail_root.add_child(sep)

	# Movepool — capacités achetées, assignables à CE Pokémon
	var loadout := GameManager.get_move_loadout(_selected_pid)
	_detail_root.add_child(_lbl_node(
		"── MOVEPOOL — %d / %d équipées (clic pour équiper/retirer) ──" % [loadout.size(), GameManager.move_slot_count],
		16, 280, 544, 20, 13, C_DIM))

	var purchasable: Array = []
	for m: Dictionary in MoveShopScreen.MOVE_LIST:
		if str(m.get("api", "")) in GameManager.purchased_move_names:
			purchasable.append(m)

	if purchasable.is_empty():
		_detail_root.add_child(_lbl_node(
			"Aucune capacité achetée — direction le Tuteur de capacités !",
			16, 320, 544, 24, 13, C_DIM, true))
		return

	var mx := 16
	var my := 304
	var col_w := 178
	for m: Dictionary in purchasable:
		var api: String   = str(m.get("api", ""))
		var label: String = str(m.get("label", api))
		var mtype: String  = str(m.get("type", "normal"))
		var equipped := api in loadout
		# Hors movepool : capacité achetée mais que CE Pokémon ne peut pas
		# apprendre (ex : Séisme sur Absol) → carte grisée, non cliquable.
		var learnable := pd.can_learn(api)

		var card := Panel.new()
		card.position = Vector2(mx, my)
		card.size     = Vector2(col_w - 6, 56)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var border := C_GOOD if equipped else C_BORDER
		if not learnable:
			border = Color(0.55, 0.30, 0.28)
		_style(card, C_CARD_SEL if equipped else C_CARD, border, 6)
		card.modulate = Color(1, 1, 1, 0.45) if not learnable else Color.WHITE
		_detail_root.add_child(card)

		var tpill := TypeIcon.make_pill(mtype, 70.0, 16.0, 8)
		tpill.position = Vector2(4, 4)
		card.add_child(tpill)

		card.add_child(_lbl_node(label, 4, 24, col_w - 14, 18, 11, C_TEXT))
		if not learnable:
			card.add_child(_lbl_node("✗ Hors movepool", 4, 40, col_w - 14, 14, 10, Color(0.80, 0.40, 0.36)))
		elif equipped:
			card.add_child(_lbl_node("✓ Équipée", 4, 40, col_w - 14, 14, 10, C_GOOD))
		elif loadout.size() >= GameManager.move_slot_count:
			card.add_child(_lbl_node("Slots pleins", 4, 40, col_w - 14, 14, 10, C_DIM))
		else:
			card.add_child(_lbl_node("Clic pour équiper", 4, 40, col_w - 14, 14, 10, C_DIM))

		if learnable:
			var move_pid := _selected_pid
			var capture_api := api
			card.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton:
					var mbe := event as InputEventMouseButton
					if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
						GameManager.toggle_move_in_loadout(move_pid, capture_api)
						_refresh_detail()
						get_viewport().set_input_as_handled()
			)

		mx += col_w
		if mx + col_w > 560:
			mx = 16
			my += 60


# ── Chargement API ────────────────────────────────────────────────────

func _fetch_all() -> void:
	for pid in _sorted_ids:
		PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
			if data.is_empty(): return
			var pd := PokemonData.from_api(data)
			_loaded_data[pid] = pd
			if _card_panels.has(pid):
				var card: Panel = _card_panels[pid]
				var nm := card.get_node_or_null("NameLbl")
				if nm: (nm as Label).text = pd.name_fr.to_upper()
				var tr := card.get_node_or_null("TypeRow")
				if tr: _fill_type_row(tr as Control, pd.types)
				var prog := card.get_node_or_null("ProgLbl")
				if prog and not pd.is_base_form:
					(prog as Label).text = "Forme évoluée — non recrutable"
			if pid == _selected_pid:
				_refresh_detail()
			if not pd.sprite_url.is_empty():
				_fetch_portrait(pid, pd.sprite_url)
		)


func _fetch_portrait(pid: int, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res: int, code: int, _h, body: PackedByteArray) -> void:
		http.queue_free()
		if res != HTTPRequest.RESULT_SUCCESS or code != 200: return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK: return
		var new_tex: Texture2D = ImageTexture.create_from_image(img)
		_portraits[pid] = new_tex
		if _card_tex.has(pid):
			var ct: TextureRect = _card_tex[pid]
			ct.texture = new_tex
			if _card_ph.has(pid):
				(_card_ph[pid] as ColorRect).visible = false
		_refresh_team_strip()
		if pid == _selected_pid:
			_refresh_detail()
	)
	http.request(url)


# ── Helpers ───────────────────────────────────────────────────────────


func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sh)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = Color(bg.r, bg.g, bg.b, 0.55)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.6))
	btn.add_theme_font_size_override("font_size", 13)

func _lbl(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := _lbl_node(text, x, y, w, h, fs, color, centered)
	parent.add_child(l)
	return l


func _lbl_node(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	s.bg_color = Color(0.22, 0.18, 0.11); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.25, 0.15)
	btn.add_theme_stylebox_override("hover", sh)
