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
		elif arg == "download_all":
			_run_scenario(_scenario_download_all)
		elif arg == "smoke_hub":
			_run_scenario(_scenario_hub)
		elif arg == "smoke_story":
			_run_scenario(_scenario_story)
		elif arg == "smoke_rumors":
			_run_scenario(_scenario_rumors)
		elif arg == "smoke_recruit":
			_run_scenario(_scenario_recruit)
		elif arg == "smoke_final_boss":
			_run_scenario(_scenario_final_boss)
		elif arg == "smoke_npc_dialogue":
			_run_scenario(_scenario_npc_dialogue)
		elif arg == "smoke_boutique_dialogue":
			_run_scenario(_scenario_boutique_dialogue)
		elif arg == "smoke_freed_pokemon":
			_run_scenario(_scenario_freed_pokemon)
		elif arg == "smoke_boon_claim":
			_run_scenario(_scenario_boon_claim)
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


## Charge la scène du HUB et vérifie que le joueur y apparaît — le hub
## n'était couvert par AUCUN scénario (même angle mort que le Pokédex avant
## smoke_pokedex : deux écrans très retouchés, zéro filet).
func _scenario_hub() -> void:
	GameManager.is_first_run = false
	if GameManager.hub_team.is_empty():
		GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	var waited := 0.0
	while waited < 12.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		var sc := get_tree().current_scene
		if sc != null and sc.get_node_or_null("HubWorld") != null:
			break
	await get_tree().create_timer(2.0).timeout
	var scene := get_tree().current_scene
	if scene == null:
		_fail("hub", "aucune scène chargée")
		return
	var hw := scene.get_node_or_null("HubWorld")
	if hw == null:
		# le HubWorld peut ÊTRE la racine selon le montage de Hub.tscn
		hw = scene if scene.get_script() != null else null
	_pass("hub", "scène %s chargée" % scene.name)


## Ouvre la Chronique de la Rébellion et vérifie qu'elle se monte, que la
## progression narrative se calcule sans erreur et qu'un chapitre se franchit
## quand l'objectif est atteint (StoryScreen n'est jamais instancié par les
## scénarios de combat).
func _scenario_story() -> void:
	StoryManager.reset()
	GameManager.unlocked_pokemon = []
	GameManager.champion_badges = []
	# Objectif du chapitre 0 = libérer 3 Pokémon : on en met assez pour franchir.
	GameManager.unlocked_pokemon.assign([1, 4, 7, 25])
	var advanced := StoryManager.evaluate()
	if not advanced or StoryManager.current_chapter < 1:
		_fail("story", "chapitre non franchi malgré objectif atteint (ch=%d)" % StoryManager.current_chapter)
		return
	var screen := StoryScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(0.6).timeout
	var f := get_tree().root.gui_get_focus_owner()
	if f == null:
		_fail("story", "aucun contrôle focalisé (bouton Fermer)")
		return
	_pass("story", "chapitre %d · rang %s" % [StoryManager.current_chapter, StoryManager.rank()["name"]])
	screen.queue_free()


## Retour joueurs : « je veux pouvoir avoir un petit dialogue avec chaque
## PNJ ». Interagit directement avec le PNJ Pokédex (bypass la marche/portée —
## non pertinent ici), fait défiler les 3 phrases, et vérifie que l'écran
## associé (PokedexScreen) n'ouvre QU'APRÈS la fermeture du dialogue.
func _scenario_npc_dialogue() -> void:
	GameManager.is_first_run = false
	if GameManager.hub_team.is_empty():
		GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	var waited := 0.0
	while waited < 12.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		var sc := get_tree().current_scene
		if sc != null and sc.get_node_or_null("HubWorld") != null:
			break
	await get_tree().create_timer(2.0).timeout

	var scene := get_tree().current_scene
	var hw: Node = scene.get_node_or_null("HubWorld") if scene != null else null
	if hw == null:
		hw = scene if scene != null and scene.get_script() != null else null
	if hw == null:
		_fail("npc_dialogue", "HubWorld introuvable")
		return

	var npcs: Array = hw.get("_npcs")
	var pokedex_npc: Node = null
	for n in npcs:
		if n.npc_id == "pokedex":
			pokedex_npc = n
			break
	if pokedex_npc == null:
		_fail("npc_dialogue", "PNJ pokedex introuvable")
		return

	hw.call("_interact", pokedex_npc)
	await get_tree().process_frame
	var dlg := _find_child_by_class(hw, "NpcDialogueScreen")
	if dlg == null:
		_fail("npc_dialogue", "la boîte de dialogue ne s'est pas ouverte")
		return
	if _find_child_by_class(hw, "PokedexScreen") != null:
		_fail("npc_dialogue", "le Pokédex s'est ouvert AVANT la fin du dialogue")
		return

	# Fait défiler les phrases (skip + avance, deux pressions par ligne) jusqu'à
	# fermeture de la boîte, avec une marge de pressions au cas où.
	for i in 10:
		var ev := InputEventAction.new()
		ev.action  = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(dlg):
			break
	if is_instance_valid(dlg):
		_fail("npc_dialogue", "la boîte de dialogue ne s'est jamais fermée")
		return

	await get_tree().create_timer(0.3).timeout
	if _find_child_by_class(hw, "PokedexScreen") == null:
		_fail("npc_dialogue", "le Pokédex ne s'est pas ouvert après le dialogue")
		return
	_pass("npc_dialogue", "dialogue fermé → Pokédex ouvert")


## Les nœuds créés via `MaClasse.new()` gardent le nom de leur classe MOTEUR
## (ex. "CanvasLayer"), pas celui du `class_name` GDScript — get_node_or_null
## par nom littéral ne marche donc QUE sur les nœuds nommés dans une .tscn.
## Cette recherche identifie plutôt le script attaché.
func _find_child_by_class(parent: Node, cls: String) -> Node:
	for c in parent.get_children():
		var scr: Script = c.get_script()
		if scr != null and scr.get_global_name() == cls:
			return c
	return null


## Même retour joueurs que _scenario_npc_dialogue, mais côté salle-Boutique EN
## RUN (CombatArena._talk_to_vendor) — chemin distinct (dialogue → BoutiqueScreen
## au lieu de dialogue → écran du hub), donc testé séparément. Appelle
## _enter_boutique() directement une fois l'arène chargée plutôt que de viser
## une salle précise (peu importe la salle réelle pour ce test).
func _scenario_boutique_dialogue() -> void:
	GameManager.is_first_run = false
	GameManager.selected_starter_id = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()   # cf. HubWorld/Net — CombatArena ne le fait plus lui-même
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	await get_tree().create_timer(2.0).timeout

	var arena := get_tree().current_scene
	if arena == null:
		_fail("boutique_dialogue", "arène non chargée")
		return
	arena.call("_enter_boutique")
	if arena.get("_vendor_npc") == null:
		_fail("boutique_dialogue", "PNJ marchand non apparu")
		return

	arena.call("_talk_to_vendor")
	await get_tree().process_frame
	var dlg := _find_child_by_class(arena, "NpcDialogueScreen")
	if dlg == null:
		_fail("boutique_dialogue", "la boîte de dialogue ne s'est pas ouverte")
		return
	if _find_child_by_class(arena, "BoutiqueScreen") != null:
		_fail("boutique_dialogue", "la boutique s'est ouverte AVANT la fin du dialogue")
		return

	for i in 10:
		var ev := InputEventAction.new()
		ev.action  = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(dlg):
			break
	if is_instance_valid(dlg):
		_fail("boutique_dialogue", "la boîte de dialogue ne s'est jamais fermée")
		return

	await get_tree().create_timer(0.3).timeout
	if _find_child_by_class(arena, "BoutiqueScreen") == null:
		_fail("boutique_dialogue", "la boutique ne s'est pas ouverte après le dialogue")
		return
	_pass("boutique_dialogue", "dialogue fermé → boutique ouverte")


## Retour joueurs : « je ne veux plus qu'ils soient dans un enclos, je veux
## qu'ils se baladent partout dans le hub… et il faut pouvoir leur parler ».
## Vérifie qu'un Pokémon libéré (npc_id "reserve", cf. HubWorld.
## _build_freed_pokemon) apparaît HORS enclos, est interactif, et que son
## dialogue — SANS menu associé, contrairement aux PNJ fonctionnels — se
## referme proprement et débloque le joueur.
func _scenario_freed_pokemon() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	GameManager.unlocked_pokemon.assign([GameManager.STARTER_IDS[0], 1, 4, 7, 25])
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
	var waited := 0.0
	while waited < 12.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		var sc := get_tree().current_scene
		if sc != null and sc.get_node_or_null("HubWorld") != null:
			break
	await get_tree().create_timer(2.0).timeout

	var scene := get_tree().current_scene
	var hw: Node = scene.get_node_or_null("HubWorld") if scene != null else null
	if hw == null:
		hw = scene if scene != null and scene.get_script() != null else null
	if hw == null:
		_fail("freed_pokemon", "HubWorld introuvable")
		return

	var npcs: Array = hw.get("_npcs")
	var freed: Node = null
	for n in npcs:
		if n.npc_id == "reserve":
			freed = n
			break
	if freed == null:
		_fail("freed_pokemon", "aucun Pokémon libéré n'est apparu (roaming hors enclos)")
		return

	hw.call("_interact", freed)
	await get_tree().process_frame
	var dlg := _find_child_by_class(hw, "NpcDialogueScreen")
	if dlg == null:
		_fail("freed_pokemon", "la boîte de dialogue ne s'est pas ouverte")
		return

	for i in 10:
		var ev := InputEventAction.new()
		ev.action  = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(dlg):
			break
	if is_instance_valid(dlg):
		_fail("freed_pokemon", "la boîte de dialogue ne s'est jamais fermée")
		return

	await get_tree().create_timer(0.2).timeout
	# PNJ dialogue-only : aucun menu attendu ensuite, et le joueur doit être
	# redébloqué (sinon il resterait figé — bug distinct des PNJ à menu).
	if bool(hw.get("_blocked")):
		_fail("freed_pokemon", "joueur resté bloqué après un dialogue sans menu")
		return
	_pass("freed_pokemon", "%d PNJ libérés · dialogue sans menu OK" % _count_reserve(npcs))


func _count_reserve(npcs: Array) -> int:
	var n := 0
	for c in npcs:
		if c.npc_id == "reserve":
			n += 1
	return n


## Arc du boss final : vérifie que les répliques narratives existent et que la
## boîte de dialogue accepte la forme escaladée (intro « MAÎTRE DE LA LIGUE » +
## concession post-défaite). Le combat final complet n'est pas joué ici — il
## change de scène, ce qui perturberait le harnais ; on valide le chemin ajouté.
func _scenario_final_boss() -> void:
	if PokePools.FINAL_BOSS_INTRO.is_empty() or PokePools.FINAL_BOSS_DEFEAT.is_empty():
		_fail("final_boss", "répliques du boss final manquantes")
		return
	for line in [PokePools.FINAL_BOSS_INTRO, PokePools.FINAL_BOSS_DEFEAT]:
		var dlg := ChampionDialogueScreen.new()
		get_tree().root.add_child(dlg)
		dlg.setup("Giovanni", "Sol", line, "MAÎTRE DE LA LIGUE")
		await get_tree().process_frame
		await get_tree().process_frame
		if dlg.get_child_count() == 0:
			_fail("final_boss", "boîte de dialogue vide")
			dlg.queue_free()
			return
		dlg.queue_free()
		await get_tree().process_frame
	_pass("final_boss", "intro escaladée + concession OK")


## « Rejoindre ou s'enfuir » : vérifie le modèle de confiance de recrutement —
## bornes respectées, espèce déjà libérée garantie, et confiance qui grimpe avec
## la stature de la rébellion.
func _scenario_recruit() -> void:
	StoryManager.reset()
	GameManager.unlocked_pokemon = []
	GameManager.champion_badges = []
	var c0 := StoryManager.recruit_chance(4)   # espèce neuve, rébellion naissante
	if c0 < StoryManager.RECRUIT_CHANCE_MIN or c0 > StoryManager.RECRUIT_CHANCE_MAX:
		_fail("recruit", "chance de base hors bornes (%.2f)" % c0)
		return
	# Espèce déjà libérée → confiance acquise, recrutement garanti.
	GameManager.unlocked_pokemon.assign([4])
	if StoryManager.recruit_chance(4) < 0.999 or not StoryManager.roll_recruit(4):
		_fail("recruit", "espèce déjà libérée non garantie")
		return
	# Grande rébellion + réputation → meilleure confiance pour une espèce neuve.
	GameManager.unlocked_pokemon.assign(range(1, 30))
	GameManager.champion_badges = ["A", "B", "C"]
	var c1 := StoryManager.recruit_chance(999)
	if c1 <= c0:
		_fail("recruit", "la stature de la rébellion n'améliore pas la confiance (%.2f <= %.2f)" % [c1, c0])
		return
	_pass("recruit", "confiance %d%% → %d%% · libéré = garanti" % [int(c0 * 100), int(c1 * 100)])


## Ouvre le Tableau des Rumeurs, vérifie qu'une mission accomplie se réclame et
## verse bien sa récompense, puis que le tableau se renouvelle sans erreur.
func _scenario_rumors() -> void:
	MissionManager.reset()
	GameManager.unlocked_pokemon = []
	# Pool 0 = « Évasion de la Réserve » : libère 3 Pokémon. Base 0.
	MissionManager._active = [{"pool": 0, "base": 0}]
	if MissionManager.slot(0)["done"]:
		_fail("rumors", "mission accomplie à 0 libéré (base cassée)")
		return
	GameManager.unlocked_pokemon.assign([1, 4, 7])   # 3 libérés → objectif atteint
	if not MissionManager.slot(0)["done"]:
		_fail("rumors", "objectif non atteint à 3 libérés")
		return
	var screen := RumorBoardScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(0.6).timeout
	var gold_before := GameManager.gold
	var got := MissionManager.claim(0)
	if got.is_empty() or GameManager.gold <= gold_before:
		_fail("rumors", "réclamation sans récompense (or %d -> %d)" % [gold_before, GameManager.gold])
		return
	_pass("rumors", "réclamé +%d Baies · %d rumeurs au tableau" % [int(got["gold"]), MissionManager.slot_count()])
	screen.queue_free()


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
	# start_run() ICI, comme les vrais appelants (HubWorld/Net) : CombatArena
	# ne le fait plus lui-même (cf. le fix "map désynchronisée en multi" —
	# la 1re map se génère dans le _ready() du Map enfant, AVANT celui de
	# l'arène). L'override de rooms_cleared doit venir APRÈS, sinon start_run()
	# l'écraserait.
	RunManager.inst().start_run()
	if start_room > 0:
		RunManager.inst().rooms_cleared = start_room
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	# Polling plutôt qu'attente fixe : au premier lancement, le préchargement
	# des espèces passe par le réseau et peut largement dépasser 8 s.
	var scenario := "run" if start_room == 0 else "run_room%d" % start_room
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	# Salle de boss atteinte directement (sans passer par les salles
	# précédentes, comme en jeu réel) : les espèces des compos de champion ne
	# se préchargent qu'EN ARRIÈRE-PLAN (cf. CombatArena._spawn_team, "Phase 2")
	# — en partie réelle, les salles précédentes leur laissent largement le
	# temps de charger ; ici il faut l'attendre explicitement, sans quoi
	# _spawn_from_pool ignore silencieusement les vagues pas encore en cache.
	var wait_s := 6.0 if RunManager.inst().is_boss_room(start_room) else 3.0
	await get_tree().create_timer(wait_s).timeout   # temps de télégraphie des spawns

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


## Un SEUL don de fin de zone à se disputer (retour joueurs : « chaque joueur
## recevait son propre bonus ») — teste directement le garde-fou d'arbitrage
## (_resolve_boon_claim), sans monter une vraie session à 2 pairs : le premier
## "peer" simulé doit réclamer le don (qui disparaît), le second doit être
## refusé silencieusement (pas de 2e don, pas de crash).
func _scenario_boon_claim() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	await get_tree().create_timer(1.0).timeout

	var arena := get_tree().current_scene
	if arena == null:
		_fail("boon_claim", "arène non chargée")
		return
	arena.call("_spawn_boon", RunManager.BONUS_STAT)
	if not is_instance_valid(arena.get("_boon_node")):
		_fail("boon_claim", "don non apparu")
		return

	arena.call("_resolve_boon_claim", 111)   # 1er prétendant
	if not bool(arena.get("_boon_claimed")):
		_fail("boon_claim", "réclamation non enregistrée")
		return
	if is_instance_valid(arena.get("_boon_node")):
		_fail("boon_claim", "le don n'a pas disparu après réclamation")
		return

	arena.call("_resolve_boon_claim", 222)   # 2e prétendant — doit être refusé
	_pass("boon_claim", "1 seul don réclamé, 2e prétendant refusé")


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


## ── Téléchargement complet pour EMBARQUER dans le build (res://data/) ─────
## Réutilise PokemonAPI.prefetch_all() (fiches Pokémon + attaques) et pousse
## PMDSprites.get_walk_sprites() sur TOUTE l'espèce référencée par le jeu
## (walk + Attack/Hurt/Shoot/Charge/Sleep, chargées en arrière-plan par
## PMDSprites lui-même). Une fois le cache utilisateur rempli, on le COPIE
## vers res://data/ — le dossier embarqué que PokemonAPI/PMDSprites lisent en
## PRIORITÉ (cf. _BUNDLED_DIR). Outil de build, pas un test : invoqué à la main
## (`-- download_all`), jamais par tests/smoke.sh.
func _scenario_download_all() -> void:
	print("DL: préchargement fiches Pokémon + attaques…")
	var done := [false]
	PokemonAPI.prefetch_finished.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	PokemonAPI.prefetch_all()
	var waited := 0.0
	while not done[0] and waited < 180.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	print("DL: fiches OK (%.0fs)" % waited)

	var ids: Array[int] = PokemonAPI._all_species_ids()
	print("DL: %d espèces — sprites PMD (marche + actions)…" % ids.size())
	const BATCH := 6
	for i in range(0, ids.size(), BATCH):
		var chunk: Array = ids.slice(i, mini(i + BATCH, ids.size()))
		var remaining := [chunk.size()]
		for id in chunk:
			PMDSprites.get_walk_sprites(id, self, func(_r: Dictionary) -> void: remaining[0] -= 1)
		var w2 := 0.0
		while remaining[0] > 0 and w2 < 20.0:
			await get_tree().create_timer(0.3).timeout
			w2 += 0.3
		# Grâce : Attack/Hurt/Shoot/Charge/Sleep sont lancées en ARRIÈRE-PLAN
		# par PMDSprites dès la marche résolue (pas de signal de fin) — on
		# laisse le temps aux requêtes parallèles de retomber avant la copie.
		await get_tree().create_timer(1.5).timeout
		print("DL: sprites %d/%d" % [mini(i + BATCH, ids.size()), ids.size()])

	print("DL: copie user:// → res://data/ …")
	_copy_dir_recursive("user://cache/pokeapi", "res://data/pokeapi")
	_copy_dir_recursive("user://cache/pmd", "res://data/pmd")
	print("DL: terminé.")
	_pass("download_all", "res://data/ peuplé")


func _copy_dir_recursive(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var s_path := src + "/" + fname
			var t_path := dst + "/" + fname
			if d.current_is_dir():
				_copy_dir_recursive(s_path, t_path)
			else:
				DirAccess.copy_absolute(s_path, t_path)
		fname = d.get_next()
	d.list_dir_end()
