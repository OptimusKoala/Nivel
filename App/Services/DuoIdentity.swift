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
        static let pairedAt = "nivel.duo.pairedAt"
        static let likeNotificationsEnabled = "nivel.duo.likeNotificationsEnabled"
        static let receivedLikeEventIDs = "nivel.duo.receivedLikeEventIDs"
        static let likeHistoryEventIDs = "nivel.duo.likeHistoryEventIDs"
        static let zoneChangeToken = "nivel.duo.zoneChangeToken"
        static let givenLikeEventIDs = "nivel.duo.givenLikeEventIDs"
        static let zoneSubscriptionInstalled = "nivel.duo.zoneSubscriptionInstalled"
        static let likeNotificationSubscriptionVersion =
            "nivel.duo.likeNotificationSubscriptionVersion"
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

    /// Depuis quand ce duo existe, posé à l'appairage réussi et effacé au désappairage.
    /// La section Duo des réglages l'affiche (§3.9). Optionnel, et il le restera : un duo
    /// noué par une version antérieure n'a pas de date, et il vaut mieux ne rien dire que
    /// d'en inventer une.
    var pairedAt: Date? { didSet { defaults.set(pairedAt, forKey: Key.pairedAt) } }

    /// L'interrupteur « Cœurs reçus » (§3.7) : il coupe l'alerte CloudKit, jamais
    /// l'appairage ni la réception. On garde le duo et on cesse d'être prévenu.
    ///
    /// Allumé par défaut, et la lecture en `object` plutôt qu'en `bool` est ce qui le
    /// garantit : `defaults.bool(forKey:)` rend `false` sur une clé absente, donc lu ainsi
    /// l'interrupteur naîtrait ÉTEINT sur tout appareil qui n'y a jamais touché, sans que
    /// rien ne paraisse anormal dans les réglages.
    var likeNotificationsEnabled: Bool {
        didSet { defaults.set(likeNotificationsEnabled, forKey: Key.likeNotificationsEnabled) }
    }

    /// Les `publicID` de MES entrées qui ont reçu un cœur. Persistés, et c'est une décision
    /// de la spec §3.10 : les cœurs déjà reçus restent affichés sur les entrées des journaux
    /// Repas et Sport **après le désappairage**, parce qu'ils font partie de l'histoire et
    /// non de la connexion. Gardés en mémoire seulement, ils disparaîtraient au premier
    /// relancement, et la zone qui les portait n'existe plus pour les redonner.
    ///
    /// Un tableau plutôt qu'un `Set` : `UserDefaults` ne sait pas ranger un `Set`.
    var receivedLikeEventIDs: [String] {
        didSet { defaults.set(receivedLikeEventIDs, forKey: Key.receivedLikeEventIDs) }
    }

    /// Le jeton de changement de la zone (`CKServerChangeToken`), archivé en `Data`.
    ///
    /// En `Data` et non typé, pour que ce fichier n'importe pas CloudKit : il décrit l'état
    /// de CET appareil, pas le transport. `DuoService` l'archive et le désarchive, et lui
    /// seul sait ce qu'il y a dedans.
    ///
    /// Persisté parce que c'est tout son intérêt : au réveil suivant, il dit au serveur
    /// « donne-moi ce qui a changé depuis », ce qui rend un réveil silencieux presque
    /// gratuit et, surtout, permet de savoir quels cœurs sont NOUVEAUX.
    var zoneChangeToken: Data? { didSet { defaults.set(zoneChangeToken, forKey: Key.zoneChangeToken) } }

    /// L'abonnement d'alerte des cœurs est posé sur ce téléphone. Un booléen plutôt qu'une
    /// écriture à chaque lancement : `modifySubscriptions` est une requête réseau, et la
    /// reposer à chaque ouverture coûterait sans rien apporter.
    var zoneSubscriptionInstalled: Bool {
        didSet { defaults.set(zoneSubscriptionInstalled, forKey: Key.zoneSubscriptionInstalled) }
    }

    /// Version de l'abonnement réellement posé. La v2 remplace l'ancien abonnement de zone
    /// silencieux par une alerte CloudKit, et emploie le type d'abonnement compatible avec
    /// la base partagée de l'invité. Un booléen seul ne pourrait pas distinguer une v1
    /// installée d'une v2 à poser.
    var likeNotificationSubscriptionVersion: Int {
        didSet {
            defaults.set(likeNotificationSubscriptionVersion,
                         forKey: Key.likeNotificationSubscriptionVersion)
        }
    }

    /// Les cœurs reçus des duos PASSÉS, gelés au désappairage. Ne rétrécit jamais.
    ///
    /// Deux listes et non une, parce qu'elles répondent à deux questions différentes :
    /// `receivedLikeEventIDs` dit ce que la zone COURANTE porte — il est donc remplacé à
    /// chaque lecture complète, ce qui fait bien disparaître un cœur que son auteur retire —
    /// et celle-ci dit ce qui a été reçu AVANT, ce qu'aucune zone ne peut plus confirmer.
    ///
    /// Sans elle, la promesse du §3.10 cassait un cran plus loin qu'on ne le croyait :
    /// `unpair()` préservait soigneusement les cœurs reçus, puis la première lecture
    /// complète du duo SUIVANT les remplaçait par ce que disait sa zone neuve, c'est-à-dire
    /// rien. Les Réglages promettent pourtant, juste au-dessus du bouton : « les cœurs déjà
    /// reçus restent sur tes repas et tes activités ».
    var likeHistoryEventIDs: [String] {
        didSet { defaults.set(likeHistoryEventIDs, forKey: Key.likeHistoryEventIDs) }
    }

    /// Les événements du PARTENAIRE auxquels j'ai envoyé un cœur. Persistés pour que la
    /// page s'ouvre hors ligne avec ses cœurs allumés (§3.10) : un cœur affiché éteint
    /// donnerait envie de le renvoyer alors qu'il est bien parti.
    ///
    /// Contrairement aux cœurs REÇUS, ceux-là partent au désappairage : ils vivent sur des
    /// entrées de l'autre, qu'on ne reverra jamais. Les garder n'afficherait rien nulle part.
    var givenLikeEventIDs: [String] {
        didSet { defaults.set(givenLikeEventIDs, forKey: Key.givenLikeEventIDs) }
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
        pairedAt = defaults.object(forKey: Key.pairedAt) as? Date
        // Voir la propriété : `object` et non `bool`, sous peine d'un interrupteur qui naît
        // éteint sur tous les appareils du monde.
        likeNotificationsEnabled =
            defaults.object(forKey: Key.likeNotificationsEnabled) as? Bool ?? true
        receivedLikeEventIDs = defaults.stringArray(forKey: Key.receivedLikeEventIDs) ?? []
        likeHistoryEventIDs = defaults.stringArray(forKey: Key.likeHistoryEventIDs) ?? []
        zoneChangeToken = defaults.data(forKey: Key.zoneChangeToken)
        givenLikeEventIDs = defaults.stringArray(forKey: Key.givenLikeEventIDs) ?? []
        zoneSubscriptionInstalled = defaults.bool(forKey: Key.zoneSubscriptionInstalled)
        likeNotificationSubscriptionVersion =
            defaults.integer(forKey: Key.likeNotificationSubscriptionVersion)
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
    /// Les cœurs déjà reçus survivent, et c'est le §3.10 : ils font partie de l'histoire,
    /// pas de la connexion. Ils sont VERSÉS dans l'archive plutôt que laissés en place, et
    /// la nuance est tout le correctif : la liste courante décrit la zone COURANTE, et la
    /// première lecture complète du duo suivant la remplace légitimement par ce que dit sa
    /// zone neuve. L'archive, elle, n'est relue par personne d'autre que l'affichage.
    ///
    /// `likeNotificationsEnabled` survit aussi : c'est une préférence d'appareil, comme le
    /// thème, et défaire un duo n'est pas une raison de la remettre à zéro.
    func unpair() {
        role = nil
        zoneName = nil
        zoneOwnerName = nil
        shareURL = nil
        profileLastSeenAt = nil
        unreadLikeCount = 0
        partnerSnapshot = nil
        pairedAt = nil
        // Geler ce qui a été reçu : voir `likeHistoryEventIDs`.
        likeHistoryEventIDs = Array(Set(likeHistoryEventIDs).union(receivedLikeEventIDs)).sorted()
        receivedLikeEventIDs = []
        // Le jeton et l'abonnement appartiennent à la ZONE, pas à l'appareil. Un jeton
        // survivant ferait repartir un futur duo au milieu de l'histoire d'un autre, et un
        // abonnement cru posé n'en ferait jamais poser de nouveau : plus aucun réveil, sans
        // le moindre signe.
        zoneChangeToken = nil
        zoneSubscriptionInstalled = false
        likeNotificationSubscriptionVersion = 0
        givenLikeEventIDs = []
        // Sans cette ligne, réappairer avec la même personne ne republierait RIEN tant
        // que la journée n'a pas changé : l'instantané construit serait égal à celui
        // d'avant le désappairage, et le partenaire n'aurait jamais rien à afficher.
        lastPublishedSnapshot = nil
    }
}
