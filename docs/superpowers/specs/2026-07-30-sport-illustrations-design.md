# Nivel — Spécification Illustrations Sport & Séances guidées (v1.3)

Date : 2026-07-30
Statut : validé avec Michaël (brainstorming du 30/07/2026, maquettes visuelles)
Référence : étend la section Sport (`2026-07-30-sport-section-design.md`). Mêmes principes non négociables (zéro culpabilisation, simplicité, tout en local).

## 1. Vision

Donner un visage aux sports : chaque activité et chaque séance est illustrée par une image de **Nivelito en action** (20 images générées par IA, validées, style cohérent avec la mascotte — `design/sport/*.png`). Et transformer la séance du jour en **mini-guide pas-à-pas** : une étape par écran, grande illustration, consignes concrètes et rythme suggéré — on sait quoi faire et comment, sans jamais être fliqué.

## 2. Décisions validées (brainstorming)

- **Illustrations** : images IA générées par Michaël (Nivelito en action, 1254×1254, fonds crème), déjà présentes dans `design/sport/` — 12 activités + 8 séances, nommées `<id>.png`.
- **Fallback** : si un asset manque, retomber automatiquement sur l'emoji en pastille colorée (rendu actuel) — l'app ne dépend jamais d'une image.
- **Directives** : consignes simples (3-4 puces par activité : position, mouvement, repère sécurité/respiration) + **rythme suggéré par étape de séance** (« ~10 squats tranquilles × 3, avec des pauses »). Jamais de programme rigide (séries×reps chronométrées) — esprit zéro pression. Formulations neutres (pas de points médians, décision v1.1).
- **Présentation** : **mode pas-à-pas** (option B des maquettes) — pager horizontal, une étape par écran, grande illustration visible pendant l'exercice.
- **Sur le thème sombre « Nuit douce »** : les fonds crème des images ressortent comme des vignettes claires — assumé (comme des photos).

## 3. Assets et intégration

- **Pipeline** : les sources 1254px restent dans `design/sport/` (non embarquées). Chaque image est redimensionnée en **JPEG 750×750, qualité ~80** (~100-150 Ko ; `sips -Z 750 -s format jpeg -s formatOptions 80`) et intégrée dans `App/Assets.xcassets` sous un **dossier `Sport` avec namespace activé** → `Image("Sport/walk")`, `Image("Sport/wake_up")`… Imagesets single-scale (universal). Poids total ajouté à l'app : ~2,5 Mo.
- **Composant `SportIllustration`** (`App/Views/Sport/SportIllustration.swift`) : affiche l'image `Sport/<name>` avec coins arrondis et taille paramétrable ; si `UIImage(named:)` est nil → **fallback emoji en pastille colorée** (l'emoji et la couleur sont passés en paramètres). Un seul point de vérité pour toutes les vignettes sport.
- Aucun changement de modèle persisté : les images sont référencées par les ids existants (`Activity.id`, `ActivitySession.id`).

## 4. Catalogues NivelCore — consignes et rythmes

### 4.1 `Activity.instructions: [String]` (nouveau champ requis)

3-4 puces par activité, ton Nivelito, formulations neutres. Contenu validé :

| id | instructions |
|---|---|
| walk | Garde le dos droit, les épaules relâchées · Marche d'un bon pas, les bras balancent naturellement · Respire régulièrement, la conversation doit rester possible |
| brisk_walk | Accélère le pas jusqu'à sentir le souffle monter · Les bras accompagnent, coudes pliés · Garde une foulée confortable, vitesse ne veut pas dire course |
| bike | Règle la selle : jambe presque tendue en bas de pédale · Pédale à un rythme régulier, sans forcer · Change de vitesse plutôt que de forcer sur les jambes |
| stairs | Monte marche par marche, pose tout le pied · Aide-toi de la rampe si besoin · Redescends tranquillement, la descente compte aussi · Fais une pause dès que les jambes brûlent trop |
| dance | Mets ta musique préférée, personne ne regarde · Bouge tout : bras, hanches, tête · Un léger essoufflement est bon signe, amuse-toi |
| stretching | Étire-toi lentement, sans à-coups · Tiens chaque position environ 30 secondes · La tension doit rester agréable, jamais de douleur · Respire profondément pendant l'étirement |
| plank | Avant-bras au sol, coudes sous les épaules · Corps aligné des épaules aux talons · Serre le ventre, ne creuse pas le dos · Pose les genoux quand ça tremble trop, c'est normal |
| squats | Pieds écartés largeur d'épaules · Descends comme pour t'asseoir sur une chaise · Le dos reste droit, les talons au sol · Remonte en poussant dans les talons |
| wall_pushups | Face au mur, mains à plat largeur d'épaules · Recule d'un pas, corps bien aligné · Plie les coudes pour approcher le mur, puis repousse · Plus les pieds sont loin du mur, plus c'est intense |
| active_cleaning | Mets de la musique et accélère le mouvement · Alterne les tâches pour faire bouger tout le corps · Plie les genoux pour ramasser, pas le dos |
| yoga | Installe-toi au calme, sur un tapis si possible · Enchaîne des postures simples, tenues quelques respirations · Concentre-toi sur une respiration lente et profonde · Ne force jamais une posture |
| digestive_walk | Pars tranquillement, 10 à 20 minutes après le repas · Rythme doux : c'est une balade, pas une marche sportive · Profites-en pour prendre l'air et souffler |

### 4.2 `SessionStep.tempo: String` (nouveau champ requis)

Le rythme suggéré de chaque étape, affiché en badge dans le player. Contenu validé :

| Séance | Étape | tempo |
|---|---|---|
| wake_up | stretching 4 min | ~30 s par position : bras, nuque, dos, jambes |
| wake_up | squats 4 min | ~10 squats tranquilles × 3, avec des pauses |
| wake_up | plank 3 min | 3 × ~30 s, repos entre chaque, genoux posés si besoin |
| energy_break | stairs 5 min | Monte et descends à ton rythme, pause à mi-parcours |
| energy_break | dance 5 min | 2-3 morceaux, lâche-toi ! |
| energy_break | stretching 3 min | Jambes et dos, ~30 s par étirement |
| evening_wind_down | yoga 8 min | 3-4 postures douces, tenues 4-5 respirations |
| evening_wind_down | stretching 5 min | Étirements lents, ~40 s chacun, pour préparer la nuit |
| quick_tone | squats 4 min | ~10 squats × 3, la dernière série plus lente |
| quick_tone | wall_pushups 4 min | ~8 pompes × 3, coudes près du corps |
| quick_tone | plank 4 min | 4 × ~30 s, souffle régulier |
| fresh_air | walk 15 min | Un tour de quartier d'un bon pas, en respirant à fond |
| mood_boost | dance 10 min | 3-4 morceaux qui font du bien, sans retenue |
| mood_boost | stretching 4 min | Redescends en douceur, ~30 s par étirement |
| zen_core | yoga 6 min | 2-3 postures d'équilibre, 5 respirations chacune |
| zen_core | plank 4 min | 3 × ~40 s, concentration sur la respiration |
| zen_core | stretching 4 min | Dos et épaules, lentement |
| home_cardio | stairs 6 min | 3 allers-retours, pause entre chaque |
| home_cardio | squats 3 min | ~10 squats × 2, bien poussés dans les talons |
| home_cardio | stretching 4 min | Jambes surtout : mollets, cuisses, ~30 s chacun |

Les deux champs sont **requis** (pas d'optionnel) : les catalogues sont livrés avec l'app, les tests garantissent qu'aucun n'est vide. Les champs `emoji` existants restent (fallback + rétrocompatibilité visuelle).

## 5. UI

### 5.1 `SessionPlayerSheet` (remplace `SessionDetailSheet`)

Pager horizontal (`TabView(.page)` ou équivalent) avec points de progression :

- **Page 0 — aperçu** : grande image héro de la séance (`Sport/<session.id>` — pleine largeur, carrée, coins arrondis, hauteur plafonnée ~280pt), titre, « X min · ~Y kcal », liste résumée des étapes (vignette 40pt + nom + durée), bouton « **C'est parti !** » (avance à la page 1). Si la séance est déjà faite aujourd'hui : état ✓ « Déjà faite » à la place du bouton — on peut quand même feuilleter les étapes (consultation libre).
- **Pages 1..n — une par étape** : grande illustration de l'activité (`Sport/<activityID>`, même gabarit que la héro), nom + « Étape i/n · X min », les puces `instructions` de l'activité, badge `tempo` de l'étape, bouton « **Étape suivante →** ».
- Navigation **libre** (swipe avant/arrière autorisé) : c'est un guide, pas un chrono. Pas de timer.
- La logique « page courante + état done → libellé/action du bouton » est extraite en **fonction pure testable** (`SessionPlayerSheet.buttonState(...)`), avec ce contrat EXHAUSTIF :

| Page | done | Bouton |
|---|---|---|
| 0 (aperçu) | non | « C'est parti ! » → avance à la page 1 |
| 0 (aperçu) | oui | état ✓ « Déjà faite » (pas d'action ; feuilletage libre) |
| étape i < n | — | « Étape suivante → » → page i+1 |
| étape n | non | « C'est fait ! (+40 XP) » → `logDailySession`, dismiss |
| étape n | oui | état ✓ « Déjà faite » (pas de re-validation) |

- **Pourquoi la promesse « +40 XP » est toujours honnête quand `done` est faux** (vérifié en review contre `GameService+Sport`) : `done` compte TOUTES les entrées séance du jour, le plafond XP ne compte que celles avec `xpAwarded > 0` — un sous-ensemble. `done == false` implique donc mathématiquement 0 entrée, donc plafond libre, donc 40 XP. La suppression (`deleteActivity`) efface l'entrée entière et libère le plafond (comportement assumé du pattern repas). **Aucune méthode `nextDailySessionXP()` n'est nécessaire** — contrairement aux activités libres (plafond 2/jour, où un état intermédiaire existe).
- Détents : `[.large]`, poignée visible.

### 5.2 `ActivityLogSheet` enrichie

Au-dessus du choix de durée : l'illustration de l'activité (moyenne, ~140pt, centrée) puis une section « **Comment faire** » (les puces `instructions`). Le choix de durée, le CTA (avec l'XP honnête existant) et la logique ne changent pas.

### 5.3 Vignettes partout

- **Lignes du catalogue Sport** et **« Fait aujourd'hui »** : la vignette 52pt arrondie (`SportIllustration`) remplace l'emoji seul.
- **Carte « Séance du jour »** (accueil + onglet Sport, `DailySessionCardContent`) : vignette héro 56pt à la place de l'emoji.
- Fallback emoji en pastille dans tous ces emplacements via `SportIllustration`.

## 6. Ce qui ne change PAS

Aucun modèle SwiftData, aucune règle XP/quêtes/badges, aucune notification, **aucun changement `GameService`** — le player appelle `logDailySession` et `dailySessionStatus` existants (voir §5.1 pour la preuve que `done` suffit au CTA honnête).

## 7. Tests

- **NivelCore** : décodage des catalogues enrichis — `instructions` non vides (12 activités), `tempo` non vide (toutes les étapes de toutes les séances) ; comptes inchangés.
- **App** : la fonction pure `buttonState` testée sur les 5 lignes du contrat du §5.1 ; smoke test existant inchangé.
- **Vérification visuelle** : les 20 assets présents dans le catalogue (un test app peut vérifier `UIImage(named: "Sport/<id>")` non nil pour chaque id des catalogues — garde anti-typo de nommage).

## 8. Hors périmètre

- Timer/chrono par étape, sons, haptiques de progression.
- Animations des illustrations.
- Images pour les repas, quêtes, badges.
- Régénération d'images dans l'app (tout est statique, embarqué).

## 9. Points d'attention

- **Poids de l'app** : +~2,5 Mo (20 JPEG 750px). Acceptable ; ne pas embarquer les PNG 1254px.
- **Nommage strict** : les assets DOIVENT porter exactement les ids des catalogues (le test §7 le garantit).
- **Nuit douce** : vignettes claires sur fond sombre — assumé.
- **`SessionDetailSheet` disparaît** au profit du player : l'encart accueil et l'onglet Sport pointent tous deux vers `SessionPlayerSheet`.
