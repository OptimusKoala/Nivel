import XCTest
@testable import NivelCore

final class DuoBadgeTests: XCTestCase {

    private func heure(_ h: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(h * 3_600)) }

    private func evenement(a date: Date) -> DuoEvent {
        DuoEvent(id: "E1", kind: .meal, at: date, title: "Salade", subtitle: "déjeuner")
    }

    /// La pastille s'allume dès qu'un événement du fil est postérieur à la dernière
    /// visite du profil.
    func testUnEvenementPosterieurALaDerniereVisiteAllumeLaPastille() {
        XCTAssertTrue(DuoBadge.hasNewActivity(feed: [evenement(a: heure(12))],
                                              lastSeenAt: heure(9)))
    }

    /// Et elle s'éteint à l'ouverture : tout le fil est alors antérieur à la visite.
    func testUnFilEntierementVuNAllumePasLaPastille() {
        XCTAssertFalse(DuoBadge.hasNewActivity(feed: [evenement(a: heure(8)),
                                                      evenement(a: heure(12))],
                                               lastSeenAt: heure(14)))
    }

    /// La frontière exacte : un événement horodaté À la seconde de la visite a été vu.
    /// Sans ce choix, le dernier événement de la page qu'on vient de fermer rallumerait
    /// la pastille aussitôt, et elle ne voudrait plus rien dire.
    func testUnEvenementALHeureExacteDeLaVisiteEstConsidereCommeVu() {
        XCTAssertFalse(DuoBadge.hasNewActivity(feed: [evenement(a: heure(10))],
                                               lastSeenAt: heure(10)))
    }

    /// Un seul événement neuf suffit, même noyé parmi des anciens.
    func testUnSeulEvenementNeufSuffit() {
        XCTAssertTrue(DuoBadge.hasNewActivity(
            feed: [evenement(a: heure(6)), evenement(a: heure(20)), evenement(a: heure(8))],
            lastSeenAt: heure(12)))
    }

    /// Jamais visité : tout fil non vide est une nouveauté, il n'y a pas de date à quoi
    /// le comparer.
    func testJamaisVisiteEtFilNonVideAllumeLaPastille() {
        XCTAssertTrue(DuoBadge.hasNewActivity(feed: [evenement(a: heure(9))],
                                              lastSeenAt: nil))
    }

    /// Le cas limite qui compte : jamais visité ET fil vide, donc PAS de pastille.
    /// Autrement elle s'allumerait le jour de l'appairage, avant que quiconque ait rien
    /// fait, et le premier signal du duo serait un faux — la pastille perdrait son sens
    /// avant même d'avoir servi.
    func testJamaisVisiteEtFilVideNAllumePasLaPastille() {
        XCTAssertFalse(DuoBadge.hasNewActivity(feed: [], lastSeenAt: nil))
    }

    /// Un fil vide n'allume jamais rien, visite ou pas.
    func testUnFilVideNAllumeJamaisLaPastille() {
        XCTAssertFalse(DuoBadge.hasNewActivity(feed: [], lastSeenAt: heure(9)))
    }
}
