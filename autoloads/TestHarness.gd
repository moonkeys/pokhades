extends Node

## Harnais de smoke-tests — inerte en jeu normal, ne s'active que via des
## arguments de ligne de commande (après `--`). Utilisé par tests/smoke.sh
## avant chaque livraison pour attraper les régressions qui ne se voient
## qu'en LANÇANT vraiment le jeu (ex : parse error de CombatArena qui ne
## cassait ni l'éditeur ni le boot du menu, mais toute run).
##
##   smoke_boot          : boot du menu principal, marqueur OK, quitte.
##   smoke_run           : équipe une équipe solo, lance CombatArena,
##                         vérifie équipe + ennemis apparus, quitte.
##   smoke_run_room=N    : comme smoke_run mais simule la salle N (teste
##                         les actes avancés : formes évoluées, boss…).
##   mp_test_host        : héberge, attend un client, lance la run,
##                         vérifie l'équipe, quitte.
##   mp_test_join=CODE   : rejoint, se déclare prêt, vérifie, quitte.
##
## Chaque scénario imprime SMOKE_OK <nom> ou SMOKE_FAIL <nom> <raison> —
## le script shell greppe ces marqueurs et rend un code de sortie.

const RUN_SETTLE_TIME := 8.0   # temps laissé à CombatArena pour précharger/spawner


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "smoke_boot":
			_run_scenario(_scenario_boot)
		elif arg == "smoke_run":
			_run_scenario(_scenario_run.bind(0))
		elif arg.begins_with("smoke_run_room="):
			_run_scenario(_scenario_run.bind(int(arg.substr(15))))
		elif arg == "mp_test_host":
			_run_scenario(_scenario_mp_host)
		elif arg.begins_with("mp_test_join="):
			_run_scenario(_scenario_mp_join.bind(arg.substr(13)))


func _run_scenario(fn: Callable) -> void:
	call_deferred("_launch", fn)


func _launch(fn: Callable) -> void:
	await fn.call()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _pass(name_s: String, extra: String = "") -> void:
	print("SMOKE_OK %s %s" % [name_s, extra])


func _fail(name_s: String, reason: String) -> void:
	print("SMOKE_FAIL %s %s" % [name_s, reason])


# ── Scénarios ───────────────────────────────────────────────────────────

func _scenario_boot() -> void:
	await get_tree().create_timer(3.0).timeout
	if get_tree().current_scene == null:
		_fail("boot", "aucune scène courante")
		return
	_pass("boot", String(get_tree().current_scene.name))


func _scenario_run(start_room: int) -> void:
	GameManager.is_first_run = false
	GameManager.selected_starter_id = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	if start_room > 0:
		RunManager.inst().start_run()
		RunManager.inst().rooms_cleared = start_room
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	# Polling plutôt qu'attente fixe : au premier lancement, le préchargement
	# des espèces passe par le réseau et peut largement dépasser 8 s.
	var scenario := "run" if start_room == 0 else "run_room%d" % start_room
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	await get_tree().create_timer(3.0).timeout   # temps de télégraphie des spawns

	var team := get_tree().get_nodes_in_group("players").size()
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	if team == 0:
		_fail(scenario, "équipe non apparue")
		return
	# Salle boutique/boss : pas forcément d'ennemis immédiats — on tolère 0
	# ennemi SI la salle est une boutique ; sinon des ennemis (ou une
	# télégraphie en cours) doivent exister.
	var rm := RunManager.inst()
	if enemies == 0 and not rm.is_shop_room(rm.rooms_cleared):
		_fail(scenario, "aucun ennemi apparu (team=%d)" % team)
		return
	_pass(scenario, "team=%d enemies=%d" % [team, enemies])


func _scenario_mp_host() -> void:
	if Net.host_game("SmokeHost") != OK:
		_fail("mp_host", "host_game a échoué (port occupé ?)")
		return
	await get_tree().create_timer(0.5).timeout
	print("SMOKE_CODE=%s" % Net.join_code)
	var waited := 0.0
	while Net.players.size() < 2 and waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if Net.players.size() < 2:
		_fail("mp_host", "aucun client connecté")
		return
	Net.set_my_choice(GameManager.STARTER_IDS[0], "", true)
	waited = 0.0
	while not Net.all_ready() and waited < 15.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if not Net.all_ready():
		_fail("mp_host", "les joueurs ne sont jamais tous prêts")
		return
	Net.start_game()
	await get_tree().create_timer(RUN_SETTLE_TIME).timeout
	var team := get_tree().get_nodes_in_group("players").size()
	if team < 2:
		_fail("mp_host", "équipe incomplète (team=%d)" % team)
		return
	_pass("mp_host", "team=%d" % team)
	# Reste en vie le temps que le CLIENT fasse sa propre vérification —
	# quitter tout de suite le déconnecte (server_closed) avant son check.
	await get_tree().create_timer(10.0).timeout


func _scenario_mp_join(code: String) -> void:
	GameManager.is_first_run = false
	await get_tree().create_timer(0.5).timeout
	if Net.join_game(code, "SmokeClient") != OK:
		_fail("mp_join", "join_game a échoué")
		return
	await get_tree().create_timer(2.0).timeout
	if not Net.active or Net.players.is_empty():
		_fail("mp_join", "jamais enregistré auprès de l'hôte")
		return
	Net.set_my_choice(GameManager.STARTER_IDS[1], "", true)
	await get_tree().create_timer(RUN_SETTLE_TIME + 4.0).timeout
	var team := get_tree().get_nodes_in_group("players").size()
	if team < 1:
		_fail("mp_join", "équipe non apparue côté client")
		return
	_pass("mp_join", "team=%d" % team)
