# Widget en mode teinté — avant / après (v1.13)

Le correctif du widget en mode teinté (spec v1.13 §3) ne peut pas être couvert par un
test : `\.widgetRenderingMode` est en lecture seule, et le remplacement des couleurs a
lieu dans WidgetKit, pas dans SwiftUI. Ces trois captures **sont** la preuve.

Toutes prises sur simulateur iPhone 17 (iOS 26.5), widget moyen posé sur l'écran
d'accueil, en pilotant Springboard.

| fichier | ce qu'il montre |
|---|---|
| `widget-transparent-avant.png` | Le bug signalé par Michaël. Nivelito réduit à une silhouette à oreilles, la bulle un rectangle blanc plein, « + Repas » une pastille blanche sans texte, la pastille de niveau une forme vide. |
| `widget-transparent-apres.png` | Style **Transparent** corrigé — celui que Michaël utilise. |
| `widget-teinte-apres.png` | Style **Teinté** corrigé. iOS 26 offre les deux, et tous deux passent le widget en `.accented`. |

Pour refaire la manipulation : styles d'écran d'accueil sous appui long → **Modifier** →
**Personnaliser**. Le snapshot du widget se pose à la main dans l'App Group (le mode
captures de l'app, lui, n'écrit rien : `widgetDefaults: nil`, à dessein) —
`xcrun simctl get_app_container <device> com.elitedangereuse.Nivel groups` donne le
chemin, la clé est `nivel.widget.snapshot` et la valeur un `WidgetSnapshot` en JSON.
