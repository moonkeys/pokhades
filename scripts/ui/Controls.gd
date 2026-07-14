class_name Controls
extends RefCounted

## SOURCE UNIQUE DE VÉRITÉ des touches du jeu.
##
## Avant, chaque script déclarait ses actions dans son coin (CombatArena,
## TeamMember, HubPlayer, HubWorld) — d'où le conflit Tab, qui était bindé À LA
## FOIS sur "changer de Pokémon" ET "fiche d'équipe" (une touche ne peut pas
## faire deux choses). Tout est désormais déclaré ICI, appliqué au démarrage
## (GameManager) et REMAPPABLE par le joueur (cf. ControlsScreen), avec
## persistance dans la sauvegarde (GameManager.key_bindings).

## `alt` : seconde touche par défaut (main gauche AZERTY). Elle saute dès que
## le joueur remappe l'action — son choix remplace tout.
const CATALOG: Array[Dictionary] = [
	# ── Déplacement ──
	{"id": "ui_up",    "label": "Avancer",          "key": KEY_UP,    "cat": "Déplacement"},
	{"id": "ui_down",  "label": "Reculer",          "key": KEY_DOWN,  "cat": "Déplacement"},
	{"id": "ui_left",  "label": "Aller à gauche",   "key": KEY_LEFT,  "cat": "Déplacement"},
	{"id": "ui_right", "label": "Aller à droite",   "key": KEY_RIGHT, "cat": "Déplacement"},

	# ── Combat ──
	{"id": "use_move_1", "label": "Capacité 1", "key": KEY_1, "alt": KEY_Q, "cat": "Combat"},
	{"id": "use_move_2", "label": "Capacité 2", "key": KEY_2, "alt": KEY_Z, "cat": "Combat"},
	{"id": "use_move_3", "label": "Capacité 3", "key": KEY_3, "alt": KEY_S, "cat": "Combat"},
	{"id": "use_move_4", "label": "Capacité 4", "key": KEY_4, "alt": KEY_D, "cat": "Combat"},
	{"id": "dash",       "label": "Dash / esquive", "key": KEY_SHIFT, "cat": "Combat"},
	{"id": "cs_use",     "label": "Utiliser une CS (Coupe/Surf/Force)", "key": KEY_A, "cat": "Combat"},

	# ── Équipe ──  (Tab ne fait plus qu'UNE chose : changer de Pokémon)
	{"id": "switch_pokemon", "label": "Changer de Pokémon", "key": KEY_TAB, "cat": "Équipe"},
	{"id": "team_stats",     "label": "Fiche d'équipe (sans pause)", "key": KEY_C, "cat": "Équipe"},
	{"id": "toggle_follow",  "label": "Ordre : suivre / tenir position", "key": KEY_F, "cat": "Équipe"},

	# ── Monde ──
	{"id": "interact",     "label": "Interagir (coffre, PNJ, porte)", "key": KEY_E, "cat": "Monde"},
	{"id": "hub_interact", "label": "Parler à un PNJ (hub)",          "key": KEY_E, "cat": "Monde"},
]

## Ordre d'affichage des catégories dans l'écran des contrôles.
const CATEGORIES: Array[String] = ["Déplacement", "Combat", "Équipe", "Monde"]


static func entry(id: String) -> Dictionary:
	for d: Dictionary in CATALOG:
		if str(d["id"]) == id:
			return d
	return {}


static func default_key(id: String) -> int:
	return int(entry(id).get("key", KEY_NONE))


## Touche effective : le remap du joueur, sinon le défaut du catalogue.
static func key_for(id: String) -> int:
	var custom: Variant = GameManager.key_bindings.get(id, null)
	return int(custom) if custom != null else default_key(id)


## Libellé lisible d'une touche ("Maj", "Tab", "A"…).
static func key_name(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode)


## (Re)construit l'InputMap depuis le catalogue + les remaps du joueur.
## Ne touche QUE les événements clavier : les entrées manette éventuelles des
## actions intégrées (ui_*) sont préservées.
static func apply() -> void:
	for d: Dictionary in CATALOG:
		var id := str(d["id"])
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		for ev in InputMap.action_get_events(id):
			if ev is InputEventKey:
				InputMap.action_erase_event(id, ev)

		var ev_main := InputEventKey.new()
		ev_main.keycode = key_for(id)
		InputMap.action_add_event(id, ev_main)

		# Touche secondaire : seulement tant que l'action n'a pas été remappée.
		var remapped: bool = GameManager.key_bindings.has(id)
		if not remapped and d.has("alt"):
			var ev_alt := InputEventKey.new()
			ev_alt.keycode = int(d["alt"])
			InputMap.action_add_event(id, ev_alt)


## Assigne `keycode` à `id`. Si une AUTRE action utilisait déjà cette touche,
## elle est libérée (KEY_NONE) — une touche ne peut pas faire deux choses.
## Retourne l'id de l'action dépossédée, ou "" si aucune.
static func set_binding(id: String, keycode: int) -> String:
	var stolen := ""
	for d: Dictionary in CATALOG:
		var other := str(d["id"])
		if other == id:
			continue
		# hub_interact et interact partagent [E] volontairement (contextes
		# disjoints : hub vs run) — on ne les considère pas en conflit.
		if _same_context_conflict(id, other) and key_for(other) == keycode:
			GameManager.key_bindings[other] = KEY_NONE
			stolen = other
	GameManager.key_bindings[id] = keycode
	apply()
	GameManager.save_game()
	return stolen


## interact/hub_interact vivent dans des scènes différentes : partager [E] est
## voulu, ce n'est pas un conflit.
static func _same_context_conflict(a: String, b: String) -> bool:
	var pair := [a, b]
	pair.sort()
	return pair != ["hub_interact", "interact"]


static func reset_defaults() -> void:
	GameManager.key_bindings.clear()
	apply()
	GameManager.save_game()
