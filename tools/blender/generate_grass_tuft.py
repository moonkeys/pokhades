"""
Générateur de touffe d'herbe basse (style Kenney Nature Kit — cf.
assets/kenney_nature_kit/grass*.glb déjà utilisés par KitProps.gd) : un
petit bouquet de brins fins, penchés vers l'extérieur, dégradé de couleur
du pied (sombre) à la pointe (clair). Pensé pour être posé en TRÈS grand
nombre au sol — reste volontairement léger (pas de flou/feuilles
individuelles façon arbre, juste des brins plats).

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting" (en haut).
  2. Supprime le cube par défaut de la scène (clic dessus, Suppr).
  3. Nouveau texte → colle tout ce fichier.
  4. Bouton ▶ "Run Script" (ou Alt+P).
  5. Une touffe "GrassTuft" apparaît à l'origine. Vue 3D en mode "Material
     Preview" (touche Z) pour voir les couleurs.
  6. Sélectionne-la → File > Export > glTF 2.0 (.glb), coche
     "Selected Objects".

Relance le script avec une SEED différente pour une nouvelle silhouette.
"""

import bpy
import bmesh
import random
import math
import mathutils

# ─────────────────────────────────────────────────────────────────
# Paramètres — modifie ces valeurs et relance le script pour varier
# ─────────────────────────────────────────────────────────────────
SEED          = 5           # change ce nombre pour une nouvelle silhouette

BLADE_COUNT      = 7         # brins par touffe — peu, ça reste un décor de sol
BLADE_HEIGHT_MIN = 0.16
BLADE_HEIGHT_MAX = 0.30
BLADE_WIDTH      = 0.028     # largeur à la base (tapère à 0 en pointe)
BLADE_SEGMENTS   = 3         # anneaux de hauteur — plus = courbe plus douce
BLADE_BEND_MIN   = 0.06      # décalage latéral de la pointe (courbure)
BLADE_BEND_MAX   = 0.16
TUFT_SPREAD      = 0.10      # rayon de dispersion des pieds de brins

# Couleurs NEUTRES — la saturation finale par biome vient d'ailleurs
# (Environment.adjustment_saturation, cf. BiomeAmbiance), pas d'ici.
COLOR_BASE = (0.20, 0.32, 0.12, 1.0)   # pied, plus sombre/dense
COLOR_TIP  = (0.42, 0.56, 0.22, 1.0)   # pointe, plus claire
BLADE_COLOR_VAR = 0.12                 # variation aléatoire brin par brin

SMOOTH_SHADING = False   # des brins fins facettés lisent mieux que lissés


def _material_double_sided(name: str) -> "bpy.types.Material":
    """Matériau à couleur de sommet, visible RECTO-VERSO (brins fins vus de
    dos sinon invisibles) — évite de dupliquer la géométrie pour ça."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _lerp_rgb(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _build_blade(bm: "bmesh.types.BMesh", layer, base: "mathutils.Vector",
                  lean: "mathutils.Vector", height: float, bend: float,
                  tint: float) -> None:
    """Un brin = une fine bande verticale qui se courbe vers `lean` en
    montant et se rétrécit jusqu'à un point à la pointe. `tint` (0-1)
    teinte légèrement ce brin par rapport aux autres de la touffe."""
    perp = mathutils.Vector((-lean.y, lean.x, 0.0))
    if perp.length < 0.0001:
        perp = mathutils.Vector((1.0, 0.0, 0.0))
    perp.normalize()

    rings = []
    for seg in range(BLADE_SEGMENTS + 1):
        t = seg / BLADE_SEGMENTS
        z = height * t
        lateral = bend * (t ** 1.6)          # la courbure s'accentue vers la pointe
        center = base + lean * lateral + mathutils.Vector((0.0, 0.0, z))
        half_w = (BLADE_WIDTH * 0.5) * (1.0 - t)
        col_here = _lerp_rgb(COLOR_BASE, COLOR_TIP, t)
        col_here = tuple(min(1.0, c * (0.85 + 0.3 * tint)) for c in col_here) + (1.0,)
        if seg == BLADE_SEGMENTS:
            tip_v = bm.verts.new(center)
            rings.append((tip_v, col_here))
        else:
            left  = bm.verts.new(center + perp * half_w)
            right = bm.verts.new(center - perp * half_w)
            rings.append(((left, right), col_here))

    for i in range(BLADE_SEGMENTS - 1):
        (l0, r0), col0 = rings[i]
        (l1, r1), col1 = rings[i + 1]
        face = bm.faces.new((l0, r0, r1, l1))
        for loop in face.loops:
            loop[layer] = col1 if loop.vert in (r1, l1) else col0

    (l_last, r_last), col_last = rings[-2]
    tip_v, col_tip = rings[-1]
    face = bm.faces.new((l_last, r_last, tip_v))
    for loop in face.loops:
        loop[layer] = col_tip if loop.vert is tip_v else col_last


def build_tuft(rng: random.Random) -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("grass_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")

    for _ in range(BLADE_COUNT):
        angle = rng.uniform(0, math.tau)
        dist = rng.uniform(0.0, TUFT_SPREAD)
        base = mathutils.Vector((math.cos(angle) * dist, math.sin(angle) * dist, 0.0))
        lean_angle = angle + rng.uniform(-0.6, 0.6)   # penche globalement vers l'extérieur
        lean = mathutils.Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))
        height = rng.uniform(BLADE_HEIGHT_MIN, BLADE_HEIGHT_MAX)
        bend = rng.uniform(BLADE_BEND_MIN, BLADE_BEND_MAX)
        tint = rng.uniform(-BLADE_COLOR_VAR, BLADE_COLOR_VAR)
        _build_blade(bm, layer, base, lean, height, bend, tint)

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("GrassTuft", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(_material_double_sided("Grass"))
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_SHADING

    # Origine au pied de la touffe (0,0,0) — même convention que les autres
    # décors (KitProps positionne tout depuis la base).
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    return obj


def main() -> None:
    rng = random.Random(SEED)
    obj = build_tuft(rng)
    print(f"GrassTuft généré — {BLADE_COUNT} brins, hauteur max ≈ {BLADE_HEIGHT_MAX:.2f} u "
          f"(SEED={SEED}). Sélectionne-le puis File > Export > glTF 2.0 (.glb).")


main()
