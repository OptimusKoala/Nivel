// App/Views/Progress/WeighInSheet.swift
// Saisie manuelle du poids (spec §4.3) : champ décimal kg (virgule française acceptée),
// date = aujourd'hui (affichage seul), "Valider (+30 XP)" → GameService.logWeight,
// puis bulle Nivelito `afterWeighIn` avant fermeture.

import SwiftUI
import SwiftData
import UIKit
import NivelCore

struct WeighInSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var bubbleText = "On fait le point ? Note ton poids, je m'occupe du reste 🧡"
    @State private var hasWeighedIn = false
    @State private var isSaving = false
    @FocusState private var fieldFocused: Bool

    /// kg saisis — accepte virgule ET point ; bornes de vraisemblance 20…300 kg.
    private var parsedKg: Double? {
        let normalized = weightText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), (20...300).contains(value) else { return nil }
        return value
    }

    /// "Aujourd'hui · mardi 29 juillet" — la pesée est toujours datée du jour (affichage seul).
    private var frenchToday: String {
        let raw = Date.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: "fr_FR"))
        )
        return "Aujourd'hui · \(raw)"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Nouvelle pesée")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)

                HStack(alignment: .top, spacing: 10) {
                    NivelitoView(expression: hasWeighedIn ? .joy : .encouraging, size: 64)
                    SpeechBubble(text: bubbleText)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                }

                Text(frenchToday)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.subtext)

                weightField

                validateButton

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear { fieldFocused = true }
    }

    private var weightField: some View {
        HStack(spacing: 10) {
            TextField("80,4", text: $weightText)
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .disabled(isSaving)
            Text("kg")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.subtext)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(parsedKg != nil ? Theme.orange : .clear, lineWidth: 2)
        )
    }

    private var validateButton: some View {
        Button(action: validate) {
            Text("Valider (+30 XP)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.orange],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
                .opacity(parsedKg == nil ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(parsedKg == nil || isSaving)
    }

    private func validate() {
        guard let kg = parsedKg, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        fieldFocused = false
        Task {
            await game.logWeight(kg: kg)
            // Bulle afterWeighIn : petit moment avec Nivelito avant la fermeture.
            hasWeighedIn = true
            bubbleText = game.nivelitoSays(context: .afterWeighIn)
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        }
    }
}

#Preview {
    @Previewable @State var shown = true
    let schema = Schema([UserProfile.self, MealEntry.self, WeightEntry.self,
                         DayLog.self, GamificationState.self])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return Theme.background
        .ignoresSafeArea()
        .sheet(isPresented: $shown) {
            WeighInSheet()
                .presentationDetents([.medium])
        }
        .fontDesign(.rounded)
        .modelContainer(container)
        .environment(GameService(modelContext: container.mainContext,
                                 stepsService: FakeStepsService()))
}
