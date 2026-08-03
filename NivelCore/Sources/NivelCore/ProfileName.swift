// NivelCore/Sources/NivelCore/ProfileName.swift
// Règle unique de nettoyage du prénom (spec v1.12 §5 et §6). Deux écrans le
// saisissent — l'onboarding et les Réglages — et un seul endroit doit décider ce
// qu'est un prénom acceptable, sinon l'un pourrait persister ce que l'autre refuse.

import Foundation

public enum ProfileName {
    /// Prénom débarrassé de ses espaces et retours à la ligne de tête et de queue.
    /// Les espaces intérieurs sont préservés : « Marie Claire » est un prénom.
    public static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Acceptable = il reste quelque chose après nettoyage. Un prénom vide
    /// laisserait l'Accueil et le widget muets sans qu'aucun écran le signale.
    public static func isAcceptable(_ raw: String) -> Bool {
        !sanitized(raw).isEmpty
    }
}
