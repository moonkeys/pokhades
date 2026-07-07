class_name UpgradeShopScreen
extends CanvasLayer

signal closed

const C_BG     := Color(0.04, 0.03, 0.02, 0.82)
const C_PANEL  := Color(0.10, 0.075, 0.045, 0.96)
const C_BORDER := Color(0.62, 0.50, 0.32)
const C_TEXT   := Color(0.96, 0.92, 0.80)
const C_DIM    := Color(0.62, 0.55, 0.42)
const C_GOLD   := Color(0.92, 0.72, 0.25)
const C_GOLD_LT:= Color(0.94, 0.88, 0.72)
const C_GOOD   := Color(0.38, 0.82, 0.45)


func _ready() -> void:
	layer = 10
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(140, 60)
	panel.size     = Vector2(1000, 600)
	_style(panel, C_PANEL, C_BORDER, 14)
	add_child(panel)

	var hdr := Panel.new()
	hdr.position = Vector2(0, 0)
	hdr.size     = Vector2(1000, 72)
	_style_col(hdr, Color(0.24, 0.18, 0.08), 14, true)
	panel.add_child(hdr)

	_lbl(panel, "⊕  AMÉLIORATIONS PERMANENTES", 24, 14, 700, 44, 22, C_GOLD_LT)
	_lbl(panel, "◆ %d Baies" % GameManager.gold, 760, 22, 200, 28, 16, C_GOLD)

	# ── Section capacités ─────────────────────────────────────────────
	_lbl(panel, "Emplacements de capacités", 40, 95, 460, 26, 17, C_TEXT)
	_lbl(panel, "Chaque Pokémon équipe plus de capacités en combat", 40, 119, 460, 20, 12, C_DIM)

	var slot_names := ["1 slot\n(départ)", "2 slots", "3 slots", "4 slots\n(max)"]
	for i in 4:
		var owned   := i < GameManager.move_slot_count
		var current := i == GameManager.move_slot_count - 1
		var buyable := i == GameManager.move_slot_count and i < 4
		var cost    := GameManager.MOVE_SLOT_COSTS[i - 1] if i > 0 else 0

		var card := Panel.new()
		card.position = Vector2(40 + i * 116, 148)
		card.size     = Vector2(104, 88)
		_style(card,
			Color(0.20, 0.16, 0.09) if owned else Color(0.12, 0.10, 0.06),
			C_GOLD if current else C_BORDER, 8)
		panel.add_child(card)

		_lbl(card, slot_names[i], 4, 6, 96, 44, 11, C_TEXT if owned else C_DIM, true)

		if buyable:
			var btn := _mk_buy_btn("%d Baies" % cost, Vector2(4, 54), Vector2(96, 28),
				GameManager.gold >= cost)
			var cap_cost := cost
			btn.pressed.connect(func() -> void: _buy_move_slot(cap_cost))
			card.add_child(btn)
		elif owned:
			_lbl(card, "✓ Obtenu", 4, 62, 96, 20, 11, C_GOOD, true)
		else:
			_lbl(card, "Bloqué", 4, 62, 96, 20, 11, C_DIM, true)

	# ── Section équipe ────────────────────────────────────────────────
	_lbl(panel, "Slots d'équipe", 40, 268, 460, 26, 17, C_TEXT)
	_lbl(panel, "Augmente la taille maximale de ton équipe de combat", 40, 292, 460, 20, 12, C_DIM)

	var team_names := ["1 Pokémon\n(départ)", "2 Pokémon", "3 Pokémon", "4 Pokémon", "5 Pokémon", "6 Pokémon\n(max)"]
	for i in 6:
		var owned   := i < GameManager.team_slot_count
		var current := i == GameManager.team_slot_count - 1
		var buyable := i == GameManager.team_slot_count and i < 6
		var cost    := GameManager.TEAM_SLOT_COSTS[i - 1] if i > 0 else 0

		var card := Panel.new()
		card.position = Vector2(40 + i * 153, 320)
		card.size     = Vector2(140, 88)
		_style(card,
			Color(0.20, 0.16, 0.09) if owned else Color(0.12, 0.10, 0.06),
			C_GOLD if current else C_BORDER, 8)
		panel.add_child(card)

		_lbl(card, team_names[i], 4, 6, 132, 44, 11, C_TEXT if owned else C_DIM, true)

		if buyable:
			var btn := _mk_buy_btn("%d Baies" % cost, Vector2(4, 54), Vector2(132, 28),
				GameManager.gold >= cost)
			var cap_cost := cost
			btn.pressed.connect(func() -> void: _buy_team_slot(cap_cost))
			card.add_child(btn)
		elif owned:
			_lbl(card, "✓ Obtenu", 4, 62, 132, 20, 11, C_GOOD, true)

	# ── Section passifs ───────────────────────────────────────────────
	_lbl(panel, "Passifs de récolte", 40, 428, 460, 26, 17, C_TEXT)
	_lbl(panel, "Effets permanents actifs pendant tes runs", 40, 452, 460, 20, 12, C_DIM)

	var magnet_card := Panel.new()
	magnet_card.position = Vector2(40, 480)
	magnet_card.size     = Vector2(300, 88)
	var has_magnet := GameManager.berry_magnet
	_style(magnet_card, Color(0.20, 0.16, 0.09) if has_magnet else Color(0.12, 0.10, 0.06),
		C_GOLD if has_magnet else C_BORDER, 8)
	panel.add_child(magnet_card)
	_lbl(magnet_card, "🧲  Aimant à Baies", 10, 8, 280, 22, 15, C_TEXT)
	_lbl(magnet_card, "Les baies tombées au sol viennent à toi.", 10, 32, 280, 20, 11, C_DIM)
	if has_magnet:
		_lbl(magnet_card, "✓ Obtenu", 10, 60, 280, 20, 12, C_GOOD)
	else:
		var mcost := GameManager.BERRY_MAGNET_COST
		var mbtn := _mk_buy_btn("%d Baies" % mcost, Vector2(10, 56), Vector2(150, 28),
			GameManager.gold >= mcost)
		mbtn.pressed.connect(func() -> void:
			if GameManager.spend_gold(GameManager.BERRY_MAGNET_COST):
				GameManager.berry_magnet = true
				_rebuild()
		)
		magnet_card.add_child(mbtn)

	# ── Charges de Dash (Maj en run) — 0 au départ, 3 max ─────────────
	_lbl(panel, "Charges de Dash", 560, 95, 400, 26, 17, C_TEXT)
	_lbl(panel, "Esquive/burst (Maj) — tu commences sans dash", 560, 119, 400, 20, 12, C_DIM)
	var dash_names := ["0 dash\n(départ)", "1 charge", "2 charges", "3 charges\n(max)"]
	for i in 4:
		var d_owned   := i <= GameManager.dash_charges_bought
		var d_current := i == GameManager.dash_charges_bought
		var d_buyable := i == GameManager.dash_charges_bought + 1 and i <= 3
		var d_cost    := GameManager.DASH_CHARGE_COSTS[i - 1] if i > 0 else 0

		var d_card := Panel.new()
		d_card.position = Vector2(560 + i * 104, 148)
		d_card.size     = Vector2(96, 88)
		_style(d_card,
			Color(0.84, 0.76, 0.60) if d_owned else Color(0.70, 0.63, 0.50),
			C_GOLD if d_current else C_BORDER, 8)
		panel.add_child(d_card)

		_lbl(d_card, dash_names[i], 4, 6, 88, 44, 11, C_TEXT if d_owned else C_DIM, true)

		if d_buyable:
			var d_btn := _mk_buy_btn("%d Baies" % d_cost, Vector2(4, 54), Vector2(88, 28),
				GameManager.gold >= d_cost)
			var cap_d_cost := d_cost
			d_btn.pressed.connect(func() -> void:
				if GameManager.spend_gold(cap_d_cost):
					GameManager.dash_charges_bought += 1
					_rebuild()
			)
			d_card.add_child(d_btn)
		elif d_owned:
			_lbl(d_card, "✓ Obtenu", 4, 62, 88, 20, 11, C_GOOD, true)
		else:
			_lbl(d_card, "Bloqué", 4, 62, 88, 20, 11, C_DIM, true)

	# ── Capacités Spéciales — permanentes, valables pour toutes les runs ──
	_lbl(panel, "Capacités Spéciales", 360, 428, 460, 26, 17, C_TEXT)
	_lbl(panel, "Franchis les obstacles en run (touche A) — définitif", 360, 452, 460, 20, 12, C_DIM)

	for i in GameManager.CS_CATALOG.size():
		var cs: Dictionary = GameManager.CS_CATALOG[i]
		var cs_id: String  = cs["id"]
		var has_cs := GameManager.owns_cs(cs_id)
		var cs_card := Panel.new()
		cs_card.position = Vector2(360 + i * 205, 480)
		cs_card.size     = Vector2(195, 88)
		_style(cs_card, Color(0.20, 0.16, 0.09) if has_cs else Color(0.12, 0.10, 0.06),
			C_GOLD if has_cs else C_BORDER, 8)
		panel.add_child(cs_card)
		_lbl(cs_card, "%s  %s" % [cs["sym"], cs["name"]], 10, 8, 180, 22, 14, C_TEXT)
		var cs_desc := _lbl(cs_card, cs["desc"], 10, 30, 178, 26, 9, C_DIM)
		cs_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if has_cs:
			_lbl(cs_card, "✓ Obtenu", 10, 62, 170, 20, 12, C_GOOD)
		else:
			var cs_price: int = cs["price"]
			var cs_btn := _mk_buy_btn("%d Baies" % cs_price, Vector2(10, 56), Vector2(120, 28),
				GameManager.gold >= cs_price)
			var cap_id := cs_id
			var cap_price := cs_price
			cs_btn.pressed.connect(func() -> void:
				if GameManager.buy_cs(cap_id, cap_price):
					_rebuild()
			)
			cs_card.add_child(cs_btn)

	# ── Fermer ────────────────────────────────────────────────────────
	var close := Button.new()
	close.text     = "✕  Fermer"
	close.position = Vector2(816, 548)
	close.size     = Vector2(160, 40)
	close.add_theme_font_size_override("font_size", 15)
	close.add_theme_color_override("font_color", C_DIM)
	_btn_neutral(close)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


func _buy_move_slot(cost: int) -> void:
	if not GameManager.spend_gold(cost):
		return
	GameManager.move_slot_count += 1
	_rebuild()


func _buy_team_slot(cost: int) -> void:
	if not GameManager.spend_gold(cost):
		return
	GameManager.team_slot_count += 1
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child is MenuNav:
			continue
		child.queue_free()
	await get_tree().process_frame
	_build()
	MenuNav.focus_first(self)


# ── Helpers UI ────────────────────────────────────────────────────────

func _mk_buy_btn(text: String, pos: Vector2, sz: Vector2, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text     = text
	btn.position = pos
	btn.size     = sz
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", C_GOLD if enabled else C_DIM)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.22, 0.17, 0.09); sn.border_color = C_GOLD if enabled else C_BORDER
	sn.set_border_width_all(2); sn.set_corner_radius_all(6)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.24, 0.12)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	return btn


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
	s.bg_color = Color(0.22, 0.18, 0.11); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.25, 0.15)
	btn.add_theme_stylebox_override("hover", sh)
