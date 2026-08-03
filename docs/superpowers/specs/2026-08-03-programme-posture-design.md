# Nivel — Spécification Programme posture (v1.11)

Date : 2026-08-03
Statut : validé avec Michaël (brainstorm du 03/08/2026, maquettes du visual companion)
Référence : étend la section Sport (`2026-07-30-sport-section-design.md`), les illustrations et le player (`2026-07-30-sport-illustrations-design.md`), le timer (`2026-07-31-exercise-timer-design.md`) et les rappels réglables (`2026-08-02-timing-rappels-design.md`).

Ce document est le **lot C**, dernier des trois. Le lot B est livré en v1.9, le lot A en v1.10.

## 1. Vision

Marion veut travailler sa posture : nuque enfoncée, épaules enroulées, ce qu'on appelle couramment une bosse de bison. Elle sait que des exercices ne font pas de miracle. **Ce dont elle a besoin, ce sont des exercices qui ont fait leurs preuves, et surtout de la rigueur et un rappel pour les faire.**

Cette phrase décide de tout ce qui suit : la valeur du lot n'est pas dans la liste d'exercices, elle est dans le fait qu'ils soient effectivement faits. Le programme choisit donc à sa place ce qu'elle fait ce soir, et un rappel arrive à 21 h.

### 1.1 Deux règles de langage, décidées explicitement

**L'app n'écrit jamais « bosse de bison ».** Elle nomme la zone : « Posture », « Nuque et haut du dos ». C'est le seul écran qui pointerait un défaut physique par son nom dans une app qui n'affiche jamais de rouge et ne dit jamais qu'un jour est raté.

**L'app ne promet pas de faire disparaître quoi que ce soit.** Ce qu'on appelle bosse de bison mêle une composante posturale, sur laquelle ces exercices agissent réellement, et parfois une composante adipeuse ou structurelle, sur laquelle ils n'agissent pas. Les textes disent donc ce que les exercices font vraiment : dégager la nuque, ouvrir la poitrine, réveiller les muscles qui tiennent les omoplates. Même honnêteté que le tilde des kcal et que « dépense indicative, jamais créditée au budget ».

## 2. Décisions validées

- **Ciblage par interrupteur**, pas par prénom. « Programme posture » dans les Réglages, éteint par défaut, `UserDefaults` par appareil.
- **Neuf exercices, cinq séances**, dans leurs propres catalogues, avec leur propre rotation quotidienne.
- **Soutien de la rigueur par une quête hebdomadaire** dédiée, plus un compteur mensuel factuel. **Aucun streak**, jamais.
- **Rappel quotidien à 21 h**, allumé en même temps que le programme, modifiable ensuite comme les autres.
- **Section Posture en tête** de l'onglet Sport (maquette B).
- **Les neuf illustrations sont générées par Michaël avant l'implémentation des catalogues** (option A).

## 3. Le ciblage

`PosturePlanSettings`, sur le modèle exact de `SoundSettings` en v1.9 : `@Observable`, `static let shared`, `UserDefaults` injectable pour les tests, clé `nivel.posturePlan`, **défaut faux**.

Allumer l'interrupteur fait trois choses :

1. la section Posture apparaît dans l'onglet Sport ;
2. le rappel de 21 h s'active, en posant explicitement `remindersEnabled["posture"] = true` ;
3. la quête posture devient tirable au prochain lundi.

L'éteindre retire les trois. Le rappel est alors désactivé de la même façon explicite, sinon il continuerait de sonner pour un programme invisible.

**Pourquoi pas le prénom du profil.** Tester `profile.name == "Marion"` mettrait le prénom d'une personne en dur dans une condition, casserait à un renommage, et ferait dépendre le comportement de l'app d'une chaîne saisie à l'onboarding. Un interrupteur éteint par défaut remplit le besoin réel, « que ça n'encombre pas mon écran à moi », sans rien de tout cela.

**Pourquoi pas un champ sur `UserProfile`.** Conceptuellement plus propre, mais une migration SwiftData et une interface de réglage pour un résultat identique sur deux téléphones qui ne se parlent pas.

## 4. Les exercices

Nouveau fichier `posture-activities.json`, même schéma que `activities.json` (`Activity` : id, name, emoji, location, kcalPerMin, durations, instructions). Tous à la maison, sans matériel.

| id | Nom | Emoji | kcal/min | Durées |
|---|---|---|---|---|
| `chin_tucks` | Rentrés de menton | 🙂 | 2,0 | 1 / 2 / 3 |
| `supine_chin_tuck` | Nuque allongée | 🛏️ | 2,0 | 2 / 3 / 5 |
| `wall_angels` | Anges au mur | 🙌 | 2,5 | 2 / 3 / 5 |
| `wall_thoracic` | Ouverture du dos au mur | 🧱 | 2,0 | 2 / 3 / 5 |
| `scapular_squeeze` | Rétractions d'omoplates | 🤲 | 2,5 | 1 / 2 / 3 |
| `prone_y_raise` | Relevés en Y au sol | 🔰 | 2,5 | 2 / 3 / 4 |
| `doorway_stretch` | Ouverture des pectoraux | 🚪 | 2,0 | 1 / 2 / 3 |
| `neck_stretch` | Étirement de la nuque | 🧣 | 2,0 | 2 / 3 / 4 |
| `open_book` | Rotation du buste au sol | 📖 | 2,0 | 2 / 3 / 5 |

Dépense volontairement basse : ce sont de la mobilité et du maintien, pas du cardio. Comme partout, ces kcal sont indicatives et **jamais créditées au budget**.

### 4.1 Les consignes

Trois à quatre puces chacune, ton coach doux, un repère de sécurité, comme les 20 activités existantes.

**`chin_tucks`, Rentrés de menton**
- Assise ou debout, regard droit devant, épaules relâchées
- Recule le menton à l'horizontale, comme pour faire un double menton, sans baisser la tête
- Tiens 5 secondes, relâche, recommence tranquillement
- Tu dois sentir un étirement à l'arrière du cou, jamais une douleur

**`supine_chin_tuck`, Nuque allongée**
- Allongée sur le dos, genoux pliés, sans coussin sous la tête
- Recule doucement le menton et allonge la nuque vers le haut du tapis
- Garde 5 secondes en respirant, puis relâche
- La tête reste posée : ce n'est pas un relevé, juste un allongement

**`wall_angels`, Anges au mur**
- Dos au mur, talons à quelques centimètres, bas du dos aussi plat que possible
- Bras en chandelier contre le mur, coudes et poignets au contact
- Fais glisser les bras vers le haut puis vers le bas, en gardant le contact
- Si les poignets décollent, réduis l'amplitude : mieux vaut petit et propre

**`wall_thoracic`, Ouverture du dos au mur**
- Face au mur, mains à plat au-dessus de la tête, coudes légèrement fléchis
- Recule les pieds et laisse la poitrine descendre entre les bras
- Respire dans le haut du dos, laisse-le s'ouvrir à chaque expiration
- Ne creuse pas le bas du dos : l'ouverture vient du haut

**`scapular_squeeze`, Rétractions d'omoplates**
- Assise ou debout, bras le long du corps, épaules basses
- Rapproche les omoplates l'une de l'autre, comme pour pincer une feuille entre elles
- Tiens 5 secondes sans monter les épaules vers les oreilles
- Relâche complètement entre chaque, c'est le relâchement qui fait le travail

**`prone_y_raise`, Relevés en Y au sol**
- À plat ventre, front posé, bras tendus devant en Y, pouces vers le plafond
- Décolle les bras de quelques centimètres en rapprochant les omoplates
- Tiens 3 secondes, redescends en contrôlant
- Le front reste posé : la tête ne participe pas

**`doorway_stretch`, Ouverture des pectoraux**
- Debout dans l'encadrement d'une porte, avant-bras contre le montant, coude à hauteur d'épaule
- Avance doucement d'un pas jusqu'à sentir l'avant de l'épaule s'ouvrir
- Respire, tiens 20 à 30 secondes, change de côté
- Un étirement confortable, jamais un pincement à l'avant de l'épaule

**`neck_stretch`, Étirement de la nuque**
- Assise, dos droit, une main posée sous la cuisse pour garder l'épaule basse
- Incline la tête de l'autre côté, oreille vers l'épaule, sans tourner
- Respire, tiens 20 à 30 secondes, change de côté
- Aucun à-coup, aucune traction avec la main : le poids de la tête suffit

**`open_book`, Rotation du buste au sol**
- Allongée sur le côté, genoux pliés remontés, bras tendus l'un sur l'autre devant toi
- Ouvre le bras du dessus en grand vers l'arrière, en suivant la main du regard
- Laisse les genoux posés, ce sont les épaules qui tournent
- Va où ça vient sans forcer, et respire une fois arrivée

## 5. Les cinq séances

Nouveau fichier `posture-sessions.json`, même schéma que `sessions.json` (`ActivitySession` : id, title, emoji, steps avec activityID, minutes, tempo, segments).

`SessionStep` exige un `tempo` par étape, affiché en badge dans le player, et accepte un `segments` optionnel qui dessine des graduations sur l'anneau du timer. Les deux sont donnés ici : sans eux l'implémenteur devrait les inventer.

| Séance | Étape | min | tempo | segments |
|---|---|---|---|---|
| `posture_evening`<br>Nuque & haut du dos<br>8 min | `chin_tucks` | 2 | 8 rentrés, 5 secondes chacun | 8 |
| | `wall_angels` | 3 | 10 montées lentes | 10 |
| | `neck_stretch` | 3 | 2 tenues de 30 s de chaque côté | 4 |
| `posture_open`<br>Ouverture<br>8 min | `doorway_stretch` | 2 | 2 tenues de 30 s de chaque côté | 4 |
| | `wall_thoracic` | 3 | 5 respirations, 3 fois | 3 |
| | `open_book` | 3 | 8 ouvertures de chaque côté | |
| `posture_strength`<br>Réveil des omoplates<br>7 min | `scapular_squeeze` | 2 | 10 pincements, 5 secondes chacun | 10 |
| | `prone_y_raise` | 3 | 3 séries de 8 | 3 |
| | `chin_tucks` | 2 | 8 rentrés, 5 secondes chacun | 8 |
| `posture_gentle`<br>Tout en douceur<br>6 min | `supine_chin_tuck` | 3 | 8 allongements tranquilles | 8 |
| | `open_book` | 3 | 8 ouvertures de chaque côté | |
| `posture_full`<br>Le tour complet<br>9 min | `chin_tucks` | 2 | 8 rentrés, 5 secondes chacun | 8 |
| | `wall_angels` | 3 | 10 montées lentes | 10 |
| | `doorway_stretch` | 2 | 1 tenue de 45 s de chaque côté | 2 |
| | `scapular_squeeze` | 2 | 10 pincements | 10 |

`open_book` n'a pas de graduations : « 8 de chaque côté » ne se découpe pas en tours d'anneau lisibles, et la spec du timer réserve `segments` aux séries explicites.

Cinq séances, donc une rotation sur cinq jours : la même ne revient que le sixième soir.

**« Tout en douceur » existe pour les soirs sans énergie**, et ce n'est pas un détail : un programme qui n'offre qu'un seul niveau d'effort se fait abandonner le premier soir de fatigue.

## 6. La rotation

Les catalogues posture sont **des fichiers séparés**, jamais versés dans `activities.json` ni `sessions.json`. Deux raisons, dont un interdit explicite de la spec sport :

1. les verser dans les catalogues globaux les afficherait sur les deux téléphones ;
2. surtout, **la rotation de la séance du jour passerait de 11 à 16 entrées**, donc la séance affichée chaque jour changerait pour tout le monde. La spec sport interdit de toucher à cette rotation.

**Pools séparés pour choisir, table unique pour résoudre.** Les listes affichées et les deux rotations restent cloisonnées, mais `GameService` fusionne activités globales et posture dans son dictionnaire d'ids : sans quoi une entrée posture dans « Fait aujourd'hui » ou dans le journal n'aurait plus de nom.

Aucun code de rotation nouveau : `DailySessionPicker.session(for:sessions:calendar:)` est déjà générique, on l'appelle avec le pool posture. Même référence fixe du 1ᵉʳ janvier 2026, modulo 5. Les deux téléphones verraient donc la même séance posture le même jour, ce qui est sans effet ici puisqu'un seul l'active, mais préserve la propriété.

## 7. La rigueur, sans streak

L'app n'a **délibérément aucun streak** : pas de série à ne pas casser, pas de jour raté, jamais de rouge. C'est ce qui la rend supportable, et le lot C ne fait pas exception. Trois leviers, tous non punitifs.

### 7.1 La séance déjà choisie

Le premier levier, et le plus fort : le soir, Marion ouvre l'onglet Sport et trouve la séance du jour déjà décidée. La friction du choix disparaît, et c'est elle qui fait qu'on s'y met ou pas.

### 7.2 La quête hebdomadaire

Un drapeau `requiresPosture` sur `Quest`, filtré dans `QuestEngine.weeklyDraw` exactement comme `requiresSteps` l'est déjà pour HealthKit. Nouvelle métrique `postureSessionsDone`.

**Décodage : le champ doit être optionnel avec un défaut à faux.** Les entrées existantes de `quests.json` ne le portent pas, et un `Bool` non optionnel ferait échouer le décodage de tout le catalogue, donc disparaître les quêtes de tout le monde. `decodeIfPresent` et un `init(from:)` explicite, comme `SessionStep.segments` en v1.5.

**Comptée en jours distincts**, comme `dailySessionsDone` : quatre séances en une soirée valent une. Sinon la quête récompense le bachotage plutôt que la régularité, c'est-à-dire l'inverse de ce qu'on cherche.

Trois quêtes ajoutées au pool, toutes `requiresPosture: true` : 3, 4 et 5 séances posture sur la semaine.

Comme toutes les quêtes de l'app : tirée le lundi, XP à la clé, et **jamais reprochée si elle n'est pas finie**. La semaine suivante en redonne une autre, sans commentaire.

### 7.3 Le compteur mensuel

« 12 soirs ce mois-ci » sous le titre de la carte. Un fait, pas un jugement : aucun objectif, aucune jauge, donc rien à manquer.

**Compté en jours distincts, comme la quête**, et le libellé dit « soirs » plutôt que « séances » pour le refléter. Deux compteurs qui comptent différemment la même chose afficheraient 3 dans la quête et 5 sur la carte pour la même semaine, et personne ne pourrait deviner pourquoi.

### 7.4 Ce qui est explicitement refusé

Pas de série de jours consécutifs. Pas de notification qui insiste ou qui relance. Pas de « tu n'as rien fait depuis trois jours ». Ces mécaniques marchent quelques semaines et font désinstaller ensuite.

## 8. L'XP

`ActivityKind` gagne un cas `posture`. `XPEngine` gagne une action `postureSessionDone`, **40 XP, plafond d'une par jour, indépendant de celui de la séance du jour**.

L'indépendance est nécessaire : réutiliser l'action `dailySessionDone` ferait que faire la séance du jour ET la séance posture le même soir n'en paierait qu'une, ce qui punirait exactement le comportement qu'on veut installer.

Les exercices posture pris à l'unité rapportent l'XP d'activité existante, avec son plafond de deux par jour, sans changement.

## 9. L'écran

Section « Posture » **en tête de l'onglet Sport**, avant la séance du jour (maquette B, validée) :

- le titre « Sport » reste tout en haut : c'est l'en-tête de la première section de la `List`, il suit donc la section Posture qui devient première ;
- l'overline « Posture » ;
- la carte de la séance du soir, même forme que `DailySessionCardContent`, avec le compteur mensuel en sous-titre ;
- les neuf exercices en lignes, même forme que les sections « À la maison » et « Dehors ».

Puis la séance du jour, puis les sections existantes, inchangées.

**Le coût assumé** : la séance du jour, cœur de l'onglet depuis la v1.3, passe au deuxième rang chez Marion. C'est le prix du raisonnement de §1 : le rappel de 21 h ouvre l'app, et ce qu'il y a à faire doit être la première chose sous le titre, sans défiler ni chercher.

Le player et la feuille d'activité sont réutilisés tels quels : `SessionPlayerSheet` pour la séance, `ActivityLogSheet` pour un exercice à l'unité, avec leur timer, leurs consignes et leurs chimes de la v1.9.

## 10. Le rappel de 21 h

Cinquième entrée de `ReminderCatalog` :

| id | Titre | Défaut | Jour modifiable | Contexte |
|---|---|---|---|---|
| `posture` | Posture | tous les jours, 21 h 00 | non | `.postureReminder` |

21 h et non 20 h 30 : le rappel « Dîner » sonne à 20 h, et deux notifications collées se font ignorer toutes les deux. Heure modifiable au sélecteur depuis la v1.9.

**Son propre contexte de messages**, `postureReminder`, avec **douze** textes dans `messages.json`, plutôt que de réutiliser `.evening` qui parlerait de dîner. Même approche que `weighReminder` en v1. Ton du reste de la banque : jamais d'injonction, jamais de reproche. Par exemple « Cinq minutes pour ta nuque, ça se fait bien avant le canapé 🧡 », jamais « tu n'as pas fait ta séance ».

**La clé `remindersEnabled["posture"]` est posée explicitement** quand l'interrupteur s'allume. C'est ce qui neutralise le piège documenté en v1.9 : une entrée ajoutée au catalogue naît éteinte, puisqu'une clé absente vaut désactivé.

## 11. Les illustrations

**Premier livrable, et il est de Michaël** (option A choisie).

`SportAssetsTests` exige que chaque entrée des catalogues sport ait son illustration embarquée. Les catalogues posture doivent donc atterrir **après** les images, sinon la suite est rouge. Le plan en tient compte : les entrées de catalogue sont la dernière tâche.

**Quatorze images**, pas neuf : les séances ont elles aussi leur illustration, affichée en grand sur la page d'aperçu du player via `SportHeroIllustration(name: session.id)`. Omission de la première version de ce document, corrigée après l'échec du script.

Deux corrections d'outillage étaient nécessaires et sont **déjà faites** :

- `scripts/import-sport-images.sh` compare les sources de `design/sport/` aux ids des catalogues, mais ne lisait que `activities.json` et `sessions.json`. Il lit désormais aussi les deux catalogues posture, sinon il refuse à jamais des images dont l'id ne lui est pas connu.
- Les deux catalogues posture ont donc dû être écrits AVANT l'import, et non en dernier comme annoncé plus haut dans la première version. Cela ne crée aucune fenêtre rouge : `SportAssetsTests` ne parcourt encore que les catalogues globaux, et il ne s'étendra aux catalogues posture qu'une fois les images en place.

Les quatorze sont générées et importées (750 px, JPEG q80) au 03/08/2026.

Ce que chaque dessin doit montrer, Nivelito de profil ou de trois quarts selon le cas :

| id | Le dessin |
|---|---|
| `chin_tucks` | Assis de profil, menton reculé, un léger double menton assumé, index posé sur le menton pour montrer le geste |
| `supine_chin_tuck` | Allongé sur le dos vu de côté, genoux pliés, nuque allongée, tête posée au sol |
| `wall_angels` | Dos contre un mur, bras en chandelier, coudes et poignets au contact du mur |
| `wall_thoracic` | Face au mur, mains à plat en hauteur, poitrine qui descend entre les bras, dos long |
| `scapular_squeeze` | Vu de dos, bras le long du corps, omoplates rapprochées, épaules basses |
| `prone_y_raise` | À plat ventre, front au sol, bras tendus devant en Y légèrement décollés, pouces vers le haut |
| `doorway_stretch` | De profil dans l'encadrement d'une porte, avant-bras contre le montant, coude à hauteur d'épaule |
| `neck_stretch` | Assis, tête inclinée sur le côté, oreille vers l'épaule, une main sous la cuisse |
| `open_book` | Allongé sur le côté, genoux remontés, bras du dessus ouvert vers l'arrière, regard qui suit la main |

Et les cinq héros de séance, Nivelito en situation comme les onze existants :

| id | Le dessin |
|---|---|
| `posture_evening` | Debout de trois quarts, dos long, menton légèrement reculé, épaules basses et ouvertes. L'image de référence du programme. |
| `posture_open` | Bras écartés en grand, poitrine ouverte, tête légèrement en arrière, l'air de respirer un grand coup |
| `posture_strength` | Vu de trois quarts arrière, coudes fléchis tirés vers l'arrière, omoplates serrées |
| `posture_gentle` | Allongé sur le dos sur un tapis, genoux pliés, très détendu, presque du repos. Doit se lire comme le soir sans énergie. |
| `posture_full` | Debout bien droit, une main sur la nuque, l'autre ouvrant l'épaule, un petit air satisfait |

## 12. Ce qui ne change pas

- La séance du jour, sa rotation, sa référence fixe du 1ᵉʳ janvier 2026, ses 11 séances et ses 20 activités.
- L'instantané du widget et sa timeline. Aucune des sept clés ne bouge.
- Les repas, l'objectif kcal, le total du jour, tout le lot A de la v1.10.
- Les quatre rappels existants et leurs horaires.
- L'XP des activités et de la séance du jour, et tous les badges.

## 13. Hors périmètre, explicitement

- Progression sur plusieurs semaines, ou niveaux de difficulté croissants.
- Suivi de photos, de mesures ou d'angles.
- Un deuxième programme ciblé (genoux, lombaires...). L'architecture le permettrait, ce lot ne le fait pas.
- Réglage des séances ou des compositions depuis l'app.
- Toute forme de série de jours consécutifs (§7.4).
- Partage ou export.

## 14. Tests

**NivelCore**

- Chargement des deux catalogues posture, et **cloisonnement** : aucun id posture dans `activities.json` ni `sessions.json`, et réciproquement. C'est le test qui protège la rotation de la séance du jour.
- La rotation posture sur cinq entrées : cinq jours consécutifs donnent cinq séances distinctes, le sixième revient à la première.
- Intégrité : chaque `activityID` cité par une séance posture existe, durées croissantes, `kcalPerMin` positif, 3 à 4 consignes par exercice.
- `QuestEngine.weeklyDraw` : une quête `requiresPosture` n'est jamais tirée quand le programme est éteint, et l'est quand il est allumé. Ce test doit échouer si le drapeau est ignoré.
- `XPEngine` : `postureSessionDone` à 40, plafonnée à une par jour, et **indépendante de `dailySessionDone`** — le test fait les deux le même jour et vérifie que les deux paient.
- Le cinquième rappel dans `ReminderCatalog`, valeurs épinglées, et son libellé français « tous les jours à 21 h ».
- **Douze messages et non huit.** `MessageBankTests` exige déjà au moins douze textes par contexte, pour la variété. La première version de ce document en demandait huit, ce qui aurait obligé à assouplir ce test générique : c'est le contenu qu'il fallait compléter, pas la garde qu'il fallait affaiblir.
- Aucun tiret cadratin dans les nouvelles ressources (le test existant couvre tout le bundle).

**App**

- `PosturePlanSettings` : défaut faux, persistance, `false` persisté non confondu avec l'absence de clé.
- Allumer l'interrupteur pose `remindersEnabled["posture"] = true` ; l'éteindre le remet à faux.
- `postureSessionsDone` compte des **jours distincts** : deux séances le même soir valent une.
- Le compteur mensuel sur un mois à zéro, à une et à plusieurs séances.
- La section Posture est absente de l'onglet Sport quand l'interrupteur est éteint.

## 15. Livraison

Version **1.11 (build 12)** dans `project.yml`, sur les **deux** cibles.

**À vérifier sur le téléphone de Marion**

1. Interrupteur éteint : l'onglet Sport est identique à la v1.10, aucun rappel supplémentaire.
2. Interrupteur allumé : la section Posture apparaît en tête, et le rappel de 21 h est actif dans les Réglages sans autre geste.
3. Le rappel arrive bien à 21 h le soir même ou le lendemain.
4. Cinq soirs de suite donnent cinq séances différentes.
5. Faire la séance posture ET la séance du jour le même soir paie les deux XP.
6. La quête posture apparaît au tirage du lundi suivant, pas avant.
7. Le rendu de la section en tête sur le plus petit des deux iPhones.

**Sur le téléphone de Michaël** : rien ne doit avoir changé, interrupteur laissé éteint.
