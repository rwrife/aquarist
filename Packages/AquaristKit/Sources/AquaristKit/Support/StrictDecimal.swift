import Foundation

/// Strict whole-string decimal parsing.
///
/// `Decimal(string:)` differs across platforms in how much of a dirty
/// string it accepts (swift-corelibs-foundation greedily parses
/// `"10 ppm"` as `10`). The domain needs identical unknown-safe behavior
/// on Linux CI and Apple runners, so every user-text number parse goes
/// through this helper: any trailing/leading garbage means `nil` → the
/// UI renders "unknown", never a silently truncated number.
enum StrictDecimal {
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var sawDigit = false
        var sawDot = false
        for (index, character) in trimmed.enumerated() {
            switch character {
            case "+", "-":
                guard index == 0 else { return nil }
            case ".":
                if sawDot { return nil }
                sawDot = true
            default:
                guard character.isNumber else { return nil }
                sawDigit = true
            }
        }
        guard sawDigit else { return nil }
        return Decimal(string: trimmed)
    }
}
