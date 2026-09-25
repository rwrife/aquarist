import Foundation

/// Outcome of comparing a reading against a user's own reference band.
///
/// Note the naming: membership is phrased strictly as the user's own
/// statement (`matchesUserBand`) — the domain makes **no** safety,
/// toxicity, or diagnostic claims of any kind.
public enum BandMembership: Equatable, Sendable {
    /// The reading parses to a number inside the user's stated band.
    case matchesUserBand
    /// The reading parses to a number outside the user's stated band.
    case outsideUserBand
    /// Cannot say — the band, the reading, or both are unparseable or
    /// missing. Rendered as "unknown"; never guessed.
    case unknown
}

/// A user-entered reference band for one parameter (e.g. "my pH target").
///
/// The band is *the user's own statement*: every string is stored and
/// echoed verbatim (`label`, and the raw low/high text), and membership
/// queries compare only parsed numbers the user themselves entered.
public struct ReferenceBand: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID

    /// Parameter this band applies to — the user's own label.
    public var parameter: String

    /// Verbatim label text the user gave the band (e.g. "my tank's norm").
    public var label: String

    /// Raw text for the band's lower bound, echoed verbatim.
    public var rawLow: String?

    /// Raw text for the band's upper bound, echoed verbatim.
    public var rawHigh: String?

    public init(
        id: UUID = UUID(),
        parameter: String,
        label: String,
        rawLow: String? = nil,
        rawHigh: String? = nil
    ) {
        self.id = id
        self.parameter = parameter
        self.label = label
        self.rawLow = rawLow
        self.rawHigh = rawHigh
    }

    /// Lower bound parsed from user text, or `nil` if absent/unparseable.
    public var low: Decimal? { rawLow.flatMap(StrictDecimal.parse) }

    /// Upper bound parsed from user text, or `nil` if absent/unparseable.
    public var high: Decimal? { rawHigh.flatMap(StrictDecimal.parse) }

    /// Compares a reading (user's raw text) against the user's own band.
    ///
    /// `.unknown` whenever the band has no numeric bounds at all or the
    /// reading does not parse to a number — the UI then renders "unknown"
    /// instead of implying any verdict.
    public func membership(ofReadingRawValue rawValue: String) -> BandMembership {
        guard let value = StrictDecimal.parse(rawValue) else {
            return .unknown
        }
        guard low != nil || high != nil else { return .unknown }

        // One-sided bands check only their stated side; two-sided check both.
        if let low, value < low { return .outsideUserBand }
        if let high, value > high { return .outsideUserBand }
        return .matchesUserBand
    }
}
