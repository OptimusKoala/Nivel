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

private struct SettingsContent: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(GameService.self) private var game
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var kcalText = ""
    /// Nouvel objectif proposé par "Recalculer" — non nil = alerte de confirmation visible.
    @State private var recalcProposal: Int?
    @FocusState private var kcalFocused: Bool

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
        .onAppear { kcalText = String(profile.dailyCalorieTarget) }
        .onChange(of: kcalText) { _, text in commitKcal(text) }
        .onChange(of: kcalFocused) { _, focused in
            // Sortie de champ : on réaffiche la valeur réellement persistée
            // (une saisie invalide n'est jamais appliquée).
            if !focused { kcalText = String(profile.dailyCalorieTarget) }
        }
        .onChange(of: profile.heightCm) { save() }
        .onChange(of: profile.birthDate) { save() }
        .onChange(of: profile.sexRaw) { save() }
        .onChange(of: profile.activityRaw) { save() }
        .onChange(of: profile.dailyStepGoal) { save() }
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
    private var currentWeightKg: Double {
        weights.last?.weightKg ?? profile.initialWeightKg
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Profil

    private var profileSection: some View {
        section("Profil") {
            row("Prénom") {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(Theme.subtext)
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
        }
    }

    // MARK: - Rappels

    private var remindersSection: some View {
        section("Rappels") {
            reminderToggle("lunch", "Déjeuner", "tous les jours à 12 h 30")
            divider
            reminderToggle("dinner", "Dîner", "tous les jours à 20 h")
            divider
            reminderToggle("weigh", "Pesée", "le samedi à 9 h")
            divider
            reminderToggle("steps", "Pas", "tous les jours à 18 h")
        }
    }

    private func reminderToggle(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: reminderBinding(id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtext)
            }
        }
    }

    /// Binding d'un rappel — réassignation COMPLÈTE du dictionnaire (règle SwiftData :
    /// pas de mutation en place des collections d'un @Model), puis re-planification.
    private func reminderBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { profile.remindersEnabled[id] ?? false },
            set: { newValue in
                var enabled = profile.remindersEnabled
                enabled[id] = newValue
                profile.remindersEnabled = enabled
                save()
                NotificationService.reschedule(for: profile)
            }
        )
    }

    // MARK: - Thème

    /// Choix de la palette (v1.1) — PAR APPAREIL : persisté dans UserDefaults
    /// par ThemeStore, indépendant du profil SwiftData. Le changement re-rend
    /// toute l'app instantanément (façade Theme + @Observable).
    private var themeSection: some View {
        section("Thème") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(ThemePalette.all) { palette in
                    ThemeSwatchCard(palette: palette,
                                    isSelected: ThemeStore.shared.palette.id == palette.id) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            ThemeStore.shared.palette = palette
                        }
                        // Le thème vit dans UserDefaults, hors SwiftData : aucune
                        // sauvegarde ne déclenche le hook, on synchronise ici.
                        game.syncWidget()
                    }
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
            Text("Fait avec 🧡 pour Michaël & Marion")
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Briques de mise en page

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
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

    private var divider: some View {
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

    private func applyRecalc(_ target: Int) {
        // Même garde-fou que la saisie manuelle (CalorieCalculator a déjà ses
        // planchers, mais l'objectif persisté reste borné quoi qu'il arrive).
        let clamped = min(max(target, Self.kcalRange.lowerBound), Self.kcalRange.upperBound)
        profile.dailyCalorieTarget = clamped
        kcalText = String(clamped)
        save()
    }

    /// Sauvegarde explicite : silencieuse en release, assert en debug (échec = bug).
    private func save() {
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

/// Carte de sélection d'une palette : pastille d'aperçu (fond du thème +
/// points primaire/accent), emoji + nom, coche animée sur la sélection.
private struct ThemeSwatchCard: View {
    let palette: ThemePalette
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                swatch
                HStack(spacing: 5) {
                    Text(palette.emoji).font(.footnote)
                    Text(palette.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.orange : Theme.track,
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                        .background(Circle().fill(Theme.card))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thème \(palette.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Cercle d'aperçu construit sur `palette.previewSwatches`.
    private var swatch: some View {
        let preview = palette.previewSwatches
        return ZStack {
            Circle().fill(preview.background)
            Circle().stroke(palette.subtext.opacity(0.45), lineWidth: 1)
            HStack(spacing: 3) {
                ForEach(Array(preview.dots.enumerated()), id: \.offset) { _, dot in
                    Circle().fill(dot).frame(width: 12, height: 12)
                }
            }
        }
        .frame(width: 42, height: 42)
    }
}

#Preview {
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self, ActivityEntry.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let profile = UserProfile(
        name: "Michaël", sex: .male,
        birthDate: Calendar.current.date(from: DateComponents(year: 1990, month: 5, day: 12))!,
        heightCm: 180, initialWeightKg: 90, activity: .light,
        dailyCalorieTarget: 2100,
        remindersEnabled: ["lunch": true, "dinner": true, "weigh": true, "steps": false]
    )
    container.mainContext.insert(profile)
    container.mainContext.insert(WeightEntry(date: .now, weightKg: 88.4))
    return SettingsView()
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}
