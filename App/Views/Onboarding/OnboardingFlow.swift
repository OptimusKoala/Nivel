// App/Views/Onboarding/OnboardingFlow.swift
// Premier lancement (spec §5) : 5 pages, transitions spring, Nivelito partout.
// À la fin : UserProfile + WeightEntry initiale + GamificationState (quêtes tirées),
// planification des rappels (NotificationService), sauvegarde explicite → tabs.

import SwiftUI
import SwiftData
import UserNotifications
import NivelCore

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext

    @State private var page = 0

    // Saisies
    @State private var name = ""
    // Optionnel volontairement : « pas encore choisi » doit être représentable,
    // sinon la carte Homme paraîtrait pré-sélectionnée sur un écran qui demande
    // de choisir, et l'objectif kcal serait calculé sur un sexe non confirmé.
    @State private var sex: Sex?
    @State private var birthDate = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    @State private var heightCm = 175.0
    @State private var weightText = ""
    @State private var activity: ActivityLevel = .light

    // Autorisations (refus OK — l'app continue, spec §5)
    @State private var healthGranted = false
    @State private var healthAsked = false
    @State private var notificationsAsked = false

    private let pageCount = 5

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 16)

                ZStack {
                    switch page {
                    case 0: WelcomePage(onContinue: advance)
                    case 1: IdentityPage(
                        name: $name,
                        sex: $sex,
                        canContinue: Self.canLeaveIdentity(name: name, sex: sex),
                        onContinue: advance
                    )
                    case 2: InfosPage(
                        heightCm: $heightCm,
                        birthDate: $birthDate,
                        weightText: $weightText,
                        sex: sexBinding,
                        activity: $activity,
                        canContinue: weightKg != nil,
                        onContinue: advance
                    )
                    case 3: GoalPage(target: computedTarget, onContinue: advance)
                    default: PermissionsPage(
                        healthAsked: healthAsked,
                        notificationsAsked: notificationsAsked,
                        onHealth: requestHealth,
                        onNotifications: requestNotifications,
                        onFinish: complete
                    )
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: page)
        .foregroundStyle(Theme.text)
    }

    // MARK: - En-tête

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.orange : Theme.track)
                    .frame(width: index == page ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.4), value: page)
        .accessibilityLabel("Étape \(page + 1) sur \(pageCount)")
    }

    // MARK: - Valeurs dérivées

    /// Le picker de la page Infos travaille sur un `Sex` non optionnel. Le repli
    /// est inatteignable : on ne quitte pas la page Identité sans avoir choisi.
    private var sexBinding: Binding<Sex> {
        Binding(get: { sex ?? .male }, set: { sex = $0 })
    }

    /// Décision de la page Identité : les deux entrées doivent être renseignées.
    /// Extraite en fonction pure pour être testable sans piloter SwiftUI.
    static func canLeaveIdentity(name: String, sex: Sex?) -> Bool {
        sex != nil && ProfileName.isAcceptable(name)
    }

    /// Poids saisi — accepte la virgule française.
    private var weightKg: Double? {
        let value = Double(weightText.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 20, value < 400 else { return nil }
        return value
    }

    private var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    private var computedTarget: Int {
        CalorieCalculator.dailyTarget(
            sex: sex ?? .male,
            weightKg: weightKg ?? 80,
            heightCm: heightCm,
            ageYears: ageYears,
            activity: activity
        )
    }

    // MARK: - Navigation

    private func advance() {
        guard page < pageCount - 1 else { return }
        page += 1
    }

    // MARK: - Autorisations

    private func requestHealth() {
        guard !healthAsked else { return }
        // Drapeau posé AVANT l'await : un double-tap rapide ne relance pas la demande.
        healthAsked = true
        Task {
            healthGranted = await HealthKitService().requestAuthorization()
        }
    }

    private func requestNotifications() {
        guard !notificationsAsked else { return }
        notificationsAsked = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    // MARK: - Finalisation

    private func complete() {
        // Garde anti-doublon : ne rien faire si un profil existe déjà.
        let existing = (try? modelContext.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard existing.isEmpty else { return }

        let weight = weightKg ?? 80
        let profile = UserProfile(
            // Pas de repli : la page Identité garantit un prénom non vide.
            name: ProfileName.sanitized(name),
            sex: sex ?? .male,
            birthDate: birthDate,
            heightCm: heightCm,
            initialWeightKg: weight,
            activity: activity,
            dailyCalorieTarget: computedTarget,
            dailyStepGoal: 8000,
            remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": true]
        )
        modelContext.insert(profile)
        modelContext.insert(WeightEntry(date: .now, weightKg: weight))

        let weekID = QuestEngine.weekID(for: .now, calendar: GameService.calendar)
        let pool = (try? Catalogs.quests()) ?? []
        // Lu comme au renouvellement hebdo (DayCloser) : l'interrupteur est éteint
        // par défaut, donc personne ne tire de quête posture à l'onboarding tant
        // qu'il n'a pas été allumé dans les Réglages (spec v1.11 §3).
        let quests = QuestEngine.weeklyDraw(pool: pool, weekID: weekID, stepsAvailable: healthGranted,
                                            postureAvailable: PosturePlanSettings.shared.isEnabled)
        modelContext.insert(GamificationState(
            totalXP: 0,
            activeQuestIDs: quests.map(\.id),
            questWeekID: weekID
        ))

        do {
            try modelContext.save()
            NotificationService.reschedule(for: profile)
        } catch {
            assertionFailure("SwiftData save failed at onboarding: \(error)")
        }
    }
}

// MARK: - Page 1 : Bienvenue

private struct WelcomePage: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            NivelitoView(expression: .joy, size: 160)
            VStack(spacing: 12) {
                Text("Salut ! Moi c'est Nivelito 🧡")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Je t'accompagne à ton rythme, zéro pression. On avance ensemble, un petit pas à la fois.")
                    .font(.body)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            Button("Commencer", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Page 2 : Identité

private struct IdentityPage: View {
    @Binding var name: String
    @Binding var sex: Sex?
    let canContinue: Bool
    let onContinue: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    field("Je suis") {
                        HStack(spacing: 12) {
                            sexCard(.male, avatar: "boy", label: "Homme")
                            sexCard(.female, avatar: "girl", label: "Femme")
                        }
                    }
                    field("Mon prénom") {
                        TextField("Ton prénom", text: $name)
                            .font(.headline)
                            .focused($nameFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { if canContinue { onContinue() } }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("Continuer", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            NivelitoView(expression: .happy, size: 60)
            SpeechBubble(text: "Et toi, tu es qui ?")
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Même gabarit que l'`infoCard` de la page Infos : les deux pages se suivent,
    /// elles doivent se ressembler.
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // Les deux Nivelito illustrés (Avatars/boy, Avatars/girl) et non des glyphes
    // cozy : un glyphe monochrome de 28 pt ne fait pas un visage, et l'app a déjà
    // un langage d'illustrations couleur (les vignettes sport). Décoratifs : le
    // label porte le sens. L'état retenu reprend le vocabulaire d'`activityRow`
    // (bordure + fond orange clair) : cet écran n'a pas de coche, il doit dire
    // « sélectionné » autrement.
    private func sexCard(_ value: Sex, avatar: String, label: String) -> some View {
        let isSelected = sex == value
        return Button {
            sex = value
            nameFocused = true
        } label: {
            VStack(spacing: 8) {
                Image(decorative: "Avatars/\(avatar)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text(label).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Theme.orange.opacity(0.10) : Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Theme.orange : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Page 3 : Infos

private struct InfosPage: View {
    @Binding var heightCm: Double
    @Binding var birthDate: Date
    @Binding var weightText: String
    @Binding var sex: Sex
    @Binding var activity: ActivityLevel
    let canContinue: Bool
    let onContinue: () -> Void

    @FocusState private var weightFocused: Bool

    /// Borne haute de la date de naissance : au moins 13 ans.
    private static let maxBirthDate = Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                NivelitoView(expression: .encouraging, size: 60)
                SpeechBubble(text: "Quelques infos pour calculer ton objectif !")
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 14) {
                    infoCard("Taille") {
                        Stepper(value: $heightCm, in: 120...220, step: 1) {
                            Text("\(Int(heightCm)) cm").font(.headline)
                        }
                    }
                    infoCard("Date de naissance") {
                        DatePicker("", selection: $birthDate, in: ...Self.maxBirthDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "fr_FR"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    infoCard("Poids actuel") {
                        HStack {
                            TextField("72,5", text: $weightText)
                                .keyboardType(.decimalPad)
                                .focused($weightFocused)
                                .font(.headline)
                            Text("kg").foregroundStyle(Theme.subtext)
                        }
                    }
                    infoCard("Sexe") {
                        Picker("Sexe", selection: $sex) {
                            Text("Homme").tag(Sex.male)
                            Text("Femme").tag(Sex.female)
                        }
                        .pickerStyle(.segmented)
                    }
                    infoCard("Niveau d'activité") {
                        VStack(spacing: 8) {
                            activityRow(.sedentary, "Sédentaire", "beaucoup de temps assis")
                            activityRow(.light, "Léger", "je bouge un peu chaque jour")
                            activityRow(.moderate, "Modéré", "de l'exercice régulier")
                            activityRow(.active, "Actif", "sport fréquent")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("Continuer", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func activityRow(_ level: ActivityLevel, _ title: String, _ subtitle: String) -> some View {
        Button {
            activity = level
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(Theme.subtext)
                }
                Spacer()
                Image(systemName: activity == level ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(activity == level ? Theme.orange : Theme.track)
                    .font(.title3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(activity == level ? Theme.orange.opacity(0.10) : Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(activity == level ? Theme.orange : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page 4 : Objectif

private struct GoalPage: View {
    let target: Int
    let onContinue: () -> Void

    @State private var showSources = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            NivelitoView(expression: .joy, size: 130)
            VStack(spacing: 16) {
                Text("~\(target) kcal")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.orange)
                Text("Je te propose ~\(target) kcal par jour : une perte douce, sans pression. Tu pourras l'ajuster quand tu veux.")
                    .font(.body)
                    .foregroundStyle(Theme.subtext)
                    .multilineTextAlignment(.center)
                // Citation exigée par App Review (1.4.1) : la recommandation kcal
                // doit pointer vers ses sources là où elle est faite.
                Button("D'où vient ce calcul ?") { showSources = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .card()
            .padding(.horizontal, 24)
            .sheet(isPresented: $showSources) { SourcesView() }
            Spacer()
            Button("C'est parti !", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Page 5 : Autorisations

private struct PermissionsPage: View {
    let healthAsked: Bool
    let notificationsAsked: Bool
    let onHealth: () -> Void
    let onNotifications: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                NivelitoView(expression: .encouraging, size: 72)
                SpeechBubble(text: "Deux petites autorisations, et si tu préfères sans, ça marche aussi !")
                    .padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            permissionCard(
                icon: "icon_heart",
                title: "Santé",
                subtitle: "Pour compter tes pas automatiquement.",
                asked: healthAsked,
                action: onHealth
            )
            permissionCard(
                icon: "icon_bell",
                title: "Notifications",
                subtitle: "Des petits rappels bienveillants, jamais de reproche.",
                asked: notificationsAsked,
                action: onNotifications
            )
            Spacer()
            Button("Terminer", action: onFinish)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private func permissionCard(
        icon: String, title: String, subtitle: String,
        asked: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            CozyIcon(name: icon, size: 45).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtext)
            }
            Spacer()
            if asked {
                CozyIcon(name: "icon_check", size: 26)
                    .font(.title2)
                    .foregroundStyle(Theme.green)
            } else {
                // « Continuer », pas « Autoriser » : App Review (5.1.1) refuse un
                // pré-écran dont le bouton préjuge la réponse — c'est la boîte de
                // dialogue système qui autorise, pas celui-ci.
                Button("Continuer", action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.orange, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingFlow()
        .fontDesign(.rounded)
        .modelContainer(for: [UserProfile.self, MealEntry.self, WeightEntry.self,
                               DayLog.self, GamificationState.self, ActivityEntry.self], inMemory: true)
}
