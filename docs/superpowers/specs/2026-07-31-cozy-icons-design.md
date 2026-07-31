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
| `icon_check` | Sceau de validation rond | rempli | `checkmark.circle.fill` | Les 5 usages « badge/statut » : DailySessionCard, SessionPlayerSheet, badge de thème (Settings), badge de quête complétée (Quêtes), badge de permission (Onboarding). ⚠️ Le 6ᵉ usage (OnboardingFlow, radio de sélection `checkmark.circle.fill`/`circle`) reste en SF : c'est un contrôle de formulaire, pas un badge — le passer en cozy créerait un clash avec son état vide natif. |
| `icon_play` | Triangle play dodu | rempli | `play.fill` | Timer : Lancer, Reprendre |
| `icon_pause` | Deux barres rondes | rempli | `pause.fill` | Timer : Pause |
| `icon_restart` | Flèche circulaire dodue | contour | `arrow.counterclockwise` | Timer : Recommencer |

**Restent en SF Symbols (volontaire)** : chevrons de navigation, `trash` des swipes, `plus/minus.circle.fill` des steppers, `sparkles`/`sparkle` des célébrations (décoratifs, vérifiés), et le radio de sélection de l'onboarding (voir table). Utilitaire = natif (familiarité, accessibilité). Les **widgets** (v1.6) ne sont pas touchés.

## 3. Sources et pipeline

- **Source de vérité UNIQUE** : `scripts/gen-icons.swift` (CoreGraphics pur, exécuté via `swift scripts/gen-icons.swift`, zéro dépendance) : les 15 glyphes y sont définis en primitives CG (arcs, béziers, rects arrondis — traduction fidèle des tracés validés en démo), canvas 28×28.
- **Sorties générées** (les DEUX à chaque run ; contenu déterministe — les PDF portent des métadonnées de date Quartz, seuls artefacts variables entre deux runs, contrairement à `import-sport-images.sh` qui est byte-idempotent) :
  1. **PDF vectoriels** dans `App/Assets.xcassets/Icons/` (dossier à namespace) — imagesets universal, single scale, `preserves-vector-representation: true`, `template-rendering-intent: template` : teinte automatique (orange/taupe, les 4 palettes suivent), scaling propre ;
  2. **Exports de référence** dans `design/icons/` : une planche-contact PNG (`contact-sheet.png`, chaque glyphe à 25pt et 50pt) pour la relecture visuelle — c'est l'outil du contrôle qualité avant intégration.
- Un seul endroit à éditer pour retoucher un glyphe ; pas de double maintenance SVG↔code.

## 4. Intégration

- **`RootView.MainTabView`** : chaque `tabItem` devient `Label("Accueil", image: selectedTab == .home ? "Icons/tab_home_fill" : "Icons/tab_home")` (le body se ré-évalue à chaque changement de sélection — pattern standard). Idem pour les 5 onglets.
- **`HomeView`** et tous les sites hors tab bar : via le composant **`CozyIcon(name:size:)`** — un asset PDF IGNORE `.font()` (contrairement à un SF Symbol), la taille est donc explicite (size ≈ encre voulue / 0,76), et `Image(decorative:)` évite que VoiceOver annonce l'id d'asset.
- **Coches** : les 5 `checkmark.circle.fill` → `CozyIcon(name: "icon_check", size: ...)` (dans les `Label`, via le builder `Label { Text } icon: { CozyIcon }` — le texte a11y ne change pas).
- **Timer (`TimerRingView.TimerButtons`)** : `Label { Text } icon: { CozyIcon(...) }` avec `icon_play`/`icon_pause`/`icon_restart` (size 20).
- Les `Label` gardent leurs textes ; les icônes sont `decorative` : VoiceOver lit les textes, jamais les ids d'assets.

## 5. Ce qui ne change PAS

Aucune logique, aucun modèle, aucun test métier. Chevrons/trash/steppers/sparkles restent SF. Widgets intouchés.

## 6. Tests

- `NivelTests/IconAssetsTests.swift` : pour chacun des 15 noms (liste pinnée), `UIImage(named: "Icons/<nom>")` non nil ; et vérification que le rendu est template (`renderingMode`) si accessible, sinon présence seule.
- Vérification visuelle simulateur : tab bar (état sélectionné rempli, teintes sur les 4 palettes), ⚙️, coches, boutons du timer.

## 7. Points d'attention

- **Taille tab bar** : glyphes dessinés sur canvas 28×28 (~76 % d'encre, ~3,5pt de marge par bord) ; iOS affiche ~25pt — vérifier l'équilibre optique entre les 5 (la pousse et l'haltère sont plus « légers » que la maison, ajuster les épaisseurs si besoin au simulateur).
- **PDF template** : bien poser `template-rendering-intent` dans le Contents.json, sinon les PDF s'affichent en noir. Ce sont les PREMIERS imagesets PDF template du catalogue (Sport/ = JPEG) : valider UN glyphe à 25pt au simulateur (teinte, netteté) avant de générer les 15.
- **Le switch contour/rempli au tap** doit être instantané (pas d'animation nécessaire, le cross-fade natif de la tab bar suffit).
