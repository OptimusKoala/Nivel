// App/Services/DuoDatabase.swift
// Le SEUL fichier du dépôt qui connaît l'asymétrie propriétaire / invité (spec 1.15
// §3.2). Tout le reste du code appelle `database` et `zoneID` sans jamais savoir de quel
// côté du partage il se trouve.
//
// C'est ce qui empêche l'asymétrie de se répandre : elle est technique, elle n'intéresse
// personne d'autre, et un écran du lot A2 qui se mettrait à tester le rôle pour choisir
// une base finirait par le tester à cinq endroits, dont un faux.
//
// Le propriétaire lit et écrit dans `privateCloudDatabase`, l'invité dans
// `sharedCloudDatabase`, et la zone de l'invité porte le `ownerName` du propriétaire au
// lieu de `__defaultOwner__`.

import CloudKit

enum DuoDatabase {
    static let containerID = "iCloud.com.elitedangereuse.Nivel"
    /// Nom de la zone personnalisée créée par celui qui invite. `DuoIdentity.zoneName`
    /// fait foi quand il est renseigné ; cette constante est ce qu'on crée au départ.
    static let defaultZoneName = "duo"

    /// Le couple à qui parler. Les deux vont toujours ensemble : une base sans sa zone,
    /// ou l'inverse, est la faute que ce type existe pour rendre impossible.
    struct Target {
        let database: CKDatabase
        let zoneID: CKRecordZone.ID
        /// Le type d'abonnement autorisé dépend de la base. CloudKit n'accepte les
        /// abonnements de zone que dans `.private` ; l'invité, dans `.shared`, doit poser
        /// un abonnement de base (voir `DuoService.makeLikeSubscription`).
        let scope: CKDatabase.Scope
    }

    /// `nil` quand aucun duo n'est appairé — il n'y a alors rien à résoudre, et
    /// l'appelant doit s'arrêter là plutôt que d'inventer une zone. `nil` aussi pour un
    /// invité sans `zoneOwnerName` : sans lui, la `CKRecordZone.ID` reconstruite
    /// pointerait sur `__defaultOwner__`, c'est-à-dire sur SOI, et on écrirait
    /// tranquillement dans une zone à soi que personne ne lit.
    static func target(for identity: DuoIdentity,
                       container: CKContainer = CKContainer(identifier: containerID)) -> Target? {
        guard let role = identity.role else { return nil }
        let zoneName = identity.zoneName ?? defaultZoneName

        switch role {
        case .owner:
            return Target(
                database: container.privateCloudDatabase,
                zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName),
                scope: .private)
        case .guest:
            guard let ownerName = identity.zoneOwnerName else { return nil }
            return Target(
                database: container.sharedCloudDatabase,
                zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName),
                scope: .shared)
        }
    }
}
