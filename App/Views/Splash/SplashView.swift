// App/Views/Splash/SplashView.swift
// Splash animé (spec §5) : à chaque lancement à froid, Nivelito apparaît avec un
// rebond doux (scale 0.3 → dépassement → 1 en spring), le logotype "Nivel" glisse
// dessous. ~1,5 s, skippable d'un tap — l'orchestration (durée, tap, fondu de
// sortie) vit dans RootView ; cette vue ne gère que son animation d'entrée.

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mascotVisible = false
    @State private var titleVisible = false

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                NivelitoView(expression: .happy, size: 150)
                    .scaleEffect(mascotVisible ? 1 : 0.3)
                    .opacity(mascotVisible ? 1 : 0)

                Text("Nivel")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible || reduceMotion ? 0 : 22)
            }
        }
        .onAppear {
            if reduceMotion {
                // Reduce Motion : simple fondu, pas de rebond ni de glissement.
                withAnimation(.easeIn(duration: 0.3)) {
                    mascotVisible = true
                    titleVisible = true
                }
            } else {
                // dampingFraction 0.55 → dépassement à ~1.05 avant de se poser à 1.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    mascotVisible = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
                    titleVisible = true
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .fontDesign(.rounded)
}
