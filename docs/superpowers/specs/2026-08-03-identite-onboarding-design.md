# Nivel — Spécification Identité à l'onboarding (v1.12)

Date : 2026-08-03
Statut : validé avec Michaël (brainstorm du 03/08/2026)
Référence : modifie la page 2 du premier lancement décrit en §5 de `2026-07-29-nivel-v1-design.md`, et la section Profil des Réglages (§6 du même document).

Changement mineur, un seul écran touché plus une ligne de Réglages. Pas de migration de données.

## 1. Le problème

La page 2 de l'onboarding propose deux cartes en dur : Michaël et Marion. Chaque carte remplit d'un seul geste le prénom **et** le sexe, puis avance.

C'était juste tant que l'app avait exactement deux utilisateurs connus d'avance. Ça ne l'est plus : l'écran demande à quelqu'un de se reconnaître dans une liste de deux prénoms qui ne sont pas forcément le sien. Le sexe, lui, est une donnée dont l'app a réellement besoin — il entre dans `CalorieCalculator.dailyTarget` — alors que le prénom n'est qu'un mot pour s'adresser à la personne.

On sépare donc les deux : le sexe se choisit, le prénom se saisit.

C'est le même raisonnement que celui qui a écarté le ciblage par prénom en v1.11 (« Pourquoi pas le prénom du profil », §3 de la spec Programme posture) : un prénom est une chaîne libre, pas un identifiant de comportement.

## 2. Décisions validées

- **Un seul écran**, pas deux : les cartes Homme/Femme et le champ prénom cohabitent sur la page 2. Le flux reste à cinq pages, les points de progression ne changent pas.
- **Le picker « Sexe » de la page Infos est conservé.** Il permet de corriger sans revenir en arrière — le flux n'a pas de bouton retour.
- **Le prénom est obligatoire** : bouton Continuer désactivé tant qu'il est vide, comme le poids l'est déjà sur la page Infos. Le repli `"Michaël"` codé en dur disparaît.
- **Le prénom devient modifiable dans les Réglages**, conséquence directe de la saisie libre : sans ça, une faute de frappe à l'onboarding serait définitive alors que le prénom s'affiche sur l'Accueil et dans les widgets.

## 3. La page 2

`ProfileChoicePage` devient `IdentityPage`. Elle passe d'un callback « un tap choisit et avance » à un formulaire à deux entrées terminé par un bouton Continuer, comme les pages Infos et Objectif.

```
        ● ━ ● ● ●

   🧡  ╭────────────────────╮
  Nivelito│ Et toi, tu es qui ? │
        ╰────────────────────╯

  JE SUIS
  ╭──────────╮  ╭──────────╮
  │   👦     │  │   👧     │
  │  Homme   │  │  Femme   │
  ╰──────────╯  ╰──────────╯

  MON PRÉNOM
  ╭──────────────────────────╮
  │ Michaël                  │
  ╰──────────────────────────╯

  ╭──────────────────────────╮
  │       Continuer          │
  ╰──────────────────────────╯
```

**Les cartes passent côte à côte** (`HStack`) au lieu d'empilées : deux options courtes, et ça laisse la place au champ prénom sans faire défiler.

**Elles doivent se lire « sélectionnée », pas « déjà tapée ».** Elles reprennent donc exactement le vocabulaire visuel d'`activityRow` sur la page Infos : bordure `Theme.orange` de 1,5 pt et fond `Theme.orange.opacity(0.10)` sur l'option retenue. Sans cet état, un écran qui ne réagit qu'en avançant ne dirait pas ce qui a été choisi.

Les assets `Avatars/boy` et `Avatars/girl` sont réutilisés tels quels, toujours en `Image(decorative:)` : le label Homme/Femme porte le sens, l'illustration décore. La raison d'origine tient toujours — un glyphe cozy monochrome ne fait pas un visage, et l'app a un langage d'illustrations couleur. `IconAssetsTests` continue de garantir leur présence, sans modification.

**Accessibilité** : chaque carte porte `.isSelected` quand elle l'est. `activityRow` ne le fait pas — elle s'appuie sur une coche visible — mais ici il n'y a pas de coche.

**Le champ prénom** reprend le duo `Overline` + `card()` d'`InfosPage`, avec `.textInputAutocapitalization(.words)` pour éviter le prénom en minuscules.

**Les deux étiquettes `Overline`** (« JE SUIS », « MON PRÉNOM ») remplacent le titre isolé « Choisis ton profil ». La page a maintenant deux entrées et chacune a besoin d'être nommée ; un titre global ne dirait plus lequel des deux champs il annonce. La bulle de Nivelito, « Et toi, tu es qui ? », ne change pas : elle vaut pour les deux.

## 4. « Pas encore choisi » doit être un état représentable

`sex` vaut aujourd'hui `.male` par défaut. Sur un écran qui demande explicitement de choisir, la carte Homme apparaîtrait pré-sélectionnée — et quelqu'un qui traverse l'onboarding sans y prêter attention obtiendrait un objectif calculé sur un sexe qu'il n'a jamais confirmé.

Le `@State` du flux devient donc `Sex?`, à nil au départ.

Le picker de la page Infos étant conservé, il reçoit une liaison dérivée non optionnelle :

```swift
private var sexBinding: Binding<Sex> {
    Binding(get: { sex ?? .male }, set: { sex = $0 })
}
```

`InfosPage` n'est pas modifiée. `computedTarget` et `complete()` lisent `sex ?? .male` : un repli inatteignable en pratique, puisqu'on ne quitte pas la page 2 sans avoir choisi, mais qui garde ces deux fonctions totales.

**Pourquoi pas un booléen `sexPicked` à côté d'un `sex` non optionnel** : deux variables pour un seul concept, qui peuvent se désynchroniser. L'optionnel dit la même chose sans état redondant.

## 5. Finalisation

`complete()` stocke le prénom saisi débarrassé de ses espaces de tête et de queue, sans valeur de secours — l'écran garantit qu'il est non vide.

`choose(profile:)` est supprimée : `advance()` devient directement l'action du bouton Continuer.

Le reste de `complete()` ne change pas : `WeightEntry` initiale, tirage des quêtes, `NotificationService.reschedule`, garde anti-doublon sur un profil existant.

## 6. Réglages : prénom modifiable

La ligne « Prénom » du bloc Profil passe d'un `Text` à un `TextField`.

Elle suit la mécanique de l'objectif kcal, qui résout déjà exactement ce problème d'un champ texte libre qui ne doit jamais persister une valeur invalide :

- un tampon `@State nameText`, initialisé dans `.onAppear` ;
- `commitName` ne persiste que si le prénom nettoyé est non vide et différent de l'actuel ;
- à la sortie de champ (`@FocusState`), le tampon réaffiche la valeur réellement enregistrée.

Conséquence : vider le champ puis l'abandonner retrouve l'ancien prénom au lieu de laisser un profil sans nom. Un profil sans nom afficherait un Accueil et un widget muets, sans qu'aucun écran ne signale le problème.

La persistance passe par le `save()` local, comme les autres lignes du bloc. La synchro widget est déjà couverte : `save()` appelle `game.syncWidget()`, et son commentaire mentionne déjà le prénom comme faisant partie du snapshot.

## 7. Tests

Nouveau `NivelTests/OnboardingIdentityTests.swift`, sur le modèle d'`ActivityLogSheetTests` et `SessionPlayerTests` : la décision est extraite en fonctions statiques pures sur la vue, testables sans piloter SwiftUI.

| Fonction | Cas couverts |
|---|---|
| `sanitizedName(_:)` | espaces de tête et de queue retirés ; prénom composé (« Jean-Marc », « Marie Claire ») préservé ; chaîne d'espaces → vide |
| `canLeaveIdentity(name:sex:)` | refus si sexe nil ; refus si prénom vide ; refus si prénom uniquement des espaces ; acceptation si les deux sont renseignés |

Et un test symétrique côté Réglages, dans le fichier de tests des Réglages existant ou un nouveau selon ce qui s'y prête : `commitName` avec une chaîne vide ou d'espaces ne remplace jamais le prénom persisté.

## 8. Hors périmètre

- « Fait avec 🧡 pour Michaël & Marion » dans la section À propos : c'est une dédicace, pas du flux utilisateur.
- Les prénoms en dur dans les `#Preview` et les tests : ce sont des canvas et des fixtures.
- Le commentaire de `QuestEngine` qui parle du tirage « chez Michaël ET chez Marion » : il illustre un raisonnement sur deux profils distincts, toujours valable.
