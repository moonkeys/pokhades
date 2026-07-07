extends Node3D

## Premier jet 2.5D (HD-2D façon Octopath Traveler) : sol procédural,
## props en primitives 3D (aucun asset externe requis), personnage en
## sprite PMD existant billboardé. Scène de test autonome — F6 pour lancer.

const GROUND_SIZE := 40.0
const PLAYER_PID   := 25   # Pikachu — sprite déjà en cache localement
const MOVE_SPEED   := 4.0
const CAM_HEIGHT   := 3.5
const CAM_BACK     := 7.5
const CAM_FOV      := 32.0
const SPRITE_PIXEL_SIZE := 0.022
const FOOT_LIFT := 0.06   # léger ajustement — le scan de pixels laisse le perso un poil enfoncé
const PLAY_BOUND   := GROUND_SIZE * 0.5 - 1.5

var _player:        CharacterBody3D  = null
var _player_sprite:  AnimatedSprite3D = null
var _cam:            Camera3D        = null
var _cam_target:     Vector3          = Vector3.ZERO
var _current_anim := "idle"


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_backdrop()
	_build_props()
	_build_player()
	_build_camera()


# ── Environnement (ciel, lumière, ambiance) ─────────────────────────────

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color        = Color(0.42, 0.62, 0.88)
	sky_mat.sky_horizon_color    = Color(0.85, 0.78, 0.66)
	sky_mat.ground_bottom_color  = Color(0.30, 0.28, 0.24)
	sky_mat.ground_horizon_color = Color(0.85, 0.78, 0.66)
	sky.sky_material = sky_mat
	e.sky = sky

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.fog_enabled     = true
	e.fog_light_color = Color(0.86, 0.80, 0.68)
	e.fog_density     = 0.012
	e.glow_enabled    = true
	e.glow_intensity  = 0.5
	e.glow_bloom      = 0.15
	e.tonemap_mode    = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color   = Color(1.0, 0.93, 0.80)
	sun.light_energy  = 1.15
	sun.shadow_enabled = true
	add_child(sun)


# ── Sol (shader procédural — zéro texture externe) ──────────────────────

const _GRASS_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley;

void fragment() {
	float n = fract(sin(dot(floor(UV * 60.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 base = vec3(0.30, 0.52, 0.24);
	vec3 hi   = vec3(0.38, 0.60, 0.28);
	ALBEDO = mix(base, hi, n * 0.4);
	ROUGHNESS = 0.85;
}
"""

func _build_ground() -> void:
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	mesh_inst.mesh = plane

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _GRASS_SHADER
	mat.shader = shader
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE, 0.2, GROUND_SIZE)
	cs.shape = shape
	cs.position = Vector3(0, -0.1, 0)
	body.add_child(cs)
	add_child(body)


# ── Collines lointaines (silhouette bon marché pour l'horizon) ──────────

func _build_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 5:
		var hill := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(6.0, 11.0)
		mesh.height = mesh.radius * 1.1
		hill.mesh = mesh
		var ang := (TAU / 5.0) * i + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(26.0, 32.0)
		hill.position = Vector3(cos(ang) * dist, -mesh.radius * 0.55, sin(ang) * dist)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.52, 0.62, 0.66).lerp(Color(0.42, 0.56, 0.62), rng.randf())
		mat.roughness = 1.0
		hill.material_override = mat
		add_child(hill)


# ── Props (arbres, rochers — primitives 3D, pas d'asset requis) ─────────

func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 18:
		var pos := Vector3(rng.randf_range(-16.0, 16.0), 0.0, rng.randf_range(-16.0, 16.0))
		if pos.length() < 3.0:
			continue
		if rng.randf() < 0.7:
			_spawn_tree(pos, rng.randf_range(0.85, 1.25))
		else:
			_spawn_rock(pos, rng.randf_range(0.6, 1.1))


func _spawn_tree(pos: Vector3, scale_mult: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 1.4
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, 0.7 * scale_mult, 0)
	trunk.scale = Vector3.ONE * scale_mult
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.24, 0.14)
	trunk_mat.roughness = 0.9
	trunk.material_override = trunk_mat
	root.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.0
	canopy_mesh.height = 1.8
	canopy.mesh = canopy_mesh
	canopy.position = Vector3(0, 1.9 * scale_mult, 0)
	canopy.scale = Vector3.ONE * scale_mult
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.24, 0.46, 0.20)
	canopy_mat.roughness = 0.85
	canopy.material_override = canopy_mat
	root.add_child(canopy)

	_add_shadow_blob(root, 1.1 * scale_mult, Vector3.ZERO)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35 * scale_mult
	shape.height = 2.0 * scale_mult
	cs.shape = shape
	cs.position = Vector3(0, 1.0 * scale_mult, 0)
	body.add_child(cs)
	root.add_child(body)


func _spawn_rock(pos: Vector3, scale_mult: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.6, 0.8)
	mesh_inst.mesh = box
	mesh_inst.position = pos + Vector3(0, 0.3 * scale_mult, 0)
	mesh_inst.rotation_degrees = Vector3(0, randf_range(0, 360), 0)
	mesh_inst.scale = Vector3.ONE * scale_mult
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.50, 0.46)
	mat.roughness = 0.95
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	_add_shadow_blob(self, scale_mult * 0.7, pos)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.6, 0.8) * scale_mult
	cs.shape = shape
	cs.position = pos + Vector3(0, 0.3 * scale_mult, 0)
	body.add_child(cs)
	add_child(body)


func _add_shadow_blob(parent: Node3D, radius: float, local_pos: Vector3) -> void:
	var blob := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	blob.mesh = mesh
	blob.position = local_pos + Vector3(0, 0.01, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = mat
	parent.add_child(blob)


# ── Joueur (sprite PMD existant, billboardé) ─────────────────────────────

func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.position = Vector3(0, 0, 0)
	add_child(_player)

	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.1
	cs.shape = shape
	cs.position = Vector3(0, 0.55, 0)
	_player.add_child(cs)

	_player_sprite = AnimatedSprite3D.new()
	_player_sprite.billboard      = BaseMaterial3D.BILLBOARD_FIXED_Y
	_player_sprite.pixel_size     = SPRITE_PIXEL_SIZE
	_player_sprite.centered       = true
	_player_sprite.shaded         = true
	_player_sprite.double_sided   = true
	_player_sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# Ombre dynamique à la forme du sprite (projetée par la lumière) — pas de blob rond
	_player_sprite.cast_shadow    = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_player.add_child(_player_sprite)

	PMDSprites.get_walk_sprites(PLAYER_PID, self, func(result: Dictionary) -> void:
		if result.is_empty() or not is_instance_valid(_player_sprite): return
		_player_sprite.sprite_frames = result.frames
		_player_sprite.play("idle")
		# Sprite centré : on remonte son pivot pour que ses "pieds" (vrai pixel
		# opaque le plus bas, pas le bord de la frame qui a souvent une marge
		# vide) touchent le sol à y=0.
		var frame_size: Vector2i = result.get("frame_size", Vector2i(32, 40))
		var foot_row: int        = result.get("foot_row", frame_size.y - 1)
		_player_sprite.position.y = (float(foot_row) - float(frame_size.y) * 0.5) * SPRITE_PIXEL_SIZE \
			+ FOOT_LIFT
	)


# ── Caméra (angle fixe façon Octopath, suit le joueur) ───────────────────

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_cam_target = _player.position
	_update_camera(true)


func _update_camera(snap: bool) -> void:
	_cam_target = _cam_target.lerp(_player.position, 1.0 if snap else 0.12)
	var offset := Vector3(0, CAM_HEIGHT, CAM_BACK)
	_cam.position = _cam_target + offset
	_cam.look_at(_cam_target + Vector3(0, 0.9, 0), Vector3.UP)


# ── Déplacement + animation directionnelle (même logique que la 2D) ─────

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var dir := Vector3(
		Input.get_axis("ui_left", "ui_right"),
		0.0,
		Input.get_axis("ui_up", "ui_down")
	)
	if dir.length() > 1.0:
		dir = dir.normalized()

	_player.velocity = dir * MOVE_SPEED
	_player.move_and_slide()
	_player.position.y = 0.0
	_player.position.x = clampf(_player.position.x, -PLAY_BOUND, PLAY_BOUND)
	_player.position.z = clampf(_player.position.z, -PLAY_BOUND, PLAY_BOUND)

	_update_anim(Vector2(dir.x, dir.z))
	_update_camera(false)


func _update_anim(dir: Vector2) -> void:
	if not is_instance_valid(_player_sprite) or not _player_sprite.sprite_frames:
		return
	var anim: String
	if dir.length() < 0.1:
		anim = "idle"
	else:
		var sector := int(round(fposmod(dir.angle(), TAU) / (TAU / 8.0))) % 8
		match sector:
			0: anim = "walk_right"
			1: anim = "walk_downright"
			2: anim = "walk_down"
			3: anim = "walk_downleft"
			4: anim = "walk_left"
			5: anim = "walk_upleft"
			6: anim = "walk_up"
			_: anim = "walk_upright"

	if anim != _current_anim:
		_current_anim = anim
		if _player_sprite.sprite_frames.has_animation(anim):
			_player_sprite.play(anim)
