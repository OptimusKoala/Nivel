# Nivel — Spécification Icônes cozy, vague 2 : catalogues (v1.10)

Date : 2026-08-02
Statut : validé avec Michaël (arbitrages du 02/08/2026, y compris ses retours après relecture au simulateur)
Prolonge : `2026-07-31-cozy-icons-design.md` (les 15 glyphes d'identité, tab bar et timer). Aucun tiret cadratin dans les textes.

## 1. Vision

La vague 1 a remplacé les SF Symbols d'identité par des glyphes cozy. Restaient les emoji des **catalogues de données** : badges, quêtes, thèmes, plus une poignée d'emoji posés en dur dans les vues. Cette vague les fait basculer dans le même langage graphique, avec deux exceptions assumées.

## 2. Ce qui bascule, ce qui reste

### 2.1 Bascule en cozy

| Site | Emplacements |
|---|---|
| Badges : grille de `QuestsView`, `BadgeDetailSheet`, bannière de `CelebrationsHost` | les 24 badges |
| Quêtes hebdo : `WeeklyQuestCard` (Quêtes et Accueil), bannière de célébration | 16 des 18 quêtes |
| Thèmes de `ThemePalette` (Réglages) | 4 |
| Vues en dur : en-têtes `SportView`, `StatCard`, repère de `StepsChart`, sous-titre de `CalorieRing`, état vide de `CaloriesChart` | 6 |
| Onboarding : 2 cartes de permission | 2 |

### 2.2 Reste en emoji, volontairement

- **La nourriture** (décision Michaël) : les 16 plats de `dishes.json` et les 6 extras d'`extras.json`. Un catalogue de plats est plus lisible en emoji : la couleur y porte l'information (une fraise rouge, une salade verte) et un glyphe monochrome de 28pt ne distingue pas 16 plats.
- **Deux quêtes thématiquement nourriture**, pour la même raison : `light_dessert_3` (🍎) et `light_dessert_5` (🍏). C'est ce qui impose le modèle mixte du §4.
- **La prose de Nivelito** : ~30 occurrences dans `messages.json` et les états vides (« Fait avec 🧡 », « ça arrive 😌 », « Salut {name} 👋 »). Un emoji au fil d'une phrase est de la typographie, pas une icône : une `CozyIcon` alignée sur la ligne de base casserait le rythme du texte.
- Les **commentaires de code** (11 lignes) : jamais rendus.

**Nuance sur 🍽️, tranchée après relecture** : l'assiette-et-couverts avait d'abord été rangée avec la nourriture, sur le badge `first_meal` comme dans les sous-titres. Michaël l'a trouvée « très étrange » à l'écran, et il a raison : le rendu Apple de 🍽️ est une assiette grise et froide, qui jure au milieu des glyphes teintés. Elle n'est d'ailleurs pas de la ponctuation affective comme 🧡 — c'est un repère « repas ». Elle bascule donc en cozy, et le remplacement dépend du SENS :

- **« un repas »** → le bol `tab_meals`. Un seul site : le sous-titre de `CalorieRing` (« Reste ~1 900 kcal »), qui parle de ce qu'il reste à manger.
- **« logger un repas »** → `icon_meal_log`, une **pomme et un crayon** (direction Michaël). C'est une action, pas un objet : le bol ne la disait pas, et le stylo nu qui servait à `log_meals_14` ne disait qu'« écrire ». Trois sites : badge `first_meal`, quête `log_meals_14`, état vide de `CaloriesChart` (« Logge tes repas pour voir ton historique ici »).

Dans le catalogue de plats, l'entrée « Autre » garde un emoji mais devient 🥘.

### 2.3 Nettoyage : les 31 emoji morts du sport

`activities.json` (20) et `sessions.json` (11) portaient un champ `emoji` qui ne s'affichait **jamais** : `SportIllustration` et `SportHeroIllustration` n'y retombent que si `UIImage(named: "Sport/<id>")` est nil, et les 31 ids ont tous leur imageset (vérifié : aucun id sans illustration, aucune illustration orpheline).

Le champ part donc d'`Activity` et d'`ActivitySession`, et le repli des deux vues devient une `CozyIcon(name: "tab_sport")` sur la pastille teintée existante. Le repli reste, mais il ne transporte plus une donnée fantôme dans le modèle.

## 3. Les 34 nouveaux glyphes

Même contrat que la vague 1 : canvas 28×28, trait 2,4 à bouts ronds, formes dodues, définis en primitives CoreGraphics dans `scripts/gen-icons.swift`, émis en PDF template. Le catalogue passe de 15 à **49** imagesets.

```
pas/mouvement  footprint · footprints · boot · runner · map · flame · repeat
journal        calendar · calendar_month · notebook · meal_log · book · books · ribbon
niveaux        star · star_double · comet · medal
objectifs      target · flag · clover · scale · trend_down · compass
sobriété       drop · glass_empty
moments        sun · moon
thèmes         flan · mint · wave
divers         tree · heart · bell
```

Quatre emoji tombent sur des glyphes déjà dessinés : 🏠 → `tab_home`, 💪 → `tab_sport`, 🏆 → `tab_quests`, 🍽️ → `tab_meals` (plus le repli sport → `tab_sport`).

### 3.1 Paliers : distinguer par la forme, pas par la couleur

Plusieurs badges et quêtes sont des paliers du même objectif, et l'emoji les séparait par la couleur — information perdue en template monochrome. Chaque paire reçoit donc deux **silhouettes franchement différentes** :

| Paliers | Emoji | Glyphes |
|---|---|---|
| Pas, paliers 1 / 2 / 3 | 👟 / 🥾 / 🚶 | une empreinte / deux empreintes / chaussure de rando |
| Repas loggés 50 / 200 | 📖 / 📚 | livre ouvert / deux livres empilés |
| Journal 7 / 30 jours | 📅 / 🗓️ | calendrier à une rangée / calendrier à grille dense |
| Niveaux 5 / 10 / 20 | ⭐ / 🌟 / 💫 | étoile / étoile plus étincelle / comète à traîne |
| Sans alcool 2 / 4 jours | 💧 / 🫗 | goutte / verre vide |

L'échelle des pas mérite un mot : elle passait d'abord par une **basket**, que Michaël n'a pas aimée — et à la relecture c'était bien le glyphe le plus faible du lot, une masse plate posée sur une semelle. Elle est remplacée par **une empreinte**, ce qui donne au passage une échelle plus naturelle (une empreinte → deux empreintes → chaussure de rando pour la longue distance) et supprime la basket de l'app.

Les quêtes sont tirées à 3 par semaine (`QuestEngine.weeklyDraw`), donc deux paliers voisins co-occurrent rarement, mais la grille de badges affiche les 24 d'un coup : c'est là que la distinction compte, et un test l'épingle (§6).

### 3.2 Table de correspondance

Badges (`badges.json`) :

| id | Emoji | Icône |
|---|---|---|
| `first_weigh` | ⚖️ | `icon_scale` |
| `first_meal` | 🍽️ | `icon_meal_log` |
| `journal_7` | 📅 | `icon_calendar` |
| `journal_30` | 🗓️ | `icon_calendar_month` |
| `steps_10k` | 👟 | `icon_footprint` |
| `steps_15k` | 🥾 | `icon_footprints` |
| `steps_total_100k` | 🚶 | `icon_boot` |
| `km_100` | 🗺️ | `icon_map` |
| `level_5` | ⭐ | `icon_star` |
| `level_10` | 🌟 | `icon_star_double` |
| `level_20` | 💫 | `icon_comet` |
| `quest_first` | 🎯 | `icon_target` |
| `quest_10` | 🏹 | `icon_flag` |
| `week_target` | 🍀 | `icon_clover` |
| `trend_down` | 📉 | `icon_trend_down` |
| `weigh_10` | 🧭 | `icon_compass` |
| `meals_50` | 📖 | `icon_book` |
| `meals_200` | 📚 | `icon_books` |
| `steps_total_1m` | 🏆 | `tab_quests` |
| `journal_100` | 🎖️ | `icon_ribbon` |
| `sport_first` | 🥇 | `icon_medal` |
| `sport_10` | 🏃 | `icon_runner` |
| `sport_50` | 🔥 | `icon_flame` |
| `sport_sessions_5` | 🔁 | `icon_repeat` |

`quest_10` (« Aventurier confirmé ») est la seule **métaphore changée** : un arc, sa corde et sa flèche font trois tracés qui se croisent dans 20pt d'encre, et la première planche-contact le lisait « triangle de lecture ». Un fanion planté dit « conquis » aussi bien et se lit à 25pt.

Quêtes (`quests.json`) :

| id | Emoji | Icône |
|---|---|---|
| `log_dinners_5` | 🌙 | `icon_moon` |
| `log_meals_10` | 📔 | `icon_notebook` |
| `log_meals_14` | ✍️ | `icon_meal_log` |
| `steps_25k` | 🚶 | `icon_footprint` |
| `steps_35k` | 👟 | `icon_footprints` |
| `steps_50k` | 🥾 | `icon_boot` |
| `step_goal_3` | 🎯 | `icon_target` |
| `weigh_in_1` | ⚖️ | `icon_scale` |
| `within_target_3` | 🍀 | `icon_clover` |
| `within_target_4` | 🌟 | `icon_star_double` |
| `no_alcohol_2` | 💧 | `icon_drop` |
| `no_alcohol_4` | 🫗 | `icon_glass_empty` |
| `light_dessert_3` | 🍎 | **reste 🍎** |
| `light_dessert_5` | 🍏 | **reste 🍏** |
| `log_breakfast_4` | ☀️ | `icon_sun` |
| `activities_3` | 🏃 | `icon_runner` |
| `activities_5` | 💪 | `tab_sport` |
| `daily_sessions_2` | 📅 | `icon_calendar` |

Thèmes et vues :

| Site | Emoji | Icône |
|---|---|---|
| Thème Crème | 🍮 | `icon_flan` |
| Thème Menthe | 🌿 | `icon_mint` |
| Thème Océan | 🌊 | `icon_wave` |
| Thème Nuit douce | 🌙 | `icon_moon` |
| `SportView` « À la maison » | 🏠 | `tab_home` |
| `SportView` « Dehors » | 🌳 | `icon_tree` |
| `StatCard` « Pas » | 👟 | `icon_footprint` |
| `StepsChart`, repère de record | 🏆 | `tab_quests` |
| `CalorieRing`, sous-titre sous l'objectif | 🍽️ | `tab_meals` |
| `CaloriesChart`, état vide | 🍽️ | `icon_meal_log` |
| Onboarding, permission pas | 👟 | `icon_heart` |
| Onboarding, permission notifications | 🔔 | `icon_bell` |

La carte de permission **Santé** portait la basket, puisqu'elle parle de compter les pas. Un cœur dit « Santé » beaucoup plus directement — et c'est la métaphore de l'app Santé d'iOS, à laquelle la carte demande justement l'accès.

### 3.3 Les deux profils de l'onboarding : des illustrations, pas des glyphes

Les cartes « Michaël » et « Marion » utilisent **`Avatars/boy` et `Avatars/girl`**, deux Nivelito illustrés en couleur, importés depuis `design/icons/{boy,girl}.png` par `scripts/import-avatars.sh`.

Deux têtes cozy monochromes avaient d'abord été dessinées. Elles ne tiennent pas : un visage tient à très peu de traits, et à 28pt de canvas la barbe puis la chevelure refermaient le visage en une fente — les deux avatars se lisaient « personnage encapuchonné », quand ils ne se confondaient pas. L'app a déjà un langage d'illustrations couleur (les 31 vignettes sport) : les profils en relèvent, pas du jeu de glyphes.

Le script produit du **PNG et non du JPEG**, contrairement à `import-sport-images.sh` : ces illustrations sont détourées et se posent sur la carte blanche, un JPEG remplirait le fond en noir. Redimensionnées à 384 px pour un affichage à 72 pt, soit ~120 Ko chacune au lieu des 900 Ko de la source.

## 4. Modèle de données : `CatalogIcon`

Deux entrées sur 42 restent des emoji : le champ ne peut donc pas être un simple nom d'asset. `emoji: String` devient `icon: CatalogIcon` sur `Badge` et `Quest`.

```swift
/// Identité visuelle d'une entrée de catalogue : un glyphe cozy, ou un emoji quand
/// l'emoji reste plus lisible (la nourriture, spec §2.2).
public enum CatalogIcon: Codable, Hashable, Sendable {
    case cozy(String)     // nom d'asset dans Icons/
    case emoji(String)
}
```

Encodage sur **une seule chaîne** dans le JSON, pour ne pas alourdir 42 entrées : un préfixe `icon_` ou `tab_` donne `.cozy`, tout le reste donne `.emoji`. La règle est mécanique et vérifiée par un test (§6) : toute valeur `.cozy` doit résoudre vers un asset existant, sinon l'entrée est un `.emoji` invalide qui s'afficherait en texte brut.

`ThemePalette.icon` est un simple `String` : les 4 thèmes ont tous un glyphe, il n'y a aucune exception emoji à représenter, et ce type est partagé avec l'extension widget — qui n'affiche que les couleurs et n'embarque pas le catalogue d'assets de l'app.

`Dish` et `Extra` gardent leur champ `emoji` inchangé : la nourriture ne bascule pas, et `MealEstimatorTests` n'est pas touché.

## 5. Rendu

Un seul point d'entrée côté vues, à côté de `CozyIcon` :

```swift
struct CatalogGlyph: View {
    let icon: CatalogIcon
    let size: CGFloat
    var locked = false
}
```

La **teinte reste au site d'appel** (`foregroundStyle`, qui traverse un PDF template et laisse un emoji intact) : ce composant ne prend en charge que ce qui diffère vraiment entre un glyphe et un emoji. `.emoji` est rendu en `.system(size: size * 0.76)` — l'inverse de la règle de taille de la vague 1, pour qu'au même `size` l'encre d'un emoji et celle d'un glyphe coïncident.

### 5.1 Tailles

Un asset PDF ignore `.font()` : chaque site passe en taille explicite, `size ≈ encre voulue / 0,76`.

| Site | Emoji avant | `size` |
|---|---|---|
| Grille de badges (cercle 62) | 30 | 39 |
| `BadgeDetailSheet` | 72 | 80 |
| `WeeklyQuestCard` | 28 | 37 |
| `CelebrationBanner` | `.title2` | 29 |
| Cartes de permission de l'onboarding | 34 | 45 |
| Badge de thème, `StatCard`, en-têtes `SportView` | `.footnote` / `.caption` | 15 à 17 |
| `CaloriesChart`, état vide | `.subheadline` | 21 |

`icon_meal_log` est le seul glyphe à demander une taille supérieure à ses voisins de même contexte : il porte **deux** éléments, et à 17 pt la pomme et le crayon se tassaient (vu au simulateur). D'où 21 dans l'état vide de `CaloriesChart`.

### 5.2 Badge verrouillé : la teinte, et surtout PAS d'opacité en plus

Avant la bascule, `QuestsView` estompait l'emoji d'un badge verrouillé par `.grayscale(1).opacity(0.35)`. Un PDF template est déjà monochrome : `grayscale` n'y produit aucun effet, et l'estompage doit passer par la **teinte** — `Theme.subtext` au lieu de `Theme.orange`.

Le 0,35 d'opacité, lui, ne doit **pas** être conservé pour un glyphe. Il avait été calibré pour un emoji désaturé, qui garde des pixels sombres ; appliqué à un glyphe déjà teint clair, il donnait `Theme.subtext` (#B09A8A) à 35 % sur `Theme.track` (#F4E7DB), soit aucun contraste : les 23 badges verrouillés étaient invisibles. Constaté au simulateur, pas au raisonnement.

Le cas emoji garde `grayscale` avec une opacité portée de 0,35 à **0,5**, pour peser autant que les glyphes teintés voisins de la grille.

### 5.3 Sites à adapter

- `QuestsView` : grille de badges, `WeeklyQuestCard`, `BadgeDetailSheet`.
- `HomeView` : `QuestCard` (une seconde carte de quête, distincte de celle de `QuestsView`).
- `CelebrationsHost` : `CelebrationBanner(emoji:)` devient `CelebrationBanner(icon:)`, et `bannerContent` remonte un `CatalogIcon`.
- `SettingsView+DevicePreferences` : badge de thème.
- `StatCard`, `CalorieRing`, `CaloriesChart` : `HStack` glyphe plus texte, l'icône étant décorative.
- `StepsChart` : le repère de record passe en annotation `CozyIcon`.
- `SportView` : `Overline` reçoit une surcharge `Overline(_ text: String, icon: String?)`.
- `OnboardingFlow` : `profileCard(avatar:)` et les cartes de permission.
- `SportIllustration` / `SportHeroIllustration` : `fallbackEmoji` disparaît (§2.3), ce qui touche aussi `TimerRingView`, `DailySessionCard`, `ActivityLogSheet` et `SessionPlayerSheet`.

## 6. Tests

- `IconAssetsTests` : la liste épinglée passe de 15 à 49 noms ; chacun doit charger, être template et mesurer 28×28.
- Les deux avatars sont testés à part : illustrations couleur, donc ni template ni 28×28.
- Chaque `icon` de badge, de quête et de thème qui est un `.cozy` doit résoudre vers un asset existant (40 au total) : c'est le garde-fou de la règle de préfixe du §4.
- Le test miroir épingle que les **seules** entrées restées en emoji sont `light_dessert_3` et `light_dessert_5` : une troisième, oubliée dans un futur ajout, échouerait ici.
- `CatalogsTests` : la distinction visuelle des badges se vérifie désormais sur `icon` et non sur `emoji` (l'intention du test ne change pas).
- `MealEstimatorTests` : inchangé.
- Relecture visuelle sur la planche-contact, qui passe en **grille** de 10 colonnes et deux bandes (50 px et 100 px) : 49 glyphes ne tiennent plus sur une rangée. C'est la bande du bas qui décide, puisqu'elle est à la taille réelle d'affichage.

## 7. Points d'attention et pièges rencontrés

- **Un croissant ne se fait pas en even-odd.** Empiler deux disques et remplir en even-odd donne la différence **symétrique**, pas la soustraction : dès que le trou dépasse du disque — ce qu'exige un croissant mince — la part « trou hors disque » se remplit aussi, et on obtient une masse pleine avec une lentille évidée. `crescent()` construit donc un vrai tracé à **deux arcs**. Le paramètre qui décide de la lecture est l'angle balayé par l'arc du disque, `2·(π − acos(a/r))` : ~160° donne un croissant à deux cornes, ~200° un « anneau à encoche ».
- **Un croissant est excentré par construction** : il n'occupe qu'un côté de son disque. Sans recentrage de la boîte englobante, la lune s'affiche en filet collé au bord de sa case, deux fois plus petite que ses voisines. D'où les aides `rotated()` et `centered()`.
- **La planche-contact ne remplace pas le simulateur.** Trois défauts n'y étaient pas visibles : les badges verrouillés sans contraste (§5.2), la lune en anneau, et les avatars encapuchonnés. Un glyphe se juge à sa taille réelle, sur son fond réel, avec sa teinte réelle.
- **Lisibilité à 25pt** : `icon_books` a été ramené de trois livres à deux (trois tranches de 4pt ne laissent que 2pt de blanc et la pile se lit « menu ») ; `icon_mint` a ses feuilles attachées à la tige et non posées à côté ; `icon_tree` a une base de houppier large, plate et festonnée, sans quoi il se lit « ballon » puis « champignon » ; `icon_flame` a une pointe secondaire et un creux, sans quoi c'est une goutte.
- **Un composite monochrome ne peut pas se chevaucher.** `icon_meal_log` juxtapose pomme et crayon côte à côte, sans recouvrement. Ce n'est pas un choix esthétique : un PDF template n'a qu'une couleur, rien ne peut en masquer autre chose, et un crayon posé sur la pomme fusionnerait avec elle en une seule tache. Le corollaire est qu'un composite coûte de la place — d'où sa taille majorée (§5.1).
- **Aucune logique métier ne change** : ni seuils de badges, ni tirage de quêtes, ni calcul de kcal. Les widgets ne sont pas touchés.
