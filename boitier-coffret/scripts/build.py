# Construit le Coffret, controle les pieces et exporte les STL.
# Lancement : blender -b --factory-startup --python scripts/build.py
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import params as P  # noqa: E402
from geo import mesh_stats, boolean  # noqa: E402
import parts_body  # noqa: E402
import parts_drawer  # noqa: E402

ROOT = os.path.dirname(HERE)
STL = os.path.join(ROOT, "stl")
os.makedirs(STL, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

body = parts_body.make_body()
drawer = parts_drawer.make_drawer()
diff = parts_drawer.make_diffuser()
dev, leds = parts_drawer.make_device()
fob, ring = parts_drawer.make_fob()


def overlap(a, b):
    tmp = a.copy()
    tmp.data = a.data.copy()
    bpy.context.scene.collection.objects.link(tmp)
    boolean(tmp, b, "INTERSECT", keep=True)
    vol = mesh_stats(tmp)[1] if len(tmp.data.polygons) else 0.0
    bpy.data.objects.remove(tmp, do_unlink=True)
    return vol


lines = [f"Coffret {P.W:.1f} x {P.D:.1f} x {P.H:.1f} mm"]
for ob in (body, drawer, diff):
    bad, vol = mesh_stats(ob)
    d = ob.dimensions
    lines.append(f"{ob.name}: {d.x:.1f} x {d.y:.1f} x {d.z:.1f} mm, {vol / 1000:.2f} cm3, "
                 f"aretes non manifold : {bad}")
for a, b in ((body, drawer), (body, dev), (drawer, dev), (body, diff), (body, fob)):
    lines.append(f"Chevauchement {a.name} / {b.name} : {overlap(a, b):.3f} mm3")
lines.append(f"Plastique entre Chameleon et badge : {P.Z_RECESS - P.Z_DEV1:.2f} mm "
             f"(dont {P.SKIN:.1f} mm de paroi)")

files = {body: "coffret_corps.stl", drawer: "coffret_tiroir.stl", diff: "coffret_diffuseur.stl"}
for ob, name in files.items():
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.wm.stl_export(filepath=os.path.join(STL, name), export_selected_objects=True,
                          ascii_format=False, apply_modifiers=True)

import presentation  # noqa: E402
presentation.setup()  # apres l'export : couleurs, mm et vue pour l'ouverture dans Blender
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "coffret.blend"))
with open(os.path.join(ROOT, "controle.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
