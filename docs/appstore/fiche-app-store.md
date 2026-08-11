# Fiche App Store — Nivel

Tout ce qui doit être saisi dans App Store Connect, prêt à copier-coller.

⚠️ **Ce fichier est lu par `scripts/asc-fiche.py`**, qui écrit ces champs directement dans
App Store Connect : chaque valeur est le bloc de code qui suit son libellé en gras. Modifier
un texte ici puis relancer le script suffit ; ne pas renommer les libellés en gras.
App : `6797520298` · Bundle id : `com.elitedangereuse.Nivel` · Team : `AXVF69V3LL`
Langue de la fiche : **français (France)** · Diffusion : **France uniquement**

---

## 1. Informations de la version

**Nom** (30 max)

```
Nivel
```

**Sous-titre** (30 max — 26 utilisés)

```
Perdre du poids en douceur
```

**Texte promotionnel** (170 max — modifiable sans nouvelle version)

```
Nivelito, petit panda roux, t'accompagne sans jamais juger : repas notés en trois gestes, sport tout doux, quêtes et badges. Un jour « raté », ça n'existe pas ici.
```

**Description** (4 000 max)

```
Nivel est une app de perte de poids qui ne gronde jamais.

On note ses repas en quelques secondes, on suit ses pas et son poids, on valide de petites activités physiques — et on gagne de l'expérience, des niveaux, des quêtes et des badges, façon jeu vidéo cozy.

ZÉRO PRESSION, C'EST LA RÈGLE DU JEU
Pas de rouge, pas de série à ne pas casser, pas de reproche. Un jour « raté » n'existe pas. Nivelito, le petit panda roux qui t'accompagne, encourage — il ne juge pas.

LES REPAS EN TROIS GESTES
Un catalogue de 85 aliments : plats composés, accompagnements, boissons, encas. L'estimation des calories s'affiche immédiatement, et tu peux descendre au détail de l'ingrédient et au gramme si tu en as envie — ou simplement saisir un chiffre à la main. Ton objectif quotidien est calculé à partir de ton profil (formule de Mifflin-St Jeor, moins un déficit doux).

DU SPORT TOUT DOUX
20 activités et 11 séances composées, chacune illustrée par Nivelito, avec des consignes « comment faire » et un rythme suggéré. Marche, danse libre, yoga, gainage, étirements, ménage actif : rien d'intimidant.

UNE SÉANCE DU JOUR GUIDÉE
Une étape par écran, un minuteur en anneau facultatif que tu lances seulement si tu le veux. Jamais d'avance automatique : c'est un guide, pas un chef.

XP, NIVEAUX, QUÊTES ET BADGES
18 quêtes hebdomadaires tirées le lundi, 24 badges à débloquer, une progression toujours visible et jamais de score négatif.

DES PROGRÈS HONNÊTES
Tendance de poids lissée plutôt que le chiffre brut du jour, pas quotidiens lus dans l'app Santé (facultatif), historique de tes journées.

DES WIDGETS
Sur l'écran d'accueil et sur l'écran verrouillé : ton objectif du jour, une nouvelle phrase de Nivelito chaque heure, et un raccourci pour noter un repas en un geste.

QUATRE THÈMES COZY
Crème, Menthe, Océan et Nuit douce. Réglable sur chaque téléphone.

100 % LOCAL, VRAIMENT
Aucun compte, aucun serveur, aucune publicité, aucune mesure d'audience. Tes données ne quittent pas ton iPhone — nous n'y avons jamais accès. L'app fonctionne entièrement hors connexion.

Nivel est en français, conçu et développé en France, et son code est ouvert (licence MIT).

Nivel n'est pas un dispositif médical et ne remplace pas l'avis d'un professionnel de santé.
```

**Nouveautés de cette version** (4 000 max — version 1.13)

```
Six retours d'usage de la première semaine, dont deux corrections.

• Le widget reste lisible quand l'écran d'accueil est en mode transparent ou teinté : Nivelito ne se réduit plus à une silhouette blanche.
• Nouveau bouton « Noter une activité » sur l'accueil, pour déclarer ce que tu viens de faire sans passer par l'onglet Sport.
• « Logger un repas » devient « Noter un repas », et le bouton est maintenant aussi dans l'onglet Repas.
• Dans un repas en cours, un élément se retire d'un glissement vers la gauche.
• Les annonces de trophée s'écartent d'un glissement vers le haut, quand tu n'as pas envie de les lire.
```

**Mots-clés** (100 max — 94 utilisés, séparés par des virgules sans espace)

```
mincir,kcal,calories,repas,podomètre,marche,journal,motivation,bienveillant,cozy,quêtes,badges
```

**URL d'assistance** (obligatoire)

```
https://optimuskoala.github.io/Nivel/support.html
```

**URL marketing** (facultatif)

```
https://optimuskoala.github.io/Nivel/
```

**Copyright**

```
2026 L'Élite Dangereuse
```

---

## 2. Catégories

| Champ | Valeur |
|---|---|
| Catégorie principale | Santé et remise en forme |
| Catégorie secondaire | Style de vie |

`LSApplicationCategoryType` est déjà positionné sur `public.app-category.healthcare-fitness`
dans `project.yml`.

---

## 3. Confidentialité de l'app

**URL de la politique de confidentialité** (obligatoire)

```
https://optimuskoala.github.io/Nivel/privacy.html
```

**Questionnaire « Pratiques en matière de confidentialité des données »**

> Réponse : **« Non, nous ne collectons aucune donnée de cette application »**.

C'est exact et vérifiable : l'app n'a aucun appel réseau, aucun SDK tiers, aucun compte.
Les données de santé (pas) sont lues depuis HealthKit, affichées, et jamais transmises —
lire une donnée sur l'appareil sans l'exfiltrer n'est pas une collecte au sens d'Apple.

Le manifeste `PrivacyInfo.xcprivacy` embarqué déclare la même chose, plus l'unique API à
motif requis utilisée : `NSPrivacyAccessedAPICategoryUserDefaults`, motif `CA92.1`
(réglages de l'app et pont vers ses widgets).

---

## 4. Classification par âge

Répondre **« aucun / non »** à l'ensemble du questionnaire : pas de violence, pas de contenu
sexuel, pas de jeu d'argent, pas de contenu généré par les utilisateurs, pas de lien vers
l'extérieur, pas d'achat intégré. Résultat attendu : **4+**.

Nuance à ne pas cocher de travers : Nivel ne donne aucun traitement ni conseil médical, il
n'y a donc pas de « contenu médical ». La phrase de non-responsabilité est déjà dans la
description.

---

## 5. Prix et disponibilité

| Champ | Valeur |
|---|---|
| Prix | Gratuit |
| Achats intégrés | Aucun |
| Disponibilité | France uniquement |
| Distribution sur Vision Pro / Mac | Non |

---

## 6. Informations sur l'app (une seule fois, pas par version)

| Champ | Valeur |
|---|---|
| Nom de l'entité juridique | L'Élite Dangereuse |
| Utilisation de l'IDFA | Non |
| Chiffrement | Exempté — `ITSAppUsesNonExemptEncryption = false` est dans l'Info.plist, aucun questionnaire ne sera posé |
| Droits sur le contenu | Contient uniquement du contenu original |

---

## 7. Notes pour l'équipe de validation (« App Review Information »)

```
Bonjour,

Nivel fonctionne entièrement hors connexion : aucun compte à créer, aucun identifiant de
test nécessaire. Il suffit d'ouvrir l'app et de renseigner le profil demandé au premier
lancement (prénom, sexe, date de naissance, taille, poids, niveau d'activité) pour accéder
à toutes les fonctions.

L'accès à HealthKit (lecture du nombre de pas uniquement, jamais d'écriture) est facultatif :
si l'autorisation est refusée, l'app fonctionne normalement, sans compteur de pas.

L'app est en français uniquement et diffusée en France uniquement.

Aucune donnée n'est collectée : pas d'appel réseau, pas de SDK tiers, pas de publicité,
pas d'analytique. Le code source est public : https://github.com/OptimusKoala/Nivel

Merci !
```

**Contact** : contact@elitedangereuse.fr

---

## 8. Captures d'écran

Huit captures 6,9 pouces (1320 × 2868), dans `docs/appstore/framed/`, à téléverser **dans
cet ordre** — les trois premières sont les seules visibles sans faire défiler :

| # | Fichier | Accroche |
|---|---|---|
| 1 | `01-home.png` | Ta journée d'un coup d'œil |
| 2 | `02-meallog.png` | Un repas en trois gestes |
| 3 | `03-sport.png` | Du sport tout doux |
| 4 | `04-session.png` | Nivelito bouge avec toi |
| 5 | `05-step.png` | Une étape par écran |
| 6 | `06-progress.png` | Des progrès honnêtes |
| 7 | `07-quests.png` | Des quêtes, zéro reproche |
| 8 | `08-night.png` | Quatre thèmes cozy |

La taille 6,9 pouces est la seule exigée pour l'iPhone : App Store Connect s'en sert pour
toutes les tailles inférieures. Les captures brutes, sans habillage, sont dans
`docs/appstore/raw/`.

Pour les régénérer après une évolution de l'app : `./scripts/screenshots.sh`.
