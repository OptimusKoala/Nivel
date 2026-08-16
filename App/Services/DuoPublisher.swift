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
        Task { @MainActor in await publishDuoNow(identity: identity) }
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

        // 1, 2 et 3. Attribuer, persister, PUIS construire — dans cet ordre, tenu par
        // `prepareDuoSnapshot` et éprouvé par un test qui rougit si on l'inverse.
        let steps = await todaySteps()
        guard let snapshot = prepareDuoSnapshot(memberID: memberID, steps: steps, now: now)
        else { return false }

        // 4. Sortir si rien n'a bougé. L'égalité de `DuoSnapshot` ignore `generatedAt`
        // exprès : la comparer rendrait chaque instantané différent du précédent, et
        // l'app écrirait dans iCloud à chaque retour au premier plan, à chaque
        // validation, à chaque bascule de minuit, sans qu'un seul chiffre ait changé.
        guard snapshot != identity.lastPublishedSnapshot else { return false }

        // 5 bis. Les cœurs devenus orphelins partent DANS LA MÊME OPÉRATION que
        // l'instantané : jamais d'état intermédiaire où les chiffres seraient à jour et
        // les cœurs encore accrochés à des entrées disparues.
        let orphelins = await orphanLikeRecordIDs(in: target, me: memberID)

        do {
            try await write(snapshot, deleting: orphelins, to: target)
            // 6. Mémoriser SEULEMENT après une écriture réussie : mémoriser avant ferait
            // qu'un échec réseau serait pris pour un succès, et la journée ne repartirait
            // plus jamais tant qu'un chiffre n'aurait pas rebougé.
            identity.lastPublishedSnapshot = snapshot
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
    private func write(_ snapshot: DuoSnapshot, deleting orphelins: [CKRecord.ID],
                       to target: DuoDatabase.Target) async throws {
        let recordID = CKRecord.ID(recordName: snapshot.memberID, zoneID: target.zoneID)
        let record = CKRecord(recordType: "DuoMember", recordID: recordID)

        record["memberID"] = snapshot.memberID as CKRecordValue
        record["name"] = snapshot.name as CKRecordValue
        record["sexRaw"] = snapshot.sexRaw as CKRecordValue
        record["level"] = snapshot.level as CKRecordValue
        record["totalXP"] = snapshot.totalXP as CKRecordValue
        record["xpIntoLevel"] = snapshot.xpIntoLevel as CKRecordValue
        record["xpForNextLevel"] = snapshot.xpForNextLevel as CKRecordValue
        record["dayKey"] = snapshot.dayKey as CKRecordValue
        record["kcalEaten"] = snapshot.kcalEaten as CKRecordValue
        record["kcalTarget"] = snapshot.kcalTarget as CKRecordValue
        record["burned"] = snapshot.burned as CKRecordValue
        record["burnTarget"] = snapshot.burnTarget as CKRecordValue
        record["steps"] = snapshot.steps as CKRecordValue
        // Quête absente : les trois champs restent nil plutôt que de valoir 0, qui se
        // lirait « quête à 0/0 » chez le partenaire au lieu de « pas de quête ».
        record["questTitle"] = snapshot.quest?.title as CKRecordValue?
        record["questDone"] = snapshot.quest?.done as CKRecordValue?
        record["questTotal"] = snapshot.quest?.total as CKRecordValue?
        // Le fil vit DANS l'enregistrement du membre, en JSON (§3.4) : une seule écriture
        // par changement, aucun conflit possible, et quelques kilo-octets au pire.
        record["feedJSON"] = (String(data: try JSONEncoder().encode(snapshot.events),
                                     encoding: .utf8) ?? "[]") as CKRecordValue
        record["generatedAt"] = snapshot.generatedAt as CKRecordValue

        _ = try await target.database.modifyRecords(
            saving: [record], deleting: orphelins, savePolicy: .changedKeys)
    }

    /// Les cœurs qui ne désignent plus rien (spec §3.4). La DÉCISION vit dans
    /// `DuoLikeID.orphanEventIDs`, pure et testée ; ici il n'y a que la lecture de la
    /// zone et la traduction en identifiants d'enregistrement.
    ///
    /// Deux points que le commentaire de `orphanEventIDs` développe et qu'il faut avoir
    /// en tête ici :
    ///
    /// - la comparaison se fait contre `allLocalPublicIDs()`, TOUT le magasin, et surtout
    ///   pas contre le fil du jour qu'on vient de construire et qui est sous la main.
    ///   Le fil ne couvre que la journée courante : à minuit, tous les cœurs de la veille
    ///   deviendraient orphelins et seraient effacés, y compris ceux qui s'affichent sur
    ///   les entrées passées des journaux ;
    /// - la requête ne demande que MES événements (`ownerID == me`), et le filtre est
    ///   redit dans `orphanEventIDs` : les cœurs que j'ai donnés portent l'`ownerID` de
    ///   l'autre, leurs entrées ne sont pas dans mon magasin, et je les jugerais tous
    ///   orphelins.
    ///
    /// Un échec de lecture rend une liste vide plutôt que de propager : un nettoyage
    /// impossible ne doit JAMAIS empêcher la publication des chiffres du jour.
    private func orphanLikeRecordIDs(in target: DuoDatabase.Target,
                                     me: String) async -> [CKRecord.ID] {
        let requete = CKQuery(recordType: "DuoLike",
                              predicate: NSPredicate(format: "ownerID == %@", me))
        guard let reponse = try? await target.database.records(matching: requete,
                                                               inZoneWith: target.zoneID)
        else { return [] }

        var coeurs: [DuoLikeRef] = []
        var enregistrementsParEvenement: [String: [CKRecord.ID]] = [:]
        for (recordID, resultat) in reponse.matchResults {
            guard let record = try? resultat.get(),
                  let eventID = record["eventID"] as? String,
                  let ownerID = record["ownerID"] as? String
            else { continue }
            coeurs.append(DuoLikeRef(eventID: eventID, ownerID: ownerID))
            enregistrementsParEvenement[eventID, default: []].append(recordID)
        }

        let orphelins = DuoLikeID.orphanEventIDs(
            likes: coeurs, localPublicIDs: allLocalPublicIDs(), me: me)
        return orphelins.flatMap { enregistrementsParEvenement[$0] ?? [] }
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
