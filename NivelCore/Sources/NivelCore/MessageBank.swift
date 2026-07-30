import Foundation

public enum MessageContext: String, Codable, CaseIterable, Sendable {
    case morning, midday, evening, afterMealLog, afterActivity, afterWeighIn, weighReminder,
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
            guard let ctx = MessageContext(rawValue: key) else {
                assertionFailure("messages.json: unknown context key '\(key)'")
                continue
            }
            store[ctx] = msgs
        }
        return MessageBank(store: store)
    }

    public func messages(for context: MessageContext) -> [NivelitoMessage] { store[context] ?? [] }

    /// Choix aléatoire hors dernier message utilisé, avec substitution {name}/{value} (spec §8).
    ///
    /// Contrat : les contextes dont les messages contiennent `{value}` (`afterMealLog`,
    /// `afterActivity`, `levelUp`, `questCompleted`) requièrent un `value` non nil — sinon le placeholder
    /// survit dans le texte (assert en debug, silencieux en release).
    ///
    /// Si le seul message du contexte est celui exclu, il est réutilisé (la répétition
    /// vaut mieux qu'un texte hors contexte) ; le fallback générique ne sert que si le
    /// contexte est réellement vide.
    public func pick(context: MessageContext, excluding lastID: String?, name: String, value: Int?) -> NivelitoMessage {
        let all = messages(for: context)
        let candidates = all.filter { $0.id != lastID }
        let chosen = candidates.randomElement()
            ?? all.randomElement()
            ?? NivelitoMessage(id: "fallback", text: "Salut {name} !")
        var text = chosen.text.replacingOccurrences(of: "{name}", with: name)
        if let value { text = text.replacingOccurrences(of: "{value}", with: String(value)) }
        assert(!(value == nil && text.contains("{value}")),
               "MessageBank.pick: message '\(chosen.id)' (\(context)) contient {value} mais value est nil")
        return NivelitoMessage(id: chosen.id, text: text)
    }
}
