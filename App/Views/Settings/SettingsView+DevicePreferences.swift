// App/Views/Settings/SettingsView+DevicePreferences.swift
// Sections "Son", "Programme posture" et "Thème" des réglages (spec §4.5, §4.11) :
// préférences PAR APPAREIL qui vivent dans UserDefaults (SoundSettings, ThemeStore,
// PosturePlanSettings). Son et thème n'appellent donc pas le `save()` local ; le
// programme posture fait exception (voir postureSection) puisqu'allumer le
// programme doit AUSSI poser une clé sur le profil SwiftData (spec v1.11 §3).

import SwiftUI
import NivelCore

extension SettingsContent {
    // MARK: - Son

    /// Préférence PAR APPAREIL (comme le thème) : elle vit dans UserDefaults, pas
    /// dans SwiftData, donc aucun `save()` ici. Elle n'entre pas non plus dans
    /// l'instantané du widget, donc pas de `syncWidget()` non plus.
    var soundSection: some View {
        // `@Bindable` local plutôt qu'un Binding get/set à la main : la propriété n'a
        // aucun effet de bord à l'écriture, contrairement aux rappels qui doivent
        // réassigner un dictionnaire SwiftData puis re-planifier.
        @Bindable var sound = SoundSettings.shared
        return section("Son") {
            Toggle(isOn: $sound.timerSoundEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Son du timer").font(.subheadline.weight(.semibold))
                    Text("sonne même en mode silencieux")
                        .font(.caption).foregroundStyle(Theme.subtext)
                }
            }
        }
    }

    // MARK: - Programme posture

    /// Interrupteur PAR APPAREIL (spec v1.11 §3), éteint par défaut. Contrairement
    /// au son ou au thème, l'allumer a un effet SwiftData : `PosturePlanSettings
    /// .setEnabled` pose `profile.remindersEnabled["posture"]` puis replanifie —
    /// sans quoi le rappel de 21 h naîtrait éteint (piège documenté v1.9). D'où le
    /// `Binding` fait à la main plutôt qu'un `@Bindable` direct sur `isEnabled`.
    ///
    /// Sous-titre honnête (spec §1.1) : décrit la zone travaillée, ne promet aucun
    /// résultat, et n'écrit jamais "bosse de bison".
    var postureSection: some View {
        section("Programme posture") {
            Toggle(isOn: postureBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Programme posture").font(.subheadline.weight(.semibold))
                    Text("Exercices doux pour la nuque et le haut du dos, avec un rappel chaque soir à 21 h.")
                        .font(.caption).foregroundStyle(Theme.subtext)
                }
            }
        }
    }

    private var postureBinding: Binding<Bool> {
        Binding(
            get: { PosturePlanSettings.shared.isEnabled },
            set: { PosturePlanSettings.shared.setEnabled($0, on: profile) }
        )
    }

    // MARK: - Thème

    /// Choix de la palette (v1.1) — PAR APPAREIL : persisté dans UserDefaults
    /// par ThemeStore, indépendant du profil SwiftData. Le changement re-rend
    /// toute l'app instantanément (façade Theme + @Observable).
    var themeSection: some View {
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
}

/// Carte de sélection d'une palette : pastille d'aperçu (fond du thème +
/// points primaire/accent), glyphe + nom, coche animée sur la sélection.
private struct ThemeSwatchCard: View {
    let palette: ThemePalette
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                swatch
                HStack(spacing: 5) {
                    CozyIcon(name: palette.icon, size: 17)
                        .foregroundStyle(Theme.text)
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
                    CozyIcon(name: "icon_check", size: 21)
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
