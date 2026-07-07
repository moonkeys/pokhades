class_name WaterSurface
extends RefCounted

## Surface d'eau animée partagée (maps de combat + étang du Hub).
##
## Construit un maillage subdivisé à partir d'un ensemble de cases d'eau,
## avec la DISTANCE AU RIVAGE cuite dans la couleur des sommets (1 = large,
## 0 = bord) — le shader s'en sert pour :
##   - une écume claire animée qui "clapote" le long des bords (les rives
##     deviennent lisibles d'un coup d'œil) ;
##   - un dégradé peu profond → profond vers le centre ;
##   - amarrer les vagues au rivage (le bord ne flotte pas dans le vide).
## La subdivision (3×3 par case) rend la houle réellement visible — un quad
## par case n'avait que ses 4 coins à déplacer.

const SUBDIV := 3

static var _shader: Shader = null

const _SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

uniform vec4 shallow_color : source_color = vec4(0.32, 0.62, 0.66, 0.70);
uniform vec4 deep_color    : source_color = vec4(0.13, 0.32, 0.42, 0.86);
uniform vec4 foam_color    : source_color = vec4(0.93, 0.97, 0.95, 1.0);
uniform float wave_amp  = 0.07;
uniform float wave_freq = 1.6;

varying float v_shore;   // 0 = rive, 1 = large (COLOR.r du maillage)
varying float v_wave;    // hauteur de houle locale (-1..1)
varying vec2  v_pos;

void vertex() {
	v_shore = COLOR.r;
	v_pos   = VERTEX.xz;
	float w = sin(VERTEX.x * wave_freq + TIME * 1.3) * 0.5
	        + sin(VERTEX.z * wave_freq * 0.8 - TIME * 0.9) * 0.35
	        + sin((VERTEX.x + VERTEX.z) * wave_freq * 0.5 + TIME * 0.6) * 0.15;
	v_wave = w;
	// Amarré au rivage : le bord ondule peu, le large respire franchement
	VERTEX.y += w * wave_amp * (0.35 + 0.65 * v_shore);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Look PIXEL-ART (façon « 2d pixel water shader ») : tout est échantillonné
	// sur une grille fixe de 8 texels/unité puis POSTERISÉ en bandes de
	// couleur — des aplats nets qui clapotent, plus de dégradés lisses.
	vec2 gp = floor(v_pos * 8.0) / 8.0;

	float depth_t = clamp(v_shore * 1.2, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_t);

	// Houle : bandes de surbrillance NETTES (step) qui traversent la surface
	float band = sin(gp.x * 1.8 - TIME * 1.4) * sin(gp.y * 1.5 + TIME * 1.0);
	col += step(0.62, band) * 0.10;
	col += step(0.65, v_wave) * 0.10;

	// Étincelles pixel : de rares cellules de la grille scintillent
	float n  = hash2(gp);
	float tw = step(0.992, fract(n + TIME * (0.05 + n * 0.10)));
	col = mix(col, foam_color.rgb, tw);

	// Écume de rive : bande claire dont la largeur respire (clapotis), au
	// bord intérieur DENTELÉ par la grille — une rive pixel, pas une ligne lisse
	float lap    = sin(TIME * 1.8 + gp.x * 1.7 + gp.y * 1.3) * 0.5 + 0.5;
	float foam_w = 0.22 + lap * 0.14 + (hash2(gp * 3.0) - 0.5) * 0.10;
	float foam   = 1.0 - step(foam_w, v_shore);
	col = mix(col, foam_color.rgb, foam * 0.85);

	// Posterisation : 6 niveaux par canal — la signature pixel-art
	col = floor(col * 6.0 + 0.5) / 6.0;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col + fresnel * 0.08;
	ALPHA  = max(mix(shallow_color.a, deep_color.a, depth_t), foam * 0.9);
	ROUGHNESS = 0.2;
	SPECULAR  = 0.5;
}
"""


static func get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER
	return _shader


## Construit la surface pour `cells` (Array de Vector2i, une case = 1×1 u).
## Le nœud retourné est à y=0 — l'appelant le positionne (ex : y = 0.06).
static func build(cells: Array, shallow: Color, deep: Color,
		foam: Color = Color(0.93, 0.97, 0.95)) -> MeshInstance3D:
	var cell_set: Dictionary = {}
	for c: Vector2i in cells:
		cell_set[c] = true

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.0 / float(SUBDIV)

	for cell: Vector2i in cells:
		# Distance au rivage aux 4 coins de la case (0 = coin de bord)
		var s00 := _corner_shore(cell_set, cell.x, cell.y)
		var s10 := _corner_shore(cell_set, cell.x + 1, cell.y)
		var s01 := _corner_shore(cell_set, cell.x, cell.y + 1)
		var s11 := _corner_shore(cell_set, cell.x + 1, cell.y + 1)

		for iy in SUBDIV:
			for ix in SUBDIV:
				var u0 := ix * step
				var u1 := (ix + 1) * step
				var t0 := iy * step
				var t1 := (iy + 1) * step
				_add_vert(st, cell, u0, t0, _bilerp(s00, s10, s01, s11, u0, t0))
				_add_vert(st, cell, u1, t0, _bilerp(s00, s10, s01, s11, u1, t0))
				_add_vert(st, cell, u1, t1, _bilerp(s00, s10, s01, s11, u1, t1))
				_add_vert(st, cell, u0, t0, _bilerp(s00, s10, s01, s11, u0, t0))
				_add_vert(st, cell, u1, t1, _bilerp(s00, s10, s01, s11, u1, t1))
				_add_vert(st, cell, u0, t1, _bilerp(s00, s10, s01, s11, u0, t1))
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.name = "WaterSurface"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = get_shader()
	mat.set_shader_parameter("shallow_color", shallow)
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("foam_color", foam)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _add_vert(st: SurfaceTool, cell: Vector2i, u: float, t: float, shore: float) -> void:
	st.set_color(Color(shore, 0, 0))
	st.add_vertex(Vector3(cell.x + u, 0.0, cell.y + t))


## 1.0 si les 4 cases entourant le coin (cx, cz) sont de l'eau, sinon 0.0.
static func _corner_shore(cell_set: Dictionary, cx: int, cz: int) -> float:
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		if not cell_set.has(Vector2i(cx + d.x, cz + d.y)):
			return 0.0
	return 1.0


static func _bilerp(s00: float, s10: float, s01: float, s11: float, u: float, t: float) -> float:
	return lerpf(lerpf(s00, s10, u), lerpf(s01, s11, u), t)
