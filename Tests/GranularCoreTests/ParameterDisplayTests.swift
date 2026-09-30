import Foundation
import Testing
@testable import GranularCore

private let english = Locale(identifier: "en_US")
private let german = Locale(identifier: "de_DE")

@Test func proportionsReadAsWholeNumbersOutOfAHundred() {
    let display = ParameterDisplay.proportion(in: 0 ... 1)

    #expect(display.text(for: 0.72, locale: english) == "72")
    #expect(display.text(for: 0, locale: english) == "0")
    #expect(display.text(for: 0.254, locale: english) == "25")
    #expect(display.accessibilityText(for: 0.72, locale: english) == "72")
    #expect(ParameterDisplay.proportion(in: 0 ... 0.5).text(for: 0.5, locale: english) == "50")
}

@Test func signedProportionsShowTheirDirection() {
    let display = ParameterDisplay.proportion(in: -1 ... 1)

    #expect(display.isSigned)
    #expect(display.text(for: 0.45, locale: english) == "+45")
    #expect(display.text(for: -0.45, locale: english) == "-45")
    #expect(display.text(for: 0, locale: english) == "0")
    // Too small to show isn't shown as a negative zero.
    #expect(display.text(for: -0.001, locale: english) == "0")
    #expect(display.editingText(for: 0.45, locale: english) == "45")
}

@Test func exposureStrengthAndGrainSizeReadInTheirOwnUnits() {
    #expect(ParameterDisplay.exposure.text(for: 0.3, locale: english) == "+0.3 EV")
    #expect(ParameterDisplay.exposure.text(for: -1.25, locale: english) == "-1.3 EV")
    #expect(ParameterDisplay.exposure.text(for: 0, locale: english) == "0.0 EV")
    #expect(ParameterDisplay.strength.text(for: 1, locale: english) == "100%")
    #expect(ParameterDisplay.strength.accessibilityText(for: 1.5, locale: english) == "150 percent")
    #expect(ParameterDisplay.grainSize.text(for: 10, locale: english) == "10.0 µm")
    #expect(ParameterDisplay.grainSize.accessibilityText(for: 3.86, locale: english) == "3.9 micrometers")
    #expect(ParameterDisplay.exposure.text(for: 0.5, locale: german) == "+0,5 EV")
}

@Test func typedValuesAreParsedInDisplayUnitsAndClamped() {
    let signed = ParameterDisplay.proportion(in: -1 ... 1)
    #expect(signed.storedValue(from: "45", in: -1 ... 1, locale: english) == 0.45)
    #expect(signed.storedValue(from: "+45", in: -1 ... 1, locale: english) == 0.45)
    #expect(signed.storedValue(from: "\u{2212}20", in: -1 ... 1, locale: english) == -0.2)
    #expect(signed.storedValue(from: "250", in: -1 ... 1, locale: english) == 1)
    #expect(signed.storedValue(from: "  -500 ", in: -1 ... 1, locale: english) == -1)
    #expect(signed.storedValue(from: "lots", in: -1 ... 1, locale: english) == nil)
    #expect(signed.storedValue(from: "", in: -1 ... 1, locale: english) == nil)

    #expect(ParameterDisplay.exposure.storedValue(from: "+0.7 EV", in: -2 ... 2, locale: english) == 0.7)
    #expect(ParameterDisplay.exposure.storedValue(from: "-3", in: -2 ... 2, locale: english) == -2)
    #expect(ParameterDisplay.exposure.storedValue(from: "0,5", in: -2 ... 2, locale: german) == 0.5)
    #expect(ParameterDisplay.strength.storedValue(from: "150%", in: 0 ... 2, locale: english) == 1.5)
    #expect(ParameterDisplay.grainSize.storedValue(from: "12 µm", in: 2 ... 60, locale: english) == 12)
    #expect(ParameterDisplay.grainSize.storedValue(from: "1", in: 2 ... 60, locale: english) == 2)
}

@Test func arrowKeysStepByOneVisibleUnitFromWhatsShown() {
    let display = ParameterDisplay.proportion(in: 0 ... 1)

    // 34.7 shows as 35, so one step up reads 36 and one down reads 34.
    #expect(abs(display.stepped(0.347, by: 1, in: 0 ... 1) - 0.36) < 0.000_001)
    #expect(abs(display.stepped(0.347, by: -1, in: 0 ... 1) - 0.34) < 0.000_001)
    #expect(abs(display.stepped(0.5, by: 10, in: 0 ... 1) - 0.6) < 0.000_001)
    #expect(display.stepped(0.995, by: 1, in: 0 ... 1) == 1)
    #expect(display.stepped(0, by: -1, in: 0 ... 1) == 0)
    #expect(abs(ParameterDisplay.exposure.stepped(0.3, by: -1, in: -2 ... 2) - 0.2) < 0.000_001)
}

@Test func pastedAdjustmentsKeepTheRecipesOwnIdentity() {
    var target = FilmRecipe.classic35
    target.canister = "tape"
    var source = FilmRecipe.builtIns[3]
    source.tone.exposure = 0.4
    source.grain.seed = 99

    let pasted = target.applyingAdjustments(of: source)

    #expect(pasted.id == target.id)
    #expect(pasted.name == target.name)
    #expect(pasted.canister == "tape")
    #expect(pasted.tone.exposure == 0.4)
    #expect(pasted.grain == source.grain)
    #expect(pasted.diffusion == source.diffusion)
    #expect(pasted.hasSameAdjustments(as: source))
    #expect(!target.hasSameAdjustments(as: source))
}
