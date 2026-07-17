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
		elif arg == "smoke_pokedex":
			_run_scenario(_scenario_pokedex)
		elif arg == "smoke_pokedex_stress":
			_run_scenario(_scenario_pokedex_stress)
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


## Ouvre le VRAI PokedexScreen et vérifie la navigation clavier : deux erreurs
## de suite (typage cassé, parse cassé) sont passées au travers des scénarios
## de combat, qui n'instancient jamais cet écran. On simule ui_right/ui_down et
## on exige que le focus BOUGE — c'est le contrat de la navigation aux flèches.
func _scenario_pokedex() -> void:
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	# 2,5 s : le temps que TOUT l'asynchrone retombe (données API, portraits,
	# sprites PMD) — c'est un rafraîchissement déclenché par un portrait tardif
	# qui tuait le focus à ~1,5 s, un simple await court ne l'aurait jamais vu.
	await get_tree().create_timer(2.5).timeout

	var vp := get_tree().root
	var f0 := vp.gui_get_focus_owner()
	if f0 == null:
		_fail("pokedex", "aucun contrôle focalisé à l'ouverture")
		return
	for action in ["ui_right", "ui_down"]:
		var ev := InputEventAction.new()
		ev.action  = action
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
	var f1 := vp.gui_get_focus_owner()
	if f1 == null or f1 == f0:
		_fail("pokedex", "focus inerte (%s -> %s)" % [f0, f1])
		return
	_pass("pokedex", "focus %s -> %s" % [f0.name, f1.name])


## STRESS : simule des remplacements d'attaque en RAFALE (retour joueurs :
## « erreur quand je change une attaque plusieurs fois »). Presse les cartes CT
## et les boutons du sélecteur de remplacement via leurs signaux pressed.
func _scenario_pokedex_stress() -> void:
	var starter: int = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [starter]
	if not starter in GameManager.unlocked_pokemon:
		GameManager.unlocked_pokemon.append(starter)
	GameManager.purchased_move_names = ["cut", "strength", "surf", "thunderbolt"]
	GameManager.move_slot_count = 2
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.0).timeout
	screen._select(starter)
	await get_tree().create_timer(0.5).timeout

	# Chaque pression déclenche un _refresh_detail qui DÉTRUIT les boutons
	# suivants — la liste est donc re-collectée à chaque itération (une liste
	# figée finirait par presser un nœud libéré : plantage du harnais, pas de
	# l'écran).
	var total_pressed := 0
	for round_i in 40:
		var btns: Array = _all_buttons(screen._detail_root)
		if btns.is_empty():
			break
		var n: Button = btns[round_i % btns.size()]
		if not is_instance_valid(n):
			continue
		n.emit_signal("pressed")
		total_pressed += 1
		await get_tree().process_frame
		await get_tree().process_frame
		# si un sélecteur de remplacement s'est ouvert, presse sa 1re option
		if is_instance_valid(screen._replace_picker):
			var opts := _all_buttons(screen._replace_picker)
			if not opts.is_empty():
				(opts[0] as Button).emit_signal("pressed")
				await get_tree().process_frame
				await get_tree().process_frame
	if total_pressed < 10:
		_fail("pokedex_stress", "trop peu de pressions exercées (%d)" % total_pressed)
		return
	_pass("pokedex_stress", "%d pressions sans erreur" % total_pressed)


func _all_buttons(root: Node) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and not (n as Button).disabled:
			out.append(n)
		stack.append_array(n.get_children())
	return out


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
