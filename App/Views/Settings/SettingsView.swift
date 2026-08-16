// App/Views/Settings/SettingsView.swift
// Réglages (spec §4.5) : profil, objectifs, rappels, santé, à propos.
// Liste "cozy" custom (cartes sur fond crème) plutôt que Form — le Form UIKit
// imposerait son propre fond et casserait le thème.
// Persistance : sauvegarde explicite à chaque modification, via le `save()` local
// (modelContext.save() + synchronisation du widget), pas via GameService.

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct SettingsView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                SettingsContent(profile: profile)
            } else {
                ZStack { Theme.background.ignoresSafeArea() }
            }
        }
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }
}

struct SettingsContent: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(GameService.self) var game

    @State private var kcalText = ""
    /// Nouvel objectif proposé par "Recalculer" — non nil = alerte de confirmation visible.
    @State private var recalcProposal: Int?
    @FocusState private var kcalFocused: Bool
    /// Tampon du prénom, comme `kcalText` : une frappe invalide ne doit jamais
    /// atteindre le profil persisté.
    @State private var nameText = ""
    @FocusState private var nameFocused: Bool
    /// Sheet des citations scientifiques (À propos > Sources scientifiques).
    @State private var showSources = false

    /// Bornes de vraisemblance de l'objectif kcal saisi à la main.
    private static let kcalRange = 800...6000
    /// Borne haute de la date de naissance : au moins 13 ans (comme l'onboarding).
    private static let maxBirthDate = Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now

    private let health = HealthKitService()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Réglages")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    profileSection
                    goalsSection
                    soundSection
                    postureSection
                    muscuSection
                    remindersSection
                    themeSection
                    healthSection
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        .onAppear {
            kcalText = String(profile.dailyCalorieTarget)
            nameText = profile.name
        }
        .onChange(of: kcalText) { _, text in commitKcal(text) }
        .onChange(of: kcalFocused) { _, focused in
            // Sortie de champ : on réaffiche la valeur réellement persistée
            // (une saisie invalide n'est jamais appliquée).
            if !focused { kcalText = String(profile.dailyCalorieTarget) }
        }
        .onChange(of: nameText) { _, text in commitName(text) }
        .onChange(of: nameFocused) { _, focused in
            // Sortie de champ : on réaffiche le prénom réellement persisté, donc
            // un champ vidé puis abandonné retrouve l'ancien prénom.
            if !focused { nameText = profile.name }
        }
        .onChange(of: profile.heightCm) { save() }
        .onChange(of: profile.birthDate) { save() }
        .onChange(of: profile.sexRaw) { save() }
        .onChange(of: profile.activityRaw) { save() }
        .onChange(of: profile.dailyStepGoal) { save() }
        .onChange(of: profile.dailyBurnTarget) { save() }
        .alert(
            "Recalculer mon objectif",
            isPresented: Binding(
                get: { recalcProposal != nil },
                set: { if !$0 { recalcProposal = nil } }
            ),
            presenting: recalcProposal
        ) { proposal in
            Button("Appliquer") { applyRecalc(proposal) }
            Button("Annuler", role: .cancel) {}
        } message: { proposal in
            Text("~\(profile.dailyCalorieTarget) kcal → ~\(proposal) kcal, avec ton poids actuel (\(formattedWeight) kg).")
        }
    }

    // MARK: - Valeurs dérivées

    /// Poids courant = dernière pesée (il y en a toujours une, créée à l'onboarding).
    /// `game.currentWeightKg()` est un fetch one-shot, pas un état observé — mais
    /// aucune pesée ne peut être enregistrée pendant que les Réglages sont ouverts :
    /// `logWeight` n'a qu'un seul appelant dans toute l'app, `WeighInSheet`, qui
    /// n'est présentée que depuis `ProgressScreen` (jamais depuis les Réglages).
    /// Rien ici ne peut donc devenir périmé en cours d'écran.
    private var currentWeightKg: Double {
        game.currentWeightKg()
    }

    private var formattedWeight: String {
        currentWeightKg.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
    }

    private var ageYears: Int {
        Calendar.current.dateComponents([.year], from: profile.birthDate, to: .now).year ?? 30
    }

    /// Objectif recalculé avec le profil actuel + le poids de la dernière pesée (spec §6).
    private var computedTarget: Int {
        CalorieCalculator.dailyTarget(
            sex: profile.sex,
            weightKg: currentWeightKg,
            heightCm: profile.heightCm,
            ageYears: ageYears,
            activity: profile.activity
        )
    }

    /// Objectif de dépense affiché : réglé, ou calculé depuis le poids courant tant
    /// que `profile.dailyBurnTarget` vaut son sentinelle 0 (spec §5.3). Passe par
    /// `game.burnTarget()` — le point d'appariement unique entre le poids et la
    /// résolution du sentinelle — plutôt que de réapparier `profile.burnTarget(
    /// currentWeightKg:)` avec `currentWeightKg` ici même.
    private var effectiveBurnTarget: Int {
        game.burnTarget()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Profil

    private var profileSection: some View {
        section("Profil") {
            row("Prénom") {
                TextField("Ton prénom", text: $nameText)
                    .font(.headline)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)
                    // Le helper `row` place un Spacer avant son contenu. Un
                    // DatePicker a une taille intrinsèque et s'en accommode ; un
                    // TextField non, il se battrait avec le Spacer pour la place.
                    // On réclame donc le reste de la ligne — la zone tapable
                    // couvre alors toute la droite de la rangée.
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            divider
            row("Taille") {
                Stepper(value: $profile.heightCm, in: 120...220, step: 1) {
                    Text("\(Int(profile.heightCm)) cm").font(.headline)
                }
            }
            divider
            row("Date de naissance") {
                DatePicker("", selection: $profile.birthDate, in: ...Self.maxBirthDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            }
            divider
            row("Sexe") {
                Picker("Sexe", selection: $profile.sex) {
                    Text("Homme").tag(Sex.male)
                    Text("Femme").tag(Sex.female)
                }
                .pickerStyle(.segmented)
            }
            divider
            row("Niveau d'activité") {
                Picker("Niveau d'activité", selection: $profile.activity) {
                    Text("Sédentaire").tag(ActivityLevel.sedentary)
                    Text("Léger").tag(ActivityLevel.light)
                    Text("Modéré").tag(ActivityLevel.moderate)
                    Text("Actif").tag(ActivityLevel.active)
                }
                .pickerStyle(.menu)
            }

            Button("Recalculer mon objectif") {
                recalcProposal = computedTarget
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)
        }
    }

    // MARK: - Objectifs

    private var goalsSection: some View {
        section("Objectifs") {
            VStack(alignment: .leading, spacing: 6) {
                row("Objectif kcal / jour") {
                    HStack(spacing: 6) {
                        TextField("1800", text: $kcalText)
                            .keyboardType(.numberPad)
                            .focused($kcalFocused)
                            .font(.headline)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 76)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        Text("kcal").foregroundStyle(Theme.subtext)
                    }
                }
                Text("calculé : ~\(computedTarget) kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            divider
            row("Pas quotidiens") {
                Stepper(value: $profile.dailyStepGoal, in: 2000...30000, step: 500) {
                    Text("\(profile.dailyStepGoal)").font(.headline)
                }
            }
            divider
            // Sentinelle 0 = jamais réglé (spec §5.3) : tant que le joueur n'a pas
            // touché ce Stepper, il affiche et modifie la valeur calculée depuis le
            // poids courant. Premier mouvement → dailyBurnTarget se fixe et fait foi.
            row("Objectif de dépense") {
                Stepper(
                    value: Binding(
                        get: { effectiveBurnTarget },
                        set: { profile.dailyBurnTarget = $0 }
                    ),
                    in: 200...600,
                    step: 50
                ) {
                    Text("\(effectiveBurnTarget) kcal").font(.headline)
                }
            }
        }
    }

    // MARK: - Santé

    // iOS ne révèle jamais si une autorisation de LECTURE Santé a été accordée ou
    // refusée (confidentialité) — on ne prétend donc jamais "Activé" : copie neutre.
    private var healthSection: some View {
        section("Santé") {
            if health.isAvailable {
                Text("Lecture des pas configurée : si tes pas n'apparaissent pas, vérifie dans Réglages > Santé.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            } else {
                row("Accès aux pas") {
                    Text("Non activé")
                        .font(.headline)
                        .foregroundStyle(Theme.subtext)
                }
                Text("Autorise la lecture des pas dans Réglages → Confidentialité → Santé.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - À propos

    private var aboutSection: some View {
        section("À propos") {
            row("Version") {
                Text(appVersion)
                    .font(.headline)
                    .foregroundStyle(Theme.subtext)
            }
            divider
            // Citations des recommandations santé (App Review, 1.4.1) — doivent
            // rester faciles à trouver.
            Button {
                showSources = true
            } label: {
                HStack {
                    Text("Sources scientifiques").font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.subtext)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSources) { SourcesView() }
            divider
            Text("Fait avec 🧡 pour Michaël & Marion")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Briques de mise en page

    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            content()
        }
    }

    var divider: some View {
        Rectangle().fill(Theme.track).frame(height: 1)
    }

    // MARK: - Actions

    /// Applique la saisie kcal si elle est vraisemblable (les valeurs intermédiaires
    /// valides pendant la frappe sont persistées — la dernière gagne).
    private func commitKcal(_ text: String) {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              Self.kcalRange.contains(value),
              value != profile.dailyCalorieTarget else { return }
        profile.dailyCalorieTarget = value
        save()
    }

    /// Prénom à persister, ou nil si cette frappe ne doit rien changer. `static`
    /// et pure pour être testable sans profil SwiftData ni SwiftUI.
    static func nameToCommit(_ text: String, current: String) -> String? {
        guard ProfileName.isAcceptable(text) else { return nil }
        let cleaned = ProfileName.sanitized(text)
        return cleaned == current ? nil : cleaned
    }

    private func commitName(_ text: String) {
        guard let name = Self.nameToCommit(text, current: profile.name) else { return }
        profile.name = name
        save()
    }

    private func applyRecalc(_ target: Int) {
        // Même garde-fou que la saisie manuelle (CalorieCalculator a déjà ses
        // planchers, mais l'objectif persisté reste borné quoi qu'il arrive).
        let clamped = min(max(target, Self.kcalRange.lowerBound), Self.kcalRange.upperBound)
        profile.dailyCalorieTarget = clamped
        kcalText = String(clamped)
        save()
    }

    /// Sauvegarde explicite : silencieuse en release, assert en debug (échec = bug).
    func save() {
        do {
            try modelContext.save()
            // Ce chemin ne passe pas par GameService.saveOrAssert : prénom et
            // objectif kcal sont dans le snapshot, on synchronise donc ici aussi.
            game.syncWidget()
        } catch {
            assertionFailure("SwiftData save failed in SettingsView: \(error)")
        }
    }
}

#Preview {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
    )
    let profile = UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Calendar.current.date(from: DateComponents(year: 1990, month: 5, day: 12))!,
        heightCm: 180, initialWeightKg: 90, activity: .light,
        dailyCalorieTarget: 2100,
        remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": false],
        reminderTimes: ["dinner": 19 * 60 + 45],
        reminderWeekdays: ["weigh": 1]
    )
    container.mainContext.insert(profile)
    container.mainContext.insert(WeightEntry(date: .now, weightKg: 88.4))
    return SettingsView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService(), widgetDefaults: nil))
}
