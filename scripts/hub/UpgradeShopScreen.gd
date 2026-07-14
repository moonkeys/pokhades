class_name UpgradeShopScreen
extends CanvasLayer

signal closed

# Palette « bois & parchemin » (cf. UiKit) — texte SOMBRE sur les cartes
# parchemin, titres CRÈME sur le panneau bois.
const C_BORDER := UiKit.WOOD_EDGE
const C_TEXT   := UiKit.TEXT_DARK
const C_DIM    := Color(0.45, 0.33, 0.20)
const C_GOLD   := Color(0.72, 0.52, 0.12)
const C_GOLD_LT:= UiKit.GOLD
const C_GOOD   := UiKit.GREEN_DARK


func _ready() -> void:
	layer = 10
	add_child(MenuNav.make(func() -> void: closed.emit()))   # Échap = fermer
	_build()
	MenuNav.focus_first(self)


func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := UiKit.main_panel(Vector2(140, 40), Vector2(1000, 660))
	add_child(panel)
	UiKit.banner(panel, "Améliorations permanentes")
	UiKit.pop_in(panel)
	UiKit.label(panel, "◆ %d Baies" % GameManager.gold, Vector2(0, 64), 15,
		UiKit.GOLD, 1000, HORIZONTAL_ALIGNMENT_CENTER)

	# ── Section capacités ─────────────────────────────────────────────
	_lbl(panel, "Emplacements de capacités", 40, 95, 460, 26, 17, UiKit.CREAM)
	_lbl(panel, "Chaque Pokémon équipe plus de capacités en combat", 40, 119, 460, 20, 12, Color(0.85, 0.78, 0.62))

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
			UiKit.TAN if owned else UiKit.TAN_DARK,
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
	_lbl(panel, "Slots d'équipe", 40, 268, 460, 26, 17, UiKit.CREAM)
	_lbl(panel, "Augmente la taille maximale de ton équipe de combat", 40, 292, 460, 20, 12, Color(0.85, 0.78, 0.62))

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
			UiKit.TAN if owned else UiKit.TAN_DARK,
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
	_lbl(panel, "Passifs de récolte", 40, 428, 460, 26, 17, UiKit.CREAM)
	_lbl(panel, "Effets permanents actifs pendant tes runs", 40, 452, 460, 20, 12, Color(0.85, 0.78, 0.62))

	var magnet_card := Panel.new()
	magnet_card.position = Vector2(40, 480)
	magnet_card.size     = Vector2(300, 88)
	var has_magnet := GameManager.berry_magnet
	_style(magnet_card, UiKit.TAN if has_magnet else UiKit.TAN_DARK,
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
				Sfx.play_file(Sfx.SE_BUY_ITEM)
				GameManager.berry_magnet = true
				_rebuild()
		)
		magnet_card.add_child(mbtn)

	# ── Charges de Dash (Maj en run) — 0 au départ, 3 max ─────────────
	_lbl(panel, "Charges de Dash", 560, 95, 400, 26, 17, UiKit.CREAM)
	_lbl(panel, "Esquive/burst (Maj) — tu commences sans dash", 560, 119, 400, 20, 12, Color(0.85, 0.78, 0.62))
	# "0 dash (départ)" n'est pas un achat — rien à afficher, juste du bruit.
	var dash_names := ["1 charge", "2 charges", "3 charges\n(max)"]
	for i in range(1, 4):
		var d_owned   := i <= GameManager.dash_charges_bought
		var d_current := i == GameManager.dash_charges_bought
		var d_buyable := i == GameManager.dash_charges_bought + 1 and i <= 3
		var d_cost    := GameManager.DASH_CHARGE_COSTS[i - 1]

		var d_card := Panel.new()
		d_card.position = Vector2(560 + (i - 1) * 104, 148)
		d_card.size     = Vector2(96, 88)
		_style(d_card,
			UiKit.TAN if d_owned else UiKit.TAN_DARK,
			C_GOLD if d_current else C_BORDER, 8)
		panel.add_child(d_card)

		_lbl(d_card, dash_names[i - 1], 4, 6, 88, 44, 11, C_TEXT if d_owned else C_DIM, true)

		if d_buyable:
			var d_btn := _mk_buy_btn("%d Baies" % d_cost, Vector2(4, 54), Vector2(88, 28),
				GameManager.gold >= d_cost)
			var cap_d_cost := d_cost
			d_btn.pressed.connect(func() -> void:
				if GameManager.spend_gold(cap_d_cost):
					Sfx.play_file(Sfx.SE_BUY_ITEM)
					GameManager.dash_charges_bought += 1
					_rebuild()
			)
			d_card.add_child(d_btn)
		elif d_owned:
			_lbl(d_card, "✓ Obtenu", 4, 62, 88, 20, 11, C_GOOD, true)
		else:
			_lbl(d_card, "Bloqué", 4, 62, 88, 20, 11, C_DIM, true)

	# ── Capacités Spéciales — permanentes, valables pour toutes les runs ──
	_lbl(panel, "Capacités Spéciales", 360, 428, 460, 26, 17, UiKit.CREAM)
	_lbl(panel, "Franchis les obstacles en run (touche A) — définitif", 360, 452, 460, 20, 12, Color(0.85, 0.78, 0.62))

	for i in GameManager.CS_CATALOG.size():
		var cs: Dictionary = GameManager.CS_CATALOG[i]
		var cs_id: String  = cs["id"]
		var has_cs := GameManager.owns_cs(cs_id)
		var cs_card := Panel.new()
		cs_card.position = Vector2(360 + i * 205, 480)
		cs_card.size     = Vector2(195, 88)
		_style(cs_card, UiKit.TAN if has_cs else UiKit.TAN_DARK,
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

	# ── Plafond de poids de build ────────────────────────────────────────
	# cf. GameManager.compute_team_weight — Pokémon + objets tenus + CT
	# équipées ne doivent pas dépasser ce plafond pour lancer une run.
	_lbl(panel, "Plafond de poids de build", 40, 578, 460, 26, 17, UiKit.CREAM)
	_lbl(panel, "Se paie en ✦ Éclats de Champion (lâchés par les boss) — tu en as %d"
		% GameManager.champion_shards,
		40, 602, 460, 20, 12, Color(0.85, 0.78, 0.62))

	var cap_card := Panel.new()
	cap_card.position = Vector2(560, 578)
	cap_card.size     = Vector2(300, 56)
	var at_max := GameManager.build_weight_cap >= GameManager.WEIGHT_CAP_MAX
	_style(cap_card, UiKit.TAN if at_max else UiKit.TAN_DARK,
		C_GOLD if at_max else C_BORDER, 8)
	panel.add_child(cap_card)
	_lbl(cap_card, "Plafond actuel : %d" % GameManager.build_weight_cap, 10, 6, 180, 22, 14, C_TEXT)
	if at_max:
		_lbl(cap_card, "✓ Maximum", 10, 30, 180, 20, 11, C_GOOD)
	else:
		var tier := (GameManager.build_weight_cap - 24) / GameManager.WEIGHT_CAP_STEP
		var wcost: int = GameManager.WEIGHT_CAP_COSTS[tier]
		var wbtn := _mk_buy_btn("✦ %d Éclats" % wcost, Vector2(178, 12), Vector2(112, 32),
			GameManager.champion_shards >= wcost)
		wbtn.pressed.connect(func() -> void:
			if GameManager.buy_weight_cap(wcost):
				Sfx.play_file(Sfx.SE_BUY_ITEM)
				_rebuild()
		)
		cap_card.add_child(wbtn)

	# ── Fermer ────────────────────────────────────────────────────────
	var close := UiKit.button("✕  Fermer", Vector2(160, 40), false)
	close.position = Vector2(816, 600)
	close.pressed.connect(func() -> void: closed.emit())
	panel.add_child(close)


func _buy_move_slot(cost: int) -> void:
	if not GameManager.spend_gold(cost):
		return
	Sfx.play_file(Sfx.SE_BUY_ITEM)
	GameManager.move_slot_count += 1
	_rebuild()


func _buy_team_slot(cost: int) -> void:
	if not GameManager.spend_gold(cost):
		return
	Sfx.play_file(Sfx.SE_BUY_ITEM)
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
	var btn := UiKit.button(text, sz)   # bouton vert du kit (juice inclus)
	btn.position = pos
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", UiKit.scaled_font(12))
	return btn


func _lbl(parent: Node, text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", UiKit.scaled_font(fs))
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


