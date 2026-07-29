class_name PokemonInstance
extends RefCounted

var data: PokemonData
var level: int = 5
var current_hp: int = 0
var max_hp: int = 0
var current_xp: int = 0

# Attaques
var learned_moves: Array = []    # MoveData[] — toutes les attaques apprises
var equipped_moves: Array = []   # MoveData[] — les 4 équipées (sous-ensemble)

# Portrait pour l'UI (optionnel, injecté par CombatArena)
var portrait_texture: Texture2D = null

# Multiplicateurs de stats (bonus de run cumulables)
var attack_mult:     float = 1.0
var defense_mult:    float = 1.0
var speed_mult:      float = 1.0
var max_hp_mult:     float = 1.0
var sp_attack_mult:  float = 1.0
var sp_defense_mult: float = 1.0
var range_mult:      float = 1.0   # portée des attaques (cf. TeamMember._move_range_max/min)

# Coup critique / esquive — bonus de fin de zone (0.0 par défaut, cumulables,
# bornés pour rester lisibles même en cumulant plusieurs dons dans une run).
var crit_chance:  float = 0.0
var dodge_chance: float = 0.0
const _CRIT_CAP  := 0.60
const _DODGE_CAP := 0.50

func add_crit_chance(delta: float) -> void:
	crit_chance = clampf(crit_chance + delta, 0.0, _CRIT_CAP)

func add_dodge_chance(delta: float) -> void:
	dodge_chance = clampf(dodge_chance + delta, 0.0, _DODGE_CAP)

# Objet tenu — un seul à la fois par Pokémon ({} si aucun)
var held_item: Dictionary = {}

## Rappels équipés (façon Hades) — cf. GameManager.pokemon_revives. Consommés
## automatiquement à 0 PV (CombatArena._try_auto_revive), un par ranimation.
var revive_charges: int = 0

# ── Altération de statut (cf. StatusFx) ──────────────────────────────
var status: String = ""          # "" | burn | poison | paralysis | freeze | sleep
var status_time: float = 0.0
var _dot_timer: float = 0.0
const _DOT_INTERVAL := 0.9


## Inflige `kind` pour `dur` secondes. N'écrase pas un statut déjà actif
## (un Pokémon ne cumule pas les altérations).
func apply_status(kind: String, dur: float) -> bool:
	if status != "" or kind == "":
		return false
	status      = kind
	status_time = dur
	_dot_timer  = 0.0
	return true


func clear_status() -> void:
	status = ""
	status_time = 0.0


## Avance le statut d'un pas de temps. Retourne les dégâts sur la durée à
## infliger CETTE frame (0 la plupart du temps ; un « tic » toutes les
## _DOT_INTERVAL s pour brûlure/poison). Met à jour l'expiration.
func tick_status(delta: float) -> int:
	if status == "":
		return 0
	status_time -= delta
	if status_time <= 0.0:
		clear_status()
		return 0
	var dot: float = StatusFx.INFO.get(status, {}).get("dot", 0.0)
	if dot > 0.0:
		_dot_timer += delta
		if _dot_timer >= _DOT_INTERVAL:
			_dot_timer -= _DOT_INTERVAL
			return maxi(1, int(float(max_hp) * dot))
	return 0


## Peut agir (se déplacer / attaquer) ? Faux sous sommeil ou gel.
func status_can_act() -> bool:
	return status != "sleep" and status != "freeze"


## Multiplicateur de vitesse dû au statut (paralysie = moitié).
func status_speed_mult() -> float:
	return 0.5 if status == "paralysis" else 1.0


func _init(pokemon_data: PokemonData, lv: int = 5) -> void:
	data       = pokemon_data
	level      = lv
	current_xp = _xp_for_level(lv)
	max_hp     = _calc_max_hp()
	current_hp = max_hp


# ── Attaques ─────────────────────────────────────────────────────────

func init_moves() -> void:
	learned_moves.clear()
	equipped_moves.clear()
	for md: MoveData in data.preloaded_moves:
		if md.level_learned <= level:
			learned_moves.append(md)

	# LE BUILD FAIT FOI. On applique exactement la règle du Pokédex
	# (GameManager.effective_loadout) sur les mêmes capacités disponibles :
	# avant, seules les CT du loadout étaient honorées et les attaques de base
	# recomplétées dans l'ordre interne — le build affiché n'était pas celui
	# joué (retour joueurs). Le cache de puissance étant persistant, le tri de
	# repli donne le même résultat des deux côtés.
	var available: Array = []
	for md: MoveData in learned_moves:
		GameManager.note_move_power(md.api_name, md.power)
		if not md.api_name in available:
			available.append(md.api_name)

	for api_name in GameManager.effective_loadout(data.id, available):
		for md: MoveData in learned_moves:
			if md.api_name == api_name and md not in equipped_moves:
				equipped_moves.append(md)
				break


func add_move(md: MoveData) -> void:
	if md not in learned_moves:
		learned_moves.append(md)
	if equipped_moves.size() < GameManager.move_slot_count and md not in equipped_moves:
		equipped_moves.append(md)


func check_new_moves() -> Array:
	var new_moves: Array = []
	for md: MoveData in data.preloaded_moves:
		if md.level_learned <= level and md not in learned_moves:
			learned_moves.append(md)
			new_moves.append(md)
			if equipped_moves.size() < GameManager.move_slot_count:
				equipped_moves.append(md)
	return new_moves


func get_attack_type() -> String:
	if not equipped_moves.is_empty():
		return (equipped_moves[0] as MoveData).type
	return data.types[0] if not data.types.is_empty() else "normal"


func get_attack_power() -> int:
	if not equipped_moves.is_empty():
		var p: int = (equipped_moves[0] as MoveData).power
		return p if p > 0 else 40
	return 40

func get_attack_class() -> String:
	if not equipped_moves.is_empty():
		return (equipped_moves[0] as MoveData).damage_class
	return "physical"


# ── PV ───────────────────────────────────────────────────────────────

func get_effective_attack() -> int:
	return int(float(data.attack) * attack_mult)

func get_effective_defense() -> int:
	return int(float(data.defense) * defense_mult)

func get_effective_sp_attack() -> int:
	return int(float(data.sp_attack) * sp_attack_mult)

func get_effective_sp_defense() -> int:
	return int(float(data.sp_defense) * sp_defense_mult)

func get_effective_speed() -> int:
	return int(float(data.speed) * speed_mult)

func apply_hp_boost(factor: float) -> void:
	# Les PV gagnés en max sont AUSSI crédités en PV courants (façon Hades) :
	# préserver le ratio rendait le bonus invisible (même barre, ex. 50/100 →
	# 60/120) — le joueur croyait que le boost ne faisait rien.
	var old_max := max_hp
	max_hp_mult *= factor
	max_hp = _calc_max_hp()
	current_hp = mini(max_hp, current_hp + maxi(0, max_hp - old_max))

func _calc_max_hp() -> int:
	var base: int = int(floor((2.0 * data.hp * level / 100.0) + level + 10))
	return int(float(base) * max_hp_mult)


func heal_percent(pct: float) -> void:
	current_hp = mini(max_hp, current_hp + int(float(max_hp) * pct))


# ── Objet tenu ───────────────────────────────────────────────────────

## Équipe `item` ({api_name, name_fr, effect, mult}). Un objet à effet de
## stat (atk/def/spd) remplace l'objet précédemment tenu (son bonus est
## retiré avant). Un objet "hp" est un consommable (soin instantané) —
## il n'est jamais conservé comme objet tenu.
func equip_item(item: Dictionary) -> void:
	var effect: String = item.get("effect", "")
	if effect == "hp":
		var add_hp := int(float(max_hp) * float(item.get("mult", 1.0)))
		current_hp = mini(max_hp, current_hp + add_hp)
		return
	if not held_item.is_empty():
		_unapply_stat_mult(held_item)
	held_item = item.duplicate()
	_apply_stat_mult(held_item)


func _apply_stat_mult(item: Dictionary) -> void:
	var mult: float = item.get("mult", 1.0)
	match item.get("effect", ""):
		"atk":     attack_mult     *= mult
		"def":     defense_mult    *= mult
		"spatk":   sp_attack_mult  *= mult
		"spdef":   sp_defense_mult *= mult
		"spd":     speed_mult      *= mult
		"maxhp":   apply_hp_boost(mult)


func _unapply_stat_mult(item: Dictionary) -> void:
	var mult: float = item.get("mult", 1.0)
	if mult == 0.0: return
	match item.get("effect", ""):
		"atk":     attack_mult     /= mult
		"def":     defense_mult    /= mult
		"spatk":   sp_attack_mult  /= mult
		"spdef":   sp_defense_mult /= mult
		"spd":     speed_mult      /= mult
		"maxhp":   apply_hp_boost(1.0 / mult)


## Équipe l'objet tenu du catalogue assigné à ce Pokémon (cf.
## GameManager.pokemon_item) — appelé une fois au spawn de run.
func equip_catalog_item(api: String) -> void:
	var it := ItemCatalog.get_item(api)
	if it.is_empty() or it.get("kind", "") != "held":
		return
	held_item = it.duplicate()
	_apply_stat_mult(held_item)

func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)


func is_fainted() -> bool:
	return current_hp <= 0


func hp_ratio() -> float:
	if max_hp == 0:
		return 0.0
	return float(current_hp) / float(max_hp)


# ── Expérience & Niveaux ─────────────────────────────────────────────

func _xp_for_level(n: int) -> int:
	return n * n * n


func add_xp(amount: int) -> bool:
	current_xp += amount
	var leveled_up := false
	while current_xp >= _xp_for_level(level + 1):
		level += 1
		_recalculate_stats()
		check_new_moves()
		leveled_up = true
	return leveled_up


func xp_ratio() -> float:
	var base_xp := _xp_for_level(level)
	var next_xp := _xp_for_level(level + 1)
	var span    := next_xp - base_xp
	if span <= 0:
		return 1.0
	return clamp(float(current_xp - base_xp) / float(span), 0.0, 1.0)


func _recalculate_stats() -> void:
	var old_ratio := hp_ratio()
	max_hp     = _calc_max_hp()
	current_hp = int(round(old_ratio * max_hp))


# ── Évolution ────────────────────────────────────────────────────────

func evolve_to(new_data: PokemonData) -> void:
	data = new_data
	_recalculate_stats()
	current_hp = max_hp
