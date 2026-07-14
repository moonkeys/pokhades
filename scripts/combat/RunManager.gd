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


# ── Structure de run en ACTES (façon Hades) ──────────────────────────
# Un acte = UN SEUL biome enchaîné : 5 salles de combat, puis la BOUTIQUE,
# puis le BOSS de l'acte. 4 actes ; le boss du dernier acte est le
# DRESSEUR FINAL (compo de champion d'arène). Plus de mélange de biomes
# salle par salle : on s'installe dans une région, puis on change.
const COMBATS_PER_ACT := 5
const ROOMS_PER_ACT   := COMBATS_PER_ACT + 2   # + boutique + boss
const ACTS            := 4

func act_of(room: int) -> int:
	return clampi(room / ROOMS_PER_ACT, 0, ACTS - 1)

func is_shop_room(room: int) -> bool:
	return room % ROOMS_PER_ACT == COMBATS_PER_ACT

func is_boss_room(room: int) -> bool:
	return room % ROOMS_PER_ACT == ROOMS_PER_ACT - 1

func is_final_boss_room(room: int) -> bool:
	return is_boss_room(room) and act_of(room) >= ACTS - 1


## Séquence de biomes de la run — UN biome par ACTE, construite au départ
## (départ doux → montée en rudesse, jamais deux actes identiques d'affilée).
## Lue par MapGenerator._apply_theme (cf. current_biome).
var _biome_sequence: Array[int] = []
var _seq_run_id: int = -1   # run_count pour lequel la séquence a été construite


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


## Pool de biomes autorisés pour un ACTE donné — se durcit au fil des actes.
## L'acte 1 est TOUJOURS la Prairie : faune de type Normal, la plus douce
## pour démarrer une run (et son champion, Blanche, est de type Normal).
func _pool_for_act(act: int) -> Array[int]:
	match act:
		0: return [MapGenerator.MapTheme.MEADOW]
		1: return [MapGenerator.MapTheme.FOREST, MapGenerator.MapTheme.AUTUMN, MapGenerator.MapTheme.LAKE]
		2: return [MapGenerator.MapTheme.SWAMP, MapGenerator.MapTheme.LAKE, MapGenerator.MapTheme.AUTUMN]
		_: return [MapGenerator.MapTheme.ROCKY, MapGenerator.MapTheme.SWAMP, MapGenerator.MapTheme.VOLCANO]


## UN biome par acte (jamais deux actes identiques d'affilée) + le CHAMPION
## de chaque acte est ASSORTI AU TYPE de son biome (Prairie → Blanche/Normal,
## Lac → Ondine/Eau… cf. PokePools.BIOME_CHAMPIONS), en évitant de revoir le
## même champion deux fois dans la run quand c'est possible.
var _champion_sequence: Array[String] = []   # nom de compo par acte

func _build_biome_sequence() -> void:
	var rng := RandomNumberGenerator.new()
	# Multijoueur : séquence identique sur tous les pairs (dérivée de la
	# graine partagée) — sinon chacun verrait des biomes différents.
	if Net.in_run:
		rng.seed = Net.zone_seed(-1)
	else:
		rng.randomize()
	_biome_sequence.clear()
	_champion_sequence.clear()
	var prev := -1
	for act in ACTS:
		var pool := _pool_for_act(act).duplicate()
		pool.erase(prev)   # pas deux fois la même région d'affilée
		if pool.is_empty():
			pool = _pool_for_act(act)
		var pick: int = pool[rng.randi() % pool.size()]
		_biome_sequence.append(pick)
		prev = pick
		# Champion du biome — un candidat pas encore affronté si possible
		var cands: Array = (PokePools.BIOME_CHAMPIONS.get(pick, ["Blanche"]) as Array).duplicate()
		var fresh := cands.filter(func(n: String) -> bool: return n not in _champion_sequence)
		if not fresh.is_empty():
			cands = fresh
		_champion_sequence.append(cands[rng.randi() % cands.size()])


## Compo de champion (PokePools.CHAMPION_TEAMS) affrontée au boss de `act` —
## toujours du type de la région.
func champion_for_act(act: int) -> Dictionary:
	_ensure_sequence()
	var team := PokePools.team_by_name(_champion_sequence[clampi(act, 0, ACTS - 1)])
	return team if not team.is_empty() else PokePools.CHAMPION_TEAMS[0]


## Biome (MapGenerator.MapTheme) de la zone courante — celui de l'ACTE.
func current_biome() -> int:
	_ensure_sequence()
	return _biome_sequence[act_of(rooms_cleared)]


## Biome de la zone à `depth` salles nettoyées (pour annoncer la suivante).
func biome_at(depth: int) -> int:
	_ensure_sequence()
	return _biome_sequence[act_of(depth)]


const BIOME_NAMES := {
	MapGenerator.MapTheme.FOREST: "Forêt",
	MapGenerator.MapTheme.SWAMP:  "Marécage",
	MapGenerator.MapTheme.MEADOW: "Prairie",
	MapGenerator.MapTheme.ROCKY:  "Montagne",
	MapGenerator.MapTheme.AUTUMN: "Bois d'automne",
	MapGenerator.MapTheme.LAKE:   "Lac",
	MapGenerator.MapTheme.VOLCANO: "Volcan",
}

func biome_name(theme: int) -> String:
	return BIOME_NAMES.get(theme, "Zone")


func current_zone_path() -> String:
	return ZONE_PATH


## Étiquette de la salle courante au sein de son acte — la structure de la
## run se lit d'un coup d'œil ("Acte 2 · Salle 3/5", "Boutique", "Boss").
func get_zone_name() -> String:
	var room := rooms_cleared
	var act := act_of(room) + 1
	if is_final_boss_room(room):
		return "Acte %d · DRESSEUR FINAL" % act
	if is_boss_room(room):
		return "Acte %d · Boss" % act
	if is_shop_room(room):
		return "Acte %d · Boutique" % act
	return "Acte %d · Salle %d/%d" % [act, room % ROOMS_PER_ACT + 1, COMBATS_PER_ACT]


## Étiquette d'une salle à venir (portes de sortie).
func _room_label(room: int) -> String:
	var theme := biome_at(room)
	if is_final_boss_room(room):
		return "%s · ☠ DRESSEUR FINAL" % biome_name(theme)
	if is_boss_room(room):
		return "%s · ☠ Boss d'acte" % biome_name(theme)
	if is_shop_room(room):
		return "%s · 🛍 Boutique" % biome_name(theme)
	return "%s · Salle %d/%d" % [biome_name(theme), room % ROOMS_PER_ACT + 1, COMBATS_PER_ACT]


func get_exits(count: int = 2) -> Array[Dictionary]:
	var depth := rooms_cleared + 1   # salle suivante
	# Le BIOME est imposé par l'acte — les deux portes ne diffèrent que par
	# le TYPE DE DON de la salle suivante (façon Hades : on choisit sa
	# récompense, pas sa région).
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var first_bonus := BONUS_SKILL if rng.randf() < 0.5 else BONUS_STAT

	var exits: Array[Dictionary] = []
	for i in count:
		var btype := first_bonus if i == 0 else (BONUS_STAT if first_bonus == BONUS_SKILL else BONUS_SKILL)
		exits.append({
			"zone_idx":    0,
			"biome":       biome_at(depth),
			"zone_name":   _room_label(depth),
			"bonus_type":  btype,
			"bonus_label": bonus_type_label(btype),
		})
	return exits


## Passe à la zone suivante. Le biome est imposé par l'ACTE (le paramètre
## `_chosen_biome` est conservé pour compat mais ignoré) ; `chosen_bonus`
## (-1 = inchangé) fixe le type de don de la nouvelle zone (porte choisie).
func advance(_chosen_biome: int = -1, chosen_bonus: int = -1) -> void:
	current_zone_idx = 0
	rooms_cleared   += 1
	if chosen_bonus >= 0:
		current_zone_bonus = chosen_bonus
