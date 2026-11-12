# Rendus du Coffret (Cycles). Lancement : blender -b coffret.blend --python scripts/render.py
import math
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import params as P  # noqa: E402
from geo import box, boolean  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "rendus")
os.makedirs(OUT, exist_ok=True)
S = bpy.context.scene
O = bpy.data.objects


def node(nt, kind, idname):
    """Retrouve un noeud par type, ou le cree (Blender 5 ne cree plus les noeuds par defaut)."""
    return next((n for n in nt.nodes if n.type == kind), None) or nt.nodes.new(idname)


def mat(name, rgb, rough=0.5, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except (AttributeError, TypeError):
        pass
    nt = m.node_tree
    b = node(nt, "BSDF_PRINCIPLED", "ShaderNodeBsdfPrincipled")
    out = node(nt, "OUTPUT_MATERIAL", "ShaderNodeOutputMaterial")
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def paint(ob, m):
    ob.data.materials.clear()
    ob.data.materials.append(m)


M = {"gris": mat("PLA gris", (0.07, 0.07, 0.075), 0.6), "gris2": mat("PLA gris clair", (0.16, 0.16, 0.17), 0.6),
     "vert": mat("Diffuseur", (0.25, 1.0, 0.4), 0.4, emit=3.0), "led": mat("LED", (0.2, 1.0, 0.3), emit=8.0),
     "noir": mat("Chameleon", (0.01, 0.01, 0.012), 0.25), "bleu": mat("Badge", (0.01, 0.08, 0.55), 0.4),
     "metal": mat("Anneau", (0.85, 0.85, 0.85), 0.2, metal=1.0), "sol": mat("Sol", (0.75, 0.75, 0.76), 0.9)}
paint(O["Corps"], M["gris"])
paint(O["Tiroir"], M["gris"])
paint(O["Diffuseur"], M["vert"])
paint(O["Chameleon"], M["noir"])
paint(O["Badge"], M["bleu"])
paint(O["Anneau"], M["metal"])
for o in O:
    if o.name.startswith("LED"):
        paint(o, M["led"])

ground = box("Sol", -400, 400, -400, 400, -1, 0)
paint(ground, M["sol"])

S.render.engine = "CYCLES"
S.cycles.device = "CPU"
S.cycles.samples = 64
S.cycles.use_denoising = True
S.render.resolution_x, S.render.resolution_y = 1200, 900
S.view_settings.view_transform = "AgX"
S.world = bpy.data.worlds.new("Studio")
try:
    S.world.use_nodes = True
except (AttributeError, TypeError):
    pass
wnt = S.world.node_tree
bg = node(wnt, "BACKGROUND", "ShaderNodeBackground")
wnt.links.new(bg.outputs["Background"], node(wnt, "OUTPUT_WORLD", "ShaderNodeOutputWorld").inputs["Surface"])
bg.inputs["Color"].default_value = (0.8, 0.8, 0.82, 1)
bg.inputs["Strength"].default_value = 0.6
sun = bpy.data.objects.new("Soleil", bpy.data.lights.new("Soleil", "SUN"))
sun.data.energy, sun.data.angle = 3.0, math.radians(20)
sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(30))
S.collection.objects.link(sun)
cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
cam.data.lens, cam.data.clip_start, cam.data.clip_end = 70, 1, 3000
S.collection.objects.link(cam)
S.camera = cam


def shoot(name, eye, target, lens=70):
    cam.location = Vector(eye)
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    S.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("rendu", name)


def move(names, dy):
    for n in names:
        O[n].location.y += dy


inside = ["Tiroir", "Chameleon"] + [o.name for o in O if o.name.startswith("LED")]

# 1. Vue 3/4 avant, tiroir ferme (Chameleon invisible).
shoot("1_coffret_ferme.png", (120, -150, 110), (0, 24, 5))

# 2. Tiroir sorti : comment le Chameleon se range.
move(inside, -30)
shoot("2_tiroir_ouvert.png", (130, -170, 120), (0, 10, 5))
move(inside, 30)

# 3. Vue de dessous : touches de reveil et encoche pour tirer.
ground.hide_render = True
shoot("3_dessous.png", (90, -110, -120), (0, 24, 4))
ground.hide_render = False

# 4. Coupe dans l'axe du bouton (X = BTN_X) : paroi de 1 mm, badge, languette.
paint(O["Tiroir"], M["gris2"])
for n in ["Corps", "Tiroir", "Chameleon", "Badge", "Diffuseur"]:
    boolean(O[n], box("coupe", P.BTN_X, 200, -200, 200, -50, 50), "DIFFERENCE")
O["Anneau"].hide_render = True
shoot("4_coupe.png", (170, -40, 60), (0, 26, 7), lens=60)
