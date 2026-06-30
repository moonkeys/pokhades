extends Node2D

# ── PNJ (pokemon_id → sprite PMD chargé async) ───────────────────────
const NPC_DEFS: Array[Dictionary] = [
	{"id": "start",    "pid": 149, "pos": Vector2(640, 175),  "accent": Color(0.85, 0.38, 0.10)},  # Dragonite
	{"id": "shop",     "pid": 113, "pos": Vector2(215, 388),  "accent": Color(0.92, 0.60, 0.72)},  # Chansey
	{"id": "team",     "pid": 68,  "pos": Vector2(1065, 388), "accent": Color(0.88, 0.35, 0.28)},  # Machamp
	{"id": "pokedex",  "pid": 137, "pos": Vector2(215, 558),  "accent": Color(0.40, 0.58, 0.95)},  # Porygon
	{"id": "upgrades", "pid": 65,  "pos": Vector2(1065, 558), "accent": Color(0.68, 0.35, 0.92)},  # Alakazam
	{"id": "moves",    "pid": 196, "pos": Vector2(640, 290),  "accent": Color(0.55, 0.75, 0.95)},  # Espeon
]

# Pokémon décoratifs — déambulent autour de leur position de départ
const AMBIENT_DEFS: Array[Dictionary] = [
	{"pid": 35,  "pos": Vector2(490, 440), "radius": 45.0},   # Clefairy
	{"pid": 133, "pos": Vector2(760, 445), "radius": 40.0},   # Eevee
	{"pid": 43,  "pos": Vector2(360, 310), "radius": 35.0},   # Oddish
	{"pid": 60,  "pos": Vector2(168, 490), "radius": 30.0},   # Poliwag
	{"pid": 39,  "pos": Vector2(900, 280), "radius": 50.0},   # Jigglypuff
	{"pid": 58,  "pos": Vector2(88,  136), "radius": 0.0},    # Growlithe — garde (immobile)
]

const INTERACT_RADIUS := 88.0
const PLAYER_START    := Vector2(640, 495)

const ZOOM  := 2.0
const MAP_W := 80 * 16   # 1280 px monde
const MAP_H := 45 * 16   # 720 px monde

# ── Palette header ────────────────────────────────────────────────────
const C_HDR      := Color(0.11, 0.08, 0.05, 0.94)
const C_HDR_LINE := Color(0.62, 0.50, 0.32)
const C_GOLD     := Color(0.76, 0.53, 0.17)
const C_TEXT_LT  := Color(0.94, 0.88, 0.72)
const C_TEXT_DIM := Color(0.58, 0.50, 0.36)

var _cam_pos:   Vector2   = PLAYER_START
var _player:    HubPlayer = null
var _npcs:      Array     = []
var _near_npc:  HubNPC    = null
var _blocked:   bool      = false
var _subscreen: CanvasLayer = null

# UI
var _ui:        CanvasLayer = null
var _prompt_lbl: Label     = null
var _gold_lbl:  Label      = null
var _team_lbl:  Label      = null
var _run_lbl:   Label      = null


func _ready() -> void:
	_build_hub_map()
	_register_key()
	_build_npcs()
	_build_ambient()
	_build_sunflowers()
	_build_player()
	_build_ui()
	if GameManager.is_first_run and GameManager.unlocked_pokemon.is_empty():
		_open_starter_selection()


func _build_hub_map() -> void:
	var map := HubMap.new()
	map.name          = "HubMapBg"
	map.z_index       = -1
	map.z_as_relative = false
	add_child(map)
	_cam_pos = PLAYER_START
	_apply_canvas_transform()


func _apply_canvas_transform() -> void:
	var vp      := get_viewport().get_visible_rect().size
	var half_vw := vp.x * 0.5 / ZOOM
	var half_vh := vp.y * 0.5 / ZOOM
	var cx := clampf(_cam_pos.x, half_vw, MAP_W - half_vw)
	var cy := clampf(_cam_pos.y, half_vh, MAP_H - half_vh)
	var t := Transform2D()
	t.x      = Vector2(ZOOM, 0)
	t.y      = Vector2(0, ZOOM)
	t.origin = Vector2(vp.x * 0.5 - cx * ZOOM, vp.y * 0.5 - cy * ZOOM)
	get_viewport().canvas_transform = t


func _register_key() -> void:
	if not InputMap.has_action("hub_interact"):
		InputMap.add_action("hub_interact")
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		InputMap.action_add_event("hub_interact", ev)


# ── Construction ──────────────────────────────────────────────────────

func _build_npcs() -> void:
	for def: Dictionary in NPC_DEFS:
		var npc := HubNPC.new()
		npc.position = def["pos"]
		npc.z_index  = int(def["pos"].y)
		add_child(npc)
		npc.setup(def["id"], def["pid"], def["accent"])
		_npcs.append(npc)


func _build_ambient() -> void:
	for def: Dictionary in AMBIENT_DEFS:
		var npc := HubNPC.new()
		npc.position = def["pos"]
		npc.z_index  = int(def["pos"].y)
		add_child(npc)
		npc.setup("ambient", def["pid"], Color(0, 0, 0, 0))
		var r: float = def.get("radius", 40.0)
		if r > 0.0:
			npc.start_wandering(def["pos"], r, randf_range(14.0, 22.0))


func _build_sunflowers() -> void:
	# Patches de tournesols animés (remplacent les tiles statiques)
	for tile_x in [41, 45]:
		var field := SunflowerField.new()
		field.position = Vector2(tile_x * 16, 38 * 16)
		field.z_index  = 39 * 16 + 1
		add_child(field)


func _build_player() -> void:
	_player = HubPlayer.new()
	_player.position = PLAYER_START
	_player.z_index  = int(PLAYER_START.y)
	add_child(_player)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)

	# Fond du header
	var hdr_bg := ColorRect.new()
	hdr_bg.color    = C_HDR
	hdr_bg.position = Vector2.ZERO
	hdr_bg.size     = Vector2(1280, 72)
	_ui.add_child(hdr_bg)

	var hdr_line := ColorRect.new()
	hdr_line.color    = C_HDR_LINE
	hdr_line.position = Vector2(0, 70)
	hdr_line.size     = Vector2(1280, 2)
	_ui.add_child(hdr_line)

	_gold_lbl = _mk_lbl("◆ 0 Or",          18,  14, 200, 42, 20, C_GOLD)
	_team_lbl = _mk_lbl("Équipe : —",       240, 14, 440, 42, 16, C_TEXT_LT)
	_run_lbl  = _mk_lbl("Run #0",          1140, 14, 130, 42, 16, C_TEXT_DIM)

	_prompt_lbl = _mk_lbl("", 240, 668, 800, 46, 19, Color(0.12, 0.09, 0.05))
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_lbl.visible = false

	_refresh_labels()


func _mk_lbl(text: String, x: float, y: float, w: float, h: float,
		fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text; l.position = Vector2(x, y); l.size = Vector2(w, h)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	_ui.add_child(l)
	return l


func _refresh_labels() -> void:
	if not is_instance_valid(_gold_lbl):
		return
	_gold_lbl.text = "◆ %d Or" % GameManager.gold
	var ts := GameManager.hub_team.size()
	var mx := GameManager.get_max_team_size()
	_team_lbl.text = "Équipe : %d / %d" % [ts, mx]
	_run_lbl.text  = "Run #%d" % GameManager.run_count


# ── Process / interaction ─────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	_cam_pos = _cam_pos.lerp(_player.position, 8.0 * delta)
	_apply_canvas_transform()

	_player.move_tick(delta, _blocked)
	_player.z_index = int(_player.position.y)

	if _blocked:
		return

	# Détection PNJ interactif le plus proche
	var best_npc:  HubNPC = null
	var best_dist: float  = INTERACT_RADIUS

	for npc: HubNPC in _npcs:
		if not is_instance_valid(npc) or npc.npc_id == "ambient":
			continue
		var d := _player.position.distance_to(npc.position)
		if d < best_dist:
			best_dist = d
			best_npc  = npc

	for npc: HubNPC in _npcs:
		if is_instance_valid(npc):
			npc.set_in_range(npc == best_npc)

	if best_npc != _near_npc:
		_near_npc = best_npc
		_update_prompt(best_npc)

	if best_npc != null and Input.is_action_just_pressed("hub_interact"):
		_interact(best_npc)


func _update_prompt(npc: HubNPC) -> void:
	if not is_instance_valid(_prompt_lbl):
		return
	if npc == null:
		_prompt_lbl.visible = false
		return

	var role: String
	match npc.npc_id:
		"start":    role = "Lancer la Run"
		"shop":     role = "Boutique"
		"team":     role = "Équipe"
		"pokedex":  role = "Pokédex"
		"upgrades": role = "Améliorations"
		"moves":    role = "Capacités"
		_:          role = "Parler"

	var display_name := npc.npc_name if not npc.npc_name.is_empty() else "…"
	_prompt_lbl.text    = "[ E ]   %s   –   %s" % [display_name, role]
	_prompt_lbl.visible = true

	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.91, 0.85, 0.70, 0.90)
	s.border_color = Color(0.62, 0.50, 0.32)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	_prompt_lbl.add_theme_stylebox_override("normal", s)


func _interact(npc: HubNPC) -> void:
	_blocked = true
	var screen: CanvasLayer = null

	match npc.npc_id:
		"start":
			_start_run()
			return
		"shop":
			screen = ShopScreen.new()
		"team":
			screen = TeamBuilderScreen.new()
		"pokedex":
			screen = PokedexScreen.new()
		"upgrades":
			screen = UpgradeShopScreen.new()
		"moves":
			screen = MoveShopScreen.new()

	if screen == null:
		_blocked = false
		return

	screen.layer = 10
	add_child(screen)
	_subscreen = screen

	if screen.has_signal("closed"):
		screen.closed.connect(func() -> void:
			screen.queue_free()
			_subscreen = null
			_blocked   = false
			_refresh_labels()
		, CONNECT_ONE_SHOT)


# ── Actions ───────────────────────────────────────────────────────────

func _start_run() -> void:
	if GameManager.hub_team.is_empty():
		_show_coming_soon("Parle d'abord à Ko\npour composer ton équipe !")
		return
	GameManager.run_count += 1
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")


func _open_starter_selection() -> void:
	_blocked = true
	var screen := StarterSelectionScreen.new()
	screen.layer = 30
	add_child(screen)
	screen.starter_chosen.connect(func(pokemon_id: int) -> void:
		GameManager.selected_starter_id = pokemon_id
		GameManager.unlock_pokemon(pokemon_id)
		GameManager.hub_team       = [pokemon_id]
		GameManager.is_first_run   = false
		screen.queue_free()
		_blocked = false
		_refresh_labels()
		if is_instance_valid(_player):
			PMDSprites.get_walk_sprites(pokemon_id, _player, _player._on_sprites)
	, CONNECT_ONE_SHOT)


func _show_coming_soon(msg: String) -> void:
	_blocked = true
	var canvas := CanvasLayer.new()
	canvas.layer = 25
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.03, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var lbl := Label.new()
	lbl.text = msg
	lbl.position = Vector2(340, 290)
	lbl.size     = Vector2(600, 100)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.91, 0.85, 0.70))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	canvas.add_child(lbl)

	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		canvas.queue_free()
		_blocked = false
	)
