# Tiroir, diffuseur, et maquettes (Chameleon, badge, anneau) pour les controles et les rendus.
import math
import bpy
import params as P
from geo import rrect, circle, hull, prism, box, cyl, sphere, cut, add


def make_drawer():
    dr = prism("Tiroir", rrect(P.DRAWER_W, P.DRAWER_L, 1.0, 0, P.DRAWER_L / 2), P.Z_FLOOR, P.Z_DEV1)
    hz = P.FACE_Z1 - P.Z_FLOOR
    add(dr, prism("t_facade", rrect(P.FACE_W, hz, 1.5, 0, P.Z_FLOOR + hz / 2), 0, P.FRONT_T, axis="Y"))

    # Logement du Chameleon (il se pose sur deux appuis lateraux, face HF ou LF en haut).
    cy = P.Y_DEV0 + P.DEV_L / 2
    cut(dr, prism("t_logement", rrect(P.DEV_W + 2 * P.CLR_DEV, P.DEV_L + 2 * P.CLR_DEV,
                                      P.DEV_R + P.CLR_DEV, 0, cy), P.Z_DFLOOR, P.Z_DEV1 + 1))
    for sx in (-1, 1):
        a, b = sx * (P.DEV_W / 2 + P.CLR_DEV + 0.2), sx * (P.DEV_W / 2 - P.LEDGE_W)
        add(dr, box("t_appui", min(a, b), max(a, b), P.Y_DEV0 + 3, P.Y_DEV1 - 3,
                    P.Z_DFLOOR - 0.01, P.Z_DEV0))

    # Passage de la fiche USB-C et encoche pour tirer.
    cut(dr, prism("t_usb", rrect(P.USB_W, P.USB_H, 2.4, 0, P.Z_USB), -1, P.Y_DEV0 + 0.5, axis="Y"))
    cut(dr, prism("t_tirer", circle(4.0, 0, 0, 40), -1, P.FRONT_T + 0.5, axis="Y"))

    # Touches de reveil : languette en U amincie + teton sous chaque bouton.
    hw, s = P.TONGUE_W / 2, P.SLOT
    tip = P.Y_BTN - 2.0
    root = tip + P.TONGUE_L
    z0, z1 = P.Z_FLOOR - 1, P.Z_DFLOOR + 0.01
    for sx in (-1, 1):
        x = sx * P.BTN_X
        cut(dr, box("t_u1", x - hw - s, x - hw, tip - s, root, z0, z1),
            box("t_u2", x + hw, x + hw + s, tip - s, root, z0, z1),
            box("t_u3", x - hw - s, x + hw + s, tip - s, tip, z0, z1),
            box("t_mince", x - hw - 0.01, x + hw + 0.01, tip - 0.01, root, P.Z_FLOOR + P.TONGUE_T, z1))
        add(dr, cyl("t_teton", P.NUB_D / 2, x, P.Y_BTN, P.Z_FLOOR + P.TONGUE_T - 0.01, P.Z_DEV0 - 0.3))

    # Bossages de fermeture (cran).
    for sx in (-1, 1):
        add(dr, sphere("t_cran", 1.0, (sx * (P.DRAWER_W / 2 + P.DETENT - 1.0), P.DETENT_Y, P.DETENT_Z)))
    return dr


def make_diffuser():
    zl = P.Z_CEIL + P.STRIP_LIP_T
    w, d = P.STRIP_W - 2 * P.CLR_PART, P.STRIP_D - 2 * P.CLR_PART
    return prism("Diffuseur", rrect(w, d, d / 2, 0, P.Y_LED), zl, P.H)


def make_device():
    dv = prism("Chameleon", rrect(P.DEV_W, P.DEV_L, P.DEV_R, 0, P.Y_DEV0 + P.DEV_L / 2),
               P.Z_DEV0, P.Z_DEV1)
    leds = [cyl("LED", 0.5, -P.LED_SPAN / 2 + i * P.LED_SPAN / 7, P.Y_LED,
                P.Z_DEV1 - 0.01, P.Z_DEV1 + 0.2, 12) for i in range(8)]
    return dv, leds


def make_fob():
    pts = [(x, y + P.FOB_CY) for x, y in hull(circle(15.6, 0, 0, 64) + circle(4.6, 0, 15.0, 32))]
    fob = prism("Badge", pts, P.Z_RECESS, P.Z_RECESS + 4.0, fillet_top=0.8)
    cut(fob, cyl("b_trou", 2.0, 0, P.FOB_CY + 15.0, P.Z_RECESS - 1, P.Z_RECESS + 5))
    hy, hz = P.FOB_CY + 15.0, P.Z_RECESS + 2.0
    cy_, cz = P.D + 6.5, P.H - 0.8
    r = math.hypot(hy - cy_, hz - cz)
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.8, major_segments=64,
                                     minor_segments=12, location=(0, cy_, cz),
                                     rotation=(0, math.pi / 2, 0))
    ring = bpy.context.active_object
    ring.name = "Anneau"
    return fob, ring
