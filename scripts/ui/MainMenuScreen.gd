class_name MainMenuScreen
extends Node3D

## Écran-titre — point d'entrée du jeu (cf. project.godot run/main_scene).
## Deux modes :
## - "Mode principal" : campagne solo — direct au Hub (qui ouvre lui-même
##   la sélection de starter si c'est la toute première partie, cf.
##   HubWorld._ready / GameManager.is_first_run).
## - "Mode multijoueur" : ouvre le lobby (héberger/rejoindre) par-dessus ce
##   même écran — une fois la partie lancée, Net._begin() bascule tout le
##   monde vers CombatArena.tscn, quelle que soit la scène en cours.

var _ui: CanvasLayer = null
var _lobby: MultiplayerLobbyScreen = null
var _settings: SettingsScreen = null
var _dl_status: Label = null
var _dl_btn: Button = null


func _ready() -> void:
	_build_background()
	_build_ui()


func _build_background() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color        = Color(0.40, 0.58, 0.82)
	sky_mat.sky_horizon_color    = Color(0.86, 0.80, 0.64)
	sky_mat.ground_bottom_color  = Color(0.30, 0.28, 0.24)
	sky_mat.ground_horizon_color = Color(0.86, 0.80, 0.64)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.adjustment_enabled    = true
	e.adjustment_saturation = 1.3
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color  = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.1
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 3, 8)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 50
	add_child(cam)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var panel := UiKit.main_panel(Vector2(340, 100), Vector2(600, 540))
	_ui.add_child(panel)
	UiKit.pop_in(panel)

	UiKit.banner(panel, "POKHADES")
	UiKit.label(panel, "Un rogue-lite Pokémon", Vector2(0, 66), 15,
		UiKit.TEXT_DARK.lightened(0.2), 600, HORIZONTAL_ALIGNMENT_CENTER)

	var solo := UiKit.button("⚔  Mode principal", Vector2(440, 64))
	solo.position = Vector2(80, 150)
	panel.add_child(solo)
	solo.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	)

	var multi := UiKit.button("🌐  Mode multijoueur", Vector2(440, 64))
	multi.position = Vector2(80, 222)
	panel.add_child(multi)
	multi.pressed.connect(_open_multiplayer_lobby)

	var settings := UiKit.button("⚙  Paramètres", Vector2(440, 52), false)
	settings.position = Vector2(80, 294)
	panel.add_child(settings)
	settings.pressed.connect(_open_settings)

	var quit := UiKit.button("✕  Quitter", Vector2(440, 52), false)
	quit.position = Vector2(80, 356)
	panel.add_child(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())

	# Télécharge toutes les données du jeu (espèces + attaques) en cache
	# disque une bonne fois pour toutes — ensuite plus besoin d'internet
	# pour jouer (cf. PokemonAPI.prefetch_all, réexécutable sans risque).
	_dl_btn = UiKit.button("⬇  Télécharger pour jouer hors-ligne", Vector2(440, 40), false)
	_dl_btn.position = Vector2(80, 424)
	_dl_btn.add_theme_font_size_override("font_size", UiKit.scaled_font(13))
	panel.add_child(_dl_btn)
	_dl_btn.pressed.connect(_start_offline_download)

	_dl_status = UiKit.label(panel, "", Vector2(0, 470), 12,
		UiKit.TEXT_DARK.lightened(0.35), 600, HORIZONTAL_ALIGNMENT_CENTER)

	PokemonAPI.prefetch_progress.connect(func(done: int, total: int) -> void:
		_dl_status.text = "Téléchargement… %d / %d" % [done, total]
	)
	PokemonAPI.prefetch_finished.connect(func() -> void:
		_dl_status.text = "v%s  —  ✓ Données téléchargées, jouable hors-ligne" % GameManager.VERSION
		_dl_btn.disabled = false
		_dl_btn.text = "⬇  Retélécharger"
	)
	_dl_status.text = "v%s" % GameManager.VERSION


func _start_offline_download() -> void:
	_dl_btn.disabled = true
	_dl_status.text = "Téléchargement…"
	PokemonAPI.prefetch_all()


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	_settings = SettingsScreen.new()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings = null
	, CONNECT_ONE_SHOT)


func _open_multiplayer_lobby() -> void:
	if is_instance_valid(_lobby):
		return
	_lobby = MultiplayerLobbyScreen.new()
	add_child(_lobby)
	_lobby.closed.connect(func() -> void:
		_lobby.queue_free()
		_lobby = null
	, CONNECT_ONE_SHOT)
