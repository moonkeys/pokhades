class_name SettingsScreen
extends CanvasLayer

## Écran Paramètres (UiKit) — volume général, volume des effets, couper
## le son. Accessible depuis le menu principal ET le menu pause en run
## (cf. PauseMenuScreen). Applique les changements en direct
## (GameManager.apply_audio_settings) et sauvegarde à la fermeture.

signal closed

var _panel: Panel = null


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.play_file(Sfx.SE_MENU_OPEN, -6.0)
	add_child(MenuNav.make(func() -> void: closed.emit()))
	_build()


func _build() -> void:
	_panel = UiKit.main_panel(Vector2(340, 110), Vector2(600, 440))
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
	mute_btn.position = Vector2(150, 246)
	_panel.add_child(mute_btn)
	mute_btn.pressed.connect(func() -> void:
		GameManager.audio_muted = not GameManager.audio_muted
		GameManager.apply_audio_settings()
		GameManager.save_game()
		_rebuild()
	)

	# Contrôles : voir toutes les touches, à quoi elles servent, et les remapper.
	var ctrl_btn := UiKit.button("⌨  Contrôles / touches", Vector2(300, 52), false)
	ctrl_btn.position = Vector2(150, 310)
	_panel.add_child(ctrl_btn)
	ctrl_btn.pressed.connect(_open_controls)

	var back := UiKit.button("✓  Fermer", Vector2(220, 48), false)
	back.position = Vector2(190, 374)
	_panel.add_child(back)
	back.pressed.connect(func() -> void:
		GameManager.save_game()
		closed.emit()
	)
	MenuNav.focus_first(_panel)


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
