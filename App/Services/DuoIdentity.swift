// App/Services/DuoIdentity.swift
// L'état d'appairage du duo (spec 1.15 §3.6), qui est de l'état d'APPAREIL.
//
// Tout ce qui suit vit dans `UserDefaults` et JAMAIS dans SwiftData, au même titre que
// la palette (`ThemeStore`) ou les interrupteurs de programme
// (`ReminderPlan.enabledOnThisDevice`). Ce n'est pas une commodité : ces valeurs
// décrivent CE téléphone-ci — quelle moitié du duo il est, dans quelle zone il écrit,
// ce qu'il a déjà montré à son porteur. Les mettre dans le magasin en ferait des
// données de l'utilisateur, alors que ce sont des données de l'appareil.
//
// Le magasin SwiftData reste par ailleurs la seule source de vérité des journées, et
// il n'est toujours pas miroité (§3.2, et voir `NivelApp.init`).

import Foundation
import NivelCore

/// De quel côté du partage on se trouve. L'asymétrie est technique et n'existe que
/// pour résoudre la paire (base, zone) : le propriétaire lit et écrit dans sa base
/// privée, l'invité dans la base partagée, et la zone de l'invité porte le
/// `ownerName` du propriétaire au lieu de `__defaultOwner__` (§3.2).
enum DuoRole: String, Codable, Sendable {
    case owner, guest
}

/// Ce que cet appareil sait du duo. `@Observable` comme `ThemeStore` : la pastille de
/// l'accueil et la page du duo lisent ces valeurs pendant leur `body` et se
/// rafraîchissent seules quand un cœur arrive.
@Observable
final class DuoIdentity {
    static let shared = DuoIdentity()

    /// Clés exposées (`internal`) plutôt que privées : les tests écrivent directement
    /// dans le domaine pour simuler un cache écrit par une version antérieure, ce
    /// qu'aucune API publique ne permet de faire honnêtement.
    enum Key {
        static let memberID = "nivel.duo.memberID"
        static let role = "nivel.duo.role"
        static let zoneName = "nivel.duo.zoneName"
        static let zoneOwnerName = "nivel.duo.zoneOwnerName"
        static let shareURL = "nivel.duo.shareURL"
        static let profileLastSeenAt = "nivel.duo.profileLastSeenAt"
        static let unreadLikeCount = "nivel.duo.unreadLikeCount"
        static let partnerSnapshot = "nivel.duo.partnerSnapshot"
        static let lastPublishedSnapshot = "nivel.duo.lastPublishedSnapshot"
    }

    /// L'identité de CET appareil dans le duo. `nil` tant qu'aucun duo n'a jamais été
    /// appairé, et c'est le point important : **naître ne la crée pas**.
    ///
    /// La version précédente le fabriquait à la première lecture, dans `init`. Mesuré,
    /// l'effet était bien pire qu'une inélégance : `saveOrAssert()` appelle
    /// `publishDuo()`, dont l'argument par défaut `.shared` était évalué au site
    /// d'appel, donc à CHAQUE sauvegarde — et des suites de tests qui n'ont jamais
    /// entendu parler du duo laissaient une identité dans les vrais réglages de l'hôte
    /// de test. Un type qui écrit en naissant n'a aucun endroit sûr où être lu.
    ///
    /// `private(set)` : seul `createMemberID()` l'attribue, et `unpair()` n'y touche pas.
    /// Un `memberID` qui bougerait laisserait un membre fantôme dans la zone partagée et
    /// détacherait tous les cœurs déjà reçus, un `DuoLike` désignant son donneur par cet
    /// identifiant.
    private(set) var memberID: String?

    /// Nil tant qu'aucun duo n'est appairé, et c'est ce nil qui garantit la promesse du
    /// §3.1 : sans duo, aucune requête réseau n'est émise et l'app se comporte comme la
    /// 1.14.
    var role: DuoRole? { didSet { defaults.set(role?.rawValue, forKey: Key.role) } }

    var zoneName: String? { didSet { defaults.set(zoneName, forKey: Key.zoneName) } }
    /// Renseigné du seul côté INVITÉ : c'est le `ownerName` de la zone du propriétaire,
    /// sans quoi la `CKRecordZone.ID` reconstruite pointerait sur `__defaultOwner__`,
    /// c'est-à-dire sur soi.
    var zoneOwnerName: String? { didSet { defaults.set(zoneOwnerName, forKey: Key.zoneOwnerName) } }
    /// L'URL du partage, gardée du côté PROPRIÉTAIRE pour pouvoir réafficher le QR code
    /// tant que la place n'est pas prise.
    var shareURL: URL? { didSet { defaults.set(shareURL?.absoluteString, forKey: Key.shareURL) } }

    /// Dernière ouverture de la page du partenaire. Pilote la pastille rouge, via
    /// `DuoBadge.hasNewActivity` : nil veut dire « jamais visité », un cas que ce type
    /// distingue exprès de « visité il y a longtemps ».
    var profileLastSeenAt: Date? {
        didSet { defaults.set(profileLastSeenAt, forKey: Key.profileLastSeenAt) }
    }
    var unreadLikeCount: Int { didSet { defaults.set(unreadLikeCount, forKey: Key.unreadLikeCount) } }

    /// Le dernier instantané reçu du partenaire. Ce cache est ce qui permet d'ouvrir la
    /// page HORS LIGNE sur les derniers chiffres connus au lieu d'un écran vide, et la
    /// ligne « mis à jour il y a… » dit alors la vérité sur leur âge.
    var partnerSnapshot: DuoSnapshot? {
        didSet {
            defaults.set(partnerSnapshot.flatMap { try? JSONEncoder().encode($0) },
                         forKey: Key.partnerSnapshot)
        }
    }

    /// Le dernier instantané que CET appareil a publié. C'est à lui que la publication
    /// compare ce qu'elle vient de construire pour décider d'écrire (spec §3.5), et
    /// l'égalité de `DuoSnapshot` ignore `generatedAt` exprès — sans quoi chaque passage
    /// au premier plan écrirait dans iCloud sans qu'un seul chiffre ait bougé.
    ///
    /// Persisté plutôt que gardé en mémoire : au relancement, un cache vide ferait
    /// republier une journée identique, une écriture réseau pour rien à chaque
    /// démarrage. Le §3.6 n'énumère pas cette valeur, mais elle est de la même nature
    /// que les autres — de l'état de CET appareil, sans intérêt pour le partenaire.
    var lastPublishedSnapshot: DuoSnapshot? {
        didSet {
            defaults.set(lastPublishedSnapshot.flatMap { try? JSONEncoder().encode($0) },
                         forKey: Key.lastPublishedSnapshot)
        }
    }

    var isPaired: Bool { role != nil }

    private let defaults: UserDefaults

    /// `defaults` injectable, règle posée en v1.6 pour `widgetDefaults` : les tests et
    /// les prévisualisations passent un domaine à eux, et n'écrivent jamais les vrais
    /// réglages. Le défaut `.standard` ne sert qu'à `shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // LECTURE SEULE, comme tout ce qui suit. Une chaîne vide vaut absence : elle
        // serait un identifiant accepté partout ailleurs sans en être un, exactement le
        // piège que `publicID` évite de son côté (§3.4).
        let stocke = defaults.string(forKey: Key.memberID)
        memberID = (stocke?.isEmpty == false) ? stocke : nil

        role = defaults.string(forKey: Key.role).flatMap(DuoRole.init(rawValue:))
        zoneName = defaults.string(forKey: Key.zoneName)
        zoneOwnerName = defaults.string(forKey: Key.zoneOwnerName)
        shareURL = defaults.string(forKey: Key.shareURL).flatMap(URL.init(string:))
        profileLastSeenAt = defaults.object(forKey: Key.profileLastSeenAt) as? Date
        unreadLikeCount = defaults.integer(forKey: Key.unreadLikeCount)
        // `try?` VOULU : une version future changera la forme de `DuoSnapshot`, et le
        // cache écrit par l'ancienne restera sur le disque. On repart alors sans cache
        // plutôt que d'empêcher l'app de démarrer ; la page se remplira à la prochaine
        // réponse d'iCloud.
        partnerSnapshot = (defaults.data(forKey: Key.partnerSnapshot))
            .flatMap { try? JSONDecoder().decode(DuoSnapshot.self, from: $0) }
        lastPublishedSnapshot = (defaults.data(forKey: Key.lastPublishedSnapshot))
            .flatMap { try? JSONDecoder().decode(DuoSnapshot.self, from: $0) }
    }

    /// Crée l'identité de cet appareil et la persiste. **Un seul appelant légitime : le
    /// flux d'appairage**, seul moment où une identité est réellement nécessaire. La
    /// convoquer ailleurs ferait renaître le défaut que l'optionnel ci-dessus ferme.
    ///
    /// Idempotente : si une identité existe déjà, elle est rendue telle quelle. En
    /// fabriquer une seconde laisserait la première en fantôme dans la zone partagée.
    @discardableResult
    func createMemberID() -> String {
        if let memberID, !memberID.isEmpty { return memberID }
        let neuf = UUID().uuidString
        memberID = neuf
        defaults.set(neuf, forKey: Key.memberID)
        return neuf
    }

    /// Défait le duo sur CET appareil : rôle, zone, partage, cache et compteurs.
    ///
    /// `memberID` survit, et c'est le point de cette méthode. C'est l'identité de ce
    /// téléphone, pas celle du couple : quelqu'un qui désappaire puis réappaire avec la
    /// même personne doit rester la même personne aux yeux de la zone, sous peine d'y
    /// laisser un membre fantôme et d'orpheliner tous les cœurs déjà échangés.
    ///
    /// Chaque affectation passe par son `didSet`, donc l'effacement est écrit sur le
    /// disque et pas seulement dans cette instance — un duo qui réapparaîtrait au
    /// lancement suivant serait le plus déroutant des modes de panne.
    func unpair() {
        role = nil
        zoneName = nil
        zoneOwnerName = nil
        shareURL = nil
        profileLastSeenAt = nil
        unreadLikeCount = 0
        partnerSnapshot = nil
        // Sans cette ligne, réappairer avec la même personne ne republierait RIEN tant
        // que la journée n'a pas changé : l'instantané construit serait égal à celui
        // d'avant le désappairage, et le partenaire n'aurait jamais rien à afficher.
        lastPublishedSnapshot = nil
    }
}
