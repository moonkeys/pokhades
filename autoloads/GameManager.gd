extends Node

# ── Starters disponibles ─────────────────────────────────────────────
const STARTER_IDS: Array = [25, 570, 359, 725, 656, 390, 674, 559, 447]

var selected_starter_id: int = 25

const XP_MULTIPLIER := 12

const EVOLUTIONS: Dictionary = {
	25:  {"level": 20, "evolves_to": 26},
	4:   {"level": 16, "evolves_to": 5},
	5:   {"level": 36, "evolves_to": 6},
	37:  {"level": 20, "evolves_to": 38},
	133: {"level": 20, "evolves_to": 134},
	32:  {"level": 16, "evolves_to": 33},
	33:  {"level": 36, "evolves_to": 34},
	725: {"level": 17, "evolves_to": 726},
	726: {"level": 34, "evolves_to": 727},
	656: {"level": 16, "evolves_to": 657},
	657: {"level": 36, "evolves_to": 658},
	390: {"level": 14, "evolves_to": 391},
	391: {"level": 36, "evolves_to": 392},
	674: {"level": 14, "evolves_to": 675},
	559: {"level": 18, "evolves_to": 560},
	447: {"level": 20, "evolves_to": 448},
	570: {"level": 20, "evolves_to": 571},
}

# ── État du Hub ──────────────────────────────────────────────────────
var gold:             int        = 200
var run_count:        int        = 0
var is_first_run:     bool       = true
var unlocked_pokemon: Array[int] = []
var hub_team:         Array[int] = []
var owned_items:      Array[String] = []
var run_items:        Array         = []  # items ramassés pendant la run courante

# ── Améliorations permanentes achetées au hub ─────────────────────────
var move_slot_count:       int           = 1   # emplacements capacités (1-4)
var team_slot_count:       int           = 1   # taille équipe (1-6)
var purchased_move_names:  Array[String] = []  # capacités achetées chez le tuteur

# Moveset configuré par Pokémon depuis le Pokédex — persiste même hors équipe.
# pid:int -> Array[String] (api_name des capacités équipées, ordre = slots)
var move_loadouts: Dictionary = {}

const MOVE_SLOT_COSTS: Array[int] = [100, 200, 400]  # coût pour passer à 2, 3, 4 slots
const TEAM_SLOT_COSTS: Array[int] = [80, 120, 180, 250, 350]  # pour chaque slot ajouté


## Capacités explicitement choisies pour ce Pokémon (vide si jamais configuré).
func get_move_loadout(pid: int) -> Array:
	return (move_loadouts.get(pid, []) as Array).duplicate()


## Équipe/déséquipe une capacité pour un Pokémon précis — respecte move_slot_count.
func toggle_move_in_loadout(pid: int, api_name: String) -> void:
	var arr: Array = get_move_loadout(pid)
	if api_name in arr:
		arr.erase(api_name)
	elif arr.size() < move_slot_count:
		arr.append(api_name)
	move_loadouts[pid] = arr

# ── Catalogue boutique ────────────────────────────────────────────────
const SHOP_CATALOG: Array[Dictionary] = [
	{"id": "x_attack",  "name": "Capacité+",   "sym": "▲", "price": 80,  "desc": "+20% ATQ pour toute l'équipe cette run.",          "sym_color": Color(0.95, 0.50, 0.10)},
	{"id": "x_defend",  "name": "Défense+",    "sym": "▣", "price": 80,  "desc": "+20% DÉF pour toute l'équipe cette run.",          "sym_color": Color(0.30, 0.50, 0.90)},
	{"id": "x_speed",   "name": "Agilité+",    "sym": "★", "price": 80,  "desc": "+20% VIT pour toute l'équipe cette run.",          "sym_color": Color(0.88, 0.80, 0.10)},
	{"id": "boost_hp",  "name": "Vigueur",     "sym": "◆", "price": 100, "desc": "+20% PV max pour toute l'équipe cette run.",       "sym_color": Color(0.18, 0.70, 0.35)},
	{"id": "revive",    "name": "Rappel",      "sym": "✦", "price": 150, "desc": "Le premier KO de l'équipe est relevé à 50% PV.",   "sym_color": Color(0.90, 0.60, 0.10)},
	{"id": "exp_share", "name": "Partage XP",  "sym": "⊕", "price": 120, "desc": "+30% d'expérience gagnée pendant la run.",         "sym_color": Color(0.25, 0.55, 0.95)},
]

# ── Capacités Spéciales (CS) — débloquent le franchissement d'obstacles
# en run (eau, arbres à couper, rochers). Achat unique et permanent,
# puis assignées à un Pokémon de l'équipe (cf. CSAssignScreen).
const CS_CATALOG: Array[Dictionary] = [
	{"id": "cs_surf",  "name": "CS Surf",  "sym": "≈", "price": 250, "desc": "Permet de nager à travers l'eau une fois assignée à un Pokémon de l'équipe.",        "sym_color": Color(0.25, 0.55, 0.90), "permanent": true},
	{"id": "cs_coupe", "name": "CS Coupe", "sym": "✂", "price": 200, "desc": "Permet de couper les arbres bloquant l'accès à certains coffres.",                    "sym_color": Color(0.30, 0.70, 0.30), "permanent": true},
	{"id": "cs_force", "name": "CS Force", "sym": "⛰", "price": 220, "desc": "Permet de pousser/casser les rochers bloquant l'accès à certains coffres.",           "sym_color": Color(0.65, 0.45, 0.25), "permanent": true},
]

# pid:int -> "cs_surf"/"cs_coupe"/"cs_force" assigné à ce Pokémon (au plus 1 CS par Pokémon)
var cs_holders: Dictionary = {}


func owns_cs(cs_id: String) -> bool:
	return cs_id in owned_items


## Assigne `cs_id` au Pokémon `pid` — un Pokémon ne peut tenir qu'une seule
## CS à la fois (remplace toute assignation précédente pour ce Pokémon),
## et une CS n'est tenue que par un seul Pokémon à la fois.
func assign_cs(cs_id: String, pid: int) -> void:
	for key in cs_holders.keys():
		if cs_holders[key] == pid:
			cs_holders.erase(key)
	cs_holders[cs_id] = pid


func get_cs_holder(cs_id: String) -> int:
	return cs_holders.get(cs_id, 0)


func get_pokemon_cs(pid: int) -> String:
	for key in cs_holders.keys():
		if cs_holders[key] == pid:
			return key
	return ""

# ── Taille d'équipe (achetable) ───────────────────────────────────────
func get_max_team_size() -> int:
	return team_slot_count

func get_next_unlock_threshold() -> int:
	return 999  # gardé pour compatibilité

# ── Helpers ───────────────────────────────────────────────────────────
func reset_run_items() -> void:
	run_items.clear()

func add_run_item(item: Dictionary) -> void:
	run_items.append(item)

func unlock_pokemon(id: int) -> void:
	if id not in unlocked_pokemon:
		unlocked_pokemon.append(id)


# ── Déblocage par victoires cumulées ────────────────────────────────────
const UNLOCK_DEFEAT_THRESHOLD := 20

var defeat_counts: Dictionary = {}   # pid:int -> int (victoires cumulées contre cette espèce)


func get_defeat_count(pid: int) -> int:
	return defeat_counts.get(pid, 0)


## Compte une victoire contre cette espèce. Débloque automatiquement le Pokémon
## une fois le seuil atteint — seules les formes de base sont recrutables.
## Retourne true si ce KO vient de déclencher le déblocage.
func record_defeat(pid: int, is_base_form: bool = true) -> bool:
	defeat_counts[pid] = get_defeat_count(pid) + 1
	if is_base_form and pid not in unlocked_pokemon and defeat_counts[pid] >= UNLOCK_DEFEAT_THRESHOLD:
		unlock_pokemon(pid)
		return true
	return false

func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

func get_run_team() -> Array[int]:
	if hub_team.is_empty():
		return [selected_starter_id]
	return hub_team
