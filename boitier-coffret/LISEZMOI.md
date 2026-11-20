# Coffret ChameleonUltra

Boîtier imprimé en 3D qui cache entièrement le ChameleonUltra. Le badge se pose dessus, le Chameleon reste intact : pas de démontage, pas de soudure.

Encombrement : 45 × 50 × 15,8 mm.

## Contenu du dossier

| Élément | Rôle |
|---|---|
| `stl/coffret_corps.stl` | la coque : empreinte du badge, bande lumineuse, gravure NLC |
| `stl/coffret_tiroir.stl` | le tiroir qui reçoit le Chameleon, façade affleurante avec passage USB‑C |
| `stl/coffret_diffuseur.stl` | la barrette translucide posée au-dessus des 8 LED |
| `rendus/` | vues du coffret fermé, tiroir ouvert, dessous et coupe |
| `coffret.blend` | le modèle complet en mm : collection « A imprimer » et maquettes du Chameleon et du badge (régénéré par `build.py`, les retouches à la main y sont écrasées) |
| `scripts/` | génération paramétrique (Blender 5.2) |
| `controle.txt` | contrôles automatiques de la dernière génération |

## Avant d'imprimer : mesurer le Chameleon

Les cotes viennent des photos officielles (RRG, Lab401), pas d'une mesure. Vérifie au pied à coulisse les valeurs du début de `scripts/params.py` :

- `DEV_W`, `DEV_L`, `DEV_T` : 24 × 40 × 8 mm ;
- `BTN_Y`, `BTN_X` : boutons A/B à 9,3 mm du bout USB‑C et à 7,5 mm du centre ;
- `LED_Y` : rangée de LED à 8,8 mm du bout USB‑C ;
- la hauteur du port USB‑C : il est supposé à mi-épaisseur (`Z_USB`).

Conseil : imprime d'abord le tiroir seul (4 cm³, environ 30 min) pour valider l'ajustement.

## Impression

- **Matière :** PLA ou PETG pour le corps et le tiroir. Le diffuseur se fait en PETG translucide ou en PLA naturel/blanc.
- **Réglages :** couches de 0,2 mm, 3 périmètres, remplissage 20 %, **sans supports**.
- **Orientation :** chaque pièce à plat, dessous sur le plateau, telle qu'exportée.
- **Couleur :** imprimante multi-filament ? Le diffuseur peut être imprimé en place, dans la fenêtre du corps, avec un second filament.

## Montage

1. Enfoncer le diffuseur par le dessus dans sa fenêtre. Il repose sur un rebord ; s'il flotte, une goutte de colle suffit.
2. Poser le Chameleon dans le tiroir, **bout USB‑C vers la façade** :
   - face LED en haut pour les badges 13,56 MHz (Vigik, MIFARE) ;
   - face A/B en haut pour les badges 125 kHz.
3. Glisser le tiroir jusqu'au cran.

## Utilisation

- **Badge :** dans l'empreinte en goutte. L'anneau et les clés passent par l'encoche arrière.
- **Réveil :** appuyer par-dessous, à travers l'un des deux trous. La languette pousse le bouton A ou B.
- **Charge :** câble USB‑C par la façade, sans ouvrir le tiroir.

## Régénérer après modification

```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python scripts\build.py
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b coffret.blend --python scripts\render.py
```

`build.py` refait les STL et `controle.txt` (aretes non manifold, chevauchements entre pièces). `render.py` refait les vues.
