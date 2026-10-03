# iOS custom recipes — implementation plan

In the code a "preset" is a **recipe** (`FilmRecipe`). The Mac has a full library
(save, update, rename, duplicate, delete, reorder, canister, import and export as
`.granularrecipe`). The phone can only *pick* from `FilmRecipe.builtIns +
savedRecipes`, and nothing on the phone can make a saved recipe. This plan
brings the phone up to parity without touching the Mac app's behavior.

## Where things are today

- `Sources/GranularCore/FilmRecipe.swift`: `FilmRecipe`, `builtIns`,
  `uniqueName(_:among:)`, `duplicateName(for:among:)` (public).
- `Sources/GranularCore/RecipeAdjustments.swift`: `applyingAdjustments(of:)`,
  which keeps id/name/canister and takes the look from another recipe.
- `Sources/GranularCore/RecipeFile.swift`: the `.granularrecipe` format, encode
  and forgiving decode.
- `Sources/GranularCore/RecipeKey.swift`: UserDefaults keys, shared by Mac and
  phone (`recipes.saved` holds `[FilmRecipe]` JSON).
- `Sources/Granular/AppModel+Recipes.swift`, `AppModel+RecipeFiles.swift`: the
  Mac's library operations. **The reference for behavior.** Mac-only (AppKit).
- `Sources/Granular/CanisterLibrary.swift` (`CanisterDesign.library`,
  `.resolved(for:)`) and `FilmCanisterView.swift` (`CanisterStyle`,
  `FilmCanisterView`): already compiled into the iOS target by explicit
  reference in `iOS/Granular.xcodeproj`.
- `iOS/Granular/Darkroom.swift`: owns `recipe`, `selectedRecipeID`,
  `savedRecipes` (read-only today), undo for the look, persistence.
- `iOS/Granular/RecipeMenu.swift`: the picker menu, opened from the canister in
  Instant and the recipe capsule in Edit (`EditView.swift`, `EditBar`).
- `iOS/Granular/` is a **file-system synchronized group**: new `.swift` files
  dropped in that folder join the target with no pbxproj edit.

## 1. Core: a testable `RecipeLibrary` (GranularCore)

New `Sources/GranularCore/RecipeLibrary.swift`: a `public struct
RecipeLibrary: Equatable, Sendable` holding `saved: [FilmRecipe]`, with pure
mutating operations mirroring the Mac's semantics. No UI, no UserDefaults.

```swift
public struct RecipeLibrary {
    public var saved: [FilmRecipe]
    public var all: [FilmRecipe] { FilmRecipe.builtIns + saved }
    public static func newID() -> String            // "custom-<UUID>"
    public func contains(savedID:) -> Bool
    // Returns the new recipe, or nil for an empty (trimmed) name.
    public mutating func save(_ look: FilmRecipe, named: String, canister: String?) -> FilmRecipe?
    // Writes look's adjustments into saved recipe `id`; returns the updated recipe.
    public mutating func update(id: String, with look: FilmRecipe) -> FilmRecipe?
    // False for empty names or a case-insensitive clash with another recipe (built-ins included).
    public mutating func rename(id: String, to: String) -> Bool
    public mutating func setCanister(_ canister: String?, for id: String)
    // Copy inserted after the original if saved, else at the end. Canister passed in
    // (the caller resolves it, since CanisterDesign isn't in Core).
    public mutating func duplicate(id: String, canister: String?) -> FilmRecipe?
    public mutating func delete(id: String)
    public mutating func move(fromOffsets: IndexSet, toOffset: Int)
    // Fresh id, unique name; appended. Returns what was added.
    public mutating func importing(_ recipes: [FilmRecipe]) -> [FilmRecipe]
}
```

Notes:
- `save` names collide-free via `FilmRecipe.uniqueName` against `all` names.
  (Mac's save doesn't uniquify; the phone should, since there's no list beside
  the field to show the clash.)
- `IndexSet.move` lives in SwiftUI; implement `move` by hand in Core (or
  `import Foundation` only and write the remove/insert), since GranularCore
  must not import SwiftUI.
- Do **not** refactor the Mac `AppModel` onto this in this change.

Tests: `Tests/GranularCoreTests/RecipeLibraryTests.swift` (Swift Testing,
`@Test` free functions like the existing files). Cover save (trim, empty →
nil, unique name, new id prefix, canister kept), update keeps id/name/canister,
rename clash with built-in and with saved (case-insensitive) and self-rename
allowed, duplicate placement for saved vs built-in and its name, delete, move,
importing gives fresh ids and unique names among themselves and existing ones.

## 2. Darkroom: library operations (iOS)

In `iOS/Granular/Darkroom.swift`, keep `savedRecipes` as the public read
surface (everything already uses it) but back the operations with
`RecipeLibrary`. Add a `// MARK: Library` section:

- `saveCurrentAsRecipe(named:canister:) -> FilmRecipe?`: saves `recipe` and
  selects the new one (look unchanged, now unmodified).
- `updateSelectedRecipe()`: only when `selectedRecipeID` is a saved recipe;
  sets `recipe` to the updated one.
- `canUpdateSelectedRecipe: Bool` = modified && selected is saved.
- `renameRecipe(id:to:) -> Bool`: if it's the selected one, also rename
  `recipe` (keep it in sync, as the Mac does).
- `setCanister(_:forRecipe:)`: same sync to `recipe` when selected.
- `duplicateRecipe(id:) -> FilmRecipe?`: canister =
  `CanisterDesign.resolved(for: original).id`.
- `deleteRecipe(id:)`: if selected, fall back to `classic35` *keeping the
  look*: `selectedRecipeID = classic35.id; recipe =
  FilmRecipe.classic35.applyingAdjustments(of: recipe)` (as the Mac does).
- `moveSavedRecipes(fromOffsets:toOffset:)`.
- `importRecipes(from urls: [URL]) -> (imported: [FilmRecipe], failures: [(String, Error)])`:
  security-scoped access, `RecipeFile.decode(..., fallbackName: file name)`,
  then `RecipeLibrary.importing`.
- `persistRecipes()`: encode `savedRecipes` to `RecipeKey.saved`; call it from
  every mutation, then `persistRecipe()` where the selection/look changed.

Undo: these library actions are **not** on the look's undo stack. Library
changes that also change `recipe` (update, delete-selected, save) must not push
an undo step either: wrap the `recipe` assignment so `recordChange` skips it
(reuse `isRestoring`, or add a small `withoutRecordingUndo { }` helper).
Clear `undoStack`/`redoStack` entries whose `id` no longer exists? No: keep it
simple; `restore` already ignores ids that aren't available.

## 3. Recipe files on iOS

- Add `iOS/Info.plist` (**outside** `iOS/Granular/`, so the synchronized group
  doesn't copy it as a resource) containing only `UTExportedTypeDeclarations`
  (same declaration as `Resources/Info.plist`, minus `UTTypeIconFile`),
  `CFBundleDocumentTypes` (role Viewer, rank Owner, content type
  `com.danielmccullum.granular.recipe`), and `LSSupportsOpeningDocumentsInPlace
  = false`. Set `INFOPLIST_FILE = Info.plist` in both build configurations of
  the app target in `project.pbxproj`; keep `GENERATE_INFOPLIST_FILE = YES` so
  the existing `INFOPLIST_KEY_*` settings still merge.
- New `iOS/Granular/RecipeTransfer.swift`:
  - `extension UTType { static let granularRecipe = UTType(exportedAs: RecipeFile.typeIdentifier, conformingTo: .json) }`
  - `struct RecipeDocument: Transferable` wrapping a `FilmRecipe`, with a
    `FileRepresentation(exportedContentType: .granularRecipe)` that writes
    `RecipeFile(recipe:).encoded()` to a temp file named
    `RecipeFile.fileName(for:)` so it arrives in Files/AirDrop with the
    recipe's name; `SentTransferredFile(url)`.
- `GranularApp`: `.onOpenURL { url in }` on `CameraView()`; if
  `RecipeFile.isRecipeFile(url)`, call `darkroom.importRecipes(from: [url])`
  and open the library sheet showing the result (state described below).

## 4. UI

Follow the app's existing iOS idioms: Liquid Glass (`.glassEffect`,
`.buttonStyle(.glass)`), `.sensoryFeedback`, `withAnimation(.smooth)`, short
doc comments in the house voice (see the existing files). **No visible
instructional/hint text anywhere** (no "Swipe to delete", no "Tap to…"
captions). Text fields commit on submit and on dismissal.

### 4a. RecipeMenu additions (`RecipeMenu.swift`)

Above the picker, in a `Section`:
- `Update “<name>”` (`arrow.triangle.2.circlepath`): when `canUpdateSelectedRecipe`.
- `Save as Recipe…` (`plus`): always; opens the Save sheet.
- `Revert to …` stays where it is.
Below the picker: `Recipes…` (`square.stack`): opens the Recipe Library sheet.

The menu lives in two places, so sheet presentation state should live on
`Darkroom` (or a tiny `@Observable` on it): e.g. `var recipeSheet:
RecipeSheet?` with `enum RecipeSheet: Identifiable { case save, library }`,
presented once from `CameraView` with `.sheet(item:)`. That also gives
`onOpenURL` a way to open the library.

### 4b. Save sheet: `iOS/Granular/SaveRecipeSheet.swift`

- `NavigationStack`, title "Save Recipe", Cancel / Save toolbar buttons (Save
  disabled while the trimmed name is empty), `.presentationDetents([.medium])`.
- A large `FilmCanisterView` showing the chosen canister with the typed name
  (`CanisterStyle` for a recipe with that canister; look at how
  `CanisterStyle(recipe:isModified:)` builds a style).
- `TextField("Name", …)` focused on appear, `.submitLabel(.done)`, submit saves.
  Prefill: the current recipe's name if it's a saved recipe, else "My Recipe";
  select-all isn't needed.
- A horizontal `ScrollView` of every `CanisterDesign.library` design as a small
  canister, the selected one ringed; default is
  `CanisterDesign.resolved(for: current).id` for a saved recipe, else a random
  `CanisterDesign.automatic` element chosen once on appear.
- On save: `darkroom.saveCurrentAsRecipe`, `.success` haptic, dismiss.

### 4c. Recipe Library sheet: `iOS/Granular/RecipeLibrarySheet.swift`

- `NavigationStack` + `List`, title "Recipes", large detents, Done button.
- Section "My Recipes" (only if non-empty) then "Built In". Each row: small
  canister (`FilmCanisterView`, ~36pt tall like the Edit bar's), name,
  trailing checkmark when it's the recipe in use and unmodified
  (`!isRecipeModified && id == selectedRecipeID`).
- Tap a row: `selectRecipe`, dismiss.
- Saved rows: `.onDelete` and `.onMove` (with an `EditButton` in the toolbar),
  `.contextMenu` with Rename, Duplicate, Canister (submenu `Picker` over
  `CanisterDesign.library`), Share (`ShareLink(item: RecipeDocument(...),
  preview: SharePreview(name))`), Delete (destructive).
- Built-in rows: context menu with Duplicate and Share only.
- Delete via context menu asks with `.confirmationDialog`; swipe delete
  doesn't (the swipe is the confirmation).
- Rename: an `.alert` with a `TextField`, Cancel/Rename; if
  `renameRecipe` returns false, keep the alert's name unchanged and show
  nothing extra (the button is just disabled when the trimmed name is empty or
  matches another recipe; compute that up front).
- Toolbar Import (`square.and.arrow.down`): `.fileImporter(allowedContentTypes:
  [.granularRecipe], allowsMultipleSelection: true)` → `importRecipes`. On
  failures show one `.alert` with the first error's `localizedDescription`,
  titled like the Mac's (“<file>” couldn’t be imported. / N files couldn’t be
  imported.).
- After importing (from the button or `onOpenURL`), scroll to / briefly
  highlight the last imported row (`ScrollViewReader`), nothing more.

## 5. Verification

1. `swift test` from the repo root: all existing tests plus the new
   `RecipeLibraryTests` pass.
2. Build the iOS app:
   `xcodebuild -project iOS/Granular.xcodeproj -scheme Granular -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build`
   (list schemes with `xcodebuild -list -project iOS/Granular.xcodeproj` if
   the name differs). Zero new warnings in the files touched.
3. Mac app still builds: `swift build`.
4. Run on the booted iPhone 18 Pro simulator and exercise: edit a slider →
   Save as Recipe → it appears selected and unmodified; edit again → Update;
   rename, change canister (Instant canister reflects it), duplicate a
   built-in, reorder, delete the selected one (look stays, recipe falls back
   to Classic 35 shown as modified), share a recipe to Files and import it
   back (gets a "2" name).

## Out of scope

- Moving the Mac's `AppModel` onto `RecipeLibrary`.
- iCloud sync of recipes between Mac and phone.
- Undo for library changes on the phone.
