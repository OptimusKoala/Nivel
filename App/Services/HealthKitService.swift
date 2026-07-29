// App/Services/HealthKitService.swift
import Foundation
import HealthKit

/// Abstraction testable de la lecture des pas (spec §11) :
/// la logique métier ne touche jamais HealthKit directement.
protocol StepsProviding {
    var isAvailable: Bool { get }
    func requestAuthorization() async -> Bool
    /// Pas du jour donné — nil si refusé/indisponible ou erreur de requête.
    func steps(on day: Date) async -> Int?
    /// Pas par jour (clé = minuit local) sur l'intervalle [from, to[ — borne haute exclusive.
    /// nil = indisponible/refusé OU erreur de requête ; `[:]` = requête réussie mais
    /// aucun pas enregistré. La distinction compte : la clôture des journées
    /// (DayCloser.swift) ne doit JAMAIS figer un 0 sur une erreur transitoire.
    func dailySteps(from: Date, to: Date) async -> [Date: Int]?
}

/// Implémentation HealthKit — HKStatisticsCollectionQuery quotidienne,
/// .cumulativeSum sur stepCount.
///
/// ⚠️ Limitation HealthKit : pour les autorisations en LECTURE, l'API ne révèle
/// jamais si l'utilisateur a accepté ou refusé (confidentialité) — un refus est
/// indistinguable d'une absence de données. On approxime donc "autorisé" par un
/// drapeau UserDefaults posé quand `requestAuthorization()` aboutit sans erreur
/// (best-effort : le drapeau signifie "la demande a été présentée", pas "accordé").
/// Un utilisateur ayant refusé verra simplement des compteurs à 0.
final class HealthKitService: StepsProviding {
    private static let didRequestKey = "nivel.healthkit.didRequestAuthorization"

    private let store = HKHealthStore()
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable() && defaults.bool(forKey: Self.didRequestKey)
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount)])
            defaults.set(true, forKey: Self.didRequestKey)
            return true
        } catch {
            return false
        }
    }

    func steps(on day: Date) async -> Int? {
        guard isAvailable else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        guard let byDay = await dailySteps(from: start, to: end) else { return nil }
        return byDay[start] ?? 0
    }

    func dailySteps(from: Date, to: Date) async -> [Date: Int]? {
        guard isAvailable else { return nil }
        let anchor = calendar.startOfDay(for: from)
        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: to, options: .strictStartDate)
        let calendar = self.calendar

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                // Échec de requête (dont refus) → nil : distinct de "aucun pas",
                // pour que rien ne soit figé à 0 sur une erreur transitoire.
                guard let collection else {
                    continuation.resume(returning: nil)
                    return
                }
                var result: [Date: Int] = [:]
                collection.enumerateStatistics(from: anchor, to: to) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        let day = calendar.startOfDay(for: stats.startDate)
                        result[day] = Int(sum.doubleValue(for: .count()))
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}

/// Fake injectable — previews et tests (spec §11).
final class FakeStepsService: StepsProviding {
    /// Pas par jour, clé = minuit local.
    var stepsByDay: [Date: Int]
    var authorized: Bool
    /// Simule une ERREUR de requête HealthKit (service disponible mais requête
    /// qui échoue) : `dailySteps` renvoie nil alors qu'`isAvailable` reste vrai.
    var failing: Bool
    private let calendar: Calendar

    init(
        stepsByDay: [Date: Int] = [:],
        authorized: Bool = true,
        failing: Bool = false,
        calendar: Calendar = .current
    ) {
        self.stepsByDay = stepsByDay
        self.authorized = authorized
        self.failing = failing
        self.calendar = calendar
    }

    var isAvailable: Bool { authorized }

    func requestAuthorization() async -> Bool { authorized }

    func steps(on day: Date) async -> Int? {
        guard authorized, !failing else { return nil }
        return stepsByDay[calendar.startOfDay(for: day)] ?? 0
    }

    func dailySteps(from: Date, to: Date) async -> [Date: Int]? {
        guard authorized, !failing else { return nil }
        // Borne haute exclusive, comme le predicate HealthKit de HealthKitService.
        return stepsByDay.filter { $0.key >= calendar.startOfDay(for: from) && $0.key < to }
    }
}
