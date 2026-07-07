class_name RunManager

# Singleton statique — persiste entre les swaps de zone sans rechargement de scène.
static var _s: RunManager = null
static func inst() -> RunManager:
	if not _s:
		_s = RunManager.new()
	return _s


const ZONE_PATH := "res://scenes/world/BiomeMap.tscn"

var current_zone_idx: int = 0   # toujours 0 (BiomeMap)
var rooms_cleared:    int = 0

# ── Bonus de zone (façon Hades) ───────────────────────────────────────
# Un SEUL type de bonus par zone, annoncé à l'avance par la porte choisie.
# À la fin de la zone, un « don » apparaît au centre de la map ; le récupérer
# ouvre la récompense correspondante.
const BONUS_SKILL := 0   # nouvelle attaque (choix Pokémon → attaque)
const BONUS_STAT  := 1   # bonus de stats pour toute l'équipe
var current_zone_bonus: int = BONUS_STAT   # type du don de la zone COURANTE

const BONUS_LABELS := {
	BONUS_SKILL: "✦ Nouvelle attaque",
	BONUS_STAT:  "⬆ Bonus de stats",
}

func bonus_type_label(t: int) -> String:
	return BONUS_LABELS.get(t, "Don")


## Séquence de biomes de la run — construite au départ pour un enchaînement
## LOGIQUE (départ doux, montée en rudesse, répétitions possibles) au lieu
## d'un tirage aléatoire indépendant par zone. Indexée par rooms_cleared ;
## lue par MapGenerator._apply_theme (cf. current_biome).
var _biome_sequence: Array[int] = []
var _seq_run_id: int = -1   # run_count pour lequel la séquence a été construite
const _SEQ_LEN := 40


func start_run(_start_idx: int = 0) -> void:
	current_zone_idx = 0
	rooms_cleared    = 0
	current_zone_bonus = BONUS_STAT   # 1re zone : bonus de stats par défaut
	_ensure_sequence()


## Construit la séquence une seule fois par run. La 1re map se génère AVANT
## CombatArena._ready/start_run (les enfants _ready d'abord) ; on se cale
## donc sur GameManager.run_count (déjà incrémenté au lancement de la run)
## pour que la 1re zone et start_run partagent exactement la même séquence.
func _ensure_sequence() -> void:
	if _biome_sequence.is_empty() or _seq_run_id != GameManager.run_count:
		_build_biome_sequence()
		_seq_run_id = GameManager.run_count


## Génère une suite de biomes cohérente :
##   - 2 premières zones douces (Prairie / Forêt) ;
##   - puis progression vers des biomes plus rudes (Marécage, Montagne) au fil
##     de la profondeur, via 3 paliers de pools qui se durcissent ;
##   - chance de RÉPÉTER le biome précédent (« on est encore dans la même
##     région ») pour éviter le zapping permanent.
## Pool de biomes autorisés à une profondeur donnée (0 = 1re zone). Le pool
## se durcit avec la profondeur — partagé par la séquence par défaut ET les
## choix de portes (get_exits).
func _pool_for_depth(depth: int) -> Array[int]:
	if depth < 2:
		return [MapGenerator.MapTheme.MEADOW, MapGenerator.MapTheme.FOREST]
	if depth < 6:
		return [MapGenerator.MapTheme.FOREST, MapGenerator.MapTheme.AUTUMN, MapGenerator.MapTheme.SWAMP, MapGenerator.MapTheme.LAKE]
	return [MapGenerator.MapTheme.SWAMP, MapGenerator.MapTheme.ROCKY, MapGenerator.MapTheme.AUTUMN, MapGenerator.MapTheme.LAKE]


func _build_biome_sequence() -> void:
	var rng := RandomNumberGenerator.new()
	# Multijoueur : séquence identique sur tous les pairs (dérivée de la
	# graine partagée) — sinon chacun verrait des biomes différents.
	if Net.in_run:
		rng.seed = Net.zone_seed(-1)
	else:
		rng.randomize()
	_biome_sequence.clear()
	var prev := -1
	for i in _SEQ_LEN:
		var pool := _pool_for_depth(i)
		var pick: int
		# ~35% de chance de rester dans le même biome s'il est dans le pool courant
		if prev != -1 and prev in pool and rng.randf() < 0.35:
			pick = prev
		else:
			pick = pool[rng.randi() % pool.size()]
		_biome_sequence.append(pick)
		prev = pick


## Biome (MapGenerator.MapTheme) de la zone courante (par profondeur).
func current_biome() -> int:
	_ensure_sequence()
	return _biome_sequence[mini(rooms_cleared, _biome_sequence.size() - 1)]


## Biome de la zone à `depth` salles nettoyées (pour annoncer la suivante).
func biome_at(depth: int) -> int:
	_ensure_sequence()
	return _biome_sequence[clampi(depth, 0, _biome_sequence.size() - 1)]


const BIOME_NAMES := {
	MapGenerator.MapTheme.FOREST: "Forêt",
	MapGenerator.MapTheme.SWAMP:  "Marécage",
	MapGenerator.MapTheme.MEADOW: "Prairie",
	MapGenerator.MapTheme.ROCKY:  "Montagne",
	MapGenerator.MapTheme.AUTUMN: "Bois d'automne",
	MapGenerator.MapTheme.LAKE:   "Lac",
}

func biome_name(theme: int) -> String:
	return BIOME_NAMES.get(theme, "Zone")


func current_zone_path() -> String:
	return ZONE_PATH


## Nom générique — le biome de la salle SUIVANTE est tiré au sort à son
## instanciation, donc inconnu ici ; CombatArena préfixe le nom du biome
## courant via _zone_label().
func get_zone_name() -> String:
	return "Salle %d" % (rooms_cleared + 1)


func get_exits(count: int = 2) -> Array[Dictionary]:
	var next_floor := rooms_cleared + 2   # salle affichée = suivante (1-indexée)
	var depth := rooms_cleared + 1        # profondeur de la zone suivante

	# Chaque porte propose un BIOME DIFFÉRENT tiré du pool de profondeur — le
	# choix de porte détermine le biome suivant (cf. advance / _on_exit_chosen).
	var biome_pool := _pool_for_depth(depth).duplicate()
	biome_pool.shuffle()

	# Type de DON annoncé par chaque porte (façon Hades) : alterné entre les
	# deux portes pour offrir un vrai choix skill/stats quand c'est possible.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var first_bonus := BONUS_SKILL if rng.randf() < 0.5 else BONUS_STAT

	var exits: Array[Dictionary] = []
	for i in count:
		var theme: int = biome_pool[i % biome_pool.size()]
		var btype := first_bonus if i == 0 else (BONUS_STAT if first_bonus == BONUS_SKILL else BONUS_SKILL)
		exits.append({
			"zone_idx":    0,
			"biome":       theme,
			"zone_name":   "%s · Salle %d" % [biome_name(theme), next_floor],
			"bonus_type":  btype,
			"bonus_label": bonus_type_label(btype),
		})
	return exits


## Passe à la zone suivante. `chosen_biome` (porte choisie, -1 = garder la
## séquence) écrase le biome ; `chosen_bonus` (-1 = inchangé) fixe le type de
## don de la nouvelle zone (annoncé par la porte).
func advance(chosen_biome: int = -1, chosen_bonus: int = -1) -> void:
	current_zone_idx = 0
	rooms_cleared   += 1
	if chosen_biome >= 0:
		_ensure_sequence()
		_biome_sequence[mini(rooms_cleared, _biome_sequence.size() - 1)] = chosen_biome
	if chosen_bonus >= 0:
		current_zone_bonus = chosen_bonus
