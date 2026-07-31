// App/Services/DeepLink.swift
// Deep links des widgets (spec widgets §7) — parse PUR, testé dans DeepLinkTests.

import Foundation

enum DeepLink: Equatable {
    case logMeal

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "nivel" else { return nil }
        return url.host == "log-meal" ? .logMeal : nil
    }
}
