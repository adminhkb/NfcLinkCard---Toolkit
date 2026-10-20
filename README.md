# NLC Toolkit

Application Flutter pour Android, iOS et ordinateur (Windows, Linux, macOS), destinée au **ChameleonUltra V2**. Le parcours principal met la **lecture** et l’**écriture** de cartes au premier plan. Les outils spécialisés sont regroupés dans un **mode avancé**.

NLC Toolkit est un dérivé de [Chameleon Ultra GUI](https://github.com/GameTec-live/ChameleonUltraGUI). [MIFARE Classic Tool (MCT)](https://github.com/ikarus23/MifareClassicTool) sert de référence pour l’évolution des fonctions MIFARE Classic. Le code présent ne couvre pas encore toutes les fonctions de MCT, et la compatibilité avec un ChameleonUltra V2 physique reste à valider sur chaque plateforme.

## Parcours principal

1. Connecter le ChameleonUltra V2 par le moyen proposé sur la plateforme (Bluetooth LE ou USB/série, selon le matériel).
2. Ouvrir **Lecture** pour détecter une carte et lire les données accessibles. Pour MIFARE Classic, les secteurs protégés nécessitent les clés adaptées.
3. Examiner et enregistrer le résultat dans **Bibliothèque**.
4. Ouvrir **Écriture**, choisir un dump MIFARE Classic, un bloc de données et sa clé A ou B, puis présenter la carte cible. L’application demande une confirmation et relit le bloc après l’écriture quand la carte l’autorise.

L’accueil vérifie le protocole et les commandes nécessaires du micrologiciel avant d’ouvrir la lecture ou l’écriture. L’écriture dépend du type de carte et de la méthode prise en charge par l’appareil. Elle peut modifier définitivement le contenu de la carte cible : utiliser une carte sur laquelle vous êtes autorisé à intervenir et conserver une sauvegarde avant toute écriture.

## Mode avancé

La base de code contient notamment la gestion des dictionnaires de clés, l’édition et l’import/export de données de cartes, la gestion des emplacements d’émulation du ChameleonUltra, ainsi que des outils de diagnostic et de capture HF/LF. Leur disponibilité dépend du type de carte, du firmware et de la connexion. Les fonctions de MCT qui n’existent pas encore dans ce projet devront être ajoutées et validées individuellement.

## Dictionnaires de clés MCT

L’application embarque les trois dictionnaires de clés fournis par **MIFARE Classic Tool** : `std.keys` (3 clés), `extended-std.keys` (2 477 clés) et `hotel-std.keys` (24 clés). Ils sont conservés tels quels, avec leurs commentaires de provenance. Le format est une clé MIFARE Classic hexadécimale de 12 caractères par ligne ; les lignes vides et les commentaires commençant par `#` sont ignorés. Les clés des fichiers Standard et Hôtel sont déjà comprises dans le fichier Étendu.

Ces fichiers proviennent du [dépôt officiel de MCT](https://github.com/ikarus23/MifareClassicTool/tree/b52568c8f274968ded8a7a4bf6f3a067419b63ed/Mifare%20Classic%20Tool/app/src/main/assets/key-files), au commit `b52568c8f274968ded8a7a4bf6f3a067419b63ed`. Voir leur [notice d’attribution](chameleonultragui/assets/dictionaries/mct/NOTICE.md) et la [licence GPLv3](LICENSE).

Au premier lancement après l’installation ou la mise à jour, NLC Toolkit les ajoute dans **Bibliothèque → Dictionnaires → MIFARE Classic Tool** sans remplacer les dictionnaires personnels. Pour une carte MIFARE Classic, **Lire → Fonctions avancées → Clés** propose **MCT · Standard** par défaut ; **MCT · Étendu** et **MCT · Hôtel** peuvent être choisis dans la liste. Le dictionnaire Étendu peut rendre la vérification des clés sensiblement plus longue.

## Analyse des données dynamiques

Dans **Voir le dump**, l’option **Analyser les données dynamiques** examine les dumps MIFARE Classic 1K et 4K. Elle relève des empreintes textuelles, des clés connues présentes dans les trailers et des [blocs de valeur MIFARE](https://www.nxp.com/docs/en/data-sheet/MF1S50YYX_V1.pdf). Un second dump enregistré du même UID peut être sélectionné pour repérer les blocs de données modifiés entre deux lectures.

Ces indices ne prouvent pas à eux seuls un code tournant, une connexion GSM ou le comportement d’une centrale d’accès. Deux dumps identiques ne prouvent pas non plus l’absence de protection. L’application remplace parfois un bloc non lu par seize octets `00` ; l’analyse différentielle écarte donc les blocs nuls ou absents et signale les comparaisons limitées. Les références aux fabricants sont des profils possibles, pas une identification certifiée. Le module n’affirme jamais qu’une copie sera acceptée.

## État des fonctions MIFARE Classic

| Fonction | État dans le code |
| --- | --- |
| Lire une carte et enregistrer un dump avec des clés connues | Présent |
| Écrire un bloc de données sur une carte ordinaire avec une clé A/B, puis relire ce bloc | Présent |
| Écrire un dump complet sur une carte Magic compatible | Avancé |
| Gérer les dictionnaires, éditer et comparer les dumps, interpréter les conditions d’accès et les blocs de valeur | Avancé |
| Rechercher des indices de données dynamiques et comparer deux dumps MIFARE Classic du même UID | Avancé |
| Calculer un BCC et exporter un dump au format texte MCT | Avancé |
| Formater une carte vers son état de livraison et lancer un clonage rapide de l’UID depuis l’application | À réaliser |

La lecture et l’écriture avec un ChameleonUltra V2 réel doivent encore être validées sur Android, iOS et ordinateur.

## Développement

Le projet Flutter se trouve dans `chameleonultragui/`. Installer une version de Flutter et de Dart compatible avec [`pubspec.yaml`](chameleonultragui/pubspec.yaml), puis lancer depuis la racine du dépôt :

```sh
cd chameleonultragui
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

La compilation iOS et macOS nécessite un environnement Apple adapté. Les identifiants natifs Android, iOS, macOS et GTK utilisent provisoirement `com.nfclinkcard.nlctoolkit` ; cela ne réserve aucun nom dans les boutiques d'applications. Les exécutables Windows et Linux s'appellent `nlc_toolkit`. La publication nécessite des comptes, certificats et secrets propres à NLC Toolkit. Le workflow de publication est manuel et reste inactif tant que la variable `NLC_PUBLISH_ENABLED` n'est pas définie à `true`. Le nom du package Flutter et les recettes AUR/Flatpak restent issus du projet source et devront être adaptés avant leur distribution sous le nom NLC Toolkit. Les anciennes pages de [documentation du projet source](https://github.com/GameTec-live/ChameleonUltraGUI/tree/main/docs) décrivent Chameleon Ultra GUI et ses versions publiées, pas une version publiée de NLC Toolkit.

## Version Windows portable

Depuis la racine du dépôt, générer une archive contenant l'exécutable et ses dépendances :

```powershell
pwsh -File chameleonultragui/tool/package_windows.ps1
```

Décompresser l'archive créée dans `chameleonultragui/dist/` avant de lancer `nlc_toolkit.exe`. Brancher le ChameleonUltra V2 en USB, puis le sélectionner dans **Connexion**. Si la détection automatique ne le trouve pas, choisir son port COM avec **Connexion manuelle**. Le Bluetooth du PC n'est pas encore pris en charge dans la version Windows.

## Origine et licence

NLC Toolkit reprend le code de **Chameleon Ultra GUI** et conserve l’attribution de ses auteurs et contributeurs. Les icônes d’origine ont été conçues par [St.Ricky](https://github.com/Saint-Ricky). **MIFARE Classic Tool** est une référence fonctionnelle distincte ; ce dépôt ne prétend ni être sa version multiplateforme ni offrir aujourd’hui une équivalence complète.

Ce dépôt est distribué sous [GNU GPL version 3](LICENSE). Les avis de droits d’auteur existants et le texte de la licence sont conservés.
