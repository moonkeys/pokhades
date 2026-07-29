"""
Champignons luminescents (marqueur du gothique-lumineux, cf. tools/DA_bible.md
pilier 2). Un petit bouquet : pied sombre (couleur de sommet) + chapeau
ÉMISSIF cyan qui rayonne dans l'ombre. Réservé aux biomes tardifs/sombres
(marais, grotte).

Couleur signature CYAN = "le monde / la magie" (cf. DA).

UTILISATION : Blender > Scripting > coller > Run Script (Alt+P) > vue
"Rendered" (touche Z > Rendered) pour voir l'émission > export glTF 2.0.

En jeu (Godot) : le chapeau garde son matériau émissif ; le glow du
WorldEnvironment le fait "rayonner". Change SEED pour varier.
"""

import bpy
import bmesh
import random
import math
import mathutils

SEED = 3

CLUSTER_COUNT   = 6
CLUSTER_SPREAD  = 0.19        # rayon de dispersion des pieds

STEM_H_MIN      = 0.11
STEM_H_MAX      = 0.30
STEM_RADIUS     = 0.017
STEM_SEGMENTS   = 3
STEM_BEND       = 0.05

CAP_R_MIN       = 0.05
CAP_R_MAX       = 0.09
CAP_SQUASH      = 0.62        # dôme aplati (1 = sphère)
CAP_SUBDIV      = 2

# Palette (cf. DA) : cyan spectral émissif + pied d'ombre. Cyan bien SATURÉ
# (peu de rouge) pour garder la teinte même à forte émission ; intensité
# modérée en preview — en jeu c'est le glow du WorldEnvironment qui amplifie.
COLOR_STEM_TOP  = (0.18, 0.26, 0.28, 1.0)
COLOR_STEM_BASE = (0.07, 0.11, 0.12, 1.0)
COLOR_CAP_EMIT  = (0.10, 0.80, 0.92, 1.0)   # cyan spectral saturé
CAP_EMIT_STRENGTH = 1.6


def _vcol_material(name, base_rgba):
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


def _emissive_material(name, color, strength):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = color
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def _new_object(mesh, name):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_stems(rng):
    """Tous les pieds fusionnés (un objet, matériau couleur de sommet)."""
    mesh = bpy.data.meshes.new("stems")
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    tops = []   # (position sommet, rayon chapeau) pour poser les chapeaux
    for _ in range(CLUSTER_COUNT):
        ang = rng.uniform(0, math.tau)
        dist = rng.uniform(0, CLUSTER_SPREAD)
        base = mathutils.Vector((math.cos(ang) * dist, math.sin(ang) * dist, 0.0))
        lean_ang = ang + rng.uniform(-0.5, 0.5)
        lean = mathutils.Vector((math.cos(lean_ang), math.sin(lean_ang), 0.0))
        perp = mathutils.Vector((-lean.y, lean.x, 0.0))
        h = rng.uniform(STEM_H_MIN, STEM_H_MAX)
        rings = []
        for i in range(STEM_SEGMENTS + 1):
            t = i / STEM_SEGMENTS
            center = base + lean * (STEM_BEND * t * t) + mathutils.Vector((0, 0, h * t))
            r = STEM_RADIUS * (1.0 - 0.35 * t)
            l = bm.verts.new(center + perp * r)
            rv = bm.verts.new(center - perp * r)
            rings.append((l, rv, center))
        for i in range(STEM_SEGMENTS):
            l0, r0, _ = rings[i]
            l1, r1, _ = rings[i + 1]
            f = bm.faces.new((l0, r0, r1, l1))
            for loop in f.loops:
                t = max(0.0, min(1.0, loop.vert.co.z / max(1e-4, h)))
                col = tuple(COLOR_STEM_BASE[k] + (COLOR_STEM_TOP[k] - COLOR_STEM_BASE[k]) * t
                            for k in range(3)) + (1.0,)
                loop[layer] = col
        tops.append((rings[-1][2], rng.uniform(CAP_R_MIN, CAP_R_MAX)))
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Mushroom_Stems")
    obj.data.materials.append(_vcol_material("Mush_Stem", COLOR_STEM_TOP))
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj, tops


def build_caps(rng, tops):
    """Chapeaux dôme émissifs cyan (un objet, matériau émissif)."""
    mesh = bpy.data.meshes.new("caps")
    bm = bmesh.new()
    for top, radius in tops:
        c = mathutils.Vector(top)
        dome = bmesh.new()
        bmesh.ops.create_icosphere(dome, subdivisions=CAP_SUBDIV, radius=radius)
        for v in dome.verts:
            v.co.z *= CAP_SQUASH
        bmesh.ops.translate(dome, verts=dome.verts, vec=c + mathutils.Vector((0, 0, radius * CAP_SQUASH * 0.5)))
        tmp = bpy.data.meshes.new("tmp_cap")
        dome.to_mesh(tmp)
        dome.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(mesh, "Mushroom_Caps")
    obj.data.materials.append(_emissive_material("Mush_Cap_Glow", COLOR_CAP_EMIT, CAP_EMIT_STRENGTH))
    for p in obj.data.polygons:
        p.use_smooth = False   # facetté (cf. DA)
    return obj


def main():
    rng = random.Random(SEED)
    stems, tops = build_stems(rng)
    caps = build_caps(rng, tops)
    bpy.ops.object.select_all(action="DESELECT")
    stems.select_set(True)
    caps.select_set(True)
    bpy.context.view_layer.objects.active = stems
    bpy.ops.object.join()
    stems.name = "GlowMushrooms"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    print(f"GlowMushrooms généré (SEED={SEED}). Vue Rendered pour l'émission, "
          f"export glTF 2.0.")


main()
