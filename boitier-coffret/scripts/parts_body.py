# Corps du Coffret : coque, cavite du tiroir, empreinte du badge, bande lumineuse.
from mathutils import Matrix
import params as P
from geo import rrect, circle, hull, prism, box, cyl, sphere, cut, boolean, text_mesh


def make_body():
    body = prism("Corps", rrect(P.W, P.D, P.CORNER_R, 0, P.D / 2, seg=14), 0, P.H,
                 fillet_top=P.TOP_FILLET, chamfer_bot=P.BOTTOM_CHAMFER)

    # Cavite ou coulisse le tiroir, et logement affleurant de sa facade.
    cut(body, box("c_cavite", -P.CAV_W / 2, P.CAV_W / 2, -1, P.CAV_L, P.Z_FLOOR, P.Z_CEIL))
    hz = P.POCKET_Z1 - P.Z_FLOOR
    cut(body, prism("c_facade", rrect(P.POCKET_W, hz, 1.75, 0, P.Z_FLOOR + hz / 2),
                    -1, P.FRONT_T, axis="Y"))

    # Empreinte du badge (goutte) qui debouche a l'arriere, et encoche de l'anneau.
    goutte = hull(circle(P.FOB_R, 0, P.FOB_CY, 96) + circle(P.TAB_R, 0, P.TAB_CY, 40))
    cut(body, prism("c_badge", goutte, P.Z_RECESS, P.H + 1))
    cut(body, box("c_anneau", -P.RING_NOTCH_W / 2, P.RING_NOTCH_W / 2,
                  P.CAV_L + 2.5, P.D + 1, P.RING_NOTCH_Z, P.H + 1))

    # Fenetre de la bande lumineuse, avec un rebord bas qui retient le diffuseur.
    zl = P.Z_CEIL + P.STRIP_LIP_T
    cut(body, prism("c_bande", rrect(P.STRIP_W, P.STRIP_D, P.STRIP_D / 2, 0, P.Y_LED),
                    zl, P.H + 1))
    w2, d2 = P.STRIP_W - 2 * P.STRIP_LIP, P.STRIP_D - 2 * P.STRIP_LIP
    cut(body, prism("c_bande_bas", rrect(w2, d2, d2 / 2, 0, P.Y_LED), P.Z_CEIL - 1, zl + 0.01))

    # Trous de doigt sous les touches de reveil (boutons A et B).
    for sx in (-1, 1):
        cut(body, cyl("c_doigt", P.PRESS_HOLE_D / 2, sx * P.BTN_X, P.Y_BTN, -1, P.Z_FLOOR + 0.01))

    # Encoche sous la facade pour tirer le tiroir.
    cut(body, prism("c_tirer", circle(4.0, 0, 0, 40), -1, P.FRONT_T + 1.5, axis="Y"))

    # Crans de fermeture : empreintes des bossages du tiroir.
    for sx in (-1, 1):
        cx = sx * (P.DRAWER_W / 2 + P.DETENT - 1.0)
        cut(body, sphere("c_cran", 1.1, (cx, P.DETENT_Y, P.DETENT_Z)))

    # Gravure NLC sur le flanc droit, lisible de l'exterieur.
    mat = Matrix(((0, 0, 1, P.W / 2), (1, 0, 0, P.D * 0.5), (0, 1, 0, P.H * 0.48), (0, 0, 0, 1)))
    logo = text_mesh("c_logo", P.LOGO_TEXT, P.LOGO_SIZE, P.LOGO_DEPTH, mat)
    boolean(body, logo, "DIFFERENCE", solver="EXACT")
    return body
