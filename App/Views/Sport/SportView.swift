// App/Views/Sport/SportView.swift
// Onglet Sport (spec sport §8.3) : séance du jour, catalogue Maison/Dehors/Ça pousse
// (les sections viennent de `SportSection`, spec v1.14 §4.3),
// « Fait aujourd'hui » (swipe = supprimer, jour même par construction).

import SwiftUI
import SwiftData
import NivelCore

struct SportView: View {
    @Environment(GameService.self) private var game

    @State private var sessionStatus: (session: ActivitySession, done: Bool)?
    @State private var todayEntries: [ActivityEntry] = []
    @State private var selectedActivity: Activity?
    @State private var showSessionPlayer = false
    // Section Posture (spec v1.11 §9) : état séparé de la séance du jour, la
    // sheet du player reçoit `kind: .posture` pour savoir laquelle des trois logger.
    @State private var postureSessionStatus: (session: ActivitySession, done: Bool)?
    @State private var showPostureSessionPlayer = false
    // Section Muscu (spec v1.14 §4.4) : troisième état de séance, même mécanique.
    @State private var muscuSessionStatus: (session: ActivitySession, done: Bool)?
    @State private var showMuscuSessionPlayer = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            sportList
        }
        // reload() est synchrone : onAppear suffit (couvre 1ᵉʳ affichage ET retours d'onglet).
        .onAppear {
            reload()
            #if DEBUG
            // Capture « séance guidée » (scripts/screenshots.sh) : absent en release.
            if ScreenshotMode.autoOpensDailySession { showSessionPlayer = true }
            #endif
        }
        .sheet(isPresented: $showSessionPlayer, onDismiss: reload) {
            if let status = sessionStatus {
                SessionPlayerSheet(session: status.session, done: status.done, kind: .dailySession,
                                   initialPage: Self.playerInitialPage)
            }
        }
        .sheet(isPresented: $showPostureSessionPlayer, onDismiss: reload) {
            if let status = postureSessionStatus {
                SessionPlayerSheet(session: status.session, done: status.done, kind: .posture)
            }
        }
        .sheet(isPresented: $showMuscuSessionPlayer, onDismiss: reload) {
            if let status = muscuSessionStatus {
                SessionPlayerSheet(session: status.session, done: status.done, kind: .muscu)
            }
        }
        .sheet(item: $selectedActivity, onDismiss: reload) { activity in
            ActivityLogSheet(activity: activity)
        }
    }

    /// La liste, et — en DEBUG SEULEMENT — de quoi l'ouvrir sur une section donnée
    /// pour la capture App Store (`ScreenshotMode.initialSportSection`). Ni le lecteur
    /// de défilement ni la zone sûre rendue à la liste n'existent chez Apple.
    @ViewBuilder
    private var sportList: some View {
        #if DEBUG
        ScrollViewReader { proxy in
            list
                // La zone sûre du haut, RENDUE à la liste. `scrollTo` aligne la vue
                // visée sur le haut de cette zone-là : sans cet ajout, elle l'aligne
                // sur le bord de l'écran et l'en-tête se retrouve à cheval sur
                // « 9 h 41 ». Transparente, et surtout PAS peinte : une bande opaque
                // se dessine PAR-DESSUS la liste, elle recouvrirait le titre qu'on
                // vient d'y amener. Hauteur nulle hors capture Sport : écran intact.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: screenshotTopInset)
                }
                .onAppear { scrollToScreenshotSection(proxy) }
        }
        #else
        list
        #endif
    }

    /// Blanc AJOUTÉ au-dessus de l'en-tête visé, et de lui seul (zéro partout ailleurs,
    /// zéro hors mode captures).
    ///
    /// Il ne se voit pas : `scrollTo` alignant le TITRE, tout ce qui le précède part
    /// au-dessus de l'écran. C'est justement son rôle — sans lui, la fin de la section
    /// « Dehors » dépasse encore derrière l'heure. DEUX hauteurs de barre d'état : la
    /// première rend celle que la liste avait reprise, la seconde emporte l'espacement
    /// entre deux sections et le coin arrondi de la carte précédente, qui affleurait
    /// encore de six points tout en haut de l'image.
    private func headerCushion(for section: SportSection) -> CGFloat {
        #if DEBUG
        section == ScreenshotMode.initialSportSection ? 2 * ScreenshotMode.scrolledHeaderCushion : 0
        #else
        0
        #endif
    }

    #if DEBUG
    /// Hauteur de la zone sûre rendue à la liste — nulle si aucune section n'est visée.
    private var screenshotTopInset: CGFloat {
        ScreenshotMode.initialSportSection == nil ? 0 : ScreenshotMode.scrolledHeaderCushion
    }

    /// Défilement d'ouverture du mode captures, APRÈS le premier `reload()`.
    ///
    /// `DispatchQueue.main.async` et non un appel direct : ce `onAppear`-ci est celui de
    /// la liste, il précède donc celui du `ZStack`, où `reload()` fait apparaître la
    /// carte de la séance du jour AU-DESSUS de la section visée. Défiler avant elle
    /// laisserait le cadrage descendre d'une carte au moment où elle s'insère.
    private func scrollToScreenshotSection(_ proxy: ScrollViewProxy) {
        guard let section = ScreenshotMode.initialSportSection else { return }
        DispatchQueue.main.async { proxy.scrollTo(section, anchor: .top) }
    }
    #endif

    private var list: some View {
        List {
            // En tête, avant la séance du jour (spec v1.11 §9) : auto-cloisonnée,
            // invisible sur le téléphone où l'interrupteur est éteint.
            PostureSection(
                sessionStatus: postureSessionStatus,
                monthCount: game.postureSessionsThisMonth(),
                activities: game.postureCatalog.activities,
                onOpenSession: { showPostureSessionPlayer = true },
                onSelectActivity: { selectedActivity = $0 }
            )

            Section {
                if let status = sessionStatus {
                    Button { showSessionPlayer = true } label: {
                        DailySessionCardContent(session: status.session,
                                                kcal: game.sessionKcal(status.session),
                                                done: status.done)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            } header: { header }

            // APRÈS la séance du jour, avant les sections d'activités (spec v1.14
            // §4.4) : la posture reste en tête, c'est le programme de Marion.
            // Auto-cloisonnée, comme PostureSection.
            MuscuSection(
                sessionStatus: muscuSessionStatus,
                monthCount: game.muscuSessionsThisMonth(),
                onOpenSession: { showMuscuSessionPlayer = true }
            )

            // Sections, ordre, libellés et icônes viennent tous de `SportSection` :
            // rien ici ne peut diverger d'ActivityPickerSheet, pas même par omission.
            ForEach(SportSection.displayOrder, id: \.self) { section in
                activitySection(section)
            }

            if !todayEntries.isEmpty {
                Section {
                    ForEach(todayEntries) { entry in
                        doneRow(entry)
                    }
                } header: {
                    Overline("Fait aujourd'hui")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// Page du lecteur à l'ouverture : l'aperçu, sauf en mode captures (DEBUG) où le
    /// script peut demander directement la première étape guidée.
    private static var playerInitialPage: Int {
        #if DEBUG
        return ScreenshotMode.isEnabled ? ScreenshotMode.sessionInitialPage : 0
        #else
        return 0
        #endif
    }

    private func reload() {
        sessionStatus = game.dailySessionStatus()
        postureSessionStatus = game.postureSessionStatus()
        muscuSessionStatus = game.muscuSessionStatus()
        todayEntries = game.todayActivities()
    }

    private var header: some View {
        Text("Sport")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
    }

    private func activitySection(_ section: SportSection) -> some View {
        Section {
            // Ligne partagée avec ActivityPickerSheet (v1.13) : les deux listes des
            // mêmes activités ne doivent pas pouvoir diverger.
            ForEach(section.activities(in: game.activityCatalog)) { activity in
                ActivityRow(activity: activity) { selectedActivity = activity }
            }
        } header: {
            // L'identité EST le cas de `SportSection` : c'est elle que vise le
            // défilement d'ouverture du mode captures, posée sur l'en-tête pour que
            // « aller à la section » veuille dire « son titre en haut de l'écran ».
            // Le coussin (nul hors mode captures, et hors de la section visée) tient
            // ce titre sous la barre d'état — voir `scrolledHeaderCushion`.
            Overline(section.frLabel, icon: section.icon)
                .padding(.top, headerCushion(for: section))
                .id(section)
        }
    }

    private func doneRow(_ entry: ActivityEntry) -> some View {
        let name: String = {
            switch entry.kind {
            case .activity:
                return game.activitiesByID[entry.refID]?.name ?? entry.refID
            case .dailySession:
                return game.sessionCatalog.first { $0.id == entry.refID }?.title ?? entry.refID
            case .posture:
                // Une entrée posture porte un id de SÉANCE, comme .dailySession, et non
                // un id d'exercice : `logPostureSession` est le miroir de
                // `logDailySession`. Chercher dans le catalogue d'exercices retomberait
                // silencieusement sur l'id brut (« posture_evening ») dans la liste du jour.
                return game.postureCatalog.sessions.first { $0.id == entry.refID }?.title
                    ?? game.activitiesByID[entry.refID]?.name
                    ?? entry.refID
            case .muscu:
                // Même piège que .posture — un id de SÉANCE, jamais d'exercice — mais
                // SANS le repli par `activitiesByID` : le programme muscu n'a pas
                // d'exercices à lui, aucun id `muscu_*` n'existe dans cette table, et
                // le maillon serait donc du code mort qui retomberait toujours sur l'id brut.
                return game.muscuCatalog.sessions.first { $0.id == entry.refID }?.title ?? entry.refID
            }
        }()
        return HStack(spacing: 12) {
            SportIllustration(name: entry.refID)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("\(entry.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
            Text("~\(entry.estimatedKcal.frFormatted) kcal")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.orange)
        }
        .listRowBackground(Theme.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task {
                    await game.deleteActivity(entry: entry)
                    reload()
                }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .tint(Theme.accent)   // accent, pas rouge (spec v1 §7.4)
        }
    }
}

// MARK: - Previews

@MainActor
private func sportPreviewFixture() -> (container: ModelContainer, game: GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = container.mainContext

    context.insert(UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 180, initialWeightKg: 90, activity: .moderate,
        dailyCalorieTarget: 2000
    ))

    // Deux entrées du jour pour peupler « Fait aujourd'hui » ET l'état ✓ de la
    // carte séance (même session que la rotation du jour, spec sport §3.3).
    context.insert(ActivityEntry(kind: .activity, refID: "walk", durationMinutes: 20,
                                 estimatedKcal: 80, xpAwarded: 30))
    let sessions = (try? Catalogs.sessions()) ?? []
    if let todaySession = DailySessionPicker.session(for: .now, sessions: sessions,
                                                     calendar: GameService.calendar) {
        context.insert(ActivityEntry(kind: .dailySession, refID: todaySession.id,
                                     durationMinutes: todaySession.totalMinutes,
                                     estimatedKcal: 120, xpAwarded: 40))
    }
    try? context.save()

    let fake = FakeStepsService()
    return (container, GameService(modelContext: context, stepsService: fake, widgetDefaults: nil))
}

#Preview("Sport") {
    let (container, game) = sportPreviewFixture()
    SportView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
