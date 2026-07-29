extends Node

## Inerte dans le jeu normal (desktop) — ne s'active que dans l'export Web
## dédié à la démo publique du site (cf. export_presets.cfg, preset "Web
## Demo", custom_features="web_demo"). Saute le menu/le hub/la sélection de
## starter : direct dans le biome 1 (acte 0, toujours Prairie — cf.
## RunManager._pool_for_act) avec Pikachu déjà en équipe, en solo.
## Même recette que TestHarness._scenario_run, sans les assertions de test.

func _ready() -> void:
	if not OS.has_feature("web_demo"):
		return
	GameManager.is_first_run = false
	GameManager.selected_starter_id = 25   # Pikachu
	GameManager.hub_team = [25]
	RunManager.inst().start_run()
	get_tree().change_scene_to_file("res://scenes/combat/CombatArena.tscn")
