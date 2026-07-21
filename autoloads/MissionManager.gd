extends Node
## TABLEAU DES RUMEURS — missions de libération optionnelles entre les runs.
##
## Prolonge la narration de la rébellion (cf. StoryManager) par des objectifs
## FACULTATIFS et RÉCURRENTS : un tableau de trois « rumeurs » que le joueur
## accomplit au fil des runs, réclame contre une récompense, puis voit se
## renouveler. Comme StoryManager, ce singleton ne crée aucune mécanique de
## combat : chaque mission se lit sur un compteur DÉJÀ suivi et persistant.
##
## Modèle « delta depuis l'assignation » : à l'apparition d'une rumeur on note
## la valeur COURANTE du compteur visé (base). L'avancement = valeur actuelle −
## base. La mission est donc « libère 3 Pokémon DE PLUS », ce qui donne le bon
## ressenti d'un objectif frais à chaque renouvellement.
##
## Persistance déléguée à GameManager (unique point d'I/O), via to_dict()/
## from_dict() appelés depuis save_game()/load_game().

signal board_changed

const SLOTS := 3

## Pool de rumeurs. `metric` ∈ {"free","champions","runs","victories"} — toutes
## des grandeurs cumulatives déjà persistées côté GameManager.
const POOL: Array[Dictionary] = [
	{"title": "Évasion de la Réserve",  "metric": "free",      "target": 3,
		"rumor": "On murmure que des cages s'entrouvrent. Libère-en trois de plus, et le mouvement prendra.",
		"gold": 150, "shards": 0},
	{"title": "Marche de la Liberté",   "metric": "victories", "target": 25,
		"rumor": "Chaque combat gagné résonne comme un pas vers la liberté. Fais-en résonner vingt-cinq.",
		"gold": 200, "shards": 0},
	{"title": "Aguerris par la Route",  "metric": "runs",      "target": 2,
		"rumor": "Deux expéditions encore, et tes rangs reviendront plus soudés que jamais.",
		"gold": 180, "shards": 0},
	{"title": "La Confiance d'un Champion", "metric": "champions", "target": 1,
		"rumor": "Un dresseur-champion tient une région d'une main de fer. Fais tomber son emprise.",
		"gold": 300, "shards": 1},
	{"title": "Grand Rassemblement",    "metric": "free",      "target": 8,
		"rumor": "Huit âmes de plus derrière toi et le refuge deviendra une véritable place forte.",
		"gold": 400, "shards": 1},
	{"title": "Cent Fois Libres",       "metric": "victories", "target": 60,
		"rumor": "Soixante victoires arrachées au système : de quoi faire trembler les geôliers.",
		"gold": 350, "shards": 1},
	{"title": "Briser les Chaînes",     "metric": "champions", "target": 2,
		"rumor": "Deux champions à terre. Le verrou des régions ne tiendra pas éternellement.",
		"gold": 500, "shards": 2},
	{"title": "Longue Insurrection",    "metric": "runs",      "target": 5,
		"rumor": "Cinq campagnes menées bout à bout : les vétérans forgent la rébellion.",
		"gold": 320, "shards": 1},
]

## Un slot = {pool: index dans POOL, base: valeur du compteur à l'assignation}.
var _active: Array = []


func _ready() -> void:
	randomize()


# ── Lecture des compteurs (tous déjà persistés par GameManager) ─────────

func _metric_value(metric: String) -> int:
	match metric:
		"free":      return GameManager.unlocked_pokemon.size()
		"champions": return GameManager.champion_badges.size()
		"runs":      return GameManager.run_count
		"victories":
			var s := 0
			for v in GameManager.defeat_counts.values():
				s += int(v)
			return s
	return 0


# ── Tableau ─────────────────────────────────────────────────────────────

## Remplit les slots vides avec des rumeurs DISTINCTES. Idempotent — sûr à
## appeler à chaque ouverture du hub / du tableau.
func ensure_board() -> void:
	while _active.size() < SLOTS and _active.size() < POOL.size():
		var idx := _pick_unused()
		if idx < 0:
			break
		_active.append({"pool": idx, "base": _metric_value(POOL[idx]["metric"])})
	if _active.size() != SLOTS:
		board_changed.emit()


## Un index de POOL non présent dans les slots actifs, −1 s'il n'en reste aucun.
func _pick_unused() -> int:
	var used := {}
	for m in _active:
		used[int(m["pool"])] = true
	var choices: Array[int] = []
	for i in POOL.size():
		if not used.has(i):
			choices.append(i)
	if choices.is_empty():
		return -1
	return choices[randi() % choices.size()]


## Vue d'un slot pour l'UI : {def, current, target, done}.
func slot(i: int) -> Dictionary:
	var s: Dictionary = _active[i]
	var d: Dictionary = POOL[int(s["pool"])]
	var target := int(d["target"])
	var cur := clampi(_metric_value(d["metric"]) - int(s["base"]), 0, target)
	return {"def": d, "current": cur, "target": target, "done": cur >= target}


func slot_count() -> int:
	return _active.size()


## Réclame la récompense d'un slot accompli et y fait apparaître une nouvelle
## rumeur (renouvellement EN PLACE — l'ordre du tableau ne saute pas). Renvoie
## la récompense accordée {gold, shards}, ou {} si la mission n'était pas prête.
func claim(i: int) -> Dictionary:
	if i < 0 or i >= _active.size():
		return {}
	var view := slot(i)
	if not view["done"]:
		return {}
	var d: Dictionary = view["def"]
	var gold := int(d["gold"])
	var shards := int(d["shards"])
	GameManager.add_gold(gold)
	if shards > 0:
		GameManager.add_champion_shards(shards)

	# Renouvellement en place : nouvelle rumeur distincte des autres slots.
	var idx := _pick_unused()
	if idx >= 0:
		_active[i] = {"pool": idx, "base": _metric_value(POOL[idx]["metric"])}
	else:
		_active.remove_at(i)   # pool épuisé : on retire simplement le slot
	board_changed.emit()
	return {"gold": gold, "shards": shards}


# ── Persistance (déléguée par GameManager) ──────────────────────────────

func to_dict() -> Dictionary:
	return {"active": _active}


func from_dict(d: Dictionary) -> void:
	_active = d.get("active", [])
	# Purge d'éventuels index devenus invalides (pool réordonné entre versions).
	var clean: Array = []
	for m in _active:
		if typeof(m) == TYPE_DICTIONARY and int(m.get("pool", -1)) >= 0 \
				and int(m.get("pool", -1)) < POOL.size():
			clean.append({"pool": int(m["pool"]), "base": int(m.get("base", 0))})
	_active = clean
	ensure_board()


func reset() -> void:
	_active = []
