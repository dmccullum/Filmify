import Foundation

/// Where the recipes live in user defaults, the same on the Mac and the phone.
public enum RecipeKey {
    public static let saved = "recipes.saved"
    public static let selectedID = "recipes.selectedID"
    public static let working = "recipes.working"
    public static let isModified = "recipes.isModified"
}
