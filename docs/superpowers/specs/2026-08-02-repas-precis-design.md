# Nivel — Spécification Repas précis (v1.10)

Date : 2026-08-02
Statut : validé avec Michaël (brainstorm du 02/08/2026, maquettes du visual companion)
Référence : refond le log de repas de la v1 (`2026-07-29-nivel-v1-design.md` §4.2 et §6).

Ce document est le **lot A** d'une demande en trois lots. Le lot B (`2026-08-02-timing-rappels-design.md`) est livré en v1.9. Reste ensuite le **lot C** : programme posture de Marion, exercices ciblés, ciblage par profil, rappel du soir.

## 1. Vision

Le log de repas de la v1 tient en un plat forfaitaire, une portion à trois crans et quatre extras. C'est rapide, et c'est trop grossier dès qu'on veut savoir ce qu'on a réellement mangé : une salade vaut 350 kcal qu'elle soit verte ou couverte de thon et de croûtons, un steak n'a pas d'accompagnement, un paquet de chips à 16 h ne se logge pas du tout.

v1.10 rend le chiffre juste **quand on veut bien faire l'effort**, sans allonger le cas courant. Un repas devient une liste de lignes ; chaque plat arrive déjà composé ; on n'ouvre le détail que le jour où on remplace le thon par du poulet.

La philosophie ne change pas : zéro pression, l'app informe et n'ordonne pas. Le détail est une possibilité, jamais une obligation.

## 2. Décisions validées

- **Le détail change le compte de calories** (pas une note libre), et **chaque plat a une composition par défaut** : on ne détaille que si on veut.
- **La portion n'est pas un mode, c'est un bouton qui écrit des grammes.** Léger / normal / copieux réécrivent d'un coup les quantités de tous les composants (×0,7, ×1, ×1,3). Il n'y a donc aucun multiplicateur qui s'applique après coup par-dessus une quantité saisie à la main.
- **Tout est stocké en grammes.** L'unité affichée (« 1 œuf », « 1 c. à soupe ») vient du catalogue à l'affichage, jamais de la base.
- **`manualKcal` est une surcharge** au niveau du repas, pas un mode. Vide, l'app calcule ; rempli, c'est cette valeur qui compte, et **le tilde disparaît**.
- **Le plat devient facultatif** : un repas est au moins une ligne, quelle qu'elle soit. Une bière seule est un repas.
- **Feuille en panier + catalogue à onglets** (maquette B), et **les puces de portion vivent dans l'écran de détail** (maquette C).
- **Pas de conversion de l'historique.** Un seul repas est loggé aujourd'hui ; les anciens champs sont supprimés.

## 3. Le modèle

### 3.1 `MealEntry` (app, SwiftData)

Perd `dishID`, `portionRaw`, `extras`. Gagne :

```swift
var lines: [MealLine] = []   // au moins une pour tout repas créé en v1.10
var manualKcal: Int?         // nil = calculé
```

`date`, `slotRaw`, `estimatedKcal` et `xpAwarded` sont inchangés.

**Migration.** Suppression de trois propriétés, ajout de deux : migration légère SwiftData. L'unique repas déjà loggé conserve sa date, son créneau, son `estimatedKcal` et son XP, et **perd son détail** : il s'affiche « Repas » avec ses kcal, et reste supprimable. C'est un choix explicite de Michaël (« on n'a qu'un seul repas loggé, fais au plus simple ») : aucune fonction de conversion, aucun double chemin d'affichage, aucun test de forme ancienne.

Les nouvelles propriétés portent leur défaut **sur la déclaration**, pas seulement dans l'`init` (leçon `completedThisWeekQuestIDs` en v1, reconfirmée en v1.9).

### 3.2 `MealLine` (NivelCore)

```swift
/// Un composant : toujours un item du catalogue et un poids.
public struct MealComponent: Codable, Equatable, Hashable, Sendable {
    public let itemID: String
    public let grams: Int                // TOUJOURS des grammes
}

public enum MealLine: Codable, Equatable, Hashable, Sendable {
    /// Une bière, un paquet de chips, un accompagnement ajouté à la main.
    case simple(MealComponent)
    /// Un plat et sa composition. Son poids est la somme de ses composants,
    /// il n'en porte pas un à lui.
    case composed(itemID: String, components: [MealComponent])
}
```

**Un enum, pas une struct à champ optionnel.** Avec `grams` et `components` côte à côte, une ligne composée porterait un poids propre qui ne veut rien dire et que le calcul ignorerait en silence : un état illégal représentable, donc tôt ou tard écrit par erreur. L'enum rend le cas impossible, et **borne la profondeur à un niveau par construction** plutôt que par convention. C'est le même raisonnement que `DurationSelection` en v1.9.

**Pourquoi les grammes et rien d'autre.** Si l'unité affichée était persistée, corriger un jour le poids de référence d'un œuf fausserait rétroactivement tous les repas déjà loggés. En grammes, un repas passé reste ce qu'il était.

### 3.3 Le calcul (NivelCore, pur)

```swift
MealEstimator.kcal(lines:) -> Int              // somme récursive
MealEstimator.kcal(entry:) -> Int              // manualKcal s'il existe, sinon la somme
```

Un composant vaut `grams × kcalPer100g / 100`, arrondi à l'entier au niveau du repas et non composant par composant (sinon quinze arrondis se cumulent). Une ligne composée vaut la somme de ses composants.

`MealEntry.estimatedKcal` est écrit à la validation avec **le résultat de `kcal(entry:)`**, `manualKcal` compris. C'est ce qui garantit que le total du jour, l'anneau de l'accueil et le widget affichent la valeur saisie à la main, et pas l'estimation qu'elle remplace.

## 4. Le catalogue

### 4.1 `FoodItem` (NivelCore)

```swift
public struct FoodItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let kcalPer100g: Double
    public let unitLabel: String?     // « œuf », « c. à soupe », « verre »... nil = au gramme
    public let unitGrams: Int?        // poids d'une unité ; nil si unitLabel est nil
    public let category: Category     // dish, side, drink, snack
    public let tags: [String]         // « alcohol », « richDessert »... voir §7.1
    public let slots: [MealSlot]      // pertinent pour les plats ; vide = tous
    public let defaultGrams: Int      // quantité posée au tap dans le catalogue
}
```

Chargé depuis `foods.json` via `Catalogs`, comme les plats et les activités. Les compositions par défaut vivent dans `compositions.json` : `dishID → [(itemID, grams)]`.

**Une seule valeur énergétique est stockée : `kcalPer100g`.** Les tables ci-dessous donnent aussi les kcal par unité, parce que c'est ainsi qu'on raisonne en les relisant, mais c'est une **valeur dérivée** : `kcalPer100g = kcalParUnité × 100 / unitGrams`. C'est cette colonne dérivée qui va dans le JSON, et un test la revérifie contre la table (§10). Pour les boissons, `unitGrams` est le volume en millilitres, un liquide pesant à peu près son volume ; pour un cocktail ou un café, ce poids est nominal et ne sert qu'à porter le calcul.

### 4.2 Les boissons (15)

| id | Nom | Unité | g | kcal / unité | kcal/100 g |
|---|---|---|---|---|---|
| `water` | Eau | 1 verre | 200 | 0 | 0 |
| `tea` | Thé ou infusion | 1 tasse | 200 | 0 | 0 |
| `coffee` | Café noir | 1 tasse | 200 | 2 | 1 |
| `soda_zero` | Soda light ou zéro | 1 canette | 330 | 1 | 0,3 |
| `coffee_milk` | Café au lait sucré | 1 tasse | 200 | 90 | 45 |
| `milk` | Lait | 1 verre | 200 | 128 | 64 |
| `juice` | Jus de fruit | 1 verre | 200 | 110 | 55 |
| `soda` | Soda | 1 canette | 330 | 139 | 42 |
| `beer_half` | Bière, demi | 25 cl | 250 | 108 | 43 |
| `beer_pint` | Bière, pinte | 50 cl | 500 | 215 | 43 |
| `wine` | Vin | 1 verre | 125 | 106 | 85 |
| `spirit` | Alcool fort ou apéritif | 1 dose | 40 | 100 | 250 |
| `cocktail` | Cocktail | 1 verre | 200 | 250 | 125 |
| `hot_chocolate` | Chocolat chaud | 1 tasse | 200 | 200 | 100 |
| `smoothie` | Smoothie | 1 verre | 200 | 180 | 90 |

Les valeurs aux 100 g ont été choisies pour être physiquement plausibles, pas pour tomber rond : un soda est bien à 42, une bière à 43, un vin à 85. Les kcal par unité en découlent, ce qui explique 108 plutôt que 110 pour un demi.

**Demi et pinte sont deux entrées**, pas un stepper sur « bière » : deux demis et une pinte ne sont pas le même geste dans la tête de qui les commande.

**« Cocktail » reste un forfait unique.** Un mojito et une piña colada ne sont pas comparables, mais un sous-catalogue de cocktails pour deux personnes qui en boivent trois par an ne se justifie pas. Hors périmètre, assumé.

### 4.3 Les encas (12)

| id | Nom | Unité | g | kcal / unité | kcal/100 g |
|---|---|---|---|---|---|
| `fruit` | Fruit | 1 | 150 | 80 | 53 |
| `yogurt` | Yaourt | 1 pot | 125 | 75 | 60 |
| `choco_square` | Carré de chocolat | 1 | 10 | 55 | 550 |
| `biscuit` | Biscuit | 1 | 10 | 50 | 500 |
| `candy` | Bonbons | 1 poignée | 30 | 105 | 350 |
| `compote` | Compote | 1 gourde | 90 | 90 | 100 |
| `cheese_snack` | Fromage | 1 part | 30 | 105 | 350 |
| `chips` | Petit paquet de chips | 1 paquet | 28 | 153 | 545 |
| `nuts` | Oléagineux | 1 poignée | 30 | 180 | 600 |
| `choco_bar` | Barre chocolatée | 1 | 45 | 230 | 511 |
| `croissant` | Viennoiserie | 1 | 70 | 301 | 430 |
| `ice_cream` | Glace | 1 boule | 100 | 200 | 200 |

**Les chips sont au format européen individuel**, 27,5 g, soit environ 150 kcal à 545 kcal aux 100 g. Un paquet familial partagé se règle en tapant les grammes : inutile d'une seconde entrée.

**L'id de la viennoiserie est `croissant`, pas `pastry`** : `pastry` est déjà l'id du plat Viennoiserie hérité de la v1, et réutiliser le même identifiant ferait perdre silencieusement l'une des deux entrées à l'indexation du catalogue.

### 4.4 Les accompagnements et ingrédients (42)

kcal aux 100 g. Ceux qui ont une unité naturelle la portent, les autres se saisissent au gramme.

| id | Nom | kcal/100 g | Unité |
|---|---|---|---|
| `pasta_cooked` | Pâtes cuites | 160 | |
| `rice_cooked` | Riz cuit | 130 | |
| `potato` | Pommes de terre | 90 | |
| `fries` | Frites | 300 | |
| `mash` | Purée | 110 | |
| `bread` | Pain | 270 | 1 tranche = 40 g |
| `burger_bun` | Pain à burger | 280 | 1 = 80 g |
| `pizza_dough` | Pâte à pizza | 270 | |
| `cereal_flakes` | Céréales | 380 | |
| `lettuce` | Salade verte | 15 | |
| `tomato` | Tomates | 20 | |
| `green_veg` | Légumes verts | 40 | |
| `soup_veg` | Légumes de soupe | 35 | |
| `corn` | Maïs | 100 | |
| `avocado` | Avocat | 160 | 1 demi = 75 g |
| `legumes` | Légumineuses | 120 | |
| `egg` | Œuf | 145 | 1 = 60 g |
| `chicken` | Poulet | 165 | |
| `beef` | Viande rouge | 250 | |
| `beef_patty` | Steak haché | 250 | 1 = 120 g |
| `fish_fillet` | Poisson | 130 | |
| `tuna` | Thon | 130 | |
| `ham` | Jambon | 145 | 1 tranche = 40 g |
| `bacon` | Lardons | 300 | |
| `cheese` | Fromage | 350 | |
| `grated_cheese` | Fromage râpé | 380 | |
| `mozzarella` | Mozzarella | 280 | |
| `croutons` | Croûtons | 430 | |
| `vinaigrette` | Vinaigrette | 450 | 1 c. à soupe = 12 g |
| `olive_oil` | Huile d'olive | 900 | 1 c. à soupe = 12 g |
| `butter` | Beurre | 750 | 1 noisette = 10 g |
| `cream` | Crème | 200 | 1 c. à soupe = 15 g |
| `sauce` | Sauce | 250 | |
| `tomato_sauce` | Sauce tomate | 40 | |
| `ketchup` | Ketchup | 100 | 1 c. à soupe = 15 g |
| `mayo` | Mayonnaise | 700 | 1 c. à soupe = 15 g |
| `jam` | Confiture | 270 | 1 c. à café = 10 g |
| `honey` | Miel | 320 | 1 c. à café = 10 g |
| `sugar` | Sucre | 400 | 1 morceau = 5 g |
| `fruit_pieces` | Fruits coupés | 55 | |
| `plain_yogurt` | Yaourt nature | 60 | 1 pot = 125 g |
| `drink_milk` | Lait (ingrédient) | 45 | |

### 4.5 Les compositions par défaut

Chacune doit retomber sur le forfait actuel du plat, **à 10 % près**. C'est un test, pas une intention (§8).

| Plat (forfait v1) | Composition par défaut | Somme |
|---|---|---|
| Pâtes, 650 | pâtes 250 g, sauce tomate 120 g, fromage râpé 25 g, huile 12 g | 651 |
| Riz / féculents, 550 | riz 250 g, poulet 100 g, légumes verts 150 g | 550 |
| Salade composée, 350 | salade 80 g, tomates 100 g, œuf 60 g, thon 80 g, maïs 50 g, vinaigrette 12 g, croûtons 10 g | 370 |
| Légumes + protéine, 450 | légumes verts 250 g, poulet 150 g, huile 12 g | 456 |
| Viande rouge + accomp., 700 | viande 150 g, frites 100 g, légumes verts 80 g | 707 |
| Poisson + accomp., 500 | poisson 150 g, riz 150 g, légumes verts 100 g, beurre 10 g | 505 |
| Pizza, 900 | pâte 200 g, sauce tomate 80 g, mozzarella 100 g, jambon 40 g | 910 |
| Soupe, 300 | légumes de soupe 350 g, crème 30 g, pain 40 g | 290 |
| Sandwich, 550 | pain 120 g, jambon 50 g, fromage 30 g, beurre 8 g | 562 |
| Plat mijoté, 600 | viande 120 g, pommes de terre 200 g, légumes verts 100 g, sauce 40 g | 620 |
| Fast-food, 950 | pain à burger 80 g, steak haché 120 g, fromage 20 g, frites 120 g | 954 |
| Tartines, 350 | pain 80 g, beurre 12 g, confiture 20 g | 360 |
| Céréales, 400 | céréales 70 g, `drink_milk` 200 g, fruits coupés 80 g | 400 |
| Viennoiserie, 300 | `croissant` 70 g | 301 |
| Yaourt & fruits, 200 | yaourt nature 125 g, fruits coupés 120 g, miel 15 g | 189 |
| Autre, 600 | **aucune** | 600 |

**« Autre » n'a délibérément pas de composition.** C'est une ligne **simple**, pas composée : la porte de sortie. On la pose, et si on connaît mieux le chiffre on saisit `manualKcal`. Prétendre la composer serait inventer un contenu qu'on ne connaît pas. Son unité est « 1 plat » pour 400 g nominaux à 150 kcal/100 g, soit les 600 kcal du forfait v1 ; ce poids ne veut rien dire et c'est assumé plutôt que caché.

### 4.6 Modifier un repas existant

Le mode édition de la feuille (`MealLogSheet(entry:)`) charge les lignes du repas et se comporte en tout point comme une création : mêmes onglets, même détail, même saisie manuelle. À la validation, `updateMeal` recalcule `estimatedKcal`, ajuste le `DayLog` du delta et **ne réattribue aucun XP**, exactement comme aujourd'hui.

## 5. La feuille de log

### 5.1 Structure

Du haut vers le bas : puces de créneau (inchangées), panier « Ton repas », catalogue à onglets, barre basse.

La feuille gagne un `NavigationStack` : le détail d'une ligne **pousse un écran**, il n'ouvre pas une feuille par-dessus la feuille. Même raison qu'en v1.9 pour la roue de durée, et une composition à six lignes ne tient pas dépliée en place.

### 5.2 Le panier

Vide : une ligne discrète, « Tape un plat, une boisson, ce que tu veux », plutôt qu'un grand blanc.

Chaque ligne : emoji, nom, quantité en clair (« normal · 6 ingrédients », « 50 g », « 1 verre »), kcal, chevron. Swipe pour supprimer, comme dans le journal.

### 5.3 Le catalogue

Quatre onglets : **Plats · Accompagnements · Boissons · Encas**. L'onglet Plats s'ouvre filtré sur le créneau courant. Un tap ajoute la ligne avec son `defaultGrams` et rien d'autre : c'est le chemin de quinze secondes.

### 5.4 L'écran de détail d'une ligne

Poussé par le chevron. De haut en bas :

- Les trois puces **Léger / Normal / Copieux**, qui réécrivent les grammes de tous les composants à ×0,7 / ×1 / ×1,3 de la composition par défaut. Effet immédiat et visible sur les quantités affichées juste en dessous.
- La liste des composants, chacun avec son réglage : stepper dans l'unité naturelle quand il y en a une, champ en grammes sinon, et un champ en grammes accessible dans tous les cas.
- Un bouton pour ajouter un ingrédient à la composition, et un swipe pour en retirer un.
- Pour une ligne **simple** (une bière, un paquet de chips), le même écran sans la section composants : juste la quantité.

**Le raccourci de portion coûte un aller-retour** sur le geste courant « pâtes, copieux, validé ». Michaël a vu ce compromis en maquette et a choisi cet emplacement pour garder le panier sobre.

### 5.5 La barre basse

À gauche l'estimation, à droite le bouton de validation, comme aujourd'hui.

L'estimation affiche **« ~ 635 kcal »** quand elle est calculée, et **« 635 kcal » sans tilde** quand `manualKcal` est rempli. Un tap sur le montant ouvre la saisie manuelle ; quand elle est active, un bouton « revenir à l'estimation » la vide.

## 6. Le journal

La ligne d'un repas affiche le résumé de ses lignes au lieu de « portion · extras » : nom de la première ligne, puis le nombre des autres, par exemple « Salade composée +2 ». Les kcal suivent la même règle de tilde que la barre basse.

Un repas sans lignes (l'unique entrée d'avant la migration) s'affiche « Repas » avec ses kcal.

## 7. Les quêtes qui lisent le contenu d'un repas

**Correction apportée pendant l'implémentation.** Ce document affirmait d'abord que les quêtes et badges ne regardent jamais le contenu d'un repas. C'est faux pour deux métriques, trouvées en traçant ce que la bascule casse :

- `daysWithoutAlcohol` cherchait les extras d'id `beer` et `wine` ;
- `lightDessertDays` cherchait l'extra `dessert_rich`.

Or `beer` est scindé en `beer_half` et `beer_pint`, et `dessert_rich` disparaît. Sans rien faire, ces deux quêtes seraient devenues **silencieusement toujours réussies** : aucune ligne ne portant plus les anciens ids, la condition « aucun alcool » aurait été vraie tous les jours. Un bug qu'aucun test n'aurait signalé et qui aurait donné de l'XP pour rien.

### 7.1 Le classement vit dans les données

Plutôt qu'une liste d'ids en dur dans `GameService`, `FoodItem` porte un champ `tags`. Deux tags aujourd'hui :

| tag | Items |
|---|---|
| `alcohol` | `beer_half`, `beer_pint`, `wine`, `spirit`, `cocktail` |
| `richDessert` | `choco_bar`, `ice_cream`, `croissant` |

Les métriques interrogent le catalogue : un jour compte comme sans alcool si aucun composant d'aucune de ses lignes ne porte le tag `alcohol`. Ainsi le lot C, ou n'importe quel ajout futur au catalogue, classe son item là où il le déclare, et non dans un fichier de service qu'il faudrait penser à ouvrir.

**Un changement de comportement à assumer** : la quête sans alcool attrape désormais aussi les spiritueux et les cocktails. En v1 elle ne voyait que la bière et le vin, parce que le catalogue n'avait rien d'autre. C'est ce que la quête a toujours voulu dire.

Un test épingle les deux listes ci-dessus, pour qu'un item ajouté sans tag ne passe pas inaperçu.

## 8. Ce qui ne change pas

- Le nombre de repas loggés : `mealsLogged`, et tous les badges qui en dépendent.
- L'objectif kcal, le total du jour, l'anneau de l'accueil et l'instantané du widget lisent `estimatedKcal`, figé à l'écriture. Aucune des sept clés du widget ne bouge.
- L'XP par repas, ses plafonds, la banque de messages.
- La navigation par jour du journal, et la règle « modifiable le jour même uniquement ».

## 9. Hors périmètre, explicitement

- Recherche textuelle dans le catalogue. Quatre onglets suffisent à cette taille.
- Repas favoris, ou dupliqués depuis un jour précédent.
- Code-barres, base de données externe, photo.
- Macros : protéines, lipides, glucides.
- Sous-catalogue de cocktails.
- Réglage des compositions par défaut depuis l'app.
- Profondeur de composition supérieure à un niveau.

## 10. Tests

**NivelCore**

- `MealEstimator.kcal(lines:)` : ligne simple, ligne composée (somme des composants, pas son propre `grams`), imbrication, liste vide, arrondi.
- `MealEstimator.kcal(entry:)` : `manualKcal` court-circuite bien la somme ; `nil` retombe sur le calcul.
- **Le garde-fou des compositions** : pour chacun des quinze plats composés, la somme de la composition par défaut est à moins de 10 % du forfait v1. Un ingrédient mal dosé est attrapé ici, pas au dîner.
- Intégrité du catalogue : tout `itemID` cité dans `compositions.json` existe dans `foods.json` ; pas de doublon d'`id` ; `unitGrams` non nil si et seulement si `unitLabel` l'est ; `defaultGrams` strictement positif ; `kcalPer100g` positif ou nul.
- **La colonne dérivée** : pour chaque item à unité, `unitGrams × kcalPer100g / 100` retombe sur la valeur « kcal / unité » des tables §4.2 et §4.3, à une unité près. C'est le garde-fou contre une erreur de conversion recopiée dans le JSON.
- Le raccourci de portion : ×0,7 / ×1 / ×1,3 appliqués à une composition donnent les grammes attendus, arrondis à l'entier.
- Aucun tiret cadratin dans `foods.json` ni `compositions.json` (le test existant couvre déjà toutes les ressources du bundle).
- **Les tags de §7.1 épinglés** : exactement les cinq items alcoolisés, exactement les trois desserts gourmands. Un item ajouté sans tag ne doit pas passer inaperçu.
- Les deux métriques de quête sur une journée avec et sans alcool, et avec et sans dessert gourmand, en construisant les repas depuis des lignes.

**App**

- `MealEntry` accepte et relit des lignes imbriquées après un `save()` (SwiftData sait sérialiser le tableau de valeurs).
- La règle du tilde : présent quand `manualKcal` est nil, absent sinon.
- Le résumé de ligne du journal sur un repas à une, deux et quatre lignes.
- Un repas sans lignes s'affiche sans planter.

## 11. Livraison

Version **1.10 (build 11)** dans `project.yml`, sur les **deux** cibles.

**À vérifier sur les téléphones, par Michaël**

1. Au premier lancement, le store s'ouvre et les poids, pas, XP, badges et quêtes sont intacts. Seul le repas d'avant perd son détail.
2. Logger une bière seule, sans plat.
3. Logger un paquet de chips à 16 h.
4. Détailler une salade : retirer les croûtons, passer le thon en poulet, vérifier que le total suit.
5. Saisir des kcal à la main et vérifier que le tilde disparaît, dans la feuille et dans le journal.
6. Le rendu du panier et de l'écran de détail sur le plus petit des deux iPhones.
