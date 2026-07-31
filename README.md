# Nivel

<p align="center">
  <img src="design/appicon.svg" alt="Nivelito, la mascotte de Nivel" width="160"/>
</p>

**Nivel** est une app iOS de perte de poids **gamifiée et zéro pression** : on logge ses repas en quelques secondes, on suit ses pas et son poids, on valide de petites activités physiques (marche, étirements, gainage… et la « séance du jour », la même sur les deux téléphones), et on gagne de l'XP, des niveaux, des quêtes et des badges — sans jamais de rouge, de culpabilité ni d'échec. Un jour "raté" n'existe pas : Nivel encourage, il ne juge pas.

Chaque sport est **illustré par Nivelito en action**, et la séance du jour se suit en **mode pas-à-pas guidé** : une étape par écran, avec les consignes (« comment faire »), un rythme suggéré et un **timer optionnel** qu'on lance si on veut (jamais imposé, jamais d'avance automatique) — un guide, pas un chef.

Cinq onglets : **Accueil · Repas · Sport · Progrès · Quêtes** — les Réglages sont accessibles via le bouton ⚙️ en haut de l'accueil.

L'essentiel de la journée (anneau calories, niveau, un mot de Nivelito) reste visible sans ouvrir l'app grâce à des **widgets** sur l'écran d'accueil et l'écran verrouillé, avec un raccourci pour logger un repas en un geste.

Le tout est accompagné de **Nivelito**, un petit panda roux qui commente la journée avec bienveillance (et qui sert d'icône à l'app).

## Captures

| <img src="docs/captures/appicon-256.png" alt="Icône de l'app Nivel" width="200"/> | <img src="docs/captures/splash.png" alt="Écran de démarrage de Nivel" width="220"/> |
|:---:|:---:|
| L'icône de l'app : Nivelito sur fond crème. | L'écran de démarrage, avec Nivelito qui t'accueille. |

*(davantage de captures après installation sur iPhone)*

## Architecture

- **`NivelCore/`** — package Swift **pur** (aucune dépendance UI ni SwiftData) : calculs de calories, XP, niveaux, quêtes, badges, tendance de poids, banque de messages. Entièrement testé avec `swift test`.
- **`App/`** — l'app **SwiftUI + SwiftData** : vues, services (HealthKit, notifications, clôture de journée, GameService), thème, Nivelito.
- Le projet Xcode est **généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)** à partir de `project.yml` : ne pas éditer le `.xcodeproj` à la main, relancer `xcodegen generate` après toute modification de `project.yml`.

## Commandes

```sh
# Générer le projet Xcode (après clone ou modification de project.yml)
xcodegen generate

# Tests de la logique pure (NivelCore)
cd NivelCore && swift test

# Tests de l'app (SwiftData, services) sur simulateur
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Régénérer les assets sport (App/Assets.xcassets/Sport) depuis design/sport/*.png
./scripts/import-sport-images.sh

# Régénérer les icônes cozy (App/Assets.xcassets/Icons + design/icons/contact-sheet.png)
swift scripts/gen-icons.swift
```

## Installer Nivel sur ton iPhone (compte Apple gratuit)

Pas besoin de compte développeur payant — mais l'app **expire au bout de 7 jours** (voir plus bas).

1. Générer et ouvrir le projet : `xcodegen generate && open Nivel.xcodeproj`.
2. Dans Xcode, sélectionner la target **Nivel** → onglet **Signing & Capabilities** → **Team** = ton Apple ID personnel.
   *Si aucun compte n'apparaît : Xcode → **Settings…** → **Accounts** → **+** → ajouter ton Apple ID.*
3. Brancher l'iPhone en USB (accepter "Se fier à cet ordinateur" sur le téléphone si demandé).
4. Sélectionner l'iPhone comme **destination** en haut de la fenêtre Xcode, puis **⌘R**.
5. **Premier lancement uniquement** : l'iPhone bloque l'app. Aller dans **Réglages → Général → VPN et gestion de l'appareil**, toucher ton profil développeur et **faire confiance**. Relancer l'app.

> ⚠️ **À refaire TOUS LES 7 JOURS** : avec un compte gratuit, la signature expire au bout d'une semaine — l'app refuse alors de se lancer. Il suffit de rebrancher **chaque téléphone** et de refaire ⌘R (étapes 3-4). Si c'est trop contraignant à l'usage, le compte développeur payant (99 €/an) supprime cette limite.
>
> 📅 Builder les deux téléphones **depuis le même commit** (dans la même session, sans `git pull` entre les deux) : la « séance du jour » est calculée à partir du catalogue embarqué — deux versions différentes peuvent afficher deux séances différentes le même jour.

**Deux utilisateurs, deux téléphones** : chacun (Michaël / Marion) choisit **son profil à l'onboarding sur SON téléphone**. Les données restent locales à chaque appareil.

**Widgets** : après installation, appui long sur l'écran d'accueil → **+** → chercher « Nivel » (petit et moyen), ou personnaliser l'écran verrouillé pour les accessoires. Quand la signature expire (7 jours, compte gratuit), le widget se fige avec l'app — le re-build hebdomadaire réveille les deux.

## Structure du projet

```
Nivel/
├── project.yml              # Définition XcodeGen (targets Nivel + NivelTests + NivelWidgets)
├── NivelCore/               # Package Swift : logique métier pure + tests unitaires
│   ├── Sources/NivelCore/   #   Calories, XP, niveaux, quêtes, badges, tendance poids,
│   │                        #   catalogues JSON (plats, extras, activités, séances…)
│   └── Tests/               #   `swift test`
├── App/                     # App SwiftUI + SwiftData
│   ├── Models/              #   Modèles persistés (profil, repas, pesées, journal…)
│   ├── Services/            #   GameService, HealthKit, notifications, clôture de journée
│   ├── Views/               #   Accueil, repas, sport, progrès, quêtes, réglages, onboarding…
│   ├── Nivelito/            #   La mascotte (formes vectorielles, bulles de dialogue)
│   └── Assets.xcassets/     #   Icône d'app, couleurs, illustrations sport (Sport/) et
│                            #   icônes cozy (Icons/, PDF template) — toutes générées
├── Shared/                  # Code compilé dans l'app ET le widget (palettes, formes Nivelito, pont App Group)
├── Widgets/                 # Extension WidgetKit (provider, vues des 4 familles)
├── NivelTests/              # Tests d'intégration de l'app (simulateur)
├── design/                  # Sources : SVG (Nivelito, icône), sport/ (PNG 1254px), icons/ (planche-contact)
├── scripts/                 # import-sport-images.sh + gen-icons.swift (assets régénérables)
└── docs/                    # Spec et plan d'implémentation
```
