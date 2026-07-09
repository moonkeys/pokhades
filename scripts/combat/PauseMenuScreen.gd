class_name PauseMenuScreen
extends CanvasLayer

## Menu pause en run (Échap) — reprendre, paramètres (volume/son), ou
## abandonner la run en cours (avec confirmation — perte de progression
## de cette run). Habillage UiKit, cohérent avec le reste du jeu.

signal closed

var _panel:        Panel = null
var _confirm_quit: bool = false
var _settings:     SettingsScreen = null


func _ready() -> void:
	layer = 33
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	add_child(MenuNav.make(_on_cancel_pressed))
	_build()


func _exit_tree() -> void:
	get_tree().paused = false


func _on_cancel_pressed() -> void:
	if _confirm_quit:
		_confirm_quit = false
		_build()
	else:
		closed.emit()


func _build() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = UiKit.main_panel(Vector2(390, 170), Vector2(500, 340))
	add_child(_panel)
	UiKit.pop_in(_panel)

	if _confirm_quit:
		_build_confirm()
	else:
		_build_main()
	MenuNav.focus_first(_panel)


func _build_main() -> void:
	UiKit.banner(_panel, "PAUSE")

	var resume_btn := UiKit.button("▶  Reprendre", Vector2(400, 52))
	resume_btn.position = Vector2(50, 90)
	_panel.add_child(resume_btn)
	resume_btn.pressed.connect(func() -> void: closed.emit())

	var settings_btn := UiKit.button("⚙  Paramètres", Vector2(400, 52), false)
	settings_btn.position = Vector2(50, 152)
	_panel.add_child(settings_btn)
	settings_btn.pressed.connect(_open_settings)

	var quit_btn := UiKit.button("✕  Quitter la run", Vector2(400, 52), false)
	quit_btn.position = Vector2(50, 214)
	_panel.add_child(quit_btn)
	quit_btn.pressed.connect(func() -> void:
		_confirm_quit = true
		_build()
	)


func _build_confirm() -> void:
	UiKit.banner(_panel, "ABANDONNER ?")
	UiKit.label(_panel, "Tu vas quitter cette run — sa progression sera perdue.\nRevenir au hub ?",
		Vector2(30, 100), 15, UiKit.CREAM, 440, HORIZONTAL_ALIGNMENT_CENTER)

	var yes := UiKit.button("✕  Oui, quitter", Vector2(200, 52), false)
	yes.position = Vector2(50, 220)
	_panel.add_child(yes)
	yes.pressed.connect(_do_quit)

	var no := UiKit.button("↩  Non, continuer", Vector2(200, 52))
	no.position = Vector2(260, 220)
	_panel.add_child(no)
	no.pressed.connect(func() -> void:
		_confirm_quit = false
		_build()
	)


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	_settings = SettingsScreen.new()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
	, CONNECT_ONE_SHOT)


func _do_quit() -> void:
	if Net.in_run:
		Net.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
