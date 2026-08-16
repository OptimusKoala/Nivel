// NivelTests/DuoProfileTests.swift
// La page du partenaire (spec 1.15 §3.9) : ses décisions, extraites de la vue.
//
// Une page ne se teste pas ; ce qu'elle dit, si. Et ce qu'elle dit compte plus ici que
// partout ailleurs dans l'app : c'est le seul écran de Nivel dont les phrases sont lues à
// propos de QUELQU'UN D'AUTRE. La règle zéro culpabilisation de la v1 y est donc éprouvée
// au mot, dans les deux sens — ne rien reprocher, et ne rien laisser croire de faux.

import XCTest
import NivelCore
@testable import Nivel

final class DuoProfileFreshnessTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 10_000)

    /// La ligne de fraîcheur n'est pas décorative : les chiffres PEUVENT être en retard
    /// (réseau absent, réveil différé, app tuée), et il vaut mieux le dire que laisser
    /// croire à un chiffre juste.
    func testLaLigneDeFraicheurSeLitEnFrancais() {
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(240)),
                       "mis à jour il y a 4 min")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(20)),
                       "mis à jour à l'instant")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(7_200)),
                       "mis à jour il y a 2 h")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(3 * 86_400)),
                       "mis à jour il y a 3 j")
    }

    /// Les bascules d'unité, là où une erreur d'un cran se voit : 59 s est encore
    /// « à l'instant », 60 s est déjà une minute.
    func testLesBasculesDUniteTombentAuBonEndroit() {
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(59)),
                       "mis à jour à l'instant")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(60)),
                       "mis à jour il y a 1 min")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(3_600)),
                       "mis à jour il y a 1 h")
        XCTAssertEqual(DuoProfileView.freshness(generatedAt: base,
                                                now: base.addingTimeInterval(86_400)),
                       "mis à jour il y a 1 j")
    }

    /// Horloges désaccordées entre deux iPhones : un instantané « du futur » ne doit pas
    /// afficher un âge négatif. Ça n'a rien de théorique, les deux appareils n'ont aucune
    /// raison d'être à la seconde près.
    func testUnInstantaneVenuDuFuturNAffichePasUnAgeNegatif() {
        let texte = DuoProfileView.freshness(generatedAt: base,
                                             now: base.addingTimeInterval(-500))

        XCTAssertEqual(texte, "mis à jour à l'instant")
        XCTAssertFalse(texte.contains("-"))
    }
}

final class DuoProfileToneTests: XCTestCase {

    /// Journée vide : on le dit sans reproche. Aucun « seulement », aucun « déjà », aucun
    /// « toujours rien ». Le reproche serait lu par quelqu'un d'AUTRE que celui qu'il vise,
    /// ce qui le rend plus lourd encore qu'ailleurs dans l'app.
    func testLeFilVideParleSansReproche() {
        let texte = DuoProfileView.emptyFeedText(partner: "Marion")

        XCTAssertEqual(texte, "Marion n'a rien noté pour l'instant")
        for interdit in ["seulement", "déjà", "toujours rien", "encore rien", "aucun effort",
                         "pas encore fait"] {
            XCTAssertFalse(texte.lowercased().contains(interdit), texte)
        }
        XCTAssertFalse(texte.contains("—"))
    }

    /// Partenaire sans prénom connu : la phrase tient quand même debout et ne laisse ni
    /// blanc ni « nil ».
    func testLeFilVideTientDeboutSansPrenom() {
        let texte = DuoProfileView.emptyFeedText(partner: nil)

        XCTAssertFalse(texte.isEmpty)
        XCTAssertFalse(texte.hasPrefix(" "))
        for fuite in ["nil", "Optional", "  "] {
            XCTAssertFalse(texte.contains(fuite), texte)
        }
    }

    /// Un instantané d'hier ne doit pas s'afficher comme la journée d'aujourd'hui : le fil
    /// se vide à minuit côté publication, mais le CACHE local, lui, porte encore la veille
    /// (spec §3.4).
    func testUnInstantaneDHierEstReconnuPerime() {
        XCTAssertTrue(DuoProfileView.isStale(dayKey: "2026-08-15", today: "2026-08-16"))
        XCTAssertFalse(DuoProfileView.isStale(dayKey: "2026-08-16", today: "2026-08-16"))
        // Un instantané « de demain » (horloges désaccordées, voyage) est traité comme
        // périmé lui aussi : ce n'est pas la journée qu'on regarde.
        XCTAssertTrue(DuoProfileView.isStale(dayKey: "2026-08-17", today: "2026-08-16"))
    }

    /// Ce qu'on montre alors : pas les chiffres de la veille maquillés en aujourd'hui, mais
    /// une phrase qui dit l'attente. Sans reproche, là encore : l'autre n'a rien fait de
    /// mal, son téléphone n'a simplement pas encore publié.
    func testUneJourneePerimeeLeDitSansReproche() {
        let texte = DuoProfileView.staleNotice(partner: "Marion")

        // Même tournure que sa voisine du même écran, celle de l'instantané jamais reçu :
        // deux phrases qui disent la même chose doivent la dire pareil.
        XCTAssertEqual(texte, "La journée de Marion n'est pas encore arrivée")
        for interdit in ["erreur", "échec", "problème", "seulement", "déjà"] {
            XCTAssertFalse(texte.lowercased().contains(interdit), texte)
        }
        XCTAssertFalse(texte.contains("—"))
    }

    /// L'avatar suit le sexe publié, avec les illustrations présentes depuis la v1.1.
    /// `sexRaw` voyage en clair : une valeur qu'une version future publierait ne doit pas
    /// laisser un trou à la place du visage.
    func testLAvatarSuitLeSexePublieEtNeLaisseJamaisDeTrou() {
        XCTAssertEqual(DuoProfileView.avatarName(sexRaw: "female"), "Avatars/girl")
        XCTAssertEqual(DuoProfileView.avatarName(sexRaw: "male"), "Avatars/boy")
        XCTAssertFalse(DuoProfileView.avatarName(sexRaw: "quelque chose d'inconnu").isEmpty)
    }
}

final class DuoFeedRowTests: XCTestCase {

    private func evenement(_ kind: DuoEvent.Kind) -> DuoEvent {
        DuoEvent(id: "E1", kind: kind, at: Date(timeIntervalSince1970: 5_000),
                 title: "Salade de lentilles", subtitle: "déjeuner, ~ 420 kcal")
    }

    /// Un événement de genre INCONNU — celui qu'une 1.16 publierait — reste affichable, avec
    /// une icône neutre. C'est toute la raison d'être du repli `unknown` : `title` et
    /// `subtitle` étant calculés à la publication, la ligne est parfaitement lisible, et la
    /// laisser tomber serait strictement pire que de la montrer sans son icône.
    func testUnGenreInconnuGardeUneIconeNeutreEtResteAffichable() {
        let neutre = DuoFeedRow.iconName(for: .unknown)

        XCTAssertFalse(neutre.isEmpty)
        XCTAssertNotEqual(neutre, DuoFeedRow.iconName(for: .meal))
        XCTAssertNotEqual(neutre, DuoFeedRow.iconName(for: .activity))
    }

    func testChaqueGenreConnuAsonIcone() {
        XCTAssertFalse(DuoFeedRow.iconName(for: .meal).isEmpty)
        XCTAssertFalse(DuoFeedRow.iconName(for: .activity).isEmpty)
        XCTAssertNotEqual(DuoFeedRow.iconName(for: .meal), DuoFeedRow.iconName(for: .activity))
    }

    /// Le cœur est un BOUTON, libellé « Aimer » ou « Ne plus aimer » suivi du nom de
    /// l'événement (spec §3.9) : jamais un glyphe décoratif, sans quoi VoiceOver
    /// annoncerait « bouton » sans dire de quoi, quatre fois de suite dans la même journée.
    func testLeCoeurEstUnBoutonQuiDitCeQuIlFaitEtSurQuoi() {
        XCTAssertEqual(DuoFeedRow.heartLabel(isLiked: false, eventTitle: "Salade de lentilles"),
                       "Aimer Salade de lentilles")
        XCTAssertEqual(DuoFeedRow.heartLabel(isLiked: true, eventTitle: "Salade de lentilles"),
                       "Ne plus aimer Salade de lentilles")
    }

    /// L'heure de la ligne, en français, sans secondes.
    func testLHeureDeLaLigneSeLitSansSecondes() {
        let midi = Date(timeIntervalSince1970: 1_786_881_600)  // 2026-08-16, 12 h UTC

        let texte = DuoFeedRow.time(for: midi, timeZone: TimeZone(identifier: "UTC")!)

        XCTAssertEqual(texte, "12:00")
    }

    /// Le sous-titre est celui du PUBLICATEUR, recopié tel quel : rien n'est recalculé ici,
    /// puisque le partenaire n'a pas forcément les mêmes catalogues (§3.4).
    func testLeSousTitreEstCeluiQuiAEtePublie() {
        XCTAssertEqual(evenement(.meal).subtitle, "déjeuner, ~ 420 kcal")
    }
}

// MARK: - Les cœurs envoyés

@MainActor
final class DuoGivenLikesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "nivel.tests.duolikes.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Un cœur envoyé hors ligne reste ALLUMÉ à l'écran, même quand la zone dit le
    /// contraire : c'est l'attente locale qui prime, jusqu'à ce que l'envoi passe ou soit
    /// abandonné. Sans cela, le cœur s'éteindrait tout seul sous le doigt au premier
    /// rafraîchissement, et on croirait avoir raté son geste.
    func testUneAttenteLocalePrimeSurCeQueDitLaZone() {
        XCTAssertEqual(DuoService.applying(["E2": true], to: ["E1"]), ["E1", "E2"])
        XCTAssertEqual(DuoService.applying(["E1": false], to: ["E1"]), [])
        XCTAssertEqual(DuoService.applying([:], to: ["E1"]), ["E1"])
    }

    /// Les cœurs que J'AI donnés sont persistés eux aussi : la page s'ouvre hors ligne sur
    /// le cache (§3.10), et un cœur qui s'y afficherait éteint donnerait envie de le
    /// renvoyer alors qu'il est bien parti.
    func testLesCoeursDonnesSurviventAuRelancement() {
        let identite = DuoIdentity(defaults: defaults)
        identite.givenLikeEventIDs = ["E1", "E2"]

        XCTAssertEqual(Set(DuoIdentity(defaults: defaults).givenLikeEventIDs), ["E1", "E2"])
    }

    /// Mais ils partent au désappairage, contrairement aux cœurs REÇUS : un cœur donné vit
    /// sur une entrée de l'autre, qu'on ne verra plus jamais. Le garder n'afficherait rien
    /// nulle part.
    func testLesCoeursDonnesPartentAuDesappairage() async {
        let identite = DuoIdentity(defaults: defaults)
        identite.createMemberID()
        identite.role = .guest
        identite.givenLikeEventIDs = ["E1"]
        identite.receivedLikeEventIDs = ["R1"]
        let service = DuoService(identity: identite, resolveTarget: { _ in nil })

        await service.unpair()

        XCTAssertTrue(identite.givenLikeEventIDs.isEmpty)
        XCTAssertEqual(identite.receivedLikeEventIDs, ["R1"], "les reçus, eux, restent")
    }

    /// Sans duo appairé, un tap sur un cœur ne part pas dans le vide : rien n'est résolu,
    /// rien n'est écrit. Le cas existe — la page peut rester ouverte pendant qu'on défait le
    /// duo depuis les réglages sur l'autre onglet.
    func testAimerSansDuoNeResoutMemePasLaZone() async {
        var resolutions = 0
        let service = DuoService(identity: DuoIdentity(defaults: defaults),
                                 resolveTarget: { _ in resolutions += 1; return nil })

        await service.toggleLike(on: DuoEvent(id: "E1", kind: .meal,
                                              at: Date(timeIntervalSince1970: 5_000),
                                              title: "Dîner", subtitle: "dîner, ~ 620 kcal"))

        XCTAssertEqual(resolutions, 0)
        XCTAssertTrue(service.givenLikeEventIDs.isEmpty)
    }
}
