"""
Générateur de fleur basse (style Kenney Nature Kit — cf.
assets/kenney_nature_kit/flower_*.glb déjà utilisés par KitProps.gd,
FLOWERS_RED/PURPLE/YELLOW) : une tige fine + une couronne de pétales en
losange autour d'un petit cœur coloré. Même technique que les feuilles de
l'arbre (petites cartes plates orientées, couleurs de sommet) — pensé pour
être dispersé en nombre dans/à côté des touffes d'herbe.

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting" (en haut).
  2. Supprime le cube par défaut de la scène (clic dessus, Suppr).
  3. Nouveau texte → colle tout ce fichier.
  4. Bouton ▶ "Run Script" (ou Alt+P).
  5. Une fleur "Flower" apparaît à l'origine. Vue 3D en mode "Material
     Preview" (touche Z) pour voir les couleurs.
  6. Sélectionne-la → File > Export > glTF 2.0 (.glb), coche
     "Selected Objects".

Change FLOWER_VARIANT ("red" / "purple" / "yellow") ou SEED et relance
pour varier.
"""

import bpy
import bmesh
import random
import math
import mathutils

# ─────────────────────────────────────────────────────────────────
# Paramètres — modifie ces valeurs et relance le script pour varier
# ─────────────────────────────────────────────────────────────────
SEED           = 2
FLOWER_VARIANT = "red"       # "red" / "purple" / "yellow" — cf. PETAL_PALETTES

STEM_HEIGHT    = 0.22
STEM_WIDTH     = 0.018
STEM_SEGMENTS  = 3
STEM_BEND      = 0.03        # léger arc, comme un vrai brin

PETAL_COUNT    = 6
PETAL_LENGTH   = 0.075
PETAL_WIDTH_RATIO = 0.55     # largeur = longueur × ce ratio
PETAL_UPTILT   = 0.35        # inclinaison vers le haut (rad) — 0 = à plat, effet "coupe"
PETAL_JITTER   = 0.12        # irrégularité d'angle/longueur entre pétales

CENTER_RADIUS  = 0.022
CENTER_HEIGHT  = 0.018

COLOR_STEM   = (0.24, 0.38, 0.15, 1.0)   # vert, cohérent avec generate_grass_tuft
COLOR_CENTER = (0.85, 0.66, 0.16, 1.0)   # cœur jaune, quelle que soit la variante

PETAL_PALETTES = {
    "red":    (0.82, 0.20, 0.22, 1.0),
    "purple": (0.55, 0.28, 0.70, 1.0),
    "yellow": (0.92, 0.78, 0.20, 1.0),
}
PETAL_COLOR_VAR = 0.12       # variation aléatoire, pétale par pétale

SMOOTH_SHADING = False       # pétales/tige facettés — cohérent avec l'herbe


def _material_double_sided(name: str) -> "bpy.types.Material":
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


def _build_stem(bm: "bmesh.types.BMesh", layer, lean: "mathutils.Vector") -> "mathutils.Vector":
    """Tige verticale, légèrement arquée dans la direction `lean` —
    retourne la position de sa pointe (où la couronne de pétales vient se
    poser). Appelée deux fois en croix (cf. build_flower) : une tige plate
    seule peut devenir quasi invisible vue de face sous certains angles."""
    perp = mathutils.Vector((-lean.y, lean.x, 0.0))

    rings = []
    for seg in range(STEM_SEGMENTS + 1):
        t = seg / STEM_SEGMENTS
        z = STEM_HEIGHT * t
        lateral = STEM_BEND * (t ** 1.6)
        center = lean * lateral + mathutils.Vector((0.0, 0.0, z))
        half_w = (STEM_WIDTH * 0.5) * (1.0 - 0.6 * t)   # se resserre un peu, pas jusqu'à 0
        left  = bm.verts.new(center + perp * half_w)
        right = bm.verts.new(center - perp * half_w)
        rings.append((left, right, center))

    for i in range(STEM_SEGMENTS):
        l0, r0, _ = rings[i]
        l1, r1, _ = rings[i + 1]
        face = bm.faces.new((l0, r0, r1, l1))
        for loop in face.loops:
            loop[layer] = COLOR_STEM

    return rings[-1][2]   # centre du dernier anneau = pointe de la tige


def _add_petal(bm: "bmesh.types.BMesh", layer, center: "mathutils.Vector",
                out_dir: "mathutils.Vector", length: float, width: float, color: tuple) -> None:
    up = mathutils.Vector((0.0, 0.0, 1.0))
    side = out_dir.cross(up)
    if side.length < 0.0001:
        side = mathutils.Vector((1.0, 0.0, 0.0))
    side.normalize()

    base  = center
    tip   = center + out_dir * length
    left  = center + side * (width * 0.5) + out_dir * (length * 0.18)
    right = center - side * (width * 0.5) + out_dir * (length * 0.18)

    for verts_order in ((base, left, tip, right), (base, right, tip, left)):
        verts = [bm.verts.new(v) for v in verts_order]
        face = bm.faces.new(verts)
        for loop in face.loops:
            loop[layer] = color


def _add_center(bm: "bmesh.types.BMesh", layer, pos: "mathutils.Vector") -> None:
    """Petit cœur conique (façon disque floral) posé à la pointe de la
    tige, au centre de la couronne de pétales."""
    core = bmesh.new()
    bmesh.ops.create_cone(
        core, cap_ends=True, segments=6,
        radius1=CENTER_RADIUS, radius2=CENTER_RADIUS * 0.75, depth=CENTER_HEIGHT,
    )
    bmesh.ops.translate(core, verts=core.verts, vec=pos + mathutils.Vector((0, 0, CENTER_HEIGHT * 0.5)))
    mesh_tmp = bpy.data.meshes.new("tmp_center")
    core.to_mesh(mesh_tmp)
    core.free()

    before = len(bm.faces)
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)
    bm.faces.ensure_lookup_table()
    for face in list(bm.faces)[before:]:
        for loop in face.loops:
            loop[layer] = COLOR_CENTER


def build_flower(rng: random.Random) -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("flower_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")

    lean = mathutils.Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.0))
    if lean.length < 0.0001:
        lean = mathutils.Vector((1.0, 0.0, 0.0))
    lean.normalize()
    lean_cross = mathutils.Vector((-lean.y, lean.x, 0.0))   # tige jumelle à 90°
    tip = _build_stem(bm, layer, lean)
    _build_stem(bm, layer, lean_cross)

    base_color = PETAL_PALETTES.get(FLOWER_VARIANT, PETAL_PALETTES["red"])
    for i in range(PETAL_COUNT):
        ang = (i / PETAL_COUNT) * math.tau + rng.uniform(-PETAL_JITTER, PETAL_JITTER)
        horiz = mathutils.Vector((math.cos(ang), math.sin(ang), 0.0))
        out_dir = (horiz * math.cos(PETAL_UPTILT) + mathutils.Vector((0, 0, 1)) * math.sin(PETAL_UPTILT))
        out_dir.normalize()
        length = PETAL_LENGTH * rng.uniform(1.0 - PETAL_JITTER, 1.0 + PETAL_JITTER)
        t = rng.uniform(0.0, 1.0)
        dark  = tuple(max(0.0, c * (1.0 - PETAL_COLOR_VAR)) for c in base_color[:3])
        light = tuple(min(1.0, c * (1.0 + PETAL_COLOR_VAR)) for c in base_color[:3])
        color = _lerp_rgb(dark, light, t) + (1.0,)
        _add_petal(bm, layer, tip, out_dir, length, length * PETAL_WIDTH_RATIO, color)

    _add_center(bm, layer, tip)

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Flower", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(_material_double_sided("Flower_%s" % FLOWER_VARIANT))
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_SHADING

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    return obj


def main() -> None:
    rng = random.Random(SEED)
    build_flower(rng)
    print(f"Flower ({FLOWER_VARIANT}) généré — hauteur ≈ {STEM_HEIGHT + PETAL_LENGTH:.2f} u "
          f"(SEED={SEED}). Sélectionne-la puis File > Export > glTF 2.0 (.glb).")


main()
