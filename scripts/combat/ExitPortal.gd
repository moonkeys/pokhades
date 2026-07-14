class_name ExitPortal
extends Area3D

## Portail de sortie de zone — HD-2D (phase 2) : matérialisé par un petit
## bâtiment de jonction façon "porte de route" Pokémon (mur + toit en pente),
## plus lisible qu'un simple halo au sol pour marquer la fin d'une route.
## Même logique de déclenchement : seul le membre actif entre en contact
## déclenche le choix (la hitbox de détection reste un cercle invisible
## devant le bâtiment, pas besoin de marcher jusqu'au mur).

signal chosen(data: Dictionary)

const TRIGGER_RADIUS := 4.0   # ancien rayon 64 px / 16

const WALL_W := 2.6
const WALL_D := 1.9
const WALL_H := 1.9
const ROOF_OVERHANG := 0.35
const ROOF_HEIGHT   := 0.9

const C_WALL := Color(0.86, 0.80, 0.64)
const C_ROOF := Color(0.55, 0.22, 0.20)
const C_DOOR := Color(0.14, 0.10, 0.06)

var _data:      Dictionary = {}
var _triggered: bool       = false
var _active:    bool       = false   # une porte FERMÉE ne déclenche rien
var _pulse:     float      = 0.0

var _glow:     MeshInstance3D     = null
var _glow_mat: StandardMaterial3D = null
var _door:     MeshInstance3D     = null   # battant (sombre = fermé)
var _is_tunnel: bool = false


## `data.active` (défaut true) : porte ouverte (halo + trigger) ou fermée
## (visible mais inerte, jusqu'à `open()`). `data.style` : "house" (défaut)
## ou "tunnel" (montagne). `data.bonus_label` : SEULE étiquette affichée
## (plus de nom de zone ni de numéro de vague, cf. retour joueurs).
func setup(data: Dictionary) -> void:
	_data   = data
	_active = bool(data.get("active", true))
	var style: String = str(data.get("style", "house"))

	# Hitbox de détection joueur — devant le bâtiment, pas besoin de le
	# traverser pour déclencher le choix de sortie.
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = TRIGGER_RADIUS
	cs.shape  = sh
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)

	collision_layer = 8   # layer dédié (n'interfère pas avec murs/ennemis)
	collision_mask  = 1 if _active else 0   # fermée = ne détecte personne

	if style == "tunnel":
		_is_tunnel = true
		_build_tunnel()
	else:
		_build_gate_building()

	# Léger halo au sol devant la porte, pulsé — indique l'interactivité.
	# Masqué tant que la porte est fermée.
	_glow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius    = 0.85
	disc.bottom_radius = 0.85
	disc.height        = 0.03
	_glow.mesh = disc
	_glow.position = Vector3(0, 0.02, WALL_D * 0.5 + 0.9)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.4, 1.0, 0.6, 0.35)
	_glow_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = _active
	add_child(_glow)

	# UNIQUEMENT le libellé de récompense, au-dessus du bâtiment.
	var bonus: String = data.get("bonus_label", "")
	if not bonus.is_empty():
		var lbl_b := Label3D.new()
		lbl_b.text = bonus
		lbl_b.position = Vector3(0, WALL_H + ROOF_HEIGHT + 0.35, 0)
		lbl_b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl_b.no_depth_test = true
		lbl_b.font_size = 46
		lbl_b.pixel_size = 0.009
		lbl_b.modulate = Color(0.5, 1.0, 0.55) if _active else Color(0.70, 0.72, 0.62)
		lbl_b.outline_size = 13
		lbl_b.outline_modulate = Color(0.05, 0.12, 0.05)
		lbl_b.name = "BonusLabel"
		add_child(lbl_b)

	body_entered.connect(_on_body_entered)


## Ouvre une porte spawée fermée (fin de salle) : réveille le halo, active
## la hitbox et éclaircit le battant + le libellé.
func open() -> void:
	if _active:
		return
	_active = true
	collision_mask = 1
	if is_instance_valid(_glow):
		_glow.visible = true
	if is_instance_valid(_door):
		if _is_tunnel:
			_door.visible = false
		else:
			(_door.material_override as StandardMaterial3D).albedo_color = C_DOOR
	var lbl := get_node_or_null("BonusLabel")
	if lbl is Label3D:
		(lbl as Label3D).modulate = Color(0.5, 1.0, 0.55)


## Petit bâtiment de jonction : murs (BoxMesh) + toit en pente (deux
## BoxMesh fins inclinés, façon prisme) + porte plus sombre en façade.
## Purement visuel — la hitbox de déclenchement est déjà posée par setup().
func _build_gate_building() -> void:
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(WALL_W, WALL_H, WALL_D)
	wall.mesh = wall_box
	wall.position = Vector3(0, WALL_H * 0.5, 0)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = C_WALL
	wall_mat.roughness    = 0.9
	wall.material_override = wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(wall)

	# Porte — inset sombre sur la face sud (celle que le joueur voit en
	# arrivant depuis la map), légèrement en avant pour éviter le z-fight.
	# Couleur assombrie tant que la porte est FERMÉE (cf. open()).
	var door := MeshInstance3D.new()
	var door_quad := QuadMesh.new()
	door_quad.size = Vector2(0.7, 1.1)
	door.mesh = door_quad
	door.position = Vector3(0, 0.55, WALL_D * 0.5 + 0.01)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = C_DOOR if _active else C_DOOR.darkened(0.5)
	door_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	door.material_override = door_mat
	door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(door)
	_door = door

	_add_roof_pitch(WALL_W * 0.5 + ROOF_OVERHANG,  1.0)
	_add_roof_pitch(WALL_W * 0.5 + ROOF_OVERHANG, -1.0)


## Style "montagne" : bouche de grotte (même modèle que les caves) au lieu
## d'une maison — cf. MapRender3D._add_cave_entrance pour la référence.
func _build_tunnel() -> void:
	# Arche de grotte texturée (cave-kit) — même modèle que les entrées de
	# grotte, cf. MapRender3D._add_cave_entrance. Échelle à affiner à l'œil.
	var plate := KitProps.instance_textured(KitProps.CAVE_KIT_DIR, KitProps.CAVE_GATE_ROCK)
	plate.scale    = Vector3(0.6, 0.6, 0.6)
	plate.position = Vector3(0, 0, WALL_D * 0.3)
	add_child(plate)

	# "Battant" virtuel : un voile sombre qui bouche le trou tant que fermé,
	# retiré à l'ouverture (même rôle que la porte de la maison).
	var seal := MeshInstance3D.new()
	var seal_quad := QuadMesh.new()
	seal_quad.size = Vector2(1.1, 1.6)
	seal.mesh = seal_quad
	seal.position = Vector3(0, 0.9, WALL_D * 0.3 + 0.45)
	var seal_mat := StandardMaterial3D.new()
	seal_mat.albedo_color = Color(0.05, 0.04, 0.05, 0.95 if not _active else 0.0)
	seal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	seal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seal.material_override = seal_mat
	seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seal.visible = not _active
	add_child(seal)
	_door = seal


## Un pan de toit — box fine inclinée depuis le faîte central vers un bord
## du mur, `side` = +1/-1 pour le pan gauche/droit.
func _add_roof_pitch(half_span: float, side: float) -> void:
	var slope_len := sqrt(half_span * half_span + ROOF_HEIGHT * ROOF_HEIGHT)
	var angle := atan2(ROOF_HEIGHT, half_span)

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(slope_len, 0.12, WALL_D + ROOF_OVERHANG * 1.6)
	mi.mesh = box
	mi.position = Vector3(side * half_span * 0.5, WALL_H + ROOF_HEIGHT * 0.5, 0)
	mi.rotation.z = -side * angle
	var mat := StandardMaterial3D.new()
	mat.albedo_color = C_ROOF
	mat.roughness    = 0.8
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _process(delta: float) -> void:
	_pulse += delta * 3.0
	if is_instance_valid(_glow):
		var p := sin(_pulse) * 0.5 + 0.5   # 0..1
		_glow_mat.albedo_color = Color(0.4, 1.0, 0.6, 0.25 + p * 0.25)
		var s := 1.0 + p * 0.12
		_glow.scale = Vector3(s, 1.0, s)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	# Seul le membre actif déclenche la sortie
	var is_active_player: bool = body.is_in_group("players") and body.get("is_active") == true
	if not is_active_player:
		return
	_triggered = true
	Sfx.play("portal")
	chosen.emit(_data)
