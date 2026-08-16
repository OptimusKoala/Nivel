// App/Views/Settings/SettingsView+Duo.swift
// Section « Duo » des réglages (spec 1.15 §3.9, §3.10) : l'état courant, inviter,
// rejoindre, l'annonce des cœurs, et le désappairage.
//
// C'est le SEUL chemin de l'app qui mène au duo, par décision du §3.11 : rien sur l'accueil
// tant qu'aucun duo n'existe, donc aucune découverte imposée à qui n'en veut pas.
//
// Le ton suit la règle fondatrice de la v1. Pas de compte iCloud n'est pas une faute de
// l'utilisateur, c'est un fait qu'on explique en disant où aller le régler ; une zone
// disparue n'est pas une panne à annoncer mais un duo à refaire. Aucun rouge, aucun
// reproche, et les quatre libellés sont éprouvés au mot près.

import SwiftUI
import UIKit
import UserNotifications
import NivelCore

/// Les quatre états de la section, et rien d'autre : un état de plus serait un état qu'aucun
/// libellé ne nomme.
enum DuoSettingsState: Equatable {
    /// Pas de compte iCloud sur cet appareil. Prime sur tout le reste : sans lui, rien du
    /// duo ne peut fonctionner, pas même afficher le cache.
    case noAccount
    /// Aucun duo appairé. L'état de tout le monde avant la 1.15, et de qui n'en veut pas.
    case unpaired
    /// Appairé. `name` reste optionnel : entre l'acceptation du partage et la première
    /// publication de l'autre, on est appairé sans savoir encore avec qui.
    case paired(name: String?, since: Date?)
    /// La place est PRISE — la zone porte bien deux membres — mais rien de lisible n'est
    /// arrivé de l'autre. Distinct de l'attente ordinaire, et sans délai inventé : c'est le
    /// compte de membres qui tranche, et il est déjà lu à chaque rafraîchissement.
    case partnerSilent(since: Date?)
    /// La zone n'existe plus en face. L'état local dit encore « appairé », et c'est
    /// justement le moment de proposer de recommencer.
    case zoneGone

    /// L'état, à partir de ce qu'on sait. **L'ordre des cas est la décision** : le compte
    /// d'abord, la zone ensuite, l'appairage local en dernier — du plus fondamental au plus
    /// local. Le tester à l'envers afficherait « appairé avec Marion » à quelqu'un qui n'a
    /// plus de compte iCloud, donc plus rien du tout.
    static func current(hasAccount: Bool, isPaired: Bool, zoneIsGone: Bool,
                        partnerName: String?, pairedAt: Date?,
                        memberCount: Int? = nil) -> DuoSettingsState {
        guard hasAccount else { return .noAccount }
        // La zone perdue passe AVANT l'appairage local, dans les deux sens : quand il vaut
        // encore vrai (l'état d'appareil n'a pas encore été effacé) comme quand il vient de
        // tomber (le service s'est désappairé en constatant la perte). Sans cette place,
        // l'écran retomberait sur le muet « aucun duo » à l'instant précis où il a quelque
        // chose à expliquer.
        guard !zoneIsGone else { return .zoneGone }
        guard isPaired else { return .unpaired }
        // Personne de nommé, mais la place est prise : quelqu'un a bien rejoint et quelque
        // chose n'est pas passé. On le dit autrement que l'attente des premières secondes,
        // sans inventer de délai — c'est le compte de membres qui fait la différence, et il
        // vient de la dernière lecture réussie.
        if partnerName == nil, let memberCount, !DuoService.seatIsFree(memberCount: memberCount) {
            return .partnerSilent(since: pairedAt)
        }
        return .paired(name: partnerName, since: pairedAt)
    }

    /// La phrase d'état. Une seule par cas, et jamais un mot de reproche : celui qui la lit
    /// n'est responsable d'aucune de ces situations.
    static func label(for state: DuoSettingsState) -> String {
        switch state {
        case .noAccount:
            return "Connecte-toi à iCloud pour créer un duo"
        case .unpaired:
            return "Aucun duo pour l'instant"
        case .zoneGone:
            return "Ce duo n'existe plus, tu peux en créer un nouveau"
        case .partnerSilent(let since):
            let depuis = since.map { " depuis le \(frDate($0))" } ?? ""
            return "Ton duo a rejoint\(depuis), sa journée n'est pas encore arrivée"
        case .paired(let name, let since):
            let depuis = since.map { " depuis le \(frDate($0))" } ?? ""
            // Sans nom, on ne laisse surtout pas un blanc : on dit l'attente, qui est la
            // vérité de cet instant.
            guard let name else { return "Appairé\(depuis), en attente de l'autre iPhone" }
            return "Appairé avec \(name)\(depuis)"
        }
    }

    /// « 16 août 2026 ». Formateur en français explicite : la date d'appairage est affichée
    /// dans une phrase française, pas dans la langue du système, et un test l'épingle au mot.
    private static func frDate(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.dateFormat = "d MMMM yyyy"
        return format.string(from: date)
    }
}

/// Ce que la ligne « Cœurs reçus » a le droit d'afficher.
///
/// L'interrupteur seul MENTAIT. L'autorisation système des notifications n'est demandée
/// qu'une fois, à l'onboarding, et il n'existe aucun autre chemin pour l'accorder : qui a
/// refusé ce jour-là ne recevait plus jamais rien, avec un interrupteur allumé sous les yeux
/// et `DuoNotifications.post` qui sortait en silence.
///
/// Deux cas et pas trois : quand le système dit non, ce que vaut le réglage de l'app n'a
/// aucune importance, et prétendre le contraire est exactement l'erreur qu'on répare.
enum DuoLikeNoticeRow: Equatable {
    /// Le système laisse passer : l'interrupteur dit vrai, on le montre.
    case toggle
    /// Le système ne laisse rien passer. On explique, et on ouvre la porte.
    case systemOff

    /// **La même règle que `DuoNotifications.post`**, consultée à la source plutôt que
    /// recopiée : c'est leur divergence qui a fait le défaut, pas l'une ou l'autre.
    static func current(status: UNAuthorizationStatus) -> DuoLikeNoticeRow {
        DuoNotifications.systemAllows(status) ? .toggle : .systemOff
    }

    /// Ce qu'on dit quand le système ne laisse rien passer.
    ///
    /// Le ton est celui de « pas de compte iCloud », juste au-dessus dans le même écran, et
    /// pour la même raison : ce n'est pas une erreur de l'utilisateur, c'est un réglage à
    /// connaître. On explique, on dit ce qui continue de marcher, et on ouvre la porte.
    /// Aucun rouge, aucun reproche, aucune alerte.
    static let systemOffLabel =
        "Les notifications de Nivel sont désactivées dans les réglages de l'iPhone."

    /// Ce qui continue de marcher, et c'est vrai : un cœur reçu se range et s'affiche, seule
    /// l'annonce se tait. Le dire évite de laisser croire qu'on perd quelque chose.
    static let systemOffDetail =
        "Les cœurs de ton duo arrivent quand même, tu les retrouves sur tes repas, tes activités et sur l'accueil."
}

/// Les deux feuilles d'appairage, ouvertes depuis cette section et de nulle part ailleurs.
enum DuoPairingSheet: String, Identifiable {
    case invite, join
    var id: String { rawValue }
}

extension SettingsContent {

    // MARK: - Duo

    var duoSection: some View {
        section("Duo") {
            Text(DuoSettingsState.label(for: duoState))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch duoState {
            case .noAccount:
                Text("Le duo passe par ta zone iCloud personnelle : rien ne part sur un serveur de Nivel.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

            case .unpaired, .zoneGone:
                divider
                boutonsDAppairage

            case .paired, .partnerSilent:
                divider
                interrupteurDesCoeurs
                divider
                boutonDeDesappairage
            }
        }
        .sheet(item: $duoSheet) { feuille in
            switch feuille {
            case .invite: DuoPairingView()
            case .join: DuoJoinView()
            }
        }
        // Les deux états système se demandent au système, donc en asynchrone. Optimistes par
        // défaut (`duoHasICloudAccount` naît à `true`, `duoNoticeStatus` à `.authorized`) :
        // afficher « connecte-toi à iCloud » ou « les notifications sont désactivées »
        // pendant la fraction de seconde de la réponse serait un mensonge clignotant.
        .task {
            duoHasICloudAccount = await duo.accountIsAvailable()
            duoNoticeStatus = await DuoNotifications.systemStatus()
            // Relire la zone en ouvrant les réglages, et c'est le seul crochet de
            // rafraîchissement du dépôt tant que l'accueil n'en a pas (tâche à venir) :
            // sans lui, un invité resterait indéfiniment « en attente de l'autre iPhone »
            // alors que le partenaire a publié depuis longtemps. Sans duo appairé, l'appel
            // sort à sa première ligne et n'émet rien (§3.1).
            await duo.refresh()
        }
        // Le retour des réglages système. C'est la moitié qui manquerait sans quoi : on
        // propose d'aller accorder l'autorisation, la personne le fait, revient, et
        // trouverait le même message qu'avant son départ. `.task` ne rejoue pas, la vue
        // n'ayant jamais disparu.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { duoNoticeStatus = await DuoNotifications.systemStatus() }
        }
    }

    private var duoState: DuoSettingsState {
        DuoSettingsState.current(hasAccount: duoHasICloudAccount,
                                 isPaired: duo.isPaired,
                                 zoneIsGone: duo.zoneIsGone,
                                 partnerName: duo.partnerSnapshot?.name,
                                 pairedAt: duo.pairedAt,
                                 memberCount: duo.memberCount)
    }

    private var boutonsDAppairage: some View {
        VStack(spacing: 10) {
            Button("Inviter") { duoSheet = .invite }
                .buttonStyle(PrimaryButtonStyle())
            Button("Rejoindre") { duoSheet = .join }
                .buttonStyle(SecondaryButtonStyle())
            Text("Un seul partenaire à la fois. Vous voyez chacun la journée de l'autre : les repas, les activités, l'anneau du jour. Jamais le poids.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var interrupteurDesCoeurs: some View {
        switch DuoLikeNoticeRow.current(status: duoNoticeStatus) {
        case .toggle:
            Toggle(isOn: coeursBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cœurs reçus").font(.subheadline.weight(.semibold))
                    Text("être prévenu quand ton duo aime un repas ou une activité")
                        .font(.caption).foregroundStyle(Theme.subtext)
                }
            }

        case .systemOff:
            // Pas d'interrupteur du tout : en montrer un désactivé laisserait croire que le
            // réglage de l'app y est pour quelque chose, alors que rien de ce qu'on peut
            // toucher ici ne changera quoi que ce soit.
            VStack(alignment: .leading, spacing: 8) {
                Text("Cœurs reçus").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(DuoLikeNoticeRow.systemOffLabel)
                    .font(.caption).foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(DuoLikeNoticeRow.systemOffDetail)
                    .font(.caption).foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// Binding fait à la main : la valeur vit dans `DuoIdentity`, que seul le service touche.
    private var coeursBinding: Binding<Bool> {
        Binding(get: { duo.likeNotificationsEnabled },
                set: { duo.likeNotificationsEnabled = $0 })
    }

    private var boutonDeDesappairage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Défaire le duo") { duoConfirmingUnpair = true }
                .buttonStyle(SecondaryButtonStyle())
            Text("Les cœurs déjà reçus restent sur tes repas et tes activités.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        // Une confirmation, parce que le geste est irréversible côté nuage. SANS rôle
        // `.destructive`, qui peindrait le bouton en rouge : la règle « jamais de rouge »
        // de la v1 tient jusqu'ici, et « Défaire le duo » est assez clair sans couleur.
        .confirmationDialog("Défaire le duo ?", isPresented: $duoConfirmingUnpair,
                            titleVisibility: .visible) {
            Button("Défaire le duo") { Task { await duo.unpair() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vous cesserez de voir vos journées. Tu pourras en refaire un quand tu veux.")
        }
    }
}
