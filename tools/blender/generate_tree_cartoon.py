"""
Générateur d'arbres CARTOON DÉTAILLÉ — esprit low-poly coloré mais avec une
VRAIE charpente de branches visible (ramification récursive) et un feuillage
facetté piqué de feuilles fines. Le détail vient de la structure visible +
des feuilles découpées, pas de masses lissées.

Un seul réglage à connaître : PRESET (l'espèce). Tout le reste se configure
tout seul. Aucune texture/UV — couleurs de sommet (glTF COLOR_0), lues
nativement par Godot.

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting".
  2. Supprime le cube par défaut (clic, Suppr).
  3. Nouveau texte → colle tout ce fichier.
  4. Change la ligne PRESET juste en dessous.
  5. ▶ Run Script (Alt+P) → vue "Material Preview" (Z) pour les couleurs.
  6. Sélectionne l'arbre → File > Export > glTF 2.0 (.glb), "Selected
     Objects".

Change SEED pour une nouvelle silhouette DU MÊME preset.
"""

import bpy
import bmesh
import random
import math
import mathutils

# ═══════════════════════════════════════════════════════════════════
# ⭐ CHOISIS UN PRESET ICI ⭐
# ═══════════════════════════════════════════════════════════════════
SEED   = 4
PRESET = "oak"   # "oak" / "oak_clumped" / "dead_oak" / "pine" / "sakura" /
                 # "willow" / "bonsai" / "palm"


# ═══════════════════════════════════════════════════════════════════
# Réglages de BASE (valeurs par défaut = preset "oak"). Chaque preset
# ne surcharge que ce qui le distingue (voir _PRESETS plus bas).
# ═══════════════════════════════════════════════════════════════════
# Modes (aiguillage) :
TRUNK_MODE   = "cartoon"   # "cartoon" (charpente récursive) / "pine" / "palm"
FOLIAGE_MODE = "clumps"    # "clumps" / "along" (feuilles le long des branches) / "none"

# ── Charpente récursive (TRUNK_MODE="cartoon") ───────────────────
TRUNK_HEIGHT   = 0.95
TRUNK_RADIUS   = 0.15
TRUNK_TILT     = 0.08        # inclinaison du tronc
BRANCH_LEVELS  = 3           # nb de divisions après le tronc
CHILDREN_MIN   = 2
CHILDREN_MAX   = 3
FIRST_LEN      = 0.74        # longueur des branches maîtresses
LENGTH_FALLOFF = 0.76
RADIUS_FALLOFF = 0.62
SPREAD_ANGLE   = 0.88        # écart angulaire des filles (rad)
UP_BIAS        = 0.28        # 0 = suit la mère, 1 = redressé vers le haut
BEND_JITTER    = 0.24
GRAVITY        = 0.0         # tire les branches vers le bas (saule)
TERMINAL_DROOP = 0.0         # 0 = rien ; 1 = branches terminales pendantes (saule)
TERMINAL_LEN_MULT = 1.0      # longueur des branches terminales (saule = long)
TERMINAL_RADIUS_MULT = 1.0   # épaisseur des branches terminales (saule = fin fouet)
TUBE_SEGMENTS  = 6

# ── Feuillage en touffes (FOLIAGE_MODE="clumps") ─────────────────
CLUMP_RADIUS_MIN = 0.26
CLUMP_RADIUS_MAX = 0.40
CLUMP_SUBDIV     = 2
CLUMP_BUMP       = 0.14
CLUMP_SQUASH     = 1.0       # <1 = coussins aplatis (bonsaï)
CLUMP_ON_NONTERMINAL = 0.15  # proba de touffe sur un nœud non terminal
CLUMP_KEEP_CHANCE    = 1.0   # proba qu'un rameau TERMINAL porte une touffe
                             # (< 1 = feuillage clairsemé, charpente visible)

LEAVES_PER_CLUMP = 20
LEAF_LEN_MIN     = 0.06
LEAF_LEN_MAX     = 0.11
LEAF_WIDTH_RATIO = 0.42
LEAF_TILT        = 0.7
LEAF_PUSH        = 0.10
LEAF_COLOR_VAR   = 0.18

# ── Feuilles le long des branches (FOLIAGE_MODE="along", saule) ──
ALONG_LEAVES_PER_SEG = 7     # feuilles réparties sur chaque branche terminale
ALONG_LEAF_LEN_MIN   = 0.05
ALONG_LEAF_LEN_MAX   = 0.09
ALONG_LEAF_WIDTH_RATIO = 0.30

# ── Sapin (TRUNK_MODE="pine") — étages de cônes ──────────────────
PINE_TRUNK_HEIGHT = 0.42
PINE_LAYER_COUNT  = 6
PINE_LAYER_HEIGHT = 0.46
PINE_BASE_RADIUS  = 0.62
PINE_TOP_RADIUS   = 0.09
PINE_OVERLAP      = 0.40
PINE_JAG          = 0.10
PINE_SEGMENTS     = 10

# ── Palmier (TRUNK_MODE="palm") ──────────────────────────────────
PALM_TRUNK_HEIGHT = 2.05
PALM_TRUNK_RADIUS = 0.10
PALM_RING_FREQ    = 14.0
PALM_FROND_COUNT  = 9
PALM_FROND_LEN_MIN = 0.55
PALM_FROND_LEN_MAX = 0.80
PALM_FROND_AMP_MIN = 0.22
PALM_FROND_AMP_MAX = 0.38
PALM_FROND_ARC_K   = 1.35
PALM_FROND_SEGMENTS = 8
PALM_FROND_SPINE_W = 0.032
PALM_LEAFLETS_PER_SIDE = 7
PALM_LEAFLET_LEN_MIN = 0.11
PALM_LEAFLET_LEN_MAX = 0.17
PALM_LEAFLET_W_RATIO = 0.16

# ── Sakura : tapis de pétales au sol ─────────────────────────────
GROUND_PETALS      = False
GROUND_PETAL_COUNT = 34
GROUND_PETAL_RADIUS_MIN = 0.3
GROUND_PETAL_RADIUS_MAX = 1.1

# ── Palette (neutre — saturation par biome côté moteur) ─────────────
COLOR_BARK_DARK  = (0.24, 0.15, 0.09, 1.0)
COLOR_BARK_LIGHT = (0.40, 0.28, 0.17, 1.0)
COLOR_LEAF       = (0.30, 0.50, 0.22, 1.0)
BARK_RINGS       = False     # True = anneaux horizontaux (palmier)
LEAF_MOTTLE_DARK  = 0.86
LEAF_MOTTLE_LIGHT = 1.20
MOTTLE_FREQ       = 3.0

SMOOTH_TRUNK   = True
SMOOTH_FOLIAGE = False


# ═══════════════════════════════════════════════════════════════════
# PRESETS — chacun ne surcharge que ses différences
# ═══════════════════════════════════════════════════════════════════
_PRESETS = {
    "oak": {},

    "oak_clumped": {
        "BRANCH_LEVELS": 2, "SPREAD_ANGLE": 1.05, "FIRST_LEN": 0.9,
        "CLUMP_RADIUS_MIN": 0.34, "CLUMP_RADIUS_MAX": 0.5,
        "CLUMP_ON_NONTERMINAL": 0.0,
    },

    "dead_oak": {
        "FOLIAGE_MODE": "none", "BRANCH_LEVELS": 4,
        "SPREAD_ANGLE": 0.7, "UP_BIAS": 0.4, "BEND_JITTER": 0.3,
        "TERMINAL_LEN_MULT": 0.8,
    },

    "pine": {
        "TRUNK_MODE": "pine", "FOLIAGE_MODE": "none",
        "COLOR_LEAF": (0.15, 0.31, 0.19, 1.0),
    },

    "sakura": {
        "COLOR_LEAF": (0.90, 0.66, 0.76, 1.0),
        "COLOR_BARK_DARK": (0.18, 0.14, 0.14, 1.0),
        "COLOR_BARK_LIGHT": (0.34, 0.27, 0.25, 1.0),
        "GROUND_PETALS": True,
    },

    "willow": {
        "FOLIAGE_MODE": "along", "BRANCH_LEVELS": 3,
        "SPREAD_ANGLE": 0.7, "UP_BIAS": 0.35, "GRAVITY": 0.3,
        "TERMINAL_DROOP": 0.92, "TERMINAL_LEN_MULT": 2.3,
        "TERMINAL_RADIUS_MULT": 0.4,                    # fouets vraiment fins
        "CHILDREN_MIN": 3, "CHILDREN_MAX": 4,
        "TRUNK_RADIUS": 0.13, "RADIUS_FALLOFF": 0.5,
        "ALONG_LEAVES_PER_SEG": 26,                    # rideau bien dense
        "ALONG_LEAF_LEN_MIN": 0.07, "ALONG_LEAF_LEN_MAX": 0.12,
        "ALONG_LEAF_WIDTH_RATIO": 0.42,
        "COLOR_LEAF": (0.46, 0.56, 0.24, 1.0),
        "COLOR_BARK_DARK": (0.26, 0.24, 0.14, 1.0),
        "COLOR_BARK_LIGHT": (0.40, 0.38, 0.22, 1.0),
    },

    "bonsai": {
        "TRUNK_HEIGHT": 1.4, "TRUNK_RADIUS": 0.22, "TRUNK_TILT": 0.35,
        "BRANCH_LEVELS": 2, "FIRST_LEN": 0.9, "LENGTH_FALLOFF": 0.8,
        "SPREAD_ANGLE": 1.25, "UP_BIAS": 0.12, "CHILDREN_MIN": 2, "CHILDREN_MAX": 3,
        "CLUMP_RADIUS_MIN": 0.34, "CLUMP_RADIUS_MAX": 0.5, "CLUMP_SQUASH": 0.4,
        "CLUMP_ON_NONTERMINAL": 0.0,
        "COLOR_LEAF": (0.22, 0.42, 0.20, 1.0),
    },

    "palm": {
        "TRUNK_MODE": "palm", "FOLIAGE_MODE": "none", "BARK_RINGS": True,
        "PALM_TRUNK_HEIGHT": 1.7, "PALM_TRUNK_RADIUS": 0.12,
        "PALM_FROND_COUNT": 13,
        "PALM_FROND_LEN_MIN": 0.82, "PALM_FROND_LEN_MAX": 1.15,
        "PALM_FROND_AMP_MIN": 0.28, "PALM_FROND_AMP_MAX": 0.46,
        "PALM_FROND_SPINE_W": 0.05,
        "PALM_LEAFLETS_PER_SIDE": 12,
        "PALM_LEAFLET_LEN_MIN": 0.20, "PALM_LEAFLET_LEN_MAX": 0.30,
        "PALM_LEAFLET_W_RATIO": 0.30,
        "COLOR_LEAF": (0.24, 0.48, 0.22, 1.0),
        "COLOR_BARK_DARK": (0.30, 0.24, 0.15, 1.0),
        "COLOR_BARK_LIGHT": (0.48, 0.40, 0.26, 1.0),
    },

    # ── Arbre de ZONE TARDIVE (cf. DA §2 pilier 3) : noueux, tordu, sombre,
    # feuillage clairsemé. Palette d'ombre (bark quasi noir, feuillage vert
    # sourd froid). Beaucoup de niveaux de branches = charpente tourmentée.
    "gnarled": {
        "BRANCH_LEVELS": 4, "CHILDREN_MIN": 2, "CHILDREN_MAX": 3,
        "SPREAD_ANGLE": 1.08, "UP_BIAS": 0.20, "BEND_JITTER": 0.5,
        "TRUNK_TILT": 0.26, "TRUNK_RADIUS": 0.17, "TRUNK_HEIGHT": 0.9,
        "FIRST_LEN": 0.78, "LENGTH_FALLOFF": 0.74,
        # feuillage CLAIRSEMÉ : petites touffes, une branche sur ~6 seulement,
        # pour que la charpente tordue reste bien visible (menace).
        "CLUMP_RADIUS_MIN": 0.13, "CLUMP_RADIUS_MAX": 0.22,
        "CLUMP_ON_NONTERMINAL": 0.0, "LEAVES_PER_CLUMP": 11,
        "CLUMP_KEEP_CHANCE": 0.6,   # proba qu'un rameau terminal PORTE une touffe
        "COLOR_LEAF": (0.17, 0.30, 0.24, 1.0),
        "COLOR_BARK_DARK": (0.08, 0.08, 0.09, 1.0),
        "COLOR_BARK_LIGHT": (0.20, 0.18, 0.16, 1.0),
    },

    # ── Marais gothique — SQUELETTE NU tordu (dramatique, très gothique).
    # Écorce brune LISIBLE (pas le noir plat). C'est l'arbre principal du
    # marécage (cf. DA), majoritaire dans le mix.
    "gnarled_bare": {
        "FOLIAGE_MODE": "none",
        "BRANCH_LEVELS": 4, "CHILDREN_MIN": 2, "CHILDREN_MAX": 3,
        "SPREAD_ANGLE": 1.08, "UP_BIAS": 0.20, "BEND_JITTER": 0.5,
        "TRUNK_TILT": 0.26, "TRUNK_RADIUS": 0.17, "TRUNK_HEIGHT": 0.9,
        "FIRST_LEN": 0.78, "LENGTH_FALLOFF": 0.74, "TERMINAL_LEN_MULT": 0.85,
        "COLOR_BARK_DARK": (0.15, 0.13, 0.12, 1.0),
        "COLOR_BARK_LIGHT": (0.34, 0.29, 0.25, 1.0),
    },

    # ── Marais gothique — quelques feuillus à CANOPÉE SOMBRE DENSE (masse
    # cohérente, pas des boules) pour varier la forêt morte. Minoritaire.
    "gnarled_leafy": {
        "BRANCH_LEVELS": 4, "CHILDREN_MIN": 2, "CHILDREN_MAX": 3,
        "SPREAD_ANGLE": 1.08, "UP_BIAS": 0.20, "BEND_JITTER": 0.5,
        "TRUNK_TILT": 0.26, "TRUNK_RADIUS": 0.17, "TRUNK_HEIGHT": 0.9,
        "FIRST_LEN": 0.78, "LENGTH_FALLOFF": 0.74,
        "CLUMP_RADIUS_MIN": 0.30, "CLUMP_RADIUS_MAX": 0.46,
        "CLUMP_ON_NONTERMINAL": 0.5, "CLUMP_KEEP_CHANCE": 1.0,
        "LEAVES_PER_CLUMP": 14,
        "COLOR_LEAF": (0.16, 0.28, 0.22, 1.0),   # vert marais sombre et froid
        "COLOR_BARK_DARK": (0.15, 0.13, 0.12, 1.0),
        "COLOR_BARK_LIGHT": (0.34, 0.29, 0.25, 1.0),
    },
}
if PRESET not in _PRESETS:
    raise ValueError(f"PRESET inconnu : {PRESET!r}. Choix : {sorted(_PRESETS)}")
globals().update(_PRESETS[PRESET])


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════
def _noise(x, y, z, freq, seed):
    return (
        math.sin(x * freq + seed) +
        math.sin(y * freq * 1.31 + seed * 1.7) +
        math.sin(z * freq * 0.77 + seed * 2.3) +
        math.sin((x + y) * freq * 0.53 + seed * 0.4)
    ) / 4.0


def _material(name, base_rgba, double_sided=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    if double_sided:
        mat.use_backface_culling = False
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


def _new_object(mesh, name):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _perp_basis(axis):
    ref = mathutils.Vector((0, 0, 1)) if abs(axis.z) < 0.9 else mathutils.Vector((1, 0, 0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    return u, v


def _bark_color(z):
    if BARK_RINGS:
        band = 0.5 + 0.5 * math.sin(z * PALM_RING_FREQ)
        t = max(0.0, min(1.0, band))
    else:
        t = max(0.0, min(1.0, z / (TRUNK_HEIGHT * 2.2)))
    return tuple(COLOR_BARK_DARK[i] + (COLOR_BARK_LIGHT[i] - COLOR_BARK_DARK[i]) * t
                 for i in range(3)) + (1.0,)


def _leaf_mottle(v, base):
    m = (_noise(v.x, v.y, v.z, MOTTLE_FREQ, SEED + 5) + 1.0) * 0.5
    k = LEAF_MOTTLE_DARK + (LEAF_MOTTLE_LIGHT - LEAF_MOTTLE_DARK) * m
    return tuple(min(1.0, base[i] * k) for i in range(3)) + (1.0,)


def _add_leaf_card(bm, layer, center, normal, length, width, tilt, rgba):
    normal = normal.normalized()
    arb = mathutils.Vector((0, 0, 1)) if abs(normal.z) < 0.9 else mathutils.Vector((1, 0, 0))
    tan = arb.cross(normal).normalized()
    bit = normal.cross(tan)
    t2 = tan * math.cos(tilt) + bit * math.sin(tilt)
    b2 = -tan * math.sin(tilt) + bit * math.cos(tilt)
    tip   = center + t2 * (length * 0.62)
    baseP = center - t2 * (length * 0.38)
    left  = center + b2 * (width * 0.5) - t2 * (length * 0.04)
    right = center - b2 * (width * 0.5) - t2 * (length * 0.04)
    for order in ((baseP, left, tip, right), (baseP, right, tip, left)):
        verts = [bm.verts.new(p) for p in order]
        face = bm.faces.new(verts)
        for loop in face.loops:
            loop[layer] = rgba


# ═══════════════════════════════════════════════════════════════════
# Charpente récursive (TRUNK_MODE="cartoon")
# ═══════════════════════════════════════════════════════════════════
def _add_tube(bm, layer, p0, p1, r0, r1):
    axis = (p1 - p0)
    if axis.length < 1e-5:
        return
    axis = axis.normalized()
    u, v = _perp_basis(axis)
    ring0, ring1 = [], []
    for s in range(TUBE_SEGMENTS):
        ang = (s / TUBE_SEGMENTS) * math.tau
        d = u * math.cos(ang) + v * math.sin(ang)
        ring0.append(bm.verts.new(p0 + d * r0))
        ring1.append(bm.verts.new(p1 + d * r1))
    for s in range(TUBE_SEGMENTS):
        s2 = (s + 1) % TUBE_SEGMENTS
        face = bm.faces.new((ring0[s], ring0[s2], ring1[s2], ring1[s]))
        for loop in face.loops:
            loop[layer] = _bark_color(loop.vert.co.z)


def _grow(bm, layer, rng, start, direction, length, radius, level, segments):
    down = mathutils.Vector((0, 0, -1))
    terminal = level <= 0
    if terminal and TERMINAL_DROOP > 0:
        direction = direction.lerp(down, TERMINAL_DROOP).normalized()
        length *= TERMINAL_LEN_MULT
        radius *= TERMINAL_RADIUS_MULT
    end = start + direction * length
    _add_tube(bm, layer, start, end, radius, radius * RADIUS_FALLOFF)
    segments.append({"p0": start.copy(), "p1": end.copy(), "level": level, "terminal": terminal})
    if terminal:
        return

    n = rng.randint(CHILDREN_MIN, CHILDREN_MAX)
    up = mathutils.Vector((0, 0, 1))
    u, v = _perp_basis(direction)
    for i in range(n):
        base_ang = (i / n) * math.tau + rng.uniform(-0.4, 0.4)
        side = u * math.cos(base_ang) + v * math.sin(base_ang)
        child = direction * math.cos(SPREAD_ANGLE) + side * math.sin(SPREAD_ANGLE)
        child = child.lerp(up, UP_BIAS)
        child += down * GRAVITY
        child += mathutils.Vector((rng.uniform(-BEND_JITTER, BEND_JITTER),
                                   rng.uniform(-BEND_JITTER, BEND_JITTER),
                                   rng.uniform(-BEND_JITTER * 0.5, BEND_JITTER)))
        child = child.normalized()
        _grow(bm, layer, rng, end, child, length * LENGTH_FALLOFF,
              radius * RADIUS_FALLOFF, level - 1, segments)


def build_branches(rng):
    mesh = bpy.data.meshes.new("branches_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    segments = []

    base = mathutils.Vector((0, 0, 0))
    tilt = mathutils.Vector((rng.uniform(-TRUNK_TILT, TRUNK_TILT),
                             rng.uniform(-TRUNK_TILT, TRUNK_TILT), 1)).normalized()
    trunk_top = base + tilt * TRUNK_HEIGHT
    _add_tube(bm, layer, base, trunk_top, TRUNK_RADIUS, TRUNK_RADIUS * 0.8)

    n = rng.randint(CHILDREN_MIN, CHILDREN_MAX)
    up = mathutils.Vector((0, 0, 1))
    u, v = _perp_basis(tilt)
    for i in range(n):
        base_ang = (i / n) * math.tau + rng.uniform(-0.3, 0.3)
        side = u * math.cos(base_ang) + v * math.sin(base_ang)
        child = tilt * math.cos(SPREAD_ANGLE) + side * math.sin(SPREAD_ANGLE)
        child = child.lerp(up, UP_BIAS * 0.6)
        child = child.normalized()
        _grow(bm, layer, rng, trunk_top, child, FIRST_LEN,
              TRUNK_RADIUS * 0.72, BRANCH_LEVELS - 1, segments)

    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Branches")
    obj.data.materials.append(_material("CT_Bark", COLOR_BARK_LIGHT))
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_TRUNK
    return obj, segments


# ═══════════════════════════════════════════════════════════════════
# Feuillage
# ═══════════════════════════════════════════════════════════════════
def _foliage_material(name):
    obj_mat = _material(name, COLOR_LEAF, double_sided=(FOLIAGE_MODE == "along"))
    return obj_mat


def build_foliage(rng, segments):
    mesh = bpy.data.meshes.new("foliage_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    dark  = tuple(max(0.0, c * (1.0 - LEAF_COLOR_VAR)) for c in COLOR_LEAF[:3])
    light = tuple(min(1.0, c * (1.0 + LEAF_COLOR_VAR)) for c in COLOR_LEAF[:3])

    if FOLIAGE_MODE == "clumps":
        sites = []
        for seg in segments:
            if seg["terminal"]:
                if rng.random() <= CLUMP_KEEP_CHANCE:
                    sites.append((seg["p1"], rng.uniform(CLUMP_RADIUS_MIN, CLUMP_RADIUS_MAX)))
            elif rng.random() < CLUMP_ON_NONTERMINAL:
                sites.append((seg["p1"], rng.uniform(CLUMP_RADIUS_MIN, CLUMP_RADIUS_MAX) * 0.6))
        for center, radius in sites:
            c = mathutils.Vector(center)
            blob = bmesh.new()
            bmesh.ops.create_icosphere(blob, subdivisions=CLUMP_SUBDIV, radius=radius)
            for bv in blob.verts:
                bv.co.z *= CLUMP_SQUASH
                nn = _noise(bv.co.x + c.x, bv.co.y + c.y, bv.co.z + c.z, 6.0, SEED)
                bv.co += bv.co.normalized() * (nn * CLUMP_BUMP * radius)
            bmesh.ops.translate(blob, verts=blob.verts, vec=c)
            tmp = bpy.data.meshes.new("tmp_clump")
            blob.to_mesh(tmp)
            blob.free()
            before = len(bm.faces)
            bm.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
            bm.faces.ensure_lookup_table()
            for face in list(bm.faces)[before:]:
                for loop in face.loops:
                    loop[layer] = _leaf_mottle(loop.vert.co, COLOR_LEAF)
            n_leaves = max(6, int(LEAVES_PER_CLUMP * (radius / CLUMP_RADIUS_MAX)))
            for _ in range(n_leaves):
                nrm = mathutils.Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
                if nrm.length < 1e-4:
                    continue
                nrm.normalize()
                pos = c + mathutils.Vector((nrm.x, nrm.y, nrm.z * CLUMP_SQUASH)) * radius
                pos += nrm * (LEAF_PUSH * radius)
                t = rng.uniform(0.0, 1.0)
                col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3)) + (1.0,)
                ln = rng.uniform(LEAF_LEN_MIN, LEAF_LEN_MAX)
                _add_leaf_card(bm, layer, pos, nrm, ln, ln * LEAF_WIDTH_RATIO,
                               rng.uniform(-LEAF_TILT, LEAF_TILT), col)

    elif FOLIAGE_MODE == "along":
        for seg in segments:
            if not seg["terminal"]:
                continue
            p0, p1 = mathutils.Vector(seg["p0"]), mathutils.Vector(seg["p1"])
            axis = (p1 - p0)
            perp = _perp_basis(axis.normalized() if axis.length > 1e-4 else mathutils.Vector((0, 0, 1)))[0]
            for _ in range(ALONG_LEAVES_PER_SEG):
                t = rng.uniform(0.15, 1.0)
                pos = p0 + axis * t
                tt = rng.uniform(0.0, 1.0)
                col = tuple(dark[i] + (light[i] - dark[i]) * tt for i in range(3)) + (1.0,)
                ln = rng.uniform(ALONG_LEAF_LEN_MIN, ALONG_LEAF_LEN_MAX)
                _add_leaf_card(bm, layer, pos, perp, ln, ln * ALONG_LEAF_WIDTH_RATIO,
                               rng.uniform(-0.6, 0.6), col)

    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Foliage")
    obj.data.materials.append(_foliage_material("CT_Leaves"))
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_FOLIAGE
    return obj


# ═══════════════════════════════════════════════════════════════════
# Tronc simple (pour sapin / palmier)
# ═══════════════════════════════════════════════════════════════════
def build_simple_trunk(rng, height, r_base, r_top, flare=1.3):
    mesh = bpy.data.meshes.new("trunk_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    rings = []
    RN, SEG = 8, 14
    for ri in range(RN + 1):
        t = ri / RN
        z = t * height
        radius = r_base + (r_top - r_base) * t
        if t < 0.16:
            radius *= 1.0 + (0.16 - t) / 0.16 * (flare - 1.0)
        dx = math.sin(t * 1.0 + SEED) * 0.22 * TRUNK_TILT * t * height
        dy = math.cos(t * 1.0 + SEED) * 0.22 * TRUNK_TILT * t * height
        ring = []
        for s in range(SEG):
            ang = (s / SEG) * math.tau
            ring.append(bm.verts.new((dx + math.cos(ang) * radius, dy + math.sin(ang) * radius, z)))
        rings.append(ring)
    for r in range(RN):
        a, b = rings[r], rings[r + 1]
        for s in range(SEG):
            s2 = (s + 1) % SEG
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    bm.faces.new(reversed(rings[0]))
    bm.faces.new(rings[-1])
    for face in bm.faces:
        for loop in face.loops:
            loop[layer] = _bark_color(loop.vert.co.z)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Trunk")
    obj.data.materials.append(_material("CT_Bark", COLOR_BARK_LIGHT))
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# ═══════════════════════════════════════════════════════════════════
# Sapin (étages de cônes)
# ═══════════════════════════════════════════════════════════════════
def build_pine_canopy(rng):
    mesh = bpy.data.meshes.new("pine_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    base_z = PINE_TRUNK_HEIGHT * 0.4
    step = PINE_LAYER_HEIGHT * (1.0 - PINE_OVERLAP)
    for i in range(PINE_LAYER_COUNT):
        t = i / max(1, PINE_LAYER_COUNT - 1)
        radius = PINE_BASE_RADIUS + (PINE_TOP_RADIUS - PINE_BASE_RADIUS) * t
        z = base_z + i * step
        cone = bmesh.new()
        bmesh.ops.create_cone(cone, cap_ends=True, segments=PINE_SEGMENTS,
                              radius1=radius, radius2=radius * 0.12, depth=PINE_LAYER_HEIGHT)
        bmesh.ops.translate(cone, verts=cone.verts, vec=(0, 0, z + PINE_LAYER_HEIGHT * 0.5))
        for cv in cone.verts:
            rxy = math.hypot(cv.co.x, cv.co.y)
            if rxy > 0.001:
                jit = 1.0 + rng.uniform(-PINE_JAG, PINE_JAG)
                cv.co.x *= jit
                cv.co.y *= jit
        tmp = bpy.data.meshes.new("tmp_pine")
        cone.to_mesh(tmp)
        cone.free()
        before = len(bm.faces)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        bm.faces.ensure_lookup_table()
        for face in list(bm.faces)[before:]:
            for loop in face.loops:
                loop[layer] = _leaf_mottle(loop.vert.co, COLOR_LEAF)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Pine")
    obj.data.materials.append(_material("CT_Leaves", COLOR_LEAF))
    for poly in obj.data.polygons:
        poly.use_smooth = SMOOTH_FOLIAGE
    return obj


# ═══════════════════════════════════════════════════════════════════
# Palmier (palmes rayonnantes)
# ═══════════════════════════════════════════════════════════════════
def _build_frond(bm, layer, rng, top):
    yaw = rng.uniform(0, math.tau)
    outward = mathutils.Vector((math.cos(yaw), math.sin(yaw), 0.0))
    perp = mathutils.Vector((-outward.y, outward.x, 0.0))
    length = rng.uniform(PALM_FROND_LEN_MIN, PALM_FROND_LEN_MAX)
    amp = rng.uniform(PALM_FROND_AMP_MIN, PALM_FROND_AMP_MAX)
    w0 = PALM_FROND_SPINE_W * rng.uniform(0.85, 1.15)

    def pt(t):
        z = amp * math.sin(t * math.pi * PALM_FROND_ARC_K)
        return top + outward * (length * t) + mathutils.Vector((0, 0, z))

    rings = []
    for i in range(PALM_FROND_SEGMENTS + 1):
        t = i / PALM_FROND_SEGMENTS
        c = pt(t)
        hw = w0 * 0.5 * (1.0 - 0.7 * t)
        rings.append((bm.verts.new(c + perp * hw), bm.verts.new(c - perp * hw)))
    for i in range(PALM_FROND_SEGMENTS):
        l0, r0 = rings[i]
        l1, r1 = rings[i + 1]
        face = bm.faces.new((l0, r0, r1, l1))
        for loop in face.loops:
            loop[layer] = COLOR_LEAF
    dark  = tuple(max(0.0, c * 0.85) for c in COLOR_LEAF[:3])
    light = tuple(min(1.0, c * 1.15) for c in COLOR_LEAF[:3])
    for side in (1.0, -1.0):
        for i in range(PALM_LEAFLETS_PER_SIDE):
            t = 0.12 + (i / max(1, PALM_LEAFLETS_PER_SIDE - 1)) * 0.82
            pos = pt(t)
            shrink = 1.0 - t * 0.55
            ll = rng.uniform(PALM_LEAFLET_LEN_MIN, PALM_LEAFLET_LEN_MAX) * shrink
            tt = rng.uniform(0.0, 1.0)
            col = tuple(dark[j] + (light[j] - dark[j]) * tt for j in range(3)) + (1.0,)
            tilt = (math.pi * 0.5) * side + rng.uniform(-0.25, 0.25)
            _add_leaf_card(bm, layer, pos, perp, ll, ll * PALM_LEAFLET_W_RATIO, tilt, col)


def build_palm_crown(rng):
    mesh = bpy.data.meshes.new("palm_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    top = mathutils.Vector((0, 0, PALM_TRUNK_HEIGHT))
    for _ in range(PALM_FROND_COUNT):
        _build_frond(bm, layer, rng, top)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Palm")
    obj.data.materials.append(_material("CT_Leaves", COLOR_LEAF, double_sided=True))
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


# ═══════════════════════════════════════════════════════════════════
# Pétales au sol (sakura)
# ═══════════════════════════════════════════════════════════════════
def build_ground_petals(rng):
    mesh = bpy.data.meshes.new("petals_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    dark  = tuple(max(0.0, c * 0.85) for c in COLOR_LEAF[:3])
    light = tuple(min(1.0, c * 1.10) for c in COLOR_LEAF[:3])
    for _ in range(GROUND_PETAL_COUNT):
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(GROUND_PETAL_RADIUS_MIN, GROUND_PETAL_RADIUS_MAX)
        pos = mathutils.Vector((math.cos(ang) * r, math.sin(ang) * r, 0.012))
        nrm = mathutils.Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1)).normalized()
        t = rng.uniform(0.0, 1.0)
        col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3)) + (1.0,)
        ln = rng.uniform(0.05, 0.09)
        _add_leaf_card(bm, layer, pos, nrm, ln, ln * 0.75, rng.uniform(0, math.tau), col)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "CT_Petals")
    obj.data.materials.append(_material("CT_Leaves", COLOR_LEAF))
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


# ═══════════════════════════════════════════════════════════════════
def main():
    global TRUNK_HEIGHT
    rng = random.Random(SEED)
    parts = []

    if TRUNK_MODE == "pine":
        TRUNK_HEIGHT = PINE_TRUNK_HEIGHT
        parts.append(build_simple_trunk(rng, PINE_TRUNK_HEIGHT, 0.12, 0.06, flare=1.4))
        parts.append(build_pine_canopy(rng))
        name = "Pine"
    elif TRUNK_MODE == "palm":
        TRUNK_HEIGHT = PALM_TRUNK_HEIGHT
        parts.append(build_simple_trunk(rng, PALM_TRUNK_HEIGHT, PALM_TRUNK_RADIUS,
                                        PALM_TRUNK_RADIUS * 0.8, flare=1.2))
        parts.append(build_palm_crown(rng))
        name = "Palm"
    else:
        branches, segments = build_branches(rng)
        parts.append(branches)
        if FOLIAGE_MODE != "none":
            parts.append(build_foliage(rng, segments))
        if GROUND_PETALS:
            parts.append(build_ground_petals(rng))
        name = {"clumps": "CartoonTree", "along": "Willow", "none": "DeadTree"}[FOLIAGE_MODE]

    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    parts[0].name = f"CT_{PRESET}"

    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    print(f"{parts[0].name} généré (SEED={SEED}, PRESET={PRESET}). "
          f"Material Preview (Z) puis export glTF 2.0.")


main()
