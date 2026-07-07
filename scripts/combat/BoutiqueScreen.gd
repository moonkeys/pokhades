class_name BoutiqueScreen
extends CanvasLayer

## Boutique de run — étal du Perrserker. Trois rayons :
##   • Attaques : on choisit un Pokémon, puis parmi 3 nouvelles attaques
##     compatibles, puis QUELLE attaque actuelle on remplace ;
##   • Baies : échange des Pokédollars ₽ contre des Baies (monnaie persistante).
## CombatArena applique chaque achat (débit ₽ + effet) puis appelle refresh().

signal learn_move(member_index: int, option_index: int, replace_index: int)  # replace_index -1 = ajouter
signal buy_berries(price: int, amount: int)
signal boon_stat(stat_id: String)   # don « stats » : boost choisi appliqué à toute l'équipe
signal closed

## Contexte : "vendor" (Perrserker : attaques payantes + CS + Baies),
## "skill" (don gratuit : seulement le choix d'attaque), "stat" (don gratuit :
## choix d'un boost de stats pour toute l'équipe).
var _kind: String = "vendor"

const STAT_BOONS: Array[Dictionary] = [
	{"id": "boost_atk", "label": "⚔  Attaque +20%",  "col": Color(0.95, 0.50, 0.20)},
	{"id": "boost_def", "label": "🛡  Défense +20%",  "col": Color(0.35, 0.60, 0.95)},
	{"id": "boost_hp",  "label": "♥  PV max +20%",   "col": Color(0.90, 0.35, 0.42)},
	{"id": "boost_spd", "label": "⚡  Vitesse +20%",  "col": Color(0.95, 0.85, 0.25)},
]

const C_BG    := Color(0.06, 0.05, 0.03, 0.93)
const C_CARD  := Color(0.14, 0.11, 0.07, 0.96)
const C_GOLD  := Color(0.88, 0.72, 0.25)
const C_BERRY := Color(0.80, 0.42, 0.55)
const C_TEXT  := Color(0.94, 0.88, 0.72)
const C_DIM   := Color(0.58, 0.50, 0.36)
const C_GOOD  := Color(0.35, 0.85, 0.45)
const C_MOVE  := Color(0.72, 0.55, 0.92)

const BERRY_PACKS: Array[Dictionary] = [
	{"amount": 20,  "price": 60},
	{"amount": 50,  "price": 130},
	{"amount": 120, "price": 280},
]

var _team:   Array = []   # membres vivants
var _offers: Array = []   # _offers[i] = Array (≤3) d'attaques proposées, [] si aucune/consommé
var _root:   Control = null

# Navigation : -1 = parcours (grille de Pokémon) ; sinon index du membre choisi.
var _sel_member: int = -1
var _sel_option: int = -1   # attaque choisie (dans _offers[_sel_member]) ; -1 = pas encore


func setup(team: Array, offers: Array, kind: String = "vendor") -> void:
	layer  = 22
	_team   = team
	_offers = offers
	_kind   = kind
	_sel_member = -1
	_sel_option = -1
	# Navigation clavier : Échap = retour/fermer ; flèches = focus natif.
	add_child(MenuNav.make(_on_cancel_pressed))
	_rebuild()


## Le jeu est en PAUSE tant que l'écran est ouvert — sinon les flèches de
## navigation du menu déplaceraient aussi le Pokémon derrière.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true


func _exit_tree() -> void:
	get_tree().paused = false


## Échap : remonte d'une étape (choix remplacement → choix attaque → parcours),
## sinon ferme l'écran.
func _on_cancel_pressed() -> void:
	if _sel_option >= 0:
		_sel_option = -1
		_rebuild()
	elif _sel_member >= 0:
		_sel_member = -1
		_rebuild()
	else:
		closed.emit()


func refresh() -> void:
	# Après un achat on revient au parcours.
	_sel_member = -1
	_sel_option = -1
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		if c is MenuNav:
			continue   # le gestionnaire clavier survit aux reconstructions
		c.queue_free()
	_root = _bg_panel()

	var header := "🛍  Boutique du Perrserker  🛍"
	if _kind == "skill": header = "★  Don  —  Nouvelle attaque  ★"
	elif _kind == "stat": header = "★  Don  —  Bonus de stats  ★"
	_label(_root, header, Vector2(640, 22), 26, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	if _kind == "vendor":
		_label(_root, "Bourse : %d ₽      Baies : %d ◆" % [GameManager.run_money, GameManager.gold],
			Vector2(640, 58), 17, C_GOLD.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)

	if _kind == "stat":
		_build_stat_boon()
	elif _sel_member < 0:
		_build_browse()
	elif _sel_option < 0:
		_build_pick_attack()
	else:
		_build_pick_replace()

	MenuNav.focus_first(_root)   # flèches → navigation entre les boutons


# ── Phase 1 : parcours (choix du Pokémon + CS + Baies) ─────────────────
func _build_browse() -> void:
	_label(_root, "✦  Apprendre une attaque  —  choisis un Pokémon",
		Vector2(640, 96), 18, C_MOVE, HORIZONTAL_ALIGNMENT_CENTER)

	var n := _team.size()
	var card_w := 220.0
	var card_h := 118.0
	var cols   := mini(maxi(n, 1), 5)
	var gap    := (1280.0 - cols * card_w) / (cols + 1)
	for i in n:
		var col := i % cols
		var row := i / cols
		var cx  := gap + col * (card_w + gap)
		var cy  := 126.0 + row * (card_h + 12)
		_build_member_card(_root, i, Vector2(cx, cy), card_w, card_h)

	# Baies uniquement chez le vendeur (pas dans un don gratuit).
	# Les CS s'achètent désormais au vendeur d'AMÉLIORATIONS du Hub
	# (permanentes, toutes les runs) — plus ici.
	if _kind == "vendor":
		_label(_root, "◆  Baies  —  échange tes Pokédollars",
			Vector2(640, 380), 18, C_BERRY, HORIZONTAL_ALIGNMENT_CENTER)
		var pcard_w := 240.0
		var pgap    := (1280.0 - BERRY_PACKS.size() * pcard_w) / (BERRY_PACKS.size() + 1)
		for i in BERRY_PACKS.size():
			_build_berry_card(_root, BERRY_PACKS[i], Vector2(pgap + i * (pcard_w + pgap), 412), pcard_w, 96)

	_build_continue()


# ── Don « stats » : choix d'un boost pour toute l'équipe ───────────────
func _build_stat_boon() -> void:
	_label(_root, "Choisis un bonus — appliqué à TOUTE l'équipe",
		Vector2(640, 150), 20, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	var n := STAT_BOONS.size()
	var card_w := 260.0
	var gap := (1280.0 - n * card_w) / (n + 1)
	for i in n:
		var boon: Dictionary = STAT_BOONS[i]
		var col: Color = boon["col"]
		var btn := Button.new()
		btn.text = str(boon["label"])
		btn.position = Vector2(gap + i * (card_w + gap), 260)
		btn.size = Vector2(card_w, 120)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", col.lightened(0.3))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.16, 0.13, 0.09); st.border_color = col
		st.set_border_width_all(2); st.set_corner_radius_all(10)
		var sh := st.duplicate() as StyleBoxFlat
		sh.bg_color = Color(0.24, 0.19, 0.13)
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover",  sh)
		btn.add_theme_stylebox_override("pressed", sh)
		var sid: String = boon["id"]
		btn.pressed.connect(func() -> void: boon_stat.emit(sid))
		_root.add_child(btn)
	_build_continue()


func _build_member_card(parent: Node, idx: int, pos: Vector2, w: float, h: float) -> void:
	var inst: PokemonInstance = _team[idx].pokemon_instance
	var options: Array = _offers[idx] if idx < _offers.size() else []
	var available := not options.is_empty()

	var card := Button.new()
	card.position = pos
	card.size     = Vector2(w, h)
	card.disabled = not available
	var st := StyleBoxFlat.new()
	st.bg_color     = C_CARD if available else Color(0.11, 0.09, 0.06, 0.95)
	st.border_color = C_MOVE.darkened(0.2) if available else C_DIM
	st.set_border_width_all(2); st.set_corner_radius_all(8)
	var sh := st.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.20, 0.16, 0.11)
	card.add_theme_stylebox_override("normal", st)
	card.add_theme_stylebox_override("hover",  sh)
	card.add_theme_stylebox_override("pressed", sh)
	card.add_theme_stylebox_override("disabled", st)
	parent.add_child(card)

	if is_instance_valid(inst.portrait_texture):
		var tex := TextureRect.new()
		tex.texture      = inst.portrait_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.position     = Vector2(6, 6); tex.size = Vector2(54, 54)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tex)
	_label(card, inst.data.name_fr.capitalize(), Vector2(66, 10), 15, C_TEXT)
	_label(card, "Niv. %d" % inst.level, Vector2(66, 32), 12, C_DIM)
	_label(card, "✦ %d attaque(s) dispo" % options.size() if available else "— rien de compatible",
		Vector2(10, 84), 12, C_MOVE if available else C_DIM)

	if available:
		var ci := idx
		card.pressed.connect(func() -> void:
			_sel_member = ci; _sel_option = -1; _rebuild())


# ── Phase 2 : choix parmi 3 attaques ───────────────────────────────────
func _build_pick_attack() -> void:
	var inst: PokemonInstance = _team[_sel_member].pokemon_instance
	var options: Array = _offers[_sel_member]
	_label(_root, "%s  —  choisis une attaque à apprendre" % inst.data.name_fr.capitalize(),
		Vector2(640, 110), 20, C_MOVE, HORIZONTAL_ALIGNMENT_CENTER)

	var card_w := 320.0
	var gap    := (1280.0 - options.size() * card_w) / (options.size() + 1)
	for i in options.size():
		_build_attack_option(_root, i, options[i], Vector2(gap + i * (card_w + gap), 200), card_w, 150)

	# Attaques actuelles (aperçu)
	_label(_root, "Attaques actuelles : " + _current_moves_str(inst), Vector2(640, 400), 14, C_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)
	_build_back(func() -> void: _sel_member = -1; _rebuild())
	_build_continue()


func _build_attack_option(parent: Node, i: int, mv: Dictionary, pos: Vector2, w: float, h: float) -> void:
	var price: int = int(mv.get("price", 110))
	var afford := GameManager.run_money >= price
	var card := Button.new()
	card.position = pos; card.size = Vector2(w, h)
	card.disabled = not afford
	var st := StyleBoxFlat.new()
	st.bg_color = C_CARD if afford else Color(0.11, 0.09, 0.06, 0.95)
	st.border_color = C_MOVE if afford else C_DIM
	st.set_border_width_all(2); st.set_corner_radius_all(8)
	var sh := st.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.22, 0.17, 0.12)
	card.add_theme_stylebox_override("normal", st)
	card.add_theme_stylebox_override("hover",  sh)
	card.add_theme_stylebox_override("pressed", sh)
	card.add_theme_stylebox_override("disabled", st)
	parent.add_child(card)

	_label(card, str(mv.get("label", "")), Vector2(14, 16), 20, C_MOVE if afford else C_DIM)
	_label(card, "Type : %s" % String(mv.get("type", "")).capitalize(), Vector2(14, 52), 14, C_TEXT)
	_label(card, "Puissance : %d" % int(mv.get("power", 0)), Vector2(14, 76), 14, C_TEXT)
	_label(card, "%s" % String(mv.get("class", "")).capitalize(), Vector2(14, 100), 12, C_DIM)
	var price_txt := "Gratuit" if price <= 0 else "%d ₽" % price
	_label(card, price_txt, Vector2(w - 116, 108), 18, C_GOOD if price <= 0 else (C_GOLD if afford else C_DIM))

	if afford:
		var ci := i
		card.pressed.connect(func() -> void: _sel_option = ci; _rebuild())


# ── Phase 3 : quelle attaque remplacer ─────────────────────────────────
func _build_pick_replace() -> void:
	var inst: PokemonInstance = _team[_sel_member].pokemon_instance
	var mv: Dictionary = _offers[_sel_member][_sel_option]
	_label(_root, "%s apprend %s" % [inst.data.name_fr.capitalize(), mv.get("label", "")],
		Vector2(640, 120), 20, C_MOVE, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_root, "Quelle attaque remplacer ?", Vector2(640, 156), 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)

	var moves: Array = inst.equipped_moves
	var card_w := 260.0
	var cols := maxi(moves.size(), 1)
	var gap := (1280.0 - cols * card_w) / (cols + 1)
	for i in moves.size():
		var md: MoveData = moves[i]
		var mx := gap + i * (card_w + gap)
		_build_replace_btn(_root, "%s\n(Puiss. %d)" % [md.display_name, md.power], Vector2(mx, 230),
			card_w, 96, i)

	# Emplacement libre seulement si un SLOT DÉBLOQUÉ est vacant (les slots
	# s'achètent au hub, cf. GameManager.move_slot_count) — sinon on ne peut
	# que remplacer une attaque existante.
	if moves.size() < GameManager.move_slot_count:
		_label(_root, "(emplacement libre disponible)", Vector2(640, 344), 13, C_GOOD,
			HORIZONTAL_ALIGNMENT_CENTER)
		_build_replace_btn(_root, "➕  Ajouter\n(ne rien remplacer)", Vector2(510, 370), 260, 70, -1)

	_build_back(func() -> void: _sel_option = -1; _rebuild())


func _build_replace_btn(parent: Node, text: String, pos: Vector2, w: float, h: float, replace_index: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.position = pos; btn.size = Vector2(w, h)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_MOVE)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.18, 0.14, 0.10); st.border_color = C_MOVE
	st.set_border_width_all(2); st.set_corner_radius_all(8)
	var sh := st.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.26, 0.20, 0.14)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover",  sh)
	btn.add_theme_stylebox_override("pressed", sh)
	parent.add_child(btn)
	var mi := _sel_member; var oi := _sel_option; var ri := replace_index
	btn.pressed.connect(func() -> void:
		_sel_member = -1; _sel_option = -1   # retour au parcours après achat
		learn_move.emit(mi, oi, ri))


# ── Cartes CS / Baies (parcours) ───────────────────────────────────────
func _build_berry_card(parent: Node, pack: Dictionary, pos: Vector2, w: float, h: float) -> void:
	var amount: int = int(pack["amount"]); var price: int = int(pack["price"])
	var afford := GameManager.run_money >= price
	var card := Panel.new()
	card.position = pos; card.size = Vector2(w, h)
	var st := StyleBoxFlat.new()
	st.bg_color = C_CARD if afford else Color(0.11, 0.09, 0.06, 0.95)
	st.border_color = C_BERRY if afford else C_DIM
	st.set_border_width_all(2); st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)
	_label(card, "◆  %d Baies" % amount, Vector2(14, 12), 18, C_BERRY if afford else C_DIM)
	_label(card, "%d ₽" % price, Vector2(14, 44), 16, C_GOLD if afford else C_DIM)
	var btn := _small_btn("Échanger", Vector2(w - 116, 56), C_BERRY, afford)
	var cp := price; var ca := amount
	btn.pressed.connect(func() -> void: buy_berries.emit(cp, ca))
	card.add_child(btn)


# ── Helpers ────────────────────────────────────────────────────────────
func _small_btn(text: String, pos: Vector2, col: Color, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = text; btn.position = pos; btn.size = Vector2(104, 28)
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", col if enabled else C_DIM)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.18, 0.15, 0.11); bs.border_color = col if enabled else C_DIM
	bs.set_border_width_all(2); bs.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_stylebox_override("hover",  bs)
	btn.add_theme_stylebox_override("disabled", bs)
	return btn


func _current_moves_str(inst: PokemonInstance) -> String:
	var names: Array[String] = []
	for md: MoveData in inst.equipped_moves:
		names.append("%s (%d)" % [md.display_name, md.power])
	return "  ·  ".join(names)


func _build_back(cb: Callable) -> void:
	var btn := Button.new()
	btn.text = "←  Retour"
	btn.position = Vector2(40, 626); btn.size = Vector2(180, 50)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", C_DIM)
	btn.add_theme_color_override("font_hover_color", C_TEXT)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.15, 0.10); s.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", s)
	btn.pressed.connect(cb)
	_root.add_child(btn)


func _build_continue() -> void:
	var cont := Button.new()
	cont.text     = "Continuer  →"
	cont.position = Vector2(520, 626)
	cont.size     = Vector2(240, 56)
	cont.add_theme_font_size_override("font_size", 22)
	cont.add_theme_color_override("font_color",       C_TEXT)
	cont.add_theme_color_override("font_hover_color", C_GOLD)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.22, 0.17, 0.09); sn.border_color = C_GOLD
	sn.set_border_width_all(2); sn.set_corner_radius_all(12)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.24, 0.12)
	cont.add_theme_stylebox_override("normal", sn)
	cont.add_theme_stylebox_override("hover",  sh)
	cont.add_theme_stylebox_override("pressed", sh)
	cont.pressed.connect(func() -> void: closed.emit())
	_root.add_child(cont)


func _bg_panel() -> Control:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg


func _label(parent: Node, text: String, pos: Vector2,
		font_size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = Vector2(600, 44)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		l.position.x -= 300
		l.size.x      = 1280
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l
