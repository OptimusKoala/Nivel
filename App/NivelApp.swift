// App/NivelApp.swift
import SwiftUI
import SwiftData

@main
struct NivelApp: App {
    private let container: ModelContainer
    /// Instance UNIQUE partagée par toute l'app (la file des célébrations vit dedans).
    @State private var gameService: GameService

    init() {
        #if DEBUG
        // Captures App Store (scripts/screenshots.sh) : store en mémoire garni d'un
        // profil de démo et pas simulés. Absent du binaire de release.
        if ScreenshotMode.isEnabled {
            let container = ScreenshotMode.makeContainer()
            ScreenshotMode.seed(into: container.mainContext)
            self.container = container
            _gameService = State(initialValue: GameService(
                modelContext: container.mainContext,
                stepsService: ScreenshotMode.makeStepsService(),
                widgetDefaults: nil
            ))
            return
        }
        #endif

        // `cloudKitDatabase: .none` est OBLIGATOIRE depuis la 1.15, et ce n'est pas une
        // précaution : c'est ce qui empêche l'app de planter au lancement.
        //
        // La valeur par défaut est `.automatic`, qui veut dire « miroite si l'app a
        // l'entitlement iCloud ». Tant que Nivel n'avait pas cet entitlement, le défaut
        // ne faisait rien. En l'ajoutant pour le duo, il s'est mis à vouloir miroiter
        // TOUT le magasin — et CloudKit exige que chaque attribut soit optionnel ou
        // porte un défaut, ce que ce schéma ne respecte pas. Mesuré : le store ne
        // charge plus, `try!` lève, l'app meurt au démarrage.
        //
        // C'est précisément ce que la spec 1.15 §3.2 refuse : le magasin local reste la
        // seule source de vérité, on ne miroite RIEN, et le duo passe par une zone
        // partagée où l'app publie un petit instantané. Le §11 de la 1.14 l'avait déjà
        // établi pour une autre raison, toujours valable : `DayLog.day` porte un
        // `@Attribute(.unique)`, que CloudKit interdit.
        //
        // `groupContainer` reste implicite (`.automatic`) : le magasin vit dans l'App
        // Group depuis la v1.6, et le nommer autrement déplacerait le fichier, donc
        // perdrait les données déjà là.
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)])
        self.container = container
        _gameService = State(initialValue: GameService(
            modelContext: container.mainContext,
            stepsService: HealthKitService(),
            // Le SEUL endroit du dépôt qui convoque le singleton. Partout ailleurs il est
            // injecté, et `nil` en test : c'est ce qui garantit qu'aucune suite n'écrit
            // dans les vrais réglages.
            duoIdentity: .shared
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .modelContainer(container)
                .environment(gameService)
        }
    }
}
