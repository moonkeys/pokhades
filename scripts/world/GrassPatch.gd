class_name GrassPatch
extends RefCounted

## Herbe pixel-art 3D (inspirée de la démo « Dylearn 3D Pixel Art Grass ») :
## des TOUFFES de brins dessinées en pixel-art (texture procédurale à bandes,
## filter NEAREST) posées sur deux quads croisés en X, le tout dans UN SEUL
## MultiMesh (1 draw call) avec un shader d'ondulation au vent — le haut des
## brins ondule, le pied reste ancré. Teinte par biome via uniform.
##
## Usage : add_child(GrassPatch.build(transforms, tint))

const TUFT_W := 0.62
const TUFT_H := 0.52

static var _tex:    ImageTexture = null
static var _mesh:   ArrayMesh    = null
static var _shader: Shader       = null

const _SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, specular_disabled;

uniform sampler2D blades : source_color, filter_nearest;
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.05;

void vertex() {
	// Le sommet du brin (UV.y = 0) ondule, le pied (UV.y = 1) reste planté.
	float w = 1.0 - UV.y;
	float phase = MODEL_MATRIX[3].x * 0.9 + MODEL_MATRIX[3].z * 1.3;
	VERTEX.x += sin(TIME * 1.7 + phase) * sway * w;
	VERTEX.z += cos(TIME * 1.1 + phase * 0.7) * sway * 0.5 * w;
}

void fragment() {
	vec4 c = texture(blades, UV);
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb * tint;
	ROUGHNESS = 1.0;
}
"""


## Construit le MultiMeshInstance3D — `transforms` : un Transform3D par touffe
## (position + rotation Y + échelle déjà appliquées), `tint` : teinte du biome.
static func build(transforms: Array, tint: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _get_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader()
	mat.set_shader_parameter("blades", _get_texture())
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER
	return _shader


## ── Matériau de SOL saturé (retour utilisateur : le sol baké était trop
## clair/délavé alors que les sprites 2D allaient bien — on sature et
## assombrit UNIQUEMENT le terrain, pas le reste de la scène). Partagé par
## MapRender3D (maps de run) et HubMap. ──────────────────────────────────
static var _ground_shader: Shader = null

const _GROUND_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_nearest;
uniform float sat = 1.45;
uniform float val = 0.88;

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = clamp(mix(vec3(g), c, sat) * val, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
"""

static func ground_material(tex: Texture2D, sat: float = 1.45, val: float = 0.88) -> ShaderMaterial:
	if _ground_shader == null:
		_ground_shader = Shader.new()
		_ground_shader.code = _GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _ground_shader
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("sat", sat)
	mat.set_shader_parameter("val", val)
	return mat


## Deux quads croisés en X (4 triangles double-face via cull_disabled),
## pied à y=0, UV.y = 0 en HAUT (poids d'ondulation du shader).
static func _get_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := TUFT_W * 0.5
	for ang in [0.0, PI * 0.5]:
		var dx := cos(ang) * hw
		var dz := sin(ang) * hw
		var a := Vector3(-dx, 0.0, -dz)        # pied gauche
		var b := Vector3(dx, 0.0, dz)          # pied droit
		var c := Vector3(dx, TUFT_H, dz)       # haut droit
		var d := Vector3(-dx, TUFT_H, -dz)     # haut gauche
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(1, 0)); st.add_vertex(c)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(c)
		st.set_uv(Vector2(0, 0)); st.add_vertex(d)
	st.generate_normals()
	_mesh = st.commit()
	return _mesh


## ── HAUTE HERBE : touffes buissonneuses pixel-art (référence utilisateur :
## touffes denses de brins arqués vert vif, variante à cœur sombre creux).
## Billboards en MultiMesh — 1 draw call par variante, ancrés au sol. ──────

static var _tuft_tex: Array = [null, null]   # [pleine, creuse]

## MultiMeshInstance3D de touffes de haute herbe. `hollow` = variante à
## centre creux (cœur d'ombre), `tint` = teinte du biome.
static func build_tufts(transforms: Array, tint: Color, hollow: bool) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.45, 1.15)
	quad.center_offset = Vector3(0, 0.55, 0)   # pied au sol
	var mat := StandardMaterial3D.new()
	mat.albedo_texture   = _get_tuft_texture(hollow)
	mat.albedo_color     = tint
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode   = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.texture_filter   = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness        = 1.0
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Texture 28×22 : ~13 brins arqués depuis la base centrale, courbés vers
## l'extérieur, 3 verts + liseré sombre en périphérie — le style de la
## référence. `hollow` : cœur d'ombre au centre (touffe « habitée »).
static func _get_tuft_texture(hollow: bool) -> ImageTexture:
	var idx := 1 if hollow else 0
	if _tuft_tex[idx] != null:
		return _tuft_tex[idx]
	var w := 28; var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark  := Color(0.08, 0.19, 0.07)
	var mid   := Color(0.20, 0.44, 0.13)
	var light := Color(0.36, 0.66, 0.21)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if hollow else 42

	# Dôme de masse sombre : la touffe est PLEINE à la base (référence :
	# touffes denses et bombées), les brins se détachent par-dessus.
	for y in range(h - 11, h):
		var dy := (float(y) - float(h - 1)) / 10.0
		var half := (w * 0.42) * sqrt(maxf(0.0, 1.0 - dy * dy))
		for x in range(int(w * 0.5 - half), int(w * 0.5 + half) + 1):
			if x >= 0 and x < w:
				img.set_pixel(x, y, dark)

	# Cœur d'ombre (variante creuse) — plus noir au centre
	if hollow:
		for y in range(h - 8, h):
			for x in range(8, w - 8):
				var dx := (float(x) - w * 0.5) / (w * 0.24)
				var dy2 := (float(y) - (h - 3.0)) / 5.0
				if dx * dx + dy2 * dy2 < 1.0:
					img.set_pixel(x, y, Color(0.03, 0.08, 0.03))

	# Brins arqués DENSES : deux rangées entremêlées, courbés vers l'extérieur
	var blades := 22
	for b in blades:
		var t0 := (float(b) + 0.5) / float(blades)          # 0 → 1 sur la largeur
		var spread := (t0 - 0.5) * 2.0
		var x0 := w * 0.5 + spread * 7.5 + rng.randf_range(-1.0, 1.0)
		var blade_h := rng.randi_range(11, 18)
		if hollow and absf(spread) < 0.35:
			blade_h = rng.randi_range(6, 9)                # centre plus court (creux)
		var curve := spread * rng.randf_range(4.0, 8.0)     # arc vers l'extérieur
		var shade := rng.randf() < 0.35                     # brins arrière plus sombres
		for s in blade_h:
			var t := float(s) / float(blade_h - 1)
			var px := int(x0 + curve * t * t)
			var py := (h - 1) - s
			if px < 0 or px >= w or py < 0 or py >= h:
				continue
			var col := mid if t < 0.55 else light
			if shade:
				col = dark if t < 0.55 else mid
			img.set_pixel(px, py, col)
			# base plus épaisse (2 px)
			if t < 0.5 and px + 1 < w:
				img.set_pixel(px + 1, py, mid if not shade else dark)
	_tuft_tex[idx] = ImageTexture.create_from_image(img)
	return _tuft_tex[idx]


## Texture pixel-art procédurale 16×16 : 5 brins verticaux de hauteurs
## variées, 3 bandes de vert (sombre au pied → clair en pointe) — le rendu
## « pixel art » vient du NEAREST + alpha net.
static func _get_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bands := [Color(0.16, 0.30, 0.12), Color(0.24, 0.44, 0.16), Color(0.38, 0.62, 0.24)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 421
	for blade in 5:
		var x := 1 + blade * 3 + rng.randi_range(0, 1)
		var h := rng.randi_range(9, 14)          # hauteur du brin (px)
		var lean := rng.randi_range(-1, 1)       # penché d'1 px vers le haut
		for y in h:
			var row := size - 1 - y              # depuis le bas
			var t := float(y) / float(maxi(h - 1, 1))
			var col: Color = bands[mini(int(t * 3.0), 2)]
			var px := x + (lean if t > 0.6 else 0)
			if px >= 0 and px < size:
				img.set_pixel(px, row, col)
				# brin plus épais à la base
				if t < 0.4 and px + 1 < size:
					img.set_pixel(px + 1, row, col)
	_tex = ImageTexture.create_from_image(img)
	return _tex
