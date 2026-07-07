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
