# Mise en forme de coffret.blend pour l'ouvrir dans Blender : couleurs, unites en mm,
# collections "A imprimer" / "Maquettes", vue 3D cadree sur le coffret.
import math
import bpy
from mathutils import Euler, Vector

COLORS = {"Corps": (0.08, 0.08, 0.085, 1), "Tiroir": (0.17, 0.17, 0.18, 1),
          "Diffuseur": (0.3, 1.0, 0.45, 1), "Chameleon": (0.015, 0.015, 0.02, 1),
          "LED": (0.2, 1.0, 0.3, 1), "Badge": (0.02, 0.12, 0.7, 1), "Anneau": (0.8, 0.8, 0.8, 1)}
PRINT = ("Corps", "Tiroir", "Diffuseur")


def _mat(name, rgba):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = rgba  # couleur affichee en mode Solide
    try:
        m.use_nodes = True
    except (AttributeError, TypeError):
        pass
    nt = m.node_tree
    if nt is not None:
        b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None) \
            or nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) \
            or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
        b.inputs["Base Color"].default_value = rgba
        if name in ("Diffuseur", "LED"):
            b.inputs["Emission Color"].default_value = rgba
            b.inputs["Emission Strength"].default_value = 2.0
        if name == "Anneau":
            b.inputs["Metallic"].default_value = 1.0
    return m


def setup():
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 0.001  # 1 unite Blender = 1 mm
    sc.unit_settings.length_unit = "MILLIMETERS"

    colls = {}
    for name in ("A imprimer", "Maquettes (ne pas imprimer)"):
        c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
        if name not in sc.collection.children:
            sc.collection.children.link(c)
        colls[name] = c
    for ob in list(sc.collection.objects):
        key = "LED" if ob.name.startswith("LED") else ob.name
        if key in COLORS and ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(_mat(key, COLORS[key]))
        dest = colls["A imprimer"] if key in PRINT else colls["Maquettes (ne pas imprimer)"]
        dest.objects.link(ob)
        sc.collection.objects.unlink(ob)

    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type != "VIEW_3D":
                continue
            sp = area.spaces.active
            sp.clip_start, sp.clip_end = 0.1, 5000
            sp.shading.type = "SOLID"
            sp.shading.color_type = "MATERIAL"
            r3d = sp.region_3d
            r3d.view_perspective = "PERSP"
            r3d.view_location = Vector((0, 25, 6))
            r3d.view_distance = 140
            r3d.view_rotation = Euler((math.radians(62), 0, math.radians(40))).to_quaternion()
