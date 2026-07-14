class_name KitProps
extends RefCounted

## Utilitaires partagés pour instancier/styliser les meshes du pack Kenney
## Nature Kit (CC0) — réutilisés par MapRender3D (maps de combat) ET HubMap
## (Hub), pour que les deux zones parlent le même langage visuel sans
## dupliquer la logique de stylisation. cf. assets/kenney_nature_kit/License.txt
## (CC0, domaine public, aucune attribution requise).

const KIT_DIR := "res://assets/kenney_nature_kit/"

## Cave-kit (Kenney Modular Cave Kit, CC0) — modules de grotte texturés via
## un atlas `colormap.png` (une seule matière). Chargés PAR CHEMIN COMPLET et
## SANS l'aplatissement toon de prepare_mesh (qui les rendrait unis) — cf.
## instance_textured(). Remplace les vieilles arches `cliff_cave_rock`.
const CAVE_KIT_DIR := "res://assets/kenney_modular-cave-kit_1.0/Models/GLB format/"
const CAVE_GATE_ROCK := "gate-rock.glb"   # arche de grotte rocheuse (4×4 u)
const CAVE_FLOOR := "template-floor.glb"  # dalle plate 4×4 u, centrée, y=0
const CAVE_WALL  := "template-wall.glb"   # panneau 4 large × 4 haut, face +Z


## Instancie un GLB EXTERNE (hors nature-kit plat) en gardant ses matériaux
## d'origine — pour les modèles à texture atlas (cave-kit) que le pipeline
## toon dénaturerait. `dir` = dossier res:// complet, `file` = nom du .glb.
static func instance_textured(dir: String, file: String) -> Node3D:
	var scene: PackedScene = load(dir + file)
	if scene == null:
		push_error("KitProps.instance_textured: introuvable %s%s" % [dir, file])
		return Node3D.new()
	return scene.instantiate()

const TREES_ROUND: Array[String] = [
	"tree_default.glb", "tree_default_dark.glb", "tree_fat.glb", "tree_oak.glb", "tree_oak_dark.glb",
]
const TREES_PINE: Array[String] = [
	"tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb", "tree_pineTallD.glb",
]
## Variantes automnales (mêmes géométries, feuillages orange/jaune baked)
const TREES_FALL: Array[String] = [
	"tree_default_fall.glb", "tree_oak_fall.glb", "tree_fat_fall.glb", "tree_detailed_fall.glb",
]
## Hauteur native (unités monde, mesurée sur le modèle) — sert à normaliser
## chaque variante sur une hauteur cible cohérente malgré leurs tailles
## d'origine différentes.
const TREE_NATIVE_HEIGHT := {
	"tree_default.glb": 1.708, "tree_default_dark.glb": 1.708,
	"tree_fat.glb": 1.150, "tree_oak.glb": 1.226, "tree_oak_dark.glb": 1.226,
	"tree_pineTallA.glb": 1.530, "tree_pineTallB.glb": 1.935,
	"tree_pineTallC.glb": 1.670, "tree_pineTallD.glb": 2.075,
	"tree_default_fall.glb": 1.708, "tree_oak_fall.glb": 1.226,
	"tree_fat_fall.glb": 1.150, "tree_detailed_fall.glb": 1.332,
}

const ROCKS_LARGE: Array[String] = [
	"rock_largeA.glb", "rock_largeB.glb", "rock_largeC.glb", "rock_largeD.glb", "rock_largeE.glb", "rock_largeF.glb",
]
const ROCKS_SMALL: Array[String] = [
	"rock_smallA.glb", "rock_smallB.glb", "rock_smallC.glb", "rock_smallD.glb",
	"rock_smallE.glb", "rock_smallF.glb", "rock_smallG.glb", "rock_smallH.glb", "rock_smallI.glb",
]

const BUSHES: Array[String] = [
	"plant_bush.glb", "plant_bushDetailed.glb", "plant_bushSmall.glb", "plant_bushTriangle.glb",
]
## Hauteur native des buissons — même principe que TREE_NATIVE_HEIGHT.
const BUSH_NATIVE_HEIGHT := {
	"plant_bush.glb": 0.244, "plant_bushDetailed.glb": 0.360,
	"plant_bushSmall.glb": 0.207, "plant_bushTriangle.glb": 0.296,
}

const FLOWERS_RED:    Array[String] = ["flower_redA.glb", "flower_redB.glb", "flower_redC.glb"]
const FLOWERS_PURPLE: Array[String] = ["flower_purpleA.glb", "flower_purpleB.glb", "flower_purpleC.glb"]
const FLOWERS_YELLOW: Array[String] = ["flower_yellowA.glb", "flower_yellowB.glb", "flower_yellowC.glb"]
const GRASS_TALL:  Array[String] = ["grass_large.glb", "grass_leafsLarge.glb"]
const GRASS_SMALL: Array[String] = ["grass.glb", "grass_leafs.glb", "plant_flatShort.glb"]

# ── Décors de vie (Hub) — tailles natives ~0.1-1.0, cf. mesures en tête ──
const CAMPFIRES: Array[String] = ["campfire_logs.glb", "campfire_stones.glb"]
const FENCE_LOW := "fence_simpleLow.glb"   # segment 1.04 u de long, aligné X
const STUMPS:    Array[String] = ["stump_round.glb", "stump_oldTall.glb"]
const MUSHROOMS: Array[String] = [
	"mushroom_red.glb", "mushroom_redGroup.glb", "mushroom_tan.glb", "mushroom_tanGroup.glb",
]
const LOGS:      Array[String] = ["log.glb", "log_stack.glb"]
const STATUE_HEAD := "statue_head.glb"
const STATUE_RING := "statue_ring.glb"
const REEDS:     Array[String] = ["grass_leafsLarge.glb", "grass_large.glb"]   # roseaux de berge

static var _mesh_cache: Dictionary = {}
static var _wind_shader: Shader = null

const _WIND_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float sway = 0.05;
uniform float height_ref = 0.22;

void vertex() {
	// VERTEX.y est en espace local (avant l'échelle du nœud/de l'instance
	// MultiMesh) — la base du modèle (y≈0) reste fixe, le sommet oscille.
	float t = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.x;
	VERTEX.x += sin(TIME * 1.4 + phase) * sway * t;
	VERTEX.z += cos(TIME * 1.1 + phase) * sway * 0.6 * t;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
}
"""

static func get_wind_shader() -> Shader:
	if _wind_shader == null:
		_wind_shader = Shader.new()
		_wind_shader.code = _WIND_SHADER
	return _wind_shader


static func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := find_mesh_instance(c)
		if found != null:
			return found
	return null


## Charge le mesh d'un fichier du pack, le duplique et prépare ses
## matériaux — couleurs plates mattes + toon shading (cohérent avec le
## reste du rendu HD-2D), éventuellement teintées par nom de matériau glTF
## (clés de `tints` = noms "grass"/"dirt"/"colorRed"… tels qu'exportés par
## Kenney), éventuellement avec le shader de vent (herbe/fleurs). Mis en
## cache par combinaison (fichier, teintes, vent) : le résultat sert tel
## quel à un MeshInstance3D isolé (arbre, rocher) OU à un
## MultiMeshInstance3D (herbe, fleurs) — coût de rendu quasi constant
## malgré la densité.
static func prepare_mesh(file: String, tints: Dictionary, wind: bool) -> Mesh:
	var key := "%s|%s|%s" % [file, str(tints), wind]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var scene: PackedScene = load(KIT_DIR + file)
	var proto := scene.instantiate()
	var src_instance := find_mesh_instance(proto)
	var src_mesh: Mesh = src_instance.mesh if src_instance else null
	var mesh: Mesh = src_mesh.duplicate() if src_mesh else null

	if mesh != null:
		for i in mesh.get_surface_count():
			var base := src_mesh.surface_get_material(i)
			var base_color: Color = (base as StandardMaterial3D).albedo_color if base is StandardMaterial3D else Color.WHITE
			var mat_name: String = base.resource_name if base else ""
			var col: Color = tints.get(mat_name, base_color)
			if wind:
				var sh_mat := ShaderMaterial.new()
				sh_mat.shader = get_wind_shader()
				sh_mat.set_shader_parameter("albedo", col)
				mesh.surface_set_material(i, sh_mat)
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_color  = col
				mat.metallic      = 0.0
				mat.roughness     = 1.0
				mat.diffuse_mode  = BaseMaterial3D.DIFFUSE_TOON
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mesh.surface_set_material(i, mat)
	proto.queue_free()
	_mesh_cache[key] = mesh
	return mesh


## Instancie une scène GLB du pack, mesh remplacé par sa version stylée en
## cache — pour un prop isolé (arbre, rocher, buisson). Les props denses
## (herbe, fleurs) doivent utiliser build_multimesh() à la place pour
## rester performants (un seul draw call quel que soit le nombre d'instances).
static func instance(file: String, tints: Dictionary = {}) -> Node3D:
	var scene: PackedScene = load(KIT_DIR + file)
	var node := scene.instantiate()
	var mi := find_mesh_instance(node)
	if mi != null:
		mi.mesh = prepare_mesh(file, tints, false)
	return node


## Regroupe des props en un seul MultiMeshInstance3D (un fichier = un mesh
## partagé, shader de vent avec déphasage par instance) — pour l'herbe et
## les fleurs, quel que soit le nombre d'instances.
## `transforms[i]` = position/échelle/rotation de l'instance i ; `phases[i]`
## = déphasage de vent (indépendant par instance, pour ne pas onduler en bloc).
static func build_multimesh(file: String, transforms: Array, phases: Array, tints: Dictionary = {}) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data  = true
	mm.mesh             = prepare_mesh(file, tints, true)
	mm.instance_count   = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, Color(phases[i], 0.0, 0.0, 0.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # ombres d'herbe/fleurs = bruit visuel
	return mmi
