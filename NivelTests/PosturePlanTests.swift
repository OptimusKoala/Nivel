// NivelTests/PosturePlanTests.swift
// Interrupteur du programme posture (spec v1.11 §3) : copie conforme de
// SoundSettingsTests, PLUS le piège documenté v1.9 (clé de rappel absente = éteint)
// et le cas d'extinction en cours de semaine (spec §7.2, aucune purge de quête).

import XCTest
import SwiftData
@testable import Nivel

@MainActor
final class PosturePlanTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.posture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Persistance de base (miroir de SoundSettingsTests)

    /// Éteint par défaut : le programme n'existe que sur le téléphone qui l'allume.
    func testEteintParDefaut() {
        XCTAssertFalse(PosturePlanSettings(defaults: defaults).isEnabled)
    }

    func testLeChoixEstPersiste() {
        PosturePlanSettings(defaults: defaults).isEnabled = true
        XCTAssertTrue(PosturePlanSettings(defaults: defaults).isEnabled)
    }

    /// `false` persisté doit survivre : `object(forKey:)` et non `bool(forKey:)`,
    /// sinon on ne peut pas distinguer "jamais réglé" de "réglé à false" (ici les
    /// deux valent faux, donc le test bascule d'abord à vrai pour les distinguer).
    func testFauxPersisteNEstPasConfonduAvecLAbsence() {
        defaults.set(true, forKey: PosturePlanSettings.defaultsKey)
        XCTAssertTrue(PosturePlanSettings(defaults: defaults).isEnabled)
        defaults.set(false, forKey: PosturePlanSettings.defaultsKey)
        XCTAssertFalse(PosturePlanSettings(defaults: defaults).isEnabled)
        defaults.removeObject(forKey: PosturePlanSettings.defaultsKey)
        XCTAssertFalse(PosturePlanSettings(defaults: defaults).isEnabled)
    }

    // MARK: - Le piège du rappel muet (spec v1.9 : clé absente = désactivé)

    private func makeProfile() throws -> UserProfile {
        let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                             DayLog.self, GamificationState.self, ActivityEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let profile = UserProfile(
            name: "Marion", sex: .female,
            birthDate: Date(timeIntervalSince1970: 0),
            heightCm: 165, initialWeightKg: 62, activity: .light,
            dailyCalorieTarget: 1700,
            remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": true]
        )
        container.mainContext.insert(profile)
        return profile
    }

    /// LE test du lot 5 : une clé absente de `remindersEnabled` vaut désactivée
    /// (piège documenté v1.9). Allumer l'interrupteur doit donc poser EXPLICITEMENT
    /// `remindersEnabled["posture"] = true`, sinon le rappel de 21 h naît muet et
    /// Marion ne le trouve jamais dans les Réglages.
    func testAllumerPoseExplicitementLaCleDuRappel() throws {
        let profile = try makeProfile()
        let settings = PosturePlanSettings(defaults: defaults)
        XCTAssertNil(profile.remindersEnabled["posture"], "aucune clé avant le premier allumage")

        settings.setEnabled(true, on: profile)
        XCTAssertEqual(profile.remindersEnabled["posture"], true)
        XCTAssertTrue(settings.isEnabled)
    }

    /// Symétrique : éteindre repose la clé à faux, plutôt que de la retirer (une
    /// clé retirée redeviendrait "absente", donc encore désactivée par accident,
    /// mais on veut ici vérifier que le geste inverse est bien explicite aussi).
    func testEteindreRemetLaCleAFaux() throws {
        let profile = try makeProfile()
        let settings = PosturePlanSettings(defaults: defaults)
        settings.setEnabled(true, on: profile)
        XCTAssertEqual(profile.remindersEnabled["posture"], true)

        settings.setEnabled(false, on: profile)
        XCTAssertEqual(profile.remindersEnabled["posture"], false)
        XCTAssertFalse(settings.isEnabled)
    }

    // MARK: - Extinction en cours de semaine (spec §7.2 : aucune purge de quête)

    /// Éteindre le programme alors qu'une quête posture est active pour la semaine
    /// ne doit RIEN faire de plus que le rappel et l'affichage : la quête reste à sa
    /// progression, ne se complète pas, et le lundi suivant en tire une autre. La
    /// retirer de force serait la seule fois où l'app reprendrait quelque chose.
    func testEteindreEnCoursDeSemaineNePurgePasLesQuetes() throws {
        let profile = try makeProfile()
        let state = GamificationState(
            totalXP: 200,
            activeQuestIDs: ["posture_sessions_3"],
            questWeekID: "2026-W32",
            questProgress: ["posture_sessions_3": 2]
        )
        container.mainContext.insert(state)
        try container.mainContext.save()

        let settings = PosturePlanSettings(defaults: defaults)
        settings.setEnabled(true, on: profile)
        settings.setEnabled(false, on: profile)

        XCTAssertEqual(state.activeQuestIDs, ["posture_sessions_3"])
        XCTAssertEqual(state.questProgress["posture_sessions_3"], 2)
    }

    // MARK: - Enregistrement d'une séance posture (Task 6, spec §6/§7.3/§8)

    private func makeService() throws -> GameService {
        _ = try makeProfile()
        container.mainContext.insert(GamificationState())
        try container.mainContext.save()
        return GameService(modelContext: container.mainContext,
                           stepsService: FakeStepsService(authorized: false), widgetDefaults: nil)
    }

    /// Plafonds INDÉPENDANTS au niveau du SERVICE (pas seulement de XPEngine) :
    /// faire la séance posture ET la séance du jour le même soir doit payer les
    /// deux, sinon on punit exactement le comportement qu'on veut installer.
    func testLogPostureSessionEtSeanceDuJourPaientLesDeuxLeMemeSoir() async throws {
        let service = try makeService()
        let posture = try XCTUnwrap(service.postureCatalog.sessions.first)
        let daily = try XCTUnwrap(service.sessionCatalog.first)

        let postureEntry = await service.logPostureSession(session: posture)
        let dailyEntry = await service.logDailySession(session: daily)

        XCTAssertEqual(postureEntry.xpAwarded, 40)
        XCTAssertEqual(dailyEntry.xpAwarded, 40)
    }

    /// Miroir exact de `dailySessionDayCount` : deux séances posture le même soir
    /// valent UN jour, sinon la quête et le compteur récompenseraient le
    /// bachotage plutôt que la régularité (spec §7.2, §7.3).
    func testDoublePostureSessionSameDayCountsOnce() async throws {
        let service = try makeService()
        let posture = try XCTUnwrap(service.postureCatalog.sessions.first)

        _ = await service.logPostureSession(session: posture)
        _ = await service.logPostureSession(session: posture)

        let (start, end) = try XCTUnwrap(service.dayBounds(for: .now))
        XCTAssertEqual(service.postureSessionDayCount(from: start, to: end), 1)
    }

    /// Le compteur mensuel de la carte (spec §7.3) : zéro, une, puis plusieurs
    /// séances sur des jours DISTINCTS du mois courant.
    func testCompteurMensuelAZeroUneEtPlusieursJours() async throws {
        let service = try makeService()
        let posture = try XCTUnwrap(service.postureCatalog.sessions.first)
        let now = Date(timeIntervalSince1970: 1_785_000_000) // date fixe, sans dépendre du jour du run

        XCTAssertEqual(service.postureSessionsThisMonth(now: now), 0)

        _ = await service.logPostureSession(session: posture, date: now)
        XCTAssertEqual(service.postureSessionsThisMonth(now: now), 1)

        let calendar = GameService.calendar
        let dayLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let twoDaysLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: now))
        _ = await service.logPostureSession(session: posture, date: dayLater)
        _ = await service.logPostureSession(session: posture, date: twoDaysLater)
        XCTAssertEqual(service.postureSessionsThisMonth(now: now), 3)
    }

    /// Une entrée posture dans "Fait aujourd'hui" porte un id de SÉANCE (comme
    /// `.dailySession`), résoluble via le catalogue posture ; et un exercice
    /// posture pris isolément se résout via la table `activitiesByID` FUSIONNÉE
    /// (spec §6) — sinon l'un ou l'autre s'affiche en id brut dans la liste.
    func testEntreePostureResolubleParSonTitre() async throws {
        let service = try makeService()
        let posture = try XCTUnwrap(service.postureCatalog.sessions.first)
        let firstExercise = try XCTUnwrap(service.postureCatalog.activities.first)

        let entry = await service.logPostureSession(session: posture)
        let today = service.todayActivities()
        XCTAssertTrue(today.contains { $0.id == entry.id })
        XCTAssertEqual(entry.refID, posture.id)
        XCTAssertEqual(
            service.postureCatalog.sessions.first { $0.id == entry.refID }?.title,
            posture.title
        )
        // La table fusionnée porte aussi les EXERCICES posture (pas seulement les
        // séances), sinon un exercice loggé à l'unité (ActivityKind.activity)
        // perdrait son nom dans la même liste.
        XCTAssertEqual(service.activitiesByID[firstExercise.id]?.name, firstExercise.name)
    }
}
