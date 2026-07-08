class_name MultiplayerLobbyScreen
extends CanvasLayer

## Lobby multijoueur (jusqu'à 6) — héberger ou rejoindre par code, choisir
## son Pokémon (parmi les débloqués DE L'HÔTE) et un objet tenu, se déclarer
## prêt. L'hôte lance la partie quand tout le monde est prêt. Habillage
## UiKit (bois & parchemin) — même langage visuel que tous les autres menus
## (Boutique, Pokédex, etc.).

signal closed

var _panel:       Panel = null
var _mode:        String = "menu"   # menu | lobby
var _my_pid:      int  = 0
var _my_item:     String = ""       # api du catalogue, "" = aucun
var _my_ready:    bool = false
var _status_lbl:  Label = null
var _code_input:  LineEdit = null

## pid → {"name": String, "types": Array, "portrait": Texture2D}
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

	_panel = UiKit.main_panel(Vector2(140, 20), Vector2(1000, 680))
	add_child(_panel)
	UiKit.banner(_panel, "MULTIJOUEUR")

	var close := UiKit.button("✕  Quitter", Vector2(170, 44), false)
	close.position = Vector2(24, 616)
	close.pressed.connect(func() -> void:
		Net.reset()
		closed.emit()
	)
	_panel.add_child(close)

	_status_lbl = UiKit.label(_panel, "", Vector2(220, 626), 14, UiKit.GREEN, 560, HORIZONTAL_ALIGNMENT_CENTER)
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

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


func _player_name() -> String:
	var n := OS.get_environment("USER")
	return n if n != "" else "Dresseur"


# ── Lobby : roster + choix Pokémon + objet + prêt ──────────────────────

func _build_lobby() -> void:
	# Code de partie (hôte) — deux codes distincts pour éviter la confusion
	# LAN/Internet (cf. Net.join_code / Net.join_code_public) : un joueur du
	# MÊME réseau doit utiliser le code "réseau local", pas le code Internet
	# (certaines box ne routent pas leur propre IP publique en interne).
	if Net.is_host():
		UiKit.label(_panel, "Code (même Wi-Fi/réseau) :", Vector2(40, 78), 14, UiKit.CREAM, 320)
		UiKit.label(_panel, Net.join_code, Vector2(40, 100), 26, UiKit.GOLD, 300)
		if Net.join_code_public != "" and Net.join_code_public != Net.join_code:
			UiKit.label(_panel, "Code (Internet, autre réseau) :", Vector2(40, 142), 14, UiKit.CREAM, 320)
			UiKit.label(_panel, Net.join_code_public, Vector2(40, 164), 22, UiKit.GOLD, 300)
	else:
		UiKit.label(_panel, "Connecté — en attente du lancement par l'hôte.",
			Vector2(40, 92), 14, UiKit.CREAM, 500)

	# Roster (droite)
	UiKit.label(_panel, "Joueurs  (%d/6)" % Net.players.size(), Vector2(640, 78), 16, UiKit.CREAM, 300)
	var order := Net.player_order()
	for i in order.size():
		var id: int = order[i]
		var p: Dictionary = Net.players[id]
		var row := UiKit.card(_panel, Vector2(640, 112 + i * 52), Vector2(320, 44))
		var who: String = str(p["name"]) + ("  (hôte)" if id == 1 else "")
		UiKit.label(row, who, Vector2(12, 2), 14, UiKit.TEXT_DARK, 200)
		var pinfo: Dictionary = _data_cache.get(p["pid"], {})
		UiKit.label(row, str(pinfo.get("name", "#%d" % int(p["pid"]))),
			Vector2(12, 22), 11, UiKit.TEXT_DARK.lightened(0.2), 200)
		UiKit.label(row, "✓ prêt" if p["ready"] else "…", Vector2(250, 10), 14,
			UiKit.GREEN_DARK if p["ready"] else UiKit.TEXT_DARK.lightened(0.3), 80)

	# Choix du Pokémon (gauche) : liste défilante (icône + nom + type) +
	# aperçu du Pokémon sélectionné (grand sprite + type) — pioche dans les
	# débloqués de L'HÔTE (cf. _selectable_pids).
	UiKit.label(_panel, "Ton Pokémon :", Vector2(40, 210), 16, UiKit.CREAM, 300)
	var pid_scroll := ScrollContainer.new()
	pid_scroll.position = Vector2(40, 240)
	pid_scroll.size     = Vector2(340, 160)
	pid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(pid_scroll)
	var pid_list := VBoxContainer.new()
	pid_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pid_list.add_theme_constant_override("separation", 6)
	pid_scroll.add_child(pid_list)
	for pid in _selectable_pids():
		pid_list.add_child(_build_pid_row(pid))

	_build_pid_preview(Vector2(400, 240), Vector2(200, 160))

	# Objet tenu (optionnel) — liste défilante, mêmes règles que le Pokémon
	# (piochée dans l'inventaire de L'HÔTE, cf. _selectable_items).
	UiKit.label(_panel, "Objet tenu (optionnel) :", Vector2(40, 414), 14, UiKit.CREAM, 320)
	var item_scroll := ScrollContainer.new()
	item_scroll.position = Vector2(40, 440)
	item_scroll.size     = Vector2(560, 66)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(item_scroll)
	var item_list := VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 6)
	item_scroll.add_child(item_list)
	var item_choices: Array = [""]
	item_choices.append_array(_selectable_items())
	for api in item_choices:
		item_list.add_child(_build_item_row(api))

	# Prêt / lancer
	var action_y := 528.0
	var ready_btn := UiKit.button("✓  Prêt !" if not _my_ready else "✎  Modifier", Vector2(220, 52))
	ready_btn.position = Vector2(40, action_y)
	ready_btn.disabled = _selectable_pids().is_empty()
	ready_btn.pressed.connect(func() -> void:
		_my_ready = not _my_ready
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
	)
	_panel.add_child(ready_btn)

	if Net.is_host():
		var start := UiKit.button("⚔  LANCER LA RUN", Vector2(340, 52))
		start.position = Vector2(640, action_y)
		start.disabled = not Net.all_ready()
		start.pressed.connect(func() -> void: Net.start_game())
		_panel.add_child(start)
		if not Net.all_ready():
			UiKit.label(_panel, "Il faut au moins 2 joueurs, tous prêts.",
				Vector2(640, action_y + 56), 12, UiKit.CREAM, 340)


## Ligne cliquable de la liste défilante des Pokémon (icône PMD + nom +
## pastille de type) — sélection immédiate au clic, même quand verrouillé
## par "Prêt" (désactivée dans ce cas, cf. `disabled`).
func _build_pid_row(pid: int) -> Button:
	var sel := pid == _my_pid
	var row := Button.new()
	row.custom_minimum_size = Vector2(320, 48)
	row.size = Vector2(320, 48)
	row.disabled = _my_ready
	row.add_theme_stylebox_override("normal",
		UiKit.style(UiKit.TAN if sel else UiKit.BROWN_CARD, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 3 if sel else 2))
	row.add_theme_stylebox_override("hover",
		UiKit.style(UiKit.TAN_DARK, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 2))
	row.add_theme_stylebox_override("disabled", row.get_theme_stylebox("normal"))
	row.add_theme_stylebox_override("focus", UiKit.style(UiKit.TAN, UiKit.CYAN_SEL, 8, 3))
	UiKit.juice(row)

	var data: Dictionary = _data_cache.get(pid, {})
	var portrait: Texture2D = data.get("portrait", null)
	if is_instance_valid(portrait):
		var tex := TextureRect.new()
		tex.texture      = portrait
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.position     = Vector2(4, 4)
		tex.size         = Vector2(40, 40)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)

	var name_col := UiKit.TEXT_DARK if sel else UiKit.CREAM
	UiKit.label(row, str(data.get("name", "#%d" % pid)), Vector2(52, 4), 14, name_col, 150)
	var types: Array = data.get("types", [])
	if not types.is_empty():
		UiKit.type_badge(row, Vector2(50, 24), str(types[0]), 18.0)

	row.pressed.connect(func() -> void:
		_my_pid = pid
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
		_rebuild()
	)
	return row


## Aperçu du Pokémon sélectionné — grand sprite + nom + type (cf. demande :
## voir les types ET les sprites quand on sélectionne).
func _build_pid_preview(pos: Vector2, size: Vector2) -> void:
	var card := UiKit.dark_card(_panel, pos, size)
	var data: Dictionary = _data_cache.get(_my_pid, {})
	var portrait: Texture2D = data.get("portrait", null)
	if is_instance_valid(portrait):
		var tex := TextureRect.new()
		tex.texture      = portrait
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.position     = Vector2((size.x - 84) * 0.5, 10)
		tex.size         = Vector2(84, 84)
		card.add_child(tex)
	UiKit.label(card, str(data.get("name", "#%d" % _my_pid)), Vector2(0, 98), 15,
		UiKit.CREAM, size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var types: Array = data.get("types", [])
	if not types.is_empty():
		UiKit.type_badge(card, Vector2((size.x - 64.8) * 0.5, 122), str(types[0]), 18.0)


## Ligne cliquable de la liste défilante des objets tenus (icône + nom).
func _build_item_row(api: String) -> Button:
	var sel := api == _my_item
	var row := Button.new()
	row.custom_minimum_size = Vector2(540, 44)
	row.size = Vector2(540, 44)
	row.disabled = _my_ready
	row.add_theme_stylebox_override("normal",
		UiKit.style(UiKit.TAN if sel else UiKit.BROWN_CARD, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 3 if sel else 2))
	row.add_theme_stylebox_override("hover",
		UiKit.style(UiKit.TAN_DARK, UiKit.CYAN_SEL if sel else UiKit.WOOD_EDGE, 8, 2))
	row.add_theme_stylebox_override("disabled", row.get_theme_stylebox("normal"))
	row.add_theme_stylebox_override("focus", UiKit.style(UiKit.TAN, UiKit.CYAN_SEL, 8, 3))
	UiKit.juice(row)

	var name_col := UiKit.TEXT_DARK if sel else UiKit.CREAM
	if api == "":
		UiKit.label(row, "Aucun", Vector2(12, 4), 14, name_col, 300)
	else:
		var it := ItemCatalog.get_item(api)
		var icon_tex: Texture2D = ItemCatalog.icon(api)
		if is_instance_valid(icon_tex):
			var tex := TextureRect.new()
			tex.texture      = icon_tex
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.position     = Vector2(4, 4)
			tex.size         = Vector2(36, 36)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tex)
		UiKit.label(row, str(it.get("name_fr", api)).capitalize(), Vector2(48, 4), 14, name_col, 300)

	row.pressed.connect(func() -> void:
		_my_item = api
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
		_rebuild()
	)
	return row


# ── Helpers ────────────────────────────────────────────────────────────

## Récupère nom FR + types (PokemonAPI) et portrait (sprite PMD "walk_down",
## même source que les portraits en combat/Boutique) — met à jour l'écran
## dès que chaque donnée arrive (chargement async).
func _resolve_data(pid: int) -> void:
	if _data_cache.has(pid) and _data_cache[pid].has("types"):
		return
	if not _data_cache.has(pid):
		_data_cache[pid] = {}
	PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
		if data.is_empty() or not is_instance_valid(self):
			return
		_data_cache[pid]["name"]  = str(data.get("name_fr", "#%d" % pid)).capitalize()
		_data_cache[pid]["types"] = data.get("types", [])
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


func _set_status(msg: String, ok: bool) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color", UiKit.GREEN if ok else UiKit.RED_SOFT)
