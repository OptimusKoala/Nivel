import Foundation

public enum MessageContext: String, Codable, CaseIterable, Sendable {
    case morning, midday, evening, afterMealLog, afterActivity, afterWeighIn, weighReminder,
         levelUp, badge, questCompleted, stepsEncouragement, overTarget, comeback, fun
    /// Rappel de 21 h du programme posture (spec v1.11 §10). Contexte séparé de `.evening`,
    /// qui parle du dîner : mêmes principes que `.weighReminder` en v1. La clé JSON
    /// correspondante DOIT exister dans messages.json, sinon `MessageBank.load` déclenche
    /// `assertionFailure` en debug (silencieux en release) — les deux s'ajoutent ensemble.
    case postureReminder
    /// Rappel de 19 h du programme muscu maison (spec v1.14 §4.4). Contexte séparé de
    /// `.postureReminder` : réutiliser ce dernier ferait dire à Nivelito un texte
    /// d'étirement de la nuque pour une séance de pompes. Comme pour la posture, la clé
    /// JSON correspondante DOIT exister dans messages.json, sinon `MessageBank.load`
    /// déclenche `assertionFailure` en debug (silencieux en release) — les deux
    /// s'ajoutent ensemble.
    case muscuReminder
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
        // Le symétrique du garde ci-dessus, et le plus important des deux. Une clé JSON
        // inconnue est bruyante : elle vient d'être écrite, on la cherche. Un CONTEXTE
        // SANS CLÉ est silencieux — la boucle ci-dessus itère les clés du JSON, donc un
        // cas d'enum ajouté sans ses textes n'y est jamais visité : `messages(for:)`
        // rend [], et `pick` retombe sur « Salut {name} ! ». Une notification générique
        // à la place d'un rappel, en release comme en debug, sans rien dans les logs.
        // Possible seulement parce que `MessageContext` est `CaseIterable`.
        for context in MessageContext.allCases where (store[context] ?? []).isEmpty {
            assertionFailure("messages.json: contexte '\(context.rawValue)' sans textes")
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
