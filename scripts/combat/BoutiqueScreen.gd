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
## Renforce une attaque DÉJÀ équipée (+puissance, cf. MoveData.apply_upgrade)
## au lieu d'en apprendre une nouvelle — retour joueurs : « pouvoir donner des
## bonus aux attaques déjà existantes, pas toujours de nouvelles attaques ».
signal upgrade_move(member_index: int, option_index: int)
signal buy_berries(price: int, amount: int)
signal buy_cs(cs_id: String)
signal buy_potion(member_index: int, item_id: String)
signal boon_stat(stat_id: String, member_index: int)   # tout se choisit sur un seul écran
signal closed

## Conversion ₽ → Baies. Taux VOLONTAIREMENT ingrat (≈0.25 baie/₽ au lieu de
## 0.43) : c'était le principal robinet d'inflation des baies, et convertir sa
## bourse en monnaie méta ne doit jamais être plus rentable que d'acheter de
## quoi survivre à la run.
const BERRY_PACKS: Array[Dictionary] = [
	{"amount": 20,  "price": 100},
	{"amount": 50,  "price": 220},
	{"amount": 120, "price": 480},
]

## Bassin COMPLET des dons de stat — 3 tirés au hasard à chaque don (cf.
## CombatArena._roll_stat_boon_offer), plus jamais les 4/9 en bloc à chaque
## fois (retour joueurs : « proposer le choix entre 3 bonus, pas 4 générés
## systématiquement » + « ajouter vitesse de déplacement, réduction des
## cooldowns, portée, critique, esquive, attaque/défense spéciale »).
const STAT_BOONS: Array[Dictionary] = [
	{"id": "boost_atk",   "label": "Attaque +20%",       "sym": "⚔"},
	{"id": "boost_def",   "label": "Défense +20%",       "sym": "🛡"},
	{"id": "boost_hp",    "label": "PV max +20%",        "sym": "♥"},
	{"id": "boost_spd",   "label": "Vitesse +20%",       "sym": "⚡"},
	{"id": "boost_spatk", "label": "Atq. Spé +20%",      "sym": "✨"},
	{"id": "boost_spdef", "label": "Déf. Spé +20%",      "sym": "🔰"},
	{"id": "atk_rate",    "label": "Cadence -15%",       "sym": "⏱"},
	{"id": "boost_range", "label": "Portée +20%",        "sym": "🎯"},
	{"id": "boost_crit",  "label": "Critique +15%",      "sym": "💥"},
	{"id": "boost_dodge", "label": "Esquive +12%",       "sym": "💨"},
]

## Objets de soin achetables en boutique — s'appliquent au Pokémon de
## l'onglet sélectionné (_sel_member). "heal" < 0 = soin complet ; les
## rappels ("revive": true) ne s'utilisent QUE sur un membre K.O., et ce
## sont le SEUL moyen de le ranimer (cf. CombatArena._buy_boutique_potion).
const ICON_DIR := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Items/"
const HEAL_ITEMS: Array[Dictionary] = [
	{"id": "potion",       "name": "Potion",       "heal": 20,   "price": 40,  "revive": false, "icon": ICON_DIR + "POTION.png"},
	{"id": "super_potion", "name": "Super Potion", "heal": 50,   "price": 90,  "revive": false, "icon": ICON_DIR + "SUPERPOTION.png"},
	{"id": "hyper_potion", "name": "Hyper Potion", "heal": 120,  "price": 160, "revive": false, "icon": ICON_DIR + "HYPERPOTION.png"},
	{"id": "max_potion",   "name": "Potion Max",   "heal": -1.0, "price": 220, "revive": false, "icon": ICON_DIR + "MAXPOTION.png"},
	{"id": "revive",       "name": "Rappel",       "heal": 0.5,  "price": 150, "revive": true,  "icon": ICON_DIR + "REVIVE.png"},
	{"id": "max_revive",   "name": "Rappel Max",   "heal": 1.0,  "price": 280, "revive": true,  "icon": ICON_DIR + "MAXREVIVE.png"},
]

static var _item_icon_cache: Dictionary = {}

static func _item_icon(path: String) -> Texture2D:
	if not _item_icon_cache.has(path):
		_item_icon_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _item_icon_cache[path]

var _kind: String = "vendor"
var _team:   Array = []
var _offers: Array = []
var _sel_member: int = 0        # onglet Pokémon sélectionné
var _replace_option: int = -1   # offre en attente d'un remplacement (-1 = aucune)
var _panel: Panel = null
var _tabs: Array = []           # onglets Pokémon (restauration du focus)
var _focus_tab: int = -1        # onglet à refocaliser après _rebuild (navigation flèches)
var _first_build: bool = true   # pop d'apparition uniquement à l'ouverture
var _shop_tab: String = "baies" # "baies" (Baies & CS) | "soins" (Potions & Rappels)


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
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)


func _exit_tree() -> void:
	get_tree().paused = false
	Sfx.play_file(Sfx.SE_MENU_CLOSE, -6.0)


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

	# Navigation flèches : on rend le focus à l'onglet COURANT après chaque
	# reconstruction.
	#
	# BUG CORRIGÉ (bloquant, surtout en multi) : le `else` appelait
	# MenuNav.focus_first(), qui donnait le focus au PREMIER bouton focalisable
	# — c'est-à-dire l'onglet du 1er Pokémon. Or les onglets sélectionnent au
	# `focus_entered` : on retombait donc systématiquement sur le 1er Pokémon.
	# Conséquence : impossible de remplacer une attaque sur un autre Pokémon —
	# cliquer "Apprendre" (qui reconstruit pour choisir quoi remplacer)
	# ramenait aussitôt à l'onglet du premier.
	var ft := _focus_tab if _focus_tab >= 0 else _sel_member
	_focus_tab = -1
	if ft >= 0 and ft < _tabs.size():
		(_tabs[ft] as Button).grab_focus.call_deferred()
	else:
		MenuNav.focus_first(_panel)


## Fiche complète d'une attaque ([I]) — nom FR, type, puissance/précision/PP,
## effet maison et description officielle. Charge le détail via PokemonAPI ;
## son MenuNav (ajouté après celui de l'écran) capte Échap en premier.
var _move_info: CanvasLayer = null

func _open_move_info(mv: Dictionary) -> void:
	if is_instance_valid(_move_info):
		_move_info.queue_free()
	var pop := CanvasLayer.new()
	pop.layer = 30
	_move_info = pop
	add_child(pop)
	var close_pop := func() -> void:
		pop.queue_free()
		_move_info = null
	pop.add_child(MenuNav.make(close_pop))
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.02, 0.01, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pop.add_child(veil)
	var panel := UiKit.main_panel(Vector2(360, 150), Vector2(600, 400))
	pop.add_child(panel)
	UiKit.banner(panel, str(mv.get("label", "Attaque")))
	UiKit.type_badge(panel, Vector2(32, 84), str(mv.get("type", "normal")), 24.0)
	var body := UiKit.label(panel, "Chargement…", Vector2(32, 128), 14, UiKit.CREAM, 536, HORIZONTAL_ALIGNMENT_LEFT, true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var house := str(mv.get("desc", ""))
	var api := str(mv.get("api", ""))
	var w_body: WeakRef = weakref(body)
	PokemonAPI.get_move(api, func(md: Dictionary) -> void:
		var bd: Label = w_body.get_ref()
		if bd == null: return
		var lines: Array[String] = []
		var pv: Variant = md.get("power")
		var av: Variant = md.get("accuracy")
		var ppv: Variant = md.get("pp")
		var kl: String = {"physical": "Physique", "special": "Spéciale", "status": "Statut"} \
			.get(str(md.get("damage_class", str(mv.get("damage_class", "")))), "?")
		lines.append("Puissance : %s      Précision : %s      PP : %s" % [
			str(int(pv)) if pv != null else str(int(mv.get("power", 0))),
			("%d %%" % int(av)) if av != null else "—",
			str(int(ppv)) if ppv != null else "—"])
		lines.append("Classe : %s" % kl)
		if house != "":
			lines.append("")
			lines.append("★ Effet dans Pokhades : %s" % house)
		var d := str(md.get("desc_fr", ""))
		if d != "":
			lines.append("")
			lines.append(d)
		bd.text = "\n".join(lines))
	var ok := UiKit.button("Fermer  (Échap)", Vector2(220, 40), false)
	ok.position = Vector2(190, 340)
	ok.pressed.connect(close_pop)
	panel.add_child(ok)
	MenuNav.focus_first(panel)


# ── Don « stats » — UN SEUL écran ─────────────────────────────────────
## Le choix se faisait en DEUX fenêtres : la grille des stats ici, puis un
## ItemRewardScreen par-dessus pour désigner le Pokémon. On enchaînait deux
## panneaux pour une seule décision, et le second masquait le premier — d'où
## le "j'ai pas vu ce choix" (retour joueurs).
##
## Tout tient maintenant sur un écran : le Pokémon EN HAUT, le bonus en
## dessous. La sélection suit le FOCUS (flèches) — pas besoin de valider le
## Pokémon avant de descendre : le libellé rappelle en permanence à qui le
## bonus s'appliquera, et Entrée sur un bonus conclut.
var _stat_hint: Label = null
var _stat_boon_btns: Array = []   # boutons "Choisir" des 4 stats (cible du focus)

func _build_stat_boon() -> void:
	UiKit.banner(_panel, "Bonus de stats")
	_stat_boon_btns.clear()
	_build_stat_member_row()

	# 3 dons tirés au hasard, décidés une fois pour toutes par CombatArena
	# (_roll_stat_boon_offer) et passés via `_offers` — pas les 4/9 systématiquement
	# (retour joueurs). Filet de sécurité si jamais vide : les 3 premiers du bassin.
	var offer: Array = _offers if not _offers.is_empty() else STAT_BOONS.slice(0, 3)
	var cw := 380.0; var ch := 108.0
	for i in offer.size():
		var boon: Dictionary = offer[i]
		var px := 40.0 + (i % 2) * (cw + 40.0)
		var py := 300.0 + (i / 2) * (ch + 20.0)
		var card := UiKit.card(_panel, Vector2(px, py), Vector2(cw, ch))
		UiKit.icon_square(card, Vector2(16, 24), boon["sym"], 54.0)
		UiKit.label(card, boon["label"], Vector2(90, 36), 21, UiKit.TEXT_DARK, 270)
		var btn := UiKit.button("Choisir", Vector2(110, 38))
		btn.position = Vector2(cw - 126, ch - 50)
		var sid: String = boon["id"]
		btn.pressed.connect(func() -> void: boon_stat.emit(sid, _sel_member))
		card.add_child(btn)
		_stat_boon_btns.append(btn)

	_add_continue(556)


## Rangée de sélection du Pokémon (haut de l'écran). Les membres K.O. et, en
## multijoueur, les copies des AUTRES joueurs (remote_peer != 0) sont
## désactivés : on ne buffe que ses propres Pokémon valides.
func _build_stat_member_row() -> void:
	_tabs.clear()
	var live: Array = []
	for m in _team:
		if is_instance_valid(m) and m.pokemon_instance != null:
			live.append(m)
	if live.is_empty():
		return

	# Le membre présélectionné doit être ÉLIGIBLE : _sel_member vaut 0 par
	# défaut, or le 1er membre peut être K.O. ou appartenir à un autre joueur.
	if not _stat_member_ok(_team[_sel_member] if _sel_member < _team.size() else null):
		for m in live:
			if _stat_member_ok(m):
				_sel_member = m.team_index
				break

	var cw := 128.0
	var pad := (880.0 - live.size() * cw) / float(live.size() + 1)
	for i in live.size():
		var m = live[i]
		var inst: PokemonInstance = m.pokemon_instance
		var px := pad + i * (cw + pad)
		var card := UiKit.card(_panel, Vector2(px, 84), Vector2(cw, 150))

		if is_instance_valid(inst.portrait_texture):
			var tex := TextureRect.new()
			tex.texture        = inst.portrait_texture
			tex.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.position       = Vector2((cw - 56) * 0.5, 6)
			tex.size           = Vector2(56, 56)
			tex.modulate.a     = 0.45 if inst.is_fainted() else 1.0
			tex.mouse_filter   = Control.MOUSE_FILTER_IGNORE   # le clic doit atteindre le bouton
			card.add_child(tex)

		UiKit.label(card, inst.data.name_fr.capitalize(), Vector2(4, 64), 13,
			UiKit.RED_SOFT if inst.is_fainted() else UiKit.TEXT_DARK,
			cw - 8, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.label(card, "Niv. %d" % inst.level, Vector2(4, 82), 11,
			UiKit.TEXT_DARK.lightened(0.25), cw - 8, HORIZONTAL_ALIGNMENT_CENTER)

		var ok := _stat_member_ok(m)
		var btn := UiKit.button("K.O." if inst.is_fainted() else "Choisir", Vector2(cw - 16, 34), ok)
		btn.position = Vector2(8, 106)
		btn.disabled = not ok
		var idx: int = m.team_index
		if ok:
			# Sélection au FOCUS : les flèches parcourent la rangée et le Pokémon
			# visé devient la cible, sans validation intermédiaire.
			btn.focus_entered.connect(func() -> void: _set_stat_member(idx))
			# Entrée sur un Pokémon = "c'est celui-là" → on descend aux bonus.
			btn.pressed.connect(func() -> void:
				_set_stat_member(idx)
				if not _stat_boon_btns.is_empty():
					(_stat_boon_btns[0] as Button).grab_focus()
			)
		card.add_child(btn)
		_tabs.append(btn)
		# Focus initial sur le Pokémon RETENU, et via sa position dans _tabs.
		# _rebuild indexe _tabs par _sel_member, qui est un team_index : les deux
		# ne coïncident pas dès qu'un membre manque, et le bouton visé pourrait
		# être désactivé (K.O. / autre joueur) — grab_focus y échouerait en
		# silence et les flèches resteraient inertes.
		if ok and idx == _sel_member:
			_focus_tab = _tabs.size() - 1

	var info := UiKit.dark_card(_panel, Vector2(40, 244), Vector2(800, 46))
	_stat_hint = UiKit.label(info, "", Vector2(0, 12), 18, UiKit.CREAM, 800,
		HORIZONTAL_ALIGNMENT_CENTER)
	_refresh_stat_hint()


func _stat_member_ok(m) -> bool:
	if m == null or not is_instance_valid(m) or m.pokemon_instance == null:
		return false
	if m.pokemon_instance.is_fainted():
		return false
	return m.remote_peer == 0   # multi : pas les Pokémon des autres joueurs


func _set_stat_member(idx: int) -> void:
	if _sel_member == idx:
		return
	_sel_member = idx
	_refresh_stat_hint()


## Rappel permanent de la cible — c'est LUI qui remplace la seconde fenêtre :
## sans lui, on choisirait un bonus sans savoir à qui il va.
func _refresh_stat_hint() -> void:
	if not is_instance_valid(_stat_hint):
		return
	var nm := "?"
	if _sel_member >= 0 and _sel_member < _team.size():
		var m = _team[_sel_member]
		if is_instance_valid(m) and m.pokemon_instance != null:
			nm = m.pokemon_instance.data.name_fr.capitalize()
	_stat_hint.text = "Bonus pour :  %s" % nm


# ── Parchemin d'attaque (mockup 2) — un seul écran ────────────────────
## En multijoueur, on ne doit acheter/changer des attaques QUE pour SON
## PROPRE Pokémon — avant ça, tous les membres de tous les joueurs
## apparaissaient en onglets et n'importe qui pouvait dépenser SES ₽ sur
## le Pokémon d'un AUTRE joueur (retour joueurs). remote_peer == 0 = copie
## locale qui nous appartient (cf. TeamMember, même schéma que le HUD).
func _own_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _team.size():
		var m = _team[i]
		if not is_instance_valid(m):
			continue
		if Net.in_run and "remote_peer" in m and m.remote_peer != 0:
			continue
		out.append(i)
	return out


func _build_attack_scroll() -> void:
	UiKit.banner(_panel, "Améliorations et Boutique" if _kind == "vendor" else "Nouvelle Attaque")
	if _kind == "vendor":
		UiKit.label(_panel, "Bourse : %d ₽    Baies : %d ◆" % [GameManager.run_money, GameManager.gold],
			Vector2(0, 62), 15, UiKit.GOLD, 880, HORIZONTAL_ALIGNMENT_CENTER)

	# Onglets Pokémon RICHES (portrait + nom + niveau + type) — le contenu
	# change dès que le FOCUS arrive sur l'onglet (flèches) : plus besoin
	# d'appuyer sur Entrée pour comparer les Pokémon. Restreints à NOS
	# PROPRES Pokémon en multijoueur (cf. _own_indices).
	var own := _own_indices()
	if _sel_member not in own:
		_sel_member = own[0] if not own.is_empty() else 0
	var tab_w := 168.0
	var tabs_x := (880.0 - own.size() * (tab_w + 12.0)) * 0.5
	for oi in own.size():
		var i: int = own[oi]
		var inst: PokemonInstance = _team[i].pokemon_instance
		var sel := i == _sel_member
		var tab := Button.new()
		tab.position = Vector2(tabs_x + oi * (tab_w + 12.0), 74)
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

	# ── Colonne droite : nouvelles attaques + renforts ────────────────
	UiKit.label(_panel, "APPRENDRE UNE ATTAQUE OU EN RENFORCER UNE",
		Vector2(452, 176), 13, UiKit.CREAM, 400)
	var options: Array = _offers[_sel_member] if _sel_member < _offers.size() else []
	if options.is_empty():
		var empty := UiKit.dark_card(_panel, Vector2(452, 202), Vector2(392, 56))
		UiKit.label(empty, "Rien à apprendre ni renforcer pour ce Pokémon", Vector2(0, 18), 14,
			UiKit.CREAM, 392, HORIZONTAL_ALIGNMENT_CENTER)
	for i in options.size():
		var mv: Dictionary = options[i]
		var y := 202.0 + i * 82.0
		var price := int(mv.get("price", 0))
		var afford: bool = price <= 0 or GameManager.run_money >= price
		var is_upgrade: bool = str(mv.get("kind", "learn")) == "upgrade"
		var ocard := UiKit.card(_panel, Vector2(452, y), Vector2(392, 76), _replace_option == i)
		UiKit.icon_square(ocard, Vector2(10, 14), UiKit.type_sym(str(mv.get("type", ""))), 48.0)
		UiKit.label(ocard, str(mv.get("label", "")), Vector2(68, 7), 17, UiKit.TEXT_DARK, 210)
		UiKit.type_badge(ocard, Vector2(68, 34), str(mv.get("type", "")), 21.0)
		if is_upgrade:
			UiKit.label(ocard, "Puiss. %d → %d%s" % [int(mv.get("power", 0)), int(mv.get("power_after", 0)),
				("  ·  %d ₽" % price) if price > 0 else ""],
				Vector2(152, 38), 13, UiKit.TEXT_DARK.lightened(0.25), 220)
		else:
			UiKit.label(ocard, "Puiss. %d%s  ·  [I] détails" % [int(mv.get("power", 0)),
				("  ·  %d ₽" % price) if price > 0 else ""],
				Vector2(152, 38), 13, UiKit.TEXT_DARK.lightened(0.25), 220)
		var learn := UiKit.button("Renforcer" if is_upgrade else "Apprendre", Vector2(104, 40))
		learn.position = Vector2(392 - 116, 18)
		learn.disabled = not afford
		# [I] sur le bouton (focalisable) ouvre la fiche complète de l'attaque —
		# on choisit une capacité en run sans la connaître par cœur (retour
		# joueurs). Même geste que dans le Pokédex. Pas de fiche pour un
		# renforcement : c'est la MÊME attaque, déjà connue.
		if not is_upgrade:
			var mv_capture := mv
			learn.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventKey and (ev as InputEventKey).pressed \
						and (ev as InputEventKey).keycode == KEY_I:
					_open_move_info(mv_capture)
					get_viewport().set_input_as_handled())
		var oi := i; var mi := _sel_member
		if is_upgrade:
			learn.pressed.connect(func() -> void: upgrade_move.emit(mi, oi))
		else:
			learn.pressed.connect(func() -> void:
				if _team[mi].pokemon_instance.equipped_moves.size() < GameManager.move_slot_count:
					learn_move.emit(mi, oi, -1)      # slot libre : direct
				else:
					_replace_option = oi              # sinon : choisir quoi remplacer
					_rebuild())
		ocard.add_child(learn)

	# ── Boutique du bas (vendeur uniquement) : Baies & CS / Potions ───
	if _kind == "vendor":
		var tab_baies := Button.new()
		tab_baies.text     = "⭐ Baies & CS"
		tab_baies.position = Vector2(272, 458)
		tab_baies.size     = Vector2(160, 30)
		tab_baies.add_theme_stylebox_override("normal",
			UiKit.style(UiKit.TAN if _shop_tab == "baies" else UiKit.BROWN_CARD, UiKit.WOOD_EDGE, 8, 3))
		tab_baies.add_theme_stylebox_override("hover", tab_baies.get_theme_stylebox("normal"))
		tab_baies.add_theme_stylebox_override("pressed", tab_baies.get_theme_stylebox("normal"))
		tab_baies.pressed.connect(func() -> void: _shop_tab = "baies"; _rebuild())
		_panel.add_child(tab_baies)

		var tab_soins := Button.new()
		tab_soins.text     = "🧪 Potions & Rappels"
		tab_soins.position = Vector2(444, 458)
		tab_soins.size     = Vector2(180, 30)
		tab_soins.add_theme_stylebox_override("normal",
			UiKit.style(UiKit.TAN if _shop_tab == "soins" else UiKit.BROWN_CARD, UiKit.WOOD_EDGE, 8, 3))
		tab_soins.add_theme_stylebox_override("hover", tab_soins.get_theme_stylebox("normal"))
		tab_soins.add_theme_stylebox_override("pressed", tab_soins.get_theme_stylebox("normal"))
		tab_soins.pressed.connect(func() -> void: _shop_tab = "soins"; _rebuild())
		_panel.add_child(tab_soins)

		if _shop_tab == "baies":
			_build_shop_baies()
		else:
			_build_shop_soins()

	_add_continue(578)


func _build_shop_baies() -> void:
	for i in BERRY_PACKS.size():
		var pack: Dictionary = BERRY_PACKS[i]
		var bx := 36.0 + i * 140.0
		var bcard := UiKit.card(_panel, Vector2(bx, 494), Vector2(130, 76))
		UiKit.label(bcard, "◆ %d Baies" % int(pack["amount"]), Vector2(8, 6), 14, UiKit.TEXT_DARK, 120)
		var bb := UiKit.button("%d ₽" % int(pack["price"]), Vector2(96, 30))
		bb.position = Vector2(17, 36)
		bb.disabled = GameManager.run_money < int(pack["price"])
		var pr := int(pack["price"]); var am := int(pack["amount"])
		bb.pressed.connect(func() -> void: buy_berries.emit(pr, am))
		bcard.add_child(bb)
	var cs_list: Array = GameManager.CS_CATALOG
	for i in cs_list.size():
		var cs: Dictionary = cs_list[i]
		var cx := 460.0 + i * 132.0
		var ccard := UiKit.card(_panel, Vector2(cx, 494), Vector2(122, 76))
		UiKit.label(ccard, "%s %s" % [cs.get("sym", ""), cs.get("name", "")],
			Vector2(6, 6), 13, UiKit.TEXT_DARK, 116)
		if GameManager.owns_cs(cs["id"]):
			UiKit.label(ccard, "✓ Obtenue", Vector2(6, 42), 13, UiKit.GREEN_DARK, 110)
		else:
			var cb := UiKit.button("%d ₽" % int(cs["price"]), Vector2(92, 30))
			cb.position = Vector2(15, 36)
			cb.disabled = GameManager.run_money < int(cs["price"])
			var cid: String = cs["id"]
			cb.pressed.connect(func() -> void: buy_cs.emit(cid))
			ccard.add_child(cb)


## Potions/rappels — s'appliquent au Pokémon dont l'onglet est sélectionné
## en haut de l'écran (_sel_member). Un Rappel n'est utilisable QUE sur un
## membre K.O. ; une Potion seulement sur un membre vivant (pas à 100% PV).
func _build_shop_soins() -> void:
	if _team.is_empty():
		return
	var target: PokemonInstance = _team[_sel_member].pokemon_instance
	UiKit.label(_panel, "Sur %s (onglet ci-dessus)" % target.data.name_fr.capitalize(),
		Vector2(0, 494), 13, UiKit.CREAM.darkened(0.1), 880, HORIZONTAL_ALIGNMENT_CENTER)
	var cw := 134.0
	for i in HEAL_ITEMS.size():
		var item: Dictionary = HEAL_ITEMS[i]
		var ix := 36.0 + i * (cw + 6.0)
		var icard := UiKit.card(_panel, Vector2(ix, 514), Vector2(cw, 76))
		var icon := _item_icon(str(item["icon"]))
		if icon != null:
			var tex := TextureRect.new()
			tex.texture         = icon
			tex.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.expand_mode     = TextureRect.EXPAND_IGNORE_SIZE
			tex.texture_filter  = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.mouse_filter    = Control.MOUSE_FILTER_IGNORE
			tex.position        = Vector2(4, 2)
			tex.size             = Vector2(28, 28)
			icard.add_child(tex)
		UiKit.label(icard, str(item["name"]), Vector2(34, 4), 12, UiKit.TEXT_DARK, cw - 38)

		var is_revive: bool = item.get("revive", false)
		var eligible := is_revive == target.is_fainted() and not (not is_revive and target.hp_ratio() >= 1.0)
		var price := int(item["price"])
		var can_afford := GameManager.run_money >= price
		var btn := UiKit.button("%d ₽" % price, Vector2(cw - 16, 30))
		btn.position = Vector2(8, 40)
		btn.disabled = not eligible or not can_afford
		# Un bouton désactivé ne déclenche jamais "pressed" — sans ce message,
		# le clic ne fait rien et ça se lit comme un bug ("l'effet ne s'est
		# pas déclenché"). On explique toujours pourquoi.
		if not eligible:
			btn.tooltip_text = ("%s est K.O. — un Rappel est nécessaire." % target.data.name_fr.capitalize()) \
				if is_revive and not target.is_fainted() else \
				("Utilisable seulement sur un Pokémon K.O." if is_revive else "Déjà à 100% PV.")
		elif not can_afford:
			btn.tooltip_text = "Pas assez de Pokédollars ₽."
		var mi := _sel_member; var iid: String = item["id"]
		btn.pressed.connect(func() -> void: buy_potion.emit(mi, iid))
		icard.add_child(btn)


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
