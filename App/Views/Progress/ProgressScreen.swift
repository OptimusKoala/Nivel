// App/Views/Progress/ProgressScreen.swift
// Écran Progrès (spec §4.3) : sélecteur de période, courbe de poids (points + tendance
// lissée), historique calories (barres vs objectif), historique de pas (masqué si
// HealthKit indisponible, spec §10) et bouton "+ Pesée".
// Nommé ProgressScreen (et non ProgressView) pour ne pas entrer en collision avec
// SwiftUI.ProgressView.

import SwiftUI
import SwiftData
import NivelCore

// MARK: - Période

enum ProgressPeriod: String, CaseIterable, Identifiable {
    case oneMonth = "1 mois"
    case threeMonths = "3 mois"
    case all = "Tout"

    var id: String { rawValue }

    /// Borne basse (minuit local, incluse) — nil pour "Tout".
    func startDate(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .oneMonth: return calendar.date(byAdding: .day, value: -29, to: today)
        case .threeMonths: return calendar.date(byAdding: .day, value: -89, to: today)
        case .all: return nil
        }
    }
}

// MARK: - Écran

struct ProgressScreen: View {
    @Environment(GameService.self) private var game
    @Query(sort: \WeightEntry.date) private var allWeights: [WeightEntry]
    @Query(sort: \DayLog.day) private var allDayLogs: [DayLog]
    @Query private var profiles: [UserProfile]

    @State private var period: ProgressPeriod = .oneMonth
    /// Pas par jour sur la période — nil tant que non chargé ; vide si HealthKit
    /// refusé/indisponible ou sans aucune donnée → la section Pas est masquée (spec §10).
    @State private var stepsByDay: [Date: Int]?
    @State private var showWeighIn = false

    private var profile: UserProfile? { profiles.first }

    // MARK: Données dérivées (recalculées à chaque évaluation — bornes jamais figées)

    private var periodStart: Date? {
        period.startDate(now: .now, calendar: GameService.calendar)
    }

    private var weightPoints: [(date: Date, kg: Double)] {
        allWeights
            .filter { entry in periodStart.map { entry.date >= $0 } ?? true }
            .map { ($0.date, $0.weightKg) }
    }

    /// Jours avec des kcal loggées. Le DayLog du jour est tenu à jour EN DIRECT par
    /// GameService à chaque log/édition/suppression de repas → la barre d'aujourd'hui est vivante.
    private var calorieDays: [CaloriesChart.Day] {
        let currentTarget = profile?.dailyCalorieTarget ?? 0
        return allDayLogs
            .filter { log in log.kcalEaten > 0 && (periodStart.map { log.day >= $0 } ?? true) }
            .map { log in
                CaloriesChart.Day(
                    day: log.day,
                    kcal: log.kcalEaten,
                    // Objectif du jour figé s'il existe, sinon l'objectif courant.
                    target: log.kcalTarget > 0 ? log.kcalTarget : currentTarget
                )
            }
    }

    private var stepDays: [StepsChart.Day] {
        (stepsByDay ?? [:])
            .map { StepsChart.Day(day: $0.key, steps: $0.value) }
            .sorted { $0.day < $1.day }
    }

    // MARK: Corps

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Progrès")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)

                    periodPicker
                    weightSection
                    weighInButton
                    caloriesSection
                    // Section Pas masquée si AUCUNE donnée (spec §10) : un refus HealthKit
                    // en lecture est indistinguable d'une absence de données (limitation
                    // plateforme) — le dictionnaire vide couvre les deux cas.
                    if let stepsByDay, !stepsByDay.isEmpty {
                        stepsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await loadSteps() }
        }
        .task(id: period) { await loadSteps() }
        .sheet(isPresented: $showWeighIn) {
            WeighInSheet()
                .presentationDetents([.medium])
        }
    }

    private func loadSteps() async {
        let calendar = GameService.calendar
        let now = Date.now
        // Période capturée AU DÉPART : une requête HealthKit lente dépassée par un
        // changement de période ne doit pas écraser les données de la nouvelle.
        let requested = period
        // "Tout" : depuis la création du profil (jamais distantPast — requête HealthKit bornée).
        let fallbackStart = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now))
        let start = periodStart
            ?? profile.map { calendar.startOfDay(for: $0.createdAt) }
            ?? fallbackStart
            ?? now
        let result = await game.dailySteps(from: start, to: now)
        guard requested == period, !Task.isCancelled else { return }
        stepsByDay = result
    }

    // MARK: Sections

    private var periodPicker: some View {
        Picker("Période", selection: $period) {
            ForEach(ProgressPeriod.allCases) { candidate in
                Text(candidate.rawValue).tag(candidate)
            }
        }
        .pickerStyle(.segmented)
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Poids")
                Spacer()
                if let last = allWeights.last {
                    Text("\(last.weightKg.frWeight) kg")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.orange)
                }
            }
            WeightChart(entries: weightPoints)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var weighInButton: some View {
        Button {
            showWeighIn = true
        } label: {
            Text("+ Pesée")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.orange],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
        }
        .buttonStyle(.plain)
    }

    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Calories")
            CaloriesChart(days: calorieDays, target: profile?.dailyCalorieTarget ?? 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Pas")
            StepsChart(days: stepDays)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
    }
}

// MARK: - Formatage

extension Double {
    /// "80,4" — décimale française à 1 chiffre (spec : affichage "80,4 kg").
    var frWeight: String {
        formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
    }
}

// MARK: - Previews

@MainActor
private func progressPreviewFixture(stepsAuthorized: Bool) -> (ModelContainer, GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = container.mainContext
    let calendar = GameService.calendar
    let today = calendar.startOfDay(for: .now)

    context.insert(UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 180, initialWeightKg: 91, activity: .moderate,
        dailyCalorieTarget: 2000,
        createdAt: calendar.date(byAdding: .day, value: -60, to: today)!
    ))

    // Pesées : tendance douce à la baisse avec fluctuations.
    var kg = 91.0
    for offset in stride(from: -56, through: 0, by: 4) {
        let date = calendar.date(byAdding: .day, value: offset, to: today)!
        kg += Double((offset * 13) % 7 - 3) * 0.2 - 0.15
        context.insert(WeightEntry(date: date, weightKg: kg))
    }

    // DayLogs : kcal variées autour de l'objectif.
    var steps: [Date: Int] = [:]
    for offset in -29...0 {
        let day = calendar.date(byAdding: .day, value: offset, to: today)!
        let kcal = 1600 + ((offset * 37) % 9) * 90
        context.insert(DayLog(day: day, steps: 0, kcalEaten: kcal, kcalTarget: 2000,
                              closed: offset < 0))
        steps[day] = 5000 + ((offset * 53) % 11) * 700
    }
    try? context.save()

    let fake = FakeStepsService(stepsByDay: steps, authorized: stepsAuthorized)
    return (container, GameService(modelContext: context, stepsService: fake))
}

#Preview("Progrès") {
    let (container, game) = progressPreviewFixture(stepsAuthorized: true)
    return ProgressScreen()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Sans HealthKit") {
    let (container, game) = progressPreviewFixture(stepsAuthorized: false)
    return ProgressScreen()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
