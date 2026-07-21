extends Node
## LA RÉBELLION — colonne vertébrale narrative du jeu.
##
## Pitch : un Pokémon sauvage refuse que les siens vivent enfermés dans des
## Poké Balls. Il lance une rébellion pour libérer les Pokémon capturés et
## prouver qu'un Pokémon peut choisir son destin.
##
## Ce singleton ne fait QUE de la narration/progression : il se branche sur des
## mécaniques qui existent déjà (GameManager.unlocked_pokemon = les libérés,
## GameManager.champion_badges = les dresseurs-boss vaincus). Il n'introduit
## aucune monnaie ni combat nouveau — il donne du SENS à ce qui existe.
##
## Persistance : StoryManager n'écrit pas de fichier lui-même. GameManager reste
## l'unique point d'I/O (save.json) et sérialise notre état via to_dict() /
## from_dict(), appelés depuis GameManager.save_game()/load_game().

## Émis quand on franchit un chapitre (nouvel objectif) — le hub s'y abonne pour
## afficher une bannière « Nouveau chapitre ».
signal chapter_advanced(index: int)
## Émis quand le rang de rébellion change (assez de Pokémon libérés).
signal rank_changed(index: int)


## Un objectif se lit sur l'état DÉJÀ suivi par GameManager :
##   "free"      → nombre de Pokémon libérés (unlocked_pokemon.size())
##   "champions" → nombre de dresseurs-boss vaincus (champion_badges.size())
const CHAPTERS: Array[Dictionary] = [
	{
		"title": "L'Étincelle",
		"intro": "Tu es né libre, et tu refuses les Poké Balls. Autour de toi, "
			+ "des Pokémon capturés obéissent, dressés, enfermés. Assez. La "
			+ "rébellion commence par toi — et par ceux que tu convaincras.",
		"objective": "Libère 3 Pokémon pour lancer le mouvement.",
		"goal": "free", "target": 3,
	},
	{
		"title": "Premiers Fronts",
		"intro": "La rumeur court : un Pokémon sauvage brise les chaînes. Les "
			+ "dresseurs s'inquiètent. Affronte-en un et montre que leurs "
			+ "captifs peuvent choisir de rejoindre la rébellion.",
		"objective": "Vaincs 1 dresseur-champion.",
		"goal": "champions", "target": 1,
	},
	{
		"title": "La Rébellion Grandit",
		"intro": "Le refuge se remplit. Chaque Pokémon libéré en inspire un "
			+ "autre. Fais grossir les rangs — un mouvement ne survit que s'il "
			+ "grandit plus vite qu'on ne le réprime.",
		"objective": "Porte la rébellion à 12 Pokémon libérés.",
		"goal": "free", "target": 12,
	},
	{
		"title": "Front de Région",
		"intro": "Les champions de zone verrouillent chaque région. Brise leur "
			+ "emprise, l'une après l'autre : chaque badge arraché est une "
			+ "région où les Pokémon peuvent à nouveau choisir.",
		"objective": "Vaincs 3 dresseurs-champions.",
		"goal": "champions", "target": 3,
	},
	{
		"title": "Soulèvement",
		"intro": "Ce n'est plus une fuite, c'est un soulèvement. Vingt-cinq "
			+ "âmes libres derrière toi. Le système des dresseurs vacille — il "
			+ "est temps de viser sa tête.",
		"objective": "Rassemble 25 Pokémon libérés.",
		"goal": "free", "target": 25,
	},
	{
		"title": "La Chaîne Brisée",
		"intro": "Au sommet, une Ligue qui incarne tout ce que tu combats : le "
			+ "contrôle absolu. Bats ses maîtres et offre au monde un choix — "
			+ "suivre un dresseur… ou vivre libre.",
		"objective": "Vaincs les 5 champions et mène la rébellion à son terme.",
		"goal": "champions", "target": 5,
	},
]

## Rangs de rébellion selon le nombre de Pokémon libérés. Le `perk` est pour
## l'instant DESCRIPTIF (fanion du refuge) — une phase ultérieure branchera ces
## paliers sur de vrais bonus de hub (soins, entraînement…).
const RANKS: Array[Dictionary] = [
	{"min": 0,  "name": "Fugitif",        "perk": "Tu fuis encore, seul."},
	{"min": 3,  "name": "Meneur",         "perk": "Les premiers te suivent."},
	{"min": 8,  "name": "Cellule Rebelle","perk": "Un noyau soudé se forme."},
	{"min": 15, "name": "Insurrection",   "perk": "Le refuge prend vie."},
	{"min": 25, "name": "Soulèvement",    "perk": "Ton nom se murmure partout."},
	{"min": 40, "name": "Révolution",     "perk": "Un monde libre est en vue."},
]


## Index du chapitre courant (0 = premier). Persisté.
var current_chapter: int = 0
## Chapitres dont l'intro a déjà été montrée au joueur (évite de la rejouer).
var _seen_intros: Array = []
## Dernier rang notifié — sert à détecter un changement de rang à afficher.
var _last_rank: int = 0


# ── Lectures ────────────────────────────────────────────────────────────

func rebellion_size() -> int:
	return GameManager.unlocked_pokemon.size()


func champions_beaten() -> int:
	return GameManager.champion_badges.size()


func rank_index() -> int:
	var idx := 0
	var size := rebellion_size()
	for i in RANKS.size():
		if size >= int(RANKS[i]["min"]):
			idx = i
	return idx


func rank() -> Dictionary:
	return RANKS[rank_index()]


## Chapitre courant (borné au dernier si la progression est « terminée »).
func chapter() -> Dictionary:
	return CHAPTERS[clampi(current_chapter, 0, CHAPTERS.size() - 1)]


func is_finished() -> bool:
	return current_chapter >= CHAPTERS.size()


## Avancement de l'objectif courant : {current, target, done}.
func objective_progress() -> Dictionary:
	if is_finished():
		return {"current": 1, "target": 1, "done": true}
	var ch := chapter()
	var cur := champions_beaten() if ch["goal"] == "champions" else rebellion_size()
	var tgt := int(ch["target"])
	return {"current": mini(cur, tgt), "target": tgt, "done": cur >= tgt}


# ── Progression ─────────────────────────────────────────────────────────

## À appeler après tout événement qui peut faire avancer l'histoire (boss
## vaincu, Pokémon libéré, entrée dans le hub). Émet les signaux idoines et
## renvoie true si un chapitre a été franchi (le hub peut alors féliciter).
func evaluate() -> bool:
	# Rang de rébellion (indépendant des chapitres).
	var r := rank_index()
	if r != _last_rank:
		_last_rank = r
		rank_changed.emit(r)

	# Franchit AUTANT de chapitres que l'état le permet (on peut avoir dépassé
	# plusieurs jalons d'un coup, p. ex. en revenant d'une grosse run).
	var advanced := false
	while not is_finished() and objective_progress()["done"]:
		current_chapter += 1
		advanced = true
		chapter_advanced.emit(current_chapter)
	return advanced


## ── Confiance / recrutement (« rejoindre ou s'enfuir ») ─────────────────
##
## Au KO d'un dresseur, l'un de ses Pokémon PEUT rejoindre la rébellion… ou
## s'enfuir si les conditions ne sont pas réunies. La confiance se gagne :
##   • une espèce DÉJÀ libérée te fait confiance → elle rejoint à coup sûr ;
##   • sinon, la probabilité grandit avec la STATURE de la rébellion (rang) et
##     ta RÉPUTATION (dresseurs déjà vaincus).
## C'est le pont concret entre la progression narrative et une mécanique de run.

const RECRUIT_CHANCE_MIN := 0.15
const RECRUIT_CHANCE_MAX := 0.95

func recruit_chance(pid: int) -> float:
	if pid in GameManager.unlocked_pokemon:
		return 1.0
	var base := 0.30 + 0.10 * float(rank_index())   # 0.30 → 0.80 selon le rang
	var rep := 0.05 * float(champions_beaten())      # réputation grandissante
	return clampf(base + rep, RECRUIT_CHANCE_MIN, RECRUIT_CHANCE_MAX)


## true = le Pokémon rejoint ; false = il s'enfuit.
func roll_recruit(pid: int) -> bool:
	return randf() < recruit_chance(pid)


func has_seen_intro(index: int) -> bool:
	return index in _seen_intros


func mark_intro_seen(index: int) -> void:
	if index not in _seen_intros:
		_seen_intros.append(index)


# ── Persistance (déléguée par GameManager) ──────────────────────────────

func to_dict() -> Dictionary:
	return {
		"current_chapter": current_chapter,
		"seen_intros":     _seen_intros,
		"last_rank":       _last_rank,
	}


func from_dict(d: Dictionary) -> void:
	current_chapter = int(d.get("current_chapter", 0))
	_seen_intros    = d.get("seen_intros", [])
	_last_rank      = int(d.get("last_rank", rank_index()))


func reset() -> void:
	current_chapter = 0
	_seen_intros    = []
	_last_rank      = 0
