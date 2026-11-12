# Cotes du Coffret ChameleonUltra, en mm. Toutes les pieces en dependent :
# corriger ici apres mesure au pied a coulisse, puis relancer build.py.
# Repere : X = largeur (gauche -> droite), Y = profondeur (facade Y=0 -> arriere),
# Z = hauteur (dessous Z=0). 1 unite Blender = 1 mm.

# --- ChameleonUltra (photos RRG / Lab401, a verifier sur l'appareil) ---
DEV_W, DEV_L, DEV_T, DEV_R = 24.0, 40.0, 8.0, 4.0  # largeur, longueur, epaisseur, rayon des coins
LED_Y = 8.8        # rangee des 8 LED (face HF) depuis le bout USB-C
LED_SPAN = 17.0    # etendue de la rangee de LED
BTN_Y = 9.3        # boutons A/B (face LF) depuis le bout USB-C
BTN_X = 7.5        # ecart des boutons par rapport au centre
USB_W, USB_H = 12.6, 6.8  # passage de la fiche USB-C, surmoulage compris

# --- Jeux d'impression ---
CLR_DEV = 0.3      # Chameleon dans son logement (par cote)
CLR_SLIDE = 0.25   # tiroir dans le corps (par cote)
CLR_PART = 0.15    # diffuseur dans sa fenetre (par cote)

# --- Empilage vertical ---
WALL_BOTTOM = 1.6  # fond du corps
DRAWER_FLOOR = 1.2  # fond du tiroir
GAP_UNDER = 1.5    # vide sous le Chameleon (tetes de vis, touches de reveil)
GAP_OVER = 0.3     # jeu entre le Chameleon et le plafond
SKIN = 1.0         # plastique entre le Chameleon et le badge
RECESS_DEPTH = 2.2  # profondeur de l'empreinte du badge

Z_FLOOR = WALL_BOTTOM                         # 1.6  sol de la cavite
Z_DFLOOR = Z_FLOOR + DRAWER_FLOOR             # 2.8  dessus du fond du tiroir
Z_DEV0 = Z_DFLOOR + GAP_UNDER                 # 4.3  dessous du Chameleon
Z_DEV1 = Z_DEV0 + DEV_T                       # 12.3 dessus du Chameleon
Z_CEIL = Z_DEV1 + GAP_OVER                    # 12.6 plafond de la cavite
Z_RECESS = Z_CEIL + SKIN                      # 13.6 fond de l'empreinte
H = Z_RECESS + RECESS_DEPTH                   # 15.8 hauteur totale
Z_USB = Z_DEV0 + DEV_T / 2                    # 8.3  axe du port USB-C

# --- Tiroir (le Chameleon y entre bout USB-C vers la facade) ---
FRONT_T = 2.0                                 # epaisseur de la facade du tiroir
Y_DEV0 = FRONT_T + CLR_DEV                    # 2.3  bout USB-C du Chameleon
Y_DEV1 = Y_DEV0 + DEV_L                       # 42.3
DRAWER_WALL = 1.6
DRAWER_BACK = 1.6
DRAWER_W = DEV_W + 2 * CLR_DEV + 2 * DRAWER_WALL   # 27.8
DRAWER_L = Y_DEV1 + CLR_DEV + DRAWER_BACK          # 44.2
FACE_W = 34.0                                 # largeur visible de la facade
FACE_Z1 = 13.4                                # haut de la facade
LEDGE_W = 1.6                                 # appuis lateraux du Chameleon
DETENT = 0.35                                 # saillie des crans de fermeture
DETENT_Y, DETENT_Z = 8.0, 11.0

# Touches de reveil : languettes souples dans le fond du tiroir, sous A et B,
# a pousser par-dessous a travers deux trous du corps.
Y_BTN = Y_DEV0 + BTN_Y                        # 11.6
TONGUE_W, TONGUE_L, TONGUE_T = 4.4, 12.0, 0.8
SLOT = 0.6                                    # largeur de la decoupe en U
NUB_D = 3.0                                   # teton qui appuie sur le bouton
PRESS_HOLE_D = 9.0                            # trou de doigt sous le corps

# --- Corps ---
W, D = 45.0, 50.0                             # largeur, profondeur
CORNER_R = 6.0                                # rayon des coins (vue de dessus)
TOP_FILLET = 2.0                              # arrondi des aretes du dessus
BOTTOM_CHAMFER = 0.4                          # anti "patte d'elephant"
CAV_W = DRAWER_W + 2 * CLR_SLIDE              # 28.3
CAV_L = DRAWER_L + 0.3                        # 44.5
POCKET_W = FACE_W + 2 * CLR_SLIDE             # logement de la facade
POCKET_Z1 = FACE_Z1 + CLR_SLIDE

# --- Bande lumineuse au-dessus des LED ---
Y_LED = Y_DEV0 + LED_Y                        # 11.1
STRIP_W, STRIP_D = 19.0, 3.0
STRIP_LIP, STRIP_LIP_T = 0.5, 0.6             # rebord qui retient le diffuseur

# --- Empreinte du badge (goutte) ---
FOB_R = 16.75                                 # partie ronde : diametre 33.5
FOB_CY = Y_LED + STRIP_D / 2 + 2.0 + FOB_R    # 31.35 (2 mm de bord apres la bande)
TAB_R = 5.5                                   # languette de l'anneau
TAB_CY = FOB_CY + 15.5                        # debouche a l'arriere
RING_NOTCH_W, RING_NOTCH_Z = 7.0, 7.0         # encoche ou l'anneau descend

# --- Gravure ---
LOGO_TEXT, LOGO_SIZE, LOGO_DEPTH = "NLC", 6.5, 0.6
