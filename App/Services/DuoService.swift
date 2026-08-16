// App/Services/DuoService.swift
// L'état observable du duo (spec 1.15 §3.6, §3.7, §3.8) : le seul objet sur lequel les
// écrans du lot A2 s'appuient. Aucune vue ne parle à CloudKit, elles parlent à celui-ci.
//
// Il lit la zone partagée, donc l'essentiel de ce fichier NE SE PROUVE PAS : ni le
// simulateur ni la CI ne savent jouer deux comptes iCloud. La parade est la même qu'au
// lot A1 et qu'en v1 avec `HomeView.bubbleDecision` : **toute décision est extraite en
// statique pure**, éprouvée par un test, et le reste est de la plomberie mince, écrite
// sans astuce. Quatre décisions vivent ici :
//
// 1. qui est mon partenaire parmi les membres de la zone (§3.6) ;
// 2. le partage doit-il rester ouvert (§3.6) ;
// 3. quels cœurs me visent (§3.7) ;
// 4. ce texte scanné est-il une invitation (§3.6).
//
// Ce que ce fichier ne fait PAS, et qui viendra dans les tâches suivantes du lot : créer
// la zone et le `CKShare`, accepter une invitation, poser l'abonnement de zone, envoyer
// ou retirer un cœur. Il lit, il range, il décide.

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
         }) {
        self.identity = identity
        self.resolveTarget = resolveTarget
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
