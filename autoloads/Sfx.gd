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
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var path := DIR
	if VARIANTS.has(sfx_name):
		path += "%s_%d.ogg" % [sfx_name, randi() % int(VARIANTS[sfx_name])]
	else:
		path += "%s.ogg" % sfx_name
	play_file(path, volume_db, pitch_jitter)


## Joue un fichier audio arbitraire (SE/ME du pack Essentials) sur le même
## pool que les sons du jeu — ex : Sfx.play_file(Sfx.SE_MENU_OPEN).
func play_file(path: String, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var stream := _get_stream(path)
	if stream == null:
		return

	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream      = stream
	p.volume_db   = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# ── Chemins des SE/BGM Essentials utilisés par le jeu ────────────────────
const ESSENTIALS_AUDIO := "res://Pokemon Essentials v21.1 2023-07-30/Audio/"
const SE_MENU_OPEN   := ESSENTIALS_AUDIO + "SE/GUI menu open.ogg"
const SE_MENU_CLOSE  := ESSENTIALS_AUDIO + "SE/GUI menu close.ogg"
const SE_BUY_ITEM    := ESSENTIALS_AUDIO + "SE/Mart buy item.ogg"
const SE_MOVE_LEARNT := ESSENTIALS_AUDIO + "SE/Pkmn move learnt.ogg"
const ME_EVO_START   := ESSENTIALS_AUDIO + "ME/Evolution start.ogg"
const ME_EVO_SUCCESS := ESSENTIALS_AUDIO + "ME/Evolution success.ogg"
const BGM_BOSS       := ESSENTIALS_AUDIO + "BGM/Battle trainer.ogg"
const BGM_VICTORY    := ESSENTIALS_AUDIO + "BGM/Battle victory.ogg"
const BGM_EVOLUTION  := ESSENTIALS_AUDIO + "BGM/Evolution.ogg"


# ── Musique (BGM) — un seul lecteur, bus Master (le curseur "effets" ne
# touche pas la musique ; le volume général si). ─────────────────────────
var _music: AudioStreamPlayer = null
var _music_path: String = ""

func play_music(path: String, loop: bool = true, volume_db: float = -8.0) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.bus = "Master"
		add_child(_music)
	if _music_path == path and _music.playing:
		return
	var stream := _get_stream(path)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_music_path      = path
	_music.stream    = stream
	_music.volume_db = volume_db
	_music.play()


func stop_music() -> void:
	_music_path = ""
	if is_instance_valid(_music):
		_music.stop()


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
