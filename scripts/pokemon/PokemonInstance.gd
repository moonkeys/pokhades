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
var attack_mult:  float = 1.0
var defense_mult: float = 1.0
var speed_mult:   float = 1.0
var max_hp_mult:  float = 1.0


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
	var slots := GameManager.move_slot_count
	var count  := mini(slots, learned_moves.size())
	for i in count:
		equipped_moves.append(learned_moves[i])


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


# ── PV ───────────────────────────────────────────────────────────────

func get_effective_attack() -> int:
	return int(float(data.attack) * attack_mult)

func get_effective_defense() -> int:
	return int(float(data.defense) * defense_mult)

func get_effective_speed() -> int:
	return int(float(data.speed) * speed_mult)

func apply_hp_boost(factor: float) -> void:
	var ratio: float = hp_ratio()
	max_hp_mult *= factor
	max_hp = _calc_max_hp()
	current_hp = int(ratio * float(max_hp))

func _calc_max_hp() -> int:
	var base: int = int(floor((2.0 * data.hp * level / 100.0) + level + 10))
	return int(float(base) * max_hp_mult)


func heal_percent(pct: float) -> void:
	current_hp = mini(max_hp, current_hp + int(float(max_hp) * pct))

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
