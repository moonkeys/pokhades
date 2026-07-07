class_name CombatVFX
extends RefCounted

## Effets de "game feel" du combat — chiffres de dégâts flottants, nuage de
## disparition à la mort, orbes d'or. Tout est autonome (spawn puis
## auto-destruction), appelé ponctuellement par TeamMember/EnemyAI ; aucun
## état à gérer côté appelant.

static var _soft_tex: GradientTexture2D = null


## ── Chiffres de dégâts ────────────────────────────────────────────────────
## `kind` colore le chiffre selon le contexte :
##   "super"  → attaque super efficace (orange, plus gros)
##   "weak"   → pas très efficace (gris, plus petit)
##   "player" → dégâts subis par l'équipe (rouge)
##   "normal" → tout le reste (blanc)
static func spawn_damage_number(parent: Node, pos: Vector3, amount: int, kind: String = "normal") -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0.08, 0.06, 0.04, 0.9)
	lbl.pixel_size = 0.010
	match kind:
		"immune":
			lbl.font_size = 40
			lbl.modulate = Color(0.60, 0.60, 0.65)
			lbl.text = "∅"
		"super":
			lbl.font_size = 64
			lbl.modulate = Color(1.0, 0.62, 0.12)
			lbl.text += " !"
		"weak":
			lbl.font_size = 40
			lbl.modulate = Color(0.72, 0.72, 0.72)
		"player":
			lbl.font_size = 52
			lbl.modulate = Color(1.0, 0.30, 0.25)
		_:
			lbl.font_size = 50
			lbl.modulate = Color(0.98, 0.95, 0.88)
	# Léger décalage aléatoire — deux coups rapprochés ne se superposent pas
	lbl.position = pos + Vector3(randf_range(-0.35, 0.35), 1.7, randf_range(-0.15, 0.15))
	parent.add_child(lbl)

	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y + 1.1, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.chain().tween_callback(lbl.queue_free)


## ── Impact au point de contact ────────────────────────────────────────────
## Éclat additif qui gonfle + gerbe d'étincelles projetées vers l'extérieur.
## Appelé au moment où un coup porte (cf. EnemyAI/TeamMember.take_damage) —
## `tint` colore l'éclat selon le type de l'attaque.
## PERF : meshes/matériaux PARTAGÉS et mis en cache par teinte — un impact
## par coup à cadence élevée ne doit rien allouer côté GPU ; le fondu passe
## par GeometryInstance3D.transparency (par instance), jamais par le matériau
## partagé.
static var _impact_mesh:  QuadMesh = null
static var _impact_pm:    ParticleProcessMaterial = null
static var _impact_mats:  Dictionary = {}   # tint(Color) -> StandardMaterial3D (éclat)
static var _spark_meshes: Dictionary = {}   # tint(Color) -> QuadMesh avec matériau étincelle

static func spawn_impact(parent: Node, pos: Vector3, tint: Color = Color(1.0, 0.95, 0.72)) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return

	# Éclat central : quad additif face-caméra qui grossit et s'efface vite
	var mi := MeshInstance3D.new()
	mi.mesh              = _get_impact_mesh()
	mi.material_override = _get_impact_mat(tint)
	mi.position          = pos
	mi.scale             = Vector3.ONE * 0.45
	parent.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.7, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, 0.18).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

	# Gerbe d'étincelles — burst rapide et serré, additif, teinté
	var p := GPUParticles3D.new()
	p.one_shot      = true
	p.emitting      = true
	p.amount        = 9
	p.lifetime      = 0.30
	p.explosiveness = 1.0
	p.position      = pos
	p.process_material = _get_impact_pm()
	p.draw_pass_1      = _get_spark_mesh(tint)
	parent.add_child(p)
	parent.get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


static func _get_impact_mesh() -> QuadMesh:
	if _impact_mesh == null:
		_impact_mesh = QuadMesh.new()
		_impact_mesh.size = Vector2(1, 1)
	return _impact_mesh


static func _get_impact_mat(tint: Color) -> StandardMaterial3D:
	if _impact_mats.has(tint):
		return _impact_mats[tint]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture  = _get_soft_texture()
	mat.albedo_color    = tint
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	_impact_mats[tint] = mat
	return mat


static func _get_impact_pm() -> ParticleProcessMaterial:
	if _impact_pm == null:
		_impact_pm = ParticleProcessMaterial.new()
		_impact_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_impact_pm.emission_sphere_radius = 0.06
		_impact_pm.direction     = Vector3(0, 0.25, 0)
		_impact_pm.spread        = 170.0
		_impact_pm.initial_velocity_min = 2.6
		_impact_pm.initial_velocity_max = 5.2
		_impact_pm.gravity       = Vector3(0, -5.0, 0)
		_impact_pm.damping_min   = 1.0
		_impact_pm.damping_max   = 2.5
		_impact_pm.scale_min     = 0.5
		_impact_pm.scale_max     = 1.1
	return _impact_pm


static func _get_spark_mesh(tint: Color) -> QuadMesh:
	if _spark_meshes.has(tint):
		return _spark_meshes[tint]
	var pquad := QuadMesh.new()
	pquad.size = Vector2(0.14, 0.14)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = _get_soft_texture()
	pmat.albedo_color   = tint
	pmat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.blend_mode     = BaseMaterial3D.BLEND_MODE_ADD
	pmat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pquad.material = pmat
	_spark_meshes[tint] = pquad
	return pquad


## Couleur d'impact d'un type d'attaque (repli : blanc chaud).
const TYPE_COLORS := {
	"fire": Color(1.0, 0.55, 0.20),   "water": Color(0.35, 0.65, 1.0),
	"grass": Color(0.50, 0.90, 0.40), "electric": Color(1.0, 0.90, 0.25),
	"ice": Color(0.65, 0.90, 1.0),    "fighting": Color(0.90, 0.40, 0.30),
	"poison": Color(0.72, 0.42, 0.85),"ground": Color(0.85, 0.68, 0.40),
	"flying": Color(0.72, 0.80, 0.95),"psychic": Color(1.0, 0.45, 0.72),
	"bug": Color(0.70, 0.82, 0.30),   "rock": Color(0.78, 0.68, 0.45),
	"ghost": Color(0.55, 0.45, 0.80), "dragon": Color(0.45, 0.55, 0.95),
	"dark": Color(0.55, 0.48, 0.55),  "steel": Color(0.75, 0.80, 0.88),
	"fairy": Color(1.0, 0.70, 0.88),  "normal": Color(1.0, 0.95, 0.78),
}

static func type_color(t: String) -> Color:
	return TYPE_COLORS.get(t, Color(1.0, 0.95, 0.78))


## Kind à partir du multiplicateur de type (cf. DamageCalculator.type_multiplier).
static func kind_from_multiplier(mult: float) -> String:
	if mult <= 0.01:
		return "immune"
	if mult > 1.01:
		return "super"
	if mult < 0.99:
		return "weak"
	return "normal"


## ── Nuage de disparition (mort d'un Pokémon) ─────────────────────────────
static func spawn_death_poof(parent: Node, pos: Vector3, tint: Color = Color(0.92, 0.92, 0.95)) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.one_shot   = true
	p.emitting   = true
	p.amount     = 14
	p.lifetime   = 0.55
	p.explosiveness = 1.0
	p.position   = pos + Vector3(0, 0.5, 0)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread    = 80.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -1.2, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.5
	pm.scale_min = 1.6
	pm.scale_max = 3.0
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_soft_texture()
	mat.albedo_color   = tint
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode  = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)

	parent.get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


## ── Orbes d'or (purement visuel — l'or reste crédité en fin de salle) ────
static func spawn_gold_orbs(parent: Node, pos: Vector3, count: int = 4) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	for i in count:
		var orb := GoldOrb.new()
		orb.position = pos + Vector3(randf_range(-0.4, 0.4), 0.5, randf_range(-0.4, 0.4))
		parent.add_child(orb)


static func _get_soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.9))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient  = grad
		_soft_tex.fill      = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to   = Vector2(1.0, 0.5)
		_soft_tex.width     = 64
		_soft_tex.height    = 64
	return _soft_tex
