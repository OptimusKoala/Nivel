import Foundation

public enum MessageContext: String, Codable, CaseIterable, Sendable {
    case morning, midday, evening, afterMealLog, afterWeighIn, weighReminder,
         levelUp, badge, questCompleted, stepsEncouragement, overTarget, comeback, fun
}

public struct NivelitoMessage: Codable, Identifiable, Sendable {
    public let id: String
    public let text: String
}

public struct MessageBank: Sendable {
    private let store: [MessageContext: [NivelitoMessage]]

    public static func load() throws -> MessageBank {
        let raw: [String: [NivelitoMessage]] = try Catalogs.load("messages")
        var store: [MessageContext: [NivelitoMessage]] = [:]
        for (key, msgs) in raw {
            guard let ctx = MessageContext(rawValue: key) else { continue }
            store[ctx] = msgs
        }
        return MessageBank(store: store)
    }

    public func messages(for context: MessageContext) -> [NivelitoMessage] { store[context] ?? [] }

    /// Choix aléatoire hors dernier message utilisé, avec substitution {name}/{value} (spec §8).
    public func pick(context: MessageContext, excluding lastID: String?, name: String, value: Int?) -> NivelitoMessage {
        let candidates = messages(for: context).filter { $0.id != lastID }
        let chosen = candidates.randomElement() ?? NivelitoMessage(id: "fallback", text: "Salut {name} !")
        var text = chosen.text.replacingOccurrences(of: "{name}", with: name)
        if let value { text = text.replacingOccurrences(of: "{value}", with: String(value)) }
        return NivelitoMessage(id: chosen.id, text: text)
    }
}
