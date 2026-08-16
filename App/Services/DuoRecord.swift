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
