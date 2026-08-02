# Nivel — Spécification Timing & rappels (v1.9)

Date : 2026-08-02
Statut : validé avec Michaël (brainstorm du 02/08/2026, maquettes du visual companion)
Référence : étend le timer d'exercice (`2026-07-31-exercise-timer-design.md`) et les rappels de la v1 (`2026-07-29-nivel-v1-design.md` §10).

Ce document est le **lot B** d'une demande en trois lots. Les deux autres feront leurs propres specs :

- **Lot A — Repas précis** : kcal saisies à la main, détail et accompagnements, quantité en grammes, catalogue de boissons élargi.
- **Lot C — Programme posture de Marion** : exercices ciblés, ciblage par profil, rappel du soir. Dépend du catalogue de rappels introduit ici (§3).

Ordre d'exécution retenu : **B, puis A, puis C**. Le lot B est court et livrable vite ; son catalogue de rappels sert directement au lot C.

## 1. Vision

Trois irritants d'usage, sans rapport entre eux sauf qu'ils touchent tous au temps.

1. **Le timer ne s'entend pas.** Le son de fin est un « Tink » système minuscule, muet dès que l'iPhone est en silencieux. On ne sait pas, sans regarder l'écran, qu'une étape est finie ni si la séance est terminée.
2. **Les rappels sont figés.** Quatre horaires écrits en dur dans le code. Ils ne conviennent pas forcément aux deux personnes qui utilisent l'app.
3. **Les durées sport sont approximatives.** Trois durées imposées par activité, et l'app enregistre la durée choisie même quand le timer dit autre chose.

Rien ici ne change la philosophie : zéro pression, opt-in, l'app informe et n'ordonne pas.

## 2. Décisions validées

- **Deux chimes embarqués**, générés par script, joués **même en mode silencieux**, avec un interrupteur dans les Réglages. Un son distinct pour « étape suivante » et pour « c'est terminé ».
- **Pas d'enchaînement automatique** des étapes. Le son signale, l'utilisateur tape. L'avance automatique réclamerait une modélisation de la récupération : hors périmètre, éventuellement une spec à part un jour.
- **Heure modifiable sur les quatre rappels**, plus le jour de la semaine pour la pesée. Pas de création de rappels sur mesure.
- **Disposition « tout sur une ligne »** pour les réglages de rappel (maquette A).
- **Durée libre en sport** via une quatrième puce « Autre » qui déplie une roue sur place (maquette A), **et** enregistrement du temps réellement écoulé quand on s'arrête plus tôt.

## 3. Le son du timer

### 3.1 Les deux fichiers

`scripts/gen-sounds.swift` synthétise deux fichiers `.caf` dans `App/Resources/Sounds/`, committés. Même principe que `scripts/gen-icons.swift` : une source unique dans le dépôt, un asset régénérable, jamais un fichier trouvé ailleurs. Script idempotent.

| Fichier | Contenu | Durée visée | Sens |
|---|---|---|---|
| `timer_step.caf` | une note chaude (fondamentale + une harmonique, enveloppe courte) | ~0,35 s | cette étape est finie, passe à la suite |
| `timer_done.caf` | trois notes montantes (do, mi, sol) | ~0,9 s | c'est terminé |

Mono, 44,1 kHz, PCM 16 bits. Attaque douce et extinction complète : aucun clic en fin de buffer.

### 3.2 La couche de lecture

`App/Services/SoundPlayer.swift`, `@MainActor` :

- Deux `AVAudioPlayer` construits à la première lecture, `prepareToPlay()`, gardés en mémoire pour la durée de vie du processus. Aucune latence au déclenchement.
- Session audio en catégorie `.playback` avec l'option `.mixWithOthers`. `.playback` est ce qui fait sonner malgré l'interrupteur silencieux ; `.mixWithOthers` évite de couper la musique ou le podcast en cours.
- La session est activée à la première lecture et **jamais désactivée** ensuite : activer/désactiver à chaque son produit des micro-coupures dans l'audio des autres apps.
- Toute erreur d'`AVAudioSession` ou d'`AVAudioPlayer` est avalée silencieusement. Un son qui ne part pas ne fait jamais crasher ni ne remonte à l'écran.

### 3.3 Où ça sonne

| Surface | Chime |
|---|---|
| Player, fin d'une étape non finale (`number < stepCount`) | `step` |
| Player, fin de la dernière étape (`number == stepCount`) | `done` |
| Activité libre (`ActivityLogSheet`), fin du timer | `done` |

Les deux règles d'honnêteté existantes sont conservées telles quelles : rien ne sonne si le dépassement atteint 2 s (fin vécue en différé, app en arrière-plan), rien ne sonne dans le player si la page n'est pas la page courante.

### 3.4 Dette payée : un seul bloc tick

La v1.5 avait noté un bloc tick → son dupliqué à l'identique entre `ActivityLogSheet` (lignes 102-110) et `StepPageView` (lignes 265-277). Les deux doivent changer de toute façon pour choisir leur chime. La logique part en deux morceaux, pour que la décision soit testable sans jouer un son.

**Décision pure** (NivelCore, testable) :

```
TimerChime.decide(overrun:transitioned:isCurrent:soundEnabled:) -> Feedback?
```

`Feedback` porte le retour haptique et, optionnellement, le chime à jouer. Retourne `nil` quand il ne s'est rien passé. C'est ici que vivent le seuil des 2 s, le filtre `isCurrent` et le réglage de son.

**Site d'appel** (App), un seul helper partagé par les deux surfaces :

```
TimerChime.onTick(timer:at:isCurrent:chime:) -> Bool
```

qui concentre l'ordre imposé « lire `overrun` **avant** `syncNow` », appelle `decide`, puis exécute le retour renvoyé. `ActivityLogSheet` n'a pas de notion de page courante et passe donc `isCurrent: true`. Retourne `true` si la transition a eu lieu, pour que l'appelant garde la main sur le reste.

Le réglage de son est lu au site d'appel et **passé en paramètre** à `decide` : la décision reste pure, les tests n'ont pas à toucher aux `UserDefaults`.

### 3.5 Le réglage

Nouvelle carte « Son » dans les Réglages, **entre Objectifs et Rappels** :

- Un interrupteur « Son du timer », sous-titre « sonne même en mode silencieux ». Le sous-titre est honnête sur le comportement inhabituel, il ne le cache pas.
- Actif par défaut.
- Stocké **par appareil** dans `UserDefaults` sous la clé `nivel.timerSound`, comme le thème : c'est une préférence de téléphone, pas de profil. Aucune migration SwiftData, aucun impact sur l'instantané du widget.
- L'haptique reste active indépendamment du réglage : couper le son ne coupe pas le retour tactile.

### 3.6 Compromis assumé

Sonner par-dessus l'interrupteur silencieux est un choix fort pour une app par ailleurs très douce. Le garde-fou : cela n'arrive **que** sur un timer lancé explicitement par l'utilisateur quelques minutes plus tôt, jamais à froid, et l'interrupteur des Réglages le désactive complètement.

## 4. Les rappels configurables

### 4.1 Le catalogue (NivelCore)

`ReminderDefinition` : identifiant, titre, heure et minute par défaut, jour par défaut (`Int?`, convention `Calendar` : 1 = dimanche), drapeau « jour modifiable », contexte de la banque de messages.

`ReminderCatalog.all` reprend **exactement** les valeurs actuelles de `NotificationService.reminders` :

| id | Titre | Défaut | Jour modifiable | Contexte |
|---|---|---|---|---|
| `lunch` | Déjeuner | tous les jours, 12 h 30 | non | `.midday` |
| `dinner` | Dîner | tous les jours, 20 h 00 | non | `.evening` |
| `weigh` | Pesée | samedi, 9 h 00 | **oui** | `.weighReminder` |
| `steps` | Pas | tous les jours, 18 h 00 | non | `.stepsEncouragement` |

Le lot C ajoutera une cinquième entrée et rien d'autre.

### 4.2 Le stockage (UserProfile)

Deux nouvelles propriétés sur `UserProfile` :

```swift
var reminderTimes: [String: Int] = [:]     // id → minutes depuis minuit (0...1439)
var reminderWeekdays: [String: Int] = [:]  // id → jour (1...7)
```

**Le défaut est écrit sur la déclaration, pas seulement dans l'`init`.** C'est ce qui rend la migration SwiftData légère, et c'est la leçon de `completedThisWeekQuestIDs` en v1 : le défaut de l'`init` ne suffit pas pour les stores existants.

Clé absente = valeur du catalogue. Les deux téléphones déjà installés retrouvent donc leurs horaires actuels sans aucune action.

Règle SwiftData déjà en vigueur dans le projet : **réassignation complète du dictionnaire** à chaque écriture, jamais de mutation en place.

### 4.3 La planification (NivelCore + App)

Le calcul sort de `NotificationService` pour devenir pur et testable :

```
ReminderPlanner.planned(enabled:times:weekdays:) -> [PlannedReminder]
```

`PlannedReminder` : id, heure, minute, jour (`Int?`), contexte. Le planificateur :

- ignore les rappels dont `enabled[id] != true` ;
- applique la surcharge quand elle existe, le défaut du catalogue sinon ;
- **borne les valeurs aberrantes sur le défaut du catalogue** : minutes hors `0...1439`, jour hors `1...7`, jour posé sur un rappel dont le jour n'est pas modifiable ;
- ignore les identifiants inconnus des dictionnaires (résidus d'une version antérieure).

`NotificationService` garde ce qui lui est propre : la vérification d'autorisation, le compteur de génération, le tirage du texte dans la banque, et le bloc `removeAllPendingNotificationRequests` + `add` **synchrone** (aucun `await` entre les deux, l'atomicité actuelle est préservée).

Contrainte de concurrence à respecter : `UserProfile` est un `@Model`, donc non `Sendable`. `reschedule(for:)` capture aujourd'hui `profile.name` et `profile.remindersEnabled` **avant** tout passage asynchrone ; il doit désormais capturer aussi `reminderTimes` et `reminderWeekdays` au même endroit, et ne plus jamais toucher au profil après le premier `await`.

Faire tourner une roue d'heure émet des dizaines de changements, donc autant de re-planifications. Le compteur de génération déjà en place les absorbe : chaque appel devenu obsolète pendant son `await` est abandonné, seul le dernier écrit réellement. Aucun anti-rebond supplémentaire n'est nécessaire.

### 4.4 L'écran (maquette A, « tout sur une ligne »)

Chaque ligne de la carte « Rappels » : titre, sous-titre de fréquence, puis à droite le sélecteur de jour (pesée seulement), le sélecteur d'heure, l'interrupteur.

Les deux sélecteurs sont **natifs et déjà employés dans ce fichier** : `DatePicker(displayedComponents: .hourAndMinute)` en style `.compact` (comme la date de naissance) et `Picker` en style `.menu` (comme le niveau d'activité). Aucun contrôle maison.

- **Rappel éteint** : les deux sélecteurs passent en `.disabled(true)` et iOS les grise de lui-même. Un rappel coupé n'affiche donc pas une heure d'apparence active.
- **Sous-titres calculés**, plus de texte en dur : « tous les jours » ou « chaque semaine ».
- **Accessibilité** : la ligne est un élément combiné dont le libellé porte la phrase entière, par exemple « Pesée, le samedi à 9 h ». Sans cela VoiceOver énoncerait trois contrôles décousus.
- Le binding d'heure convertit minutes ↔ `Date` via `DateComponents` dans le calendrier courant, sur un jour de référence arbitraire. Seuls l'heure et la minute sont lus en retour.
- Chaque modification (interrupteur, heure, jour) déclenche le `save()` local de `SettingsView` puis `NotificationService.reschedule`.

### 4.5 Le formatage français (NivelCore, pur)

`ReminderSchedule.frLabel(hour:minute:weekday:)`, avec minutes sur deux chiffres et minutes omises à zéro :

| Entrée | Sortie |
|---|---|
| 12 h 30, tous les jours | `tous les jours à 12 h 30` |
| 20 h 00, tous les jours | `tous les jours à 20 h` |
| 8 h 05, tous les jours | `tous les jours à 8 h 05` |
| 0 h 00, tous les jours | `tous les jours à 0 h` |
| 9 h 00, samedi | `le samedi à 9 h` |
| 9 h 00, dimanche | `le dimanche à 9 h` |

## 5. La durée en sport

### 5.1 La durée libre

Une quatrième puce « Autre » rejoint les trois durées du catalogue dans `ActivityLogSheet`.

- La sélectionner déplie une roue de minutes **sur place**, sous la rangée de puces, avec l'estimation kcal en dessous. Pas de feuille au-dessus de la feuille : `ActivityLogSheet` est déjà en détent `.large`, la place existe.
- Plage : **1 à 240 minutes**, pas de 1 minute.
- Valeur d'ouverture : la durée déjà sélectionnée si une puce l'était, sinon la durée médiane du catalogue de l'activité. On part toujours d'une valeur plausible.
- État de la puce : tant qu'elle n'a pas été choisie, elle affiche « Autre » sans sous-titre, là où les trois puces du catalogue affichent leurs kcal. Une fois choisie, son sous-titre devient la valeur courante (« 25 min »), et l'estimation kcal correspondante s'affiche sous la roue.
- Ensuite tout se comporte comme une puce classique : `Activity.estimatedKcal(minutes:)` inchangé, timer créé sur la durée, XP inchangée (30, plafond de 2 par jour).
- La séance du jour n'est pas concernée : ses étapes restent composées.

Comportement hérité conservé : changer de durée pendant qu'un timer tourne le remet à zéro. C'est déjà le cas au tap sur une autre puce, et « Recommencer » couvre le geste.

### 5.2 Le temps réellement écoulé

**Limite trouvée dans le code existant** : `ExerciseTimerModel.elapsed(at:)` est plafonné à la durée (`min(duration, ...)`, ligne 30). Le modèle ne peut donc jamais rapporter un dépassement. Capturer « j'ai fait 23 min au lieu de 20 » exigerait de toucher à la machine à états, à l'anneau et à la phase `finished`. Ce n'est pas fait : en pratique on s'arrête quand ça sonne, et le cas « j'ai fait 1 h 40 » est désormais couvert par la durée libre.

On capture donc **l'arrêt anticipé**, qui est le vrai cas d'usage. Fonction pure dans NivelCore :

```
LoggedDuration.resolve(chosenMinutes:elapsedSeconds:timerUsed:) -> Int
```

| Situation | Résultat |
|---|---|
| Timer jamais lancé (`timerUsed == false`) | `chosenMinutes` |
| Timer allé au bout (phase `finished`) | `chosenMinutes` |
| Timer en cours ou en pause à la validation | `elapsedSeconds / 60` arrondi, minimum 1, plafonné à `chosenMinutes` |

Les kcal sont recalculées sur la durée réellement enregistrée.

### 5.3 L'affichage de la durée enregistrée

Dans `ActivityLogSheet` uniquement (la séance du jour enregistre toujours le total de ses étapes), quand la durée enregistrée diffère de la durée choisie, une ligne discrète apparaît **au-dessus** du bouton de validation : « noté : 14 min ». Le libellé du bouton ne change pas.

Raison : le bouton porte déjà « C'est fait ! (+30 XP) ». Y insérer la durée le rend trop long pour un iPhone compact, et l'XP affichée compte (elle tombe à zéro une fois le plafond du jour atteint). La ligne séparée dit la vérité sans encombrer le bouton.

## 6. Ce qui ne change pas

- La séance du jour, sa rotation déterministe, ses étapes, ses graduations.
- L'XP, les plafonds journaliers, les quêtes, les badges.
- L'instantané du widget et sa timeline. Aucune des sept clés ne bouge.
- Le son des notifications de rappel : elles gardent `UNNotificationSound.default`.
- Le calcul des kcal des repas, le catalogue des plats, le journal.
- La machine à états du timer, hormis l'exposition de l'écoulé au moment de la validation.

## 7. Hors périmètre, explicitement

- L'enchaînement automatique des étapes du player et la modélisation de la récupération.
- La création, la suppression ou le renommage de rappels sur mesure.
- Un son personnalisé pour les notifications.
- La modification de la durée des séances composées.
- La capture d'une durée **supérieure** à la durée choisie (voir §5.2).

## 8. Tests

**NivelCore**

- `ReminderCatalog` : les quatre défauts épinglés valeur par valeur. Ce test garantit qu'aucun téléphone déjà installé ne voit ses horaires bouger.
- `ReminderSchedule.frLabel` : la table du §4.5, plus les sept jours de la semaine.
- `ReminderPlanner.planned` : rappel éteint absent du résultat ; surcharge appliquée ; minutes à -1 et à 1440 ramenées au défaut ; jour à 0 et à 9 ramenés au défaut ; jour posé sur un rappel non modifiable ignoré ; identifiant inconnu ignoré.
- `LoggedDuration.resolve` : la table du §5.2, plus les bords 0 s, 29 s (donne 1), écoulé égal à la durée, durée libre à 240.

**App**

- `TimerChime.decide` (NivelCore) : silence quand `isCurrent` est faux, quand le dépassement atteint 2 s, quand `soundEnabled` est faux, et quand il n'y a pas eu de transition. Haptique présente même sans son. Logique pure, aucun son réellement joué.
- Choix du chime selon (numéro d'étape, nombre d'étapes) : `step` pour une étape intermédiaire, `done` pour la dernière et pour l'activité libre.
- Présence des deux `.caf` dans le bundle, non vides, durée épinglée, dans l'esprit de `SportAssetsTests`.
- `ActivityLogSheet` : la puce « Autre » crée le timer sur la valeur de la roue.
- Persistance : modifier une heure dans les Réglages l'écrit dans le profil et produit le bon sous-titre.

## 9. Livraison

- Version **1.9 (build 10)** dans `project.yml`, sur les **deux** cibles. Sinon XcodeGen retombe sur 1.0/1 (leçon v1.6).
- Aucun tiret cadratin dans les textes utilisateur. Le test `testNoBundleResourceContainsEmDash` continue de couvrir les ressources JSON ; les `.caf` ne sont pas du texte.

**À vérifier sur les téléphones, par Michaël**

1. Le chime sonne interrupteur silencieux activé, et ne coupe pas une musique en cours.
2. Le chime « une note » et le chime « trois notes » se distinguent à l'oreille sans regarder l'écran.
3. Au premier lancement, le store existant s'ouvre et **les quatre rappels ont gardé leurs horaires actuels** (migration des deux dictionnaires sur `UserProfile`).
4. Une notification arrive bien à l'heure modifiée, le lendemain.
5. Les deux iPhones sont buildés depuis le même commit.
