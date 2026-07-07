class_name BoutiqueScreen
extends CanvasLayer

## Écran « bois & parchemin » (cf. UiKit, mockups utilisateur) — UN SEUL
## écran clair, trois contextes :
##   "vendor" : Améliorations & Boutique (attaques payantes + Baies + CS) ;
##   "skill"  : don gratuit — même parchemin d'attaque, sans boutique ;
##   "stat"   : don gratuit — grille 2×2 de bonus d'équipe.
## Parchemin d'attaque : on choisit son Pokémon (onglets), on voit ses
## attaques ACTUELLES à gauche et les NOUVELLES à droite ; « Apprendre »
## apprend direct s'il reste un slot, sinon on clique l'attaque à remplacer
## (surbrillance cyan). Échap annule le remplacement, puis ferme.

signal learn_move(member_index: int, option_index: int, replace_index: int)  # -1 = slot libre
signal buy_berries(price: int, amount: int)
signal buy_cs(cs_id: String)
signal boon_stat(stat_id: String)
signal closed

const BERRY_PACKS: Array[Dictionary] = [
	{"amount": 20,  "price": 60},
	{"amount": 50,  "price": 130},
	{"amount": 120, "price": 280},
]

const STAT_BOONS: Array[Dictionary] = [
	{"id": "boost_atk", "label": "Attaque +20%", "sym": "⚔"},
	{"id": "boost_def", "label": "Défense +20%", "sym": "🛡"},
	{"id": "boost_hp",  "label": "PV max +20%",  "sym": "♥"},
	{"id": "boost_spd", "label": "Vitesse +20%", "sym": "⚡"},
]

var _kind: String = "vendor"
var _team:   Array = []
var _offers: Array = []
var _sel_member: int = 0        # onglet Pokémon sélectionné
var _replace_option: int = -1   # offre en attente d'un remplacement (-1 = aucune)
var _panel: Panel = null
var _tabs: Array = []           # onglets Pokémon (restauration du focus)
var _focus_tab: int = -1        # onglet à refocaliser après _rebuild (navigation flèches)
var _first_build: bool = true   # pop d'apparition uniquement à l'ouverture


func setup(team: Array, offers: Array, kind: String = "vendor") -> void:
	layer   = 22
	_team   = team
	_offers = offers
	_kind   = kind
	_sel_member = 0
	_replace_option = -1
	add_child(MenuNav.make(_on_cancel_pressed))
	_rebuild()


## Le jeu est en PAUSE tant que l'écran est ouvert (les flèches naviguent).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true


func _exit_tree() -> void:
	get_tree().paused = false


func refresh() -> void:
	_replace_option = -1
	_rebuild()


func _on_cancel_pressed() -> void:
	if _replace_option >= 0:
		_replace_option = -1
		_rebuild()
	else:
		closed.emit()


# ── Construction ───────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in get_children():
		if c is MenuNav:
			continue
		c.queue_free()

	# Voile discret (le monde reste visible, saturé, derrière — cf. mockup)
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.05, 0.03, 0.45)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	_panel = UiKit.main_panel(Vector2(200, 34), Vector2(880, 636))
	add_child(_panel)
	_tabs.clear()

	if _kind == "stat":
		_build_stat_boon()
	else:
		_build_attack_scroll()

	if _first_build:
		_first_build = false
		UiKit.pop_in(_panel)

	# Navigation flèches : si la reconstruction vient d'un changement
	# d'onglet, on rend le focus à cet onglet (le parcours continue).
	if _focus_tab >= 0 and _focus_tab < _tabs.size():
		(_tabs[_focus_tab] as Button).grab_focus.call_deferred()
		_focus_tab = -1
	else:
		MenuNav.focus_first(_panel)


# ── Don « stats » : grille 2×2 (mockup 1) ─────────────────────────────
func _build_stat_boon() -> void:
	UiKit.banner(_panel, "Bonus de stats")
	var cw := 380.0; var ch := 120.0
	for i in STAT_BOONS.size():
		var boon: Dictionary = STAT_BOONS[i]
		var px := 40.0 + (i % 2) * (cw + 40.0)
		var py := 96.0 + (i / 2) * (ch + 26.0)
		var card := UiKit.card(_panel, Vector2(px, py), Vector2(cw, ch))
		UiKit.icon_square(card, Vector2(18, 30), boon["sym"], 58.0)
		UiKit.label(card, boon["label"], Vector2(96, 44), 22, UiKit.TEXT_DARK, 270)
		var btn := UiKit.button("Choisir", Vector2(110, 40))
		btn.position = Vector2(cw - 128, ch - 54)
		var sid: String = boon["id"]
		btn.pressed.connect(func() -> void: boon_stat.emit(sid))
		card.add_child(btn)

	var info := UiKit.dark_card(_panel, Vector2(40, 402), Vector2(800, 74))
	UiKit.label(info, "Choisis un bonus — appliqué à TOUTE l'équipe",
		Vector2(0, 24), 20, UiKit.CREAM, 800, HORIZONTAL_ALIGNMENT_CENTER)
	_add_continue(520)


# ── Parchemin d'attaque (mockup 2) — un seul écran ────────────────────
func _build_attack_scroll() -> void:
	UiKit.banner(_panel, "Améliorations et Boutique" if _kind == "vendor" else "Nouvelle Attaque")
	if _kind == "vendor":
		UiKit.label(_panel, "Bourse : %d ₽    Baies : %d ◆" % [GameManager.run_money, GameManager.gold],
			Vector2(0, 62), 15, UiKit.GOLD, 880, HORIZONTAL_ALIGNMENT_CENTER)

	# Onglets Pokémon RICHES (portrait + nom + niveau + type) — le contenu
	# change dès que le FOCUS arrive sur l'onglet (flèches) : plus besoin
	# d'appuyer sur Entrée pour comparer les Pokémon.
	_sel_member = clampi(_sel_member, 0, maxi(0, _team.size() - 1))
	var tab_w := 168.0
	var tabs_x := (880.0 - _team.size() * (tab_w + 12.0)) * 0.5
	for i in _team.size():
		var inst: PokemonInstance = _team[i].pokemon_instance
		var sel := i == _sel_member
		var tab := Button.new()
		tab.position = Vector2(tabs_x + i * (tab_w + 12.0), 74)
		tab.size     = Vector2(tab_w, 60)
		tab.add_theme_stylebox_override("normal",
			UiKit.style(UiKit.TAN if sel else UiKit.BROWN_CARD, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 10, 4 if sel else 3))
		tab.add_theme_stylebox_override("hover",
			UiKit.style(UiKit.TAN_DARK, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 10, 3))
		tab.add_theme_stylebox_override("pressed", tab.get_theme_stylebox("normal"))
		tab.add_theme_stylebox_override("focus",
			UiKit.style(UiKit.TAN if sel else UiKit.TAN_DARK, UiKit.CYAN_SEL, 10, 4))
		_panel.add_child(tab)

		if is_instance_valid(inst.portrait_texture):
			var tex := TextureRect.new()
			tex.texture      = inst.portrait_texture
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.position     = Vector2(4, 4)
			tex.size         = Vector2(52, 52)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tab.add_child(tex)
		var name_col := UiKit.TEXT_DARK if sel else UiKit.CREAM
		UiKit.label(tab, inst.data.name_fr.capitalize(), Vector2(60, 5), 14, name_col, 106)
		UiKit.label(tab, "Niv. %d" % inst.level, Vector2(60, 24), 11, name_col.lightened(0.15) if sel else name_col.darkened(0.1), 100)
		if not inst.data.types.is_empty():
			UiKit.type_badge(tab, Vector2(58, 39), inst.data.types[0], 17.0)

		var ci := i
		# FOCUS = sélection immédiate (le panneau se reconstruit et rend le
		# focus à l'onglet — la navigation aux flèches reste fluide)
		tab.focus_entered.connect(func() -> void:
			if _sel_member != ci:
				_sel_member = ci
				_replace_option = -1
				_focus_tab = ci
				_rebuild()
		)
		tab.pressed.connect(func() -> void:
			if _sel_member != ci:
				_sel_member = ci; _replace_option = -1; _rebuild())
		_tabs.append(tab)

	var inst: PokemonInstance = _team[_sel_member].pokemon_instance
	UiKit.label(_panel, "📜  Parchemin d'Attaque", Vector2(0, 140), 21, UiKit.GOLD,
		880, HORIZONTAL_ALIGNMENT_CENTER)

	# ── Colonne gauche : attaques actuelles ──────────────────────────
	UiKit.label(_panel, "ATTAQUES ACTUELLES DE %s (Niv. %d)"
		% [inst.data.name_fr.to_upper(), inst.level], Vector2(36, 176), 13, UiKit.CREAM, 400)
	var moves: Array = inst.equipped_moves
	for i in moves.size():
		var md: MoveData = moves[i]
		var y := 202.0 + i * 62.0
		if _replace_option >= 0:
			# Mode remplacement : les attaques deviennent cliquables (cyan)
			var mcard := UiKit.card(_panel, Vector2(36, y), Vector2(400, 56), true)
			_fill_move_row(mcard, md)
			var pick := UiKit.button("Remplacer", Vector2(96, 34), true)
			pick.position = Vector2(296, 11)
			var ri := i; var oi := _replace_option; var mi := _sel_member
			pick.pressed.connect(func() -> void: learn_move.emit(mi, oi, ri))
			mcard.add_child(pick)
		else:
			var mcard := UiKit.card(_panel, Vector2(36, y), Vector2(400, 56))
			_fill_move_row(mcard, md)
	if _replace_option >= 0:
		UiKit.label(_panel, "Choisis l'attaque à remplacer  (Échap : annuler)",
			Vector2(36, 202.0 + moves.size() * 62.0), 14, UiKit.CYAN_SEL, 400)

	# ── Colonne droite : nouvelles attaques ──────────────────────────
	UiKit.label(_panel, "NOUVELLES ATTAQUES DISPONIBLES À APPRENDRE",
		Vector2(452, 176), 13, UiKit.CREAM, 400)
	var options: Array = _offers[_sel_member] if _sel_member < _offers.size() else []
	if options.is_empty():
		var empty := UiKit.dark_card(_panel, Vector2(452, 202), Vector2(392, 56))
		UiKit.label(empty, "Rien à apprendre pour ce Pokémon", Vector2(0, 18), 14,
			UiKit.CREAM, 392, HORIZONTAL_ALIGNMENT_CENTER)
	for i in options.size():
		var mv: Dictionary = options[i]
		var y := 202.0 + i * 82.0
		var price := int(mv.get("price", 0))
		var afford: bool = price <= 0 or GameManager.run_money >= price
		var ocard := UiKit.card(_panel, Vector2(452, y), Vector2(392, 76), _replace_option == i)
		UiKit.icon_square(ocard, Vector2(10, 14), UiKit.type_sym(str(mv.get("type", ""))), 48.0)
		UiKit.label(ocard, str(mv.get("label", "")), Vector2(68, 7), 17, UiKit.TEXT_DARK, 210)
		UiKit.type_badge(ocard, Vector2(68, 34), str(mv.get("type", "")), 21.0)
		UiKit.label(ocard, "Puiss. %d%s" % [int(mv.get("power", 0)),
			("  ·  %d ₽" % price) if price > 0 else ""],
			Vector2(152, 38), 13, UiKit.TEXT_DARK.lightened(0.25), 130)
		var learn := UiKit.button("Apprendre", Vector2(104, 40))
		learn.position = Vector2(392 - 116, 18)
		learn.disabled = not afford
		var oi := i; var mi := _sel_member
		learn.pressed.connect(func() -> void:
			if _team[mi].pokemon_instance.equipped_moves.size() < GameManager.move_slot_count:
				learn_move.emit(mi, oi, -1)      # slot libre : direct
			else:
				_replace_option = oi              # sinon : choisir quoi remplacer
				_rebuild())
		ocard.add_child(learn)

	# ── Boutique du bas (vendeur uniquement) : Baies + CS ─────────────
	if _kind == "vendor":
		UiKit.label(_panel, "⭐  Boutique de Baies & CS  ⭐", Vector2(0, 462), 17,
			UiKit.GOLD, 880, HORIZONTAL_ALIGNMENT_CENTER)
		for i in BERRY_PACKS.size():
			var pack: Dictionary = BERRY_PACKS[i]
			var bx := 36.0 + i * 140.0
			var bcard := UiKit.card(_panel, Vector2(bx, 492), Vector2(130, 78))
			UiKit.label(bcard, "◆ %d Baies" % int(pack["amount"]), Vector2(8, 6), 14, UiKit.TEXT_DARK, 120)
			var bb := UiKit.button("%d ₽" % int(pack["price"]), Vector2(96, 30))
			bb.position = Vector2(17, 38)
			bb.disabled = GameManager.run_money < int(pack["price"])
			var pr := int(pack["price"]); var am := int(pack["amount"])
			bb.pressed.connect(func() -> void: buy_berries.emit(pr, am))
			bcard.add_child(bb)
		var cs_list: Array = GameManager.CS_CATALOG
		for i in cs_list.size():
			var cs: Dictionary = cs_list[i]
			var cx := 460.0 + i * 132.0
			var ccard := UiKit.card(_panel, Vector2(cx, 492), Vector2(122, 78))
			UiKit.label(ccard, "%s %s" % [cs.get("sym", ""), cs.get("name", "")],
				Vector2(6, 6), 13, UiKit.TEXT_DARK, 116)
			if GameManager.owns_cs(cs["id"]):
				UiKit.label(ccard, "✓ Obtenue", Vector2(6, 42), 13, UiKit.GREEN_DARK, 110)
			else:
				var cb := UiKit.button("%d ₽" % int(cs["price"]), Vector2(92, 30))
				cb.position = Vector2(15, 38)
				cb.disabled = GameManager.run_money < int(cs["price"])
				var cid: String = cs["id"]
				cb.pressed.connect(func() -> void: buy_cs.emit(cid))
				ccard.add_child(cb)

	_add_continue(578)


func _fill_move_row(card: Panel, md: MoveData) -> void:
	UiKit.icon_square(card, Vector2(8, 8), UiKit.type_sym(md.type), 40.0)
	UiKit.label(card, md.display_name, Vector2(58, 5), 16, UiKit.TEXT_DARK, 220)
	UiKit.type_badge(card, Vector2(58, 29), md.type, 20.0)
	UiKit.label(card, "%s · Puiss. %d" %
		["Spéciale" if md.damage_class == "special" else "Physique", md.power],
		Vector2(138, 31), 12, UiKit.TEXT_DARK.lightened(0.25), 160)


func _add_continue(y: float) -> void:
	var cont := UiKit.button("Continuer  →", Vector2(220, 48))
	cont.position = Vector2((_panel.size.x - 220.0) * 0.5, y)
	cont.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(cont)
