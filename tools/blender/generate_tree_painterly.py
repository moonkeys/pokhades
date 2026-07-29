"""
Générateur d'arbre style PEINT / GHIBLI — variante "haut de gamme" du
générateur low-poly (generate_tree.py). Ici le détail vient de la COULEUR
et de la LUMIÈRE, pas de la géométrie :

  - feuillage = grosses masses arrondies qui se fondent en une silhouette
    généreuse et "gonflée" (façon nuage de feuilles), ombrage LISSÉ (pas de
    facettes) ;
  - lumière PEINTE dans les couleurs de sommet : chaud/clair au sommet
    (soleil), profond/froid en dessous (ombre) — un dégradé de lumière
    directionnelle "cuit" dans le mesh, comme un décor peint à la main ;
  - variation de teinte basse fréquence par-dessus, façon coups de pinceau.

Aucune texture/UV : tout passe par les couleurs de sommet (attribut glTF
COLOR_0), lues nativement par Godot — cohérent avec le pipeline existant.

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting".
  2. Supprime le cube par défaut de la scène (clic, Suppr).
  3. Nouveau texte → colle tout ce fichier.
  4. Bouton ▶ "Run Script" (ou Alt+P).
  5. Vue 3D en mode "Material Preview" (touche Z) pour voir les couleurs.
  6. Sélectionne l'arbre → File > Export > glTF 2.0 (.glb), coche
     "Selected Objects".

Change SEED pour une nouvelle silhouette.
"""

import bpy
import bmesh
import random
import math
import mathutils

# ═══════════════════════════════════════════════════════════════════
# Réglages
# ═══════════════════════════════════════════════════════════════════
SEED = 7

# ── Tronc ────────────────────────────────────────────────────────
TRUNK_HEIGHT   = 1.15
TRUNK_RADIUS   = 0.14
TRUNK_SEGMENTS = 20          # lisse (le tronc est smooth-shadé)
TRUNK_RINGS    = 7
TRUNK_FLARE    = 1.5         # évasement de la base
TRUNK_BEND     = 0.05        # léger cambrage

# ── Feuillage ────────────────────────────────────────────────────
CANOPY_CENTER_Z = 1.50
CANOPY_RADIUS   = 0.78       # grosse couronne généreuse
CANOPY_SUBDIV   = 4          # haute résolution = smooth propre
LOBE_COUNT      = 10         # masses arrondies qui bouillonnent en silhouette
LOBE_SPREAD_XY  = 0.52       # étalement horizontal — lobes qui dépassent au bord
LOBE_SPREAD_Z   = 0.46       # étalement vertical (silhouette "gonflée")
LOBE_UP_BIAS    = 0.55       # 0 = lobes centrés, 1 = tous poussés vers le HAUT
                             # (le sommet bouillonne, la base reste pleine)
LOBE_RADIUS_MIN = 0.46       # ×CANOPY_RADIUS — plus petits = bosses distinctes
LOBE_RADIUS_MAX = 0.78
BILLOW_AMOUNT   = 0.09       # bosselage doux ×CANOPY_RADIUS (soft lumps de nuage)
BILLOW_FREQ     = 5.0

# ── Palette peinte (dégradé de lumière du haut vers le bas) ──────────
# Ordre : ombre (bas) → milieu → soleil (sommet). Teintes chaudes vers le
# sommet, froides/profondes en dessous — la signature du look peint.
COLOR_LEAF_SUN    = (0.62, 0.76, 0.34, 1.0)   # crête ensoleillée, jaune-vert chaud
COLOR_LEAF_MID    = (0.34, 0.55, 0.24, 1.0)   # vert franc
COLOR_LEAF_SHADOW = (0.15, 0.32, 0.20, 1.0)   # creux ombragés, vert profond froid

# Poids du dégradé : combien la HAUTEUR vs l'ORIENTATION (face vers le haut)
# comptent dans la lumière peinte. up_weight fort = look "lumière du ciel".
LIGHT_HEIGHT_WEIGHT = 0.40
LIGHT_UP_WEIGHT     = 0.46
LIGHT_MOTTLE_WEIGHT = 0.14   # variation aléatoire façon coups de pinceau
MOTTLE_FREQ         = 2.8

COLOR_TRUNK_TOP  = (0.42, 0.30, 0.18, 1.0)
COLOR_TRUNK_BASE = (0.22, 0.15, 0.10, 1.0)   # base assombrie = ancrage au sol

SMOOTH_SHADING = True        # ombrage lissé = cœur du style peint


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════
def _lerp3(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _grad3(shadow: tuple, mid: tuple, sun: tuple, t: float) -> tuple:
    """Dégradé à 3 arrêts ombre→milieu→soleil, t dans [0, 1]."""
    if t < 0.5:
        return _lerp3(shadow, mid, t * 2.0)
    return _lerp3(mid, sun, (t - 0.5) * 2.0)


def _cheap_noise3(x: float, y: float, z: float, freq: float, seed: float) -> float:
    """Bruit continu pas cher (somme de sinus déphasés), ~[-1, 1]."""
    return (
        math.sin(x * freq + seed) +
        math.sin(y * freq * 1.31 + seed * 1.7) +
        math.sin(z * freq * 0.77 + seed * 2.3) +
        math.sin((x + y) * freq * 0.53 + seed * 0.4) +
        math.sin((y - z) * freq * 0.61 + seed * 3.1)
    ) / 5.0


def _material(name: str, base_rgba: tuple) -> "bpy.types.Material":
    """Matériau mat qui lit les couleurs de sommet (calque "Col")."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_rgba
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _new_object(mesh: "bpy.types.Mesh", name: str) -> "bpy.types.Object":
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _shade(obj: "bpy.types.Object") -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_SHADING


# ═══════════════════════════════════════════════════════════════════
# Tronc
# ═══════════════════════════════════════════════════════════════════
def build_trunk(rng: random.Random) -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("trunk_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")

    rings = []
    for ri in range(TRUNK_RINGS + 1):
        t = ri / TRUNK_RINGS
        z = t * TRUNK_HEIGHT
        radius = TRUNK_RADIUS * (1.0 - 0.45 * t)
        if t < 0.18:
            radius *= 1.0 + (0.18 - t) / 0.18 * (TRUNK_FLARE - 1.0)
        drift_x = math.sin(t * 2.2 + SEED) * TRUNK_BEND * t
        drift_y = math.cos(t * 2.2 + SEED) * TRUNK_BEND * t
        ring = []
        for s in range(TRUNK_SEGMENTS):
            ang = (s / TRUNK_SEGMENTS) * math.tau
            x = drift_x + math.cos(ang) * radius
            y = drift_y + math.sin(ang) * radius
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)

    for r in range(TRUNK_RINGS):
        a, b = rings[r], rings[r + 1]
        for s in range(TRUNK_SEGMENTS):
            s2 = (s + 1) % TRUNK_SEGMENTS
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    bm.faces.new(reversed(rings[0]))
    bm.faces.new(rings[-1])
    bm.normal_update()

    # Dégradé vertical : base sombre (ancrage) → sommet plus clair.
    for face in bm.faces:
        for loop in face.loops:
            t = max(0.0, min(1.0, loop.vert.co.z / TRUNK_HEIGHT))
            col = _lerp3(COLOR_TRUNK_BASE, COLOR_TRUNK_TOP, t)
            loop[layer] = (col[0], col[1], col[2], 1.0)

    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "PT_Trunk")
    obj.data.materials.append(_material("PT_Bark", COLOR_TRUNK_TOP))
    _shade(obj)
    return obj


# ═══════════════════════════════════════════════════════════════════
# Feuillage peint
# ═══════════════════════════════════════════════════════════════════
def _add_lobe(bm: "bmesh.types.BMesh", center: tuple, radius: float) -> None:
    lobe = bmesh.new()
    bmesh.ops.create_icosphere(lobe, subdivisions=CANOPY_SUBDIV, radius=radius)
    bmesh.ops.translate(lobe, verts=lobe.verts, vec=center)
    tmp = bpy.data.meshes.new("tmp_lobe")
    lobe.to_mesh(tmp)
    lobe.free()
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)


def build_canopy(rng: random.Random) -> "bpy.types.Object":
    mesh = bpy.data.meshes.new("canopy_mesh")
    bm = bmesh.new()

    # Un lobe central généreux + des lobes autour/au-dessus qui se fondent :
    # la silhouette "gonflée" caractéristique du feuillage peint.
    _add_lobe(bm, (0.0, 0.0, CANOPY_CENTER_Z), CANOPY_RADIUS)
    for _ in range(LOBE_COUNT - 1):
        # z décalé vers le HAUT (LOBE_UP_BIAS) : les bosses s'accumulent au
        # sommet façon nuage/chou-fleur, la base reste comblée par le lobe
        # central — plutôt qu'une répartition symétrique qui ferait boule.
        dz = rng.uniform(-LOBE_SPREAD_Z * (1.0 - LOBE_UP_BIAS), LOBE_SPREAD_Z)
        offset = (
            rng.uniform(-LOBE_SPREAD_XY, LOBE_SPREAD_XY),
            rng.uniform(-LOBE_SPREAD_XY, LOBE_SPREAD_XY),
            CANOPY_CENTER_Z + dz,
        )
        radius = CANOPY_RADIUS * rng.uniform(LOBE_RADIUS_MIN, LOBE_RADIUS_MAX)
        _add_lobe(bm, offset, radius)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)

    # Bosselage doux : les masses gagnent des "bosses de nuage" au lieu de
    # rester des sphères parfaites — mais léger, on reste dans le smooth.
    bm.normal_update()
    billow = BILLOW_AMOUNT * CANOPY_RADIUS
    for v in bm.verts:
        n = _cheap_noise3(v.co.x, v.co.y, v.co.z, BILLOW_FREQ, SEED)
        v.co += v.normal * (n * billow)
    bm.normal_update()

    # ── LE cœur du style : lumière peinte dans les couleurs de sommet ──
    zs = [v.co.z for v in bm.verts]
    z0, z1 = min(zs), max(zs)
    z_span = max(1e-4, z1 - z0)
    layer = bm.loops.layers.color.new("Col")
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert
            height = (v.co.z - z0) / z_span                 # 0 bas → 1 haut
            up = v.normal.z * 0.5 + 0.5                      # 0 dessous → 1 dessus
            mottle = _cheap_noise3(v.co.x, v.co.y, v.co.z, MOTTLE_FREQ, SEED + 9)
            mottle = (mottle + 1.0) * 0.5                    # 0..1
            light = (
                LIGHT_HEIGHT_WEIGHT * height +
                LIGHT_UP_WEIGHT * up +
                LIGHT_MOTTLE_WEIGHT * mottle
            )
            light = max(0.0, min(1.0, light))
            col = _grad3(COLOR_LEAF_SHADOW, COLOR_LEAF_MID, COLOR_LEAF_SUN, light)
            loop[layer] = (col[0], col[1], col[2], 1.0)

    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "PT_Canopy")
    obj.data.materials.append(_material("PT_Leaves", COLOR_LEAF_MID))
    _shade(obj)
    return obj


def main() -> None:
    rng = random.Random(SEED)
    trunk = build_trunk(rng)
    canopy = build_canopy(rng)

    bpy.ops.object.select_all(action="DESELECT")
    trunk.select_set(True)
    canopy.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.join()
    trunk.name = "PaintedTree"

    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")

    print(f"PaintedTree généré (SEED={SEED}). Vue Material Preview (Z) pour "
          f"voir la lumière peinte. Export : File > glTF 2.0 (.glb).")


main()
