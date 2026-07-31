# Nivel — Spécification Icônes cozy (v1.7)

Date : 2026-07-31
Statut : validé avec Michaël (démo visuelle du 31/07/2026, option A : contour dodu, rempli quand sélectionné)
Référence : style validé dans la démo `tabbar-icons.html` (companion visuel). Aucun tiret cadratin dans les textes.

## 1. Vision

Remplacer les SF Symbols **d'identité** par des glyphes dessinés dans le langage de Nivelito : contours épais (~2,4pt à l'échelle 28) à bouts ronds, formes dodues. L'onglet actif de la tab bar passe en silhouette **remplie**. Deux métaphores changent au passage (validées en démo) : **bol fumant** pour Repas, **pousse** pour Progrès. Le mobilier utilitaire iOS reste natif.

## 2. Périmètre : les 15 glyphes

| Nom d'asset | Glyphe | Variante | Remplace | Usages |
|---|---|---|---|---|
| `tab_home` / `tab_home_fill` | Maison dodue (porte arrondie) | contour + rempli | `house.fill` | Tab bar Accueil |
| `tab_meals` / `tab_meals_fill` | Bol fumant | contour + rempli | `fork.knife` | Tab bar Repas |
| `tab_sport` / `tab_sport_fill` | Haltère à bouts ronds | contour + rempli | `figure.walk` | Tab bar Sport |
| `tab_progress` / `tab_progress_fill` | Pousse (2 feuilles + sol) | contour + rempli | `chart.line.uptrend.xyaxis` | Tab bar Progrès |
| `tab_quests` / `tab_quests_fill` | Trophée joufflu | contour + rempli | `trophy.fill` | Tab bar Quêtes |
| `icon_settings` | Engrenage dodu | contour | `gearshape.fill` | ⚙️ accueil (HomeView) |
| `icon_check` | Sceau de validation rond | rempli | `checkmark.circle.fill` | « Faite ! », « Déjà faite » et autres coches (5 usages) |
| `icon_play` | Triangle play dodu | rempli | `play.fill` | Timer : Lancer, Reprendre |
| `icon_pause` | Deux barres rondes | rempli | `pause.fill` | Timer : Pause |
| `icon_restart` | Flèche circulaire dodue | contour | `arrow.counterclockwise` | Timer : Recommencer |

**Restent en SF Symbols (volontaire)** : chevrons de navigation, `trash` des swipes, `plus/minus.circle.fill` des steppers, `sparkles`/`sparkle` des célébrations. Utilitaire = natif (familiarité, accessibilité). Les **widgets** (v1.6) ne sont pas touchés.

## 3. Sources et pipeline

- **Sources de vérité** : les tracés validés en démo sont **committés en SVG** dans `design/icons/*.svg` (un fichier par glyphe, viewBox 28×28) — même convention que `design/nivelito.svg`.
- **Générateur** : `scripts/gen-icons.swift` (CoreGraphics pur, exécuté via `swift scripts/gen-icons.swift`, zéro dépendance) : les 15 glyphes y sont définis en `CGPath` (traduction fidèle des SVG — les arcs SVG deviennent des arcs/béziers CG), rendus en **PDF vectoriels** dans `App/Assets.xcassets/Icons/` (dossier à namespace).
- **Imagesets** : universal, single scale, `preserves-vector-representation: true`, `template-rendering-intent: template` — les icônes se teintent automatiquement (orange/taupe, les 4 palettes suivent) et scalent proprement.
- Le script est **idempotent et régénérable** (philosophie `import-sport-images.sh`) ; il refuse de tourner si sa liste interne et les SVG de `design/icons/` divergent (garde de synchronisation, noms exacts).

## 4. Intégration

- **`RootView.MainTabView`** : chaque `tabItem` devient `Label("Accueil", image: selectedTab == .home ? "Icons/tab_home_fill" : "Icons/tab_home")` (le body se ré-évalue à chaque changement de sélection — pattern standard). Idem pour les 5 onglets.
- **`HomeView`** : `Image(systemName: "gearshape.fill")` → `Image("Icons/icon_settings")` (mêmes modifiers).
- **Coches** : les 5 `checkmark.circle.fill` → `Image("Icons/icon_check")` (dans les `Label`, la partie texte ne change pas).
- **Timer (`TimerRingView.TimerButtons`)** : `Label(..., systemImage:)` → `Label(..., image:)` avec `icon_play`/`icon_pause`/`icon_restart`.
- Les `Label` gardent leurs textes : rien ne change pour VoiceOver.

## 5. Ce qui ne change PAS

Aucune logique, aucun modèle, aucun test métier. Chevrons/trash/steppers/sparkles restent SF. Widgets intouchés.

## 6. Tests

- `NivelTests/IconAssetsTests.swift` : pour chacun des 15 noms (liste pinnée), `UIImage(named: "Icons/<nom>")` non nil ; et vérification que le rendu est template (`renderingMode`) si accessible, sinon présence seule.
- Vérification visuelle simulateur : tab bar (état sélectionné rempli, teintes sur les 4 palettes), ⚙️, coches, boutons du timer.

## 7. Points d'attention

- **Taille tab bar** : glyphes dessinés plein cadre 28×28 ; iOS affiche ~25pt — vérifier l'équilibre optique entre les 5 (la pousse et l'haltère sont plus « légers » que la maison, ajuster les épaisseurs si besoin au simulateur).
- **PDF template** : bien poser `template-rendering-intent` dans le Contents.json, sinon les PDF s'affichent en noir.
- **Le switch contour/rempli au tap** doit être instantané (pas d'animation nécessaire, le cross-fade natif de la tab bar suffit).
