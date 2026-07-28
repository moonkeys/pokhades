class_name DamageCalculator

# Table des types Gen 6 complète (18 types)
# format : attaquant → {défenseur: multiplicateur}
# Seules les valeurs ≠ 1.0 sont listées (1.0 = efficacité normale).
static var TYPE_CHART: Dictionary = {
	"normal":   {"rock": 0.5, "steel": 0.5, "ghost": 0.0},
	"fire":     {"fire": 0.5, "water": 0.5, "rock": 0.5, "dragon": 0.5,
				 "grass": 2.0, "ice": 2.0, "bug": 2.0, "steel": 2.0},
	"water":    {"water": 0.5, "grass": 0.5, "dragon": 0.5,
				 "fire": 2.0, "ground": 2.0, "rock": 2.0},
	"electric": {"electric": 0.5, "grass": 0.5, "dragon": 0.5, "ground": 0.0,
				 "water": 2.0, "flying": 2.0},
	"grass":    {"fire": 0.5, "grass": 0.5, "poison": 0.5, "flying": 0.5,
				 "bug": 0.5, "dragon": 0.5, "steel": 0.5,
				 "water": 2.0, "ground": 2.0, "rock": 2.0},
	"ice":      {"water": 0.5, "ice": 0.5, "steel": 0.5,
				 "grass": 2.0, "ground": 2.0, "flying": 2.0, "dragon": 2.0},
	"fighting": {"poison": 0.5, "flying": 0.5, "psychic": 0.5, "bug": 0.5, "fairy": 0.5,
				 "ghost": 0.0,
				 "normal": 2.0, "ice": 2.0, "rock": 2.0, "dark": 2.0, "steel": 2.0},
	"poison":   {"poison": 0.5, "ground": 0.5, "rock": 0.5, "ghost": 0.5, "steel": 0.0,
				 "grass": 2.0, "fairy": 2.0},
	"ground":   {"grass": 0.5, "bug": 0.5, "flying": 0.0,
				 "fire": 2.0, "electric": 2.0, "poison": 2.0, "rock": 2.0, "steel": 2.0},
	"flying":   {"electric": 0.5, "rock": 0.5, "steel": 0.5,
				 "grass": 2.0, "fighting": 2.0, "bug": 2.0},
	"psychic":  {"psychic": 0.5, "steel": 0.5, "dark": 0.0,
				 "fighting": 2.0, "poison": 2.0},
	"bug":      {"fire": 0.5, "fighting": 0.5, "flying": 0.5, "ghost": 0.5,
				 "steel": 0.5, "fairy": 0.5,
				 "grass": 2.0, "psychic": 2.0, "dark": 2.0},
	"rock":     {"fighting": 0.5, "ground": 0.5, "steel": 0.5,
				 "fire": 2.0, "ice": 2.0, "flying": 2.0, "bug": 2.0},
	"ghost":    {"normal": 0.0, "dark": 0.5,
				 "psychic": 2.0, "ghost": 2.0},
	"dragon":   {"steel": 0.5, "fairy": 0.0,
				 "dragon": 2.0},
	"dark":     {"fighting": 0.5, "dark": 0.5, "fairy": 0.5,
				 "psychic": 2.0, "ghost": 2.0},
	"steel":    {"fire": 0.5, "water": 0.5, "electric": 0.5, "steel": 0.5,
				 "ice": 2.0, "rock": 2.0, "fairy": 2.0},
	"fairy":    {"fire": 0.5, "poison": 0.5, "steel": 0.5,
				 "fighting": 2.0, "dragon": 2.0, "dark": 2.0},
}


## `damage_class` ("physical"/"special"/"status") sélectionne la paire de
## stats Attaque/Défense ou Atq. Spé/Déf. Spé — jusqu'ici TOUJOURS Attaque/
## Défense, quelle que soit la classe du move (Atq. Spé/Déf. Spé n'étaient que
## cosmétiques, jamais lues en combat). Nécessaire pour que les bonus
## "Attaque Spéciale"/"Défense Spéciale" aient un effet réel.
## Retourne {"damage": int, "crit": bool} — `crit` pilote le retour visuel
## (chiffre de dégâts distinct, cf. CombatVFX).
static func calculate(
	attacker: PokemonInstance,
	defender: PokemonInstance,
	move_power: int,
	move_type: String,
	damage_class: String = "physical"
) -> Dictionary:
	var atk: float
	var def: float
	if damage_class == "special":
		atk = float(attacker.get_effective_sp_attack())
		def = float(defender.get_effective_sp_defense())
	else:
		atk = float(attacker.get_effective_attack())
		def = float(defender.get_effective_defense())
	var lvl := float(attacker.level)

	# Formule officielle Pokémon Gen 5+
	var base := ((2.0 * lvl / 5.0 + 2.0) * move_power * atk / def) / 50.0 + 2.0

	# Multiplicateur de type (peut s'appliquer sur plusieurs types défenseurs)
	var modifier := 1.0
	var chart: Dictionary = TYPE_CHART.get(move_type, {})
	for dtype in defender.data.types:
		modifier *= chart.get(dtype, 1.0)

	var rand := randf_range(0.85, 1.0)
	var crit := randf() < attacker.crit_chance
	if crit:
		modifier *= 1.5

	return {"damage": max(1, int(floor(base * modifier * rand))), "crit": crit}


static func type_multiplier(attack_type: String, defender_types: Array) -> float:
	var chart: Dictionary = TYPE_CHART.get(attack_type, {})
	var mult := 1.0
	for dtype in defender_types:
		mult *= chart.get(dtype, 1.0)
	return mult
