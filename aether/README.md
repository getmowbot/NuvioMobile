# Nuvio + AetherEngine

Ce fork de [NuvioMedia/NuvioMobile](https://github.com/NuvioMedia/NuvioMobile) suit chaque version
d'upstream et ajoute, sur iOS, un troisième lecteur à côté du lecteur interne (MPV) et des lecteurs
externes : [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

AetherEngine démultiplexe avec FFmpeg mais décode et affiche avec la chaîne native d'Apple
(VideoToolbox, AVPlayer) : Dolby Vision (profils 5, 7, 8.1, 8.4, AV1 10), HDR10+, HLG,
Dolby Atmos (E-AC-3 JOC) transmis tel quel, et audio sans perte jusqu'en 7.1 pour TrueHD et
DTS-HD MA. Les contrôles du lecteur Nuvio restent les mêmes : seul le moteur sous l'image change.

## Utilisation

**Réglages > Lecture > Lecteur** propose maintenant *Interne (MPV)*, *AetherEngine* et *Externe*.
Quand AetherEngine est choisi, les sections MPV (sortie audio/vidéo iOS) laissent la place à :

| Réglage | Effet |
| --- | --- |
| Sortie audio | *Surround* : TrueHD, DTS… convertis en Dolby Digital Plus 5.1 (marche partout). *Sans perte* : décodés bit à bit en PCM multicanal jusqu'en 7.1 (ampli HDMI / eARC pour le surround). AAC, AC-3, E-AC-3 Atmos, FLAC et ALAC passent toujours tels quels. |
| Hauteurs Atmos et DTS:X | Restitue les objets TrueHD Atmos / DTS:X dans la configuration d'enceintes choisie (5.1.2 à 9.1.6), en PCM ou en audio positionnel Apple (AirPods, AirPlay). |
| Détecter les pistes Atmos | Analyse brièvement les pistes pour étiqueter « Atmos » celles en E-AC-3 JOC. |
| Dolby Vision | *Automatique*, ou *HDR10 uniquement* pour les fichiers aux couleurs vertes/violettes. |
| Dolby Vision profil 7 FEL | Compose le double couche des UHD Blu-ray sur le GPU au lieu de le convertir en 8.1. |
| Décodage vidéo | Matériel (auto) ou logiciel forcé (FFmpeg / dav1d) pour les fichiers récalcitrants. |
| Sous-titres en PiP et AirPlay | Publie aussi les sous-titres texte comme pistes natives. |

Le style des sous-titres (couleurs, taille, contour, position, suppression SDH, décalage) est
celui des réglages Nuvio habituels : AetherEngine décode les sous-titres et Nuvio les dessine.

Ce qui reste sur MPV, même avec AetherEngine sélectionné : les sources dont l'audio est un flux
séparé et les bandes-annonces YouTube (AetherEngine n'assemble pas deux flux).

## Installation

Chaque version est publiée dans les *Releases* du fork (`<version>-aether`, IPA non signée) et
dans une source AltStore / SideStore à ajouter une fois :

```
https://raw.githubusercontent.com/getmowbot/NuvioMobile/cmp-rewrite/aether/altstore-source.json
```

(La source se remplit à la première publication ; le dépôt doit rester public pour qu'AltStore
puisse lire la source et télécharger l'IPA.)

L'app garde l'identifiant `com.nuvio.media` : elle remplace la version officielle sur l'appareil.
AetherEngine 7 demande **iOS 18 minimum**, donc cette build aussi.

## Suivi automatique d'upstream

Deux workflows, dans `.github/workflows/` :

- **Aether - Sync upstream** (`aether-sync-upstream.yml`), toutes les 6 h et à la demande :
  récupère la dernière release d'upstream (ou la pointe de `cmp-rewrite` avec `track: branch`),
  la fusionne dans la branche du fork, vérifie que l'intégration Xcode s'applique toujours, pousse,
  puis lance le build si cette version n'a pas encore été publiée.
  En cas de conflit, rien n'est poussé : le job échoue et ouvre une issue avec les fichiers en conflit.
- **Aether - Build IPA** (`aether-build-ipa.yml`), à la demande ou appelé par le précédent :
  build Release non signé, vérifications, release GitHub et mise à jour de la source AltStore.

### Rien ne part vers NuvioMedia

Le dépôt d'origine n'est jamais que **lu** (récupération de ses releases). Tout ce que les
workflows écrivent (fusions, releases, source AltStore, issues) va dans ce fork, et ils refusent
de s'exécuter dans le dépôt d'origine. Les notes de release ne recopient pas celles d'upstream,
pour ne pas notifier ses contributeurs via leurs `@mentions`.

Seul piège, côté GitHub : sur un fork, le bouton *New pull request* propose par défaut le dépôt
d'origine comme cible. Pour fusionner une branche dans ce fork, choisir
`getmowbot/NuvioMobile` comme *base repository* (ou fusionner en local avec git), et ne jamais
cliquer sur *Contribute* / *Open pull request* vers `NuvioMedia/NuvioMobile`.

### Mise en place (une fois)

1. Fusionner ces changements dans la branche par défaut (`cmp-rewrite`) : GitHub n'exécute les
   workflows planifiés que depuis celle-ci.
2. Onglet *Actions* du fork : activer les workflows (désactivés par défaut sur un fork).
3. *Settings > Secrets and variables > Actions* :
   - secret `FORK_SYNC_TOKEN` : jeton *fine-grained* limité à ce dépôt, permissions
     *Contents* et *Workflows* en lecture/écriture. Indispensable dès qu'une version d'upstream
     modifie `.github/workflows` (le jeton par défaut de GitHub Actions n'a pas le droit de pousser
     ces fichiers).
   - secret optionnel `NUVIO_LOCAL_PROPERTIES_BASE64` : le `local.properties` encodé en base64,
     comme pour upstream (clés d'API, comptes, synchro). Sans lui l'app se construit, mais les
     fonctions qui dépendent de ces clés sont inactives.
   - variables optionnelles : `UPSTREAM_REPOSITORY`, `UPSTREAM_BRANCH`, `AETHER_TRACK`
     (`release` / `branch`), `AETHER_MACOS_RUNNER`, `AETHER_DEVELOPER_DIR`.
4. Lancer *Aether - Sync upstream* à la main une première fois.

### Pourquoi ça fusionne sans conflit

Presque tout le code du fork est dans des fichiers qui n'existent pas chez upstream. Les fichiers
d'upstream ne sont touchés que par de courts points d'accroche :

- `PlaybackSettingsPage.kt` : le choix du lecteur et l'affichage des réglages AetherEngine ;
- `PlayerEngine.ios.kt` : la création du pont (MPV ou AetherEngine) et la position de départ ;
- `ContentView.swift` : l'enregistrement du pont AetherEngine ;
- `NowPlayingController.swift` : le propriétaire devient un protocole partagé par les deux lecteurs.

Le projet Xcode (`project.pbxproj`) n'est **pas** modifié dans git : `aether/scripts/patch-xcode-project.py`
y ajoute le paquet `NuvioAetherKit` et passe la cible à iOS 18 au moment du build.

## Développement local

```bash
python3 aether/scripts/patch-xcode-project.py
```

puis ouvrir `iosApp/iosApp.xcodeproj` comme d'habitude. Ne pas commiter le `project.pbxproj`
modifié (`git checkout -- iosApp/iosApp.xcodeproj/project.pbxproj` pour revenir en arrière).
Sans ce script, l'app se construit quand même, avec MPV seulement.

## Architecture

| Emplacement | Rôle |
| --- | --- |
| `composeApp/src/commonMain/.../player/aether/AetherSettings.kt` | Réglages AetherEngine (par profil) et leur sérialisation vers Swift |
| `composeApp/src/commonMain/.../settings/AetherPlaybackSettings.kt` | Choix du lecteur et écrans de réglages |
| `composeApp/src/iosMain/.../player/AetherPlayerBridge.kt` | Interface du pont, fabrique, choix MPV / AetherEngine |
| `iosApp/iosApp/Aether/` | Pont Kotlin ↔ Swift et contrôleur de vue (Now Playing, session audio, PiP, UI immersive) |
| `aether/NuvioAetherKit/` | Paquet Swift : moteur, sous-titres, pistes, PiP, infos média |
| `aether/scripts/` | Intégration Xcode, vérification de l'IPA, versions résolues |

`NuvioAetherKit` est volontairement un **framework dynamique** : MPVKit lie un FFmpeg statique dans
l'exécutable de l'app, et AetherEngine lié à côté utiliserait ce FFmpeg-là au lieu du sien.
Isolé dans son framework, il se lie à ses propres `AetherLib*` (voir la doc d'AetherEngine,
*Holding a second player beside the engine*). `aether/scripts/verify-ipa.sh` le contrôle à chaque build.

Les composants optionnels d'AetherEngine (`TrueHDObjectAudio`, `DTSXObjectAudio`,
`DualLayerDolbyVision`) sont activés dans `aether/NuvioAetherKit/Package.swift`. Ils peuvent être
soumis à des licences de brevets tierces ; retirez-les de la liste `traits` pour construire sans.

## Limites connues

- Pas de bascule MPV ↔ AetherEngine pendant la lecture : le choix se fait dans les réglages.
- Les sous-titres ASS sont rendus avec le style Nuvio (gras, italique, couleurs, position
  haut/milieu/bas), pas avec toute la mise en page ASS que fait MPV.
- En PiP sur le chemin natif, les boutons lecture/pause de la fenêtre pilotent AVPlayer
  directement (sans passer par la synchronisation Watch Party).
- Les réglages MPV d'image (tone mapping, EDR, égaliseur) ne s'appliquent pas : AetherEngine
  laisse l'affichage HDR / Dolby Vision au système.
