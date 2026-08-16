// App/Services/DuoService.swift
// L'état observable du duo (spec 1.15 §3.6, §3.7, §3.8) : le seul objet sur lequel les
// écrans du lot A2 s'appuient. Aucune vue ne parle à CloudKit, elles parlent à celui-ci.
//
// Il lit la zone partagée, donc l'essentiel de ce fichier NE SE PROUVE PAS : ni le
// simulateur ni la CI ne savent jouer deux comptes iCloud. La parade est la même qu'au
// lot A1 et qu'en v1 avec `HomeView.bubbleDecision` : **toute décision est extraite en
// statique pure**, éprouvée par un test, et le reste est de la plomberie mince, écrite
// sans astuce. Cinq décisions vivent ici :
//
// 1. qui est mon partenaire parmi les membres de la zone (§3.6) ;
// 2. le partage doit-il rester ouvert (§3.6) ;
// 3. quels cœurs me visent (§3.7) ;
// 4. ce texte scanné est-il une invitation (§3.6) ;
// 5. que dit-on quand ça rate (§3.10).
//
// L'appairage est en fin de fichier, et il y est plutôt que dans un `+Pairing.swift` pour
// une raison précise : `identity` est `private`, donc visible des seules extensions de CE
// fichier. Aucun écran ne peut ainsi pousser lui-même un rôle ou une zone dans les
// réglages, et l'état d'appairage n'a qu'un seul auteur.
//
// Ce que ce fichier ne fait PAS, et qui viendra dans les tâches suivantes du lot : envoyer
// ou retirer un cœur. Le TEXTE des notifications ne vit pas ici non plus, mais dans
// `DuoNotifications` : ce service rend les cœurs nouvellement arrivés, un autre décide de
// ce qu'on en dit.

import CloudKit
import Foundation
import NivelCore

/// Ce qu'il faut savoir d'un membre de la zone pour désigner mon partenaire. Pas le
/// `CKRecord` lui-même : la décision est pure et doit s'éprouver sans nuage, comme
/// `DuoLikeRef` le fait pour le nettoyage des cœurs.
struct DuoMemberRef: Equatable, Sendable {
    let memberID: String
    /// Date de création de son enregistrement, posée par le SERVEUR. C'est elle qui
    /// désigne « le premier arrivé » du §3.6.
    ///
    /// Elle vaut `.distantFuture` quand elle est inconnue — un enregistrement jamais
    /// écrit n'en a pas. Le futur lointain et non le passé, exprès : un membre dont on
    /// ignore la date ne doit pas rafler la place de celui qui est réellement arrivé le
    /// premier.
    let createdAt: Date
}

/// Un cœur tel qu'il se lit dans la zone. Volontairement distinct de `DuoLikeRef`
/// (NivelCore), qui ne porte que les deux champs du nettoyage : ici on a besoin du
/// donneur, pour le filtrage client du §3.7, et du titre, pour le texte de notification.
struct DuoLike: Equatable, Sendable, Identifiable {
    /// Qui l'envoie. Peut être vide : un champ absent ne doit jamais faire disparaître un
    /// cœur, voir `DuoRecord.like(from:)`.
    let giverID: String
    /// À qui appartient l'événement aimé.
    let ownerID: String
    /// L'événement visé, c'est-à-dire le `publicID` d'une entrée locale.
    let eventID: String
    /// Recopié dans l'enregistrement pour que le texte de notification n'exige aucune
    /// relecture du fil (§3.3).
    let eventTitle: String
    let createdAt: Date

    /// Le nom d'enregistrement du cœur, qui est aussi son identité en liste. Recomposé
    /// par `DuoLikeID` plutôt qu'écrit à la main : ce nom est déterministe par décision,
    /// et il n'a le droit d'être fabriqué qu'à un seul endroit.
    var id: String { DuoLikeID.recordName(giver: giverID, event: eventID) }
}

@Observable @MainActor
final class DuoService {

    /// L'instance de l'app, et la seule que le réveil silencieux puisse atteindre : le
    /// délégué d'application n'a pas d'environnement SwiftUI où aller chercher quoi que ce
    /// soit. Même motif que `DuoIdentity.shared`, et même précaution — la construire ne lit
    /// rien, n'écrit rien et n'émet aucune requête, donc elle n'a pas d'effet de bord à
    /// naître. Les prévisualisations et les tests construisent la leur.
    static let shared = DuoService(identity: .shared)

    /// L'appairage de CET appareil. INJECTÉ, jamais `.shared` convoqué ici : c'est la
    /// règle posée en v1.6 pour `widgetDefaults` et reprise au lot A1 pour `duoIdentity`,
    /// et elle garantit qu'aucune suite de tests n'écrit dans les vrais réglages.
    private let identity: DuoIdentity

    /// La résolution (base, zone), c'est-à-dire `DuoDatabase`, injectée comme une
    /// fonction. Deux raisons, et la seconde est la vraie :
    ///
    /// - un test peut compter les résolutions et prouver que **sans duo appairé, la zone
    ///   n'est même pas résolue** — la promesse du §3.1, qui n'aurait autrement aucun
    ///   garde-fou ;
    /// - la valeur par défaut n'est PAS évaluée à la construction. Un `CKContainer` passé
    ///   en argument par défaut serait, lui, fabriqué au site d'appel, donc à chaque
    ///   naissance du service, y compris chez quelqu'un sans duo. Le lot A1 a payé
    ///   exactement cette erreur avec `publishDuo(identity: .shared)`.
    private let resolveTarget: (DuoIdentity) -> DuoDatabase.Target?

    /// Le conteneur iCloud, injecté comme une fabrique et pour les mêmes deux raisons que
    /// ci-dessus. L'appairage en a besoin AVANT qu'aucune zone n'existe, là où
    /// `resolveTarget` ne peut encore rien résoudre : créer la zone, créer le partage,
    /// accepter celui d'en face.
    ///
    /// Une fabrique et non un conteneur : appelée seulement quand une requête part
    /// vraiment, elle laisse les tests prouver qu'une garde a bien coupé le chemin avant.
    private let makeContainer: () -> CKContainer

    /// Les cœurs reçus, du plus ancien au plus récent. Alimente les petits cœurs des
    /// journaux Repas et Sport (§3.8), qui s'affichent sur ses PROPRES entrées.
    private(set) var receivedLikes: [DuoLike] = []

    /// Combien de membres la zone portait à la dernière lecture réussie, `nil` tant
    /// qu'aucune n'a abouti. C'est ce que `shouldKeepShareOpen` interroge pour refermer le
    /// lien derrière le premier arrivé. `nil` plutôt que `0` après un échec : « je ne sais
    /// pas » et « la zone est vide » ne mènent pas à la même décision.
    private(set) var memberCount: Int?

    /// La zone n'existe plus en face : le partenaire a désinstallé, ou le propriétaire a
    /// défait le duo de son côté. La section Duo des réglages en fait son quatrième état et
    /// propose de recommencer (§3.10).
    ///
    /// Distingué d'une panne de réseau avec soin : annoncer la fin d'un duo parce que le
    /// train est passé dans un tunnel serait le pire des faux positifs.
    private(set) var zoneIsGone = false

    /// Une lecture est en vol. Même coalescence que `publishDuo`, et pour la même raison :
    /// le retour au premier plan, l'ouverture de la page et le réveil silencieux peuvent
    /// se déclencher dans le même tour, et chacun coûte deux requêtes réseau.
    private var isRefreshing = false

    init(identity: DuoIdentity,
         resolveTarget: @escaping (DuoIdentity) -> DuoDatabase.Target? = {
             DuoDatabase.target(for: $0)
         },
         makeContainer: @escaping () -> CKContainer = {
             CKContainer(identifier: DuoDatabase.containerID)
         }) {
        self.identity = identity
        self.resolveTarget = resolveTarget
        self.makeContainer = makeContainer
    }

    // MARK: - Ce que les écrans lisent

    var isPaired: Bool { identity.isPaired }

    /// Le dernier instantané connu du partenaire, cache compris : c'est lui qui permet
    /// d'ouvrir la page HORS LIGNE sur les derniers chiffres connus au lieu d'un écran
    /// vide, la ligne « mis à jour il y a… » disant alors la vérité sur leur âge.
    ///
    /// Lu à travers `DuoIdentity`, qui est `@Observable` : les vues se rafraîchissent donc
    /// seules, et il n'existe qu'UNE source de vérité. En recopier une seconde ici ferait
    /// diverger le cache persisté de ce qui est affiché.
    var partnerSnapshot: DuoSnapshot? { identity.partnerSnapshot }

    /// Les cœurs arrivés dont on n'a pas encore parlé à l'utilisateur. Alimente la bulle de
    /// l'accueil (§3.9) ; remis à zéro par `markProfileSeen`.
    var unreadLikeCount: Int { identity.unreadLikeCount }

    /// Depuis quand ce duo existe, pour la ligne d'état des réglages (§3.9).
    var pairedAt: Date? { identity.pairedAt }

    /// L'interrupteur « Cœurs reçus » des réglages (§3.7). En écriture aussi : c'est le seul
    /// réglage du duo que l'utilisateur touche directement, et le faire passer par le service
    /// évite qu'un écran aille écrire dans `DuoIdentity` de sa propre main.
    var likeNotificationsEnabled: Bool {
        get { identity.likeNotificationsEnabled }
        set { identity.likeNotificationsEnabled = newValue }
    }

    /// Les cœurs que j'ai ENVOYÉS, par événement du partenaire. Persistés, plus les attentes
    /// locales posées par-dessus : un cœur donné hors ligne reste allumé sous le doigt.
    var givenLikeEventIDs: Set<String> {
        Self.applying(pendingLikes, to: Set(identity.givenLikeEventIDs))
    }

    /// Les cœurs partis, ou retirés, dont l'écriture n'a pas abouti. `true` = à poser,
    /// `false` = à retirer. Retentés au prochain rafraîchissement, puis ABANDONNÉS
    /// silencieusement (§3.10) : un cœur n'a pas d'importance au point de mériter une file
    /// persistante et des messages d'échec.
    private var pendingLikes: [String: Bool] = [:]

    /// Les événements à moi qui portent un cœur, pour les journaux Repas et Sport (§3.8).
    /// Lu depuis `DuoIdentity`, donc **persistant** : ils survivent au relancement et au
    /// désappairage, comme la spec l'exige.
    var likedEventIDs: Set<String> { Set(identity.receivedLikeEventIDs) }

    /// La pastille du bouton avatar de l'accueil (§3.9). La décision est celle du lot A1 ;
    /// ce service ne fait que lui apporter le fil et la date de dernière visite.
    var hasNewActivity: Bool {
        DuoBadge.hasNewActivity(feed: identity.partnerSnapshot?.events ?? [],
                                lastSeenAt: identity.profileLastSeenAt)
    }

    /// Ouvrir la page du partenaire éteint le signal (§3.9). La date est persistée par le
    /// `didSet` de `DuoIdentity` : sans cela la pastille reviendrait au lancement suivant,
    /// sur des événements déjà vus, et une pastille qui ment une fois n'est plus regardée.
    func markProfileSeen(at now: Date = .now) {
        identity.profileLastSeenAt = now
        identity.unreadLikeCount = 0
    }

    // MARK: - La lecture de la zone

    /// Ce qu'une lecture de changements a rendu. Un type nommé plutôt qu'un tuple de cinq
    /// membres : trois de ses champs sont des cas d'échec distincts, et les confondre est
    /// exactement ce qui rend un état muet.
    struct ZoneDelta {
        var members: [(reference: DuoMemberRef, record: CKRecord)] = []
        var likes: [DuoLike] = []
        /// Les noms d'enregistrement des cœurs SUPPRIMÉS depuis le jeton. Le serveur ne rend
        /// qu'un nom : c'est `DuoLikeID.eventID(fromRecordName:giver:)` qui dit quel cœur
        /// s'est éteint, en retirant un préfixe connu plutôt qu'en découpant à l'aveugle.
        var deletedLikeRecordNames: [String] = []
        var token: CKServerChangeToken?
        /// La lecture n'a rien donné : réseau, service occupé, compte parti. On garde tout
        /// ce qu'on sait et on ne conclut rien.
        var failed = false
        /// Le jeton est périmé : ce n'est pas une panne, c'est CloudKit qui demande de
        /// repartir d'une lecture complète.
        var tokenExpired = false
        var zoneGone = false
    }

    /// Relit la zone en ENTIER et reconstruit l'état : le partenaire, son instantané, les
    /// cœurs. Ne rend rien et ne lève rien — comme la publication, aucune erreur de duo
    /// n'interrompt l'utilisateur (§3.5). Un échec laisse le cache en place, et la ligne de
    /// fraîcheur dit son âge.
    func refresh() async {
        // La garde d'appairage est la PREMIÈRE ligne, avant même la résolution de la
        // zone : sans duo, le §3.1 promet qu'aucune requête n'est émise et que l'app se
        // comporte exactement comme la 1.14. Un test compte les résolutions.
        guard identity.isPaired, let me = identity.memberID else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let target = resolveTarget(identity) else { return }

        // Jeton NIL, donc lecture complète : c'est ce qui rend cette fonction sans mémoire,
        // et donc juste quoi qu'il se soit passé entre deux appels. Le jeton rendu est
        // gardé pour que le prochain RÉVEIL ne voie que ce qui est arrivé après.
        let delta = await fetchZoneChanges(in: target, since: nil)
        // La zone a disparu : on se désappaire ici et maintenant, plutôt que d'afficher un
        // duo qui n'existe plus et de laisser un réappairage hériter de son état.
        if delta.zoneGone { handleZoneLoss(); return }
        guard !delta.failed else { return }

        memberCount = delta.members.count
        if let partenaire = Self.partner(among: delta.members.map(\.reference), excluding: me),
           let record = delta.members.first(where: { $0.reference.memberID == partenaire.memberID })?
               .record,
           let instantane = DuoRecord.snapshot(from: record) {
            identity.partnerSnapshot = instantane
        }
        // Être SEUL dans la zone n'est pas une erreur : c'est l'instant entre l'acceptation
        // du partage et la première écriture de l'autre. On garde le cache et on n'affiche
        // aucun échec, surtout pas pendant l'appairage où tout va bien.

        // Les cœurs que j'ai donnés voyagent dans le même lot : c'est ce qui allume les
        // cœurs pleins de la page du partenaire, y compris après un relancement.
        identity.givenLikeEventIDs = delta.likes.filter { $0.giverID == me }.map(\.eventID)

        receivedLikes = Self.incomingLikes(from: delta.likes, me: me)
        // Compter AVANT d'écrire la nouvelle liste : c'est l'ancienne qui dit ce qu'on
        // connaissait déjà. Une lecture complète qui rangerait sans compter rendrait tout
        // cœur découvert ici invisible pour le réveil suivant, et donc pour toujours.
        identity.unreadLikeCount = Self.unreadCount(current: identity.unreadLikeCount,
                                                    known: likedEventIDs,
                                                    incoming: receivedLikes)
        // Recopiés dans l'état d'appareil pour survivre au relancement ET au désappairage
        // (§3.10). La liste REMPLACE la précédente : un cœur retiré par son auteur est une
        // suppression d'enregistrement, et il doit disparaître aussi ici. C'est précisément
        // ce que la lecture complète permet et qu'un delta ne permettrait pas.
        identity.receivedLikeEventIDs = receivedLikes.map(\.eventID)
        identity.zoneChangeToken = Self.archive(delta.token)

        // La place vient peut-être d'être prise. C'est ici, et nulle part ailleurs, qu'on le
        // sait sans payer une requête de plus. Sans effet dans tous les autres cas.
        await closeShareIfSeatTaken()
        await installSubscriptionIfNeeded(in: target)
        await retryPendingLikes(in: target, me: me)
    }

    /// Le réveil silencieux (§3.7) : lit ce qui a changé DEPUIS le dernier jeton, range, et
    /// rend les cœurs qui viennent d'arriver — c'est l'appelant qui notifie.
    ///
    /// Rend une liste vide dans tous les cas où il n'y a rien à annoncer, y compris sans duo
    /// appairé : un abonnement peut survivre quelques minutes côté serveur après un
    /// désappairage, et ce réveil-là ne doit rien faire du tout.
    @discardableResult
    func handleRemoteWake() async -> [DuoLike] {
        guard identity.isPaired, let me = identity.memberID,
              let target = resolveTarget(identity) else { return [] }

        var delta = await fetchZoneChanges(in: target,
                                           since: Self.unarchive(identity.zoneChangeToken))

        // Jeton périmé : CloudKit demande de repartir de zéro. Le confondre avec une panne
        // laisserait l'appareil coincé sur un jeton mort, à ne plus jamais rien recevoir, en
        // silence et pour toujours.
        if delta.tokenExpired {
            identity.zoneChangeToken = nil
            delta = await fetchZoneChanges(in: target, since: nil)
        }
        if delta.zoneGone { handleZoneLoss(); return [] }
        guard !delta.failed else { return [] }

        // L'instantané du partenaire voyage dans le même lot : le prendre au passage évite
        // une lecture de plus à l'ouverture de sa page.
        if let partenaire = Self.partner(among: delta.members.map(\.reference), excluding: me),
           let record = delta.members.first(where: { $0.reference.memberID == partenaire.memberID })?
               .record,
           let instantane = DuoRecord.snapshot(from: record) {
            identity.partnerSnapshot = instantane
        }

        // Nouveaux = qui me visent, et dont on n'a pas déjà parlé. Le filtrage du donneur
        // est CÔTÉ CLIENT (§3.7) : on ne s'en remet pas au fait que CloudKit épargnerait
        // l'appareil d'origine, sous peine de se notifier son propre cœur.
        let miens = Self.incomingLikes(from: delta.likes, me: me)
        let nouveaux = DuoNotifications.unseen(miens, knownEventIDs: likedEventIDs)

        // Les cœurs RETIRÉS par leur auteur pendant qu'on dormait. Sans cette prise en
        // compte, un cœur repris resterait affiché sur une entrée jusqu'à la prochaine
        // lecture complète — c'est-à-dire jusqu'au prochain passage au premier plan.
        let eteints = Self.extinguishedEventIDs(delta.deletedLikeRecordNames, me: me,
                                                partner: identity.partnerSnapshot?.memberID)
        if !eteints.isEmpty {
            receivedLikes.removeAll { eteints.contains($0.eventID) }
            identity.givenLikeEventIDs = identity.givenLikeEventIDs.filter {
                !eteints.contains($0)
            }
        }

        receivedLikes = Self.merge(receivedLikes, with: miens)
        identity.unreadLikeCount = Self.unreadCount(current: identity.unreadLikeCount,
                                                    known: likedEventIDs, incoming: miens)
        identity.receivedLikeEventIDs = receivedLikes.map(\.eventID)
        identity.zoneChangeToken = Self.archive(delta.token)

        return nouveaux
    }

    /// La lecture de changements de zone, et le SEUL chemin de lecture du duo.
    ///
    /// `CKFetchRecordZoneChangesOperation` plutôt que `CKQuery`, et ce n'est pas une
    /// élégance : une requête exige un index QUERYABLE posé à la main dans le tableau de
    /// bord CloudKit. S'il manque, la lecture ne lève pas — elle rend zéro résultat. Le
    /// symptôme serait un appairage réussi qui reste éternellement « en attente de l'autre
    /// iPhone », sans le moindre message. La lecture de changements n'exige aucun index, et
    /// c'est de toute façon elle que le réveil silencieux impose.
    ///
    /// Jeton nil : la zone entière. Jeton présent : ce qui a changé depuis.
    private func fetchZoneChanges(in target: DuoDatabase.Target,
                                  since token: CKServerChangeToken?) async -> ZoneDelta {
        var delta = ZoneDelta()
        do {
            let reponse = try await target.database.recordZoneChanges(inZoneWith: target.zoneID,
                                                                      since: token)

            for (_, resultat) in reponse.modificationResultsByID {
                guard let record = try? resultat.get().record else { continue }
                switch record.recordType {
                case DuoRecord.memberType:
                    if let reference = DuoRecord.memberRef(from: record) {
                        delta.members.append((reference, record))
                    }
                case DuoRecord.likeType:
                    if let coeur = DuoRecord.like(from: record) { delta.likes.append(coeur) }
                default:
                    continue
                }
            }
            for suppression in reponse.deletions where suppression.recordType == DuoRecord.likeType {
                delta.deletedLikeRecordNames.append(suppression.recordID.recordName)
            }
            delta.token = reponse.changeToken
            zoneIsGone = false
        } catch {
            delta.failed = true
            delta.tokenExpired = Self.shouldRestartFromScratch(error: error)
            delta.zoneGone = Self.isZoneGone(error: error)
            // L'erreur est REGARDÉE, et pas seulement avalée : c'est ici, et nulle part
            // ailleurs, qu'on apprend que la zone a disparu.
            zoneIsGone = delta.zoneGone
        }
        return delta
    }

    /// Fusionne les cœurs d'un delta avec ceux déjà en main, sans doublon et dans l'ordre
    /// d'affichage. Un delta ne dit rien des cœurs qu'il ne mentionne pas : les écraser
    /// ferait disparaître de l'écran tout ce qui n'a pas bougé depuis le dernier jeton.
    nonisolated static func merge(_ existants: [DuoLike], with arrivants: [DuoLike]) -> [DuoLike] {
        var parIdentifiant: [String: DuoLike] = [:]
        for coeur in existants + arrivants { parIdentifiant[coeur.id] = coeur }
        return parIdentifiant.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Les événements dont le cœur vient d'être retiré, à partir des noms d'enregistrement
    /// supprimés.
    ///
    /// Les deux donneurs possibles sont connus — moi et le partenaire — puisque la zone n'a
    /// que deux membres : on essaie l'un puis l'autre, et on ne suppose jamais. Un nom qui ne
    /// vient ni de l'un ni de l'autre est ignoré plutôt qu'interprété.
    nonisolated static func extinguishedEventIDs(_ recordNames: [String], me: String,
                                                 partner: String?) -> Set<String> {
        let donneurs = [me, partner].compactMap { $0 }.filter { !$0.isEmpty }
        return Set(recordNames.compactMap { nom in
            donneurs.lazy.compactMap { DuoLikeID.eventID(fromRecordName: nom, giver: $0) }.first
        })
    }

    /// Le compteur de cœurs non lus après avoir vu passer `incoming`, sachant `known`.
    ///
    /// **Les deux chemins de lecture passent par ici, et c'est le point.** La lecture
    /// complète rangeait auparavant les cœurs reçus sans jamais les compter : un cœur
    /// découvert en ouvrant les Réglages devenait « déjà vu » pour le réveil suivant, donc
    /// ni bulle ni notification, jamais. Deux chemins qui écrivent le même état doivent le
    /// compter de la même façon, ou l'un efface le travail de l'autre.
    ///
    /// Qui incrémente : les deux lectures, sur ce qu'elles découvrent d'inédit. Qui remet à
    /// zéro : `markProfileSeen`, et lui seul — c'est-à-dire l'ouverture de la page, qui est
    /// le seul moment où l'utilisateur a réellement VU les cœurs.
    nonisolated static func unreadCount(current: Int, known: Set<String>,
                                        incoming: [DuoLike]) -> Int {
        current + DuoNotifications.unseen(incoming, knownEventIDs: known).count
    }

    /// Ce jeton est-il périmé ? (§3.7) Un seul code le dit, et il ne veut PAS dire « panne » :
    /// il veut dire « recommence depuis le début ».
    nonisolated static func shouldRestartFromScratch(error: Error) -> Bool {
        (error as? CKError)?.code == .changeTokenExpired
    }

    /// Le jeton voyage en `Data` jusqu'à `DuoIdentity`, qui n'importe pas CloudKit : c'est de
    /// l'état d'appareil, pas du transport. `try?` des deux côtés — un jeton illisible fait
    /// repartir d'une lecture complète, ce qui est toujours correct, jamais un blocage.
    private nonisolated static func archive(_ token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token,
                                                 requiringSecureCoding: true)
    }

    private nonisolated static func unarchive(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self,
                                                       from: data)
    }

    /// Pose l'abonnement de zone SILENCIEUX (§3.7), une fois par appareil et par duo.
    ///
    /// `shouldSendContentAvailable = true` et AUCUN `alertBody` : le système réveille l'app
    /// sans rien montrer, et c'est l'app qui décide s'il y a lieu de dire quelque chose. Un
    /// abonnement bavard alerterait à chaque mise à jour d'anneau, plusieurs fois par jour,
    /// pour des chiffres que personne n'a demandé à voir.
    ///
    /// `CKQuerySubscription`, qui filtrerait sur les seuls `DuoLike`, n'existe pas dans la
    /// base partagée : l'invité n'a droit qu'à un abonnement de zone. On prend donc le même
    /// des deux côtés, pour n'avoir qu'un seul comportement à comprendre.
    private func installSubscriptionIfNeeded(in target: DuoDatabase.Target) async {
        guard !identity.zoneSubscriptionInstalled else { return }

        let abonnement = CKRecordZoneSubscription(zoneID: target.zoneID,
                                                  subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        abonnement.notificationInfo = info

        guard (try? await target.database.modifySubscriptions(saving: [abonnement],
                                                              deleting: [])) != nil
        else { return }
        identity.zoneSubscriptionInstalled = true
    }

    /// Identifiant fixe : reposer le même abonnement le remplace au lieu d'en empiler un
    /// second, donc un appareil ne peut pas se retrouver réveillé deux fois par changement.
    static let subscriptionID = "nivel.duo.zone"

    // MARK: - Les cœurs

    /// Allume ou éteint le cœur d'un événement du partenaire (spec §3.8). Un tap l'allume,
    /// un second le retire ; pas de compteur, à deux « aimé » ou « pas aimé » suffit.
    ///
    /// **Optimiste** : l'écran répond tout de suite, avant l'aller-retour réseau. Un cœur
    /// qui attendrait la confirmation du serveur donnerait un bouton mou, et on taperait
    /// deux fois.
    ///
    /// Aucun message d'erreur, jamais : l'écriture ratée est retentée au prochain
    /// rafraîchissement, puis abandonnée. C'est un cœur, pas un virement.
    func toggleLike(on event: DuoEvent) async {
        guard identity.isPaired, let me = identity.memberID,
              // Le propriétaire de l'événement est le partenaire, et on ne l'invente pas :
              // sans son identifiant, l'enregistrement du cœur désignerait n'importe qui.
              let proprietaire = identity.partnerSnapshot?.memberID, !proprietaire.isEmpty,
              // Un événement sans identifiant ne s'aime pas : `like-G1-` se confondrait avec
              // le cœur d'une autre entrée non identifiée (§3.4). `DuoFeedBuilder` ne publie
              // déjà que des événements identifiés ; ceci est le filet.
              !event.id.isEmpty,
              let target = resolveTarget(identity) else { return }

        let etaitAime = givenLikeEventIDs.contains(event.id)
        setGiven(event.id, liked: !etaitAime)

        let recordID = CKRecord.ID(recordName: DuoLikeID.recordName(giver: me, event: event.id),
                                   zoneID: target.zoneID)
        do {
            if etaitAime {
                // Suppression PAR NOM, sans lecture préalable : c'est exactement ce que le
                // nom déterministe du §3.3 achète.
                _ = try await target.database.modifyRecords(saving: [], deleting: [recordID],
                                                            savePolicy: .changedKeys,
                                                            atomically: false)
            } else {
                let record = DuoRecord.like(giver: me, owner: proprietaire, event: event,
                                            in: target.zoneID)
                _ = try await target.database.modifyRecords(saving: [record], deleting: [],
                                                            savePolicy: .changedKeys,
                                                            atomically: false)
            }
            pendingLikes.removeValue(forKey: event.id)
        } catch {
            pendingLikes[event.id] = !etaitAime
        }
    }

    /// Retente ce qui n'est pas passé, UNE fois, puis oublie (§3.10). La file est vidée quoi
    /// qu'il arrive : la garder ferait revivre indéfiniment un geste d'il y a trois jours,
    /// sur un fil qui n'existe plus.
    private func retryPendingLikes(in target: DuoDatabase.Target, me: String) async {
        guard !pendingLikes.isEmpty,
              let proprietaire = identity.partnerSnapshot?.memberID, !proprietaire.isEmpty
        else { pendingLikes.removeAll(); return }

        let aRejouer = pendingLikes
        pendingLikes.removeAll()
        for (evenement, aimer) in aRejouer {
            let recordID = CKRecord.ID(recordName: DuoLikeID.recordName(giver: me,
                                                                        event: evenement),
                                       zoneID: target.zoneID)
            if aimer {
                // Le titre n'est plus sous la main : l'événement du fil a pu changer. On
                // republie ce qu'on sait, et le partenaire lira son propre libellé faute de
                // mieux — mieux vaut un cœur sans titre qu'un cœur perdu.
                let evenementMinimal = DuoEvent(id: evenement, kind: .unknown, at: .now,
                                                title: "", subtitle: "")
                let record = DuoRecord.like(giver: me, owner: proprietaire,
                                            event: evenementMinimal, in: target.zoneID)
                _ = try? await target.database.modifyRecords(saving: [record], deleting: [],
                                                             savePolicy: .changedKeys,
                                                             atomically: false)
            } else {
                _ = try? await target.database.modifyRecords(saving: [], deleting: [recordID],
                                                             savePolicy: .changedKeys,
                                                             atomically: false)
            }
        }
    }

    /// Écrit l'état local d'un cœur donné, tout de suite : c'est ce que l'écran lit.
    private func setGiven(_ eventID: String, liked: Bool) {
        var donnes = Set(identity.givenLikeEventIDs)
        if liked { donnes.insert(eventID) } else { donnes.remove(eventID) }
        identity.givenLikeEventIDs = donnes.sorted()
        // L'attente locale prime jusqu'à la prochaine lecture réussie de la zone : sans
        // elle, un rafraîchissement arrivé entre le tap et l'écriture rallumerait ou
        // éteindrait le cœur sous le doigt.
        pendingLikes[eventID] = liked
    }

    /// Les cœurs donnés tels qu'on les AFFICHE : ce que la zone dit, corrigé de ce qu'on
    /// vient de faire et qui n'est pas encore parti.
    nonisolated static func applying(_ pending: [String: Bool],
                                     to given: Set<String>) -> Set<String> {
        var affiches = given
        for (evenement, aime) in pending {
            if aime { affiches.insert(evenement) } else { affiches.remove(evenement) }
        }
        return affiches
    }

    // MARK: - Les décisions

    /// Mon partenaire parmi les membres de la zone : celui qui n'est pas moi, et **le
    /// premier créé** si la zone en porte deux (§3.6).
    ///
    /// Le cas à deux autres n'est pas théorique : le partage est en `.readWrite`, donc
    /// ouvert à quiconque possède l'URL, et deux personnes peuvent l'accepter avant qu'il
    /// ne se referme. Il faut alors trancher sans hasard.
    ///
    /// Le départage sur l'identifiant à date égale n'est pas de la coquetterie : les deux
    /// téléphones prennent cette décision CHACUN DE LEUR CÔTÉ, sur la même zone. Sans
    /// second critère, l'ordre dépendrait de celui de la réponse CloudKit, qui n'est promis
    /// par rien, et chacun pourrait désigner un partenaire différent — un désaccord
    /// silencieux et permanent.
    ///
    /// Rendre `nil` n'est pas une erreur : être seul dans la zone est l'état normal entre
    /// l'acceptation du partage et la première écriture de l'autre.
    ///
    /// `nonisolated` : cette décision ne touche à rien et n'a pas d'acteur. Même motif que
    /// `GameService.dayKey`.
    nonisolated static func partner(among members: [DuoMemberRef],
                                    excluding me: String) -> DuoMemberRef? {
        members
            // Un identifiant vide n'est pas quelqu'un. `DuoIdentity` traite déjà la chaîne
            // vide comme une absence, pour la même raison : elle serait acceptée partout
            // ailleurs sans en être un, et elle gagnerait ici si elle était la plus ancienne.
            .filter { !$0.memberID.isEmpty && $0.memberID != me }
            .min { ($0.createdAt, $0.memberID) < ($1.createdAt, $1.memberID) }
    }

    /// Le lien se referme derrière le premier arrivé (§3.6). Un `CKShare` en
    /// `publicPermission = .readWrite` reste valide tant qu'on ne le révoque pas : un QR
    /// photographié par-dessus l'épaule, ou une capture d'écran qui traîne, suffirait à
    /// faire entrer un tiers. Dès qu'un second membre est là, la place est prise.
    nonisolated static func shouldKeepShareOpen(memberCount: Int) -> Bool { memberCount < 2 }

    /// Les cœurs qui me visent : ceux dont je ne suis pas le donneur et dont je possède
    /// l'événement (§3.7).
    ///
    /// **Le filtrage est côté client.** On ne s'en remet pas au fait que CloudKit
    /// épargnerait l'appareil d'origine d'un changement : c'est une politesse du service,
    /// pas une garantie, et s'y fier ferait notifier quelqu'un de son propre cœur.
    ///
    /// Le tri par date sert l'affichage : l'ordre d'une réponse CloudKit n'est promis par
    /// rien, et `createdAt` est publié précisément pour cela (§3.3). L'identifiant départage
    /// à date égale, pour que deux lectures de la même zone rendent la même liste.
    nonisolated static func incomingLikes(from likes: [DuoLike], me: String) -> [DuoLike] {
        likes
            .filter { $0.ownerID == me && $0.giverID != me }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    // MARK: - L'URL d'une invitation

    /// Ce qu'on a lu dans un QR code ou dans le champ « coller un lien ».
    enum ShareURLCheck: Equatable {
        case valid(URL)
        /// Le message à afficher tel quel. Une phrase pour la personne qui vient de
        /// scanner, jamais une erreur technique.
        case invalid(String)
    }

    /// Le champ est vide : on dit QUOI FAIRE plutôt que de constater un échec. Ce n'est pas
    /// la même situation qu'un lien refusé, et donc pas la même phrase : ici rien n'a encore
    /// été tenté.
    nonisolated static let emptyShareMessage = "Colle ici le lien reçu pour rejoindre un duo"

    /// Refus d'un lien qui n'est pas une invitation. Il dit la suite à donner, parce qu'un
    /// refus sans issue est une impasse, et il ne parle ni d'URL ni de domaine.
    nonisolated static let invalidShareMessage =
        "Ce lien n'est pas une invitation de duo. Demande à l'autre de te renvoyer son QR code."

    /// Une invitation, ou le message qui explique pourquoi ce n'en est pas une (§3.6).
    ///
    /// Le scanner lit N'IMPORTE QUEL QR code — une étiquette de colis, un wifi, une
    /// publicité — et le champ de repli accepte n'importe quel texte collé. Sans ce filtre,
    /// `CKFetchShareMetadataOperation` recevrait une URL quelconque et rendrait une erreur
    /// CloudKit brute, illisible pour qui vient simplement de scanner le mauvais carré noir.
    ///
    /// Trois conditions, et la deuxième est celle qui compte :
    ///
    /// - `https`, jamais en clair : une invitation iCloud l'est toujours, et suivre un lien
    ///   en clair reviendrait à accepter qu'il ait été réécrit en route ;
    /// - le domaine est `icloud.com` ou l'un de ses sous-domaines. La comparaison porte sur
    ///   la FIN du nom d'hôte, jamais sur sa présence quelque part dedans :
    ///   `icloud.com.pas-apple.tld` contient « icloud.com » et n'a rien d'Apple ;
    /// - le chemin est celui d'un partage, et il porte quelque chose derrière. `/share/`
    ///   tout seul ne désigne rien.
    nonisolated static func shareURL(from raw: String) -> ShareURLCheck {
        // Le scanner rend souvent un retour à la ligne, et un lien collé depuis Messages
        // traîne presque toujours une espace. Refuser pour cela serait incompréhensible
        // devant un QR parfaitement valide.
        let texte = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return .invalid(emptyShareMessage) }

        guard let url = URL(string: texte),
              url.scheme?.lowercased() == "https",
              let hote = url.host()?.lowercased(),
              hote == "icloud.com" || hote.hasSuffix(".icloud.com"),
              isSharePath(url)
        else { return .invalid(invalidShareMessage) }

        return .valid(url)
    }

    /// `/share/<jeton>`, le chemin d'une invitation. Le jeton peut voyager dans le
    /// fragment (`…/share/#abc`) selon la forme du lien, donc l'un ou l'autre suffit — mais
    /// un `/share` nu, qui ne désigne aucun partage, est refusé.
    private nonisolated static func isSharePath(_ url: URL) -> Bool {
        let composants = url.pathComponents.filter { $0 != "/" }
        guard composants.first == "share" else { return false }
        return composants.count > 1 || !(url.fragment() ?? "").isEmpty
    }
}

// MARK: - L'appairage

// Dans le MÊME fichier, et pas dans un `DuoService+Pairing.swift` : `identity` est
// `private`, donc visible des seules extensions de ce fichier. C'est ce qui garde
// l'écriture de l'état d'appairage ici et empêche un écran d'aller pousser lui-même un
// rôle ou une zone dans les réglages.
extension DuoService {

    /// Ce que l'écran d'invitation affiche : le QR, ou une phrase.
    enum InvitationResult: Equatable {
        case ready(URL)
        /// Message affichable tel quel. **Jamais une alerte modale par-dessus l'accueil** :
        /// un échec d'appairage se raconte dans l'écran qui l'a demandé.
        case failed(String)
    }

    /// Crée la zone `duo`, la partage, et rend l'URL à mettre en QR code (spec §3.6).
    ///
    /// **Idempotente**, et ce n'est pas une commodité : rouvrir l'écran d'invitation
    /// tenterait autrement un second `CKShare` sur la même zone, ce que le serveur refuse.
    /// L'écran montrerait alors un message d'échec sous un QR code parfaitement valide.
    ///
    /// `publicPermission = .readWrite` est le mode « toute personne disposant du lien » : il
    /// n'exige pas de connaître l'Apple ID de l'autre, ce qui est tout l'intérêt du QR. Sa
    /// contrepartie est le §3.6 : le lien reste valide tant qu'on ne le révoque pas, donc il
    /// se referme dès qu'un second membre apparaît, et l'écran le dit.
    func startInvitation() async -> InvitationResult {
        // L'identité de cet appareil naît ICI, et l'appairage est son seul appelant
        // légitime (lot A1). L'oublier appairerait un duo qui ne publierait JAMAIS rien :
        // `publishDuoNow` sort sur `guard let memberID`, en silence et pour toujours.
        // Avant la garde d'idempotence, donc : un appareil qui a déjà son partage mais pas
        // son identifiant est exactement le cas qu'une version antérieure a pu laisser.
        identity.createMemberID()

        if identity.role == .owner, let url = identity.shareURL { return .ready(url) }

        let base = makeContainer().privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: DuoDatabase.defaultZoneName,
                                     ownerName: CKCurrentUserDefaultName)
        do {
            // Sauver une zone qui existe déjà est sans effet et sans erreur : c'est ce qui
            // rend ce chemin rejouable après un échec réseau au milieu.
            _ = try await base.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)],
                                                 deleting: [])

            // Partage de ZONE, pas d'enregistrement : tout ce qui entre dans `duo` est
            // partagé, y compris les enregistrements que l'autre y écrira. Un partage
            // accroché à un enregistrement racine ne couvrirait que sa hiérarchie, et le
            // `DuoMember` de l'invité n'en ferait pas partie.
            let partage = CKShare(recordZoneID: zoneID)
            partage.publicPermission = .readWrite
            // Ce titre est ce que le système affiche dans la feuille de partage et dans
            // les réglages iCloud du partenaire. Il n'est lu par personne d'autre.
            partage[CKShare.SystemFieldKey.title] = "Nivel, à deux"

            let (ecritures, _) = try await base.modifyRecords(saving: [partage], deleting: [],
                                                              savePolicy: .changedKeys)
            guard let sauve = ecritures.values.compactMap({ (try? $0.get()) as? CKShare }).first,
                  let url = sauve.url
            else { return .failed(Self.genericFailureMessage) }

            // Le rôle n'est posé qu'ICI, après le succès. Le poser avant rendrait
            // `isPaired` vrai sans zone, et toute l'app se mettrait à publier dans le vide.
            identity.role = .owner
            identity.zoneName = zoneID.zoneName
            // Le propriétaire n'a pas de `zoneOwnerName` : sa zone est la sienne, et une
            // valeur restée d'un appairage précédent enverrait `DuoDatabase` chercher la
            // zone de quelqu'un d'autre.
            identity.zoneOwnerName = nil
            identity.shareURL = url
            // Depuis quand ce duo existe, pour la ligne d'état des réglages (§3.9). Posé une
            // fois, à la création : rouvrir l'écran ne le repousse pas, la garde
            // d'idempotence étant sortie bien avant.
            identity.pairedAt = .now
            zoneIsGone = false
            return .ready(url)
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    /// Ce que l'écran « Rejoindre » affiche.
    enum JoinResult: Equatable {
        case joined
        case failed(String)
    }

    /// Accepte l'invitation lue au QR code ou collée dans le champ (spec §3.6).
    ///
    /// **La validation tranche AVANT toute requête**, et c'est le cas courant, pas le cas
    /// tordu : un scanner lit n'importe quel carré noir, une étiquette de colis comme une
    /// affiche. Envoyer ce texte à `CKFetchShareMetadataOperation` rendrait une erreur
    /// CloudKit brute, illisible pour qui vient simplement de viser à côté.
    ///
    /// On n'implémente PAS le rappel système d'acceptation de partage
    /// (`windowScene(_:userDidAcceptCloudKitShareWith:)`) : il exigerait un `SceneDelegate`
    /// dans une app qui n'en a pas, et l'URL nous arrive toujours par notre propre scanner
    /// ou par notre propre champ. Contrepartie assumée : ouvrir le lien depuis Messages
    /// proposera d'ouvrir Nivel sans rien appairer, et l'écran dit que le chemin sûr est de
    /// coller le lien ici.
    func join(shareURL raw: String) async -> JoinResult {
        switch Self.shareURL(from: raw) {
        case .invalid(let message):
            return .failed(message)
        case .valid(let url):
            return await accept(url)
        }
    }

    private func accept(_ url: URL) async -> JoinResult {
        // Comme à l'invitation : sans identifiant, le duo s'appairerait sans jamais rien
        // publier. C'est la seconde et dernière porte d'entrée de `createMemberID()`.
        identity.createMemberID()

        let conteneur = makeContainer()
        do {
            // Les deux opérations que la spec nomme, sous leur forme asynchrone :
            // `CKFetchShareMetadataOperation` puis `CKAcceptSharesOperation`.
            let metadonnees = try await conteneur.shareMetadata(for: url)
            let partage = try await conteneur.accept(metadonnees)

            // La zone de l'invité porte le `ownerName` du PROPRIÉTAIRE, jamais
            // `__defaultOwner__` : sans lui, `DuoDatabase` reconstruirait une zone à soi,
            // où l'on écrirait tranquillement des chiffres que personne ne lit. C'est le
            // seul endroit du dépôt où cette valeur est obtenue.
            let zoneID = partage.recordID.zoneID
            identity.role = .guest
            identity.zoneName = zoneID.zoneName
            identity.zoneOwnerName = zoneID.ownerName
            // L'invité n'a pas de lien à montrer : le QR est l'affaire de celui qui invite.
            identity.shareURL = nil
            identity.pairedAt = .now
            zoneIsGone = false
            return .joined
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    /// Referme le partage derrière le premier arrivé (spec §3.6). Sans effet chez l'invité,
    /// qui ne possède pas le partage, et sans effet tant que la place est libre.
    ///
    /// Appelé depuis `refresh()`, donc au moment exact où le compte de membres vient d'être
    /// relu : c'est le seul instant où l'on sait, sans requête supplémentaire, que la place
    /// est prise. Un échec est silencieux et sera retenté au rafraîchissement suivant ; le
    /// pire cas est un lien qui reste ouvert quelques minutes de plus.
    func closeShareIfSeatTaken() async {
        guard identity.role == .owner, let compte = memberCount,
              !Self.shouldKeepShareOpen(memberCount: compte),
              let target = resolveTarget(identity) else { return }

        // Le partage d'une zone entière porte ce nom d'enregistrement réservé. Le relire
        // plutôt que garder le nôtre en mémoire évite d'écrire par-dessus une version que
        // le serveur aurait fait évoluer entre-temps.
        let partageID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: target.zoneID)
        guard let partage = try? await target.database.record(for: partageID) as? CKShare,
              partage.publicPermission != .none else { return }

        partage.publicPermission = .none
        guard (try? await target.database.modifyRecords(saving: [partage], deleting: [],
                                                        savePolicy: .changedKeys)) != nil
        else { return }

        // Le lien ne mène plus nulle part : ne plus le garder, c'est aussi ne plus pouvoir
        // l'afficher en QR code par mégarde.
        identity.shareURL = nil
    }

    /// Cette erreur dit-elle que la zone n'existe plus ? (spec §3.10)
    ///
    /// Deux codes seulement, et le tri compte : une panne de réseau, un service occupé ou un
    /// compte déconnecté sont PASSAGERS. Les confondre avec une zone disparue ferait
    /// annoncer la fin du duo à quelqu'un dont le train vient d'entrer dans un tunnel, et
    /// l'écran lui proposerait de tout recommencer.
    nonisolated static func isZoneGone(error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        return ck.code == .zoneNotFound || ck.code == .userDeletedZone
    }

    /// Y a-t-il un compte iCloud sur cet appareil ? Sans lui, rien du duo ne peut marcher, et
    /// la section des réglages le dit au lieu de laisser tenter un appairage voué à l'échec.
    func accountIsAvailable() async -> Bool {
        (try? await makeContainer().accountStatus()) == .available
    }

    /// Défait le duo (spec §3.10). Le propriétaire supprime la zone, l'invité quitte le
    /// partage : dans les deux cas, c'est la MÊME opération sur la base que `DuoDatabase` a
    /// déjà choisie pour nous, privée d'un côté, partagée de l'autre. L'asymétrie reste
    /// enfermée là où elle est née.
    ///
    /// **L'état local est effacé même si le nuage n'a pas répondu.** Quelqu'un hors ligne
    /// doit pouvoir quitter un duo : l'inverse ferait d'un défaut de réseau une porte
    /// verrouillée. Le pire cas est une zone qui survit quelques jours chez l'autre, que
    /// son propre désappairage effacera.
    ///
    /// Ce qui SURVIT est écrit sur `DuoIdentity.unpair()` : le `memberID` de cet appareil et
    /// les cœurs déjà reçus.
    func unpair() async {
        if let target = resolveTarget(identity) {
            _ = try? await target.database.modifyRecordZones(saving: [], deleting: [target.zoneID])
        }
        wipeLocalPairing()
    }

    /// La zone n'existe plus en face (spec §3.10) : le partenaire a désinstallé, ou l'autre
    /// a défait le duo de son côté. **On se désappaire pour de bon**, et l'écran propose de
    /// recommencer.
    ///
    /// Ce n'est pas un raffinement d'affichage, c'est ce qui empêche un mode de panne
    /// silencieux et définitif : en restant « appairé » sur une zone morte, un invité qui
    /// réinvitait ensuite gardait `zoneSubscriptionInstalled` à vrai, donc n'obtenait
    /// AUCUN abonnement sur sa nouvelle zone, donc plus jamais un seul réveil. Il gardait
    /// aussi le dernier instantané publié de l'ancien duo, si bien que son nouveau
    /// partenaire restait sur une page vide tant qu'un chiffre n'avait pas bougé. Le
    /// commentaire de `unpair()` décrivait déjà ces deux pièges ; ce chemin-ci ne passait
    /// simplement pas par lui.
    ///
    /// `zoneIsGone` est repositionné APRÈS l'effacement, exprès : c'est lui qui fait dire à
    /// l'écran « ce duo n'existe plus » au lieu du muet « aucun duo », le temps que
    /// l'utilisateur en refasse un.
    func handleZoneLoss() {
        wipeLocalPairing()
        zoneIsGone = true
    }

    /// L'effacement local, partagé par le désappairage volontaire et la perte de zone. Il
    /// ne touche PAS aux cœurs déjà reçus : ils font partie de l'histoire, pas de la
    /// connexion (§3.10).
    private func wipeLocalPairing() {
        identity.unpair()
        memberCount = nil
        zoneIsGone = false
    }

    /// Le repli quand aucun cas ne correspond, et le plus fréquent en vrai : CloudKit a une
    /// quarantaine de codes, on ne prétend pas les nommer tous.
    nonisolated static let genericFailureMessage =
        "Le duo n'a pas pu être mis en place pour l'instant, réessaie dans un moment"

    /// Ce qu'on montre quand une opération d'appairage rate (spec §3.10).
    ///
    /// Une phrase, jamais un code ni un type : la personne qui lit vient de scanner un QR
    /// code, elle n'a que faire d'un `CKError 9`. Et quand il y a une suite à donner, la
    /// phrase la donne — c'est le cas du compte iCloud absent, le seul où quelque chose se
    /// règle ailleurs que dans Nivel.
    ///
    /// Aucune ne reproche quoi que ce soit : la règle zéro culpabilisation de la v1 vaut
    /// aussi pour les pannes, qui ne sont jamais la faute de celui qui les subit.
    nonisolated static func message(for error: Error) -> String {
        guard let ck = error as? CKError else { return genericFailureMessage }

        switch ck.code {
        case .notAuthenticated:
            return "Connecte-toi à iCloud dans les réglages de l'iPhone pour créer un duo"
        case .networkUnavailable, .networkFailure:
            return "Pas de connexion pour l'instant, réessaie dans un moment"
        case .quotaExceeded:
            return "Ton espace iCloud est plein, la zone du duo n'a pas pu y être créée"
        case .permissionFailure:
            return "Le partage n'est pas autorisé sur ce compte iCloud"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud est occupé pour l'instant, réessaie dans un moment"
        case .unknownItem:
            // Le cas d'une invitation révoquée ou déjà refermée : la zone existe toujours
            // chez l'autre, mais ce lien-ci ne mène plus à rien.
            return "Cette invitation n'est plus valable, demande à l'autre de t'en renvoyer une"
        default:
            return genericFailureMessage
        }
    }
}
