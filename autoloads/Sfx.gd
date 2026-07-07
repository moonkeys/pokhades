extends Node

## Effets sonores du jeu — sons CC0 des packs Kenney (Impact Sounds,
## Interface Sounds, Music Jingles ; cf. assets/audio/License_*.txt).
##
## Usage : Sfx.play("hit"), Sfx.play("coin", -8.0). Un nom avec plusieurs
## variantes (hit_0..hit_4) en tire une au hasard ; le pitch est légèrement
## aléatoire pour que les répétitions rapides ne "mitraillent" pas.
## Pool de lecteurs en round-robin : les sons proches peuvent se chevaucher
## sans se couper.

const DIR := "res://assets/audio/"

## Nom logique → nombre de variantes (fichiers name_0.ogg … name_N-1.ogg).
## Absent du dictionnaire = fichier unique name.ogg.
const VARIANTS := {
	"hit": 5, "hurt": 5, "death": 5, "coin": 2, "dash": 2,
}

const POOL_SIZE := 10

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}   # chemin → AudioStream (cache)


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var path := DIR
	if VARIANTS.has(sfx_name):
		path += "%s_%d.ogg" % [sfx_name, randi() % int(VARIANTS[sfx_name])]
	else:
		path += "%s.ogg" % sfx_name

	var stream := _get_stream(path)
	if stream == null:
		return

	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream      = stream
	p.volume_db   = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _get_stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		push_warning("Sfx: son introuvable %s" % path)
		_streams[path] = null
		return null
	var stream: AudioStream = load(path)
	_streams[path] = stream
	return stream
