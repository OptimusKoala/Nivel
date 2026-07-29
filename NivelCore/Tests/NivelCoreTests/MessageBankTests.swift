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
}
