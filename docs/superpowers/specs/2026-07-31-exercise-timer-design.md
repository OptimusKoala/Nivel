# Nivel — Spécification Timer d'exercice (v1.5)

Date : 2026-07-31
Statut : validé avec Michaël (démo interactive du 31/07/2026, choix A : anneau + graduations)
Référence : étend le player pas-à-pas (`2026-07-30-sport-illustrations-design.md` §5.1). Lève l'exclusion « pas de timer » des specs précédentes — le timer arrive, mais fidèle à l'esprit : **un guide, pas un chef**. Aucun tiret cadratin dans les textes, formulations neutres.

## 1. Vision

Sur les exercices à durée (« 4 min de planche », étapes d'une séance), un **timer stylisé** dit où on en est et quand passer à la suite. Design validé en démo : l'illustration de l'exercice devient le **cœur d'un anneau de progression** (cousin de l'anneau calories de l'accueil), graduations pour les séries, fin en douceur (vert, haptique, CTA qui pulse) — jamais d'alarme, jamais de rouge, jamais d'avance automatique.

## 2. Décisions validées (démo)

- **Opt-in** : le timer ne démarre JAMAIS seul. Bouton « Lancer le timer » ; le player et la sheet restent utilisables sans.
- **Pause libre** : Pause/Reprendre à volonté, message doux en pause (« En pause, prends ton temps 🧡 »). Bouton « Recommencer » disponible dès le premier lancement.
- **Fin = célébration, pas alarme** : l'anneau se complète et passe au vert (`Theme.green`), le temps affiché devient « Bien joué ! », haptique `.success`, son système discret (respecte le mode silencieux), et le CTA (« Étape suivante » / « C'est fait ! ») **pulse doucement**. Pas de décompte négatif, pas de dépassement affiché.
- **Graduations des séries** : petites encoches sur l'anneau quand l'étape a des séries explicites (« 3 × 30 s » → 3 segments). Données, pas parsing (voir §4).
- **Pas d'avance automatique** : le timer signale, l'utilisateur décide (CTA ou swipe).
- **Écran maintenu allumé** pendant qu'un timer tourne (`isIdleTimerDisabled`), relâché à l'arrêt/pause/disparition de la vue.

## 3. Les deux surfaces

### 3.1 Player (`SessionPlayerSheet`, pages d'étapes)

La grande illustration carrée de l'étape devient **ronde, au centre de l'anneau** (~230pt). Sous l'anneau : le temps restant en gros chiffres rounded (`m:ss`, tabular), le badge tempo existant, puis les contrôles du timer (Lancer / Pause / Reprendre + Recommencer). Chaque page d'étape a SON timer (état local à la page) : changer de page ou fermer la sheet abandonne le timer en cours sans cérémonie. La page 0 (aperçu) ne change pas.

### 3.2 Sheet d'activité libre (`ActivityLogSheet`)

Répond au cas « 4 min de planche » hors séance. Quand une durée est sélectionnée, la vignette 140pt devient le centre d'un anneau (~180pt) avec temps + contrôles en dessous (même composant, taille réduite). Le choix de durée reste le geste principal ; changer de durée réinitialise le timer. À la fin du timer : le CTA « C'est fait ! » pulse. La validation reste manuelle et possible à tout moment (avec ou sans timer).

## 4. Données : `SessionStep.segments: Int?` (nouveau champ OPTIONNEL)

Le nombre de séries affiché en graduations vient des données (pas de parsing du tempo, fragile). `decodeIfPresent` → nil = anneau sans graduation. Étapes concernées (déduites des tempos existants, tout le reste sans graduations) :

| Séance / étape | segments |
|---|---|
| wake_up / stretching | 2 |
| wake_up / squats | 3 |
| wake_up / plank | 3 |
| quick_tone / squats | 3 |
| quick_tone / wall_pushups | 3 |
| quick_tone / plank | 4 |
| zen_core / plank | 3 |
| home_cardio / squats | 2 |
| legs_day / squats | 2 |
| gentle_cardio / high_knees | 3 |

Les tempos en fourchette (« 2-3 tenues », « 4-5 allers-retours ») ou sans série explicite n'ont PAS de graduations. Les activités libres non plus (pas de champ côté `Activity`).

## 5. Architecture

- **`ExerciseTimerModel`** (App, `@Observable`) : machine à états `idle / running(depuis: Date) / paused / finished`, durée totale en secondes, temps restant calculé sur l'horloge murale (`Date`), PAS un compteur accumulé — robuste au passage en arrière-plan (au retour, l'état est recalculé ; si le temps est écoulé pendant l'absence → `finished`, sans notification). La logique « état + date → temps restant/fraction/fini » est **pure et testée** avec des dates injectées (aucun `sleep` dans les tests).
- **`TimerRingView`** (App, `App/Views/Sport/TimerRingView.swift`) : anneau SVG-like (mêmes techniques que `CalorieRing`), gradient `Theme.accent → Theme.orange`, piste `Theme.track`, graduations optionnelles (traits couleur fond), illustration circulaire au centre (`SportIllustration` existant avec `cornerRadius: size/2` = cercle, aucune adaptation du composant), taille paramétrable (230pt player / 180pt sheet). Vert `Theme.green` à l'état `finished`.
- **Contrôles** : boutons dans le style maison (`SecondaryButtonStyle` pour Pause/Recommencer, `PrimaryButtonStyle` compact pour Lancer — suivre les conventions v1.2 du fichier).
- **Refactor requis** : `stepPage(_:number:)` est aujourd'hui une fonction privée retournant `some View` ; l'état local par page (`@State` du timer) impose d'en extraire une vraie struct `StepPageView` (keyée comme le `ForEach(id: \.offset)` existant).
- Le **tick d'affichage** (rafraîchir `m:ss` chaque seconde) vient d'un `TimelineView(.periodic(...))` ou équivalent — pas de `Timer` manuel à invalider.
- **Pulse du CTA** : modifier léger (scale/brightness ~1,2 s) appliqué quand le timer de la page est `finished`, UNIQUEMENT si la barre basse affiche un bouton actionnable (`.next` sur une page intermédiaire, `.validate` sur la dernière). Sur une séance déjà faite (`.alreadyDone`, label ✓ non interactif), rien ne pulse : l'anneau vert + l'haptique suffisent — le timer reste utilisable en consultation libre. Pulse désactivé si Reduce Motion.
- **Haptique + son** : `UINotificationFeedbackGenerator(.success)` + `AudioServicesPlaySystemSound` discret (id système léger) au passage à `finished` — uniquement si le timer était en cours au premier plan.

## 6. Ce qui ne change PAS

Aucune règle XP/validation (le timer n'est jamais requis), pas de notification locale, pas de Live Activity, `GameService` intouché, NivelCore intouché sauf le champ `segments` + JSON.

## 7. Accessibilité

Anneau décoratif ; le temps restant est un `Text` lisible par VoiceOver (mise à jour par seconde, `accessibilityLabel` du type « 2 minutes 41 restantes » à granularité raisonnable) ; boutons auto-labellisés ; pulse désactivé avec Reduce Motion ; Dynamic Type : le temps et les contrôles scalent, l'anneau garde sa taille fixe (comme l'anneau calories).

## 8. Tests

- **NivelCore** : décodage de `segments` (présent → valeur, absent → nil) ; comptes inchangés.
- **App** (`ExerciseTimerModel`, dates injectées) : idle→running→remaining exact ; pause fige le restant ; reprise reprend au bon point ; expiration → finished (y compris « pendant l'absence » : running depuis T, interrogé à T+durée+10 → finished) ; recommencer → idle ; fraction 0→1.
- Vérification visuelle simulateur : les deux surfaces, états idle/running/paused/finished, graduations sur wake_up/plank.

## 9. Hors périmètre

Notifications locales de fin de timer, Live Activities/Dynamic Island, son personnalisé, timer sur l'encart accueil, réglage de durée pendant que le timer tourne, décompte des séries individuelles (les graduations sont indicatives, pas des sous-timers).

## 10. Points d'attention

- `isIdleTimerDisabled` doit être remis à `false` dans TOUS les chemins de sortie (pause, fin, disparition de la vue, dismiss de la sheet) — un oubli vide la batterie.
- Le son système doit respecter le mode silencieux (comportement natif d'`AudioServicesPlaySystemSound`).
- Deux timers ne peuvent pas tourner en même temps par construction (état local par page/sheet, une seule page visible).
