# Nivel — Spécification v1

Date : 2026-07-29
Statut : validé avec Michaël (brainstorming du 29/07/2026)

## 1. Vision

Nivel est une app iOS en français qui accompagne Michaël et Marion dans une perte de poids douce et durable. Ce n'est pas une app de régime : c'est un compagnon bienveillant, gamifié comme un jeu vidéo cozy, qui encourage sans jamais culpabiliser. Perte visée : lente (~0,3 kg/semaine), au rythme de chacun.

**Principes non négociables :**
- Zéro culpabilisation : jamais de rouge, jamais de "raté", jamais de reproche. Un jour sans log = rien ne se passe. Un dépassement calorique = message neutre et encourageant.
- Simplicité d'usage : logger un repas prend moins de 15 secondes.
- Tout en local : aucune donnée ne quitte le téléphone, pas de backend, pas de compte en ligne.

## 2. Contexte et contraintes

- **Utilisateurs** : deux personnes (Michaël, Marion), chacune avec l'app sur son iPhone. Les deux installations sont **indépendantes** : aucune synchronisation entre téléphones.
- **Matériel** : iPhone uniquement (pas d'Apple Watch). iPhones récents, iOS 17+.
- **Distribution** : build direct depuis Xcode avec un compte Apple Developer **gratuit** → l'app expire tous les 7 jours ; procédure de re-build à documenter (brancher l'iPhone, Run). Pas d'App Store.
- **Langue** : interface et contenus 100 % français.

## 3. Stack technique

- **SwiftUI** (iOS 17+) pour toute l'UI et les animations (spring, particules, transitions).
- **SwiftData** pour la persistance locale.
- **HealthKit** en lecture seule pour les pas quotidiens (`stepCount`).
- **UserNotifications** pour les rappels locaux.
- **Aucune dépendance externe.** Un seul projet Xcode, cible unique ; le profil (Michaël/Marion) est choisi à l'onboarding sur chaque téléphone.
- La mascotte Nivelito est dessinée en formes SwiftUI natives (Path/Shape), fidèle au SVG de référence `design/nivelito.svg`, pour être animable nativement.

## 4. Navigation et écrans

Tab bar à 5 onglets : **Accueil · Repas · Progrès · Quêtes · Réglages**.

### 4.1 Accueil (dashboard)
Maquette validée (`.superpowers/brainstorm/…/design-home.html`) :
- En-tête : date, salutation personnalisée, pastille de niveau.
- Nivelito animé + bulle de message contextuel.
- Anneau des calories du jour : mangé / objectif, avec le restant mis en avant.
- Carte pas du jour : compteur, objectif (8 000 par défaut, ajustable), jauge.
- Barre d'XP vers le prochain niveau.
- Carte de la quête hebdo la plus avancée.
- Bouton principal "+ Logger un repas".

### 4.2 Repas (journal)
- Journal du jour par créneau : petit-déjeuner, déjeuner, dîner, encas.
- **Flux de log en 3 étapes** (une seule feuille modale) :
  0. Le créneau est pré-rempli d'après l'heure (avant 11 h = petit-déj, 11-15 h = déjeuner, après 18 h = dîner, sinon encas), modifiable d'un tap en tête de feuille.
  1. Type de plat (catalogue : pâtes, riz, salade, légumes + protéine, viande rouge + accompagnement, poisson, pizza, soupe, sandwich, plat mijoté, fast-food, autre… — plus des items petit-déjeuner : tartines, céréales, viennoiserie, yaourt/fruits),
  2. Portion : léger / normal / copieux (multiplicateurs 0,7 / 1 / 1,3),
  3. Extras : dessert (léger/gourmand), boissons (eau, bière, vin, soda) avec quantité.
- Estimation kcal affichée en direct pendant la sélection, validation en un tap.
- Un repas loggé est modifiable/supprimable le jour même.
- Navigation vers les jours précédents en lecture.

### 4.3 Progrès
- **Courbe de poids** : points de pesée + tendance lissée (moyenne mobile) mise en avant ; les fluctuations quotidiennes sont visuellement secondaires.
- **Historique calories** : barres jour par jour (mangé vs objectif), semaine et mois.
- **Historique de pas** : barres jour/semaine, records personnels célébrés.
- Saisie manuelle du poids ici (bouton "+ Pesée").

### 4.4 Quêtes
- 3 quêtes hebdomadaires actives, renouvelées chaque lundi, tirées d'un pool (voir §7.3).
- Collection de badges : débloqués en couleur, verrouillés en silhouette avec indice.

### 4.5 Réglages
- Profil : prénom, taille, âge, sexe, niveau d'activité, poids de départ.
- Objectif calorique : valeur calculée affichée, modifiable librement.
- Objectif de pas quotidien.
- Rappels : chaque notification activable/désactivable individuellement.
- Ré-autorisation HealthKit si refusée initialement.

## 5. Onboarding et splash

- **Splash animé** à chaque ouverture : Nivelito apparaît (rebond doux) avec le logotype "Nivel". Court (~1,5 s), skippable d'un tap.
- **Premier lancement** :
  1. Écran d'accueil chaleureux avec Nivelito qui se présente.
  2. Choix du profil : Michaël ou Marion (détermine prénom et salutations).
  3. Saisie : taille, date de naissance, sexe, poids actuel, niveau d'activité (sédentaire / léger / modéré / actif).
  4. Nivelito présente l'objectif calorique calculé (voir §6) et explique qu'il est modifiable.
  5. Demandes d'autorisation : HealthKit (pas), notifications. Refus = l'app fonctionne quand même (pas masqués / rappels off).

## 6. Calculs caloriques

- **Métabolisme de base** : formule Mifflin-St Jeor (sexe, poids, taille, âge).
- **Dépense quotidienne estimée (TDEE)** : BMR × facteur d'activité (1,2 / 1,375 / 1,55 / 1,725).
- **Objectif calorique quotidien** : TDEE − 350 kcal (déficit doux ≈ −0,3 kg/semaine), arrondi à la dizaine, modifiable dans Réglages. Plancher de sécurité : jamais sous 1 200 (femme) / 1 500 (homme) kcal.
- **Estimation des repas** : catalogue embarqué (JSON dans le bundle) associant chaque type de plat à une valeur kcal moyenne, multipliée par la portion, plus extras (ex. : dessert léger +150, gourmand +300 ; bière +150, vin +120, soda +140, eau +0). Valeurs modifiables sans toucher au code Swift.
- **Dépense liée aux pas** : estimation affichée à titre indicatif (formule ~0,04 kcal × poids(kg)/70 × pas) mais **jamais ajoutée** au budget calorique (pas d'effet "je peux remanger").
- Le poids courant utilisé par les calculs = dernière pesée enregistrée.

## 7. Gamification

### 7.1 XP et niveaux
- Actions : logger un repas +20 (max 4/jour récompensés), pesée +30 (max 1/jour), journée complète dans l'objectif kcal +50 (attribué le lendemain matin), objectif de pas atteint +40, quête hebdo complétée +150, badge débloqué +50.
- Niveau : XP cumulé à vie (jamais de perte d'XP). Seuil du niveau n = 100 × n^1,3 arrondi (progression douce, niveaux fréquents au début).
- Level-up : plein écran de célébration — Nivelito saute de joie, confettis, haptique.

### 7.2 Badges (~20 en v1)
Exemples : Première pesée · Premier repas loggé · 7 jours de journal · 30 jours de journal · 10 000 pas en un jour · 15 000 pas en un jour · 100 000 pas cumulés · 100 km cumulés · Niveau 5 / 10 / 20 · Première quête complétée · 10 quêtes complétées · Semaine complète dans l'objectif · Première tendance de poids en baisse sur 2 semaines. Définis dans un catalogue JSON embarqué.

### 7.3 Quêtes hebdomadaires
- 3 quêtes tirées aléatoirement chaque lundi dans un pool (~15 quêtes), adaptées pour rester atteignables : "Logge 5 dîners", "35 000 pas cette semaine", "3 jours avec dessert léger ou sans dessert", "2 jours sans alcool", "Pèse-toi une fois", "4 jours dans ton objectif kcal"…
- Une quête non finie disparaît sans pénalité ni message négatif.
- Formulations toujours positives (jamais "évite", "ne rate pas").

### 7.4 Ton et bienveillance
- Aucune couleur punitive (pas de rouge d'échec) ; dépassement kcal affiché en neutre.
- Retour après plusieurs jours d'absence : Nivelito accueille avec joie ("Content de te revoir !"), jamais de reproche.
- Pas de streaks : rien ne "casse".

## 8. Nivelito (mascotte)

- **Design validé** : panda roux flat mascotte (contour bordeaux #3a1220, orange #f57c1f, museau crème #f2ede0, joues brunes, blush). Référence : `design/nivelito.svg`. Sert de base au logo et à l'icône de l'app (version simplifiée sur fond crème).
- **Implémentation** : formes SwiftUI (Path bézier reprenant le SVG), composants paramétrables (yeux, bouche, position) pour les expressions.
- **Expressions v1** : neutre-souriant (défaut), joie (level-up, badge), clin d'œil (après un log), endormi (le soir après 22 h), encourageant.
- **Animations v1** : idle (respiration lente + clignements aléatoires), rebond d'apparition (splash), saut de joie + confettis (célébrations), endormissement.
- **Messages** : banque locale ~150 phrases françaises (JSON embarqué), classées par contexte : salutation (matin/midi/soir), après log de repas, après pesée, level-up, badge, quête complétée, encouragement pas, dépassement kcal (neutre), retour après absence, divers fun. Sélection aléatoire dans le contexte, sans répéter la dernière phrase utilisée.

## 9. Modèle de données (SwiftData)

- `UserProfile` : prénom, sexe, dateNaissance, tailleCm, poidsInitialKg, niveauActivité, objectifKcal (modifiable), objectifPas, préférencesRappels, dateCréation.
- `MealEntry` : date, créneau (petit-déj/déjeuner/dîner/encas), typePlat (id catalogue), portion, extras (ids + quantités), kcalEstimées, xpAttribué.
- `WeightEntry` : date, poidsKg.
- `DayLog` : date, pas (snapshot du soir), kcalMangées, objectifKcalDuJour, xpGagné, objectifKcalRespecté (bool, calculé le lendemain).
- **Traitements différés** : pas de background tasks garanties sans backend — la clôture des journées passées (snapshot de pas via l'historique HealthKit, attribution du +50 XP, calcul d'objectifKcalRespecté) et le renouvellement des quêtes du lundi s'exécutent en rattrapage au prochain passage de l'app au premier plan.
- `GamificationState` : xpTotal, niveau, badgesDébloqués [(id, date)], quêtesActives [(id, progression, semaine)], historique quêtes complétées.
- **Catalogues statiques** (JSON dans le bundle, pas en base) : plats + kcal, extras + kcal, badges, pool de quêtes, banque de messages Nivelito.

## 10. Intégrations système

- **HealthKit** : lecture des pas du jour et de l'historique (requête statistiques quotidiennes). Rafraîchi à chaque passage au premier plan. Autorisation refusée → cartes de pas masquées, quêtes de pas exclues du tirage.
- **Notifications locales** (chacune désactivable) :
  - 12 h 30 : rappel déjeuner ("Ton déjeuner mérite d'être loggé 🍽️")
  - 20 h 00 : rappel dîner
  - Samedi 9 h : rappel pesée hebdo
  - 18 h 00 : encouragement pas (texte générique, les notifications locales ne peuvent pas lire HealthKit au moment de l'envoi)
  - Textes tirés de la banque de messages, ton bienveillant.

## 11. Tests

Tests unitaires (XCTest) sur la logique métier :
- Calculs BMR / TDEE / objectif (cas hommes, femmes, bornes plancher).
- Estimation kcal des repas (plat × portion + extras).
- Attribution d'XP (plafonds quotidiens) et seuils de niveaux.
- Tirage et progression des quêtes hebdo (renouvellement le lundi, non-répétition).
- Déblocage des badges.
- Sélection des messages Nivelito (contexte correct, non-répétition immédiate).
La logique métier est isolée dans des types purs testables (sans dépendance UI/HealthKit) ; HealthKit est abstrait derrière un protocole avec fake pour les tests.

## 12. Hors périmètre v1

- Synchronisation entre les deux téléphones, backend, comptes en ligne.
- Apple Watch, widgets, Live Activities.
- Scan de code-barres, base alimentaire détaillée, photos de repas.
- Messages générés par IA (la banque de phrases est conçue pour être remplaçable par un LLM en v2).
- Streaks, classements compétitifs entre profils.
- Mode sombre (v1 = thème clair cozy uniquement).
- Publication App Store / TestFlight.

## 13. Risques et points d'attention

- **Expiration 7 jours** (compte gratuit) : re-build hebdomadaire des deux téléphones nécessaire ; documenter la procédure (README). Si trop contraignant à l'usage → envisager le compte payant (99 €/an).
- **Précision des estimations** : assumée approximative ; l'app affiche "~" devant les kcal estimées pour rester honnête.
- **Pas sans téléphone sur soi** : les pas iPhone sous-estiment l'activité réelle ; le ton de l'app n'en fait jamais un échec.
