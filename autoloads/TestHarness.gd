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
		elif arg == "smoke_npc_intro_once":
			_run_scenario(_scenario_npc_intro_once)
		elif arg == "smoke_boutique_dialogue":
			_run_scenario(_scenario_boutique_dialogue)
		elif arg == "smoke_freed_pokemon":
			_run_scenario(_scenario_freed_pokemon)
		elif arg == "smoke_boon_claim":
			_run_scenario(_scenario_boon_claim)
		elif arg == "smoke_xp_share":
			_run_scenario(_scenario_xp_share)
		elif arg == "smoke_lobby_item_stats":
			_run_scenario(_scenario_lobby_item_stats)
		elif arg == "smoke_new_bonuses":
			_run_scenario(_scenario_new_bonuses)
		elif arg == "smoke_team_buff":
			_run_scenario(_scenario_team_buff)
		elif arg == "smoke_move_protect":
			_run_scenario(_scenario_move_protect)
		elif arg == "smoke_move_upgrade":
			_run_scenario(_scenario_move_upgrade)
		elif arg == "smoke_los_throttle":
			_run_scenario(_scenario_los_throttle)
		elif arg == "smoke_sprite_occlusion":
			_run_scenario(_scenario_sprite_occlusion)
		elif arg == "smoke_lava_burn":
			_run_scenario(_scenario_lava_burn)
		elif arg == "smoke_portrait_race":
			_run_scenario(_scenario_portrait_race)
		elif arg == "smoke_stats_overlay_item":
			_run_scenario(_scenario_stats_overlay_item)
		elif arg == "smoke_enemy_aggro":
			_run_scenario(_scenario_enemy_aggro)
		elif arg == "smoke_auto_revive":
			_run_scenario(_scenario_auto_revive)
		elif arg == "smoke_cooldown_focus":
			_run_scenario(_scenario_cooldown_focus)
		elif arg == "smoke_pokedex":
			_run_scenario(_scenario_pokedex)
		elif arg == "smoke_gromago_refresh":
			_run_scenario(_scenario_gromago_refresh)
		elif arg == "smoke_pokedex_revive":
			_run_scenario(_scenario_pokedex_revive)
		elif arg == "smoke_pokedex_tabs":
			_run_scenario(_scenario_pokedex_tabs)
		elif arg == "smoke_team_evolve_display":
			_run_scenario(_scenario_team_evolve_display)
		elif arg == "smoke_evolution_popup":
			_run_scenario(_scenario_evolution_popup)
		elif arg == "smoke_pokedex_item_row":
			_run_scenario(_scenario_pokedex_item_row)
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
	# Un précédent smoke_npc_intro_once (même sauvegarde user://save.json,
	# persistante entre lancements headless) peut avoir marqué "pokedex"
	# comme déjà vu — ce test veut spécifiquement l'intro, on la garantit.
	GameManager.seen_npc_intros = {}
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


## Retour joueurs : « les PNJ à service ne doivent parler qu'une fois, puis
## ouvrir le menu directement » (Dracolosse, Porygon…). Réutilise le PNJ
## Pokédex : une 2e interaction, APRÈS que l'intro a déjà été vue une 1re
## fois, doit ouvrir le Pokédex SANS repasser par NpcDialogueScreen.
func _scenario_npc_intro_once() -> void:
	GameManager.is_first_run = false
	if GameManager.hub_team.is_empty():
		GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	GameManager.seen_npc_intros = {}
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
		_fail("npc_intro_once", "HubWorld introuvable")
		return

	var npcs: Array = hw.get("_npcs")
	var pokedex_npc: Node = null
	for n in npcs:
		if n.npc_id == "pokedex":
			pokedex_npc = n
			break
	if pokedex_npc == null:
		_fail("npc_intro_once", "PNJ pokedex introuvable")
		return

	# 1re interaction : intro normale, puis fermeture du Pokédex (marque vu).
	hw.call("_interact", pokedex_npc)
	await get_tree().process_frame
	var dlg := _find_child_by_class(hw, "NpcDialogueScreen")
	if dlg == null:
		_fail("npc_intro_once", "1re interaction : dialogue absent")
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
	await get_tree().create_timer(0.3).timeout
	var pdx: Node = _find_child_by_class(hw, "PokedexScreen")
	if pdx == null:
		_fail("npc_intro_once", "1re interaction : Pokédex jamais ouvert")
		return
	if pdx.has_signal("closed"):
		pdx.emit_signal("closed")
	await get_tree().create_timer(0.3).timeout

	if not GameManager.has_seen_npc_intro("pokedex"):
		_fail("npc_intro_once", "l'intro n'a pas été marquée comme vue")
		return

	# 2e interaction : DOIT sauter le dialogue et ouvrir le Pokédex direct.
	hw.call("_interact", pokedex_npc)
	await get_tree().process_frame
	if _find_child_by_class(hw, "NpcDialogueScreen") != null:
		_fail("npc_intro_once", "2e interaction : le dialogue s'est rejoué")
		return
	if _find_child_by_class(hw, "PokedexScreen") == null:
		_fail("npc_intro_once", "2e interaction : le Pokédex ne s'est pas ouvert directement")
		return
	_pass("npc_intro_once", "intro jouée une fois, menu direct ensuite")


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


## Recherche récursive (toute la sous-arborescence) d'un Label dont le texte
## CONTIENT `needle` — utilisé pour vérifier qu'une valeur affichée est bien
## celle attendue sans dépendre d'un chemin de nœud précis.
func _find_label_with_text(node: Node, needle: String) -> Label:
	if node is Label and needle in (node as Label).text:
		return node
	for c in node.get_children():
		var found := _find_label_with_text(c, needle)
		if found != null:
			return found
	return null


## Même principe que _find_label_with_text, mais pour un Button dont le texte
## est EXACTEMENT `text` (les steppers +/− du Pokédex n'ont qu'un caractère).
func _find_button_with_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var found := _find_button_with_text(c, text)
		if found != null:
			return found
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


## Retour joueurs : « le Bazar de Gromago se ferme et se rouvre violemment
## après un achat ». _rebuild() détruisait tout l'écran (voile, cadre,
## bannière — dont l'anim pop_in rejouée à chaque achat) ; vérifie que
## _panel reste la MÊME instance après un achat (rafraîchi en place,
## cf. GromagoShopScreen._refresh_cards) et que le compteur "×N" suit.
func _scenario_gromago_refresh() -> void:
	GameManager.gold           = 999999
	GameManager.item_inventory = {}
	var screen := GromagoShopScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel_before: Node = screen.get("_panel")
	if panel_before == null:
		_fail("gromago_refresh", "panneau introuvable")
		screen.queue_free()
		return

	var buy := _find_button_with_text(screen, "Acheter")
	if buy == null:
		_fail("gromago_refresh", "bouton Acheter introuvable")
		screen.queue_free()
		return
	buy.pressed.emit()
	await get_tree().process_frame

	var panel_after: Node = screen.get("_panel")
	if panel_after != panel_before or not is_instance_valid(panel_before):
		_fail("gromago_refresh", "le panneau a été détruit/recréé après l'achat")
		screen.queue_free()
		return

	if _find_label_with_text(screen, "×1") == null:
		_fail("gromago_refresh", "compteur ×1 non affiché après l'achat")
		screen.queue_free()
		return

	_pass("gromago_refresh", "achat rafraîchi en place, panneau non détruit")
	screen.queue_free()


## Retour joueurs : « pouvoir équiper des Rappels, ça coûte du poids ». Ouvre
## le Pokédex, sélectionne le starter et presse le "+" du stepper de rappels
## (cf. PokedexScreen._build_revive_row) : vérifie que GameManager.
## pokemon_revives change ET que le poids d'équipe affiché suit.
func _scenario_pokedex_revive() -> void:
	var pid: int = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [pid]
	GameManager.set_assigned_revives(pid, 0)
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.5).timeout

	screen.call("_select", pid)
	await get_tree().process_frame
	await get_tree().process_frame

	var w_before := GameManager.compute_team_weight()
	var plus := _find_button_with_text(screen, "+")
	if plus == null:
		_fail("pokedex_revive", "bouton + du stepper introuvable")
		screen.queue_free()
		return
	plus.pressed.emit()
	await get_tree().process_frame

	if GameManager.get_assigned_revives(pid) != 1:
		_fail("pokedex_revive", "le + n'a pas incrémenté la charge (eu %d)" % GameManager.get_assigned_revives(pid))
		screen.queue_free()
		return
	var w_after := GameManager.compute_team_weight()
	if w_after - w_before != GameManager.REVIVE_WEIGHT:
		_fail("pokedex_revive", "poids d'équipe non mis à jour (%d -> %d)" % [w_before, w_after])
		screen.queue_free()
		return

	var minus := _find_button_with_text(screen, "−")
	if minus == null:
		_fail("pokedex_revive", "bouton − du stepper introuvable")
		screen.queue_free()
		return
	minus.pressed.emit()
	await get_tree().process_frame
	if GameManager.get_assigned_revives(pid) != 0:
		_fail("pokedex_revive", "le − n'a pas décrémenté la charge (eu %d)" % GameManager.get_assigned_revives(pid))
		screen.queue_free()
		return

	_pass("pokedex_revive", "stepper +/− : charge et poids d'équipe à jour")
	screen.queue_free()


## Retour joueurs : « réorganiser les onglets pour que tout soit visible » —
## "Débloqués (140)"/"À débloquer (12)" débordait de son bouton dans une
## colonne de 456px partagée par 4 onglets. Le compte est passé en infobulle ;
## vérifie que le texte du bouton ne contient plus de parenthèses (donc plus
## court) et que le compte reste consultable via tooltip_text.
func _scenario_pokedex_tabs() -> void:
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.5).timeout

	var tabs: Array = screen.get("_tab_buttons")
	if tabs.is_empty():
		_fail("pokedex_tabs", "aucun onglet construit")
		screen.queue_free()
		return
	for b: Button in tabs:
		if "(" in b.text or ")" in b.text:
			_fail("pokedex_tabs", "le texte de l'onglet déborde encore avec un compte inline : %s" % b.text)
			screen.queue_free()
			return
		if not b.tooltip_text.ends_with("Pokémon"):
			_fail("pokedex_tabs", "le compte n'est pas exposé en infobulle : %s" % b.tooltip_text)
			screen.queue_free()
			return
	_pass("pokedex_tabs", "%d onglets, libellés courts, compte en infobulle" % tabs.size())
	screen.queue_free()


## Retour joueurs : « afficher le niveau de base » + « si un Bonbon fait
## dépasser le niveau d'évolution, il doit se transformer » (ex. Pikachu
## nv.20 → Raichu). Pikachu (STARTER_IDS[0]=25) évolue à 20 ; base 10 +
## 2 Bonbons (+5 chacun) = 20, pile le seuil. Vérifie que get_effective_start
## calcule bien l'évolution ET que le niveau effectif est affiché sur le
## carré d'équipe (cf. PokedexScreen._refresh_team_strip).
func _scenario_team_evolve_display() -> void:
	var pid := 25   # Pikachu — cf. GameManager.EVOLUTIONS: {"level": 20, "evolves_to": 26}
	GameManager.hub_team = [pid]
	GameManager.start_level_bonus.erase(pid)
	GameManager.item_inventory["rare-candy"] = 2
	if not GameManager.use_candy(pid) or not GameManager.use_candy(pid):
		_fail("team_evolve_display", "les Super Bonbons n'ont pas pu être consommés")
		return
	if GameManager.get_start_level_bonus(pid) < 10:
		_fail("team_evolve_display", "bonus de niveau non appliqué (%d)" % GameManager.get_start_level_bonus(pid))
		return

	var eff := GameManager.get_effective_start(pid, GameManager.BASE_TEAM_LEVEL)
	if int(eff["id"]) != 26 or int(eff["level"]) != 20:
		_fail("team_evolve_display", "get_effective_start ne calcule pas l'évolution (id=%s niveau=%s)"
			% [eff["id"], eff["level"]])
		return

	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.5).timeout
	screen.call("_refresh_team_strip")
	await get_tree().process_frame

	if _find_label_with_text(screen, "Nv 20") == null:
		_fail("team_evolve_display", "niveau effectif (Nv 20) non affiché sur le carré d'équipe")
		screen.queue_free()
		return
	_pass("team_evolve_display", "Pikachu nv.10+2 Bonbons → évolution Raichu nv.20 calculée et affichée")
	screen.queue_free()


## Retour joueurs : « en cliquant sur le sprite animé d'un Pokémon, ouvrir
## une pop-up affichant toutes ses évolutions possibles ». Ouvre la pop-up
## depuis Florizarre (#3, DERNIER maillon) : vérifie que la chaîne remonte
## bien jusqu'à Bulbizarre (#1, la racine) au lieu de ne montrer que
## Florizarre lui-même (cf. PokedexScreen._evolution_chain).
func _scenario_evolution_popup() -> void:
	GameManager.unlocked_pokemon = [1, 2, 3]
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.5).timeout

	var chain: Array = screen.call("_evolution_chain", 3)
	if chain != [1, 2, 3]:
		_fail("evolution_popup", "chaîne incorrecte pour Florizarre (attendu [1,2,3], eu %s)" % [chain])
		screen.queue_free()
		return

	screen.call("_open_evolution_popup", 3)
	await get_tree().process_frame
	await get_tree().process_frame

	var popup: Node = screen.get("_evo_popup")
	if popup == null or not is_instance_valid(popup):
		_fail("evolution_popup", "la pop-up ne s'est pas ouverte")
		screen.queue_free()
		return
	if _find_label_with_text(popup, "BULBIZARRE") == null:
		_fail("evolution_popup", "1er maillon (Bulbizarre) absent de la pop-up")
		popup.queue_free()
		screen.queue_free()
		return
	if _find_label_with_text(popup, "Niv.16") == null:
		_fail("evolution_popup", "niveau d'évolution absent de la pop-up")
		popup.queue_free()
		screen.queue_free()
		return

	_pass("evolution_popup", "chaîne complète (3 formes) affichée depuis n'importe quel maillon")
	screen.queue_free()


## Retour joueurs : « supprimer les textes inutiles (ex : 'objet 2.', 'ESP 3.
## objet')… afficher uniquement le sprite, le nom, et une description claire
## de son effet ». La ligne d'objet tenu du Pokédex mélangeait le nom de
## l'objet ET le bonus de Super Bonbon dans un seul libellé "Objet : Nom ·
## Départ +N niv" — vérifie que le nom seul apparaît, avec sa description,
## sans ce préfixe/concaténation.
func _scenario_pokedex_item_row() -> void:
	var pid: int = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [pid]
	if not (pid in GameManager.unlocked_pokemon):
		GameManager.unlocked_pokemon.append(pid)
	GameManager.item_inventory["choice-band"] = 1
	GameManager.assign_item(pid, "choice-band")   # ItemCatalog : "Bandeau Choix", desc "+50% Attaque."
	var screen := PokedexScreen.new()
	get_tree().root.add_child(screen)
	await get_tree().create_timer(2.5).timeout
	screen.call("_select", pid)
	await get_tree().process_frame

	if _find_label_with_text(screen, "Objet :") != null:
		_fail("pokedex_item_row", "le préfixe 'Objet :' concaténé subsiste")
		screen.queue_free()
		return
	if _find_label_with_text(screen, "Bandeau Choix") == null:
		_fail("pokedex_item_row", "le nom de l'objet tenu n'est pas affiché")
		screen.queue_free()
		return
	if _find_label_with_text(screen, "+50% Attaque") == null:
		_fail("pokedex_item_row", "la description de l'effet n'est pas affichée")
		screen.queue_free()
		return
	_pass("pokedex_item_row", "nom + description seuls, sans concaténation parasite")
	screen.queue_free()


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


## Partage d'XP entre coéquipiers (retour joueurs : « si un Pokémon attaque un
## ennemi et que le partenaire l'achève, les deux doivent recevoir de l'XP »).
## Vérifie que EnemyAI accumule bien TOUS les peer_id ayant frappé (et pas
## seulement le dernier) — la distribution réseau elle-même (RPC vers chaque
## pair) n'est pas rejouée ici, seule la donnée qu'elle diffuse l'est.
func _scenario_xp_share() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("enemies").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		_fail("xp_share", "aucun ennemi apparu")
		return

	var e: Node = enemies[0]
	e.call("take_damage", 1, Vector3.INF, Color.WHITE, 111, null)
	e.call("take_damage", 1, Vector3.INF, Color.WHITE, 222, null)
	var peers: Dictionary = e.get("_damaging_peers")
	if not (peers.has(111) and peers.has(222)):
		_fail("xp_share", "assistants non cumulés (%s)" % [peers])
		return
	_pass("xp_share", "2 assistants cumulés sur le même ennemi")


## Retour joueurs : « dans le menu personnage en ligne, les stats doivent se
## mettre à jour instantanément quand on équipe un objet » — jusque là, le
## panneau du lobby multijoueur affichait TOUJOURS les stats de base, sans
## jamais tenir compte de l'objet tenu choisi. Vérifie qu'équiper un objet à
## effet connu (Bandeau Choix, +50% Attaque) fait apparaître la valeur
## boostée dans le panneau, sans passer par une vraie session réseau.
func _scenario_lobby_item_stats() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	var screen := MultiplayerLobbyScreen.new()
	get_tree().root.add_child(screen)
	screen._mode   = "lobby"
	screen._my_pid = GameManager.STARTER_IDS[0]
	var waited := 0.0
	while not (screen._data_cache.get(screen._my_pid, {}) as Dictionary).has("pd") and waited < 10.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var pd: PokemonData = (screen._data_cache.get(screen._my_pid, {}) as Dictionary).get("pd")
	if pd == null:
		_fail("lobby_item_stats", "PokemonData non chargée")
		screen.queue_free()
		return

	var base_atk := pd.attack
	screen._my_item = "choice-band"   # ItemCatalog : effect=atk, mult=1.5
	screen._rebuild()
	await get_tree().create_timer(0.3).timeout

	var expected := int(round(float(base_atk) * 1.5))
	var lbl := _find_label_with_text(screen, "%d ↑" % expected)
	if lbl == null:
		_fail("lobby_item_stats", "stat boostée non affichée (attendu %d ↑, base %d)" % [expected, base_atk])
		screen.queue_free()
		return
	_pass("lobby_item_stats", "Attaque %d → %d ↑ (Bandeau Choix)" % [base_atk, expected])
	screen.queue_free()


## Nouveaux bonus/objets (retour joueurs) : split physique/spécial dans
## DamageCalculator (Atq./Déf. Spé enfin lues en combat), critique garanti à
## 100%, esquive garantie à 100%, et 3 dons DISTINCTS tirés au hasard (pas
## toujours le même bloc de 4/9).
func _scenario_new_bonuses() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("new_bonuses", "équipe non apparue")
		return
	var victim: Node = players[0]
	var attacker: PokemonInstance = victim.get("pokemon_instance")

	# 1) Split physique/spécial : Atq. Spé influe sur get_effective_sp_attack(),
	# jamais sur get_effective_attack() — jusqu'ici la classe du move était
	# ignorée par DamageCalculator (les 2 stats utilisaient TOUJOURS Attaque).
	# Comparaison sur les GETTERS (déterministes) plutôt que sur calculate(),
	# qui inclut une variance aléatoire (0.85-1.0) : deux appels successifs
	# peuvent légitimement différer même sans changement réel, ce qui rendrait
	# ce test bruité pour rien.
	var atk_base := attacker.get_effective_attack()
	var spatk_base := attacker.get_effective_sp_attack()
	attacker.sp_attack_mult = 3.0
	if attacker.get_effective_attack() != atk_base:
		_fail("new_bonuses", "Atq. Spé influence get_effective_attack() (ne devrait pas)")
		attacker.sp_attack_mult = 1.0
		return
	var spatk_boosted := attacker.get_effective_sp_attack()
	if spatk_boosted <= spatk_base:
		_fail("new_bonuses", "Atq. Spé x3 n'augmente pas get_effective_sp_attack() (%d vs base %d)" % [spatk_boosted, spatk_base])
		attacker.sp_attack_mult = 1.0
		return
	# calculate("special") doit tourner sans erreur avec cette paire de stats.
	var special_dmg: int = DamageCalculator.calculate(attacker, attacker, 60, "normal", "special")["damage"]
	attacker.sp_attack_mult = 1.0
	if special_dmg <= 0:
		_fail("new_bonuses", "calculate('special') n'a rien retourné")
		return

	# 2) Critique garanti
	attacker.crit_chance = 1.0
	var r: Dictionary = DamageCalculator.calculate(attacker, attacker, 60, "normal", "physical")
	attacker.crit_chance = 0.0
	if not r["crit"]:
		_fail("new_bonuses", "crit_chance=1.0 n'a pas critiqué")
		return

	# 3) Esquive garantie — take_damage() doit renvoyer false et ne rien retirer
	var hp_before := attacker.current_hp
	attacker.dodge_chance = 1.0
	var landed: bool = victim.call("take_damage", 10)
	attacker.dodge_chance = 0.0
	if landed or attacker.current_hp != hp_before:
		_fail("new_bonuses", "dodge_chance=1.0 n'a pas empêché les dégâts")
		return

	# 4) 3 dons DISTINCTS tirés du bassin (retour joueurs : « 3, pas 4/9 systématiques »)
	var arena := get_tree().current_scene
	var offer: Array = arena.call("_roll_stat_boon_offer")
	if offer.size() != 3:
		_fail("new_bonuses", "l'offre de dons ne fait pas 3 (%d)" % offer.size())
		return
	var ids: Dictionary = {}
	for o: Dictionary in offer:
		ids[o["id"]] = true
	if ids.size() != 3:
		_fail("new_bonuses", "doublons dans l'offre de dons (%s)" % [offer])
		return

	_pass("new_bonuses", "split phys./spé. OK · critique garanti OK · esquive garantie OK · 3 dons distincts OK")


## Retour joueurs : « afficher les boosts de stats au-dessus du Pokémon, de
## manière cumulable » + « attaques de zone pour buffer ses alliés » —
## Danse-Lames/Méditation ne faisaient jusqu'ici RIEN à l'usage (aucun
## `effect` déclaré). Vérifie apply_buff() : la stat augmente, l'étiquette
## devient visible, et deux boosts simultanés se CUMULENT dans le texte
## (pas juste le dernier qui écrase l'affichage).
func _scenario_team_buff() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("team_buff", "équipe non apparue")
		return
	var member: Node = players[0]
	var inst: PokemonInstance = member.get("pokemon_instance")

	var atk_before := inst.attack_mult
	member.call("apply_buff", "atk", 1.5, 8.0)
	if inst.attack_mult <= atk_before:
		_fail("team_buff", "apply_buff('atk') n'a pas augmenté attack_mult")
		return
	var lbl: Label3D = member.get("_buff_lbl")
	if lbl == null or not lbl.visible or "ATT" not in lbl.text:
		_fail("team_buff", "étiquette de boost absente/invisible après apply_buff")
		return

	# Cumul : un 2e boost sur une AUTRE stat doit s'AJOUTER au texte, pas le remplacer.
	member.call("apply_buff", "spatk", 1.4, 8.0)
	if "ATT" not in lbl.text or "ASP" not in lbl.text:
		_fail("team_buff", "les boosts ne se cumulent pas dans l'étiquette (texte: %s)" % lbl.text)
		return

	_pass("team_buff", "boost appliqué + étiquette cumulable : %s" % lbl.text)


## Retour joueurs : « Protection doit indiquer 'Se protège' et fonctionner
## in-game » — la CT (power=0, damage_class="status") n'avait aucun `effect`
## déclaré, donc ne faisait RIEN à l'usage. Vérifie que _use_status_move
## (kind="protect") arme la fenêtre de protection ET que take_damage()
## bloque bien tout coup pendant cette fenêtre (PV inchangés, coup refusé).
func _scenario_move_protect() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("move_protect", "équipe non apparue")
		return
	var member: Node = players[0]
	var inst: PokemonInstance = member.get("pokemon_instance")

	var protect_move: MoveData = null
	for m: Dictionary in MoveShopScreen.MOVE_LIST:
		if str(m.get("api", "")) == "protect":
			var md := MoveData.new()
			md.api_name     = "protect"
			md.display_name = str(m["label"])
			md.type         = str(m["type"])
			md.power        = 0
			md.damage_class = "status"
			md.effect       = m["effect"]
			protect_move = md
			break
	if protect_move == null:
		_fail("move_protect", "CT Protection introuvable dans MoveShopScreen.MOVE_LIST")
		return

	member.call("_use_status_move", protect_move)
	var hp_before := inst.current_hp
	var landed: bool = member.call("take_damage", 999999)
	if landed:
		_fail("move_protect", "le coup a porté malgré la Protection active")
		return
	if inst.current_hp != hp_before:
		_fail("move_protect", "PV modifiés malgré la Protection (%d -> %d)" % [hp_before, inst.current_hp])
		return
	_pass("move_protect", "Protection bloque bien tout coup pendant sa fenêtre")


## Retour joueurs : « avoir vraiment plus de choix, pouvoir donner des bonus
## d'attaque aux attaques déjà existantes… rendre la capacité plus puissante
## au lieu de toujours donner de nouvelles attaques ». Vérifie que
## _roll_move_offers propose bien une offre "upgrade" pour une attaque déjà
## équipée, et que la réclamer (_apply_move_upgrade) augmente sa puissance.
func _scenario_move_upgrade() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("move_upgrade", "équipe non apparue")
		return
	var member: Node = players[0]
	var inst: PokemonInstance = member.get("pokemon_instance")
	if inst.equipped_moves.is_empty():
		_fail("move_upgrade", "aucune attaque équipée à tester")
		return

	var arena := get_tree().current_scene
	var offers: Array = arena.call("_roll_move_offers", inst)
	var upgrade_offer: Dictionary = {}
	for o: Dictionary in offers:
		if str(o.get("kind", "")) == "upgrade":
			upgrade_offer = o
			break
	if upgrade_offer.is_empty():
		_fail("move_upgrade", "aucune offre de renfort proposée (offres: %s)" % [offers])
		return

	var idx := int(upgrade_offer["target_idx"])
	var md: MoveData = inst.equipped_moves[idx]
	var power_before := md.power
	arena.call("_apply_move_upgrade", member, idx)
	if md.power <= power_before or md.upgrade_count != 1:
		_fail("move_upgrade", "le renfort n'a pas augmenté la puissance (%d -> %d, count=%d)"
			% [power_before, md.power, md.upgrade_count])
		return
	_pass("move_upgrade", "%s renforcée : Puiss. %d → %d" % [md.display_name, power_before, md.power])


## Retour joueurs : « on ne voit pas les sprites derrière des décors 3D » —
## un obstacle placé PILE entre la caméra et le joueur doit déclencher
## l'occlusion (sprite semi-transparent, alpha-blend réactivé) ; le retirer
## doit la lever (retour au rendu opaque normal).
func _scenario_sprite_occlusion() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("sprite_occlusion", "équipe non apparue")
		return
	var member: Node = players[0]
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_fail("sprite_occlusion", "aucune caméra active")
		return

	# Aucun obstacle : pas d'occlusion.
	member.set("_occlusion_timer", 0.0)
	member.call("_update_sprite_occlusion", 0.0)
	if bool(member.get("_sprite_occluded")):
		_fail("sprite_occlusion", "occlusion signalée sans aucun obstacle sur le trajet")
		return

	# Obstacle massif planté au milieu du segment caméra → joueur (layer 1,
	# même couche que les colliders d'arbres/rochers de MapRender3D).
	var member_pos: Vector3 = member.get("global_position")
	var mid: Vector3 = (cam.global_position + member_pos) * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 6)
	cs.shape = box
	body.add_child(cs)
	get_tree().current_scene.add_child(body)
	body.global_position = mid
	await get_tree().physics_frame
	await get_tree().physics_frame

	member.set("_occlusion_timer", 0.0)
	member.call("_update_sprite_occlusion", 0.0)
	if not bool(member.get("_sprite_occluded")):
		_fail("sprite_occlusion", "obstacle massif entre caméra et joueur non détecté")
		body.queue_free()
		return
	var sprite: Node = member.get("sprite")
	if sprite.get("alpha_cut") != SpriteBase3D.ALPHA_CUT_DISABLED:
		_fail("sprite_occlusion", "alpha_cut pas repassé en blend pendant l'occlusion")
		body.queue_free()
		return

	body.queue_free()
	await get_tree().process_frame
	member.set("_occlusion_timer", 0.0)
	member.call("_update_sprite_occlusion", 0.0)
	if bool(member.get("_sprite_occluded")):
		_fail("sprite_occlusion", "occlusion persiste après retrait de l'obstacle")
		return

	_pass("sprite_occlusion", "occlusion détectée avec obstacle, levée sans")


## Retour joueurs : « la lave doit être marchable, dégâts sauf en Sprint ».
## Force une run sur le biome Volcan (RunManager.test_biome_override), place
## le joueur sur une case de lave (aucune collision ne doit l'en empêcher,
## cf. MapRender3D._build_water_collision) et vérifie que _update_lava_burn
## l'enflamme normalement, mais PAS pendant une ruée (TeamMember._dash_timer).
func _scenario_lava_burn() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().test_biome_override = MapGenerator.MapTheme.VOLCANO
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("lava_burn", "équipe non apparue")
		RunManager.inst().test_biome_override = -1
		return
	var member: Node = players[0]
	var arena := get_tree().current_scene
	var map: Node = arena.get("_map")
	if map == null or not map.has_method("is_water_cell"):
		_fail("lava_burn", "carte du volcan indisponible")
		RunManager.inst().test_biome_override = -1
		return

	var lava_cell := Vector2i(-1, -1)
	var size: Vector2i = map.call("get_map_cell_size")
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if map.call("is_water_cell", c):
				lava_cell = c
				break
		if lava_cell.x >= 0:
			break
	if lava_cell.x < 0:
		_fail("lava_burn", "aucune case de lave générée (thème volcan forcé)")
		RunManager.inst().test_biome_override = -1
		return

	var inst: PokemonInstance = member.get("pokemon_instance")
	inst.clear_status()
	member.global_position = map.call("cell_to_world3", lava_cell)
	arena.call("_update_lava_burn")
	if inst.status != "burn":
		_fail("lava_burn", "pas de brûlure en marchant sur la lave (statut: %s)" % inst.status)
		RunManager.inst().test_biome_override = -1
		return

	inst.clear_status()
	member.set("_dash_timer", 0.5)
	arena.call("_update_lava_burn")
	if inst.status == "burn":
		_fail("lava_burn", "brûlure appliquée malgré une ruée (Sprint) en cours")
		RunManager.inst().test_biome_override = -1
		return

	RunManager.inst().test_biome_override = -1
	_pass("lava_burn", "brûlure sur la lave, aucune pendant une ruée")


## Retour joueurs : « ça lag beaucoup en run, j'ai peur que ce soit pire en
## coop ». EnemyAI faisait un raycast physique de ligne de vue à CHAQUE
## frame, pour CHAQUE ennemi (60×/s) — throttlé depuis à ~7×/s
## (LOS_CHECK_INTERVAL). Vérifie indirectement le throttle : un 2e appel
## juste après le 1er ne doit PAS redéclencher de raycast (le minuteur décroît
## depuis sa valeur précédente au lieu d'être réarmé à chaque frame).
func _scenario_los_throttle() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("enemies").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		_fail("los_throttle", "aucun ennemi apparu")
		return

	var e: Node = enemies[0]
	var target: Vector3 = e.global_position + Vector3(1.0, 0, 0)
	e.call("_get_steer_target", target, 0.01)
	var timer_after_first: float = e.get("_los_check_timer")
	if timer_after_first <= 0.0:
		_fail("los_throttle", "le minuteur de vérification LOS n'a pas été réarmé")
		return

	e.call("_get_steer_target", target, 0.01)
	var timer_after_second: float = e.get("_los_check_timer")
	if timer_after_second >= timer_after_first:
		_fail("los_throttle", "le minuteur ne décroît pas — la vue est revérifiée à chaque appel")
		return
	_pass("los_throttle", "vérification LOS throttlée (%.3f -> %.3f)" % [timer_after_first, timer_after_second])


## Retour joueurs : « on ne voit pas les sprites des pokemons en run ».
## Cause : TeamMember.setup() (qui charge le sprite PMD) était appelé AVANT
## que CombatArena connecte portrait_ready — si le sprite est DÉJÀ en cache
## mémoire (PMDSprites._cache, cas fréquent : le joueur a vu son starter au
## Hub/Pokédex avant de lancer la run), le callback est SYNCHRONE et le tout
## premier portrait_ready partait dans le vide, portrait_texture restant null
## pour toute la run. Reproduit la course : préchauffe le cache PMD du
## starter AVANT de lancer la run (comme un vrai passage au Pokédex), puis
## vérifie que le portrait se peuple quand même.
func _scenario_portrait_race() -> void:
	GameManager.is_first_run = false
	var starter: int = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [starter]

	var warmed := [false]
	PMDSprites.get_walk_sprites(starter, self, func(_r: Dictionary) -> void: warmed[0] = true)
	var warm_wait := 0.0
	while not warmed[0] and warm_wait < 10.0:
		await get_tree().create_timer(0.2).timeout
		warm_wait += 0.2
	if not warmed[0]:
		_fail("portrait_race", "préchauffage du sprite PMD du starter échoué")
		return

	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("portrait_race", "équipe non apparue")
		return
	await get_tree().create_timer(0.3).timeout   # laisse passer 1-2 frames après le spawn

	var inst: PokemonInstance = players[0].get("pokemon_instance")
	if not is_instance_valid(inst.portrait_texture):
		_fail("portrait_race", "portrait_texture toujours vide (cache PMD pourtant préchauffé)")
		return
	var arena := get_tree().current_scene
	var hud_node: Node = arena.get("hud")
	var card_tex: Texture2D = (hud_node.get("_team_cards")[0] as Dictionary).get("portrait").texture
	if not is_instance_valid(card_tex):
		_fail("portrait_race", "la case d'équipe du HUD n'a pas reçu le portrait")
		return
	_pass("portrait_race", "portrait peuplé malgré un cache PMD préchauffé (course évitée)")


## Retour joueurs : « on ne voit pas l'objet associé au poke quand on veut
## voir tous les stats avec sa description et son bonus ». TeamStatsOverlay
## (touche Tab) lisait held_item["name_fr"]/["api_name"] — des clés qui
## n'ont JAMAIS existé dans ItemCatalog (toujours "name"/"api"/"desc") : le
## nom retombait systématiquement sur "?", sans aucune description.
func _scenario_stats_overlay_item() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("stats_overlay_item", "équipe non apparue")
		return
	var inst: PokemonInstance = players[0].get("pokemon_instance")
	inst.equip_catalog_item("choice-band")   # ItemCatalog : "Bandeau Choix", +50% Attaque.

	var overlay := TeamStatsOverlay.new()
	get_tree().root.add_child(overlay)
	overlay.setup(players)
	await get_tree().process_frame

	var name_lbl := _find_label_with_text(overlay, "Bandeau Choix")
	if name_lbl == null:
		_fail("stats_overlay_item", "nom de l'objet absent (\"?\" par défaut ?)")
		overlay.queue_free()
		return
	var desc_lbl := _find_label_with_text(overlay, "+50% Attaque")
	if desc_lbl == null:
		_fail("stats_overlay_item", "description/bonus de l'objet non affichée")
		overlay.queue_free()
		return
	_pass("stats_overlay_item", "nom + description de l'objet affichés")
	overlay.queue_free()


## Retour joueurs : « les ennemis doivent attendre d'être provoqués/aggro, et
## ne pas tous attaquer en même temps ». Un ennemi SAUVAGE (pas un champion —
## ceux-là restent engagés dès l'arrivée, cf. setup()) doit rester immobile
## tant qu'aucun joueur n'entre dans AGGRO_RANGE ou ne le frappe.
func _scenario_enemy_aggro() -> void:
	GameManager.is_first_run = false
	GameManager.hub_team = [GameManager.STARTER_IDS[0]]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("enemies").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var enemies := get_tree().get_nodes_in_group("enemies")
	var players := get_tree().get_nodes_in_group("players")
	if enemies.is_empty() or players.is_empty():
		_fail("enemy_aggro", "ennemis ou équipe non apparus")
		return

	var e: Node = null
	for cand in enemies:
		if not bool(cand.get("is_champion")):
			e = cand
			break
	if e == null:
		_fail("enemy_aggro", "aucun ennemi sauvage (non champion) trouvé")
		return
	var player: Node = players[0]

	# Loin de tout joueur, délai de réveil déjà écoulé : doit rester passif.
	e.set("_aggro", false)
	e.set("_wake_delay", 0.0)
	e.global_position = player.global_position + Vector3(500, 0, 0)
	await get_tree().create_timer(0.3).timeout
	if bool(e.get("_aggro")):
		_fail("enemy_aggro", "un ennemi loin de tout joueur s'est aggro tout seul")
		return

	# À portée d'un joueur : doit s'aggro à la prochaine frame physique.
	e.global_position = player.global_position + Vector3(2.0, 0, 0)
	await get_tree().create_timer(0.3).timeout
	if not bool(e.get("_aggro")):
		_fail("enemy_aggro", "un ennemi à portée (AGGRO_RANGE) ne s'est pas aggro")
		return

	# Être frappé aggro INSTANTANÉMENT, même loin de tout joueur.
	e.set("_aggro", false)
	e.global_position = player.global_position + Vector3(500, 0, 0)
	e.call("take_damage", 1)
	if not bool(e.get("_aggro")):
		_fail("enemy_aggro", "take_damage() ne force pas l'aggro")
		return

	_pass("enemy_aggro", "idle hors de portée, aggro à portée ET sur dégâts")


## Retour joueurs : « pouvoir équiper des Rappels (façon Hades), coûtant du
## poids, et pouvoir les partager avec ses partenaires ». Vérifie le coût en
## poids (GameManager.compute_team_weight), l'auto-ranimation avec charge
## propre (au lieu de tomber K.O.), et le partage via le pool réseau
## (Net.consume_team_revive) une fois la charge propre épuisée.
func _scenario_auto_revive() -> void:
	GameManager.is_first_run = false
	var pid: int = GameManager.STARTER_IDS[0]
	GameManager.hub_team = [pid]
	GameManager.set_assigned_revives(pid, 0)

	var weight_without := GameManager.compute_team_weight()
	GameManager.set_assigned_revives(pid, 1)
	var weight_with := GameManager.compute_team_weight()
	if weight_with - weight_without != GameManager.REVIVE_WEIGHT:
		_fail("auto_revive", "coût en poids incorrect (%d -> %d, attendu +%d)"
			% [weight_without, weight_with, GameManager.REVIVE_WEIGHT])
		return

	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
	var waited := 0.0
	while get_tree().get_nodes_in_group("players").is_empty() and waited < 18.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		_fail("auto_revive", "équipe non apparue")
		return
	var member: Node = players[0]
	var inst: PokemonInstance = member.get("pokemon_instance")
	if inst.revive_charges != 1:
		_fail("auto_revive", "charge équipée non assignée au spawn (attendu 1, eu %d)" % inst.revive_charges)
		return

	# Coup fatal : la charge propre doit absorber le K.O.
	var landed: bool = member.call("take_damage", 999999)
	if not landed:
		_fail("auto_revive", "coup esquivé, test non concluant (relancer)")
		return
	if inst.is_fainted():
		_fail("auto_revive", "K.O. malgré une charge de rappel équipée")
		return
	if inst.revive_charges != 0:
		_fail("auto_revive", "charge propre non consommée (%d restante(s))" % inst.revive_charges)
		return
	if not member.is_in_group("players"):
		_fail("auto_revive", "le membre a quitté le groupe 'players' malgré le rappel")
		return

	# Charge propre épuisée : doit maintenant piocher dans le pool partagé.
	var pool_before: int = Net.team_revive_pool
	if pool_before <= 0:
		_pass("auto_revive", "charge propre consommée, K.O. évité (pool partagé vide, non testé)")
		return
	member.call("take_damage", 999999)
	if inst.is_fainted():
		_fail("auto_revive", "K.O. alors que le pool d'équipe partagé n'était pas vide")
		return
	if Net.team_revive_pool != pool_before - 1:
		_fail("auto_revive", "pool partagé non décrémenté (%d -> %d)" % [pool_before, Net.team_revive_pool])
		return

	_pass("auto_revive", "charge propre puis pool partagé consommés, K.O. évité les deux fois")


## Retour joueurs : « le cooldown visuel se fige si on change de focus dans
## le menu d'attaque, bloquant faussement l'attaque » + « ajouter une croix
## quand on ne peut pas enchaîner, le cooldown n'est pas toujours visible ».
## Force un slot en pleine recharge puis simule un changement de focus vers
## ce slot (comme une pression de touche 1-4) : le HUD doit refléter
## l'indisponibilité IMMÉDIATEMENT (voile + croix), sans attendre le
## prochain _physics_process.
func _scenario_cooldown_focus() -> void:
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
	var team: Array = get_tree().get_nodes_in_group("players")
	if arena == null or team.is_empty():
		_fail("cooldown_focus", "arène/équipe non prête")
		return
	var member: Node = team[0]

	var cds: PackedFloat32Array = member.get("_move_cd")
	var cd_max: PackedFloat32Array = member.get("_move_cd_max")
	cds[1] = 999.0
	cd_max[1] = 1.0
	member.set("_move_cd", cds)
	member.set("_move_cd_max", cd_max)
	member.move_selected.emit(1)   # simule la touche "2" (slot d'index 1)

	var hud_node = arena.get("hud")
	var slots: Array = hud_node.get("_move_slots")
	if slots.size() < 2:
		_fail("cooldown_focus", "moins de 2 cases de capacité")
		return
	var slot1: Dictionary = slots[1]
	var cross: Label = slot1.get("cross")
	var cd_rect: ColorRect = slot1.get("cd")
	if cross == null or not cross.visible:
		_fail("cooldown_focus", "croix d'indisponibilité absente après le changement de focus")
		return
	if cd_rect == null or cd_rect.size.y <= 0.0:
		_fail("cooldown_focus", "voile de cooldown non mis à jour (h=%s)" % [cd_rect.size.y if cd_rect else "?"])
		return
	_pass("cooldown_focus", "changement de focus → voile + croix à jour immédiatement")


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
