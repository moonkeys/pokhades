class_name MultiplayerLobbyScreen
extends CanvasLayer

## Lobby multijoueur (jusqu'à 6) — héberger ou rejoindre par code, choisir
## son Pokémon (parmi les débloqués DE L'HÔTE), voir ses stats/attaques, et
## un objet tenu, se déclarer prêt. L'hôte lance la partie quand tout le
## monde est prêt. Habillage UiKit (bois & parchemin) — même langage visuel
## que tous les autres menus (Boutique, Pokédex, etc.).

signal closed

const STAT_NAMES:  Array[String] = ["PV", "Attaque", "Défense", "Atq. Spé", "Déf. Spé", "Vitesse"]
const STAT_COLORS: Array[Color] = [
	Color(0.34, 0.69, 0.29),   # PV — vert
	Color(0.82, 0.36, 0.24),   # Attaque — rouge/orangé
	Color(0.90, 0.72, 0.25),   # Défense — or
	Color(0.30, 0.56, 0.90),   # Atq. Spé — bleu
	Color(0.58, 0.42, 0.85),   # Déf. Spé — violet
	Color(0.85, 0.46, 0.66),   # Vitesse — rose
]
const STAT_SCALE := 200.0   # échelle d'affichage des barres (stats de base rarement au-delà)

var _panel:       Panel = null
var _mode:        String = "menu"   # menu | lobby
var _my_pid:      int  = 0
var _my_item:     String = ""       # api du catalogue, "" = aucun
var _my_ready:    bool = false
var _status_lbl:  Label = null
var _code_input:  LineEdit = null

## pid → {"pd": PokemonData, "portrait": Texture2D, "moves": Array (lazy)}
var _data_cache:  Dictionary = {}


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_my_pid = GameManager.selected_starter_id
	Net.players_changed.connect(_rebuild)
	Net.join_failed.connect(func(reason: String) -> void:
		Net.reset()
		_mode = "menu"
		_rebuild()
		_set_status(reason, false)
	)
	Net.server_closed.connect(func() -> void:
		_mode = "menu"
		_rebuild()
		_set_status("L'hôte a quitté la partie.", false)
	)
	for pid in _selectable_pids():
		_resolve_data(pid)
	_rebuild()


## Un invité pioche dans les débloqués de L'HÔTE (cf.
## GameManager.effective_unlocked_pokemon) — pas les siens.
func _selectable_pids() -> Array:
	var out: Array = []
	for pid in GameManager.STARTER_IDS:
		if pid not in out: out.append(pid)
	for pid in GameManager.effective_unlocked_pokemon():
		if pid not in out: out.append(pid)
	return out


## Objets tenus disponibles (copies libres > 0) — mêmes règles hôte/invité.
func _selectable_items() -> Array:
	var out: Array = []
	for api in GameManager.effective_item_inventory():
		if int(GameManager.effective_item_inventory()[api]) > 0:
			out.append(api)
	return out


func _rebuild() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	# Passage automatique menu → lobby dès que le registre nous contient
	if Net.active and Net.players.has(Net.local_id()):
		_mode = "lobby"

	_panel = UiKit.main_panel(Vector2(140, 10), Vector2(1000, 700))
	add_child(_panel)
	UiKit.banner(_panel, "MULTIJOUEUR")

	if _mode == "menu":
		_build_menu()
	else:
		_build_lobby()


# ── Menu : héberger / rejoindre ────────────────────────────────────────

func _build_menu() -> void:
	UiKit.label(_panel, "Jouez jusqu'à 6 — l'hôte partage son code de partie.",
		Vector2(0, 78), 16, UiKit.CREAM, 1000, HORIZONTAL_ALIGNMENT_CENTER)

	var host_btn := UiKit.button("⚑  Héberger une partie", Vector2(400, 64))
	host_btn.position = Vector2(300, 150)
	host_btn.pressed.connect(func() -> void:
		if Net.host_game(_player_name()) == OK:
			_mode = "lobby"
			_rebuild()
		else:
			_set_status("Impossible d'ouvrir le serveur (port occupé ?).", false)
	)
	_panel.add_child(host_btn)

	UiKit.label(_panel, "— ou —", Vector2(0, 234), 15, UiKit.CREAM, 1000, HORIZONTAL_ALIGNMENT_CENTER)

	_code_input = LineEdit.new()
	_code_input.placeholder_text = "CODE DE PARTIE"
	_code_input.position  = Vector2(300, 280)
	_code_input.size      = Vector2(250, 54)
	_code_input.max_length = 7
	_code_input.add_theme_font_size_override("font_size", 20)
	_panel.add_child(_code_input)

	var join_btn := UiKit.button("➜  Rejoindre", Vector2(134, 54))
	join_btn.position = Vector2(566, 280)
	join_btn.pressed.connect(func() -> void:
		if _code_input.text.strip_edges().length() != 7:
			_set_status("Le code fait 7 caractères.", false)
			return
		_set_status("Connexion…", true)
		Net.join_game(_code_input.text, _player_name())
	)
	_panel.add_child(join_btn)

	var back := UiKit.button("✕  Retour", Vector2(170, 44), false)
	back.position = Vector2(40, 632)
	back.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(back)

	_status_lbl = UiKit.label(_panel, "", Vector2(220, 642), 14, UiKit.GREEN, 560, HORIZONTAL_ALIGNMENT_CENTER)
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _player_name() -> String:
	var n := OS.get_environment("USER")
	return n if n != "" else "Dresseur"


# ── Lobby : roster + choix Pokémon + stats/attaques + objet + prêt ─────

func _build_lobby() -> void:
	# Bandeau du haut : code de partie ET sprite du Pokémon choisi, aux deux
	# bouts de la même carte (mise en page "space-between", cf. demande).
	var top_card := UiKit.dark_card(_panel, Vector2(40, 68), Vector2(596, 84))
	if Net.is_host():
		UiKit.label(top_card, "Code (Wi-Fi/réseau) :", Vector2(12, 6), 12, UiKit.CREAM, 260)
		UiKit.label(top_card, Net.join_code, Vector2(12, 24), 20, UiKit.GOLD, 260)
		if Net.join_code_public != "" and Net.join_code_public != Net.join_code:
			UiKit.label(top_card, "Code (Internet) : %s" % Net.join_code_public, Vector2(12, 54), 11, UiKit.CREAM, 260)
	else:
		UiKit.label(top_card, "Connecté — en attente du lancement par l'hôte.",
			Vector2(12, 30), 13, UiKit.CREAM, 380)
	var top_portrait: Texture2D = _data_cache.get(_my_pid, {}).get("portrait", null)
	if is_instance_valid(top_portrait):
		var top_tex := TextureRect.new()
		top_tex.texture      = top_portrait
		top_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top_tex.position     = Vector2(596 - 76, 10)
		top_tex.size         = Vector2(64, 64)
		top_card.add_child(top_tex)

	# Roster — liste défilante (peut monter à 6) pour ne pas prendre trop de
	# place au-dessus du reste de l'écran.
	UiKit.label(_panel, "Joueurs  (%d/6)" % Net.players.size(), Vector2(660, 70), 15, UiKit.CREAM, 300)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.position = Vector2(660, 94)
	roster_scroll.size     = Vector2(300, 110)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(roster_scroll)
	var roster_list := VBoxContainer.new()
	roster_list.add_theme_constant_override("separation", 6)
	roster_scroll.add_child(roster_list)
	for id: int in Net.player_order():
		var p: Dictionary = Net.players[id]
		var row := Panel.new()
		row.custom_minimum_size = Vector2(280, 48)
		row.add_theme_stylebox_override("panel", UiKit.style(UiKit.TAN, UiKit.WOOD_EDGE, 8, 3))
		var pinfo: Dictionary = _data_cache.get(int(p["pid"]), {})
		var pd_r: PokemonData = pinfo.get("pd", null)
		var portrait_r: Texture2D = pinfo.get("portrait", null)
		if is_instance_valid(portrait_r):
			var ptex_r := TextureRect.new()
			ptex_r.texture      = portrait_r
			ptex_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ptex_r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ptex_r.position     = Vector2(4, 4)
			ptex_r.size         = Vector2(40, 40)
			row.add_child(ptex_r)
		var who: String = str(p["name"]) + ("  (hôte)" if id == 1 else "")
		UiKit.label(row, who, Vector2(50, 4), 14, UiKit.TEXT_DARK, 150)
		UiKit.label(row, pd_r.name_fr.capitalize() if pd_r else "#%d" % int(p["pid"]),
			Vector2(50, 24), 12, UiKit.TEXT_DARK.lightened(0.2), 150)
		UiKit.label(row, "✓ prêt" if p["ready"] else "…", Vector2(224, 14), 14,
			UiKit.GREEN_DARK if p["ready"] else UiKit.TEXT_DARK.lightened(0.3), 60)
		roster_list.add_child(row)

	# Colonne 1 — choix du Pokémon : grille à DEUX COLONNES prenant TOUTE la
	# largeur disponible (icône + nom + type), pioche dans les débloqués de
	# L'HÔTE (cf. _selectable_pids). Plus d'aperçu séparé à côté — le sprite
	# est déjà visible sur chaque case ET dans le bandeau du haut.
	UiKit.label(_panel, "Ton Pokémon :", Vector2(40, 170), 15, UiKit.CREAM, 260)
	var pid_scroll := ScrollContainer.new()
	pid_scroll.position = Vector2(40, 196)
	pid_scroll.size     = Vector2(596, 300)
	pid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(pid_scroll)
	var pid_grid := GridContainer.new()
	pid_grid.columns = 2
	pid_grid.add_theme_constant_override("h_separation", 6)
	pid_grid.add_theme_constant_override("v_separation", 6)
	pid_scroll.add_child(pid_grid)
	for pid in _selectable_pids():
		pid_grid.add_child(_build_pid_row(pid))

	# Colonne 2 — statistiques ET attaques (lui + ses évolutions), dans le
	# MÊME conteneur (cf. demande utilisateur).
	_build_stats_and_moves_panel(Vector2(662, 170), Vector2(298, 420))

	# Objet tenu (optionnel) — grille d'icônes défilante horizontalement,
	# piochée dans l'inventaire de L'HÔTE (cf. _selectable_items).
	UiKit.label(_panel, "Objet tenu (optionnel) :", Vector2(40, 522), 14, UiKit.CREAM, 320)
	var item_scroll := ScrollContainer.new()
	item_scroll.position = Vector2(40, 546)
	item_scroll.size     = Vector2(920, 56)
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(item_scroll)
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 8)
	item_scroll.add_child(item_row)
	var item_choices: Array = [""]
	item_choices.append_array(_selectable_items())
	for api in item_choices:
		item_row.add_child(_build_item_icon(api))

	# Quitter (gauche) / Prêt + Lancer (droite, cf. demande de mise en page)
	var quit_btn := UiKit.button("✕  Quitter", Vector2(170, 48), false)
	quit_btn.position = Vector2(40, 630)
	quit_btn.pressed.connect(func() -> void:
		Net.reset()
		closed.emit()
	)
	_panel.add_child(quit_btn)

	_status_lbl = UiKit.label(_panel, "", Vector2(230, 642), 13, UiKit.GREEN, 380)
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ready_btn := UiKit.button("✓  Prêt !" if not _my_ready else "✎  Modifier", Vector2(298, 46))
	ready_btn.position = Vector2(662, 600)
	ready_btn.disabled = _selectable_pids().is_empty()
	ready_btn.pressed.connect(func() -> void:
		_my_ready = not _my_ready
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
	)
	_panel.add_child(ready_btn)

	if Net.is_host():
		var start := UiKit.button("⚔  LANCER LA RUN", Vector2(298, 46))
		start.position = Vector2(662, 652)
		start.disabled = not Net.all_ready()
		if not Net.all_ready():
			start.tooltip_text = "Il faut au moins 2 joueurs, tous prêts."
		start.pressed.connect(func() -> void: Net.start_game())
		_panel.add_child(start)


## Case cliquable de la grille à 2 colonnes des Pokémon (icône PMD + nom +
## pastille de type) — sélection immédiate au clic, même quand verrouillé
## par "Prêt" (désactivée dans ce cas, cf. `disabled`).
func _build_pid_row(pid: int) -> Button:
	var sel := pid == _my_pid
	var row := Button.new()
	row.custom_minimum_size = Vector2(292, 68)
	row.disabled = _my_ready
	row.add_theme_stylebox_override("normal",
		UiKit.style(UiKit.TAN if sel else UiKit.BROWN_CARD, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 3 if sel else 2))
	row.add_theme_stylebox_override("hover",
		UiKit.style(UiKit.TAN_DARK, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 2))
	row.add_theme_stylebox_override("disabled", row.get_theme_stylebox("normal"))
	row.add_theme_stylebox_override("focus", UiKit.style(UiKit.TAN, UiKit.CYAN_SEL, 8, 3))
	UiKit.juice(row)

	var data: Dictionary = _data_cache.get(pid, {})
	var pd: PokemonData  = data.get("pd", null)
	var portrait: Texture2D = data.get("portrait", null)
	if is_instance_valid(portrait):
		var tex := TextureRect.new()
		tex.texture      = portrait
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.position     = Vector2(6, 6)
		tex.size         = Vector2(52, 52)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)

	var name_col := UiKit.TEXT_DARK if sel else UiKit.CREAM
	UiKit.label(row, pd.name_fr.capitalize() if pd else "#%d" % pid, Vector2(66, 10), 14, name_col, 200)
	if pd and not pd.types.is_empty():
		UiKit.type_badge(row, Vector2(66, 34), str(pd.types[0]), 18.0)

	row.pressed.connect(func() -> void:
		_my_pid = pid
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
		_rebuild()
	)
	return row


func _build_hint_row(text: String, w: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(w, 40)
	row.add_theme_stylebox_override("panel", UiKit.style(UiKit.BROWN_CARD.darkened(0.1), UiKit.WOOD_EDGE, 8, 2))
	UiKit.label(row, text, Vector2(8, 10), 12, UiKit.CREAM.darkened(0.15), w - 16)
	return row


## Encart UNIQUE stats + attaques (même conteneur, cf. demande utilisateur) :
## barres de statistiques de base en haut, puis la liste des attaques
## apprenables (lui ET ses évolutions, cf. _resolve_moves) en grille à 2
## colonnes juste en dessous — nom, type, puissance, ATT (physique) / ASP
## (spéciale), triées de la moins à la plus puissante.
func _build_stats_and_moves_panel(pos: Vector2, size: Vector2) -> void:
	var card := UiKit.dark_card(_panel, pos, size)
	UiKit.label(card, "Statistiques de base", Vector2(10, 8), 14, UiKit.CREAM, size.x - 20)

	var data: Dictionary = _data_cache.get(_my_pid, {})
	var pd: PokemonData  = data.get("pd", null)
	var stats_bottom := 34.0
	if pd == null:
		UiKit.label(card, "Chargement…", Vector2(10, 34), 12, UiKit.CREAM.darkened(0.15), size.x - 20)
		stats_bottom = 60.0
	else:
		var vals: Array = [pd.hp, pd.attack, pd.defense, pd.sp_attack, pd.sp_defense, pd.speed]
		var y := 34.0
		for i in 6:
			UiKit.label(card, STAT_NAMES[i], Vector2(10, y), 11, UiKit.CREAM, 74)
			_draw_stat_bar(card, Vector2(88, y + 2), size.x - 126, 12, float(vals[i]) / STAT_SCALE, STAT_COLORS[i])
			UiKit.label(card, str(vals[i]), Vector2(size.x - 34, y), 11, UiKit.CREAM, 32)
			y += 23.0
		stats_bottom = y + 4.0

	UiKit.label(card, "Attaques (avec évolutions)", Vector2(10, stats_bottom), 13, UiKit.GOLD, size.x - 20)
	var moves_top := stats_bottom + 22.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, moves_top)
	scroll.size     = Vector2(size.x - 16, size.y - moves_top - 8)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	var cell_w := (size.x - 16.0 - 4.0) * 0.5
	if data.has("moves"):
		var moves: Array = data["moves"]
		if moves.is_empty():
			grid.add_child(_build_hint_row("Aucune attaque offensive connue.", size.x - 16))
		else:
			for mv: Dictionary in moves:
				grid.add_child(_build_move_cell(mv, cell_w))
	else:
		grid.add_child(_build_hint_row("Chargement…", size.x - 16))
		_resolve_moves(_my_pid)


## Case de la grille d'attaques : nom, type, puissance, ATT/ASP.
func _build_move_cell(mv: Dictionary, w: float) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(w, 56)
	row.add_theme_stylebox_override("panel", UiKit.style(UiKit.BROWN_CARD, UiKit.WOOD_EDGE, 8, 2))
	UiKit.label(row, str(mv.get("name", "?")), Vector2(6, 3), 12, UiKit.CREAM, w - 12)
	UiKit.type_badge(row, Vector2(6, 22), str(mv.get("type", "")), 14.0)
	var physical: bool = str(mv.get("class", "physical")) == "physical"
	UiKit.label(row, "Pui. %d" % int(mv.get("power", 0)), Vector2(6, 40), 11, UiKit.CREAM.darkened(0.1), 60)
	UiKit.label(row, "ATT" if physical else "ASP", Vector2(w - 40, 40), 11,
		Color(0.85, 0.5, 0.3) if physical else Color(0.4, 0.65, 0.95), 34)
	return row


func _draw_stat_bar(parent: Control, pos: Vector2, w: float, h: float, ratio: float, col: Color) -> void:
	var bg := ColorRect.new()
	bg.color    = Color(0.14, 0.10, 0.06)
	bg.position = pos
	bg.size     = Vector2(w, h)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color    = col
	fill.position = pos + Vector2(1, 1)
	fill.size     = Vector2(maxf(0.0, (w - 2) * clampf(ratio, 0.0, 1.0)), h - 2)
	parent.add_child(fill)


## Icône cliquable d'objet tenu (grille compacte, cf. demande utilisateur).
func _build_item_icon(api: String) -> Button:
	var sel := api == _my_item
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(60, 56)
	btn.disabled = _my_ready
	btn.add_theme_stylebox_override("normal",
		UiKit.style(UiKit.TAN if sel else UiKit.BROWN_CARD, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 3 if sel else 2))
	btn.add_theme_stylebox_override("hover",
		UiKit.style(UiKit.TAN_DARK, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 2))
	btn.add_theme_stylebox_override("disabled", btn.get_theme_stylebox("normal"))
	btn.add_theme_stylebox_override("focus", UiKit.style(UiKit.TAN, UiKit.CYAN_SEL, 8, 3))
	UiKit.juice(btn)

	if api == "":
		btn.tooltip_text = "Aucun objet"
		var l := Label.new()
		l.text = "✕"
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 20)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(l)
	else:
		var it := ItemCatalog.get_item(api)
		btn.tooltip_text = str(it.get("name_fr", api)).capitalize()
		var icon_tex: Texture2D = ItemCatalog.icon(api)
		if is_instance_valid(icon_tex):
			var tex := TextureRect.new()
			tex.texture      = icon_tex
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.position     = Vector2(12, 4)
			tex.size         = Vector2(36, 36)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(tex)

	btn.pressed.connect(func() -> void:
		_my_item = api
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
		_rebuild()
	)
	return btn


# ── Helpers ────────────────────────────────────────────────────────────

## Récupère espèce (nom/types/stats/movepool) + portrait (sprite PMD
## "walk_down", même source que les portraits en combat/Boutique). Met à
## jour l'écran dès que chaque donnée arrive (chargement async).
func _resolve_data(pid: int) -> void:
	if _data_cache.has(pid) and _data_cache[pid].has("pd"):
		return
	if not _data_cache.has(pid):
		_data_cache[pid] = {}
	PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
		if data.is_empty() or not is_instance_valid(self):
			return
		_data_cache[pid]["pd"] = PokemonData.from_api(data)
		_rebuild()
	)
	PMDSprites.get_walk_sprites(pid, self, func(result: Dictionary) -> void:
		if result.is_empty() or not is_instance_valid(self):
			return
		var frames: SpriteFrames = result.frames
		if frames.has_animation("walk_down"):
			_data_cache[pid]["portrait"] = frames.get_frame_texture("walk_down", 0)
			_rebuild()
	)


## Charge un aperçu des attaques offensives (power > 0) du Pokémon
## SÉLECTIONNÉ uniquement (pas tous les débloqués — trop d'appels API pour
## un simple aperçu) — mais couvre TOUTE SA CHAÎNE D'ÉVOLUTION (les attaques
## qu'il pourra apprendre en évoluant, cf. demande utilisateur), triées de
## la moins à la plus puissante.
func _resolve_moves(pid: int) -> void:
	if _data_cache.get(pid, {}).has("moves"):
		return
	var base := GameManager.base_species_of(pid)
	var chain: Array = [base]
	var cur := base
	while GameManager.EVOLUTIONS.has(cur):
		cur = int(GameManager.EVOLUTIONS[cur]["evolves_to"])
		chain.append(cur)
	_fetch_chain_species(pid, chain, 0)


## Récupère (si besoin) les PokemonData de chaque maillon de la chaîne
## d'évolution, un par un (chaînes courtes, pas besoin de paralléliser),
## puis rassemble leurs movepools respectifs.
func _fetch_chain_species(pid: int, chain: Array, idx: int) -> void:
	if idx >= chain.size():
		_collect_chain_moves(pid, chain)
		return
	var stage: int = chain[idx]
	if _data_cache.has(stage) and _data_cache[stage].has("pd"):
		_fetch_chain_species(pid, chain, idx + 1)
		return
	PokemonAPI.get_pokemon(stage, func(data: Dictionary) -> void:
		if not is_instance_valid(self):
			return
		if not _data_cache.has(stage):
			_data_cache[stage] = {}
		if not data.is_empty():
			_data_cache[stage]["pd"] = PokemonData.from_api(data)
		_fetch_chain_species(pid, chain, idx + 1)
	)


func _collect_chain_moves(pid: int, chain: Array) -> void:
	var names: Array = []
	for stage: int in chain:
		var spd: PokemonData = _data_cache.get(stage, {}).get("pd", null)
		if spd == null:
			continue
		for entry: Dictionary in spd.level_up_moves:
			var nm: String = str(entry.get("name", ""))
			if nm != "" and nm not in names:
				names.append(nm)
	if names.is_empty():
		_data_cache[pid]["moves"] = []
		if pid == _my_pid:
			_rebuild()
		return
	names = names.slice(0, mini(names.size(), 24))

	var collected: Array = []
	var remaining := [names.size()]
	for nm in names:
		PokemonAPI.get_move(nm, func(move_data: Dictionary) -> void:
			if not is_instance_valid(self):
				return
			remaining[0] -= 1
			var power_v: Variant = move_data.get("power")
			var power: int = int(power_v) if power_v != null else 0
			if power > 0 and not move_data.is_empty():
				var fr: String = move_data.get("name_fr", "")
				collected.append({
					"name":  fr if fr != "" else str(nm).replace("-", " ").capitalize(),
					"type":  move_data.get("type", "normal"),
					"power": power,
					"class": move_data.get("damage_class", "physical"),
				})
			if remaining[0] <= 0:
				collected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return int(a["power"]) < int(b["power"]))
				_data_cache[pid]["moves"] = collected
				if pid == _my_pid:
					_rebuild()
		)


func _set_status(msg: String, ok: bool) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color", UiKit.GREEN if ok else UiKit.RED_SOFT)
