// App/Services/DuoRecord.swift
// La traduction entre les formes de NivelCore et les enregistrements CloudKit
// (spec 1.15 §3.3), séparée de `DuoPublisher` pour une raison précise : elle est
// DÉCIDABLE hors ligne.
//
// `CKRecord(recordType:recordID:)` se construit sans compte, sans réseau et sans
// entitlement ; seul `modifyRecords` a besoin du nuage. Tout ce qui vit ici est donc
// éprouvable, alors que rien ne l'était tant que ces vingt noms de champs étaient des
// littéraux nus au milieu d'une fonction async.
//
// Ces noms sont un CONTRAT DE CÂBLE : le lot A2 devra les recopier à l'identique pour
// lire ce que le partenaire écrit. Une faute de frappe y est parfaitement silencieuse —
// CloudKit crée le champ à la volée en développement, et l'autre côté lit `nil`.

import CloudKit
import Foundation
import NivelCore

enum DuoRecord {
    /// Les deux types d'enregistrements de la zone.
    static let memberType = "DuoMember"
    static let likeType = "DuoLike"

    /// Les noms de champs, nommés UNE fois. Le lot A2 lira par ces mêmes constantes, si
    /// bien qu'une faute de frappe cessera d'être silencieuse : elle sera la même des
    /// deux côtés, ou elle ne compilera pas.
    enum Field {
        static let memberID = "memberID"
        static let name = "name"
        static let sexRaw = "sexRaw"
        static let level = "level"
        static let totalXP = "totalXP"
        static let xpIntoLevel = "xpIntoLevel"
        static let xpForNextLevel = "xpForNextLevel"
        static let dayKey = "dayKey"
        static let kcalEaten = "kcalEaten"
        static let kcalTarget = "kcalTarget"
        static let burned = "burned"
        static let burnTarget = "burnTarget"
        static let steps = "steps"
        static let questTitle = "questTitle"
        static let questDone = "questDone"
        static let questTotal = "questTotal"
        static let feedJSON = "feedJSON"
        static let generatedAt = "generatedAt"
        // DuoLike
        static let eventID = "eventID"
        static let ownerID = "ownerID"
        static let giverID = "giverID"
        static let eventTitle = "eventTitle"
        static let createdAt = "createdAt"
    }

    /// L'enregistrement d'un membre, reconstruit en entier à chaque publication. Son
    /// `recordName` est le `memberID`, donc déterministe : avec `savePolicy = .changedKeys`
    /// l'écriture devient un upsert, sans relecture préalable et sans conflit possible
    /// puisque chacun n'écrit que le sien.
    static func member(from snapshot: DuoSnapshot, in zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: memberType,
            recordID: CKRecord.ID(recordName: snapshot.memberID, zoneID: zoneID))

        record[Field.memberID] = snapshot.memberID as CKRecordValue
        record[Field.name] = snapshot.name as CKRecordValue
        record[Field.sexRaw] = snapshot.sexRaw as CKRecordValue
        record[Field.level] = snapshot.level as CKRecordValue
        record[Field.totalXP] = snapshot.totalXP as CKRecordValue
        record[Field.xpIntoLevel] = snapshot.xpIntoLevel as CKRecordValue
        record[Field.xpForNextLevel] = snapshot.xpForNextLevel as CKRecordValue
        record[Field.dayKey] = snapshot.dayKey as CKRecordValue
        record[Field.kcalEaten] = snapshot.kcalEaten as CKRecordValue
        record[Field.kcalTarget] = snapshot.kcalTarget as CKRecordValue
        record[Field.burned] = snapshot.burned as CKRecordValue
        record[Field.burnTarget] = snapshot.burnTarget as CKRecordValue
        record[Field.steps] = snapshot.steps as CKRecordValue
        // Quête absente : les trois champs restent NIL plutôt que de valoir 0, qui se
        // lirait « quête à 0/0 » chez le partenaire au lieu de « pas de quête ». C'est
        // une décision, pas une conséquence du code, et un test la garde.
        record[Field.questTitle] = snapshot.quest?.title as CKRecordValue?
        record[Field.questDone] = snapshot.quest?.done as CKRecordValue?
        record[Field.questTotal] = snapshot.quest?.total as CKRecordValue?
        // Le fil vit DANS l'enregistrement du membre (§3.4) : une seule écriture par
        // changement, aucun conflit, quelques kilo-octets au pire. Le repli sur « [] »
        // est un fil vide et lisible, jamais une chaîne absente qui ferait échouer le
        // décodage chez l'autre.
        record[Field.feedJSON] = (encodedFeed(snapshot.events) ?? "[]") as CKRecordValue
        record[Field.generatedAt] = snapshot.generatedAt as CKRecordValue
        return record
    }

    /// Ce que le partenaire vient d'écrire, relu (§3.3). C'est l'exacte réciproque de
    /// `member(from:)`, et les deux passent par `Field` : une faute de frappe est donc la
    /// même des deux côtés, ou elle ne compile pas. Un test fait l'aller-retour complet,
    /// parce qu'un champ ÉCRIT mais jamais RELU passerait autrement inaperçu.
    ///
    /// **Un enregistrement amputé n'est pas affiché du tout.** Remplacer un champ manquant
    /// par 0 afficherait un chiffre faux sans le dire, alors que rendre `nil` laisse en
    /// place le cache du `DuoIdentity` et sa ligne « mis à jour il y a… », qui dit la
    /// vérité sur l'âge de ce qu'on montre. Le cas ne se produit qu'avec un enregistrement
    /// à demi écrit : le contrat de câble n'autorise que des champs AJOUTÉS, jamais retirés.
    ///
    /// Deux exceptions, et elles sont volontaires : la quête, absente par décision quand il
    /// n'y en a pas, et le fil, qu'un JSON illisible ramène à un tableau vide plutôt qu'à
    /// rien du tout — les chiffres du jour valent mieux que rien.
    static func snapshot(from record: CKRecord) -> DuoSnapshot? {
        guard let memberID = record[Field.memberID] as? String, !memberID.isEmpty,
              let name = record[Field.name] as? String,
              let sexRaw = record[Field.sexRaw] as? String,
              let level = record[Field.level] as? Int,
              let totalXP = record[Field.totalXP] as? Int,
              let xpIntoLevel = record[Field.xpIntoLevel] as? Int,
              let xpForNextLevel = record[Field.xpForNextLevel] as? Int,
              let dayKey = record[Field.dayKey] as? String,
              let kcalEaten = record[Field.kcalEaten] as? Int,
              let kcalTarget = record[Field.kcalTarget] as? Int,
              let burned = record[Field.burned] as? Int,
              let burnTarget = record[Field.burnTarget] as? Int,
              let steps = record[Field.steps] as? Int,
              let feedJSON = record[Field.feedJSON] as? String,
              let generatedAt = record[Field.generatedAt] as? Date
        else { return nil }

        // Les TROIS champs, ou pas de quête. Une quête à demi écrite ne devient jamais
        // « 0/0 » : ce serait annoncer au partenaire une quête qu'il n'a pas commencée,
        // là où l'absence se lit simplement « pas de quête », ce que l'écriture prend déjà
        // soin de dire en laissant les trois champs nil.
        var quest: DuoQuestLine?
        if let title = record[Field.questTitle] as? String,
           let done = record[Field.questDone] as? Int,
           let total = record[Field.questTotal] as? Int {
            quest = DuoQuestLine(title: title, done: done, total: total)
        }

        return DuoSnapshot(
            memberID: memberID, name: name, sexRaw: sexRaw,
            level: level, totalXP: totalXP,
            xpIntoLevel: xpIntoLevel, xpForNextLevel: xpForNextLevel,
            dayKey: dayKey,
            kcalEaten: kcalEaten, kcalTarget: kcalTarget,
            burned: burned, burnTarget: burnTarget, steps: steps,
            quest: quest, events: decodeFeed(feedJSON), generatedAt: generatedAt)
    }

    /// Ce qu'il faut d'un `DuoMember` pour désigner mon partenaire, sans décoder tout
    /// l'instantané : la zone en porte deux au plus, mais un seul est le mien à afficher.
    ///
    /// `creationDate` vient du SERVEUR et vaut nil sur un enregistrement jamais écrit. Il
    /// est alors ramené au futur le plus lointain, ce qui le fait PERDRE face à un membre
    /// réellement daté — voir `DuoMemberRef.createdAt`.
    static func memberRef(from record: CKRecord) -> DuoMemberRef? {
        guard let memberID = record[Field.memberID] as? String, !memberID.isEmpty
        else { return nil }
        return DuoMemberRef(memberID: memberID, createdAt: record.creationDate ?? .distantFuture)
    }

    /// Un cœur, en entier cette fois : `likeRef` ne porte que de quoi juger un orphelin,
    /// alors que l'affichage et la notification ont besoin du donneur et du titre.
    ///
    /// **Seuls les deux champs dont dépendent les décisions sont exigés**, exactement comme
    /// `likeRef`, et pour la même raison mesurée au lot A1 : un cœur privé de son `giverID`
    /// y était écarté du nettoyage par un `continue` silencieux, donc orphelin pour
    /// toujours. Un donneur inconnu se lit ici en chaîne vide, qui ne peut être personne —
    /// et surtout pas moi, ce qui garde le cœur visible du bon côté du filtre du §3.7.
    static func like(from record: CKRecord) -> DuoLike? {
        guard let eventID = record[Field.eventID] as? String,
              let ownerID = record[Field.ownerID] as? String
        else { return nil }

        return DuoLike(
            giverID: record[Field.giverID] as? String ?? "",
            ownerID: ownerID,
            eventID: eventID,
            eventTitle: record[Field.eventTitle] as? String ?? "",
            // Une date inconnue place le cœur en tête de liste plutôt qu'en dernière
            // nouvelle : mieux vaut le montrer trop bas que le faire passer pour l'événement
            // du moment.
            createdAt: record[Field.createdAt] as? Date ?? record.creationDate ?? .distantPast)
    }

    /// L'enregistrement d'un cœur (spec §3.3), écrit par celui qui l'envoie.
    ///
    /// Son `recordName` est DÉTERMINISTE, `like-<donneur>-<événement>`, et tout en découle :
    /// aimer deux fois réécrit le même enregistrement au lieu d'en créer un second, et
    /// retirer un cœur est une suppression par nom, sans lecture préalable.
    ///
    /// `eventTitle` est recopié ici exprès : c'est lui qui donnera son texte à la
    /// notification chez l'autre, sans qu'il ait à relire son propre fil au réveil (§3.7).
    static func like(giver: String, owner: String, event: DuoEvent,
                     in zoneID: CKRecordZone.ID, now: Date = .now) -> CKRecord {
        let record = CKRecord(
            recordType: likeType,
            recordID: CKRecord.ID(recordName: DuoLikeID.recordName(giver: giver, event: event.id),
                                  zoneID: zoneID))
        record[Field.giverID] = giver as CKRecordValue
        record[Field.ownerID] = owner as CKRecordValue
        record[Field.eventID] = event.id as CKRecordValue
        record[Field.eventTitle] = event.title as CKRecordValue
        record[Field.createdAt] = now as CKRecordValue
        return record
    }

    static func encodedFeed(_ events: [DuoEvent]) -> String? {
        guard let data = try? JSONEncoder().encode(events) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeFeed(_ json: String) -> [DuoEvent] {
        (try? JSONDecoder().decode([DuoEvent].self, from: Data(json.utf8))) ?? []
    }

    /// Ce qu'il faut d'un `DuoLike` pour décider s'il est orphelin. `nil` seulement si
    /// les DEUX champs dont dépend la décision manquent vraiment.
    ///
    /// Aucun autre champ n'est exigé, et c'est délibéré : `giverID` a servi de condition
    /// de garde ici, alors qu'il n'était jamais lu, et un cœur qui en était dépourvu se
    /// trouvait écarté du nettoyage par un `continue` silencieux — donc orphelin pour
    /// toujours. Un champ dont on ne fait rien ne doit jamais pouvoir faire échouer quoi
    /// que ce soit.
    static func likeRef(from record: CKRecord) -> DuoLikeRef? {
        guard let eventID = record[Field.eventID] as? String,
              let ownerID = record[Field.ownerID] as? String
        else { return nil }
        return DuoLikeRef(eventID: eventID, ownerID: ownerID)
    }
}
