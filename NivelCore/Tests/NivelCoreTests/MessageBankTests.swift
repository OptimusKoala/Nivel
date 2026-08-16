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

    /// Douze textes exactement pour CHAQUE rappel de programme (spec v1.11 §10,
    /// v1.14 §4.4), et aucun {value} : ces rappels n'ont pas de nombre à substituer,
    /// contrairement à afterActivity/afterMealLog.
    ///
    /// L'absence de {value} n'est pas cosmétique : le chemin notification appelle
    /// `pick(..., value: nil)` (`NotificationService.schedule`), donc un {value} glissé
    /// un jour dans un de ces textes partirait TEL QUEL dans la notification, avec un
    /// assert en debug seulement. Épinglé sur les deux contextes ensemble : la posture
    /// l'avait, les douze textes muscu seraient passés à côté d'un test resté sur
    /// `.postureReminder`.
    func testLesRappelsDeProgrammeOntDouzeMessagesSansValeur() throws {
        let bank = try MessageBank.load()
        for context in [MessageContext.postureReminder, .muscuReminder] {
            let messages = bank.messages(for: context)
            XCTAssertEqual(messages.count, 12, "\(context)")
            for msg in messages {
                XCTAssertFalse(msg.text.contains("{value}"), "\(context).\(msg.id)")
            }
        }
    }

    /// Ton de la banque (spec §1.1, §7.4) : jamais d'injonction, jamais de reproche.
    /// Le repli sur "tu n'as pas" / "tu dois" / "il faut" attrape la formulation qui
    /// culpabiliserait, symétrique de ce que l'app refuse partout ailleurs.
    ///
    /// Les DEUX contextes de programme, et non le seul rappel posture : ce sont les
    /// rappels d'un engagement qu'on a pris, donc ceux où la formulation glisse le plus
    /// facilement vers le reproche. La v1.14 y a ajouté douze textes muscu, qui seraient
    /// passés à côté d'un test resté sur `.postureReminder`.
    func testAucunReprocheNiInjonctionDansLesRappelsDeProgramme() throws {
        let bank = try MessageBank.load()
        let banned = ["tu n'as pas", "tu dois", "il faut", "tu n'as rien fait", "oublié"]
        for context in [MessageContext.postureReminder, .muscuReminder] {
            for msg in bank.messages(for: context) {
                let lowered = msg.text.lowercased()
                for phrase in banned {
                    XCTAssertFalse(lowered.contains(phrase),
                                   "\(context).\(msg.id) : « \(phrase) » ressemble à un reproche")
                }
            }
        }
    }

    /// Douze textes pour le cœur reçu (spec 1.15 §3.9), chacun portant {name} et aucun
    /// {value}.
    ///
    /// {name} est EXIGÉ ici, ce que les rappels de programme ne demandent pas, et pour
    /// une raison propre au duo : c'est le seul contexte du dépôt où {name} désigne le
    /// PARTENAIRE et non l'utilisateur. Un message sans lui dirait « quelqu'un a aimé ta
    /// journée » sans jamais nommer qui, ce qui vide la bulle de son sens.
    ///
    /// L'absence de {value} n'est pas cosmétique, c'est le même garde-fou que pour les
    /// rappels de programme : le chemin d'appel passe `value: nil`, donc un {value}
    /// glissé un jour dans un de ces textes partirait TEL QUEL dans la bulle, avec un
    /// assert en debug seulement.
    func testLesMessagesDeCoeurRecuOntDouzeTextesAvecLePrenomEtSansValeur() throws {
        let bank = try MessageBank.load()
        let messages = bank.messages(for: .duoLikeReceived)

        XCTAssertEqual(messages.count, 12)
        for msg in messages {
            XCTAssertTrue(msg.text.contains("{name}"),
                          "\(msg.id) ne nomme pas le partenaire")
            XCTAssertFalse(msg.text.contains("{value}"), msg.id)
        }

        // Et le chemin réel : rien ne doit survivre à la substitution avec value nil.
        for _ in 0..<20 {
            let msg = bank.pick(context: .duoLikeReceived, excluding: nil,
                                name: "Marion", value: nil)
            XCTAssertFalse(msg.text.contains("{name}"))
            XCTAssertFalse(msg.text.contains("{value}"))
            XCTAssertTrue(msg.text.contains("Marion"), msg.id)
        }
    }

    /// Le ton, et deux règles du dépôt sur des textes qui seront lus des dizaines de
    /// fois par deux personnes vivant ensemble : jamais de reproche ni d'injonction, et
    /// aucun tiret cadratin dans ce qui s'affiche.
    ///
    /// S'y ajoute une contrainte que seul le duo connaît : le partenaire peut être un
    /// homme ou une femme, et ces textes parlent de LUI. Toute forme accordée au genre
    /// (« passée », « contente », « ravi ») rendrait un message faux une fois sur deux.
    /// Le repli ci-dessous attrape les participes construits avec être, qui sont le
    /// piège le plus facile à écrire sans y penser.
    func testLeTonEtLesFormesDesMessagesDeCoeurRecu() throws {
        let bank = try MessageBank.load()
        let interdits = ["tu n'as pas", "tu dois", "il faut", "tu n'as rien fait", "oublié"]
        let accordes = ["est passé", "est venu", "est resté", "ravi", "content", "fier"]

        for msg in bank.messages(for: .duoLikeReceived) {
            let minuscule = msg.text.lowercased()
            for phrase in interdits {
                XCTAssertFalse(minuscule.contains(phrase),
                               "\(msg.id) : « \(phrase) » ressemble à un reproche")
            }
            for forme in accordes {
                XCTAssertFalse(minuscule.contains(forme),
                               "\(msg.id) : « \(forme) » s'accorde au genre du partenaire")
            }
            XCTAssertFalse(msg.text.contains("—"), "\(msg.id) : tiret cadratin")
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
