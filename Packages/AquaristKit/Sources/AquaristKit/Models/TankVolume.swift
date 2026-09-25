import Foundation

/// A tank's water volume with an honest exact/approximate provenance flag
/// and the user's verbatim raw input string.
///
/// Parsing is unknown-safe: anything that cannot be interpreted returns
/// `nil` rather than a guessed number.
public struct TankVolume: Codable, Equatable, Sendable {
    /// Volume normalized to liters.
    public let liters: Decimal

    /// `true` when the user marked the input as approximate
    /// (e.g. "~200 L", "approx 75 gal").
    public let isApproximate: Bool

    /// The exact string the user typed, echoed verbatim for display.
    public let rawInput: String

    public init(liters: Decimal, isApproximate: Bool, rawInput: String) {
        self.liters = liters
        self.isApproximate = isApproximate
        self.rawInput = rawInput
    }

    // MARK: - Unit conversion constants

    /// Exact liters per US liquid gallon (definition: 3.785411784 L).
    public static let litersPerUSGallon: Decimal = Decimal(string: "3.785411784")!

    // MARK: - Parsing

    /// Parses user-entered volume text such as `200 L`, `200L`, `26.5 gal`,
    /// `1500ml`, `~200 litres`, or `approx 75 gallons`.
    ///
    /// Returns `nil` when no quantity + recognized unit is present — the
    /// caller must render `.unknown`, never a default.
    public static func parse(_ input: String) -> TankVolume? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed
        var isApproximate = false
        for marker in ["~", "≈", "±"] where working.hasPrefix(marker) {
            isApproximate = true
            working = String(working.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        for prefix in ["approx", "approximately", "about", "roughly"]
        where working.lowercased().hasPrefix(prefix) {
            isApproximate = true
            working = String(working.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        // Split leading numeric run from the trailing unit text.
        let numericPrefix = working.prefix {
            $0.isNumber || $0 == "." || $0 == ","
        }
        guard !numericPrefix.isEmpty else { return nil }
        let unitText = String(working.dropFirst(numericPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Accept "1,000 L" style grouping only when commas are interior.
        let numberText = String(numericPrefix)
        if numberText.hasPrefix(",") || numberText.hasSuffix(",") { return nil }
        let normalizedNumber = numberText.replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalizedNumber), amount > 0 else {
            return nil
        }

        switch unitText {
        case "l", "liters", "litre", "litres", "liter":
            return TankVolume(liters: amount, isApproximate: isApproximate, rawInput: input)
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            return TankVolume(
                liters: amount / 1000,
                isApproximate: isApproximate,
                rawInput: input
            )
        case "gal", "gallon", "gallons":
            return TankVolume(
                liters: amount * litersPerUSGallon,
                isApproximate: isApproximate,
                rawInput: input
            )
        default:
            return nil
        }
    }

    // MARK: - Percent-of-volume arithmetic

    /// Liters corresponding to `percent` of this volume (e.g. 25 → 25% of
    /// the tank). Decimal arithmetic keeps percent math exact for typical
    /// inputs like 25% of 200 L = 50 L.
    public func liters(forPercentOfVolume percent: Decimal) -> Decimal {
        liters * percent / 100
    }
}
