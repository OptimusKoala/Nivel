// Shared/Formatting.swift
import Foundation

extension Int {
    /// "8000" → "8 000" (groupement français, espace fine insécable).
    var frFormatted: String {
        formatted(.number.locale(Locale(identifier: "fr_FR")))
    }
}
