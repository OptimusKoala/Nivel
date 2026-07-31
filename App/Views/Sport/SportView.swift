// App/Views/Sport/SportView.swift
// Onglet Sport (spec sport §8.3) : séance du jour, catalogue Maison/Dehors,
// « Fait aujourd'hui » (swipe = supprimer, jour même par construction).

import SwiftUI
import SwiftData
import NivelCore

struct SportView: View {
    @Environment(GameService.self) private var game

    @State private var sessionStatus: (session: ActivitySession, done: Bool)?
    @State private var todayEntries: [ActivityEntry] = []
    @State private var selectedActivity: Activity?
    @State private var showSessionDetail = false

    private var homeActivities: [Activity] {
        game.activityCatalog.filter { $0.location != .outdoor }
    }
    private var outdoorActivities: [Activity] {
        game.activityCatalog.filter { $0.location == .outdoor }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    if let status = sessionStatus {
                        Button { showSessionDetail = true } label: {
                            DailySessionCardContent(session: status.session,
                                                    kcal: game.sessionKcal(status.session),
                                                    done: status.done)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                } header: { header }

                activitySection("🏠 À la maison", activities: homeActivities)
                activitySection("🌳 Dehors", activities: outdoorActivities)

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
        // reload() est synchrone : onAppear suffit (couvre 1ᵉʳ affichage ET retours d'onglet).
        .onAppear(perform: reload)
        .sheet(isPresented: $showSessionDetail, onDismiss: reload) {
            if let status = sessionStatus {
                SessionDetailSheet(session: status.session, done: status.done)
            }
        }
        .sheet(item: $selectedActivity, onDismiss: reload) { activity in
            ActivityLogSheet(activity: activity)
        }
    }

    private func reload() {
        sessionStatus = game.dailySessionStatus()
        todayEntries = game.todayActivities()
    }

    private var header: some View {
        Text("Sport")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
    }

    private func activitySection(_ title: String, activities: [Activity]) -> some View {
        Section {
            ForEach(activities) { activity in
                Button { selectedActivity = activity } label: {
                    HStack(spacing: 12) {
                        SportIllustration(name: activity.id, fallbackEmoji: activity.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            // Fourchette kcal indicative (spec sport §8.3) sur les durées min/max.
                            Text(activity.durations.map(String.init).joined(separator: " / ")
                                 + " min · ~\(activity.estimatedKcal(minutes: activity.durations.first ?? 0).frFormatted)"
                                 + " à \(activity.estimatedKcal(minutes: activity.durations.last ?? 0).frFormatted) kcal")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subtext)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        } header: {
            Overline(title)
        }
    }

    private func doneRow(_ entry: ActivityEntry) -> some View {
        let (emoji, name): (String, String) = {
            switch entry.kind {
            case .activity:
                let activity = game.activitiesByID[entry.refID]
                return (activity?.emoji ?? "🏃", activity?.name ?? entry.refID)
            case .dailySession:
                let session = game.sessionCatalog.first { $0.id == entry.refID }
                return (session?.emoji ?? "📅", session?.title ?? entry.refID)
            }
        }()
        return HStack(spacing: 12) {
            SportIllustration(name: entry.refID, fallbackEmoji: emoji)
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
    return (container, GameService(modelContext: context, stepsService: fake))
}

#Preview("Sport") {
    let (container, game) = sportPreviewFixture()
    SportView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
