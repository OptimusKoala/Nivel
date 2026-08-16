// App/Services/DuoNotifications.swift
// La notification locale d'un cœur reçu (spec 1.15 §3.7).
//
// Le détour qui explique tout ce fichier : `CKQuerySubscription`, qui permettrait de ne
// réveiller le téléphone QUE pour un cœur, **n'existe pas dans la base partagée**. L'invité
// n'a droit qu'à un abonnement de ZONE, déclenché par n'importe quel changement, y compris
// une mise à jour d'anneau qui arrive plusieurs fois par jour.
//
// Donc, des deux côtés : un abonnement silencieux (aucun `alertBody`), le système réveille
// l'app, elle va chercher les changements, et **c'est elle** qui poste la notification, si
// et seulement si de nouveaux cœurs la visent. Ce détour donne le texte exact et n'alerte
// jamais pour rien.
//
// Trois limites à connaître, et le §3.7 les assume :
//
// - les réveils silencieux sont ORDINAIREMENT immédiats, mais iOS peut les retarder selon
//   la batterie et l'usage ;
// - **aucun réveil n'est envoyé si l'app a été tuée depuis le sélecteur d'apps** ;
// - si les notifications sont refusées, les cœurs arrivent sans bruit.
//
// Dans les trois cas le rattrapage se fait à l'ouverture, par la bulle bordée de Nivelito.
// C'est la raison d'être de ce signal visuel : il n'est pas un doublon décoratif, il est le
// seul chemin qui reste quand celui-ci ne passe pas.
//
// Conventions reprises de `NotificationService` : champs capturés AVANT tout `await`, garde
// sur l'autorisation, et aucun crash si elle est refusée.

import Foundation
import UserNotifications
import NivelCore

@MainActor
enum DuoNotifications {

    /// Identifiant de la demande. Fixe, donc une notification de cœur remplace la
    /// précédente au lieu de s'empiler : à deux, dix cœurs dans la journée ne doivent pas
    /// faire dix lignes dans le centre de notifications.
    nonisolated static let requestID = "nivel.duo.like"

    // MARK: - Le texte

    /// Le titre : une phrase de la banque, contexte `duoLikeReceived`, avec le prénom du
    /// partenaire en `{name}` (décision de spec, §3.7). Les mêmes phrases servent à la bulle
    /// de l'accueil, si bien qu'un cœur reçu ne dit jamais deux fois la même chose.
    ///
    /// Partenaire encore inconnu — il a aimé avant que son instantané ne nous parvienne —
    /// ou banque illisible : on dit quand même quelque chose. Une notification vide serait
    /// pire que tout, puisqu'elle a déjà fait vibrer le téléphone.
    nonisolated static func title(partner: String?, bank: MessageBank?) -> String {
        let nom = partnerDisplayName(partner)
        guard let bank else { return "\(nom) t'a envoyé un cœur 💛" }
        return bank.pick(context: .duoLikeReceived, excluding: nil, name: nom, value: nil).text
    }

    /// Comment on NOMME le partenaire quand on ne connaît pas encore son prénom : il a aimé
    /// avant que son instantané n'arrive, ce qui est le cas normal des premières secondes
    /// d'un duo.
    ///
    /// **Une seule fonction pour les deux surfaces**, et ce n'est pas de l'économie : le
    /// §3.7 veut que la notification et la bulle disent la même chose, et elles divergeaient
    /// précisément ici. La bulle passait un prénom optionnel à `nivelitoSays`, qui retombe
    /// sur le prénom du PROFIL — c'est-à-dire le sien. Elle annonçait donc « Michaël a jeté
    /// un œil à ta journée, et ça lui a plu » à Michaël.
    nonisolated static func partnerDisplayName(_ partner: String?) -> String {
        guard let partner, !partner.trimmingCharacters(in: .whitespaces).isEmpty
        else { return "Ton duo" }
        return partner
    }

    /// Le corps : le libellé de l'événement aimé, tel qu'il a été publié. Il voyage dans
    /// l'enregistrement du cœur (§3.3) précisément pour cela — au réveil, le fil n'est pas
    /// forcément sous la main, et on ne veut pas d'une requête de plus pour trois mots.
    ///
    /// Plusieurs cœurs arrivés dans le même réveil : une seule notification, qui les compte.
    /// En poster deux ferait vibrer deux fois pour un même geste.
    nonisolated static func body(for likes: [DuoLike]) -> String {
        guard likes.count == 1 else { return "\(likes.count) moments de ta journée" }
        let titre = likes[0].eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Titre absent : le titre de la notification porte déjà l'essentiel, et se taire
        // pour si peu serait pire.
        return titre.isEmpty ? "un moment de ta journée" : titre
    }

    // MARK: - Notifier, ou se taire

    /// L'interrupteur des réglages coupe la NOTIFICATION, jamais la réception : le cœur
    /// arrive, se range, s'affichera sur l'entrée et dans la bulle. On cesse seulement d'en
    /// être prévenu.
    nonisolated static func shouldNotify(newLikes: Int, enabled: Bool) -> Bool {
        newLikes > 0 && enabled
    }

    /// Les cœurs qu'on n'a pas encore annoncés. Un réveil rend les enregistrements CHANGÉS,
    /// et un cœur peut revenir dans un lot pour une raison qui ne nous regarde pas : sans ce
    /// tri, le téléphone sonnerait deux fois pour le même geste.
    nonisolated static func unseen(_ likes: [DuoLike], knownEventIDs: Set<String>) -> [DuoLike] {
        likes.filter { !knownEventIDs.contains($0.eventID) }
    }

    // MARK: - Poster

    /// Poste la notification, si elle a lieu d'être. Ne lève rien, n'affiche rien en cas de
    /// refus d'autorisation : un cœur non annoncé n'est pas une panne à signaler.
    ///
    /// Le texte est calculé AVANT le premier `await`, comme `NotificationService` le fait
    /// pour les champs du profil : ce qui suit une suspension ne doit dépendre d'aucun état
    /// qui aurait pu bouger entre-temps.
    static func post(for likes: [DuoLike], partner: String?, enabled: Bool) async {
        guard shouldNotify(newLikes: likes.count, enabled: enabled) else { return }

        let titre = title(partner: partner, bank: try? MessageBank.load())
        let corps = body(for: likes)

        let center = UNUserNotificationCenter.current()
        let reglages = await center.notificationSettings()
        guard reglages.authorizationStatus == .authorized
                || reglages.authorizationStatus == .provisional else { return }

        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = corps
        contenu.sound = .default

        // `trigger: nil` : livrée tout de suite. On est déjà réveillé par le serveur, il n'y
        // a rien à programmer.
        try? await center.add(UNNotificationRequest(identifier: requestID, content: contenu,
                                                    trigger: nil))
    }
}
