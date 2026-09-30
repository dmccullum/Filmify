import Foundation

/// How an adjustment reads in the inspector. Recipes keep the renderer's own
/// units; people see them the way they'd say them — 0 to 100, ±100 around a
/// neutral centre, stops of exposure, microns of grain.
public struct ParameterDisplay: Hashable, Sendable {
    public enum Unit: Hashable, Sendable {
        case none
        case percent
        case stops
        case micrometers

        public var symbol: String {
            switch self {
            case .none: ""
            case .percent: "%"
            case .stops: "EV"
            case .micrometers: "µm"
            }
        }

        var spokenName: String {
            switch self {
            case .none: ""
            case .percent: "percent"
            case .stops: "EV"
            case .micrometers: "micrometers"
            }
        }

        /// Every spelling a typed value might carry, stripped before parsing.
        var typedSpellings: [String] {
            switch self {
            case .none: []
            case .percent: ["%"]
            case .stops: ["EV", "stops", "stop"]
            case .micrometers: ["µm", "μm", "um", "microns", "micron"]
            }
        }
    }

    /// What one stored unit is worth on screen.
    public var scale: Double
    public var fractionDigits: Int
    /// Signed values show “+” as well as “−”, so an offset reads as one.
    public var isSigned: Bool
    public var unit: Unit
    /// One arrow-key press, in displayed units.
    public var step: Double

    public init(scale: Double, fractionDigits: Int, isSigned: Bool, unit: Unit = .none, step: Double = 1) {
        self.scale = scale
        self.fractionDigits = fractionDigits
        self.isSigned = isSigned
        self.unit = unit
        self.step = step
    }

    /// 0…1 reads as 0–100, and −1…1 as −100…+100.
    public static func proportion(in range: ClosedRange<Double>) -> ParameterDisplay {
        ParameterDisplay(scale: 100, fractionDigits: 0, isSigned: range.lowerBound < 0)
    }

    /// Exposure, in signed stops.
    public static let exposure = ParameterDisplay(scale: 1, fractionDigits: 1, isSigned: true, unit: .stops, step: 0.1)

    /// How strongly a film stock is applied, where 100% is the stock as it comes.
    public static let strength = ParameterDisplay(scale: 100, fractionDigits: 0, isSigned: false, unit: .percent)

    /// Grain size is already in microns on a 35mm frame; that's what the renderer scales by.
    public static let grainSize = ParameterDisplay(scale: 1, fractionDigits: 1, isSigned: false, unit: .micrometers, step: 0.5)

    /// The value as it's shown, rounded the same way, and never “−0”.
    public func displayedValue(_ stored: Double) -> Double {
        let factor = pow(10, Double(fractionDigits))
        let rounded = (stored * scale * factor).rounded() / factor
        return rounded == 0 ? 0 : rounded
    }

    /// The readout beside the slider, such as “+0.3 EV”, “−45” or “100%”.
    public func text(for stored: Double, locale: Locale = .current) -> String {
        withUnit(number(for: stored, showsPlus: true, locale: locale), unit.symbol)
    }

    /// What VoiceOver says, with the unit spelled out.
    public func accessibilityText(for stored: Double, locale: Locale = .current) -> String {
        withUnit(number(for: stored, showsPlus: true, locale: locale), unit.spokenName, spaced: true)
    }

    /// The number alone, as it starts out when typing a value.
    public func editingText(for stored: Double, locale: Locale = .current) -> String {
        number(for: stored, showsPlus: false, locale: locale)
    }

    /// The stored value for something typed, clamped to the parameter's range.
    /// Accepts either sign, the unit, and either decimal separator.
    public func storedValue(from text: String, in range: ClosedRange<Double>, locale: Locale = .current) -> Double? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2212}", with: "-")
        for spelling in unit.typedSpellings {
            text = text.replacingOccurrences(of: spelling, with: "", options: .caseInsensitive)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("+") {
            text.removeFirst()
        }
        if let separator = locale.decimalSeparator, separator != "." {
            text = text.replacingOccurrences(of: separator, with: ".")
        }
        guard let displayed = Double(text), displayed.isFinite, scale != 0 else { return nil }
        return clamped(displayed / scale, to: range)
    }

    /// Nudges a value by whole steps from the nearest step it shows, so the
    /// readout moves by exactly one each time.
    public func stepped(_ stored: Double, by steps: Double, in range: ClosedRange<Double>) -> Double {
        guard step > 0, scale != 0 else { return stored }
        let displayed = ((stored * scale / step).rounded() + steps) * step
        return clamped(displayed / scale, to: range)
    }

    private func number(for stored: Double, showsPlus: Bool, locale: Locale) -> String {
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(fractionDigits))
            .grouping(.never)
            .locale(locale)
        let value = displayedValue(stored)
        return isSigned && showsPlus
            ? value.formatted(style.sign(strategy: .always(includingZero: false)))
            : value.formatted(style)
    }

    private func withUnit(_ number: String, _ unitText: String, spaced: Bool? = nil) -> String {
        guard !unitText.isEmpty else { return number }
        let isSpaced = spaced ?? (unit != .percent)
        return isSpaced ? "\(number) \(unitText)" : number + unitText
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
