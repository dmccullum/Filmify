import Foundation
import Testing
@testable import GranularCore

@Test func recipeFilesRoundTripWithTheirCanister() throws {
    var recipe = FilmRecipe.classic35
    recipe.id = "custom-1"
    recipe.name = "Longmarch"
    recipe.canister = "ember"
    recipe.tone.stock = .portra400
    recipe.grain.seed = 77

    let data = try RecipeFile(recipe: recipe).encoded()
    let decoded = try RecipeFile.decode(data, fallbackName: "Ignored")

    #expect(decoded.version == RecipeFile.currentVersion)
    #expect(decoded.recipe == recipe)
}

@Test func recipeFilesCarryAVersion() throws {
    let data = try RecipeFile(recipe: .classic35).encoded()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["version"] as? Int == RecipeFile.currentVersion)
    #expect(object["recipe"] is [String: Any])
}

@Test func recipeFilesWithoutAVersionReadAsTheFirst() throws {
    let json = """
    { "recipe": { "name": "Old Faithful", "grain": \(encodedJSON(GrainSettings(amount: 0.4))) } }
    """
    let decoded = try RecipeFile.decode(Data(json.utf8), fallbackName: "File")

    #expect(decoded.version == 1)
    #expect(decoded.recipe.name == "Old Faithful")
    #expect(decoded.recipe.grain.amount == 0.4)
}

@Test func partialRecipeFilesFillInDefaults() throws {
    let json = """
    { "version": 1, "recipe": { "tone": \(encodedJSON(FilmToneSettings(stock: .hp5))) } }
    """
    let decoded = try RecipeFile.decode(Data(json.utf8), fallbackName: "Found Roll")

    #expect(decoded.recipe.name == "Found Roll")
    #expect(decoded.recipe.id == "")
    #expect(decoded.recipe.tone.stock == .hp5)
    #expect(decoded.recipe.lightShaping == LightShapingSettings())
    #expect(decoded.recipe.diffusion == DiffusionSettings())
    #expect(decoded.recipe.halation == HalationSettings())
    #expect(decoded.recipe.grain == GrainSettings())
    #expect(decoded.recipe.canister == nil)
}

@Test func bareRecipesReadAsRecipeFiles() throws {
    var recipe = FilmRecipe.builtIns[3]
    recipe.canister = "kraft"
    let decoded = try RecipeFile.decode(JSONEncoder().encode(recipe), fallbackName: "File")

    #expect(decoded.recipe == recipe)
}

@Test func blankNamesFallBackToTheFileName() throws {
    let json = #"{ "version": 1, "recipe": { "name": "  ", "grain": \#(encodedJSON(GrainSettings())) } }"#
    let decoded = try RecipeFile.decode(Data(json.utf8), fallbackName: "Longmarch")

    #expect(decoded.recipe.name == "Longmarch")
}

@Test func laterVersionsLoadWhenTheyStillRead() throws {
    let json = """
    { "version": 7, "futureKey": true, "recipe": { "name": "Tomorrow", "sparkle": 0.5 } }
    """
    let decoded = try RecipeFile.decode(Data(json.utf8), fallbackName: "File")

    #expect(decoded.version == 7)
    #expect(decoded.recipe.name == "Tomorrow")
}

@Test func unreadableLaterVersionsSaySo() {
    let json = #"{ "version": 9, "recipe": "a different shape entirely" }"#

    #expect(throws: RecipeFileError.newerVersion(9)) {
        try RecipeFile.decode(Data(json.utf8), fallbackName: "File")
    }
}

@Test func filesThatArentRecipesAreTurnedAway() {
    for json in [#"{ "hello": "world" }"#, "[1, 2, 3]", "not json"] {
        #expect(throws: RecipeFileError.unreadable) {
            try RecipeFile.decode(Data(json.utf8), fallbackName: "File")
        }
    }
}

@Test func recipeFileNamesAreSafeForTheFinder() {
    var recipe = FilmRecipe.classic35
    #expect(RecipeFile.fileName(for: recipe) == "Classic 35.granularrecipe")

    recipe.name = "Day/Night: 2"
    #expect(RecipeFile.fileName(for: recipe) == "Day-Night- 2.granularrecipe")

    recipe.name = ".hidden"
    #expect(RecipeFile.fileName(for: recipe) == "Recipe.granularrecipe")

    #expect(RecipeFile.isRecipeFile(URL(filePath: "/tmp/Longmarch.GranularRecipe")))
    #expect(!RecipeFile.isRecipeFile(URL(filePath: "/tmp/Longmarch.json")))
}

@Test func uniqueRecipeNamesCountUpLikeTheFinder() {
    let names = ["Longmarch", "longmarch 2", "Classic 35"]

    #expect(FilmRecipe.uniqueName("Fresh", among: names) == "Fresh")
    #expect(FilmRecipe.uniqueName("Longmarch", among: names) == "Longmarch 3")
    #expect(FilmRecipe.uniqueName("Classic 35", among: names) == "Classic 35 2")
    #expect(FilmRecipe.duplicateName(for: "Longmarch", among: names) == "Longmarch copy")
    #expect(FilmRecipe.duplicateName(for: "Longmarch", among: names + ["Longmarch copy"]) == "Longmarch copy 2")
}

@Test func storedRecipesMissingWholeGroupsStillLoad() throws {
    let json = #"{ "id": "custom-1", "name": "Sparse" }"#
    let decoded = try JSONDecoder().decode(FilmRecipe.self, from: Data(json.utf8))

    #expect(decoded.name == "Sparse")
    #expect(decoded.grain == GrainSettings())
}

private func encodedJSON(_ value: some Encodable) -> String {
    String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
}
