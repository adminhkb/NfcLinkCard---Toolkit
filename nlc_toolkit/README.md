# NLC Toolkit

Application Flutter (Windows, Android, iOS, macOS, Linux) pour lire, écrire et copier des badges avec un **ChameleonUltra**, reliée à l'espace Badges de l'ERP.

## Ce que fait l'application

- **Connexion avec le compte de l'ERP** : adresse e-mail et mot de passe (Firebase Auth), puis le même code de sécurité par e-mail que sur le site. « Se souvenir de cet appareil pendant 30 jours » évite le code aux ouvertures suivantes et permet d'ouvrir l'application hors connexion.
- **Mode simple** : accueil avec les prochains rendez-vous, la carte des immeubles et l'état du lecteur, plus la lecture et l'écriture d'un badge.
- **Mode avancé** : bibliothèque de cartes et de dictionnaires, tableau de bord de l'appareil, emplacements d'émulation, outils (BCC, import MCT, reniflage HF/LF…).
- **Badges enregistrés** : un badge lu peut être rangé dans Firebase Storage et rattaché à un immeuble (depuis la bibliothèque) ; chaque immeuble affiche ses badges enregistrés. Le bouton « Copier » récupère le badge le temps de l'écrire sur un badge vierge, sans le garder sur l'appareil.
- Le reste des données de l'ERP est **lu** (rendez-vous, immeubles, prospection) ; rien d'autre n'y est modifié depuis l'application.

Sous Windows, le lecteur se connecte en USB par défaut. Le Bluetooth est possible en option (réglage « Connexion Bluetooth ») : appairer d'abord le ChameleonUltra dans les réglages Bluetooth de Windows. Un seul mode à la fois (USB ou Bluetooth).

## Configuration de la liaison ERP

Les identifiants du projet Firebase ne sont pas dans le dépôt. Copier `config/erp.example.json` vers `config/erp.json` (fichier ignoré par git) et le remplir :

| Clé | Valeur |
| --- | --- |
| `NLC_ERP_PROJECT_ID` | identifiant du projet Firebase de l'ERP |
| `NLC_ERP_API_KEY` | clé d'API web du projet |
| `NLC_ERP_REGION` | région des fonctions (`us-central1`) |
| `NLC_ERP_WEB_URL` | adresse de l'ERP, pour le bouton « Ouvrir l'ERP » |

Sans ce fichier, l'application se lance mais affiche « Liaison ERP non configurée ».

## Lancer et compiler

```sh
flutter pub get
flutter run -d windows --dart-define-from-file=config/erp.json
```

Version Windows portable (archive dans `dist/`) :

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1
```

## Vérifier l'interface sans toucher à l'ERP

Une version de développement peut tourner contre un **faux ERP en mémoire** (données inventées, aucun accès réseau). Ce mode n'existe pas dans une version publiée.

```powershell
flutter build windows --debug
$env:NLC_DEMO = '1'; .\build\windows\x64\runner\Debug\nlc_toolkit.exe
```

| Variable | Effet |
| --- | --- |
| `NLC_DEMO_STAGE` | `login`, `code` ou `ready` : écran où s'arrêter (code de démonstration : `123456`) |
| `NLC_DEMO_PAGE` | page ouverte : `dashboard`, `read`, `write`, `library`, `device`, `slots`, `tools`, `settings` |
| `NLC_DEMO_MODE` | `simple` ou `advanced` |
| `NLC_DEMO_DEVICE=1` | lecteur simulé déjà connecté |
| `NLC_DEMO_ZOOM` | échelle d'affichage, par exemple `0.6` pour voir une page entière |

## Tests

```sh
flutter test
```

Les tests de `test/erp/` jouent la connexion, le code de sécurité, l'appareil mémorisé et le mode hors connexion contre le faux ERP, à l'écran comme sans interface.

Les tests de `test/emulator/` vont plus loin : ils utilisent les **émulateurs Firebase** avec les vraies règles de sécurité de l'ERP et le vrai code de ses fonctions de double authentification, sous un projet fictif. Ils sont ignorés tant que le banc d'essai n'est pas lancé :

```powershell
powershell -ExecutionPolicy Bypass -File tool/erp_emulator/start.ps1 -ErpRepo C:\chemin\vers\depot-erp
# dans un autre terminal
$env:NLC_ERP_EMULATOR = '1'; flutter test test/emulator
```

## Organisation du code

| Dossier | Contenu |
| --- | --- |
| `lib/erp/` | liaison avec l'ERP : connexion, session chiffrée, double authentification, lecture Firestore |
| `lib/gui/design/` | thème et composants d'interface, aux couleurs de l'ERP |
| `lib/gui/auth/`, `lib/gui/shell/` | écrans d'accès, barre latérale et en-tête |
| `lib/gui/page/` | pages : accueil, lecture, écriture, bibliothèque, appareil, outils, réglages |
| `lib/bridge/`, `lib/connector/`, `lib/helpers/` | dialogue avec le ChameleonUltra et outils MIFARE |

Le fond à motif (`assets/fond-erp.png`) est le rendu de la tuile générée par `tools/generer-fond-erp.mjs` dans le dépôt de l'ERP.

## Licence

Logiciel libre distribué sous [GNU GPL version 3](LICENSE), sans aucune garantie. L'origine du code et les composants tiers sont détaillés dans [NOTICE.md](NOTICE.md).
