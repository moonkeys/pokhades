"""
Générateur d'arbre à baies low-poly (style Kenney Nature Kit — cf.
assets/kenney_nature_kit/ déjà utilisé par KitProps.gd) : tronc conique
facetté + grappe de "blobs" de feuillage + petites baies rouges.

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting" (en haut).
  2. Nouveau texte → colle tout ce fichier.
  3. Bouton ▶ "Run Script" (ou Alt+P).
  4. Un arbre "BerryTree" apparaît à l'origine, prêt à exporter.
  5. Sélectionne-le → File > Export > glTF 2.0 (.glb) → coche
     "Selected Objects" pour n'exporter que lui.

Relance le script pour générer une nouvelle variante (SEED différente,
tout en haut) — chaque graine donne une silhouette différente.
"""

import bpy
import bmesh
import random
import math

# ─────────────────────────────────────────────────────────────────
# Paramètres — modifie ces valeurs et relance le script pour varier
# ─────────────────────────────────────────────────────────────────
SEED           = 7          # change ce nombre pour une nouvelle silhouette
TRUNK_HEIGHT   = 1.2
TRUNK_RADIUS   = 0.11
CANOPY_HEIGHT  = 0.95        # centre du feuillage au-dessus du sol
CANOPY_RADIUS  = 0.55
BERRY_COUNT    = 10
BERRY_RADIUS   = 0.05

# Palette alignée sur BiomeAmbiance._FOREST_PALETTE (leaves_color) et le
# rouge de baie classique façon Cheri Berry — reste cohérent avec le reste
# du décor généré par KitProps/BiomeAmbiance.
COLOR_TRUNK  = (0.30, 0.20, 0.12, 1.0)   # brun bois
COLOR_LEAVES = (0.36, 0.50, 0.20, 1.0)   # olive, cf. FOREST_PALETTE.leaves_color
COLOR_BERRY  = (0.78, 0.14, 0.12, 1.0)   # rouge baie


def _material(name: str, rgba: tuple) -> "bpy.types.Material":
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    # Cherché par TYPE, pas par nom : le nom affiché du nœud ("Principled
    # BSDF") est traduit dans les Blender en langue non-anglaise (ex. "BSDF
    # guidée" en français) — nodes.get("Principled BSDF") y renverrait None
    # et le matériau resterait blanc par défaut, sans aucune erreur visible.
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def _new_object(mesh: "bpy.types.Mesh", name: str) -> "bpy.types.Object":
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _shade_flat(obj: "bpy.types.Object") -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = False


def build_trunk() -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("trunk_mesh")
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        segments=7,                 # peu de côtés = facettes visibles (low-poly)
        radius1=TRUNK_RADIUS,
        radius2=TRUNK_RADIUS * 0.55,
        depth=TRUNK_HEIGHT,
    )
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, TRUNK_HEIGHT * 0.5))
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "BerryTree_Trunk")
    obj.data.materials.append(_material("BerryTree_Bark", COLOR_TRUNK))
    _shade_flat(obj)
    return obj


def build_canopy(rng: random.Random) -> "bpy.types.Object":
    """3-4 icosphères basse résolution imbriquées et décalées : le look
    "blob facetté" caractéristique des arbres Kenney (tree_oak / tree_fat),
    plutôt qu'une sphère parfaite trop lisse."""
    mesh = bpy.data.meshes.new("canopy_mesh")
    bm = bmesh.new()
    blob_count = rng.randint(3, 4)
    for i in range(blob_count):
        offset = (
            rng.uniform(-0.14, 0.14),
            rng.uniform(-0.14, 0.14),
            CANOPY_HEIGHT + rng.uniform(-0.08, 0.14),
        )
        radius = CANOPY_RADIUS * rng.uniform(0.75, 0.95)
        blob = bmesh.new()
        # subdivisions=2 : assez de facettes pour lire "rond" (façon
        # tree_oak Kenney) sans tomber dans les pointes trop anguleuses
        # d'un icosaèdre subdivisions=1.
        bmesh.ops.create_icosphere(blob, subdivisions=2, radius=radius)
        bmesh.ops.translate(blob, verts=blob.verts, vec=offset)
        mesh_tmp = bpy.data.meshes.new("tmp")
        blob.to_mesh(mesh_tmp)
        blob.free()
        bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "BerryTree_Canopy")
    obj.data.materials.append(_material("BerryTree_Leaves", COLOR_LEAVES))
    _shade_flat(obj)
    return obj


def build_berries(rng: random.Random) -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("berries_mesh")
    bm = bmesh.new()
    for i in range(BERRY_COUNT):
        theta = rng.uniform(0, math.tau)
        phi = rng.uniform(0.15, math.pi - 0.15)
        r = CANOPY_RADIUS * rng.uniform(0.85, 1.05)   # en surface du feuillage
        pos = (
            r * math.sin(phi) * math.cos(theta),
            r * math.sin(phi) * math.sin(theta),
            CANOPY_HEIGHT + r * math.cos(phi) * 0.6,
        )
        berry = bmesh.new()
        bmesh.ops.create_icosphere(berry, subdivisions=1, radius=BERRY_RADIUS)
        bmesh.ops.translate(berry, verts=berry.verts, vec=pos)
        mesh_tmp = bpy.data.meshes.new("tmp_berry")
        berry.to_mesh(mesh_tmp)
        berry.free()
        bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "BerryTree_Berries")
    obj.data.materials.append(_material("BerryTree_Berry", COLOR_BERRY))
    _shade_flat(obj)
    return obj


def main() -> None:
    rng = random.Random(SEED)

    trunk = build_trunk()
    canopy = build_canopy(rng)
    berries = build_berries(rng)

    # Fusionne les 3 parties en UN SEUL objet (3 matériaux) — plus simple à
    # exporter/instancier dans Godot qu'une hiérarchie à plusieurs nœuds,
    # même convention que les .glb du Kenney Nature Kit.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (trunk, canopy, berries):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.join()
    trunk.name = "BerryTree"

    # Origine à la base (0,0,0) au sol — même convention que les props
    # Kenney (KitProps positionne tout depuis la base, jamais le centre).
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")

    print(f"BerryTree généré — hauteur ≈ {TRUNK_HEIGHT + CANOPY_HEIGHT * 0.3 + CANOPY_RADIUS:.2f} u "
          f"(SEED={SEED}). Sélectionne-le puis File > Export > glTF 2.0 (.glb).")


main()
