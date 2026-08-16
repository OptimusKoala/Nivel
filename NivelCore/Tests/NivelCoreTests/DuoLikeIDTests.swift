import XCTest
@testable import NivelCore

final class DuoLikeIDTests: XCTestCase {

    /// Le nom est DÉTERMINISTE, et c'est toute la raison d'être du type : aimer deux
    /// fois écrit deux fois le même enregistrement au lieu d'en créer un doublon, et
    /// retirer un cœur devient une suppression par nom, sans requête préalable.
    func testLeNomEstDeterministeEtRecomposable() {
        XCTAssertEqual(DuoLikeID.recordName(giver: "G1", event: "E1"), "like-G1-E1")
        XCTAssertEqual(DuoLikeID.recordName(giver: "G1", event: "E1"),
                       DuoLikeID.recordName(giver: "G1", event: "E1"))
    }

    /// Deux donneurs distincts sur le même événement : deux cœurs, deux
    /// enregistrements. Sans ça, le second écraserait le premier.
    func testDeuxDonneursDifferentsDonnentDeuxNomsDifferents() {
        XCTAssertNotEqual(DuoLikeID.recordName(giver: "G1", event: "E1"),
                          DuoLikeID.recordName(giver: "G2", event: "E1"))
    }

    /// Et le même donneur sur deux événements : aimer le déjeuner n'aime pas le dîner.
    func testDeuxEvenementsDifferentsDonnentDeuxNomsDifferents() {
        XCTAssertNotEqual(DuoLikeID.recordName(giver: "G1", event: "E1"),
                          DuoLikeID.recordName(giver: "G1", event: "E2"))
    }

    /// La question qui mérite d'être posée : le séparateur est un tiret, et les UUID en
    /// contiennent quatre chacun. Deux couples différents peuvent-ils produire le même
    /// nom ?
    ///
    /// Non, et la raison est mesurée : `UUID.uuidString` fait TOUJOURS 36 caractères
    /// (8-4-4-4-12). Les deux parts étant de longueur fixe, la découpe du nom est sans
    /// ambiguïté quels que soient les tirets internes. Ces couples croisés le vérifient.
    func testAucuneCollisionEntreUUIDMalgreLeursTiretsInternes() {
        let identifiants = ["0A8A8AEC-69AE-4875-A693-3FE243DF7978",
                            "0A8A8AEC-69AE-4875-A693-3FE243DF7979",
                            "1B7B7BFD-70BF-5986-B704-4EF354EA8A80"]
        var noms: Set<String> = []
        for donneur in identifiants {
            for evenement in identifiants {
                noms.insert(DuoLikeID.recordName(giver: donneur, event: evenement))
            }
        }
        XCTAssertEqual(noms.count, identifiants.count * identifiants.count)
    }

    /// La contrepartie de la réponse ci-dessus, et c'est elle qui compte pour la suite :
    /// l'absence de collision tient à la LONGUEUR FIXE des identifiants, pas au format
    /// du nom. Sur des chaînes quelconques, « like-A-B-C » se lit aussi bien
    /// (« A », « B-C ») que (« A-B », « C ») — ce test fige donc une PRÉCONDITION,
    /// pas une propriété du format : le jour où un identifiant de longueur variable
    /// passerait par ici, la garantie tomberait sans prévenir.
    func testLaGarantieTientALaLongueurFixeDesIdentifiantsPasAuFormat() {
        XCTAssertEqual(DuoLikeID.recordName(giver: "A", event: "B-C"),
                       DuoLikeID.recordName(giver: "A-B", event: "C"),
                       "Si ces deux noms diffèrent, le format a été rendu robuste : "
                           + "tant mieux, mais relis le commentaire de `recordName`.")
    }

    /// Le cas dégénéré de cette précondition, et il n'est PAS théorique : une entrée
    /// d'avant la 1.15 dont le `publicID` n'a pas encore été rempli porte la chaîne
    /// vide (Task 2). Deux entrées vides produiraient donc le même nom de cœur, et un
    /// cœur posé sur l'une apparaîtrait sur l'autre. Ce test le constate pour que ce ne
    /// soit découvert par personne : c'est à l'appelant de n'aimer que des événements
    /// identifiés.
    func testDeuxEvenementsSansIdentifiantPartageraientLeurCoeur() {
        XCTAssertEqual(DuoLikeID.recordName(giver: "G1", event: ""),
                       DuoLikeID.recordName(giver: "G1", event: ""))
        XCTAssertEqual(DuoLikeID.recordName(giver: "G1", event: ""), "like-G1-")
    }
}
