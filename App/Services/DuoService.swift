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
// Ce que ce fichier ne fait PAS, et qui viendra dans les tâches suivantes du lot : poser
// l'abonnement de zone, envoyer ou retirer un cœur.

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

    /// Relit la zone : les membres, donc le partenaire et son instantané, puis les cœurs
    /// qui me visent. Ne rend rien et ne lève rien — comme la publication, aucune erreur
    /// de duo n'interrompt l'utilisateur (§3.5). Un échec laisse simplement le cache en
    /// place, et la ligne de fraîcheur dit son âge.
    func refresh() async {
        // La garde d'appairage est la PREMIÈRE ligne, avant même la résolution de la
        // zone : sans duo, le §3.1 promet qu'aucune requête n'est émise et que l'app se
        // comporte exactement comme la 1.14. Un test compte les résolutions.
        guard identity.isPaired, let me = identity.memberID else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let target = resolveTarget(identity) else { return }

        // Membres et cœurs se lisent dans le même passage : la page a besoin des deux, et
        // les séparer doublerait le nombre de réveils réseau pour rien.
        //
        // Les deux lectures rendent un OPTIONNEL, et rien de ce qui suit ne s'exécute sur
        // un échec. La nuance est tout sauf cosmétique : une lecture ratée qui rendrait un
        // tableau vide effacerait les cœurs déjà affichés dans les journaux Repas et Sport,
        // et annoncerait une zone sans personne. Un passage en mode avion suffirait à faire
        // disparaître ce que le duo s'est envoyé. Hors ligne, on garde ce qu'on sait.
        if let membres = await fetchMembers(in: target) {
            memberCount = membres.count

            if let partenaire = Self.partner(among: membres.map(\.reference), excluding: me),
               let record = membres.first(where: { $0.reference.memberID == partenaire.memberID })?
                   .record,
               let instantane = DuoRecord.snapshot(from: record) {
                identity.partnerSnapshot = instantane
            }
            // Être SEUL dans la zone n'est pas une erreur : c'est l'instant entre
            // l'acceptation du partage et la première écriture de l'autre. On garde le
            // cache et on n'affiche aucun échec, surtout pas pendant l'appairage où tout
            // va bien.
        }

        if let coeurs = await fetchLikes(in: target, me: me) {
            receivedLikes = Self.incomingLikes(from: coeurs, me: me)
        }

        // La place vient peut-être d'être prise. C'est ici, et nulle part ailleurs, qu'on
        // le sait sans payer une requête de plus : le compte de membres date de la ligne
        // du dessus. Sans effet dans tous les autres cas.
        await closeShareIfSeatTaken()
    }

    /// Les enregistrements `DuoMember` de la zone, avec leur référence déjà parsée.
    ///
    /// ⚠️ Cette requête suppose l'index `recordName` QUERYABLE sur `DuoMember` dans le
    /// schéma CloudKit. C'est le même pari que la requête de nettoyage du lot A1 ; à
    /// deux membres, l'alternative sans index est le `CKFetchRecordZoneChangesOperation`
    /// de la tâche des notifications, qui n'en demande aucun.
    ///
    /// `nil` sur échec, et surtout PAS une liste vide : « je n'ai pas pu lire » et « la zone
    /// est vide » mènent à des décisions opposées, l'une garde le cache et l'autre le jette.
    private func fetchMembers(
        in target: DuoDatabase.Target
    ) async -> [(reference: DuoMemberRef, record: CKRecord)]? {
        let requete = CKQuery(recordType: DuoRecord.memberType, predicate: NSPredicate(value: true))
        guard let reponse = try? await target.database.records(matching: requete,
                                                               inZoneWith: target.zoneID)
        else { return nil }

        return reponse.matchResults.compactMap { _, resultat in
            guard let record = try? resultat.get(),
                  let reference = DuoRecord.memberRef(from: record) else { return nil }
            return (reference, record)
        }
    }

    /// Les cœurs posés sur MES entrées. Le prédicat filtre déjà côté serveur, et
    /// `incomingLikes` refiltre côté client : ceinture et bretelles, comme le nettoyage du
    /// lot A1. Le nom du champ vient de `DuoRecord.Field` et non d'un littéral, sans quoi
    /// une faute de frappe rendrait une liste vide en silence.
    ///
    /// `nil` sur échec, pour la même raison que ci-dessus : un cœur reçu ne doit pas
    /// disparaître d'un journal parce que le réseau manquait à cet instant.
    private func fetchLikes(in target: DuoDatabase.Target, me: String) async -> [DuoLike]? {
        let requete = CKQuery(recordType: DuoRecord.likeType,
                              predicate: NSPredicate(format: "%K == %@",
                                                     DuoRecord.Field.ownerID, me))
        guard let reponse = try? await target.database.records(matching: requete,
                                                               inZoneWith: target.zoneID)
        else { return nil }

        return reponse.matchResults.compactMap { _, resultat in
            guard let record = try? resultat.get() else { return nil }
            return DuoRecord.like(from: record)
        }
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
