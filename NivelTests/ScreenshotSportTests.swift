// NivelTests/ScreenshotSportTests.swift
// Le cadrage de la capture App Store `03-sport` (lot F, §7).
//
// Ce que cette suite tient, et qu'aucune autre ne voit :
//
// - la capture Sport s'ouvre bien sur « Ça pousse ». Le plan du lot F l'exige, et
//   l'écran ne la montre pas de lui-même : la section est TROISIÈME, vingt lignes
//   d'activités douces la précèdent, elle est donc à deux écrans de défilement. Le
//   mode captures l'y amène, et c'est cette règle-là — pas la mécanique du
//   défilement, qui ne se vérifie qu'à l'œil — qui est vérifiable ici ;
// - les écrans `session` et `step`, qui rendent le MÊME `SportView` sous leur feuille,
//   n'héritent pas de ce défilement ;
// - la section cadrée a de quoi remplir l'écran. Une capture est relue une fois par
//   version, à l'œil ; le jour où « Ça pousse » retomberait à trois activités,
//   l'image partirait chez Apple avec les deux tiers de la page en fond crème, et
//   rien d'autre ne le dirait.
import XCTest
import NivelCore
@testable import Nivel

final class ScreenshotSportTests: XCTestCase {
    /// Le processus de test n'a pas l'argument `--nivel-screenshots` : `initialSportSection`
    /// y répond donc toujours `nil`, et c'est la fonction pure — celle qui porte la règle —
    /// qui s'interroge, écran par écran.
    func testLaCaptureSportSOuvreSurLaSectionCaPousse() {
        XCTAssertEqual(ScreenshotMode.initialSportSection(for: .sport), .strong)
        XCTAssertEqual(ScreenshotMode.initialSportSection(for: .sport)?.frLabel, "Ça pousse",
                       "le plan du lot F demande « Ça pousse » sur 03-sport")
    }

    /// `session` et `step` montrent le lecteur de séance par-dessus le même écran :
    /// les défiler ne se verrait pas et ne ferait que dégrader le tirage.
    func testLesAutresEcransNHeritentPasDeCeDefilement() {
        for screen in [ScreenshotMode.Screen.home, .meallog, .activitylog, .meals,
                       .session, .step, .progress, .quests, .idees, .recette] {
            XCTAssertNil(ScreenshotMode.initialSportSection(for: screen),
                         "l'écran « \(screen.rawValue) » partirait défilé")
        }
    }

    /// Assez d'activités pour occuper l'écran sous son titre. Neuf tiennent dans le
    /// cadre du 6,9 pouces ; le seuil est plus bas que ça, il n'est pas là pour figer
    /// le catalogue mais pour attraper une section devenue trop maigre à photographier.
    func testLaSectionCadreeARemplirLEcran() throws {
        let activities = try Catalogs.activities()
        let cadree = try XCTUnwrap(ScreenshotMode.initialSportSection(for: .sport))
        XCTAssertGreaterThanOrEqual(cadree.activities(in: activities).count, 8,
                                    "« \(cadree.frLabel) » ne remplit plus la capture 03-sport")
    }
}
