# Briques geometriques (Blender, bmesh). Toutes les formes sont des solides fermes.
import math
import os
import bpy
import bmesh
from mathutils import Matrix


def rrect(w, l, r, cx=0.0, cy=0.0, seg=10):
    """Contour 2D d'un rectangle arrondi, sens trigonometrique."""
    r = max(0.01, min(r, w / 2 - 0.01, l / 2 - 0.01))
    pts = []
    for (sx, sy, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ox, oy = cx + sx * (w / 2 - r), cy + sy * (l / 2 - r)
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def circle(r, cx=0.0, cy=0.0, seg=48):
    return [(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg))
            for i in range(seg)]


def hull(pts):
    """Enveloppe convexe (sens trigonometrique)."""
    pts = sorted(set((round(x, 5), round(y, 5)) for x, y in pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def _link(name, bm):
    bm.normal_update()  # normales a jour apres la permutation d'axes, sinon le recalcul se trompe
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    # Garde-fou : un solide ferme bien oriente a un volume signe positif.
    if bm.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def prism(name, pts, a0, a1, axis="Z", fillet_top=0.0, chamfer_bot=0.0):
    """Extrusion d'un contour 2D entre a0 et a1 le long de l'axe donne.
    axis Z : pts=(x, y) ; axis Y : pts=(x, z) ; axis X : pts=(y, z)."""
    bm = bmesh.new()
    bot = [bm.verts.new((u, v, a0)) for u, v in pts]
    top = [bm.verts.new((u, v, a1)) for u, v in pts]
    fb = bm.faces.new(list(reversed(bot)))
    ft = bm.faces.new(top)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.normal_update()
    if fillet_top > 0:
        bmesh.ops.bevel(bm, geom=list(ft.edges), offset=fillet_top, segments=5,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    if chamfer_bot > 0:
        fb = [f for f in bm.faces if f.normal.z < -0.99 and abs(f.calc_center_median().z - a0) < 1e-4][0]
        bmesh.ops.bevel(bm, geom=list(fb.edges), offset=chamfer_bot, segments=1,
                        affect="EDGES", clamp_overlap=True)
    if axis == "Y":      # (u, v, w) -> (u, w, v)
        for vt in bm.verts:
            u, v, w = vt.co
            vt.co = (u, w, v)
    elif axis == "X":    # (u, v, w) -> (w, u, v)
        for vt in bm.verts:
            u, v, w = vt.co
            vt.co = (w, u, v)
    return _link(name, bm)


def box(name, x0, x1, y0, y1, z0, z1):
    return prism(name, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1)


def cyl(name, r, cx, cy, z0, z1, seg=40):
    return prism(name, circle(r, cx, cy, seg), z0, z1)


def sphere(name, r, co, seg=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r,
                              matrix=Matrix.Translation(co))
    return _link(name, bm)


def bake(ob):
    """Applique les modificateurs et remplace le maillage."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def boolean(target, tool, op="DIFFERENCE", solver="MANIFOLD", keep=False):
    m = target.modifiers.new("b", "BOOLEAN")
    m.operation = op
    try:
        m.solver = solver
    except TypeError:
        m.solver = "EXACT"
    m.object = tool
    bake(target)
    if os.environ.get("COFFRET_DEBUG"):
        bad, vol = mesh_stats(target)
        print(f"[debug] {target.name} {op} {tool.name}: non manifold {bad}, volume {vol:.1f}")
    if not keep:
        bpy.data.objects.remove(tool, do_unlink=True)
    return target


def cut(target, *tools):
    for t in tools:
        boolean(target, t, "DIFFERENCE")
    return target


def add(target, *tools):
    for t in tools:
        boolean(target, t, "UNION")
    return target


def text_mesh(name, body, size, depth, mat):
    """Texte extrude (epaisseur 2*depth centree), place par la matrice mat."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = depth
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    tmp = bpy.data.objects.new(name + "_c", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    me.transform(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_stats(ob):
    """Aretes non manifold et volume (mm3) d'un objet maille."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume(signed=False)
    bm.free()
    return bad, vol
