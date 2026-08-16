// App/Views/Duo/DuoPairingView.swift
// L'invitation : créer le duo et montrer son QR code (spec 1.15 §3.6).
//
// Cet écran ne parle JAMAIS à CloudKit. Il demande à `DuoService`, qui rend soit une URL,
// soit une phrase à afficher. C'est la règle du lot : les vues ne connaissent pas le nuage,
// et une erreur d'appairage se raconte ici même, jamais en alerte modale par-dessus
// l'accueil.

import SwiftData
import SwiftUI
import NivelCore

struct DuoPairingView: View {
    @Environment(DuoService.self) private var duo
    @Environment(GameService.self) private var game

    /// `nil` tant que la création est en cours : c'est le seul état qui n'est ni une URL ni
    /// un message, et il mérite son indicateur d'attente plutôt qu'un carré vide.
    @State private var resultat: DuoService.InvitationResult?

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
        .task { await creer() }
    }

    // MARK: - Le code

    @ViewBuilder
    private var carteDuCode: some View {
        VStack(spacing: 14) {
            switch resultat {
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
