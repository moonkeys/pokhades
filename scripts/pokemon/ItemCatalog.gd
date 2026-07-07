class_name ItemCatalog
extends RefCounted

## Catalogue central des objets tenus + Super Bonbon. Vendus par Gromago au
## hub (contre des Baies), assignés à un Pokémon dans l'écran d'équipe, puis
## appliqués au spawn de run (cf. CombatArena._spawn_team).
##
## `effect` (objets tenus) : "atk" / "def" / "spd" → multiplicateur de stat,
## "maxhp" → bonus de PV max (via PokemonInstance.apply_hp_boost). Ces
## effets sont déjà gérés par PokemonInstance.equip_item / _apply_stat_mult.
## `kind` = "held" (objet tenu) ou "candy" (Super Bonbon, consommable qui
## augmente le niveau de départ d'un Pokémon de base).

const ICON_DIR := "res://assets/items/"

const ITEMS: Array[Dictionary] = [
	# ── Objets tenus offensifs ────────────────────────────────────────
	{"api": "choice-band",  "name": "Bandeau Choix",  "kind": "held", "effect": "atk",   "mult": 1.50, "price": 220,
		"desc": "+50% Attaque."},
	{"api": "choice-specs", "name": "Lunettes Choix", "kind": "held", "effect": "atk",   "mult": 1.40, "price": 200,
		"desc": "+40% Attaque."},
	{"api": "life-orb",     "name": "Orbe Vie",       "kind": "held", "effect": "atk",   "mult": 1.30, "price": 170,
		"desc": "+30% Attaque."},
	{"api": "muscle-band",  "name": "Muscle Band",    "kind": "held", "effect": "atk",   "mult": 1.15, "price": 110,
		"desc": "+15% Attaque."},
	{"api": "expert-belt",  "name": "Ceinture Pro",   "kind": "held", "effect": "atk",   "mult": 1.20, "price": 130,
		"desc": "+20% Attaque."},
	# ── Vitesse ───────────────────────────────────────────────────────
	{"api": "choice-scarf", "name": "Mouchoir Choix", "kind": "held", "effect": "spd",   "mult": 1.50, "price": 200,
		"desc": "+50% Vitesse."},
	# ── Défensifs / endurance ─────────────────────────────────────────
	{"api": "black-belt",   "name": "Ceinture Noire", "kind": "held", "effect": "def",   "mult": 1.40, "price": 150,
		"desc": "+40% Défense."},
	{"api": "leftovers",    "name": "Restes",         "kind": "held", "effect": "maxhp", "mult": 1.25, "price": 180,
		"desc": "+25% PV max."},
	{"api": "sitrus-berry", "name": "Baie Sitrus",    "kind": "held", "effect": "maxhp", "mult": 1.15, "price": 120,
		"desc": "+15% PV max."},
	{"api": "oran-berry",   "name": "Baie Oran",      "kind": "held", "effect": "maxhp", "mult": 1.08, "price": 70,
		"desc": "+8% PV max."},
	# ── Super Bonbon (consommable) ────────────────────────────────────
	{"api": "rare-candy",   "name": "Super Bonbon",   "kind": "candy", "effect": "",     "mult": 0.0,  "price": 250,
		"desc": "Augmente de 5 le niveau de départ d'un Pokémon (peut le faire évoluer). Consommé à l'usage."},
]

const CANDY_LEVELS   := 5    # niveaux gagnés par Super Bonbon
const CANDY_MAX_BONUS := 20  # +20 max → un starter niv.10 peut démarrer à 30


static func get_item(api: String) -> Dictionary:
	for it: Dictionary in ITEMS:
		if it["api"] == api:
			return it
	return {}


static func held_items() -> Array:
	return ITEMS.filter(func(it: Dictionary) -> bool: return it["kind"] == "held")


## Texture d'icône d'un objet — fichier local (copié des Graphics/Items
## d'Essentials), ou null si absent (l'appelant affiche un fallback texte).
static func icon(api: String) -> Texture2D:
	var path := ICON_DIR + api + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null
