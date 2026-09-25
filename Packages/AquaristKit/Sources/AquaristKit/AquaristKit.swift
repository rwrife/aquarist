/// AquaristKit — pure-domain core for Aquarist.
///
/// Issue #2 lands the full domain layer: the `Tank` model, the append-only
/// `TankEvent` ledger (water changes, test readings, doses, livestock
/// add/remove/observed, equipment events, notes), the unknown-safe
/// derivation engine (days-since-water-change, day streak, DST-safe weekly
/// water-change totals, last-dose age, raw per-parameter reading series,
/// volume parsing with an exact/approximate flag), and the user-owned
/// `ReferenceBand` that echoes user text verbatim.
///
/// Invariants enforced here (and tested):
/// - All models are value types with stable Codable round-trips.
/// - The ledger is append-only: there is no in-place mutation or removal API.
/// - Derivations are unknown-safe: missing data renders `.unknown`, never a
///   default number.
/// - Calendar math is DST-safe (calendar-based day/week stepping).
/// - `ReferenceBand` membership is phrased strictly as the user's own
///   statement; the type system contains no safety/toxicity naming.
///
/// The GRDB store is issue #3 and lives in `AquaristStore`, not this package.
public enum AquaristKit {
    /// Namespace marker for the domain layer.
    public static let domain = "AquaristKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M2-domain"
}
