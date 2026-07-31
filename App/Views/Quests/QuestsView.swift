// App/Views/Quests/QuestsView.swift
// Écran Quêtes & trophées (spec §4.4, §7) : les 3 quêtes de la semaine avec leur
// progression, puis la collection complète des badges (débloqués en couleur,
// verrouillés en silhouette avec indice). Tap sur un badge débloqué → fiche medium
// avec la date et une phrase de Nivelito.

import SwiftUI
import SwiftData
import NivelCore

struct QuestsView: View {
    @Environment(GameService.self) private var game
    @Query private var states: [GamificationState]

    @State private var selectedBadge: Badge?

    /// Catalogue complet des badges — celui déjà chargé par GameService à l'init
    /// (pas de relecture du bundle à chaque re-rendu de la vue).
    private var badges: [Badge] { game.badges }

    private var badgeUnlocks: [String: Date] { states.first?.badgeUnlocks ?? [:] }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quêtes")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)

                    weeklyQuestsSection
                    trophiesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await game.refreshQuestProgress() }
        }
        .task { await game.refreshQuestProgress() }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(badge: badge, unlockDate: badgeUnlocks[badge.id])
        }
    }

    // MARK: - Quêtes de la semaine

    private var weeklyQuestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Quêtes de la semaine")

            let statuses = game.activeQuestStatuses()
            if statuses.isEmpty {
                // Aucun tirage pour la semaine courante (rollover en attente du
                // DayCloser) : pas de reproche, juste l'info du rendez-vous du lundi
                // — même motif d'état vide que le journal (Nivelito + phrase douce).
                HStack(spacing: 12) {
                    NivelitoView(expression: .happy, size: 56)
                    Text("Tes prochaines quêtes arrivent bientôt !")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtext)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            } else {
                ForEach(statuses) { status in
                    WeeklyQuestCard(status: status)
                }
            }

            Text("Nouvelles quêtes lundi 🌱")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Trophées

    private var trophiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Trophées")
                Spacer()
                Text("\(badgeUnlocks.count) / \(badges.count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.orange)
            }

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(badges) { badge in
                    BadgeTile(badge: badge, unlockDate: badgeUnlocks[badge.id]) {
                        selectedBadge = badge
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Carte quête hebdo

private struct WeeklyQuestCard: View {
    let status: ActiveQuestStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(status.quest.emoji)
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(status.quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Spacer()
                    if status.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.orange)
                    }
                    Text("\(status.progress.frFormatted) / \(status.quest.target.frFormatted)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.orange)
                        .lineLimit(1)
                }
                ThemedProgressBar(
                    fraction: status.fraction,
                    fill: LinearGradient(
                        // Complétée : traitement or/orange ; en cours : accent doré uni.
                        colors: status.isCompleted ? [Theme.accent, Theme.orange]
                                                   : [Theme.accent, Theme.accent],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(
            // Liseré doré discret sur les quêtes complétées.
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.accent.opacity(status.isCompleted ? 0.7 : 0), lineWidth: 1.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "\(status.quest.title) : \(status.progress) sur \(status.quest.target)"
        return status.isCompleted ? base + ", complétée" : base
    }
}

// MARK: - Tuile badge

private struct BadgeTile: View {
    let badge: Badge
    let unlockDate: Date?
    /// Ouvre la fiche — bouton réservé aux badges débloqués : le verrouillé garde
    /// son mystère (seul l'indice est visible), la tuile est alors désactivée.
    let onTap: () -> Void

    private var isUnlocked: Bool { unlockDate != nil }

    var body: some View {
        Button(action: onTap) { content }
            .buttonStyle(.plain)
            .disabled(!isUnlocked)
            .accessibilityLabel(
                unlockDate.map { "\(badge.title), débloqué le \($0.frShortDate)" }
                    ?? "Badge verrouillé : \(badge.hint)"
            )
    }

    private var content: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? Theme.accent.opacity(0.22) : Theme.track)
                Text(badge.emoji)
                    .font(.system(size: 30))
                    // Silhouette : emoji désaturé et estompé tant que le badge est verrouillé.
                    .grayscale(isUnlocked ? 0 : 1)
                    .opacity(isUnlocked ? 1 : 0.35)
            }
            .frame(width: 62, height: 62)

            if let unlockDate {
                Text(badge.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(unlockDate.frShortDate)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.subtext)
            } else {
                Text(badge.hint)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.subtext)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }
}

// MARK: - Fiche badge (sheet medium)

private struct BadgeDetailSheet: View {
    @Environment(GameService.self) private var game
    let badge: Badge
    let unlockDate: Date?

    @State private var nivelitoPhrase = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                Text(badge.emoji)
                    .font(.system(size: 72))
                    .padding(.top, 8)

                Text(badge.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)

                if let unlockDate {
                    Text("Débloqué le \(unlockDate.frShortDate)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                }

                HStack(alignment: .center, spacing: 10) {
                    NivelitoView(expression: .joy, size: 64)
                    if !nivelitoPhrase.isEmpty {
                        SpeechBubble(text: nivelitoPhrase)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(24)
            .multilineTextAlignment(.center)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        // onAppear (pas body) : nivelitoSays persiste le dernier message utilisé.
        .onAppear { nivelitoPhrase = game.nivelitoSays(context: .badge) }
    }
}

// MARK: - Formatage

extension Date {
    /// "29 juil. 2026" — date courte française pour les dates de déblocage.
    var frShortDate: String {
        formatted(.dateTime.day().month(.abbreviated).year()
            .locale(Locale(identifier: "fr_FR")))
    }
}

// MARK: - Previews

@MainActor
private func questsPreviewFixture(unlockedBadges: Bool) -> (ModelContainer, GameService) {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = container.mainContext

    context.insert(UserProfile(
        name: "Marion", sex: .female,
        birthDate: Date(timeIntervalSince1970: 0),
        heightCm: 165, initialWeightKg: 62, activity: .light,
        dailyCalorieTarget: 1700
    ))

    let quests = (try? Catalogs.quests()) ?? []
    let weekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
    let active = QuestEngine.weeklyDraw(pool: quests, weekID: weekID, stepsAvailable: true)
    let unlocks: [String: Date] = unlockedBadges
        ? ["first_meal": .now, "first_weigh": .now.addingTimeInterval(-4 * 86_400),
           "journal_7": .now.addingTimeInterval(-86_400)]
        : [:]
    context.insert(GamificationState(
        totalXP: 430,
        badgeUnlocks: unlocks,
        activeQuestIDs: active.map(\.id),
        questWeekID: weekID,
        questProgress: Dictionary(uniqueKeysWithValues: active.enumerated().map {
            ($1.id, $0 == 0 ? $1.target : $1.target / 2)
        }),
        completedThisWeekQuestIDs: active.first.map { [$0.id] } ?? []
    ))
    try? context.save()

    let fake = FakeStepsService(stepsByDay: [:], authorized: true)
    return (container, GameService(modelContext: context, stepsService: fake, widgetDefaults: nil))
}

#Preview("Quêtes & trophées") {
    let (container, game) = questsPreviewFixture(unlockedBadges: true)
    return QuestsView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}

#Preview("Tout verrouillé") {
    let (container, game) = questsPreviewFixture(unlockedBadges: false)
    return QuestsView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(game)
}
