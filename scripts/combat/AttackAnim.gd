class_name AttackAnim
extends RefCounted

## Animations d'attaque — planches RPG Maker/Essentials (Graphics/Animations,
## frames 192×192 lues ligne par ligne) jouées en billboard sur la cible
## touchée. Une planche par TYPE d'attaque ; découpe et SpriteFrames mis en
## cache au premier usage (les frames vides de fin de planche sont sautées).
## Usage : AttackAnim.play(parent, position, "fire")

const DIR      := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Animations/"
const FRAME_PX := 192
const FPS      := 22.0
const WORLD_H  := 2.6    # taille monde de l'effet (~ la taille d'un Pokémon)

# Planche par type d'attaque. `tint` : teinte optionnelle (planche réutilisée
# pour un type proche). Fichiers vérifiés : dimensions multiples de 192.
const TYPE_SHEETS := {
	"normal":   {"file": "003-Attack01.png"},
	"fighting": {"file": "023-Burst01.png"},
	"fire":     {"file": "015-Fire01.png"},
	"water":    {"file": "018-Water01.png"},
	"electric": {"file": "017-Thunder01.png"},
	"ice":      {"file": "Ice1.png"},
	"grass":    {"file": "023-Burst01.png", "tint": Color(0.45, 1.0, 0.40)},
	"ground":   {"file": "Earth1.png"},
	"rock":     {"file": "Rock Tomb.png"},
	"flying":   {"file": "Wind1.png"},
	"psychic":  {"file": "Psycho Cut.png"},
	"bug":      {"file": "Scratch + Shadow Claw.png", "tint": Color(0.75, 1.0, 0.55)},
	"ghost":    {"file": "022-Darkness01.png"},
	"dark":     {"file": "Crunch.png"},
	"steel":    {"file": "Iron Head.png"},
	"poison":   {"file": "022-Darkness01.png", "tint": Color(0.85, 0.45, 1.0)},
	"dragon":   {"file": "023-Burst01.png", "tint": Color(0.55, 0.55, 1.0)},
	"fairy":    {"file": "Light1.png"},
}

static var _frames_cache: Dictionary = {}   # file -> SpriteFrames (ou null si illisible)


## Joue l'animation du type `move_type` à `pos` (position monde de la cible).
static func play(parent: Node, pos: Vector3, move_type: String) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var cfg: Dictionary = TYPE_SHEETS.get(move_type, TYPE_SHEETS["normal"])
	var frames := _get_frames(cfg["file"])
	if frames == null:
		return

	var spr := AnimatedSprite3D.new()
	spr.sprite_frames  = frames
	spr.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded         = false
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size     = WORLD_H / float(FRAME_PX)
	spr.modulate       = cfg.get("tint", Color.WHITE)
	spr.no_depth_test  = true     # l'effet reste lisible devant la cible
	spr.render_priority = 10
	spr.position       = pos + Vector3(0, 1.0, 0)
	parent.add_child(spr)
	spr.play("fx")
	spr.animation_finished.connect(spr.queue_free)


## SpriteFrames découpé depuis la planche (cache statique partagé).
static func _get_frames(file: String) -> SpriteFrames:
	if _frames_cache.has(file):
		return _frames_cache[file]
	var tex: Texture2D = load(DIR + file)
	if tex == null:
		push_warning("AttackAnim: planche introuvable %s" % file)
		_frames_cache[file] = null
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var cols := img.get_width() / FRAME_PX
	var rows := img.get_height() / FRAME_PX
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("fx")
	frames.set_animation_loop("fx", false)
	for r in rows:
		for c in cols:
			var region := img.get_region(Rect2i(c * FRAME_PX, r * FRAME_PX, FRAME_PX, FRAME_PX))
			if region.is_invisible():
				continue   # frames vides de fin de planche
			frames.add_frame("fx", ImageTexture.create_from_image(region))
	var count := frames.get_frame_count("fx")
	if count == 0:
		_frames_cache[file] = null
		return null
	# Vitesse plafonnée pour que l'effet dure au moins ~0,3 s même sur une
	# planche courte (2-3 frames) — sinon il clignote sans être lisible.
	frames.set_animation_speed("fx", minf(FPS, count / 0.3))
	_frames_cache[file] = frames
	return frames
