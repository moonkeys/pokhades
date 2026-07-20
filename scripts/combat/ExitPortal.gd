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

var _glow:     GPUParticles3D     = null   # motes lumineuses dans le passage
static var _mote_tex: GradientTexture2D = null
var _door:     MeshInstance3D     = null   # battant (sombre = fermé)
var _is_tunnel: bool = false
var _is_toll:   bool = false
var _toll_arm:  Node3D = null   # bras de barrière (baissé = fermé, levé = ouvert)

const C_TOLL_POST := Color(0.86, 0.84, 0.80)
const C_TOLL_ARM  := Color(0.82, 0.20, 0.16)
const C_TOLL_STRIPE := Color(0.95, 0.94, 0.90)
const TOLL_ARM_LEN := 2.6


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
	elif style == "toll":
		_is_toll = true
		_build_toll_gate()
	elif style == "arch":
		_build_hedge_arch()
	elif style == "pier":
		_build_pier_gate()
	else:
		_build_gate_building()

	# Léger halo au sol devant la porte, pulsé — indique l'interactivité.
	# Masqué tant que la porte est fermée.
	_glow = _make_motes()
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
		lbl_b.modulate = Color(0.5, 1.0, 0.55)
		lbl_b.outline_size = 13
		lbl_b.outline_modulate = Color(0.05, 0.12, 0.05)
		lbl_b.name = "BonusLabel"
		# La récompense ne se dévoile qu'une fois la zone NETTOYÉE (cf. open) :
		# l'annoncer pendant les vagues gâchait le choix de sortie, qui n'est
		# de toute façon pas encore possible (retour joueurs).
		lbl_b.visible = _active
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
	if _is_toll and is_instance_valid(_toll_arm):
		# La barrière se LÈVE : rotation du bras de l'horizontale vers ~78°.
		var tw := create_tween()
		tw.tween_property(_toll_arm, "rotation:z", deg_to_rad(78.0), 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif is_instance_valid(_door):
		# NB : l'arche (style "arch") ne pose PAS de `_door` — elle n'a aucun
		# obstacle à écarter, son ouverture se lit aux motes et au libellé.
		if _is_tunnel:
			_door.visible = false
		else:
			(_door.material_override as StandardMaterial3D).albedo_color = C_DOOR
	var lbl := get_node_or_null("BonusLabel")
	if lbl is Label3D:
		(lbl as Label3D).visible  = true
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


## Style "prairie" : ARCHE DE FEUILLAGE — deux grands arbres qui se rejoignent
## au-dessus du passage, encadrés de haies qui se resserrent en entonnoir vers
## un sentier qui s'enfonce. Une porte de maison plantée au milieu d'un champ
## (le style "house" par défaut) n'avait aucun sens en prairie (retour joueurs).
##
## Tant que la zone n'est pas nettoyée, le passage est bouché par un rideau de
## feuillage dense, retiré par open() — même rôle que le battant de la maison
## ou le voile de la grotte, mais lu comme "les buissons barrent le chemin".
const C_HEDGE      := Color(0.20, 0.44, 0.18)
const C_HEDGE_DARK := Color(0.13, 0.31, 0.13)
const ARCH_HALF_W  := 1.5   # demi-largeur du passage libre
## Buissons réellement importés (cf. KitProps.KIT_DIR — le dossier wiré ne
## contient qu'un sous-ensemble du pack Kenney, pas plant_bushLarge & co.).
const HEDGE_MESHES: Array[String] = [
	"plant_bush.glb", "plant_bushDetailed.glb", "plant_bushTriangle.glb",
]

func _build_hedge_arch() -> void:
	# Graine tirée de la POSITION (posée par le caller avant setup) : en
	# multijoueur, chaque pair doit voir exactement la même arche — le projet
	# proscrit le RNG global pour tout ce qui est généré par zone. Deux portes
	# d'une même salle sont à des cases différentes, donc restent distinctes.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)

	# Déclinaison par biome (data.arch_kind, posé par CombatArena) : la même
	# arche verte plantée en plein bois d'automne ou dans la vase jurait —
	# chaque région teinte SES feuillages, et le marécage troque les buissons
	# contre des roseaux.
	var kind: String = str(_data.get("arch_kind", "green"))
	var leaf: Dictionary
	match kind:
		"fall":
			leaf = {"leafsGreen": Color(0.80, 0.45, 0.12), "leafsDark": Color(0.62, 0.30, 0.10)}
		"swamp":
			leaf = {"leafsGreen": Color(0.34, 0.36, 0.22), "leafsDark": Color(0.24, 0.26, 0.16),
				"woodBark": Color(0.34, 0.29, 0.25)}
		_:
			leaf = {"leafsGreen": C_HEDGE, "leafsDark": C_HEDGE_DARK}

	# Les deux montants : de vrais arbres du kit, penchés VERS le passage pour
	# que leurs frondaisons se rejoignent en voûte au-dessus du joueur.
	for sx: float in [-1.0, 1.0]:
		var trunk := KitProps.instance("tree_default.glb", leaf)
		trunk.scale    = Vector3.ONE * 2.6
		trunk.position = Vector3(sx * (ARCH_HALF_W + 0.35), 0, 0)
		trunk.rotation = Vector3(0, rng.randf() * TAU, sx * -0.22)   # incliné vers l'axe
		add_child(trunk)

	# Haies latérales en entonnoir : VRAIS buissons du kit (la première version
	# empilait des BoxMesh — ça se lisait comme des cubes verts posés là).
	# Elles se resserrent vers l'axe à mesure qu'on avance, ce qui cadre le
	# regard sur le sentier au lieu de laisser l'œil filer sur les côtés.
	for sx: float in [-1.0, 1.0]:
		for i in 5:
			var bush: Node3D
			if kind == "swamp":
				# Roseaux, pas des haies : la flore des berges du biome (mêmes
				# bambous que MapRender3D._build_swamp_flora).
				bush = KitProps.instance_textured(
					"res://assets/kenney_nature-kit/Models/GLTF format/",
					"crops_bambooStageA.glb" if (i + int(sx)) % 2 == 0 else "crops_bambooStageB.glb")
				bush.scale = Vector3.ONE * rng.randf_range(0.9, 1.3)
			else:
				bush = KitProps.instance(HEDGE_MESHES[rng.randi() % HEDGE_MESHES.size()], leaf)
				bush.scale = Vector3.ONE * rng.randf_range(1.5, 2.3)
			bush.position   = Vector3(
				sx * (ARCH_HALF_W + 0.5 - i * 0.10) + rng.randf_range(-0.15, 0.15),
				0.0, -(0.7 + i * 1.05))
			bush.rotation.y = rng.randf() * TAU
			add_child(bush)

	# PAS de massif barrant le passage. Il y en a eu un (rôle du battant de la
	# maison / du voile de la grotte), mais il bouchait la vue sur le sentier
	# qui file au loin — or c'est LUI qui dit « la suite est par là », toute la
	# raison d'être de l'arche (retour joueurs). L'état fermé se lit désormais
	# à l'absence de motes et de libellé de récompense (cf. setup/open), pas à
	# un obstacle physique.


## Style "lac" : PORTIQUE DE PONTON — deux pilotis et une traverse de bois
## (mêmes teintes que le pont du lac, cf. MapRender3D._build_bridge), flanqués
## de barrières basses en entonnoir. Une porte de maison sur une rive n'avait
## pas plus de sens qu'en prairie.
func _build_pier_gate() -> void:
	var wood_dark := StandardMaterial3D.new()
	wood_dark.albedo_color = Color(0.40, 0.27, 0.15)
	wood_dark.roughness = 0.9
	var wood_deck := StandardMaterial3D.new()
	wood_deck.albedo_color = Color(0.52, 0.36, 0.20)
	wood_deck.roughness = 0.9

	for sx: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.22, 2.3, 0.22)
		post.mesh = pb
		post.position = Vector3(sx * ARCH_HALF_W, 1.15, 0)
		post.rotation.z = sx * -0.03
		post.material_override = wood_dark
		add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(ARCH_HALF_W * 2.0 + 0.7, 0.20, 0.26)
	beam.mesh = bb
	beam.position = Vector3(0, 2.25, 0)
	beam.material_override = wood_deck
	add_child(beam)

	# Barrières basses en entonnoir (kit nature).
	for sx: float in [-1.0, 1.0]:
		for i in 4:
			var fence := KitProps.instance("fence_simpleLow.glb")
			fence.scale      = Vector3.ONE * 1.6
			fence.position   = Vector3(sx * (ARCH_HALF_W + 0.42 - i * 0.10), 0.0, -(0.6 + i * 1.0))
			fence.rotation.y = PI * 0.5 + sx * 0.12
			add_child(fence)


## Style "village" : PÉAGE — deux poteaux + un bras de barrière rayé rouge/
## blanc, BAISSÉ (horizontal, en travers du passage) tant que la zone n'est
## pas nettoyée, puis LEVÉ par open() (cf. animation du tween). Purement
## visuel : la hitbox de déclenchement est posée par setup().
func _build_toll_gate() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = C_TOLL_POST
	post_mat.roughness    = 0.85
	# Deux poteaux de part et d'autre du passage.
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.34, 1.7, 0.34)
		post.mesh = pb
		post.position = Vector3(sx * 1.25, 0.85, 0)
		post.material_override = post_mat
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(post)

	# Bras pivotant, ancré au poteau gauche. Le pivot est un Node3D ; le bras
	# (box) est décalé de +X d'une demi-longueur pour partir du pivot.
	_toll_arm = Node3D.new()
	_toll_arm.position = Vector3(-1.25, 1.45, 0)
	# Fermé = horizontal (rotation.z = 0) ; ouvert = levé (open() → ~78°).
	_toll_arm.rotation.z = deg_to_rad(78.0) if _active else 0.0
	add_child(_toll_arm)

	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(TOLL_ARM_LEN, 0.18, 0.18)
	arm.mesh = ab
	arm.position = Vector3(TOLL_ARM_LEN * 0.5, 0, 0)
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = C_TOLL_ARM
	arm_mat.roughness    = 0.8
	arm.material_override = arm_mat
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_toll_arm.add_child(arm)

	# Rayures blanches réparties le long du bras.
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = C_TOLL_STRIPE
	for i in 3:
		var st := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.34, 0.20, 0.20)
		st.mesh = sb
		st.position = Vector3(0.55 + i * 0.75, 0, 0)
		st.material_override = stripe_mat
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_toll_arm.add_child(st)


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


## Signal d'interactivité de la porte : une colonne de MOTES lumineuses qui
## montent lentement dans le passage. Remplace le disque vert translucide posé
## au sol, qui se lisait comme un aplat de gameplay collé sur le décor (retour
## joueurs). Les motes se fondent dans l'ambiance (pollen/lucioles), attirent
## l'œil par le MOUVEMENT plutôt que par la couleur, et marquent le passage
## lui-même au lieu d'une zone au sol.
##
## Pas de _process ici : les particules s'animent seules sur le GPU.
func _make_motes() -> GPUParticles3D:
	if _mote_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
		grad.set_color(1, Color(1.0, 0.95, 0.6, 0.0))   # bord fondu = point de lumière
		_mote_tex = GradientTexture2D.new()
		_mote_tex.gradient = grad
		_mote_tex.fill = GradientTexture2D.FILL_RADIAL
		_mote_tex.fill_from = Vector2(0.5, 0.5)
		_mote_tex.fill_to   = Vector2(1.0, 0.5)
		_mote_tex.width  = 32
		_mote_tex.height = 32

	var p := GPUParticles3D.new()
	p.amount   = 22
	p.lifetime = 3.2
	p.preprocess = 2.0        # déjà "en régime" à l'apparition, pas de bouffée initiale
	p.position = Vector3(0, 0.1, WALL_D * 0.5 + 0.5)

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(1.1, 0.05, 0.5)
	m.direction = Vector3(0, 1, 0)
	m.spread    = 12.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.1
	m.gravity   = Vector3(0, 0.12, 0)    # légère poussée vers le haut, pas de chute
	m.scale_min = 0.06
	m.scale_max = 0.14
	var alpha := Curve.new()             # apparition/disparition en fondu
	alpha.add_point(Vector2(0.0, 0.0))
	alpha.add_point(Vector2(0.25, 1.0))
	alpha.add_point(Vector2(1.0, 0.0))
	var ac := CurveTexture.new()
	ac.curve = alpha
	m.alpha_curve = ac
	p.process_material = m

	var draw := QuadMesh.new()
	draw.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _mote_tex
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true   # requis pour que alpha_curve s'applique
	draw.material = mat
	p.draw_pass_1 = draw
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


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
