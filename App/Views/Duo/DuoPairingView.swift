// App/Views/Duo/DuoPairingView.swift
// Les deux moitiés de l'appairage (spec 1.15 §3.6) : `DuoPairingView` invite et montre son
// QR code, `DuoJoinView` scanne celui d'en face ou accepte un lien collé.
//
// Ces écrans ne parlent JAMAIS à CloudKit. Ils demandent à `DuoService`, qui rend soit une
// URL, soit une phrase à afficher. C'est la règle du lot : les vues ne connaissent pas le
// nuage, et une erreur d'appairage se raconte ici même, jamais en alerte modale par-dessus
// l'accueil.

import SwiftData
import SwiftUI
import VisionKit
import NivelCore

struct DuoPairingView: View {
    @Environment(DuoService.self) private var duo
    @Environment(GameService.self) private var game

    /// `nil` tant que la création est en cours : c'est le seul état qui n'est ni une URL ni
    /// un message, et il mérite son indicateur d'attente plutôt qu'un carré vide.
    @State private var resultat: DuoService.InvitationResult?
    /// La place est prise. L'écran cesse alors de montrer un code qui ne vaut plus rien.
    @State private var partenaireArrive = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Inviter")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    carteDuCode
                    carteDExplication
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        // `.task` et non `.onAppear` : la création est asynchrone, et `.task` l'annule si
        // l'écran se ferme entre-temps. Idempotente côté service, donc une réouverture
        // réaffiche le même QR sans rien recréer.
        .task {
            await creer()
            await attendreLePartenaire()
        }
    }

    // MARK: - Le code

    @ViewBuilder
    private var carteDuCode: some View {
        VStack(spacing: 14) {
            switch resultat {
            case .ready where partenaireArrive:
                Text("C'est fait, vous êtes appairés 💛")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Le lien vient de se refermer : la place est prise.")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)

            case .ready(let url):
                qr(for: url)
                ShareLink(item: url) {
                    Text("Partager le lien")
                }
                .buttonStyle(SecondaryButtonStyle())

            case .failed(let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
                Button("Réessayer") {
                    resultat = nil
                    Task { await creer() }
                }
                .buttonStyle(PrimaryButtonStyle())

            case nil:
                ProgressView()
                    .controlSize(.large)
                    .frame(height: DuoQRCode.side)
                    .accessibilityLabel("Création du duo en cours")
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    @ViewBuilder
    private func qr(for url: URL) -> some View {
        if let image = DuoQRCode.image(from: url.absoluteString) {
            Image(uiImage: image)
                .resizable()
                // Sans quoi l'agrandissement d'affichage relisse les modules du code et
                // rend le carré illisible pour la caméra d'en face.
                .interpolation(.none)
                .scaledToFit()
                .frame(width: DuoQRCode.side, height: DuoQRCode.side)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                // L'information n'est pas dans l'image pour qui ne voit pas : elle est dans
                // le bouton juste en dessous, et le libellé le dit.
                .accessibilityLabel("QR code de l'invitation, à scanner par l'autre iPhone")
        }
    }

    // MARK: - Ce que l'écran promet

    private var carteDExplication: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Comment ça marche")
            Text("Sur l'autre iPhone, ouvre Nivel, va dans les réglages et choisis Rejoindre, puis scanne ce code.")
                .font(.subheadline)
            Rectangle().fill(Theme.track).frame(height: 1)
            // Le §3.6 exige que l'écran le dise : le partage se referme dès qu'un second
            // membre apparaît. Quelqu'un qui garde ce QR en capture d'écran croirait
            // pouvoir s'en resservir, et il n'aurait aucun moyen de comprendre le refus.
            Text("Ce code ne vaut que le temps de l'appairage. Dès que ton duo l'a scanné, le lien se referme et ne sert plus à personne.")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Actions

    private func creer() async {
        // Rejouer la création à chaque apparition serait sans danger (le service est
        // idempotent) mais inutile : une URL déjà affichée reste bonne.
        guard resultat == nil else { return }
        let issue = await duo.startInvitation()
        resultat = issue

        // Écrire son propre instantané tout de suite : c'est ce qui donne quelque chose à
        // afficher au partenaire dès qu'il rejoint, au lieu d'une page vide jusqu'au
        // prochain repas. `publishDuo` est fire and forget et ne rend rien.
        if case .ready = issue { game.publishDuo() }
    }

    /// Guette l'arrivée du partenaire tant que le QR est à l'écran.
    ///
    /// C'est le seul moment de la vie de l'app où l'on interroge iCloud en boucle, et il se
    /// justifie : les deux téléphones sont côte à côte, l'un vient de scanner, et c'est
    /// exactement là qu'il faut le dire. `refresh()` referme le partage au passage (§3.6),
    /// donc l'attente n'est pas décorative : c'est elle qui claque la porte.
    ///
    /// La boucle meurt avec l'écran, `.task` annulant sa tâche à la disparition.
    private func attendreLePartenaire() async {
        guard case .ready = resultat else { return }

        while !Task.isCancelled && !partenaireArrive {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await duo.refresh()
            if let compte = duo.memberCount,
               !DuoService.shouldKeepShareOpen(memberCount: compte) {
                partenaireArrive = true
            }
        }
    }
}

// MARK: - Rejoindre

/// L'autre moitié de l'appairage : scanner le QR d'en face, ou coller son lien.
///
/// **Le champ de saisie est TOUJOURS là**, même quand la caméra fonctionne. Il n'est pas
/// un mode dégradé mais un chemin normal : on n'est pas forcément dans la même pièce, et
/// c'est aussi lui qui reste quand la caméra est refusée (§3.10). Jamais d'impasse.
struct DuoJoinView: View {
    @Environment(DuoService.self) private var duo
    @Environment(GameService.self) private var game

    @State private var lien = ""
    /// Le message d'un refus, affiché sur place. Jamais une alerte modale.
    @State private var message: String?
    @State private var enCours = false
    @State private var appaire = false

    /// Montrer le scanner, ou seulement le champ. Décision pure : elle se teste, alors que
    /// `DataScannerViewController` ne se joue ni au simulateur ni en test.
    ///
    /// `isSupported` est faux sur un appareil sans caméra Neural Engine et au simulateur ;
    /// `isAvailable` devient faux quand la caméra est refusée. Les deux mènent au même
    /// endroit, qui n'est pas une impasse.
    static func showsScanner(isSupported: Bool, isAvailable: Bool) -> Bool {
        isSupported && isAvailable
    }

    private var scannerVisible: Bool {
        Self.showsScanner(isSupported: DataScannerViewController.isSupported,
                          isAvailable: DataScannerViewController.isAvailable)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rejoindre")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    if appaire {
                        carteDeSucces
                    } else {
                        if scannerVisible { carteDuScanner }
                        carteDuLien
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Les cartes

    private var carteDuScanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Scanner")
            DuoScannerView { contenu in
                Task { await rejoindre(contenu) }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Viseur de la caméra, à pointer sur le QR code de l'autre iPhone")
            Text("Vise le QR code affiché sur l'autre iPhone.")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var carteDuLien: some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(scannerVisible ? "Ou coller le lien" : "Coller le lien")
            TextField("https://www.icloud.com/share/…", text: $lien, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(1...3)
                .font(.subheadline)
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))

            if let message {
                // Pas de rouge : la règle fondatrice vaut aussi pour les refus, qui ne sont
                // la faute de personne.
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.subtext)
            }

            Button("Rejoindre le duo") {
                Task { await rejoindre(lien) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(enCours)

            Text("Le lien s'accepte ici. Ouvert depuis Messages, il proposera d'ouvrir Nivel sans rien appairer.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var carteDeSucces: some View {
        VStack(spacing: 10) {
            Text("C'est fait, vous êtes appairés 💛")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Ta journée part vers l'autre iPhone, et la sienne arrive ici.")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Actions

    private func rejoindre(_ texte: String) async {
        // Le scanner peut lire deux fois pendant qu'une acceptation est en vol, et le
        // bouton peut être tapé pendant ce temps : une seule acceptation à la fois.
        guard !enCours, !appaire else { return }
        enCours = true
        defer { enCours = false }

        switch await duo.join(shareURL: texte) {
        case .joined:
            message = nil
            appaire = true
            // C'est cette écriture qui fait apparaître le duo chez le propriétaire (§3.6) :
            // tant que l'invité n'a pas publié son `DuoMember`, l'autre ne voit personne.
            game.publishDuo()
            await duo.refresh()

        case .failed(let texte):
            message = texte
        }
    }
}

#Preview {
    // Domaine de réglages dédié et magasin en mémoire : une prévisualisation n'appaire
    // rien pour de vrai et n'écrit pas dans les réglages de l'app.
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)])
    let identite = DuoIdentity(defaults: UserDefaults(suiteName: "nivel.preview.duo") ?? .standard)

    return DuoPairingView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(DuoService(identity: identite, resolveTarget: { _ in nil }))
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
