class_name StatusFx
extends RefCounted

## États de combat (altérations de statut) — table centrale + tirage à
## l'impact selon le TYPE de l'attaquant. La logique d'effet (dégâts sur la
## durée, ralentissement, blocage) vit dans PokemonInstance ; l'affichage
## (tag coloré flottant) est géré par TeamMember/EnemyAI via make_icon().
##
## Tags 3-lettres (rendu garanti avec la police par défaut, contrairement aux
## emojis) : BRÛ brûlure, PSN poison, PAR paralysie, GEL gel, DOR sommeil.

const INFO := {
	# DOT nettement relevé (retour joueurs : « poison/brûlure devraient faire
	# plus de dégâts ») : % des PV max par tick (cf. PokemonInstance._DOT_INTERVAL).
	"burn":      {"tag": "BRÛ", "col": Color(1.00, 0.45, 0.12), "dur": 7.0, "dot": 0.045},
	"poison":    {"tag": "PSN", "col": Color(0.72, 0.32, 0.82), "dur": 8.0, "dot": 0.060},
	"paralysis": {"tag": "PAR", "col": Color(0.95, 0.85, 0.12), "dur": 5.0, "dot": 0.0},
	"freeze":    {"tag": "GEL", "col": Color(0.50, 0.85, 1.00), "dur": 3.0, "dot": 0.0},
	"sleep":     {"tag": "DOR", "col": Color(0.62, 0.70, 1.00), "dur": 3.0, "dot": 0.0},
}

## Type d'attaque → (état infligé, probabilité). Un seul état par type.
const _BY_TYPE := {
	"fire":     {"status": "burn",      "chance": 0.25},
	"poison":   {"status": "poison",    "chance": 0.30},
	"electric": {"status": "paralysis", "chance": 0.25},
	"ice":      {"status": "freeze",    "chance": 0.15},
	"psychic":  {"status": "sleep",     "chance": 0.12},
	"grass":    {"status": "poison",    "chance": 0.10},
	"ghost":    {"status": "sleep",     "chance": 0.10},
}


## Tire un état à infliger selon le type de l'attaque, ou "" si rien.
static func roll(move_type: String) -> String:
	var e: Dictionary = _BY_TYPE.get(move_type, {})
	if e.is_empty():
		return ""
	if randf() < float(e["chance"]):
		return e["status"]
	return ""


static func duration(status: String) -> float:
	return float(INFO.get(status, {}).get("dur", 4.0))


## Tag flottant (Label3D) au-dessus du Pokémon affecté — coloré par état.
static func make_icon(status: String) -> Label3D:
	var info: Dictionary = INFO.get(status, {})
	var lbl := Label3D.new()
	lbl.text = str(info.get("tag", "?"))
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.pixel_size = 0.008
	lbl.modulate = info.get("col", Color.WHITE)
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0.08, 0.06, 0.04, 0.9)
	return lbl
