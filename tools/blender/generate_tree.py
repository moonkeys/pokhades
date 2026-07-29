"""
Générateur d'arbres low-poly (style Kenney Nature Kit — cf.
assets/kenney_nature_kit/ déjà utilisé par KitProps.gd) : tronc conique
facetté partagé par tous les types + feuillage spécifique au type choisi.
Couleurs volontairement NEUTRES/moyennes — la saturation par biome se
règle plus tard côté moteur (Environment.adjustment_saturation dans
BiomeAmbiance.gd), pas ici.

UTILISATION (dans Blender, PAS en ligne de commande) :
  1. Ouvre Blender → onglet "Scripting" (en haut).
  2. Supprime le cube par défaut de la scène (clic dessus, Suppr).
  3. Nouveau texte → colle tout ce fichier.
  4. Change la ligne PRESET juste en dessous (voir la liste des presets).
  5. Bouton ▶ "Run Script" (ou Alt+P).
  6. L'arbre apparaît à l'origine. Vue 3D en mode "Material Preview"
     (3e boule en haut à droite du viewport, ou touche Z) pour voir les
     couleurs.
  7. Sélectionne-le → File > Export > glTF 2.0 (.glb), coche
     "Selected Objects".

Relance le script avec une SEED différente pour une nouvelle silhouette DU
MÊME preset (ne change pas l'espèce, juste la forme précise).

Tout ce qu'il y a sous "Réglages avancés" reste modifiable si tu veux
affiner un preset en particulier (plus de branches, feuillage plus
dense…) — mais PRESET seul suffit pour changer d'espèce sans rien casser.
"""

import bpy
import bmesh
import random
import math
import mathutils

# ═══════════════════════════════════════════════════════════════════
# ⭐ LE SEUL RÉGLAGE À CONNAÎTRE : CHOISIS UN PRESET ICI ⭐
# ═══════════════════════════════════════════════════════════════════
SEED   = 11      # change ce nombre pour une nouvelle silhouette du même preset
PRESET = "oak"   # "oak" (arbre classique) / "oak_clumped" (touffes séparées) /
                 # "dead_oak" (arbre mort) / "pine" (sapin) / "sakura" /
                 # "willow" (saule pleureur) / "bonsai" (géant) / "palm" (palmier)

_PRESETS = {
    "oak":         {"TREE_TYPE": "classic", "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
    "oak_clumped": {"TREE_TYPE": "classic", "CLASSIC_VARIANT": "clumped", "HAS_FOLIAGE": True},
    "dead_oak":    {"TREE_TYPE": "classic", "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": False},
    "pine":        {"TREE_TYPE": "pine",    "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
    "sakura":      {"TREE_TYPE": "sakura",  "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
    "willow":      {"TREE_TYPE": "willow",  "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
    "bonsai":      {"TREE_TYPE": "bonsai",  "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
    "palm":        {"TREE_TYPE": "palm",    "CLASSIC_VARIANT": "round",   "HAS_FOLIAGE": True},
}
if PRESET not in _PRESETS:
    raise ValueError(f"PRESET inconnu : {PRESET!r}. Choix possibles : {sorted(_PRESETS)}")

# ─────────────────────────────────────────────────────────────────
# Réglages avancés — déjà couverts par le preset ci-dessus, à toucher
# seulement pour affiner (plus de branches, feuillage plus dense…).
# ─────────────────────────────────────────────────────────────────
HAS_FOLIAGE    = True        # False = arbre mort : tronc + branches nues, pas de feuillage
TREE_TYPE      = "classic"   # "classic" / "pine" / "sakura" / "willow" / "bonsai" / "palm"
CLASSIC_VARIANT = "round"    # pour TREE_TYPE="classic"/"sakura" — "round" (masse compacte)
                              # / "clumped" (touffes séparées reliées par des branches visibles)

globals().update(_PRESETS[PRESET])   # applique le preset — DOIT rester après les 3 lignes ci-dessus

TRUNK_HEIGHT   = 1.3
TRUNK_RADIUS   = 0.12
CANOPY_HEIGHT  = 1.05        # centre du feuillage au-dessus du sol
CANOPY_RADIUS  = 0.62

# ── Sapin (TREE_TYPE="pine") — étages de cônes empilés ────────────────
PINE_LAYER_COUNT   = 5
PINE_LAYER_HEIGHT  = 0.36
PINE_BASE_RADIUS   = 0.50
PINE_TOP_RADIUS    = 0.09     # rayon du sommet — presque une pointe
PINE_LAYER_OVERLAP = 0.38     # chevauchement vertical entre étages (0-1 de la hauteur)
PINE_JAG           = 0.10     # irrégularité du bord (silhouette en dents, façon aiguilles)
PINE_SEGMENTS      = 10
PINE_TRUNK_HEIGHT  = 0.42     # tronc court : juste un "pied" qui dépasse en bas —
                               # avec TRUNK_HEIGHT normal, le sommet fin des cônes
                               # devient plus étroit que le tronc avant sa pointe
COLOR_PINE = (0.14, 0.30, 0.19, 1.0)   # vert sapin — plus sombre/bleuté que COLOR_LEAVES

# Variante "clumped" — remplace certains réglages branches/touffes ci-dessous
# (bloc appliqué après leur définition, voir plus bas).

# ── Niveau de détail / rendu low-poly vs plus lisse ──────────────────
# SMOOTH_SHADING lisse les normales (fini les facettes plates visibles) ;
# les *_SEGMENTS/_SUBDIV augmentent la résolution du maillage — les deux
# ensemble donnent un rendu beaucoup moins "low poly", plus détaillé.
SMOOTH_SHADING  = True        # tronc/branches — surface lisse, sans facettes
CANOPY_SMOOTH_SHADING = False # feuillage — RESTE facetté : le lissage efface
                               # le relief des bosses (LEAF_BUMP), qui ne se
                               # verrait plus du tout sinon
TRUNK_SEGMENTS  = 16          # côtés du tronc (était 7 en low-poly)
BRANCH_SEGMENTS = 8           # côtés des branches (était 5)
CANOPY_SUBDIV   = 3           # subdivisions des sphères de feuillage — assez
                               # de sommets pour LEAF_BUMP sans faire exploser
                               # le poids du fichier (le feuillage étant
                               # facetté, chaque face duplique ses sommets)
TUFT_SUBDIV     = 2           # subdivisions des petites touffes

# ── Feuilles individuelles plaquées sur le feuillage ─────────────────
# Le bosselage (LEAF_BUMP) seul reste "une boule de polygones" — ce sont
# ces petites feuilles en losange, dispersées sur la surface et inclinées
# aléatoirement, qui cassent vraiment la silhouette ronde et donnent
# l'impression de vraies feuilles plutôt que de la géométrie abstraite.
LEAF_CARD_ENABLED    = True
LEAF_CARD_COUNT      = 260     # nombre de feuilles individuelles
LEAF_CARD_LEN_MIN    = 0.09
LEAF_CARD_LEN_MAX    = 0.16
LEAF_CARD_WIDTH_RATIO = 0.5    # largeur = longueur × ce ratio
LEAF_CARD_TILT       = 0.6     # inclinaison aléatoire max autour de la normale (rad)
LEAF_CARD_PUSH       = 0.07    # décalage vers l'extérieur ×CANOPY_RADIUS — doit
                                # dépasser LEAF_BUMP_AMOUNT pour rester au-dessus
                                # de la surface bosselée, pas s'y enfoncer
LEAF_CARD_COLOR_VAR  = 0.15    # variation de teinte aléatoire, feuille par feuille

# ── Touffes de feuilles sur les branches (en plus du feuillage central) ──
# Rapprochées du feuillage central (BRANCH_TUFT_PULL) pour FUSIONNER dedans
# au lieu de flotter en boules séparées façon amas de ballons — et une seule
# touffe pour une branche sur deux environ (BRANCH_TUFT_CHANCE), sinon trop
# de sphères qui se chevauchent = silhouette illisible en "chou-fleur".
BRANCH_TUFT_CHANCE     = 0.5    # probabilité qu'une branche donnée ait une touffe
BRANCH_TUFT_RADIUS_MIN = 0.16
BRANCH_TUFT_RADIUS_MAX = 0.22
BRANCH_TUFT_JITTER     = 0.03   # décalage aléatoire autour de la pointe
BRANCH_TUFT_PULL       = 0.70   # 0 = à la pointe exacte, 1 = au centre du feuillage

# Sans feuillage, les branches nues doivent porter la silhouette à elles
# seules — on les allonge pour que ça ne fasse pas "moignons".
BRANCH_DEAD_LEN_MULT = 1.7

# ── Tronc — détail ──────────────────────────────────────────────
TRUNK_RING_COUNT  = 8        # nb d'anneaux empilés (plus = plus de relief)
TRUNK_BARK_JITTER = 0.022    # amplitude du "bosselage" écorce par anneau
TRUNK_FLARE       = 1.35     # évasement de la base (racines), ×TRUNK_RADIUS
TRUNK_KNOT_COUNT  = 2        # petits nœuds/bosses sur l'écorce
TRUNK_BEND_AMOUNT = 0.03     # cambrage du tronc — faible par défaut (arbre
                              # droit) ; le bonsaï monte ça fort pour un
                              # tronc noueux/tordu (cf. bloc BONSAI plus bas)
TRUNK_BEND_FREQ   = 2.4      # fréquence de l'oscillation du cambrage

# ── Branches — entièrement paramétrable ─────────────────────────
BRANCH_COUNT      = 7        # nombre de branches qui plongent dans le feuillage
BRANCH_START_MIN  = 0.50     # ratio de TRUNK_HEIGHT : plage de hauteur d'attache
BRANCH_START_MAX  = 0.88
BRANCH_TILT_MIN   = 0.40     # angle depuis la verticale (rad) — 0 = tout droit
BRANCH_TILT_MAX   = 0.80
BRANCH_LEN_MIN    = 0.50     # courtes : seule la POINTE doit dépasser du feuillage
BRANCH_LEN_MAX    = 0.72
BRANCH_RADIUS_MIN = 0.03     # rayon à la base de la branche
BRANCH_RADIUS_MAX = 0.05

# ── Variante "clumped" : touffes séparées reliées par des branches bien
# visibles (façon 1ère image de référence), au lieu d'une masse compacte —
# remplace juste les réglages branches/touffes définis au-dessus. Pas de
# gros blob central : chaque branche PORTE sa propre touffe pleine taille.
if TREE_TYPE == "classic" and CLASSIC_VARIANT == "clumped":
    BRANCH_COUNT      = 6
    BRANCH_TILT_MIN    = 0.65
    BRANCH_TILT_MAX    = 1.15    # plus couché = touffes plus écartées du tronc
    BRANCH_LEN_MIN     = 0.85
    BRANCH_LEN_MAX     = 1.25    # branches nettement plus longues, bien visibles
    BRANCH_RADIUS_MIN  = 0.045
    BRANCH_RADIUS_MAX  = 0.075
    BRANCH_TUFT_CHANCE = 1.0     # TOUTES les branches ont leur touffe
    BRANCH_TUFT_PULL   = 0.05    # quasi à la pointe exacte — touffes bien séparées
    BRANCH_TUFT_JITTER = 0.02
    BRANCH_TUFT_RADIUS_MIN = 0.20   # plus petites : moins de chevauchement entre elles
    BRANCH_TUFT_RADIUS_MAX = 0.28

# ── Bonsaï géant (TREE_TYPE="bonsai") : tronc massif et TORDU (cambrage
# fort) + quelques branches épaisses et presque horizontales, chacune
# portant un coussin de feuillage APLATI (façon "nuage" de bonsaï), plus
# une petite touffe au sommet (apex). Surcharge tronc ET branches d'un
# coup, directement au niveau module (pas besoin de `global` dans main()).
if TREE_TYPE == "bonsai":
    TRUNK_HEIGHT      = 1.75    # nettement plus grand qu'un arbre classique (1.3)
    TRUNK_RADIUS       = 0.24    # quasi le double — un tronc massif
    TRUNK_FLARE        = 1.7
    TRUNK_KNOT_COUNT   = 4
    TRUNK_BEND_AMOUNT  = 0.55    # cambrage marqué — tronc noueux/tordu, pas droit
    TRUNK_BEND_FREQ    = 1.3     # basse fréquence = UNE courbe large, pas un zigzag

    BRANCH_COUNT       = 5
    BRANCH_START_MIN   = 0.32    # étagés sur une bonne partie du tronc
    BRANCH_START_MAX   = 0.85
    BRANCH_TILT_MIN    = 1.00    # presque à l'horizontale — silhouette étalée
    BRANCH_TILT_MAX    = 1.35
    BRANCH_LEN_MIN      = 0.95
    BRANCH_LEN_MAX      = 1.45
    BRANCH_RADIUS_MIN   = 0.075   # branches épaisses, pas des brindilles
    BRANCH_RADIUS_MAX   = 0.11

BONSAI_PAD_RADIUS_MIN = 0.36   # coussins de feuillage aplatis, au bout de chaque branche
BONSAI_PAD_RADIUS_MAX = 0.56
BONSAI_PAD_SQUASH     = 0.34   # écrase la sphère en "nuage" plat (1.0 = sphère normale)
BONSAI_APEX_RADIUS    = 0.30   # petite touffe sommitale, au-dessus du tronc
COLOR_BONSAI_LEAF = (0.22, 0.40, 0.20, 1.0)   # vert profond, plus sombre que COLOR_LEAVES

# ── Palmier (TREE_TYPE="palm") — tronc haut/fin à anneaux horizontaux
# (cicatrices de palmes tombées, PAS des stries verticales comme les autres
# arbres) surmonté d'une couronne de palmes qui rayonnent et retombent en
# arc, chacune "à plumes" (une nervure centrale + des folioles des deux
# côtés, comme le saule mais bien plus large/court et arqué).
if TREE_TYPE == "palm":
    TRUNK_HEIGHT      = 2.15    # nettement plus haut, palmiers = troncs élancés
    TRUNK_RADIUS       = 0.095   # fin par rapport à sa hauteur
    TRUNK_FLARE        = 1.15    # presque pas d'évasement — pas un tronc feuillu
    TRUNK_KNOT_COUNT   = 0       # pas de nœuds — l'anneau horizontal est le seul motif
    TRUNK_BEND_AMOUNT  = 0.22    # légère inclinaison, comme un vrai palmier
    TRUNK_BEND_FREQ    = 0.9     # basse fréquence = une seule courbe douce

PALM_RING_FREQ    = 14.0     # fréquence des anneaux horizontaux (cicatrices)
PALM_RING_NOISE   = 0.10
COLOR_PALM_TRUNK  = (0.42, 0.34, 0.22, 1.0)   # brun-gris, plus clair/terne que COLOR_TRUNK

PALM_FROND_COUNT      = 9
PALM_FROND_LEN_MIN    = 0.55
PALM_FROND_LEN_MAX    = 0.80
# z(t) = amplitude * sin(t·π·ARC_K) : monte puis retombe SOUS le point de
# départ (ARC_K > 1) — un seul paramètre par branche, plus simple/prévisible
# que rise+droop+tilt séparés (qui se contraient l'un l'autre et donnaient
# des palmes bien trop étirées/filiformes).
PALM_FROND_AMPLITUDE_MIN = 0.22
PALM_FROND_AMPLITUDE_MAX = 0.38
PALM_FROND_ARC_K      = 1.35
PALM_FROND_SEGMENTS   = 8
PALM_FROND_SPINE_WIDTH = 0.032

PALM_LEAFLETS_PER_SIDE = 7        # par côté de la nervure — donc ×2 par palme
PALM_LEAFLET_LEN_MIN   = 0.11
PALM_LEAFLET_LEN_MAX   = 0.17
PALM_LEAFLET_WIDTH_RATIO = 0.16   # très étroites — l'aspect "à plumes"
COLOR_PALM_FROND = (0.24, 0.48, 0.22, 1.0)   # vert tropical, assez saturé

# ── Texture d'écorce (couleurs de sommet — pas d'UV/image nécessaire) ──
BARK_TEXTURE     = True      # False = écorce unie, comme avant
BARK_STREAK_FREQ = 5.3       # nb de "stries" verticales autour du tronc
BARK_NOISE       = 0.16      # grain aléatoire par sommet (0 = stries pures)
BARK_DARK_MULT   = 0.68      # assombrit les creux des stries
BARK_LIGHT_MULT  = 1.30      # éclaircit les reliefs des stries

# ── Détail du feuillage : bosselage géométrique + mouchetures de couleur ──
# Sans ça, le feuillage n'est qu'une boule lisse même à haute subdivision —
# c'est ce bosselage qui donne l'impression de vrais amas de feuilles.
LEAF_BUMP_ENABLED = True
LEAF_BUMP_AMOUNT  = 0.09     # amplitude du bosselage, ×CANOPY_RADIUS — modéré
                              # maintenant que les feuilles individuelles
                              # (LEAF_CARD) portent l'essentiel du détail
LEAF_BUMP_FREQ    = 8.5      # + haut = bosses plus petites/nombreuses
LEAF_COLOR_MOTTLE = True     # mouchetures de teinte (clair/sombre) sur les feuilles
LEAF_MOTTLE_FREQ  = 3.2      # + bas = taches plus grandes
LEAF_DARK_MULT    = 0.78
LEAF_LIGHT_MULT   = 1.24

# Couleurs NEUTRES (ni trop ternes ni trop saturées) — la vivacité finale
# par biome vient de Environment.adjustment_saturation (cf. BiomeAmbiance),
# pas d'un ajustement à la main ici.
COLOR_TRUNK  = (0.32, 0.21, 0.13, 1.0)   # brun bois
COLOR_LEAVES = (0.32, 0.47, 0.21, 1.0)   # vert moyen

# ── Sakura (TREE_TYPE="sakura") — réutilise le squelette "classic", juste
# une palette rose/blanc à la place du vert + un tapis de pétales au sol.
COLOR_SAKURA_BLOSSOM = (0.93, 0.72, 0.80, 1.0)   # rose pâle — remplace COLOR_LEAVES
COLOR_SAKURA_TRUNK   = (0.26, 0.20, 0.18, 1.0)   # écorce plus grise, moins rousse
SAKURA_GROUND_PETALS = True
SAKURA_PETAL_COUNT   = 40
SAKURA_PETAL_RADIUS_MIN = 0.35   # rayon de dispersion autour du tronc, ×CANOPY_RADIUS
SAKURA_PETAL_RADIUS_MAX = 1.15
SAKURA_PETAL_LEN_MIN = 0.05
SAKURA_PETAL_LEN_MAX = 0.09

# ── Saule pleureur (TREE_TYPE="willow") — petite couronne haute d'où partent
# de nombreuses branches fines qui montent un peu puis retombent en cascade,
# avec des feuilles étroites disposées le long de leur longueur (pas juste
# à la pointe, comme les autres types).
WILLOW_CROWN_RADIUS = 0.42        # masse centrale — plus petite qu'un arbre classique
WILLOW_CROWN_HEIGHT = 1.05
WILLOW_CROWN_BLOB_COUNT = 3

WILLOW_BRANCH_COUNT = 22
WILLOW_REACH_MIN  = 0.20          # étalement horizontal avant de retomber
WILLOW_REACH_MAX  = 0.50
WILLOW_RISE       = 0.14          # légère montée avant la retombée
WILLOW_DROOP_MIN  = 0.85          # longueur de la chute — certaines frôlent le sol
WILLOW_DROOP_MAX  = 1.55
WILLOW_SEGMENTS   = 9
WILLOW_WIDTH      = 0.022

WILLOW_LEAVES_PER_BRANCH_MIN = 5
WILLOW_LEAVES_PER_BRANCH_MAX = 9
WILLOW_LEAF_LEN_MIN = 0.05
WILLOW_LEAF_LEN_MAX = 0.09
WILLOW_LEAF_WIDTH_RATIO = 0.28    # étroites/lancéolées, pas rondes
WILLOW_LEAF_TILT = 0.5
WILLOW_LEAF_COLOR_VAR = 0.15

COLOR_WILLOW_TWIG = (0.34, 0.36, 0.18, 1.0)   # brindille vert-brun, pas juste brune
COLOR_WILLOW_LEAF = (0.46, 0.56, 0.24, 1.0)   # vert-jaune, typique du saule


def _material(name: str, rgba: tuple, use_vertex_color: bool = False,
              double_sided: bool = False) -> "bpy.types.Material":
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    if double_sided:
        mat.use_backface_culling = False
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
        if use_vertex_color:
            # Lit les couleurs peintes par sommet (calque "Col", cf.
            # _paint_bark) plutôt qu'une teinte plate — c'est ce qui donne
            # de la texture sans avoir besoin d'UV ni d'image. Exporte
            # nativement en glTF (attribut COLOR_0), lu par Godot aussi.
            attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
            attr.layer_name = "Col"
            mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _cheap_noise3(x: float, y: float, z: float, freq: float, seed: float) -> float:
    """"Bruit" 3D pas cher (somme de sinus déphasés) — pas du vrai Perlin,
    mais continu dans l'espace et assez irrégulier pour du bosselage/des
    mouchetures. Retourne une valeur ~[-1, 1]."""
    return (
        math.sin(x * freq + seed) +
        math.sin(y * freq * 1.31 + seed * 1.7) +
        math.sin(z * freq * 0.77 + seed * 2.3) +
        math.sin((x + y) * freq * 0.53 + seed * 0.4) +
        math.sin((y - z) * freq * 0.61 + seed * 3.1)
    ) / 5.0


def _bump_leaves(bm: "bmesh.types.BMesh") -> None:
    """Déplace chaque sommet le long de sa normale selon le bruit — casse
    la sphère lisse en amas irréguliers façon vrais paquets de feuilles.
    Doit être appelé APRÈS que tous les blobs sont fusionnés dans bm."""
    if not LEAF_BUMP_ENABLED:
        return
    bm.normal_update()
    amount = LEAF_BUMP_AMOUNT * CANOPY_RADIUS
    for v in bm.verts:
        n = _cheap_noise3(v.co.x, v.co.y, v.co.z, LEAF_BUMP_FREQ, SEED)
        v.co += v.normal * (n * amount)
    bm.normal_update()


def _paint_leaves(bm: "bmesh.types.BMesh", base_rgba: tuple) -> None:
    """Mouchetures de teinte clair/sombre sur le feuillage — même principe
    que _paint_bark mais sans direction privilégiée (des taches, pas des
    stries), pour suggérer des paquets de feuilles distincts."""
    if not LEAF_COLOR_MOTTLE:
        return
    dark  = tuple(min(1.0, c * LEAF_DARK_MULT) for c in base_rgba[:3])
    light = tuple(min(1.0, c * LEAF_LIGHT_MULT) for c in base_rgba[:3])
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert.co
            n = _cheap_noise3(v.x, v.y, v.z, LEAF_MOTTLE_FREQ, SEED + 11)
            t = max(0.0, min(1.0, (n + 1.0) * 0.5))
            col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3))
            loop[layer] = (col[0], col[1], col[2], 1.0)


def _paint_bark(bm: "bmesh.types.BMesh", rng: random.Random, base_rgba: tuple) -> None:
    """Peint chaque sommet entre une teinte sombre et claire dérivées de
    base_rgba, en stries verticales autour de l'axe Z + un grain aléatoire —
    donne l'impression d'une écorce texturée sans image/UV."""
    if not BARK_TEXTURE:
        return
    dark  = tuple(min(1.0, c * BARK_DARK_MULT) for c in base_rgba[:3])
    light = tuple(min(1.0, c * BARK_LIGHT_MULT) for c in base_rgba[:3])
    layer = bm.loops.layers.color.new("Col")
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert.co
            ang = math.atan2(v.y, v.x)
            streak = 0.5 + 0.5 * math.sin(ang * BARK_STREAK_FREQ + v.z * 3.1)
            t = max(0.0, min(1.0, streak + rng.uniform(-BARK_NOISE, BARK_NOISE)))
            col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3))
            loop[layer] = (col[0], col[1], col[2], 1.0)


def _paint_palm_trunk(bm: "bmesh.types.BMesh", rng: random.Random, base_rgba: tuple) -> None:
    """Anneaux HORIZONTAUX (cicatrices de palmes tombées) plutôt que des
    stries verticales — la texture d'écorce des autres arbres ne
    conviendrait pas du tout à un palmier."""
    dark  = tuple(min(1.0, c * BARK_DARK_MULT) for c in base_rgba[:3])
    light = tuple(min(1.0, c * BARK_LIGHT_MULT) for c in base_rgba[:3])
    layer = bm.loops.layers.color.new("Col")
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert.co
            band = 0.5 + 0.5 * math.sin(v.z * PALM_RING_FREQ)
            t = max(0.0, min(1.0, band + rng.uniform(-PALM_RING_NOISE, PALM_RING_NOISE)))
            col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3))
            loop[layer] = (col[0], col[1], col[2], 1.0)


def _new_object(mesh: "bpy.types.Mesh", name: str) -> "bpy.types.Object":
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _apply_shading(obj: "bpy.types.Object", smooth: bool = SMOOTH_SHADING) -> None:
    for poly in obj.data.polygons:
        poly.use_smooth = smooth


def build_trunk(rng: random.Random) -> "bpy.types.Object":
    """Tronc construit anneau par anneau (plutôt qu'un simple cône) : chaque
    anneau a un rayon légèrement bosselé (TRUNK_BARK_JITTER) et une position
    XY qui dérive doucement — ça donne un tronc noueux/naturel au lieu d'un
    cône parfaitement lisse. La base s'évase (TRUNK_FLARE) façon racines."""
    mesh = bpy.data.meshes.new("trunk_mesh")
    bm = bmesh.new()
    segments = TRUNK_SEGMENTS

    rings: list[list["bmesh.types.BMVert"]] = []
    for ring_i in range(TRUNK_RING_COUNT + 1):
        t = ring_i / TRUNK_RING_COUNT               # 0 (base) → 1 (sommet)
        z = t * TRUNK_HEIGHT
        base_radius = TRUNK_RADIUS * (1.0 - 0.5 * t)  # se resserre vers le haut
        if t < 0.15:
            base_radius *= 1.0 + (0.15 - t) / 0.15 * (TRUNK_FLARE - 1.0)  # évasement racines
        drift_x = math.sin(t * TRUNK_BEND_FREQ + SEED) * TRUNK_BEND_AMOUNT * t
        drift_y = math.cos(t * TRUNK_BEND_FREQ + SEED) * TRUNK_BEND_AMOUNT * t

        ring_verts = []
        for s in range(segments):
            ang = (s / segments) * math.tau
            jitter = 1.0 + rng.uniform(-TRUNK_BARK_JITTER, TRUNK_BARK_JITTER)
            r = base_radius * jitter
            x = drift_x + math.cos(ang) * r
            y = drift_y + math.sin(ang) * r
            ring_verts.append(bm.verts.new((x, y, z)))
        rings.append(ring_verts)

    # Coud les anneaux successifs en quads.
    for r in range(TRUNK_RING_COUNT):
        a, b = rings[r], rings[r + 1]
        for s in range(segments):
            s2 = (s + 1) % segments
            bm.faces.new((a[s], a[s2], b[s2], b[s]))
    # Bouchons haut/bas.
    bm.faces.new(reversed(rings[0]))
    bm.faces.new(rings[-1])
    bm.normal_update()

    # Petits nœuds d'écorce : bosses locales (poussée radiale en XY
    # seulement — pousser aussi selon Z étirerait le nœud verticalement).
    for _ in range(TRUNK_KNOT_COUNT):
        ring = rings[rng.randint(1, TRUNK_RING_COUNT - 1)]
        v = ring[rng.randint(0, segments - 1)]
        xy_len = math.hypot(v.co.x, v.co.y)
        if xy_len > 0.0001:
            v.co.x += v.co.x / xy_len * 0.035
            v.co.y += v.co.y / xy_len * 0.035

    if TREE_TYPE == "palm":
        _paint_palm_trunk(bm, rng, COLOR_PALM_TRUNK)
    else:
        _paint_bark(bm, rng, COLOR_TRUNK)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Tree_Trunk")
    trunk_color = COLOR_PALM_TRUNK if TREE_TYPE == "palm" else COLOR_TRUNK
    obj.data.materials.append(_material("Tree_Bark", trunk_color, use_vertex_color=True))
    _apply_shading(obj)
    return obj


def _gen_branch_specs(rng: random.Random) -> list[dict]:
    """Tire UNE FOIS la géométrie de chaque branche (position, angle,
    longueur) — partagée entre build_branches() (le mesh) et build_canopy()
    (qui a besoin de la position des POINTES pour y poser des touffes)."""
    specs = []
    len_mult = 1.0 if HAS_FOLIAGE else BRANCH_DEAD_LEN_MULT
    for i in range(BRANCH_COUNT):
        specs.append({
            "start_z": TRUNK_HEIGHT * rng.uniform(BRANCH_START_MIN, BRANCH_START_MAX),
            "yaw":     rng.uniform(0, math.tau),
            "tilt":    rng.uniform(BRANCH_TILT_MIN, BRANCH_TILT_MAX),
            "length":  rng.uniform(BRANCH_LEN_MIN, BRANCH_LEN_MAX) * len_mult,
            "radius":  rng.uniform(BRANCH_RADIUS_MIN, BRANCH_RADIUS_MAX),
        })
    return specs


def _branch_tip(spec: dict) -> tuple:
    """Position monde de la pointe d'une branche (même rotation que dans
    build_branches, appliquée à un point local (0,0,length))."""
    length, tilt, yaw, start_z = spec["length"], spec["tilt"], spec["yaw"], spec["start_z"]
    y2 = -length * math.sin(tilt)
    z2 = length * math.cos(tilt)
    x3 = y2 * math.sin(yaw)
    y3 = y2 * math.cos(yaw)
    return (x3, y3, z2 + start_z)


def build_branches(specs: list[dict], rng: random.Random) -> "bpy.types.Object":
    """Branches fines qui partent du haut du tronc — leur pointe porte une
    touffe de feuillage (cf. build_canopy) quand HAS_FOLIAGE est actif,
    sinon elles restent nues (arbre mort)."""
    mesh = bpy.data.meshes.new("branches_mesh")
    bm = bmesh.new()
    for spec in specs:
        start_z, yaw, tilt, length = spec["start_z"], spec["yaw"], spec["tilt"], spec["length"]

        branch = bmesh.new()
        bmesh.ops.create_cone(
            branch, cap_ends=True, segments=BRANCH_SEGMENTS,
            radius1=spec["radius"], radius2=0.012,
            depth=length,
        )
        bmesh.ops.translate(branch, verts=branch.verts, vec=(0, 0, length * 0.5))
        # Oriente le long de (yaw, tilt) puis place la base sur le tronc.
        for v in branch.verts:
            x, y, z = v.co.x, v.co.y, v.co.z
            # rotation autour de X (tilt) puis Y (yaw)
            y2 = y * math.cos(tilt) - z * math.sin(tilt)
            z2 = y * math.sin(tilt) + z * math.cos(tilt)
            x3 = x * math.cos(yaw) + y2 * math.sin(yaw)
            y3 = -x * math.sin(yaw) + y2 * math.cos(yaw)
            v.co.x, v.co.y, v.co.z = x3, y3, z2 + start_z
        mesh_tmp = bpy.data.meshes.new("tmp_branch")
        branch.to_mesh(mesh_tmp)
        branch.free()
        bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
    _paint_bark(bm, rng, COLOR_TRUNK)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Tree_Branches")
    # Réutilise le matériau "Tree_Bark" déjà créé par build_trunk() (le
    # nœud de couleur par sommet y est déjà branché — pas besoin de le
    # recréer ici, ce serait un doublon sur le même matériau partagé).
    obj.data.materials.append(_material("Tree_Bark", COLOR_TRUNK))
    _apply_shading(obj)
    return obj


def _add_blob(bm: "bmesh.types.BMesh", center: tuple, radius: float,
               subdivisions: int = CANOPY_SUBDIV, squash_z: float = 1.0) -> None:
    """squash_z < 1.0 aplatit la sphère en "coussin"/nuage (cf. coussins de
    feuillage du bonsaï) — appliqué AVANT translate() donc autour du centre
    local de la sphère, pas autour de l'origine du monde."""
    blob = bmesh.new()
    bmesh.ops.create_icosphere(blob, subdivisions=subdivisions, radius=radius)
    if squash_z != 1.0:
        for v in blob.verts:
            v.co.z *= squash_z
    bmesh.ops.translate(blob, verts=blob.verts, vec=center)
    mesh_tmp = bpy.data.meshes.new("tmp")
    blob.to_mesh(mesh_tmp)
    blob.free()
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)


def _add_leaf_card(bm: "bmesh.types.BMesh", center: "mathutils.Vector", normal: "mathutils.Vector",
                    length: float, width: float, tilt: float, rgba: tuple) -> None:
    """Une "feuille" = un losange plat à 4 sommets, orienté face à `normal`
    avec une inclinaison aléatoire (`tilt`) autour de cet axe — pas une
    sphère de plus, une vraie silhouette de feuille qui dépasse. Créée en
    double face (endroit + envers) pour rester visible sous tous les angles."""
    normal = normal.normalized()
    arbitrary = mathutils.Vector((0, 0, 1)) if abs(normal.z) < 0.9 else mathutils.Vector((1, 0, 0))
    tangent = arbitrary.cross(normal).normalized()
    bitangent = normal.cross(tangent)
    t2 = tangent * math.cos(tilt) + bitangent * math.sin(tilt)
    b2 = -tangent * math.sin(tilt) + bitangent * math.cos(tilt)

    tip   = center + t2 * (length * 0.62)
    base  = center - t2 * (length * 0.38)
    left  = center + b2 * (width * 0.5) - t2 * (length * 0.04)
    right = center - b2 * (width * 0.5) - t2 * (length * 0.04)

    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for verts_order in ((base, left, tip, right), (base, right, tip, left)):
        verts = [bm.verts.new(v) for v in verts_order]
        face = bm.faces.new(verts)
        for loop in face.loops:
            loop[layer] = rgba


def _scatter_leaf_cards(bm: "bmesh.types.BMesh", rng: random.Random, blobs: list[dict]) -> None:
    """Disperse LEAF_CARD_COUNT feuilles sur la surface des sphères de
    feuillage déjà posées (`blobs` = [{"center","radius"}, ...]), au
    prorata de leur surface (radius²) pour une densité homogène."""
    if not LEAF_CARD_ENABLED or not blobs:
        return
    weights = [b["radius"] ** 2 for b in blobs]
    total_w = sum(weights)
    dark  = tuple(max(0.0, c * (1.0 - LEAF_CARD_COLOR_VAR)) for c in COLOR_LEAVES[:3])
    light = tuple(min(1.0, c * (1.0 + LEAF_CARD_COLOR_VAR)) for c in COLOR_LEAVES[:3])

    placed = 0
    attempts = 0
    max_attempts = LEAF_CARD_COUNT * 8
    while placed < LEAF_CARD_COUNT and attempts < max_attempts:
        attempts += 1
        r = rng.uniform(0, total_w)
        acc = 0.0
        blob = blobs[-1]
        for b, w in zip(blobs, weights):
            acc += w
            if r <= acc:
                blob = b
                break
        # Point aléatoire uniforme sur la sphère unité (méthode gaussienne).
        gx, gy, gz = rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)
        n = mathutils.Vector((gx, gy, gz))
        if n.length < 0.0001:
            continue
        n.normalize()
        surface = mathutils.Vector(blob["center"]) + n * blob["radius"]

        # Rejette les points ENTERRÉS dans le volume d'un AUTRE blob (les
        # sphères se chevauchent beaucoup, cf. build_canopy) — sinon la
        # moitié des feuilles se retrouvent planquées à l'intérieur de la
        # masse, invisibles, et la densité visible n'augmente presque plus
        # quand on monte LEAF_CARD_COUNT.
        hidden = False
        for other in blobs:
            if other is blob:
                continue
            if (surface - mathutils.Vector(other["center"])).length < other["radius"]:
                hidden = True
                break
        if hidden:
            continue

        pos = surface + n * (LEAF_CARD_PUSH * CANOPY_RADIUS)
        placed += 1
        t = rng.uniform(0.0, 1.0)
        col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3)) + (1.0,)
        length = rng.uniform(LEAF_CARD_LEN_MIN, LEAF_CARD_LEN_MAX)
        _add_leaf_card(
            bm, pos, n, length, length * LEAF_CARD_WIDTH_RATIO,
            rng.uniform(-LEAF_CARD_TILT, LEAF_CARD_TILT), col,
        )


def build_canopy(rng: random.Random, branch_specs: list[dict]) -> "bpy.types.Object":
    """Feuillage central (3 icosphères TRÈS imbriquées, façon tree_oak
    Kenney — une masse cohérente, pas des boules séparées) PLUS une touffe
    partiellement fondue dans cette masse à chaque pointe de branche, pour
    casser le contour sans faire "tas de ballons"."""
    canopy_center = (0.0, 0.0, CANOPY_HEIGHT)
    mesh = bpy.data.meshes.new("canopy_mesh")
    bm = bmesh.new()
    blob_specs: list[dict] = []   # {"center","radius"} — pour disperser les feuilles ensuite

    # Décalage FAIBLE (≪ le rayon) et rayons proches les uns des autres :
    # les sphères se recouvrent largement et fusionnent en une seule masse
    # à l'écran, au lieu de rester lisibles comme des boules distinctes.
    # En variante "clumped", pas de masse centrale du tout — les touffes de
    # branches (ci-dessous, pleine taille) constituent TOUT le feuillage.
    blob_count = 0 if CLASSIC_VARIANT == "clumped" else rng.randint(3, 4)
    for i in range(blob_count):
        offset = (
            rng.uniform(-0.10, 0.10),
            rng.uniform(-0.10, 0.10),
            CANOPY_HEIGHT + rng.uniform(-0.06, 0.10),
        )
        radius = CANOPY_RADIUS * rng.uniform(0.80, 0.98)
        _add_blob(bm, offset, radius)
        blob_specs.append({"center": offset, "radius": radius})

    # Touffes aux pointes d'UNE BRANCHE SUR DEUX environ, TIRÉES vers le
    # centre du feuillage (BRANCH_TUFT_PULL) : elles chevauchent la masse
    # centrale au lieu de flotter comme des bulles indépendantes, et ne
    # sont pas systématiques pour ne pas surcharger la silhouette.
    for spec in branch_specs:
        if rng.random() > BRANCH_TUFT_CHANCE:
            continue
        tip = _branch_tip(spec)
        pulled = tuple(
            tip[i] + (canopy_center[i] - tip[i]) * BRANCH_TUFT_PULL
            for i in range(3)
        )
        jitter = (
            rng.uniform(-BRANCH_TUFT_JITTER, BRANCH_TUFT_JITTER),
            rng.uniform(-BRANCH_TUFT_JITTER, BRANCH_TUFT_JITTER),
            rng.uniform(-BRANCH_TUFT_JITTER, BRANCH_TUFT_JITTER),
        )
        center = tuple(pulled[i] + jitter[i] for i in range(3))
        radius = rng.uniform(BRANCH_TUFT_RADIUS_MIN, BRANCH_TUFT_RADIUS_MAX)
        _add_blob(bm, center, radius, subdivisions=TUFT_SUBDIV)
        blob_specs.append({"center": center, "radius": radius})

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    _bump_leaves(bm)
    _paint_leaves(bm, COLOR_LEAVES)
    # Les feuilles individuelles viennent APRÈS le bosselage/la peinture de
    # la masse : elles sont indépendantes (couleur + position propres) et ne
    # doivent pas être aplaties par _bump_leaves.
    _scatter_leaf_cards(bm, rng, blob_specs)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Tree_Canopy")
    obj.data.materials.append(_material("Tree_Leaves", COLOR_LEAVES, use_vertex_color=LEAF_COLOR_MOTTLE))
    _apply_shading(obj, smooth=CANOPY_SMOOTH_SHADING)
    return obj


def build_pine_canopy(rng: random.Random) -> "bpy.types.Object":
    """Étages de cônes empilés avec chevauchement (façon sapin bas-poly) —
    bord de chaque étage légèrement irrégulier (PINE_JAG) pour évoquer des
    aiguilles plutôt qu'un cône parfaitement lisse."""
    mesh = bpy.data.meshes.new("pine_canopy_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    dark  = tuple(max(0.0, c * 0.75) for c in COLOR_PINE[:3])
    light = tuple(min(1.0, c * 1.25) for c in COLOR_PINE[:3])

    base_z = TRUNK_HEIGHT * 0.15   # le tronc dépasse un peu tout en bas
    step = PINE_LAYER_HEIGHT * (1.0 - PINE_LAYER_OVERLAP)
    for i in range(PINE_LAYER_COUNT):
        t = i / max(1, PINE_LAYER_COUNT - 1)
        radius = PINE_BASE_RADIUS + (PINE_TOP_RADIUS - PINE_BASE_RADIUS) * t
        z = base_z + i * step

        cone = bmesh.new()
        bmesh.ops.create_cone(
            cone, cap_ends=True, segments=PINE_SEGMENTS,
            radius1=radius, radius2=radius * 0.12, depth=PINE_LAYER_HEIGHT,
        )
        bmesh.ops.translate(cone, verts=cone.verts, vec=(0, 0, z + PINE_LAYER_HEIGHT * 0.5))
        # Bord irrégulier : jitter radial (autour de l'axe Z, pas en hauteur)
        # sur chaque anneau — casse la silhouette conique trop parfaite.
        for v in cone.verts:
            r_xy = math.hypot(v.co.x, v.co.y)
            if r_xy > 0.001:
                jit = 1.0 + rng.uniform(-PINE_JAG, PINE_JAG)
                v.co.x *= jit
                v.co.y *= jit

        mesh_tmp = bpy.data.meshes.new("tmp_pine")
        cone.to_mesh(mesh_tmp)
        cone.free()
        before = len(bm.faces)
        bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
        bm.faces.ensure_lookup_table()
        for face in list(bm.faces)[before:]:
            for loop_item in face.loops:
                v = loop_item.vert.co
                n = _cheap_noise3(v.x, v.y, v.z, 6.0, SEED + i * 7)
                tt = max(0.0, min(1.0, (n + 1.0) * 0.5))
                col = tuple(dark[j] + (light[j] - dark[j]) * tt for j in range(3)) + (1.0,)
                loop_item[layer] = col

    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Pine_Canopy")
    obj.data.materials.append(_material("Pine_Needles", COLOR_PINE, use_vertex_color=True))
    _apply_shading(obj, smooth=CANOPY_SMOOTH_SHADING)
    return obj


def _build_willow_branch(bm: "bmesh.types.BMesh", layer, rng: random.Random,
                          start: "mathutils.Vector") -> None:
    """Une branche fine qui part de `start`, s'étale un peu à l'horizontale
    en montant légèrement, puis retombe en cascade — et porte des feuilles
    étroites RÉPARTIES le long de sa longueur (pas juste une touffe au bout,
    comme les autres types d'arbre : c'est ce qui donne l'effet "rideau")."""
    yaw = rng.uniform(0, math.tau)
    outward = mathutils.Vector((math.cos(yaw), math.sin(yaw), 0.0))
    perp = mathutils.Vector((-outward.y, outward.x, 0.0))
    reach = rng.uniform(WILLOW_REACH_MIN, WILLOW_REACH_MAX)
    droop = rng.uniform(WILLOW_DROOP_MIN, WILLOW_DROOP_MAX)
    rise = WILLOW_RISE * rng.uniform(0.7, 1.3)
    width0 = WILLOW_WIDTH * rng.uniform(0.8, 1.2)

    def _point(t: float) -> "mathutils.Vector":
        horiz = reach * math.sqrt(t)                       # s'étale vite, puis droit
        z = rise * 4.0 * t * (1.0 - t) - droop * (t ** 1.8)  # monte un peu, retombe fort
        return start + outward * horiz + mathutils.Vector((0.0, 0.0, z))

    rings = []
    for i in range(WILLOW_SEGMENTS + 1):
        t = i / WILLOW_SEGMENTS
        center = _point(t)
        half_w = width0 * 0.5 * (1.0 - 0.5 * t)
        left  = bm.verts.new(center + perp * half_w)
        right = bm.verts.new(center - perp * half_w)
        rings.append((left, right))

    for i in range(WILLOW_SEGMENTS):
        l0, r0 = rings[i]
        l1, r1 = rings[i + 1]
        face = bm.faces.new((l0, r0, r1, l1))
        for loop_item in face.loops:
            loop_item[layer] = COLOR_WILLOW_TWIG

    dark  = tuple(max(0.0, c * (1.0 - WILLOW_LEAF_COLOR_VAR)) for c in COLOR_WILLOW_LEAF[:3])
    light = tuple(min(1.0, c * (1.0 + WILLOW_LEAF_COLOR_VAR)) for c in COLOR_WILLOW_LEAF[:3])
    n_leaves = rng.randint(WILLOW_LEAVES_PER_BRANCH_MIN, WILLOW_LEAVES_PER_BRANCH_MAX)
    for _ in range(n_leaves):
        t = rng.uniform(0.3, 1.0)   # pas de feuilles collées à l'attache
        pos = _point(t)
        tt = rng.uniform(0.0, 1.0)
        col = tuple(dark[i] + (light[i] - dark[i]) * tt for i in range(3)) + (1.0,)
        length = rng.uniform(WILLOW_LEAF_LEN_MIN, WILLOW_LEAF_LEN_MAX)
        _add_leaf_card(
            bm, pos, perp, length, length * WILLOW_LEAF_WIDTH_RATIO,
            rng.uniform(-WILLOW_LEAF_TILT, WILLOW_LEAF_TILT), col,
        )


def build_willow(rng: random.Random) -> "bpy.types.Object":
    """Petite couronne (masse de feuillage haute, cf. build_canopy en plus
    modeste) d'où partent toutes les branches retombantes — les points de
    départ sont tirés sur la surface de la couronne, comme les feuilles
    individuelles des autres types."""
    mesh = bpy.data.meshes.new("willow_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")

    crown_specs: list[dict] = []
    for i in range(WILLOW_CROWN_BLOB_COUNT):
        offset = (
            rng.uniform(-0.08, 0.08),
            rng.uniform(-0.08, 0.08),
            WILLOW_CROWN_HEIGHT + rng.uniform(-0.05, 0.08),
        )
        radius = WILLOW_CROWN_RADIUS * rng.uniform(0.80, 1.0)
        _add_blob(bm, offset, radius, subdivisions=CANOPY_SUBDIV)
        crown_specs.append({"center": offset, "radius": radius})

    # La couronne doit être peinte AVANT les branches (sinon ses faces
    # gardent la couleur de sommet par défaut = blanc, cf. bug de rendu
    # constaté) — _paint_leaves ne touche que les faces déjà présentes.
    _paint_leaves(bm, COLOR_WILLOW_LEAF)

    weights = [s["radius"] ** 2 for s in crown_specs]
    total_w = sum(weights)
    for _ in range(WILLOW_BRANCH_COUNT):
        r = rng.uniform(0, total_w)
        acc = 0.0
        chosen = crown_specs[-1]
        for s, w in zip(crown_specs, weights):
            acc += w
            if r <= acc:
                chosen = s
                break
        gx, gy, gz = rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)
        n = mathutils.Vector((gx, gy, gz))
        if n.length < 0.0001:
            continue
        n.normalize()
        if n.z < -0.2:            # les branches partent plutôt du dessus/des côtés
            n.z = -0.2
            n.normalize()
        start = mathutils.Vector(chosen["center"]) + n * chosen["radius"]
        _build_willow_branch(bm, layer, rng, start)

    # Pas de _bump_leaves ici : ça déplacerait aussi les sommets des fines
    # branches retombantes le long de leur normale, ce qui casserait leurs
    # courbes propres — contrairement au feuillage classique, le détail du
    # saule vient des branches/feuilles elles-mêmes, pas d'un bosselage de
    # surface.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Willow_Foliage")
    obj.data.materials.append(_material("Willow_Foliage", COLOR_WILLOW_LEAF,
                                         use_vertex_color=True, double_sided=True))
    _apply_shading(obj, smooth=CANOPY_SMOOTH_SHADING)
    return obj


def build_ground_petals(rng: random.Random) -> "bpy.types.Object":
    """Petit tapis de pétales tombés, dispersés en anneau autour du pied du
    tronc — juste posés à plat au sol (normale ~+Z, rotation aléatoire),
    même technique que les feuilles de la couronne (_add_leaf_card)."""
    mesh = bpy.data.meshes.new("ground_petals_mesh")
    bm = bmesh.new()
    dark  = tuple(max(0.0, c * 0.85) for c in COLOR_SAKURA_BLOSSOM[:3])
    light = tuple(min(1.0, c * 1.10) for c in COLOR_SAKURA_BLOSSOM[:3])
    for _ in range(SAKURA_PETAL_COUNT):
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(SAKURA_PETAL_RADIUS_MIN, SAKURA_PETAL_RADIUS_MAX) * CANOPY_RADIUS
        pos = mathutils.Vector((math.cos(ang) * r, math.sin(ang) * r, 0.012))
        normal = mathutils.Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1.0)).normalized()
        length = rng.uniform(SAKURA_PETAL_LEN_MIN, SAKURA_PETAL_LEN_MAX)
        t = rng.uniform(0.0, 1.0)
        col = tuple(dark[i] + (light[i] - dark[i]) * t for i in range(3)) + (1.0,)
        _add_leaf_card(bm, pos, normal, length, length * 0.75, rng.uniform(0, math.tau), col)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Sakura_Ground_Petals")
    obj.data.materials.append(_material("Sakura_Petals", COLOR_SAKURA_BLOSSOM, use_vertex_color=True))
    _apply_shading(obj, smooth=False)
    return obj


def build_bonsai_pads(rng: random.Random, branch_specs: list[dict]) -> "bpy.types.Object":
    """Un coussin de feuillage APLATI (squash_z) à la pointe de CHAQUE
    branche (façon "nuage" de bonsaï, en étages) + une petite touffe
    sommitale au-dessus du tronc. Pas de feuilles individuelles ici (la
    silhouette aplatie + le bosselage/mouchetures suffisent, même logique
    que le sapin) — les branches étant épaisses et peu nombreuses, le
    risque de "tas de ballons" est bien plus faible que pour un feuillage
    classique."""
    mesh = bpy.data.meshes.new("bonsai_pads_mesh")
    bm = bmesh.new()

    for spec in branch_specs:
        tip = _branch_tip(spec)
        jitter = (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), rng.uniform(-0.02, 0.02))
        center = tuple(tip[i] + jitter[i] for i in range(3))
        radius = rng.uniform(BONSAI_PAD_RADIUS_MIN, BONSAI_PAD_RADIUS_MAX)
        _add_blob(bm, center, radius, subdivisions=CANOPY_SUBDIV, squash_z=BONSAI_PAD_SQUASH)

    # Touffe sommitale, au-dessus du tronc — sans elle la silhouette a un
    # "trou" au sommet (toutes les branches partent plus bas, penchées).
    apex_center = (0.0, 0.0, TRUNK_HEIGHT * 1.02)
    _add_blob(bm, apex_center, BONSAI_APEX_RADIUS, subdivisions=CANOPY_SUBDIV, squash_z=BONSAI_PAD_SQUASH * 1.4)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    _bump_leaves(bm)
    _paint_leaves(bm, COLOR_BONSAI_LEAF)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Bonsai_Pads")
    obj.data.materials.append(_material("Bonsai_Foliage", COLOR_BONSAI_LEAF, use_vertex_color=True))
    _apply_shading(obj, smooth=CANOPY_SMOOTH_SHADING)
    return obj


def _build_palm_frond(bm: "bmesh.types.BMesh", layer, rng: random.Random,
                       top: "mathutils.Vector") -> None:
    """Une palme = une nervure centrale qui part du sommet du tronc, monte
    un peu puis retombe en arc (même principe que les branches du saule),
    avec des folioles étroites de chaque côté de la nervure — c'est ce qui
    donne l'aspect "à plumes" caractéristique, pas juste une lame pleine."""
    yaw = rng.uniform(0, math.tau)
    outward = mathutils.Vector((math.cos(yaw), math.sin(yaw), 0.0))
    perp = mathutils.Vector((-outward.y, outward.x, 0.0))
    length = rng.uniform(PALM_FROND_LEN_MIN, PALM_FROND_LEN_MAX)
    amplitude = rng.uniform(PALM_FROND_AMPLITUDE_MIN, PALM_FROND_AMPLITUDE_MAX)
    width0 = PALM_FROND_SPINE_WIDTH * rng.uniform(0.85, 1.15)

    def _point(t: float) -> "mathutils.Vector":
        horiz = length * t
        z = amplitude * math.sin(t * math.pi * PALM_FROND_ARC_K)
        return top + outward * horiz + mathutils.Vector((0.0, 0.0, z))

    rings = []
    for i in range(PALM_FROND_SEGMENTS + 1):
        t = i / PALM_FROND_SEGMENTS
        center = _point(t)
        half_w = width0 * 0.5 * (1.0 - 0.7 * t)
        left  = bm.verts.new(center + perp * half_w)
        right = bm.verts.new(center - perp * half_w)
        rings.append((left, right))

    for i in range(PALM_FROND_SEGMENTS):
        l0, r0 = rings[i]
        l1, r1 = rings[i + 1]
        face = bm.faces.new((l0, r0, r1, l1))
        for loop_item in face.loops:
            loop_item[layer] = COLOR_PALM_FROND

    dark  = tuple(max(0.0, c * 0.85) for c in COLOR_PALM_FROND[:3])
    light = tuple(min(1.0, c * 1.15) for c in COLOR_PALM_FROND[:3])
    for side in (1.0, -1.0):
        for i in range(PALM_LEAFLETS_PER_SIDE):
            # pas de folioles tout au début (nervure encore nue) ni tout au bout
            t = 0.12 + (i / max(1, PALM_LEAFLETS_PER_SIDE - 1)) * 0.82
            pos = _point(t)
            shrink = 1.0 - t * 0.55        # folioles plus courtes vers la pointe
            leaf_len = rng.uniform(PALM_LEAFLET_LEN_MIN, PALM_LEAFLET_LEN_MAX) * shrink
            tt = rng.uniform(0.0, 1.0)
            col = tuple(dark[j] + (light[j] - dark[j]) * tt for j in range(3)) + (1.0,)
            tilt = (math.pi * 0.5) * side + rng.uniform(-0.25, 0.25)
            _add_leaf_card(
                bm, pos, perp, leaf_len, leaf_len * PALM_LEAFLET_WIDTH_RATIO,
                tilt, col,
            )


def build_palm_crown(rng: random.Random) -> "bpy.types.Object":
    """Couronne de palmes qui rayonnent depuis le sommet du tronc."""
    mesh = bpy.data.meshes.new("palm_crown_mesh")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    top = mathutils.Vector((0.0, 0.0, TRUNK_HEIGHT))
    for _ in range(PALM_FROND_COUNT):
        _build_palm_frond(bm, layer, rng, top)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Palm_Crown")
    obj.data.materials.append(_material("Palm_Fronds", COLOR_PALM_FROND,
                                         use_vertex_color=True, double_sided=True))
    _apply_shading(obj, smooth=False)   # facetté : des palmes lissées perdraient leur lecture
    return obj


def main() -> None:
    global TRUNK_HEIGHT, COLOR_TRUNK, COLOR_LEAVES
    rng = random.Random(SEED)

    if TREE_TYPE == "pine":
        TRUNK_HEIGHT = PINE_TRUNK_HEIGHT
    elif TREE_TYPE == "sakura":
        # Réutilise le squelette "classic" — seule la palette change.
        COLOR_TRUNK  = COLOR_SAKURA_TRUNK
        COLOR_LEAVES = COLOR_SAKURA_BLOSSOM

    trunk = build_trunk(rng)
    parts = [trunk]
    name = "Tree"

    if TREE_TYPE == "pine":
        # Pas de branches : les étages de cônes couvrent le tronc — les
        # branches façon feuillu n'ont aucun sens ici.
        parts.append(build_pine_canopy(rng))
        name = "Pine"
    elif TREE_TYPE == "willow":
        # Pas non plus le système branches/canopy classique : le saule a
        # sa propre couronne + cascade de branches retombantes.
        parts.append(build_willow(rng))
        name = "Willow"
    elif TREE_TYPE == "bonsai":
        # Réutilise build_branches (épaisses/horizontales via la surcharge
        # BONSAI plus haut) mais PAS build_canopy — les coussins aplatis de
        # build_bonsai_pads remplacent le feuillage classique.
        specs = _gen_branch_specs(rng)
        parts.append(build_branches(specs, rng))
        parts.append(build_bonsai_pads(rng, specs))
        name = "Bonsai"
    elif TREE_TYPE == "palm":
        # Pas de branches non plus : les palmes partent directement du
        # sommet du tronc.
        parts.append(build_palm_crown(rng))
        name = "Palm"
    else:
        specs = _gen_branch_specs(rng)
        parts.append(build_branches(specs, rng))
        if HAS_FOLIAGE:
            parts.append(build_canopy(rng, specs))
            name = "Tree" if CLASSIC_VARIANT == "round" else "Tree_Clumped"
            if TREE_TYPE == "sakura":
                name = "Sakura"
                if SAKURA_GROUND_PETALS:
                    parts.append(build_ground_petals(rng))
        else:
            name = "Tree_Dead"

    # Fusionne tout en UN SEUL objet — plus simple à exporter/instancier
    # dans Godot qu'une hiérarchie à plusieurs nœuds, même convention que
    # les .glb du Kenney Nature Kit.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.join()
    trunk.name = name

    # Origine à la base (0,0,0) au sol — même convention que les props
    # Kenney (KitProps positionne tout depuis la base, jamais le centre).
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")

    if TREE_TYPE == "pine":
        total_h = TRUNK_HEIGHT + PINE_LAYER_HEIGHT * PINE_LAYER_COUNT * (1.0 - PINE_LAYER_OVERLAP)
    elif TREE_TYPE == "willow":
        total_h = WILLOW_CROWN_HEIGHT + WILLOW_CROWN_RADIUS
    elif TREE_TYPE == "bonsai":
        total_h = TRUNK_HEIGHT * 1.02 + BONSAI_APEX_RADIUS * BONSAI_PAD_SQUASH * 1.4
    elif TREE_TYPE == "palm":
        total_h = TRUNK_HEIGHT + PALM_FROND_AMPLITUDE_MAX
    else:
        total_h = TRUNK_HEIGHT + (CANOPY_RADIUS * 0.9 if HAS_FOLIAGE else 0.4)
    print(f"{trunk.name} généré — hauteur ≈ {total_h:.2f} u (SEED={SEED}, TREE_TYPE={TREE_TYPE}). "
          f"Sélectionne-le puis File > Export > glTF 2.0 (.glb).")


main()
