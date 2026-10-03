import Foundation
import Testing
@testable import GranularCore

private func saved(_ names: String...) -> RecipeLibrary {
    var library = RecipeLibrary()
    for name in names {
        library.save(.classic35, named: name, canister: "ember")
    }
    return library
}

@Test func savingTrimsAndKeepsTheCanister() throws {
    var library = RecipeLibrary()
    let result = library.save(.classic35, named: "  Longmarch \n", canister: "kraft")
    let recipe = try #require(result)

    #expect(recipe.name == "Longmarch")
    #expect(recipe.canister == "kraft")
    #expect(recipe.id.hasPrefix("custom-"))
    #expect(library.saved == [recipe])
    #expect(library.contains(savedID: recipe.id))
}

@Test func savingAnEmptyNameDoesNothing() {
    var library = RecipeLibrary()

    let result = library.save(.classic35, named: " \n", canister: nil)

    #expect(result == nil)
    #expect(library.saved.isEmpty)
}

@Test func savingNumbersANameThatIsTaken() throws {
    var library = saved("Longmarch")
    let secondResult = library.save(.classic35, named: "longmarch", canister: nil)
    let builtInResult = library.save(.classic35, named: "Classic 35", canister: nil)
    let second = try #require(secondResult)
    let builtIn = try #require(builtInResult)

    #expect(second.name == "longmarch 2")
    #expect(builtIn.name == "Classic 35 2")
}

@Test func updatingKeepsIdentityNameAndCanister() throws {
    var library = saved("Longmarch")
    let original = library.saved[0]
    var look = FilmRecipe.builtIns[1]
    look.grain.seed = 99

    let result = library.update(id: original.id, with: look)
    let missing = library.update(id: "nope", with: look)
    let updated = try #require(result)

    #expect(updated.id == original.id)
    #expect(updated.name == "Longmarch")
    #expect(updated.canister == "ember")
    #expect(updated.grain.seed == 99)
    #expect(library.saved == [updated])
    #expect(missing == nil)
}

@Test func renamingRefusesClashesWhateverTheirCase() {
    var library = saved("Longmarch", "Dusk")
    let dusk = library.saved[1].id

    let clash = library.rename(id: dusk, to: "LONGMARCH")
    let builtIn = library.rename(id: dusk, to: "classic 35")
    let empty = library.rename(id: dusk, to: "  ")
    #expect(!clash && !builtIn && !empty)
    #expect(library.saved[1].name == "Dusk")

    let renamed = library.rename(id: dusk, to: " Evening ")
    #expect(renamed)
    #expect(library.saved[1].name == "Evening")
}

@Test func renamingToItsOwnNameInAnotherCaseIsAllowed() {
    var library = saved("Longmarch")

    let renamed = library.rename(id: library.saved[0].id, to: "LONGMARCH")

    #expect(renamed)
    #expect(library.saved[0].name == "LONGMARCH")
}

@Test func changingTheCanister() {
    var library = saved("Longmarch")
    let id = library.saved[0].id
    library.setCanister("kraft", for: id)

    #expect(library.saved[0].canister == "kraft")
}

@Test func duplicatingASavedRecipeSitsJustAfterIt() throws {
    var library = saved("One", "Two", "Three")
    let first = library.saved[0].id
    let result = library.duplicate(id: first, canister: "kraft")
    let copy = try #require(result)

    #expect(library.saved.map(\.name) == ["One", "One copy", "Two", "Three"])
    #expect(copy.canister == "kraft")
    #expect(copy.id != first)
}

@Test func duplicatingABuiltInGoesAtTheEnd() throws {
    var library = saved("One", "Two")
    let result = library.duplicate(id: FilmRecipe.classic35.id, canister: "ember")
    let missing = library.duplicate(id: "nope", canister: nil)
    let copy = try #require(result)

    #expect(library.saved.last == copy)
    #expect(copy.name == "Classic 35 copy")
    #expect(missing == nil)
}

@Test func deletingRemovesOnlyThatRecipe() {
    var library = saved("One", "Two")
    let id = library.saved[0].id
    library.delete(id: id)

    #expect(library.saved.map(\.name) == ["Two"])
}

@Test func movingFollowsArrayMoveSemantics() {
    var library = saved("A", "B", "C", "D")
    library.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(library.saved.map(\.name) == ["B", "C", "A", "D"])

    library.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
    #expect(library.saved.map(\.name) == ["D", "B", "C", "A"])

    library.move(fromOffsets: IndexSet([0, 1]), toOffset: 4)
    #expect(library.saved.map(\.name) == ["C", "A", "D", "B"])
}

@Test func importingGivesFreshIdentitiesAndUniqueNames() {
    var library = saved("Longmarch")
    var one = FilmRecipe.classic35
    one.id = "custom-same"
    one.name = "Longmarch"
    var two = one
    two.name = "Longmarch"

    let added = library.importing([one, two])

    #expect(added.map(\.name) == ["Longmarch 2", "Longmarch 3"])
    #expect(Set(added.map(\.id)).count == 2)
    #expect(!added.contains { $0.id == "custom-same" })
    #expect(library.saved.count == 3)
}
