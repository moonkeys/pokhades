class_name BerryTree
extends Node3D

## Arbre à baies — sprite 2D billboardé, découpé dans une planche de personnage
## Pokémon Essentials (berrytree_<BAIE>.png, grille 4×4 de stades de croissance).
## On prend la case EN BAS À DROITE : l'arbre mûr, baies déjà dessinées dessus.
## Le type de baie dépend du biome (cf. MapRender3D). Bloque le passage
## (StaticBody3D) et se brise quand on l'ATTAQUE (les attaques du joueur le
## ciblent en plus des ennemis, cf. TeamMember._attack). À la casse, lâche des
## BerryPickup au sol, à l'effigie de l'item de la baie associée. Groupe
## "berry_trees".

const HP := 2                       # nombre de coups pour le briser
const TREE_H := 1.9                 # hauteur monde cible de l'arbre (uniforme, pas trop grand)
const SHEET_COLS := 4               # planche charset Essentials : 4 colonnes
const SHEET_ROWS := 4               # 4 rangées (stades de croissance)

const DEFAULT_TREE := "res://Pokemon Essentials v21.1 2023-07-30/Graphics/Characters/berrytree_AGUAVBERRY.png"
const DEFAULT_ITEM := "res://assets/items/aguav-berry.png"

var _hp: int = HP
var _broken: bool = false
var _sprite: Sprite3D = null
var _base_x: float = 0.0
var _item_path: String = DEFAULT_ITEM   # icône de la baie lâchée à la casse


## `tree_path` = planche berrytree_<BAIE>.png ; `item_path` = sprite d'item de
## la baie associée (lâchée à la casse). Choisis selon le biome par MapRender3D.
func setup(scale_mult: float = 1.0, seed_val: int = 0,
		tree_path: String = DEFAULT_TREE, item_path: String = DEFAULT_ITEM) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else randi()
	_item_path = item_path

	var target_h := TREE_H * scale_mult

	# Corps — case bas-droite (arbre mûr) de la planche 4×4, billboardée
	_sprite = Sprite3D.new()
	_sprite.name          = "Body"
	_sprite.texture       = _crop_mature(tree_path)
	_sprite.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded        = false
	_sprite.alpha_cut     = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var cell_h := 64.0
	if _sprite.texture:
		cell_h = float(_sprite.texture.get_height())
	_sprite.pixel_size    = target_h / maxf(1.0, cell_h)
	_sprite.position.y    = target_h * 0.5     # pied au niveau du sol
	# Prend la teinte de décor du biome courant (nuit cyan au marais, etc.) —
	# sinon le sprite non éclairé reste en couleurs plein jour et "sort" du
	# monde (cf. BiomeAmbiance.current_decor_tint).
	_sprite.modulate      = BiomeAmbiance.current_decor_tint
	add_child(_sprite)

	# Collision — tronc bloquant (couche 1, comme les arbres normaux)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.30 * scale_mult
	shape.height = target_h
	cs.shape = shape
	cs.position = Vector3(0, target_h * 0.5, 0)
	body.add_child(cs)
	add_child(body)

	add_to_group("berry_trees")


## Applique la teinte de décor du biome (appelée par BiomeAmbiance via le
## groupe "berry_trees" à chaque changement de biome).
func apply_biome_tint(col: Color) -> void:
	if is_instance_valid(_sprite):
		_sprite.modulate = col


## Découpe la case en bas à droite (arbre mûr, baies dessinées) de la planche.
func _crop_mature(path: String) -> Texture2D:
	var tex: Texture2D = load(path)
	if tex == null:
		tex = load(DEFAULT_TREE)
	if tex == null:
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var cw := img.get_width() / SHEET_COLS
	var ch := img.get_height() / SHEET_ROWS
	var region := img.get_region(Rect2i((SHEET_COLS - 1) * cw, (SHEET_ROWS - 1) * ch, cw, ch))
	return ImageTexture.create_from_image(region)


## Reçoit un coup d'attaque. Secoue le sprite ; au HP épuisé, se brise.
## `attacker_pos` sert à orienter l'éjection des baies.
func take_hit(attacker_pos: Vector3) -> void:
	if _broken:
		return
	_hp -= 1
	# Secousse visuelle — jitter horizontal (le billboard ignore la rotation)
	if is_instance_valid(_sprite):
		var tw := create_tween()
		tw.tween_property(_sprite, "position:x", _base_x + 0.10, 0.05)
		tw.tween_property(_sprite, "position:x", _base_x - 0.06, 0.06)
		tw.tween_property(_sprite, "position:x", _base_x, 0.06)
	Sfx.play("hit", -8.0, 0.2)
	if _hp <= 0:
		_break(attacker_pos)


func _break(attacker_pos: Vector3) -> void:
	_broken = true
	remove_from_group("berry_trees")

	# Lâche 2-4 baies au sol, à l'effigie de la baie associée
	var parent := get_parent()
	if is_instance_valid(parent):
		var n := randi_range(2, 4)
		for i in n:
			var berry := BerryPickup.new()
			berry.icon_path = _item_path
			berry.position = global_position + Vector3(randf_range(-0.6, 0.6), 0.3, randf_range(-0.6, 0.6))
			parent.add_child(berry)
		CombatVFX.spawn_death_poof(parent, global_position, Color(0.55, 0.75, 0.35))
	Sfx.play("death", -6.0)
	queue_free()
