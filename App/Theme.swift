// App/Theme.swift
import SwiftUI

enum Theme {
    static let background = Color(hex: 0xFDF6EC)
    static let card = Color.white
    static let text = Color(hex: 0x5B4A3F)
    static let subtext = Color(hex: 0xB09A8A)
    static let orange = Color(hex: 0xF57C1F)
    static let accent = Color(hex: 0xF5B453)
    static let green = Color(hex: 0x7BC86C)
    static let blue = Color(hex: 0x4DA3C7)
    static let track = Color(hex: 0xF4E7DB)
    static let outline = Color(hex: 0x3A1220)

    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 22
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}
extension View { func card() -> some View { modifier(CardStyle()) } }
