class_name SettingsScreen
extends CanvasLayer

## Écran Paramètres (UiKit) — volume général, volume des effets, couper
## le son. Accessible depuis le menu principal ET le menu pause en run
## (cf. PauseMenuScreen). Applique les changements en direct
## (GameManager.apply_audio_settings) et sauvegarde à la fermeture.

signal closed

var _panel: Panel = null
var _confirming_reset: bool = false


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)
	add_child(MenuNav.make(func() -> void: closed.emit()))
	_build()


func _build() -> void:
	if _confirming_reset:
		_build_confirm_reset()
	else:
		_build_main()


func _build_main() -> void:
	_panel = UiKit.main_panel(Vector2(320, 90), Vector2(640, 500))
	add_child(_panel)
	UiKit.pop_in(_panel)
	UiKit.banner(_panel, "PARAMÈTRES")

	UiKit.label(_panel, "Volume général", Vector2(40, 84), 15, UiKit.CREAM, 300)
	_build_slider(Vector2(40, 110), GameManager.master_volume, func(v: float) -> void:
		GameManager.master_volume = v
		GameManager.apply_audio_settings()
	)

	UiKit.label(_panel, "Volume des effets sonores", Vector2(40, 164), 15, UiKit.CREAM, 300)
	_build_slider(Vector2(40, 190), GameManager.sfx_volume, func(v: float) -> void:
		GameManager.sfx_volume = v
		GameManager.apply_audio_settings()
	)

	var mute_btn := UiKit.button(
		"🔇  Réactiver le son" if GameManager.audio_muted else "🔊  Couper le son",
		Vector2(300, 52), not GameManager.audio_muted)
	mute_btn.position = Vector2(170, 246)
	_panel.add_child(mute_btn)
	mute_btn.pressed.connect(func() -> void:
		GameManager.audio_muted = not GameManager.audio_muted
		GameManager.apply_audio_settings()
		GameManager.save_game()
		_rebuild()
	)

	# Contrôles : voir toutes les touches, à quoi elles servent, et les remapper.
	var ctrl_btn := UiKit.button("⌨  Contrôles / touches", Vector2(300, 52), false)
	ctrl_btn.position = Vector2(170, 310)
	_panel.add_child(ctrl_btn)
	ctrl_btn.pressed.connect(_open_controls)

	# Réinitialisation : efface la sauvegarde et toute la progression.
	var reset_btn := UiKit.button("🗑  Réinitialiser la partie", Vector2(300, 52), false)
	reset_btn.position = Vector2(170, 374)
	_panel.add_child(reset_btn)
	reset_btn.pressed.connect(func() -> void:
		_confirming_reset = true
		_rebuild()
	)

	var back := UiKit.button("✓  Fermer", Vector2(220, 48), false)
	back.position = Vector2(210, 438)
	_panel.add_child(back)
	back.pressed.connect(func() -> void:
		GameManager.save_game()
		closed.emit()
	)
	MenuNav.focus_first(_panel)


func _build_confirm_reset() -> void:
	_panel = UiKit.main_panel(Vector2(320, 150), Vector2(640, 340))
	add_child(_panel)
	UiKit.pop_in(_panel)
	UiKit.banner(_panel, "RÉINITIALISER LA PARTIE ?")

	UiKit.label(_panel, "Toute la progression (Pokémon débloqués, équipe, or, objets,\naméliorations…) sera définitivement perdue.\nCette action est irréversible.",
		Vector2(30, 100), 15, UiKit.CREAM, 580, HORIZONTAL_ALIGNMENT_CENTER)

	var yes := UiKit.button("✕  Oui, réinitialiser", Vector2(260, 52), false)
	yes.position = Vector2(50, 240)
	_panel.add_child(yes)
	yes.pressed.connect(_do_reset)

	var no := UiKit.button("↩  Non, annuler", Vector2(260, 52))
	no.position = Vector2(330, 240)
	_panel.add_child(no)
	no.pressed.connect(func() -> void:
		_confirming_reset = false
		_rebuild()
	)
	MenuNav.focus_first(_panel)


func _do_reset() -> void:
	GameManager.reset_save()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _open_controls() -> void:
	var cs := ControlsScreen.new()
	add_child(cs)
	cs.closed.connect(func() -> void:
		cs.queue_free()
		MenuNav.focus_first(_panel)
	, CONNECT_ONE_SHOT)


func _rebuild() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_build()


## Curseur "bois & parchemin" — piste sombre, remplissage doré, poignée
## ronde crème (même palette que les barres de stats du lobby multi).
func _build_slider(pos: Vector2, value: float, on_changed: Callable) -> void:
	var slider := HSlider.new()
	slider.position = pos
	slider.size     = Vector2(520, 24)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.01
	slider.value     = value

	var groove := StyleBoxFlat.new()
	groove.bg_color = UiKit.WOOD_DARK
	groove.set_corner_radius_all(6)
	groove.content_margin_top    = 8
	groove.content_margin_bottom = 8
	slider.add_theme_stylebox_override("slider", groove)

	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.GOLD
	fill.set_corner_radius_all(6)
	fill.content_margin_top    = 8
	fill.content_margin_bottom = 8
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	var grabber := _make_grabber_icon()
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.add_theme_icon_override("grabber_disabled", grabber)

	slider.value_changed.connect(func(v: float) -> void: on_changed.call(v))
	_panel.add_child(slider)


static var _grabber_cache: Texture2D = null

func _make_grabber_icon() -> Texture2D:
	if _grabber_cache != null:
		return _grabber_cache
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 20:
		for x in 20:
			var d := Vector2(x - 9.5, y - 9.5).length()
			if d <= 9.0:
				img.set_pixel(x, y, UiKit.CREAM if d <= 7.0 else UiKit.WOOD_EDGE)
	_grabber_cache = ImageTexture.create_from_image(img)
	return _grabber_cache


func _exit_tree() -> void:
	Sfx.play_file(Sfx.SE_MENU_CLOSE, -6.0)
