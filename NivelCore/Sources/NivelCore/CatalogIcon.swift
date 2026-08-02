// NivelCore/Sources/NivelCore/CatalogIcon.swift
// Identité visuelle d'une entrée de catalogue (spec icônes catalogues §4).

import Foundation

/// Identité visuelle d'un badge, d'une quête ou d'un thème : un glyphe cozy, ou un emoji
/// là où l'emoji reste plus lisible — la nourriture, dont la couleur porte l'information
/// qu'un glyphe monochrome perdrait (spec §2.2).
///
/// Encodé sur UNE SEULE chaîne dans les JSON : un préfixe `icon_` ou `tab_` désigne un
/// asset du dossier `Icons/`, tout le reste est un emoji littéral. Deux champs auraient
/// alourdi 42 entrées pour trois exceptions. La contrepartie de cette règle de préfixe est
/// qu'un nom d'asset mal orthographié serait pris pour un emoji et s'afficherait en texte
/// brut : `CatalogIconTests` vérifie donc que chaque `.cozy` des catalogues résout.
public enum CatalogIcon: Codable, Hashable, Sendable {
    case cozy(String)
    case emoji(String)

    public init(rawValue: String) {
        self = rawValue.hasPrefix("icon_") || rawValue.hasPrefix("tab_")
            ? .cozy(rawValue) : .emoji(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .cozy(let value), .emoji(let value): value
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
