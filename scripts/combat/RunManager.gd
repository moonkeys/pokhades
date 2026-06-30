class_name RunManager

# Singleton statique — persiste entre les swaps de zone sans rechargement de scène.
static var _s: RunManager = null
static func inst() -> RunManager:
	if not _s:
		_s = RunManager.new()
	return _s


const ZONE_PATH := "res://scenes/world/Zone1.tscn"
const BONUSES: Array = [
	{"id": "heal_full", "label": "✚ Soin complet"},
	{"id": "heal_half", "label": "✚ Soin 50%"},
	{"id": "boost_atk", "label": "⚔ ATQ +20%"},
	{"id": "boost_def", "label": "🛡 DEF +20%"},
	{"id": "boost_hp",  "label": "♥ PV +20%"},
	{"id": "boost_spd", "label": "⚡ SPD +20%"},
]

var current_zone_idx: int = 0   # toujours 0 (Zone1)
var rooms_cleared:    int = 0


func start_run(_start_idx: int = 0) -> void:
	current_zone_idx = 0
	rooms_cleared    = 0


func current_zone_path() -> String:
	return ZONE_PATH


func get_zone_name() -> String:
	return "Prairie — Niveau %d" % (rooms_cleared + 1)


func get_exits(count: int = 2) -> Array[Dictionary]:
	var bonuses_pool := BONUSES.duplicate()
	bonuses_pool.shuffle()

	var next_floor := rooms_cleared + 1
	var exits: Array[Dictionary] = []
	for i in mini(count, bonuses_pool.size()):
		var bonus := bonuses_pool[i] as Dictionary
		exits.append({
			"zone_idx":    0,
			"zone_name":   "Prairie — Niveau %d" % next_floor,
			"bonus":       bonus.get("id", "heal_half"),
			"bonus_label": bonus.get("label", ""),
		})
	return exits


func advance(_next_zone_idx: int = 0) -> void:
	current_zone_idx = 0
	rooms_cleared   += 1
