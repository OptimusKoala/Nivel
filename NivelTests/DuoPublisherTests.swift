// NivelTests/DuoPublisherTests.swift
// L'identité publique d'une entrée (spec 1.15 §3.4) : `MealEntry` et `ActivityEntry`
// gagnent un `publicID`, seule cible possible d'un cœur du duo.
import XCTest
import NivelCore
@testable import Nivel

final class DuoPublisherTests: XCTestCase {

    /// Une entrée neuve naît SANS identifiant, comme toutes celles d'avant la 1.15.
    /// C'est le point de la tâche, et il est contre-intuitif : on attendrait un
    /// `UUID().uuidString` dès la naissance. Mais le défaut est porté par la
    /// DÉCLARATION, pour garder la migration légère, et un défaut de déclaration
    /// SwiftData n'offre aucune garantie d'être évalué une fois par ligne à la
    /// migration — une centaine d'entrées existantes pourraient hériter du MÊME
    /// identifiant, ce qui est inacceptable pour une valeur qui sert de cible à un
    /// cœur. La chaîne vide est une sentinelle sans ambiguïté, et le remplissage se
    /// fait plus tard, à la volée, sur un seul chemin.
    func testUnRepasNeufNaitSansIdentifiantPublic() {
        let repas = MealEntry(slot: .lunch, estimatedKcal: 420)
        XCTAssertEqual(repas.publicID, "")
    }

    /// Même règle et même unique chemin pour une activité : rien dans l'`init` ne
    /// permet d'en fabriquer une qui naîtrait déjà identifiée.
    func testUneActiviteNeuveNaitSansIdentifiantPublic() {
        let activite = ActivityEntry(kind: .activity, refID: "bike",
                                     durationMinutes: 20, estimatedKcal: 120)
        XCTAssertEqual(activite.publicID, "")
    }
}
