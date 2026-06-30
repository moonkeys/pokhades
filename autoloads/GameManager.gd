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

const MOVE_SLOT_COSTS: Array[int] = [100, 200, 400]  # coût pour passer à 2, 3, 4 slots
const TEAM_SLOT_COSTS: Array[int] = [80, 120, 180, 250, 350]  # pour chaque slot ajouté

# ── Catalogue boutique ────────────────────────────────────────────────
const SHOP_CATALOG: Array[Dictionary] = [
	{"id": "x_attack",  "name": "Capacité+",   "sym": "▲", "price": 80,  "desc": "+20% ATQ pour toute l'équipe cette run.",          "sym_color": Color(0.95, 0.50, 0.10)},
	{"id": "x_defend",  "name": "Défense+",    "sym": "▣", "price": 80,  "desc": "+20% DÉF pour toute l'équipe cette run.",          "sym_color": Color(0.30, 0.50, 0.90)},
	{"id": "x_speed",   "name": "Agilité+",    "sym": "★", "price": 80,  "desc": "+20% VIT pour toute l'équipe cette run.",          "sym_color": Color(0.88, 0.80, 0.10)},
	{"id": "boost_hp",  "name": "Vigueur",     "sym": "◆", "price": 100, "desc": "+20% PV max pour toute l'équipe cette run.",       "sym_color": Color(0.18, 0.70, 0.35)},
	{"id": "revive",    "name": "Rappel",      "sym": "✦", "price": 150, "desc": "Le premier KO de l'équipe est relevé à 50% PV.",   "sym_color": Color(0.90, 0.60, 0.10)},
	{"id": "exp_share", "name": "Partage XP",  "sym": "⊕", "price": 120, "desc": "+30% d'expérience gagnée pendant la run.",         "sym_color": Color(0.25, 0.55, 0.95)},
]

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
