class_name PokemonData
extends RefCounted

var id: int = 0
var name_en: String = ""
var name_fr: String = ""
var types: Array = []
var hp: int = 45
var attack: int = 49
var defense: int = 49
var sp_attack: int = 65
var sp_defense: int = 65
var speed: int = 45
var sprite_url: String = ""

# Attaques niveau par niveau récupérées de PokéAPI
var level_up_moves: Array = []    # [{level: int, name: String}] triés par niveau
var preloaded_moves: Array = []   # MoveData[] chargés (power > 0 seulement)


static func from_api(data: Dictionary) -> PokemonData:
	var pd := PokemonData.new()
	pd.id       = int(data.get("id", 0))
	pd.name_en  = data.get("name_en", "")
	pd.name_fr  = data.get("name_fr", pd.name_en)
	pd.types    = data.get("types", ["normal"])
	pd.sprite_url = data.get("sprite_url", "")
	pd.level_up_moves = data.get("level_up_moves", [])
	var stats: Dictionary = data.get("stats", {})
	pd.hp        = stats.get("hp", 45)
	pd.attack    = stats.get("attack", 49)
	pd.defense   = stats.get("defense", 49)
	pd.sp_attack  = stats.get("special-attack", 65)
	pd.sp_defense = stats.get("special-defense", 65)
	pd.speed     = stats.get("speed", 45)
	return pd
