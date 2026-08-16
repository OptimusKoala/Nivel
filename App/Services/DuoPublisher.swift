// App/Services/DuoPublisher.swift
// La publication de l'instantané dans la zone partagée (spec 1.15 §3.5), calquée sur
// `GameService.syncWidget()`.
//
// C'est la moitié de la 1.15 qui NE SE PROUVE PAS : tout ce qui suit la construction de
// l'instantané parle à CloudKit, et aucun test de ce dépôt ne peut l'observer. Le code
// est donc écrit mince et sans astuce, et ce qu'il ne garantit pas est écrit noir sur
// blanc plus bas.
//
// Fire and forget, comme le widget : AUCUNE erreur n'est remontée à l'écran. Un échec
// réseau laisse simplement le partenaire sur l'instantané précédent, et la ligne de
// fraîcheur du lot A2 dira la vérité sur son âge.

import CloudKit
import Foundation
import NivelCore

extension GameService {

    /// Le crochet, posé partout où `syncWidget()` l'est déjà. Ne rend rien, n'attend
    /// rien, ne lève rien.
    ///
    /// La garde d'appairage est ICI, avant même de lancer la tâche : sans duo, la spec
    /// §3.1 promet qu'aucune requête réseau n'est émise et que l'app se comporte
    /// exactement comme la 1.14. Rien n'est créé, rien n'est demandé, rien n'est écrit —
    /// pas même un identifiant public sur un repas.
    func publishDuo() {
        // `duoIdentity` est injecté, jamais `.shared` évalué ici : un argument par défaut
        // est évalué AU SITE D'APPEL, donc à chaque sauvegarde, ce qui instanciait le
        // singleton et lisait neuf clés de réglages pour un utilisateur sans duo. La
        // promesse du §3.1 — sans duo, l'app se comporte exactement comme la 1.14 — se
        // tient ici, avant tout le reste.
        guard let identity = duoIdentity, identity.isPaired else { return }

        // COALESCENCE. `syncWidget()` tolère les appels en rafale parce qu'il écrit un
        // plist local ; ici chaque appel vaut une lecture HealthKit, une sauvegarde, une
        // requête et un aller-retour réseau. Pire, `lastPublishedSnapshot` n'étant écrit
        // qu'APRÈS l'aller-retour, deux appels qui se recouvrent franchissent tous les
        // deux la garde « rien n'a bougé » et écrivent la même chose deux fois.
        //
        // Le scénario est atteignable aujourd'hui : au retour au premier plan, `RootView`
        // publie, et si `closeOpenDays()` a quelque chose à clôturer, `saveOrAssert()`
        // publie dans le même tour. Le lot A2 ajoutera ses propres déclencheurs.
        //
        // Un appel écarté n'est pas une publication perdue : l'appel en vol construira
        // son instantané APRÈS la sauvegarde qui a déclenché le second, puisque tout ceci
        // est sur le `MainActor` — et à défaut, le crochet suivant repassera.
        guard !duoPublishInFlight else { return }
        duoPublishInFlight = true
        Task { @MainActor in
            defer { duoPublishInFlight = false }
            await publishDuoNow(identity: identity)
        }
    }

    /// La publication elle-même. `@discardableResult` et jamais `throws` : l'appelant
    /// n'a rien à décider d'un échec.
    ///
    /// Rend `true` quand une écriture est réellement partie, ce qui ne sert qu'aux tests
    /// et au débogage — surtout pas à afficher quoi que ce soit.
    @discardableResult
    func publishDuoNow(identity: DuoIdentity, now: Date = .now) async -> Bool {
        // `memberID` non nil est un état IMPOSSIBLE derrière `isPaired` — on n'appaire
        // pas sans identité — mais l'optionnel doit bien être ouvert quelque part, et
        // c'est le seul endroit qui en a besoin. Aucune branche nouvelle, juste le
        // dépliage d'un état que l'appairage garantit.
        guard identity.isPaired, let memberID = identity.memberID,
              let target = DuoDatabase.target(for: identity) else { return false }

        // Attribuer, persister, PUIS construire — dans cet ordre, tenu par
        // `prepareDuoSnapshot` et éprouvé par un test qui rougit si on l'inverse.
        let steps = await todaySteps()
        guard let snapshot = prepareDuoSnapshot(memberID: memberID, steps: steps, now: now)
        else { return false }

        // Sortir si rien n'a bougé. L'égalité de `DuoSnapshot` ignore `generatedAt`
        // exprès : la comparer rendrait chaque instantané différent du précédent, et
        // l'app écrirait dans iCloud à chaque retour au premier plan, à chaque
        // validation, à chaque bascule de minuit, sans qu'un seul chiffre ait changé.
        guard snapshot != identity.lastPublishedSnapshot else { return false }

        // Les cœurs devenus orphelins partent DANS LA MÊME OPÉRATION que l'instantané :
        // jamais d'état intermédiaire où les chiffres seraient à jour et les cœurs encore
        // accrochés à des entrées disparues.
        //
        // À NOTER, conséquence assumée de sa place APRÈS la garde ci-dessus : supprimer
        // une entrée d'une journée PASSÉE ne change pas l'instantané du jour, donc on
        // sort avant d'arriver ici et le cœur orphelin survit jusqu'au prochain vrai
        // changement. Remonter le nettoyage avant la garde coûterait une requête réseau
        // à CHAQUE passage au premier plan, y compris quand rien n'a bougé — ce que
        // toute cette fonction est faite d'éviter. Un cœur orphelin de quelques heures
        // est le moindre mal.
        let orphelins = orphanLikeRecordIDs(in: target.zoneID, identity: identity, me: memberID)

        do {
            let ecritures = try await write(snapshot, deleting: orphelins, to: target)
            // ⚠️ En mode non atomique, un enregistrement peut échouer SANS que l'appel lève.
            // Ne regarder que l'absence d'erreur levée reviendrait à faire exactement ce que
            // le commentaire ci-dessous dit éviter. Seules les SAUVEGARDES comptent : les
            // suppressions sont le nettoyage des cœurs orphelins, un à-côté qui n'a pas le
            // droit d'invalider la publication des chiffres du jour.
            guard DuoRecord.allSucceeded(ecritures.saveResults) else { return false }
            // Mémoriser SEULEMENT après une écriture réussie : mémoriser avant ferait
            // qu'un échec réseau serait pris pour un succès, et la journée ne repartirait
            // plus jamais tant qu'un chiffre n'aurait pas rebougé.
            identity.lastPublishedSnapshot = snapshot
            // Les cœurs qu'on vient de supprimer ne sont plus à supprimer. Sans cette
            // ligne, chaque publication redemanderait les mêmes suppressions jusqu'à la
            // prochaine relecture de la zone : sans dégât, mais pour rien.
            if !orphelins.isEmpty {
                let partis = Set(orphelins.map(\.recordName))
                identity.receivedLikeEventIDs = identity.receivedLikeEventIDs.filter {
                    !partis.contains(DuoLikeID.recordName(
                        giver: identity.partnerSnapshot?.memberID ?? "", event: $0))
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Les étapes 1 à 3, réunies ICI et pas dans `publishDuoNow`, pour une raison
    /// précise : l'ordre est le cœur de la publication, et il n'était protégé par aucun
    /// test tant qu'il vivait au milieu d'une fonction que rien ne peut appeler sans
    /// CloudKit. Réuni dans une fonction qui REND l'instantané, il devient observable —
    /// inverser les deux lignes ci-dessous fait virer
    /// `testLaPreparationAttribueLesIdentifiantsAvantDeConstruireLeFil` au rouge.
    ///
    /// Pourquoi l'ordre : `DuoFeedBuilder.build` écarte tout événement dont le `publicID`
    /// est vide, parce que le nom d'enregistrement d'un cœur vaut
    /// `like-<donneur>-<événement>` (voir `DuoLikeID.recordName`) — deux entrées non
    /// identifiées produiraient toutes deux `like-G1-`, et un cœur posé sur l'une
    /// apparaîtrait sur l'autre. Construire AVANT d'attribuer publierait donc une journée
    /// amputée de toutes ses entrées d'avant la 1.15, indéfiniment et en silence.
    func prepareDuoSnapshot(memberID: String, steps: Int?, now: Date = .now) -> DuoSnapshot? {
        assignMissingDuoIDs(on: now)
        return makeDuoSnapshot(memberID: memberID, steps: steps, now: now)
    }

    /// 5. L'écriture. `savePolicy = .changedKeys` : on n'écrase que ce qu'on a posé, ce
    /// qui évite d'effacer un champ qu'une version future du partenaire aurait ajouté.
    ///
    /// L'enregistrement est reconstruit à chaque fois plutôt que relu : son `recordName`
    /// est le `memberID`, donc déterministe, et `.changedKeys` fait de l'écriture un
    /// upsert. Un aller-retour réseau en moins, et aucun conflit possible puisque chacun
    /// n'écrit que le sien (§3.3).
    ///
    /// `atomically: false`, et c'est devenu indispensable depuis que les suppressions sont
    /// déduites d'une liste locale plutôt que d'une lecture fraîche de la zone : un cœur
    /// déjà parti, ou dont le donneur a changé, ferait échouer TOUT le lot en mode atomique,
    /// et les chiffres du jour ne seraient plus publiés du tout. Le nettoyage est un
    /// à-côté ; il n'a pas le droit d'emporter l'essentiel avec lui.
    private func write(
        _ snapshot: DuoSnapshot, deleting orphelins: [CKRecord.ID],
        to target: DuoDatabase.Target
    ) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
                       deleteResults: [CKRecord.ID: Result<Void, any Error>]) {
        try await target.database.modifyRecords(
            saving: [DuoRecord.member(from: snapshot, in: target.zoneID)],
            deleting: orphelins, savePolicy: .changedKeys, atomically: false)
    }

    /// Les cœurs qui ne désignent plus rien (spec §3.4), et l'endroit où le lot A2 a fait
    /// disparaître la dernière requête indexée du dépôt.
    ///
    /// **Plus aucune lecture de la zone ici.** Les cœurs reçus sont déjà en main, persistés
    /// par `DuoService` dans `DuoIdentity.receivedLikeEventIDs` : cette fonction est donc
    /// devenue synchrone, gratuite en réseau, et — ce qui vaut mieux que les deux — enfin
    /// éprouvable par des tests, ce qu'elle n'était pas tant qu'elle exigeait un compte
    /// iCloud. L'ancienne requête filtrait sur `ownerID`, donc supposait un index QUERYABLE
    /// posé à la main dans le tableau de bord CloudKit : s'il manquait, elle ne levait pas,
    /// elle rendait zéro résultat, et le nettoyage ne faisait plus rien en silence.
    ///
    /// La DÉCISION reste dans `DuoLikeID.orphanEventIDs`, pure et testée, avec les deux
    /// règles qui la gouvernent : comparer au MAGASIN et non au fil, et ne juger que ses
    /// PROPRES événements. Tous les identifiants d'ici sont des cœurs posés sur mes entrées,
    /// `DuoService.incomingLikes` n'ayant retenu que ceux-là ; `ownerID: me` le redit, et la
    /// fonction pure le revérifie.
    ///
    /// Le nom d'enregistrement est RECOMPOSÉ plutôt que retenu, et c'est l'usage prévu du
    /// §3.3 : `like-<donneur>-<événement>` est déterministe précisément pour que retirer un
    /// cœur soit une suppression par nom, sans requête préalable. Sans partenaire connu, on
    /// ne suppose pas un donneur : on ne supprime rien, et la publication suivante s'en
    /// chargera.
    ///
    /// Conséquence assumée : un cœur arrivé depuis la dernière relecture de la zone n'est pas
    /// encore dans cette liste, donc pas encore nettoyable. Il le sera au prochain tour.
    func orphanLikeRecordIDs(in zoneID: CKRecordZone.ID, identity: DuoIdentity,
                             me: String) -> [CKRecord.ID] {
        guard let donneur = identity.partnerSnapshot?.memberID, !donneur.isEmpty else { return [] }

        let coeurs = identity.receivedLikeEventIDs.map { DuoLikeRef(eventID: $0, ownerID: me) }
        let orphelins = DuoLikeID.orphanEventIDs(likes: coeurs,
                                                 localPublicIDs: allLocalPublicIDs(), me: me)
        // Trié : deux exécutions sur le même magasin rendent la même liste, ce qu'un `Set`
        // ne promet pas et ce dont les tests ont besoin pour dire quoi que ce soit.
        return orphelins.sorted().map {
            CKRecord.ID(recordName: DuoLikeID.recordName(giver: donneur, event: $0),
                        zoneID: zoneID)
        }
    }

    /// Remplit et persiste les `publicID` vides des entrées du jour — les entrées
    /// d'avant la 1.15, qui sont nées sans (spec §3.4). Une fois pour toutes : une entrée
    /// déjà identifiée n'est jamais réattribuée, sous peine de détacher ses cœurs.
    ///
    /// ⚠️ `modelContext.save()` DIRECT, et surtout pas `saveOrAssert()` : ce dernier
    /// appelle `syncWidget()`, à côté de qui `publishDuo()` est posé. Passer par lui
    /// ferait donc `publish → save → publish → save…` sans fin. Le widget n'a de toute
    /// façon rien à faire d'un identifiant public, qui n'entre dans aucun de ses champs.
    private func assignMissingDuoIDs(on now: Date) {
        guard let (debut, fin) = dayBounds(for: now) else { return }
        // Les tableaux sont fetchés UNE fois et les identifiants leur sont appliqués par
        // rang : `MissingIDAssignment` désigne les entrées par leur position, seule
        // identité disponible pour une entrée dont le `publicID` est justement vide.
        let repas = fetchMeals(from: debut, to: fin)
        let activites = activities(on: now)

        let attribution = DuoFeedBuilder.assignMissingIDs(
            meals: duoMealInputs(repas), activities: duoActivityInputs(activites))
        guard !attribution.isEmpty else { return }

        for (rang, identifiant) in attribution.meals { repas[rang].publicID = identifiant }
        for (rang, identifiant) in attribution.activities { activites[rang].publicID = identifiant }
        try? modelContext.save()
    }
}
