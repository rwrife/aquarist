/// AquaristKit — pure-domain core for Aquarist.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 (domain) lands the tank model and append-only event
/// ledger (water changes, test readings, doses, livestock/equipment
/// events, notes), the unknown-safe derivation engine (days-since,
/// DST-safe weekly totals, last-dose age, raw trend series), the
/// user-owned ReferenceBand, and the versioned backup/CSV codecs here.
/// The GRDB store is issue #3 and lives in `AquaristStore`, not this
/// package.
public enum AquaristKit {
    /// Namespace marker for the domain layer.
    public static let domain = "AquaristKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-skeleton"
}
