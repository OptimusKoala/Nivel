<div align="center">

<img src="docs/logo.png" alt="Nivelito, la mascotte de Nivel" width="168"/>

# Nivel

**Perdre du poids en douceur, sans jamais culpabiliser.**

Une app iOS gamifiée façon jeu vidéo cozy, en français, locale par défaut.

<p>
  <img src="https://img.shields.io/badge/iOS-17%2B-f57c1f?style=flat-square" alt="iOS 17+"/>
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-f57c1f?style=flat-square" alt="SwiftUI + SwiftData"/>
  <img src="https://img.shields.io/badge/WidgetKit-4%20familles-f57c1f?style=flat-square" alt="WidgetKit"/>
  <img src="https://img.shields.io/badge/tests-329%20core%20%2B%20357%20app-3a1220?style=flat-square" alt="329 tests NivelCore + 357 tests app"/>
  <img src="https://img.shields.io/badge/version-1.15.1-3a1220?style=flat-square" alt="version 1.15.1"/>
  <img src="https://img.shields.io/badge/licence-MIT-3a1220?style=flat-square" alt="licence MIT"/>
</p>

<img src="docs/gallery/brisk_walk.png" width="108"/>
<img src="docs/gallery/yoga.png" width="108"/>
<img src="docs/gallery/plank.png" width="108"/>
<img src="docs/gallery/stretching.png" width="108"/>
<img src="docs/gallery/bike.png" width="108"/>
<img src="docs/gallery/dance.png" width="108"/>

<sub>Nivelito, petit panda roux, fait chaque exercice avec toi.</sub>

</div>

---

## L'idée

On logge ses repas en quelques secondes, on suit ses pas et son poids, on valide de petites activités physiques, et on gagne de l'XP, des niveaux, des quêtes et des badges.

**Zéro pression, c'est la règle du jeu :** pas de rouge, pas de streak à ne pas casser, pas de reproche. Un jour « raté » n'existe pas. Nivelito encourage, il ne juge jamais.

## Ce qu'il y a dedans

| | |
|---|---|
| 🍲 **Repas en 3 gestes** | Catalogue de 153 aliments (plats composés, ingrédients, boissons, encas, desserts) et 35 recettes de saison, estimation kcal immédiate, détail à l'ingrédient et au gramme si on le veut, kcal saisies à la main sinon. Objectif calculé (Mifflin-St Jeor moins 350). |
| 🏃 **Sport tout doux** | 32 activités et 11 séances composées, chacune illustrée par Nivelito, avec consignes « comment faire » et rythme suggéré. |
| ⏱️ **Séance du jour guidée** | Une étape par écran, un timer en anneau **optionnel** qu'on lance si on veut. Jamais d'avance automatique : un guide, pas un chef. |
| 🏆 **XP, niveaux, quêtes, badges** | 25 quêtes hebdo tirées le lundi, 38 badges, progression visible sans jamais de score négatif. |
| 🧺 **Idées de saison** | Trois idées de repas légers par jour, classées selon ce qu'on a coché dans le frigo. 35 recettes, préparation en trois ou quatre lignes, loggeables en un geste. |
| 🔥 **Dépense du jour** | Un anneau concentrique sur l'accueil : pas et sport, à côté de ce qui a été mangé. Indicatif, jamais crédité au budget alimentaire. |
| 📈 **Progrès honnêtes** | Pas quotidiens (HealthKit), tendance de poids lissée, historique. |
| 🐼 **Nivelito** | 208 messages préécrits, une phrase adaptée au moment de la journée, micro-gestes d'idle, expression contextuelle. |
| 📱 **Widgets** | Écran d'accueil et écran verrouillé, une nouvelle phrase **chaque heure**, raccourci « logger un repas » en un geste. |
| 🎨 **4 thèmes** | Crème, Menthe, Océan, Nuit douce. Réglable par téléphone. |
| 💞 **Duo** | Voir la journée de l'autre, et lui envoyer un cœur. Partagés : prénom, avatar, niveau et XP, l'anneau du jour, les pas, la quête en cours, les repas et activités du jour. **Jamais partagés : le poids, la courbe de poids, les badges.** Aucun classement, aucun texte libre : un cœur, et c'est tout. |
| 🔒 **Local par défaut** | Aucun compte, aucun serveur, aucun tracking. **Sans duo appairé, rien ne sort de l'iPhone** : pas une requête n'est émise, et c'est l'état par défaut. Dès qu'un duo existe, la journée décrite ci-dessus part dans une zone iCloud privée partagée avec cette personne et personne d'autre. Toujours aucun serveur à nous. |

Cinq onglets : **Accueil · Repas · Sport · Progrès · Quêtes**. Les réglages sont derrière le ⚙️ en haut de l'accueil, et le duo, quand il y en a un, derrière l'avatar posé juste à côté.

## Captures

<div align="center">

| <img src="docs/appstore/raw/01-home.png" alt="L'accueil de Nivel" width="200"/> | <img src="docs/appstore/raw/02-meallog.png" alt="Le catalogue d'aliments" width="200"/> | <img src="docs/appstore/raw/05-step.png" alt="Une étape guidée de la séance du jour" width="200"/> | <img src="docs/appstore/raw/07-quests.png" alt="Quêtes et badges" width="200"/> |
|:---:|:---:|:---:|:---:|
| L'accueil. | Les repas. | La séance guidée. | Quêtes et badges. |

| <img src="docs/captures/appicon-256.png" alt="Icône de l'app Nivel" width="190"/> | <img src="docs/captures/splash.png" alt="Écran de démarrage de Nivel" width="215"/> | <img src="design/icons/contact-sheet.png" alt="Les 49 icônes cozy" width="400"/> |
|:---:|:---:|:---:|
| L'icône de l'app. | L'écran de démarrage. | Les 49 icônes cozy, dessinées à la main en CoreGraphics. |

</div>

<sub>Captures reproductibles avec <code>./scripts/screenshots.sh</code> (profil de démonstration, mode DEBUG).</sub>

## Architecture

```
┌─ NivelCore/ ────────────────┐   Package Swift PUR (zéro dépendance UI, zéro SwiftData)
│  calories · XP · niveaux    │   Calculs, catalogues JSON, banque de messages,
│  quêtes · badges · tendance │   rotation de la séance du jour, planner de timeline.
│  messages · planner widget  │  329 tests, `swift test` en 0,2 s.
└─────────────┬───────────────┘
              │
    ┌─────────┴─────────┐
┌───▼──────────┐  ┌─────▼─────────┐
│ App/         │  │ Widgets/      │   Extension WidgetKit, 4 familles.
│ SwiftUI +    │  │               │
│ SwiftData    │  └─────┬─────────┘
└───┬──────────┘        │
    └────────┬──────────┘
        ┌────▼────┐
        │ Shared/ │   Compilé dans les DEUX targets : palettes, formes de
        └─────────┘   Nivelito, pont App Group (`group.com.elitedangereuse.nivel.data`).
```

- **Le magasin local n'est jamais synchronisé.** Deux installations indépendantes (un iPhone chacun), deux bases séparées, rien n'est miroité. La « séance du jour » est identique sur les deux téléphones parce qu'elle est calculée de façon déterministe à partir de la date, pas partagée par un serveur.
- **Le duo (1.15) ne change pas ça, il publie à côté.** Quand un duo est appairé, l'app dépose un petit instantané de la journée dans une zone iCloud partagée entre les deux personnes (conteneur `iCloud.com.elitedangereuse.Nivel`), exactement comme `syncWidget()` dépose le sien dans l'App Group depuis la v1.6. La zone est décomptée sur le stockage iCloud de celui qui invite ; il n'y a de serveur à nous nulle part. Sans duo appairé, aucune requête n'est émise et l'app se comporte comme la 1.14.
- **Le projet Xcode est généré** par [XcodeGen](https://github.com/yonaskolb/XcodeGen) depuis `project.yml`. Ne jamais éditer le `.xcodeproj` à la main : relancer `xcodegen generate`.

## Commandes

```sh
# Générer le projet Xcode (après clone, ou après modification de project.yml)
xcodegen generate

# Tests de la logique pure
cd NivelCore && swift test

# Tests d'intégration de l'app (SwiftData, services) sur simulateur
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Tests d'INTERFACE du panier de repas — hors du schéma quotidien (~2,5 s par geste),
# à lancer à la main après avoir touché MealBasketView ou SwipeToDeleteRow (v1.13 §7.3)
xcodebuild -project Nivel.xcodeproj -scheme NivelPreview \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:NivelUITests/BasketSwipeTests test

# Régénérer les assets sport (App/Assets.xcassets/Sport) depuis design/sport/*.png
./scripts/import-sport-images.sh

# Régénérer les avatars de profil (App/Assets.xcassets/Avatars) depuis design/icons/{boy,girl}.png
./scripts/import-avatars.sh

# Régénérer les illustrations des boutons d'action (App/Assets.xcassets/Buttons)
./scripts/import-button-icons.sh

# Régénérer les icônes cozy (App/Assets.xcassets/Icons + planche-contact)
swift scripts/gen-icons.swift

# Régénérer les chimes du timer (App/Resources/Sounds)
swift scripts/gen-sounds.swift
```

## Publier sur l'App Store

L'app est signée par l'association **L'Élite Dangereuse** (team `AXVF69V3LL`, bundle id
`com.elitedangereuse.Nivel`, App Group `group.com.elitedangereuse.nivel.data`). Fiche,
captures et pages web vivent dans `docs/`.

```sh
# 1. Captures d'écran 6,9" habillées (docs/appstore/framed/) — à refaire quand l'UI bouge
./scripts/screenshots.sh

# 2. Clé API App Store Connect (une fois) : rôle « App Manager », clé d'équipe
#    ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 3. Archive + IPA signée + vérifications, sans envoi
./scripts/release.sh

# 4. Idem puis envoi à App Store Connect
./scripts/release.sh --upload

# 5. Remplir la fiche : version, textes, URLs, build rattachée, captures téléversées
python3 scripts/asc-fiche.py

# 6. Aperçus vidéo : deux visites guidées filmées sur simulateur, puis téléversées
./scripts/preview.sh
python3 scripts/asc-preview.py
```

Les aperçus vidéo sont tournés par la cible **NivelUITests** (schéma `NivelPreview`, hors du
schéma `Nivel` pour ne pas ralentir les tests de tous les jours) : elle promène l'app
pendant que `simctl` filme l'écran. Deux visites plutôt qu'une, parce qu'un aperçu Apple
dure 30 s au maximum et qu'un geste XCUITest coûte ~2,5 s. Le journal du tournage nomme
chaque geste manqué, et l'encodage (`scripts/encode-preview.swift`, AVFoundation, sans
dépendance) refuse de produire une vidéo hors des contraintes d'Apple.

`asc-fiche.py` lit ses textes dans `docs/appstore/fiche-app-store.md` — un texte ne se
recopie donc jamais à deux endroits. Il ne touche pas au questionnaire de confidentialité,
à la classification par âge, au prix ni aux territoires : ces quatre points se cochent dans
l'interface.

`release.sh` crée au besoin les deux profils App Store via l'API
(`scripts/asc-profiles.py`), puis **vérifie le binaire signé** : entitlements HealthKit,
App Group, conteneur iCloud du duo et `aps-environment` à `production`, certificat de
distribution, manifestes de confidentialité embarqués. Il refuse d'envoyer une IPA
incomplète, parce qu'un export mal fait perd les entitlements en silence.

Deux réglages de cette machine sont contournés dans les scripts et ne doivent pas être
« simplifiés » : la signature **manuelle** en Release (la team n'a aucun appareil
enregistré, donc aucun profil de développement possible) et le **PATH système** à l'export
(le rsync de Homebrew masque celui d'Apple et casse la fabrication de l'IPA).

Le texte de la fiche, les réponses au questionnaire de confidentialité et l'ordre des
captures sont dans [`docs/appstore/fiche-app-store.md`](docs/appstore/fiche-app-store.md).
Les pages publiques (accueil, confidentialité, assistance) sont servies par GitHub Pages
depuis le dossier `docs/`.

### Ce que la 1.15.1 demande à la main, avant de soumettre

Le duo est la première fonction de Nivel qui parle au réseau. Quatre choses en découlent,
qu'aucun script du dépôt ne fait ni ne vérifie. Tant qu'elles ne sont pas faites, la
version ne part pas.

1. **Ouvrir les capacités, puis régénérer le profil « Nivel App Store ».** Sur le portail
   développeur, l'App ID `com.elitedangereuse.Nivel` doit gagner **iCloud (CloudKit)** avec
   le conteneur `iCloud.com.elitedangereuse.Nivel` et **Push Notifications**. Relancer
   ensuite `python3 scripts/asc-profiles.py`, qui supprime et recrée un profil devenu
   invalide mais **n'ouvre aucune capacité de lui-même**. La Release signe en **manuel** :
   sans profil à jour, l'export laisse tomber les nouveaux entitlements sans un mot à la
   compilation, et l'app se casse à l'exécution, exactement comme elle perdait HealthKit et
   l'App Group avant la v1.6. Le filet est la vérification du binaire signé par
   `release.sh`, à lire jusqu'au bout.

2. **Créer le conteneur iCloud et pousser le schéma en production.** Dans le tableau de bord
   CloudKit : conteneur `iCloud.com.elitedangereuse.Nivel`, types `DuoMember`, `DuoLike` et
   `DuoLikeAlertSignal`,
   **index interrogeable sur `DuoLike.ownerID`** (le nettoyage des cœurs orphelins l'exige,
   et sans lui il échoue en silence, par conception), puis **Deploy Schema Changes** vers la
   production. Le schéma de développement ne migre pas tout seul : une version soumise sans
   ce déploiement donne un duo qui ne marche que sur les téléphones de développement.

3. **Savoir défendre la fiche de confidentialité.** Elle continue de déclarer qu'**aucune
   donnée n'est collectée**, y compris avec le duo : une base privée CloudKit ne rend rien
   accessible à l'éditeur, et c'est précisément ce qu'Apple appelle collecter. La position et
   ce qui la fonde, l'argument contraire, et la marche à suivre si un examinateur ne la suit
   pas, sont écrits dans
   [`docs/appstore/fiche-app-store.md`](docs/appstore/fiche-app-store.md) §3. **C'est le seul
   risque de rejet de cette version** : un pari raisonné, pas une certitude, que rien dans le
   dépôt ne peut vérifier à ta place.

4. **Vérifier sur les deux iPhones.** La liste complète est en
   [spec 1.15 §9](docs/superpowers/specs/2026-08-16-nivel-1.15-design.md) et elle s'est
   allongée à chaque lot ; les quatre à ne surtout pas sauter sont l'**appairage complet par
   QR**, la **suppression d'un repas aimé** (constater que le cœur disparaît vraiment chez
   l'autre est le seul moyen de distinguer un nettoyage qui marche d'un nettoyage qui échoue
   sans rien dire), les **cœurs de la veille toujours là le lendemain matin** (le seul
   scénario de la liste qui efface des données s'il retombe) et la **première publication
   côté invité** (une zone au `ownerName` faux accepte l'écriture, dans le vide, sans la
   moindre erreur).

Reste le geste habituel de fin de version, qui lui a son outil : écrire les notes de la 1.15.1
dans `docs/appstore/fiche-app-store.md`, puis lancer `python3 scripts/asc-fiche.py`.

Les captures, elles, ne sont pas à refaire : sans duo appairé, l'accueil est rigoureusement
celui de la 1.14, donc la série actuelle ne ment pas, elle montre l'app avant appairage.
Rejouer `./scripts/screenshots.sh` pour y faire figurer le bouton du duo et sa page est un
choix de vitrine, pas une correction.

## Installer sur ton iPhone (compte Apple gratuit)

Pas besoin de compte développeur payant, mais l'app **expire au bout de 7 jours** (voir l'encadré plus bas).

1. `xcodegen generate && open Nivel.xcodeproj`
2. Target **Nivel** → **Signing & Capabilities** → **Team** = ton Apple ID personnel.
   *Aucun compte dans la liste ? Xcode → **Settings…** → **Accounts** → **+**.*
3. Brancher l'iPhone en USB, accepter « Se fier à cet ordinateur » sur le téléphone.
4. Choisir l'iPhone comme destination en haut de la fenêtre Xcode, puis **⌘R**.
5. **Premier lancement uniquement :** l'iPhone bloque l'app. **Réglages → Général → VPN et gestion de l'appareil**, toucher le profil développeur, **faire confiance**, relancer.

> ⚠️ **À refaire tous les 7 jours.** Avec un compte gratuit, la signature expire au bout d'une semaine et l'app refuse de se lancer. Il suffit de rebrancher **chaque téléphone** et de refaire ⌘R (étapes 3 et 4). Le compte développeur payant (99 €/an) supprime cette limite.
>
> 📅 **Builder les deux téléphones depuis le même commit**, dans la même session, sans `git pull` entre les deux. La séance du jour est calculée à partir du catalogue embarqué : deux versions différentes peuvent afficher deux séances différentes le même jour.

**Deux utilisateurs, deux téléphones :** chacun choisit son profil à l'onboarding, sur son propre téléphone. Les données restent locales à chaque appareil, à l'exception de l'instantané du jour que publie le duo, si vous en appairez un (voir plus haut).

**Widgets :** appui long sur l'écran d'accueil → **+** → chercher « Nivel » (petit et moyen), ou personnaliser l'écran verrouillé pour les accessoires. Quand la signature expire, le widget se fige avec l'app ; le re-build hebdomadaire réveille les deux.

## Structure du projet

```
Nivel/
├── project.yml              # Définition XcodeGen (Nivel + NivelWidgets + NivelTests)
├── NivelCore/               # Package Swift : logique métier pure + tests unitaires
│   ├── Sources/NivelCore/   #   Calories, XP, niveaux, quêtes, badges, tendance de poids,
│   │                        #   catalogues JSON (aliments, compositions, recettes, activités, séances, posture, muscu, messages)
│   └── Tests/               #   `swift test`
├── App/                     # App SwiftUI + SwiftData
│   ├── Models/              #   Modèles persistés (profil, repas, pesées, journal)
│   ├── Services/            #   GameService, HealthKit, notifications, clôture de journée
│   ├── Views/               #   Accueil, repas, sport, progrès, quêtes, réglages, onboarding
│   ├── Nivelito/            #   La mascotte : formes vectorielles, bulles, micro-gestes
│   └── Assets.xcassets/     #   Icône d'app, couleurs, illustrations sport, icônes cozy
├── Shared/                  # Compilé dans l'app ET le widget (palettes, Nivelito, App Group)
├── Widgets/                 # Extension WidgetKit (provider, vues des 4 familles)
├── NivelTests/              # Tests d'intégration de l'app (simulateur)
├── design/                  # Sources : SVG (Nivelito, icône), sport/ (PNG 1254 px), icons/
├── scripts/                 # import-sport-images.sh, import-avatars.sh, gen-icons.swift, gen-sounds.swift
└── docs/                    # Specs, plans d'implémentation, captures
```

## Palette

| | Crème | Pêche | Orange Nivelito | Bordeaux |
|---|---|---|---|---|
| | `#fdf6ec` | `#f9e8d8` | `#f57c1f` | `#3a1220` |

## Licence

[MIT](LICENSE). Projet personnel, construit pour deux personnes et leur panda roux.
</content>
