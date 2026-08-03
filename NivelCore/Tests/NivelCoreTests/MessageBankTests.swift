import XCTest
@testable import NivelCore

final class MessageBankTests: XCTestCase {
    func testBankHasAllContextsWithEnoughVariety() throws {
        let bank = try MessageBank.load()
        for context in MessageContext.allCases {
            XCTAssertGreaterThanOrEqual(bank.messages(for: context).count, 12, "\(context) trop pauvre")
        }
    }

    func testPickAvoidsImmediateRepetition() throws {
        let bank = try MessageBank.load()
        var lastID: String? = nil
        for _ in 0..<50 {
            let msg = bank.pick(context: .morning, excluding: lastID, name: "Michaël", value: nil)
            XCTAssertNotEqual(msg.id, lastID)
            lastID = msg.id
        }
    }

    func testPlaceholdersAreSubstituted() throws {
        let bank = try MessageBank.load()
        let msg = bank.pick(context: .afterMealLog, excluding: nil, name: "Marion", value: 20)
        XCTAssertFalse(msg.text.contains("{name}"))
        XCTAssertFalse(msg.text.contains("{value}"))
    }

    func testAfterActivityMessagesSubstituteValue() throws {
        let bank = try MessageBank.load()
        for _ in 0..<20 {
            let msg = bank.pick(context: .afterActivity, excluding: nil, name: "Marion", value: 30)
            XCTAssertFalse(msg.text.contains("{name}"))
            XCTAssertFalse(msg.text.contains("{value}"))
        }
    }

    /// Douze textes exactement (spec v1.11 §10), aucun {value} : le rappel posture n'a
    /// pas de nombre à substituer, contrairement à afterActivity/afterMealLog.
    func testPostureReminderALesDouzeMessages() throws {
        let bank = try MessageBank.load()
        let messages = bank.messages(for: .postureReminder)
        XCTAssertEqual(messages.count, 12)
        for msg in messages {
            XCTAssertFalse(msg.text.contains("{value}"), msg.id)
        }
    }

    /// Ton de la banque (spec §1.1, §7.4) : jamais d'injonction, jamais de reproche.
    /// Le repli sur "tu n'as pas" / "tu dois" / "il faut" attrape la formulation qui
    /// culpabiliserait, symétrique de ce que l'app refuse partout ailleurs.
    func testAucunReprocheNiInjonctionDansLesMessagesPosture() throws {
        let bank = try MessageBank.load()
        let banned = ["tu n'as pas", "tu dois", "il faut", "tu n'as rien fait", "oublié"]
        for msg in bank.messages(for: .postureReminder) {
            let lowered = msg.text.lowercased()
            for phrase in banned {
                XCTAssertFalse(lowered.contains(phrase), "\(msg.id) : « \(phrase) » ressemble à un reproche")
            }
        }
    }

    /// Règle de langage explicite (spec §1.1) : l'app ne nomme jamais la zone par le
    /// terme familier, seulement "Posture" / "Nuque et haut du dos".
    func testAucunMessageNeDitLeMotBanni() throws {
        let bank = try MessageBank.load()
        for msg in bank.messages(for: .postureReminder) {
            XCTAssertFalse(msg.text.lowercased().contains("bison"), msg.id)
        }
    }
}
