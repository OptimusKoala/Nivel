# Nivel — Spécification Extension du catalogue Sport (v1.4)

Date : 2026-07-31
Statut : validé avec Michaël (brainstorming du 31/07/2026)
Référence : étend `2026-07-30-sport-section-design.md` (catalogues) et `2026-07-30-sport-illustrations-design.md` (images, consignes, player). Mêmes principes : sans matériel (mur/chaise du foyer admis), doux, zéro pression, formulations neutres, aucun tiret cadratin.

## 1. Vision

Diversifier le sport : **8 nouvelles activités** (20 au total) et **3 nouvelles séances composées** (11 au total, rotation du jour enrichie). Chaque nouveauté arrive complète : image Nivelito (générée par Michaël), consignes « comment faire », rythmes suggérés. **Aucun code Swift ne change** : tout roule sur les rails v1.3 (catalogues JSON, `SportIllustration`, player, script d'import, tests).

## 2. Décisions validées

- Sélection validée : 8 activités + 3 séances (tables ci-dessous).
- Images générées par Michaël (11 PNG ≥1024px, fond plein, même style/session que les 20 existantes), déposées dans `design/sport/` sous les ids exacts.
- La rotation de la séance du jour passe de modulo 8 à **modulo 11** : toujours déterministe et identique sur les deux iPhones **à condition de re-builder les deux téléphones ensemble** (habitude hebdo existante). Les 3 nouvelles séances sont AJOUTÉES EN FIN de `sessions.json`.
- Les emoji restent le fallback (jamais affichés tant que les assets sont là) ; la réutilisation inter-catalogues d'emoji est admise (🏃/🥾 existent dans quêtes/badges).

## 3. Les 8 nouvelles activités (`activities.json`, ajoutées en fin)

| id | Activité | emoji | Lieu | Durées (min) | kcal/min |
|---|---|---|---|---|---|
| lunges | Fentes | 🤺 | home | 3 / 5 / 10 | 5,5 |
| wall_sit | Chaise contre le mur | 🪑 | home | 2 / 4 / 6 | 4,5 |
| high_knees | Montées de genoux | 🏃 | home | 3 / 5 / 8 | 6,5 |
| march_in_place | Marche sur place | 🧍 | home | 5 / 10 / 15 | 4,0 |
| shadow_boxing | Boxe dans le vide | 🥊 | home | 3 / 5 / 8 | 6,0 |
| mobility | Réveil articulaire | 🌀 | home | 5 / 8 / 12 | 2,5 |
| gardening | Jardinage | 🌻 | outdoor | 15 / 30 / 45 | 4,0 |
| hike | Randonnée légère | 🥾 | outdoor | 30 / 45 / 60 | 5,5 |

### 3.1 Consignes (`instructions`, 3-4 puces)

| id | instructions |
|---|---|
| lunges | Un grand pas en avant, le buste reste droit · Descends le genou arrière vers le sol, sans le toucher · Pousse sur la jambe avant pour revenir, puis change de côté · Tiens-toi à un mur ou une chaise si l'équilibre manque |
| wall_sit | Dos plaqué contre le mur, pieds avancés · Glisse jusqu'à avoir les genoux pliés, comme sur une chaise invisible · Les genoux restent au-dessus des chevilles, pas au-delà · Souffle régulier, remonte dès que les cuisses brûlent trop |
| high_knees | Sur place, monte un genou après l'autre vers les hanches · Pas besoin de sauter : un pied reste toujours au sol · Les bras accompagnent comme en course · Ralentis quand le souffle monte trop |
| march_in_place | Marche sur place d'un pas régulier, les bras balancent · Devant la télé ou une fenêtre, comme tu préfères · Monte un peu plus les genoux pour intensifier |
| shadow_boxing | Poings devant le visage, genoux légèrement fléchis · Enchaîne des coups légers dans le vide, sans verrouiller les coudes · Garde des appuis légers, bouge un peu · C'est aussi fait pour évacuer : lâche-toi |
| mobility | Des cercles lents : nuque, épaules, poignets, hanches, chevilles · Amplitude confortable, jamais forcée · Quelques respirations profondes entre chaque zone |
| gardening | Plie les genoux pour jardiner au sol, pas le dos · Alterne les tâches pour varier les postures · L'arrosoir et la brouette comptent comme de la muscu douce |
| hike | Choisis un sentier facile et de bonnes chaussures · Petit rythme régulier, surtout en montée · Emporte de l'eau et profite du paysage |

## 4. Les 3 nouvelles séances (`sessions.json`, ajoutées en fin, dans cet ordre)

| id | Séance | emoji | Étapes (activityID, minutes, tempo) |
|---|---|---|---|
| legs_day | Spécial jambes | 🦵 | squats 3 « ~10 squats × 2, tranquilles » · lunges 3 « ~8 fentes par jambe, en alternant » · wall_sit 2 « 2-3 tenues de ~30 s, repos entre chaque » · stretching 3 « Cuisses et mollets, ~30 s chacun » |
| gentle_cardio | Cardio tout doux | 💓 | march_in_place 4 « Rythme régulier, accélère sur la fin si ça va » · shadow_boxing 3 « Séries de ~20 coups, pause quand tu veux » · high_knees 3 « 3 × ~40 s, repos entre les séries » · stretching 3 « Épaules et jambes, ~30 s par étirement » |
| morning_mobility | Souplesse & mobilité | 🌀 | mobility 5 « Chaque articulation y passe : ~30 s par zone » · yoga 5 « 2-3 postures douces, 4-5 respirations chacune » · stretching 4 « Termine par le dos et la nuque, lentement » |

Durées totales : 11 / 13 / 14 min. Kcal dérivées (arrondies à la dizaine) : ~50 / ~60 / ~40.

## 5. Images (11)

Mêmes contraintes que la v1.3 : PNG ≥1024px carrés, fond plein, même prompt de style, déposés dans `design/sport/` sous `<id>.png` (8 activités + `legs_day.png`, `gentle_cardio.png`, `morning_mobility.png`). Le pipeline existant fait le reste : `./scripts/import-sport-images.sh` (le garde-fou de synchronisation refuse de tourner tant que sources et ids de catalogue ne correspondent pas exactement — les JSON et les images doivent donc atterrir dans le même commit).

## 6. Ce qui ne change PAS

Aucun code Swift (vues, GameService, NivelCore hors JSON), aucun modèle, aucune règle XP/quêtes/badges. Les quêtes sport (`activitiesDone`, `dailySessionsDone`) comptent les nouvelles activités automatiquement.

## 7. Tests

- `ActivityCatalogTests` : comptes pinnés mis à jour (activités 12 → **20**, sessions 8 → **11**) ; les invariants existants (durées ×3 croissantes > 0, instructions 3-4 non vides, tempo non vide, refs des steps valides, pas de em dash) couvrent les nouveautés automatiquement.
- `SportAssetsTests` : couvre les 31 ids automatiquement (présence + largeur 750).
- `DailySessionPickerTests` : inchangés (les pins passent `count:` en paramètre) ; vérifier que `testSessionForDate` reste vert (il référence `sessions[0]`, inchangé car ajout en fin).

## 8. Points d'attention

- **Ordre d'atterrissage** : images dans `design/sport/` AVANT de lancer le script ; JSON + assets générés + comptes de tests dans le même commit (sinon le script ou les tests échouent — c'est voulu).
- **Rotation** : le modulo change au premier build ; re-builder les deux iPhones ensemble (sinon séances du jour différentes entre les deux téléphones jusqu'au prochain re-build commun).
- **wall_sit 2 min minimum** : c'est une tenue isométrique, les durées courtes sont normales.
