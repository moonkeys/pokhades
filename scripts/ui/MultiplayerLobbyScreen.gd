class_name MultiplayerLobbyScreen
extends CanvasLayer

## Lobby multijoueur (jusqu'à 6) — héberger ou rejoindre par code, choisir
## son Pokémon parmi les débloqués (starters + Pokédex), se déclarer prêt.
## L'hôte lance la partie quand tout le monde est prêt. Style calqué sur
## ShopScreen (palette parchemin).

signal closed

const C_BG      := Color(0.04, 0.03, 0.02, 0.82)
const C_PANEL   := Color(0.10, 0.075, 0.045, 0.96)
const C_BORDER  := Color(0.62, 0.50, 0.32)
const C_TEXT    := Color(0.96, 0.92, 0.80)
const C_DIM     := Color(0.62, 0.55, 0.42)
const C_GOLD    := Color(0.92, 0.72, 0.25)
const C_GOLD_LT := Color(0.94, 0.88, 0.72)
const C_OK      := Color(0.38, 0.82, 0.45)
const C_ERR     := Color(0.80, 0.20, 0.20)

var _panel:       Panel = null
var _mode:        String = "menu"   # menu | lobby
var _my_pid:      int  = 0
var _my_item:     String = ""       # api du catalogue, "" = aucun
var _my_ready:    bool = false
var _name_cache:  Dictionary = {}   # pid → nom FR
var _status_lbl:  Label = null
var _code_input:  LineEdit = null


func _ready() -> void:
	layer = 30
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
		_resolve_name(pid)
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
	_panel = Panel.new()
	_panel.position = Vector2(140, 30)
	_panel.size     = Vector2(1000, 660)
	_style(_panel, C_PANEL, C_BORDER, 14)
	add_child(_panel)

	var hdr := Panel.new()
	hdr.size = Vector2(1000, 64)
	_style_color(hdr, Color(0.24, 0.18, 0.08), 14)
	_panel.add_child(hdr)
	_panel.add_child(_lbl("⚔  MULTIJOUEUR", 24, 12, 500, 40, 22, C_GOLD_LT))

	var close := Button.new()
	close.text = "✕  Quitter"
	close.position = Vector2(24, 600)
	close.size     = Vector2(170, 42)
	close.add_theme_font_size_override("font_size", 15)
	_btn_neutral(close)
	close.pressed.connect(func() -> void:
		Net.reset()
		closed.emit()
	)
	_panel.add_child(close)

	_status_lbl = _lbl("", 220, 604, 560, 34, 14, C_OK, true)
	_panel.add_child(_status_lbl)

	if _mode == "menu":
		_build_menu()
	else:
		_build_lobby()


# ── Menu : héberger / rejoindre ────────────────────────────────────────

func _build_menu() -> void:
	_panel.add_child(_lbl("Jouez jusqu'à 6 — l'hôte partage son code de partie.",
		0, 100, 1000, 30, 16, C_DIM, true))

	var host_btn := Button.new()
	host_btn.text = "⚑  Héberger une partie"
	host_btn.position = Vector2(300, 180)
	host_btn.size     = Vector2(400, 64)
	host_btn.add_theme_font_size_override("font_size", 20)
	_btn_gold(host_btn)
	host_btn.pressed.connect(func() -> void:
		if Net.host_game(_player_name()) == OK:
			_mode = "lobby"
			_rebuild()
		else:
			_set_status("Impossible d'ouvrir le serveur (port occupé ?).", false)
	)
	_panel.add_child(host_btn)

	_panel.add_child(_lbl("— ou —", 0, 270, 1000, 26, 15, C_DIM, true))

	_code_input = LineEdit.new()
	_code_input.placeholder_text = "CODE DE PARTIE"
	_code_input.position  = Vector2(300, 320)
	_code_input.size      = Vector2(250, 54)
	_code_input.max_length = 7
	_code_input.add_theme_font_size_override("font_size", 20)
	_panel.add_child(_code_input)

	var join_btn := Button.new()
	join_btn.text = "➜  Rejoindre"
	join_btn.position = Vector2(566, 320)
	join_btn.size     = Vector2(134, 54)
	join_btn.add_theme_font_size_override("font_size", 16)
	_btn_gold(join_btn)
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


# ── Lobby : roster + choix Pokémon + prêt ──────────────────────────────

func _build_lobby() -> void:
	# Code de partie (hôte) — deux codes distincts pour éviter la confusion
	# LAN/Internet (cf. Net.join_code / Net.join_code_public) : un joueur du
	# MÊME réseau doit utiliser le code "réseau local", pas le code Internet
	# (certaines box ne routent pas leur propre IP publique en interne).
	if Net.is_host():
		_panel.add_child(_lbl("Code (même Wi-Fi/réseau) :", 40, 78, 320, 24, 14, C_DIM))
		_panel.add_child(_lbl(Net.join_code, 40, 100, 300, 36, 26, C_GOLD))
		if Net.join_code_public != "" and Net.join_code_public != Net.join_code:
			_panel.add_child(_lbl("Code (Internet, autre réseau) :", 40, 142, 320, 24, 14, C_DIM))
			_panel.add_child(_lbl(Net.join_code_public, 40, 164, 300, 32, 22, C_GOLD))
	else:
		_panel.add_child(_lbl("Connecté — en attente du lancement par l'hôte.",
			40, 92, 500, 28, 14, C_DIM))

	# Roster (droite)
	_panel.add_child(_lbl("Joueurs  (%d/6)" % Net.players.size(), 620, 80, 300, 28, 16, C_TEXT))
	var order := Net.player_order()
	for i in order.size():
		var id: int = order[i]
		var p: Dictionary = Net.players[id]
		var row := Panel.new()
		row.position = Vector2(620, 112 + i * 52)
		row.size     = Vector2(340, 44)
		_style(row, Color(0.16, 0.12, 0.07, 0.95), C_BORDER, 8)
		_panel.add_child(row)
		var who: String = str(p["name"]) + ("  (hôte)" if id == 1 else "")
		row.add_child(_lbl(who, 12, 2, 200, 40, 14, C_TEXT))
		row.add_child(_lbl(_name_cache.get(p["pid"], "#%d" % p["pid"]), 12, 22, 200, 20, 11, C_DIM))
		row.add_child(_lbl("✓ prêt" if p["ready"] else "…", 250, 10, 80, 24, 14,
			C_OK if p["ready"] else C_DIM))

	# Choix du Pokémon (gauche) — verrouillé une fois prêt. Décalé assez bas
	# pour laisser la place aux DEUX codes (LAN + Internet) affichés au-dessus.
	# Pioche dans les débloqués de L'HÔTE (cf. _selectable_pids).
	_panel.add_child(_lbl("Ton Pokémon :", 40, 210, 300, 28, 16, C_TEXT))
	var pids := _selectable_pids()
	var cols := 4
	for i in pids.size():
		var pid: int = pids[i]
		var b := Button.new()
		b.text = _name_cache.get(pid, "#%d" % pid)
		b.position = Vector2(40 + (i % cols) * 135, 244 + (i / cols) * 44)
		b.size     = Vector2(126, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.disabled = _my_ready
		if pid == _my_pid: _btn_gold(b)
		else:              _btn_neutral(b)
		var captured := pid
		b.pressed.connect(func() -> void:
			_my_pid = captured
			Net.set_my_choice(_my_pid, _my_item, _my_ready)
		)
		_panel.add_child(b)
	var grid_rows := ceili(float(pids.size()) / float(cols))
	var grid_bottom := 244.0 + grid_rows * 44.0

	# Objet tenu (optionnel) — piochés dans l'inventaire de L'HÔTE (cf.
	# _selectable_items), même logique que le choix du Pokémon.
	_panel.add_child(_lbl("Objet tenu (optionnel) :", 40, grid_bottom + 10, 320, 24, 14, C_TEXT))
	var item_choices: Array = [""]
	item_choices.append_array(_selectable_items())
	for i in item_choices.size():
		var api: String = item_choices[i]
		var b := Button.new()
		b.text = "Aucun" if api == "" else str(ItemCatalog.get_item(api).get("name_fr", api)).capitalize()
		b.position = Vector2(40 + (i % cols) * 135, grid_bottom + 40 + (i / cols) * 38)
		b.size     = Vector2(126, 32)
		b.add_theme_font_size_override("font_size", 12)
		b.disabled = _my_ready
		if api == _my_item: _btn_gold(b)
		else:                _btn_neutral(b)
		var captured_api := api
		b.pressed.connect(func() -> void:
			_my_item = captured_api
			Net.set_my_choice(_my_pid, _my_item, _my_ready)
		)
		_panel.add_child(b)
	var item_rows := ceili(float(item_choices.size()) / float(cols))
	var content_bottom := grid_bottom + 40 + item_rows * 38 + 20

	# Prêt / lancer
	var action_y := maxf(520.0, content_bottom)
	var ready_btn := Button.new()
	ready_btn.text = "✓  Prêt !" if not _my_ready else "✎  Modifier"
	ready_btn.position = Vector2(40, action_y)
	ready_btn.size     = Vector2(220, 52)
	ready_btn.add_theme_font_size_override("font_size", 17)
	_btn_gold(ready_btn)
	ready_btn.pressed.connect(func() -> void:
		_my_ready = not _my_ready
		Net.set_my_choice(_my_pid, _my_item, _my_ready)
	)
	_panel.add_child(ready_btn)

	if Net.is_host():
		var start := Button.new()
		start.text = "⚔  LANCER LA RUN"
		start.position = Vector2(620, action_y)
		start.size     = Vector2(340, 52)
		start.add_theme_font_size_override("font_size", 18)
		start.disabled = not Net.all_ready()
		_btn_gold(start)
		start.pressed.connect(func() -> void: Net.start_game())
		_panel.add_child(start)
		if not Net.all_ready():
			_panel.add_child(_lbl("Il faut au moins 2 joueurs, tous prêts.",
				620, action_y + 56, 340, 24, 12, C_DIM))


# ── Helpers ────────────────────────────────────────────────────────────

func _resolve_name(pid: int) -> void:
	if _name_cache.has(pid):
		return
	PokemonAPI.get_pokemon(pid, func(data: Dictionary) -> void:
		if data.is_empty() or not is_instance_valid(self):
			return
		_name_cache[pid] = str(data.get("name_fr", "#%d" % pid)).capitalize()
		_rebuild()
	)


func _set_status(msg: String, ok: bool) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color", C_OK if ok else C_ERR)


func _lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y)
	l.size     = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _style(p: Panel, bg: Color, border: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.20); s.shadow_size = 5
	p.add_theme_stylebox_override("panel", s)


func _style_color(p: Panel, bg: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	p.add_theme_stylebox_override("panel", s)


func _btn_gold(btn: Button) -> void:
	var sn := StyleBoxFlat.new()
	sn.bg_color = C_GOLD.lightened(0.15); sn.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sn)
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color = C_GOLD.lightened(0.30)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_color_override("font_color", Color(0.15, 0.11, 0.05))


func _btn_neutral(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.22, 0.18, 0.11); s.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = Color(0.30, 0.25, 0.15)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_color_override("font_color", C_TEXT)
