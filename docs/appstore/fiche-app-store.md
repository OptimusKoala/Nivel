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
Un catalogue de 153 aliments : plats composés, ingrédients, boissons, encas, desserts. L'estimation des calories s'affiche immédiatement, et tu peux descendre au détail de l'ingrédient et au gramme si tu en as envie — ou simplement saisir un chiffre à la main. Ton objectif quotidien est calculé à partir de ton profil (formule de Mifflin-St Jeor, moins un déficit doux).

DU SPORT TOUT DOUX
32 activités et 11 séances composées, chacune illustrée par Nivelito, avec des consignes « comment faire » et un rythme suggéré. Marche, danse libre, yoga, gainage, étirements, ménage actif : rien d'intimidant.

UNE SÉANCE DU JOUR GUIDÉE
Une étape par écran, un minuteur en anneau facultatif que tu lances seulement si tu le veux. Jamais d'avance automatique : c'est un guide, pas un chef.

XP, NIVEAUX, QUÊTES ET BADGES
25 quêtes hebdomadaires tirées le lundi, 38 badges à débloquer, une progression toujours visible et jamais de score négatif.

DES PROGRÈS HONNÊTES
Tendance de poids lissée plutôt que le chiffre brut du jour, pas quotidiens lus dans l'app Santé (facultatif), historique de tes journées.

DES WIDGETS
Sur l'écran d'accueil et sur l'écran verrouillé : ton objectif du jour, une nouvelle phrase de Nivelito chaque heure, et un raccourci pour noter un repas en un geste.

QUATRE THÈMES COZY
Crème, Menthe, Océan et Nuit douce. Réglable sur chaque téléphone.

À DEUX, SI TU VEUX
Le duo relie deux iPhone, et deux seulement. Tu vois la journée de l'autre, son anneau, ses repas, sa quête, et tu lui envoies un cœur quand ça te fait plaisir. Ni ton poids, ni ta courbe de poids, ni tes badges ne sont partagés. Aucun message, aucun classement : ce n'est pas un réseau social.

LOCAL PAR DÉFAUT
Aucun compte, aucun serveur à nous, aucune publicité, aucune mesure d'audience. Sans duo, rien ne sort de ton iPhone et l'app fonctionne entièrement hors connexion. Avec un duo, ta journée passe par ta zone iCloud privée, lisible par cette seule personne, et nous n'y avons jamais accès.

Nivel est en français, conçu et développé en France, et son code est ouvert (licence MIT).

Nivel n'est pas un dispositif médical et ne remplace pas l'avis d'un professionnel de santé.
```

**Nouveautés de cette version** (4 000 max — celles de la 1.15.1)

```
Une petite mise à jour pour le duo.

• Les cœurs reçus déclenchent désormais une vraie alerte, même quand Nivel n'est pas ouvert.
• Les alertes sont plus fiables pour les deux membres du duo, et ne s'affichent jamais lors du retrait d'un cœur.
• Désactiver les cœurs reçus ou défaire le duo coupe aussi les alertes associées.
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

> Réponse : **« Non, nous ne collectons aucune donnée de cette application »**, inchangée
> pour la 1.15. Ce questionnaire ne se remplit que dans l'interface d'App Store Connect :
> `asc-fiche.py` n'y touche pas.

C'était évident jusqu'à la 1.14, où l'app n'émettait aucune requête. Le duo de la 1.15 fait
sortir des données de l'appareil : la réponse reste la même, mais elle demande maintenant à
être défendue, et voici de quoi le faire en trois phrases devant un examinateur.

**Ce qui sort de l'appareil, et seulement quand un duo est appairé** : un prénom, le
personnage garçon ou fille du profil, un niveau et un total d'XP, les quatre nombres de
l'anneau du jour, un compte de pas, l'intitulé d'une quête, et la liste des repas et
activités du jour avec leurs heures et leurs kcal. Ni le poids, ni la courbe de poids, ni
les badges. Sans duo, rien ne part, et aucune requête n'est même émise.

**Où ça va** : dans une zone personnalisée d'une base **privée** CloudKit
(`iCloud.com.elitedangereuse.Nivel`), partagée par `CKShare` avec un seul autre
participant. La zone est décomptée sur le stockage iCloud de celui qui invite. Il n'existe
aucun serveur de l'éditeur, aucun SDK tiers, aucune régie, aucune analytique, et l'app
n'ouvre aucune autre connexion.

**Pourquoi ce n'est pas une collecte au sens d'Apple** : Apple définit « collecter » comme
transmettre des données hors de l'appareil **d'une manière qui les rende accessibles à
l'éditeur ou à ses partenaires**. Une base privée CloudKit ne donne à l'éditeur aucun accès
aux enregistrements : le tableau de bord ne montre que le schéma, jamais les données des
utilisateurs. Nous ne pouvons ni les lire, ni les exporter, ni les conserver. C'est la même
lecture que celle des apps qui n'utilisent que CloudKit privé et déclarent l'absence de
collecte, et c'est le même raisonnement que pour HealthKit : lire une donnée sur l'appareil,
ou la ranger dans l'iCloud de la personne, n'est pas la collecter.

**L'argument contraire, pour qu'il ne soit pas une surprise** : ces données sont bel et bien
**partagées avec un autre utilisateur**, et l'entitlement iCloud est visible dans le binaire.
Un examinateur peut s'arrêter là, considérer qu'un partage entre deux personnes est une
transmission à déclarer, et demander une fiche « données liées à l'utilisateur » (santé et
forme, plus un identifiant, plus le prénom). **C'est un pari assumé, pas une certitude, et un
rejet coûte un cycle de validation.** Le pari est pris parce que la réponse inverse
déclarerait une collecte qui n'a pas lieu, sur une app qui n'en fait aucune. S'il est perdu,
la marche à suivre est courte : répondre « oui » au questionnaire, cocher **Santé et forme**,
**Identifiants** et **Coordonnées (nom)**, tous **liés à l'utilisateur**, tous en usage
« Fonctionnalité de l'app », et **aucun** en suivi publicitaire. Le §7, notes pour l'équipe de
validation, explique déjà le duo et son fonctionnement : c'est là qu'il faut regarder d'abord
si une question arrive.

Le manifeste `PrivacyInfo.xcprivacy` embarqué déclare `NSPrivacyCollectedDataTypes` **vide**,
ce qui **dit exactement la même chose que la fiche** : les deux sont cohérents, et le
resteront tant que cette réponse ne change pas. Il déclare aussi l'unique API à motif requis
utilisée : `NSPrivacyAccessedAPICategoryUserDefaults`, motif `CA92.1` (réglages de l'app et
pont vers ses widgets).

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

Nivel fonctionne sans aucun compte à créer et sans identifiant de test : il suffit d'ouvrir
l'app et de renseigner le profil demandé au premier lancement (prénom, sexe, date de
naissance, taille, poids, niveau d'activité) pour accéder à toutes les fonctions.

Nouveauté de cette version, le « duo » relie deux iPhone : chacun voit la journée de l'autre
(calories, pas, repas, activités, quête en cours) et peut lui envoyer un cœur. Il se met en
place dans Réglages > Duo, en scannant un QR code, et demande donc DEUX appareils et un
compte iCloud actif ; sur un seul appareil, la section reste accessible et n'affiche aucune
erreur. Les données du duo transitent par une zone iCloud partagée entre les deux personnes
(CloudKit, conteneur iCloud.com.elitedangereuse.Nivel), jamais par un serveur à nous. Il n'y
a ni message, ni texte libre, ni contenu public : uniquement des chiffres, des intitulés
issus des catalogues de l'app, et un cœur.

L'accès à HealthKit (lecture du nombre de pas uniquement, jamais d'écriture) est facultatif :
si l'autorisation est refusée, l'app fonctionne normalement, sans compteur de pas.

L'app est en français uniquement et diffusée en France uniquement.

En dehors du duo, l'app n'émet aucune requête réseau : pas de SDK tiers, pas de publicité,
pas d'analytique. Le code source est public : https://github.com/OptimusKoala/Nivel

Merci !
```

**Contact** : contact@elitedangereuse.fr

---

## 8. Captures d'écran

Dix captures 6,9 pouces (1320 × 2868), dans `docs/appstore/framed/`, à téléverser **dans
cet ordre** — qui est aussi l'ordre alphabétique des fichiers, parce que `asc-fiche.py`
téléverse `sorted(framed/*.png)` : renuméroter est le seul moyen de changer l'ordre
d'affichage. Les trois premières sont les seules visibles sans faire défiler, d'où les
idées de saison en deuxième position.

| # | Fichier | Accroche |
|---|---|---|
| 1 | `01-home.png` | Ta journée d'un coup d'œil |
| 2 | `02-idees.png` | Des idées de saison |
| 3 | `03-meallog.png` | Un repas en trois gestes |
| 4 | `04-recette.png` | La recette, puis c'est noté |
| 5 | `05-sport.png` | Tout doux, ou ça pousse |
| 6 | `06-session.png` | Nivelito bouge avec toi |
| 7 | `07-step.png` | Une étape par écran |
| 8 | `08-progress.png` | Des progrès honnêtes |
| 9 | `09-quests.png` | Des quêtes, zéro reproche |
| 10 | `10-night.png` | Quatre thèmes cozy |

La taille 6,9 pouces est la seule exigée pour l'iPhone : App Store Connect s'en sert pour
toutes les tailles inférieures. Les captures brutes, sans habillage, sont dans
`docs/appstore/raw/`.

Pour les régénérer après une évolution de l'app : `./scripts/screenshots.sh`.
