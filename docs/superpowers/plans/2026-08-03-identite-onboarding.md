# Identité à l'onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer les deux cartes de profil en dur (Michaël / Marion) de la page 2 de l'onboarding par un choix Homme/Femme plus la saisie libre du prénom, et rendre ce prénom modifiable dans les Réglages.

**Architecture :** La règle de nettoyage du prénom part dans `NivelCore` (pure, testée en 0,04 s) parce que deux écrans la partagent. Les deux décisions d'interface — « peut-on quitter la page 2 ? » et « faut-il persister cette frappe ? » — restent des fonctions statiques pures sur leurs vues respectives, comme `ActivityLogSheet.wheelValueOnCustomTap`, ce qui les rend testables sans piloter SwiftUI. Le `@State sex` de l'onboarding devient optionnel pour que « pas encore choisi » soit un état représentable.

**Tech Stack :** Swift 6, SwiftUI, SwiftData, XCTest. Projet Xcode généré par XcodeGen depuis `project.yml`.

**Spec :** `docs/superpowers/specs/2026-08-03-identite-onboarding-design.md`

---

## Ce qu'il faut savoir avant de commencer

**Le projet Xcode est généré.** Ne jamais éditer `Nivel.xcodeproj` à la main. Les targets listent des **répertoires** (`sources: [NivelTests]`), donc tout nouveau fichier de test exige un `xcodegen generate` avant que `xcodebuild` le voie. `NivelCore` est un package SPM : ses nouveaux fichiers ne demandent aucune régénération.

**Deux suites de tests, deux vitesses.**

```sh
# Logique pure — 156 tests en ~0,04 s. À lancer en boucle.
cd NivelCore && swift test

# Intégration app (SwiftData, vues) sur simulateur — lent, plusieurs minutes.
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

**Comment ce codebase teste une vue.** Il ne pilote pas SwiftUI. Il extrait la décision en `static func` pure sur la vue et la teste directement (`ActivityLogSheetTests`, `SessionPlayerTests`). La `struct` et la `static func` doivent donc être `internal` — **pas `private`** — pour être visibles via `@testable import Nivel`. C'est la seule raison pour laquelle elles ne sont pas privées ; ne pas « nettoyer » ça.

**Langue.** Tout est en français : identifiants d'interface, libellés, commentaires, noms de tests, messages de commit. Les commentaires expliquent *pourquoi*, jamais *quoi*.

**Fichiers concernés :**

| Fichier | Rôle |
|---|---|
| Créer `NivelCore/Sources/NivelCore/ProfileName.swift` | Règle unique de nettoyage du prénom, partagée par les deux écrans |
| Créer `NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift` | Tests de cette règle |
| Modifier `App/Views/Onboarding/OnboardingFlow.swift` | `sex` optionnel, `IdentityPage`, fin du repli « Michaël » |
| Créer `NivelTests/OnboardingIdentityTests.swift` | Test de la garde du bouton Continuer |
| Modifier `App/Views/Settings/SettingsView.swift` | Prénom en `TextField` |
| Créer `NivelTests/ProfileNameSettingsTests.swift` | Test : un prénom vide n'écrase jamais celui persisté |
| Modifier `project.yml` | Version 1.12 (build 13) |

**Ordre des tâches.** La tâche 1 livre la brique que les tâches 2 et 3 consomment. Les tâches 2 et 3 sont ensuite indépendantes l'une de l'autre.

---

## Task 1 : la règle de nettoyage du prénom, dans NivelCore

Deux écrans saisissent le prénom. Un seul endroit doit décider ce qu'est un prénom acceptable, sinon l'un des deux pourrait persister ce que l'autre refuse.

**Files:**
- Create: `NivelCore/Sources/NivelCore/ProfileName.swift`
- Test: `NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift`

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift` :

```swift
// NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift
// Règle de nettoyage du prénom (spec v1.12 §7). Partagée par l'onboarding et les
// Réglages : les deux écrans doivent accepter et refuser exactement la même chose.

import XCTest
@testable import NivelCore

final class ProfileNameTests: XCTestCase {

    // MARK: - sanitized

    func testRetireLesEspacesDeTeteEtDeQueue() {
        XCTAssertEqual(ProfileName.sanitized("  Michaël  "), "Michaël")
        XCTAssertEqual(ProfileName.sanitized("\nMarion\n"), "Marion")
    }

    /// Le vrai piège d'un trim naïf : un prénom composé ou en deux mots contient
    /// des espaces et des tirets légitimes, qui doivent survivre intacts.
    func testPreserveLesPrenomsComposes() {
        XCTAssertEqual(ProfileName.sanitized("Jean-Marc"), "Jean-Marc")
        XCTAssertEqual(ProfileName.sanitized("  Marie Claire  "), "Marie Claire")
    }

    func testUneChaineDEspacesDevientVide() {
        XCTAssertEqual(ProfileName.sanitized("   "), "")
        XCTAssertEqual(ProfileName.sanitized("\t\n "), "")
    }

    func testLaCasseNEstPasTouchee() {
        // Le nettoyage ne corrige pas la casse : c'est le clavier qui capitalise
        // (textInputAutocapitalization), et « de Broglie » doit rester possible.
        XCTAssertEqual(ProfileName.sanitized("michaël"), "michaël")
    }

    // MARK: - isAcceptable

    func testAcceptableQuandIlResteQuelqueChose() {
        XCTAssertTrue(ProfileName.isAcceptable("Michaël"))
        XCTAssertTrue(ProfileName.isAcceptable("  Marion  "))
        XCTAssertTrue(ProfileName.isAcceptable("X"))
    }

    func testRefuseLeVideEtLesEspacesSeuls() {
        XCTAssertFalse(ProfileName.isAcceptable(""))
        XCTAssertFalse(ProfileName.isAcceptable("   "))
        XCTAssertFalse(ProfileName.isAcceptable("\n\t"))
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
cd NivelCore && swift test --filter ProfileNameTests
```

Attendu : échec de **compilation**, `cannot find 'ProfileName' in scope`. C'est le bon échec : le type n'existe pas encore.

- [ ] **Step 3 : écrire l'implémentation minimale**

Créer `NivelCore/Sources/NivelCore/ProfileName.swift` :

```swift
// NivelCore/Sources/NivelCore/ProfileName.swift
// Règle unique de nettoyage du prénom (spec v1.12 §5 et §6). Deux écrans le
// saisissent — l'onboarding et les Réglages — et un seul endroit doit décider ce
// qu'est un prénom acceptable, sinon l'un pourrait persister ce que l'autre refuse.

import Foundation

public enum ProfileName {
    /// Prénom débarrassé de ses espaces et retours à la ligne de tête et de queue.
    /// Les espaces intérieurs sont préservés : « Marie Claire » est un prénom.
    public static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Acceptable = il reste quelque chose après nettoyage. Un prénom vide
    /// laisserait l'Accueil et le widget muets sans qu'aucun écran le signale.
    public static func isAcceptable(_ raw: String) -> Bool {
        !sanitized(raw).isEmpty
    }
}
```

- [ ] **Step 4 : lancer le test pour vérifier qu'il passe**

```sh
cd NivelCore && swift test --filter ProfileNameTests
```

Attendu : `Executed 6 tests, with 0 failures`.

- [ ] **Step 5 : lancer toute la suite core pour vérifier qu'on n'a rien cassé**

```sh
cd NivelCore && swift test
```

Attendu : les 156 tests existants + 6 nouveaux, 0 échec.

- [ ] **Step 6 : commit**

```sh
git add NivelCore/Sources/NivelCore/ProfileName.swift \
        NivelCore/Tests/NivelCoreTests/ProfileNameTests.swift
git commit -m "feat(core): ProfileName, règle unique de nettoyage du prénom"
```

---

## Task 2 : la page 2 de l'onboarding devient `IdentityPage`

Trois changements liés dans le même fichier : `sex` devient optionnel, la page de choix devient un formulaire, le repli « Michaël » disparaît. Ils vont ensemble — séparer laisserait le fichier non compilable entre deux commits.

**Files:**
- Modify: `App/Views/Onboarding/OnboardingFlow.swift`
- Test: `NivelTests/OnboardingIdentityTests.swift` (nouveau fichier → `xcodegen generate` requis)

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NivelTests/OnboardingIdentityTests.swift` :

```swift
// NivelTests/OnboardingIdentityTests.swift
// Garde du bouton Continuer de la page Identité (spec v1.12 §3 et §7). Même
// approche qu'ActivityLogSheetTests : la décision est une fonction pure statique
// sur la vue, testable sans piloter SwiftUI.

import XCTest
import NivelCore
@testable import Nivel

final class OnboardingIdentityTests: XCTestCase {

    private func canLeave(_ name: String, _ sex: Sex?) -> Bool {
        OnboardingFlow.canLeaveIdentity(name: name, sex: sex)
    }

    /// Le cas nominal.
    func testPrenomEtSexeRenseignesLaissentPasser() {
        XCTAssertTrue(canLeave("Michaël", .male))
        XCTAssertTrue(canLeave("Marion", .female))
    }

    /// La raison d'être de l'optionnel : sans choix explicite, l'objectif kcal
    /// serait calculé sur un sexe que personne n'a confirmé.
    func testSexeNonChoisiBloque() {
        XCTAssertFalse(canLeave("Michaël", nil))
    }

    func testPrenomVideBloque() {
        XCTAssertFalse(canLeave("", .male))
    }

    /// Une barre d'espaces n'est pas un prénom — sinon le repli supprimé
    /// reviendrait par la porte de derrière, sous forme d'un profil nommé « » .
    func testPrenomDEspacesBloque() {
        XCTAssertFalse(canLeave("   ", .male))
        XCTAssertFalse(canLeave("\n\t", .female))
    }

    /// Un prénom entouré d'espaces est valide : c'est la frappe normale au clavier.
    func testPrenomEntoureDEspacesLaissePasser() {
        XCTAssertTrue(canLeave("  Michaël  ", .male))
    }
}
```

- [ ] **Step 2 : régénérer le projet puis vérifier que le test échoue**

```sh
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NivelTests/OnboardingIdentityTests test
```

Attendu : échec de compilation, `type 'OnboardingFlow' has no member 'canLeaveIdentity'`.

Si `xcodegen` est introuvable : `brew install xcodegen`. Si le simulateur nommé n'existe pas, lister les cibles disponibles avec `xcrun simctl list devices available` et substituer un iPhone présent.

- [ ] **Step 3 : rendre `sex` optionnel dans le flux**

Dans `App/Views/Onboarding/OnboardingFlow.swift`, remplacer la déclaration :

```swift
    @State private var sex: Sex = .male
```

par :

```swift
    // Optionnel volontairement : « pas encore choisi » doit être représentable,
    // sinon la carte Homme paraîtrait pré-sélectionnée sur un écran qui demande
    // de choisir, et l'objectif kcal serait calculé sur un sexe non confirmé.
    @State private var sex: Sex?
```

- [ ] **Step 4 : ajouter la liaison dérivée et la garde statique**

Toujours dans le même fichier, dans la section `// MARK: - Valeurs dérivées`, juste avant `weightKg`, ajouter :

```swift
    /// Le picker de la page Infos travaille sur un `Sex` non optionnel. Le repli
    /// est inatteignable : on ne quitte pas la page Identité sans avoir choisi.
    private var sexBinding: Binding<Sex> {
        Binding(get: { sex ?? .male }, set: { sex = $0 })
    }
```

Puis, à la fin de la même section, la garde du bouton — `static` et **non `private`**, pour être testable via `@testable import Nivel` :

```swift
    /// Décision de la page Identité : les deux entrées doivent être renseignées.
    /// Extraite en fonction pure pour être testable sans piloter SwiftUI.
    static func canLeaveIdentity(name: String, sex: Sex?) -> Bool {
        sex != nil && ProfileName.isAcceptable(name)
    }
```

- [ ] **Step 5 : brancher la nouvelle page dans le `switch`**

Remplacer, dans `body` :

```swift
                    case 1: ProfileChoicePage(onChoose: choose(profile:))
```

par :

```swift
                    case 1: IdentityPage(
                        name: $name,
                        sex: $sex,
                        canContinue: Self.canLeaveIdentity(name: name, sex: sex),
                        onContinue: advance
                    )
```

Et remplacer, dans le même `switch`, la ligne `sex: $sex,` de l'appel à `InfosPage` par :

```swift
                        sex: sexBinding,
```

- [ ] **Step 6 : supprimer `choose(profile:)` et corriger les lectures de `sex`**

Supprimer entièrement la fonction devenue inutile (section `// MARK: - Navigation`) :

```swift
    private func choose(profile chosen: (name: String, sex: Sex)) {
        name = chosen.name
        sex = chosen.sex
        advance()
    }
```

Dans `computedTarget`, remplacer `sex: sex,` par :

```swift
            sex: sex ?? .male,
```

Dans `complete()`, remplacer la ligne du prénom :

```swift
            name: name.isEmpty ? "Michaël" : name,
            sex: sex,
```

par :

```swift
            // Pas de repli : la page Identité garantit un prénom non vide.
            name: ProfileName.sanitized(name),
            sex: sex ?? .male,
```

- [ ] **Step 7 : remplacer `ProfileChoicePage` par `IdentityPage`**

Remplacer tout le bloc `// MARK: - Page 2 : Choix du profil` et la `struct ProfileChoicePage` par :

```swift
// MARK: - Page 2 : Identité

private struct IdentityPage: View {
    @Binding var name: String
    @Binding var sex: Sex?
    let canContinue: Bool
    let onContinue: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    field("Je suis") {
                        HStack(spacing: 12) {
                            sexCard(.male, avatar: "boy", label: "Homme")
                            sexCard(.female, avatar: "girl", label: "Femme")
                        }
                    }
                    field("Mon prénom") {
                        TextField("Ton prénom", text: $name)
                            .font(.headline)
                            .focused($nameFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { if canContinue { onContinue() } }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("Continuer", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            NivelitoView(expression: .happy, size: 60)
            SpeechBubble(text: "Et toi, tu es qui ?")
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Même gabarit que l'`infoCard` de la page Infos : les deux pages se suivent,
    /// elles doivent se ressembler.
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // Les deux Nivelito illustrés (Avatars/boy, Avatars/girl) et non des glyphes
    // cozy : un glyphe monochrome de 28 pt ne fait pas un visage, et l'app a déjà
    // un langage d'illustrations couleur. Décoratifs : le label porte le sens.
    // L'état retenu reprend le vocabulaire d'`activityRow` (bordure + fond orange
    // clair) : cet écran n'a pas de coche, il doit dire « sélectionné » autrement.
    private func sexCard(_ value: Sex, avatar: String, label: String) -> some View {
        let isSelected = sex == value
        return Button {
            sex = value
            nameFocused = true
        } label: {
            VStack(spacing: 8) {
                Image(decorative: "Avatars/\(avatar)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text(label).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Theme.orange.opacity(0.10) : Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Theme.orange : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
```

- [ ] **Step 8 : lancer le test pour vérifier qu'il passe**

```sh
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NivelTests/OnboardingIdentityTests test
```

Attendu : `Executed 5 tests, with 0 failures`.

- [ ] **Step 9 : vérifier l'écran dans le simulateur**

C'est un changement purement visuel : les tests ne disent rien de ce qu'on voit. Lancer l'app sur un simulateur **vierge** (Device → Erase All Content and Settings, sinon un profil existe déjà et l'onboarding est sauté) et contrôler quatre choses :

1. Aucune carte n'est pré-sélectionnée à l'arrivée, et « Continuer » est grisé.
2. Taper Homme puis Femme déplace bien la bordure orange.
3. « Continuer » s'active dès qu'une carte **et** un prénom sont là.
4. Le clavier ne masque pas le bouton (la page défile).

Puis terminer l'onboarding et vérifier que l'Accueil affiche bien le prénom saisi.

- [ ] **Step 10 : commit**

```sh
git add App/Views/Onboarding/OnboardingFlow.swift NivelTests/OnboardingIdentityTests.swift
git commit -m "feat(app): l'onboarding demande Homme/Femme puis le prénom"
```

Le `.xcodeproj` régénéré est suivi par git : s'il a changé, l'inclure dans ce commit.

---

## Task 3 : prénom modifiable dans les Réglages

Conséquence directe de la saisie libre : sans ça, une faute de frappe à l'onboarding est définitive alors que le prénom s'affiche sur l'Accueil et dans les widgets.

**Files:**
- Modify: `App/Views/Settings/SettingsView.swift`
- Test: `NivelTests/ProfileNameSettingsTests.swift`

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NivelTests/ProfileNameSettingsTests.swift` :

```swift
// NivelTests/ProfileNameSettingsTests.swift
// Le champ Prénom des Réglages ne doit jamais persister un prénom vide (spec
// v1.12 §6). Même mécanique que l'objectif kcal, testée de la même façon : la
// décision « faut-il persister cette frappe ? » est une fonction pure.

import XCTest
import NivelCore
@testable import Nivel

final class ProfileNameSettingsTests: XCTestCase {

    private func commit(_ typed: String, current: String = "Michaël") -> String? {
        SettingsContent.nameToCommit(typed, current: current)
    }

    /// Le cas nominal : un prénom différent est persisté, nettoyé.
    func testUnNouveauPrenomEstPersisteNettoye() {
        XCTAssertEqual(commit("Marion"), "Marion")
        XCTAssertEqual(commit("  Marion  "), "Marion")
    }

    /// Le vrai risque du champ libre : vider le champ ne doit pas laisser un
    /// profil sans nom, qui rendrait l'Accueil et le widget muets en silence.
    func testUnChampVideNePersisteRien() {
        XCTAssertNil(commit(""))
        XCTAssertNil(commit("   "))
        XCTAssertNil(commit("\n\t"))
    }

    /// Rien à écrire quand la valeur nettoyée est déjà celle persistée : évite un
    /// save() et une synchro widget à chaque frappe qui ne change rien.
    func testIdentiqueNePersisteRien() {
        XCTAssertNil(commit("Michaël"))
        XCTAssertNil(commit("  Michaël  "))
    }
}
```

- [ ] **Step 2 : régénérer puis vérifier que le test échoue**

```sh
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NivelTests/ProfileNameSettingsTests test
```

Attendu : échec de compilation, `type 'SettingsContent' has no member 'nameToCommit'`.

- [ ] **Step 3 : ajouter l'état du champ**

Dans `App/Views/Settings/SettingsView.swift`, à côté de `kcalText` et `kcalFocused` :

```swift
    /// Tampon du prénom, comme `kcalText` : une frappe invalide ne doit jamais
    /// atteindre le profil persisté.
    @State private var nameText = ""
    @FocusState private var nameFocused: Bool
```

- [ ] **Step 4 : rendre la ligne Prénom éditable**

Remplacer, dans `profileSection` :

```swift
            row("Prénom") {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(Theme.subtext)
            }
```

par :

```swift
            row("Prénom") {
                TextField("Ton prénom", text: $nameText)
                    .font(.headline)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)
                    // Le helper `row` place un Spacer avant son contenu. Un
                    // DatePicker a une taille intrinsèque et s'en accommode ; un
                    // TextField non, il se battrait avec le Spacer pour la place.
                    // On réclame donc le reste de la ligne — la zone tapable
                    // couvre alors toute la droite de la rangée.
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
```

- [ ] **Step 5 : brancher initialisation, commit et restauration**

Dans le chaînage de modificateurs de `body`, à côté de ceux de `kcalText`. Compléter le `.onAppear` existant :

```swift
        .onAppear {
            kcalText = String(profile.dailyCalorieTarget)
            nameText = profile.name
        }
```

et ajouter, après les deux `.onChange` de kcal :

```swift
        .onChange(of: nameText) { _, text in commitName(text) }
        .onChange(of: nameFocused) { _, focused in
            // Sortie de champ : on réaffiche le prénom réellement persisté, donc
            // un champ vidé puis abandonné retrouve l'ancien prénom.
            if !focused { nameText = profile.name }
        }
```

- [ ] **Step 6 : ajouter la décision et son application**

Dans la section `// MARK: - Actions`, à côté de `commitKcal` :

```swift
    /// Prénom à persister, ou nil si cette frappe ne doit rien changer. `static`
    /// et pure pour être testable sans profil SwiftData ni SwiftUI.
    static func nameToCommit(_ text: String, current: String) -> String? {
        guard ProfileName.isAcceptable(text) else { return nil }
        let cleaned = ProfileName.sanitized(text)
        return cleaned == current ? nil : cleaned
    }

    private func commitName(_ text: String) {
        guard let name = Self.nameToCommit(text, current: profile.name) else { return }
        profile.name = name
        save()
    }
```

`save()` couvre déjà la synchronisation du widget — son commentaire mentionne explicitement le prénom comme faisant partie du snapshot. Ne rien ajouter de ce côté.

- [ ] **Step 7 : lancer le test pour vérifier qu'il passe**

```sh
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:NivelTests/ProfileNameSettingsTests test
```

Attendu : `Executed 3 tests, with 0 failures`.

- [ ] **Step 8 : vérifier dans le simulateur**

Ouvrir les Réglages et contrôler le comportement que les tests ne voient pas :

1. Renommer, fermer les Réglages, les réouvrir : le nouveau prénom est là.
2. Vider le champ et fermer le clavier : l'ancien prénom revient.
3. L'Accueil et le widget affichent le nouveau prénom (pour le widget, le rafraîchissement peut prendre un instant).

- [ ] **Step 9 : commit**

```sh
git add App/Views/Settings/SettingsView.swift NivelTests/ProfileNameSettingsTests.swift
git commit -m "feat(app): le prénom est modifiable dans les Réglages"
```

---

## Task 4 : suite complète et version

- [ ] **Step 1 : lancer les deux suites en entier**

```sh
cd NivelCore && swift test && cd ..
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Attendu : 0 échec des deux côtés. Les tests d'onboarding existants (`WidgetSyncTests.testNilWhileOnboardingNotDone`, `AppSmokeTests`) doivent passer sans modification — s'ils échouent, c'est une régression réelle à corriger, pas un test à ajuster.

- [ ] **Step 2 : monter la version**

Dans `project.yml`, aux **deux** emplacements (target `Nivel` ligne ~32 et target `NivelWidgets` ligne ~62) — les deux doivent rester identiques :

```yaml
        CFBundleShortVersionString: "1.12"
        CFBundleVersion: "13"
```

- [ ] **Step 3 : régénérer et vérifier que ça build**

```sh
xcodegen generate
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Attendu : `BUILD SUCCEEDED`.

- [ ] **Step 4 : mettre à jour le compteur de tests du README**

Le badge et le schéma du README annoncent « 156 core + 86 app ». Remplacer par les nombres réellement affichés par les deux suites à l'étape 1 — 162 core et 94 app si tout a été ajouté comme prévu, mais **prendre les chiffres réels**, pas ceux-là.

- [ ] **Step 5 : commit**

```sh
git add project.yml Nivel.xcodeproj README.md
git commit -m "chore: version 1.12 (build 13)"
```

---

## Vérification finale

- [ ] Les deux suites passent en entier, chiffres à l'appui.
- [ ] `git grep -n '"Michaël"' App/` ne renvoie plus que des `#Preview` et la dédicace « Fait avec 🧡 pour Michaël & Marion » — aucun repli, aucune condition.
- [ ] Onboarding parcouru sur simulateur vierge avec un prénom qui n'est ni Michaël ni Marion, et ce prénom apparaît sur l'Accueil.
- [ ] Le prénom se modifie dans les Réglages et ne peut pas être vidé.
