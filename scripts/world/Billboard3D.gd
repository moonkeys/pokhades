class_name Billboard3D
extends RefCounted

## Utilitaire partagé pour les personnages en sprite PMD billboardé (HD-2D).
## Logique validée dans le prototype scripts/world/Proto3DTest.gd — centralisée
## ici pour être réutilisée par HubPlayer/HubNPC (Hub) et plus tard
## TeamMember/EnemyAI (Combat, phase 2) sans dupliquer le calcul.

const PIXEL_SIZE := 0.032   # taille rééquilibrée après retour utilisateur

## Largeur monde cible d'un personnage — PARTAGÉE Hub/Combat pour un zoom
## cohérent entre les deux modes (cf. TeamMember.DISPLAY_UNITS).
const CHAR_WIDTH := 1.75


## Dimensionne un sprite pour occuper `width` unités de large (indépendant de
## la résolution de la frame) et ancre ses pieds au sol. Utilisé par le Hub et
## le Combat pour que les personnages aient la MÊME taille dans les deux modes.
static func size_to_width(sprite: AnimatedSprite3D, pmd_result: Dictionary,
		width: float = CHAR_WIDTH, extra_lift: float = 0.0) -> void:
	var frame_size: Vector2i = pmd_result.get("frame_size", Vector2i(32, 40))
	var ps := width / float(maxi(frame_size.x, 1))
	sprite.pixel_size = ps
	align_feet(sprite, pmd_result, extra_lift, ps)


## Configure un AnimatedSprite3D pour un rendu billboard HD-2D cohérent.
static func setup_sprite(sprite: AnimatedSprite3D) -> void:
	sprite.billboard      = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size     = PIXEL_SIZE
	sprite.centered       = true
	sprite.shaded         = true
	sprite.double_sided   = true
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # pixel net, pas de flou en agrandissant


## Ajuste la position Y du sprite pour que ses "pieds" (vrai pixel opaque le
## plus bas, via `foot_row` renvoyé par PMDSprites) touchent le sol à y=0 —
## le bord de la frame a souvent une marge vide, s'y fier ferait flotter le
## personnage. `pixel_size` permet un sprite dimensionné différemment du
## standard (ex : Pokémon de combat, plus grands que les personnages du Hub).
static func align_feet(sprite: AnimatedSprite3D, pmd_result: Dictionary, extra_lift: float = 0.0, pixel_size: float = PIXEL_SIZE) -> void:
	var frame_size: Vector2i = pmd_result.get("frame_size", Vector2i(32, 40))
	var foot_row: int        = pmd_result.get("foot_row", frame_size.y - 1)
	sprite.position.y = (float(foot_row) - float(frame_size.y) * 0.5) * pixel_size + extra_lift


## Ombre "blob" au sol (quad plat + dégradé radial partagé de ShadowTexture) —
## complément de lisibilité sous les personnages billboard, dont l'ombre
## portée réelle est partielle. `size` en unités monde (x = largeur, y = profondeur).
static func make_blob_shadow(size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = size
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture     = ShadowTexture.get_texture()
	mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test       = false
	mat.cull_mode           = BaseMaterial3D.CULL_BACK
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y  = 0.02   # juste au-dessus du sol, évite le z-fight
	return mi


## Direction monde (x, z) → nom d'animation à 8 directions (même mapping que
## la version 2D — dir.y ici représente le z monde).
static func dir_to_anim(dir: Vector2) -> String:
	if dir.length() < 0.1:
		return "idle"
	var sector := int(round(fposmod(dir.angle(), TAU) / (TAU / 8.0))) % 8
	match sector:
		0: return "walk_right"
		1: return "walk_downright"
		2: return "walk_down"
		3: return "walk_downleft"
		4: return "walk_left"
		5: return "walk_upleft"
		6: return "walk_up"
		_: return "walk_upright"


# ── Props statiques depuis un tileset (arbres, lampadaires, tournesols…) ──
# Même principe que ci-dessus mais pour des sprites non-animés découpés
# d'une image de tileset partagée (pas de SpriteFrames/PMD).

const TILE_PX := 16

static var _tileset_image_cache: Dictionary = {}   # path -> Image


## Accès public à l'image du tileset (cache partagé) — utilisé par le bake
## du sol des maps de combat (MapRender3D) en plus des crops de props.
static func get_tileset_image(path: String) -> Image:
	return _get_tileset_image(path)


static func _get_tileset_image(path: String) -> Image:
	if not _tileset_image_cache.has(path):
		var tex: Texture2D = load(path)
		var img := tex.get_image() if tex else null
		if img != null and img.is_compressed():
			img.decompress()
		_tileset_image_cache[path] = img
	return _tileset_image_cache[path]


## Découpe une région du tileset (en tuiles) et retourne une texture isolée.
## `tile_px` permet d'utiliser un tileset externe avec une taille de tuile
## différente de TILE_PX (ex: 32px pour un tileset RPG Maker).
static func crop_tile(tileset_path: String, atlas_cell: Vector2i, cw: int = 1, ch: int = 1, tile_px: int = TILE_PX) -> ImageTexture:
	var img := _get_tileset_image(tileset_path)
	if img == null:
		return null
	var region := Rect2i(atlas_cell.x * tile_px, atlas_cell.y * tile_px, cw * tile_px, ch * tile_px)
	return ImageTexture.create_from_image(img.get_region(region))


## Sprite3D billboard construit à partir d'une région du tileset, ancré au
## sol via détection du vrai pixel opaque le plus bas (même logique que
## align_feet — les blocs de tuiles ont souvent une marge vide en bas).
static func make_tile_sprite(tileset_path: String, atlas_cell: Vector2i, cw: int, ch: int, scale_mult: float = 1.0, tile_px: int = TILE_PX) -> Sprite3D:
	var spr := Sprite3D.new()
	var img := _get_tileset_image(tileset_path)
	if img == null:
		return spr

	var region := Rect2i(atlas_cell.x * tile_px, atlas_cell.y * tile_px, cw * tile_px, ch * tile_px)
	var cropped := img.get_region(region)
	spr.texture         = ImageTexture.create_from_image(cropped)
	spr.billboard        = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.pixel_size       = scale_mult / float(tile_px)
	spr.centered         = true
	spr.shaded           = true
	spr.alpha_cut        = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var full_h := ch * tile_px
	var foot_row := _find_foot_row(cropped)
	var pad_below := float(full_h - 1 - foot_row)
	spr.offset = Vector2(0, float(full_h) * 0.5 - pad_below)
	return spr


## Sprite3D billboard à partir d'un fichier image complet (pas un crop de
## tileset) — même ancrage au sol par détection de pixel que make_tile_sprite.
static func make_sprite_from_file(path: String, scale_mult: float = 1.0) -> Sprite3D:
	var spr := Sprite3D.new()
	var tex: Texture2D = load(path)
	if tex == null:
		return spr
	spr.texture = tex
	spr.billboard      = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.pixel_size     = scale_mult / float(TILE_PX)
	spr.centered       = true
	spr.shaded         = true
	spr.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var full_h := img.get_height()
		var foot_row := _find_foot_row(img)
		var pad_below := float(full_h - 1 - foot_row)
		spr.offset = Vector2(0, float(full_h) * 0.5 - pad_below)
	return spr


## Comme make_sprite_from_file, mais dimensionne le sprite pour occuper
## exactement `target_width` unités monde de large — utile pour des variantes
## générées séparément dont la résolution source n'est pas identique.
static func make_sprite_from_file_sized(path: String, target_width: float) -> Sprite3D:
	var tex: Texture2D = load(path)
	if tex == null:
		return Sprite3D.new()
	var native_w := tex.get_width()
	var scale_mult := (target_width * float(TILE_PX)) / float(maxi(native_w, 1))
	return make_sprite_from_file(path, scale_mult)


## Comme make_sprite_from_file_sized, mais dimensionne par la hauteur cible —
## plus pertinent pour des objets tout en hauteur (lampadaires, poteaux).
static func make_sprite_from_file_sized_by_height(path: String, target_height: float) -> Sprite3D:
	var tex: Texture2D = load(path)
	if tex == null:
		return Sprite3D.new()
	var native_h := tex.get_height()
	var scale_mult := (target_height * float(TILE_PX)) / float(maxi(native_h, 1))
	return make_sprite_from_file(path, scale_mult)


# ── Dresseurs (combats de boss) — planches Characters/trainer_*.png,
# convention RPG Maker/Essentials : 4 colonnes (frames de marche) × 4
# lignes (bas/gauche/droite/haut), 32×48 px par case. ───────────────────

const TRAINER_FRAME_W := 32
const TRAINER_FRAME_H := 48
const TRAINER_DIR_ROWS := {"walk_down": 0, "walk_left": 1, "walk_right": 2, "walk_up": 3}

## Construit un SpriteFrames 4-directions + "idle" à partir d'une planche
## dresseur Essentials. Retourne {"frames": SpriteFrames, "frame_size":
## Vector2i} — même forme que PMDSprites.get_walk_sprites(), réutilisable
## telle quelle par align_feet()/size_to_width().
static func make_trainer_frames(path: String) -> Dictionary:
	var img := _get_tileset_image(path)
	if img == null:
		return {}
	var frames := SpriteFrames.new()
	for anim in TRAINER_DIR_ROWS:
		var row: int = TRAINER_DIR_ROWS[anim]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 6.0)
		frames.set_animation_loop(anim, true)
		for col in 4:
			var region := Rect2i(col * TRAINER_FRAME_W, row * TRAINER_FRAME_H,
				TRAINER_FRAME_W, TRAINER_FRAME_H)
			frames.add_frame(anim, ImageTexture.create_from_image(img.get_region(region)))
	# idle = la case neutre (colonne 0, ligne "bas"), figée
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 1.0)
	var idle_region := Rect2i(0, 0, TRAINER_FRAME_W, TRAINER_FRAME_H)
	frames.add_frame("idle", ImageTexture.create_from_image(img.get_region(idle_region)))
	return {"frames": frames, "frame_size": Vector2i(TRAINER_FRAME_W, TRAINER_FRAME_H)}


static func _find_foot_row(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var lowest := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.05:
				lowest = y
	return lowest if lowest != -1 else h - 1


## Largeur réelle (en unités monde) occupée par les pixels opaques d'un
## crop de tileset — utile pour dimensionner une collision qui colle
## vraiment au sprite visible (au lieu d'une largeur devinée trop étroite,
## qui laisse le joueur se faufiler sur les côtés).
static func get_tile_sprite_width(tileset_path: String, atlas_cell: Vector2i, cw: int, ch: int, scale_mult: float = 1.0, tile_px: int = TILE_PX) -> float:
	var img := _get_tileset_image(tileset_path)
	if img == null:
		return float(cw) * scale_mult
	var region := Rect2i(atlas_cell.x * tile_px, atlas_cell.y * tile_px, cw * tile_px, ch * tile_px)
	var cropped := img.get_region(region)
	var w := cropped.get_width()
	var h := cropped.get_height()
	var min_x := -1
	var max_x := -1
	for x in range(w):
		for y in range(h):
			if cropped.get_pixel(x, y).a > 0.05:
				if min_x == -1:
					min_x = x
				max_x = x
				break
	if min_x == -1:
		return float(cw) * scale_mult
	return float(max_x - min_x + 1) / float(tile_px) * scale_mult
