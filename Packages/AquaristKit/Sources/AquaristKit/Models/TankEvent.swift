import Foundation

/// The payload kinds of a single ledger entry. One flat enum covers every
/// event type so the ledger needs no polymorphic decoding tricks.
public enum TankEventPayload: Codable, Equatable, Sendable {
    /// A water change. `percentOfVolume` (e.g. 25 for 25%) and/or
    /// `volumeLiters` may be given; either alone is enough for the log,
    /// and derivations prefer an explicit liter amount when present.
    case waterChange(
        percentOfVolume: Decimal?,
        volumeLiters: Decimal?,
        note: String?
    )

    /// A test reading. The user-entered value is stored verbatim in
    /// `rawValue`; the app echoes it and never rewrites or rounds it.
    /// `parameter` is the user's own label (e.g. "pH", "NO3").
    case testReading(parameter: String, rawValue: String, note: String?)

    /// A dose of something (medication, fertilizer, additive).
    case dose(substance: String, amount: String?, note: String?)

    /// Livestock joined the tank.
    case livestockAdded(species: String, quantity: Int, note: String?)

    /// Livestock left the tank (death, rehome, split…).
    case livestockRemoved(species: String, quantity: Int, note: String?)

    /// A still-present observation about livestock (health, spawning…).
    case livestockObserved(species: String, note: String?)

    /// Equipment added / serviced / removed — recorded as a note-bearing
    /// equipment event; the ledger's append-only nature preserves the
    /// full history without mutation.
    case equipment(name: String, note: String?)

    /// Free-form note.
    case note(String)

    /// A correction/undo of a previously-logged event, referencing it by id.
    /// Append-only by design: the original event is never mutated or deleted,
    /// but it stops counting toward derived views (see
    /// `EventLedger.effectiveEvents`) once a correction references it.
    case correction(targetEventID: UUID, note: String?)
}

/// One entry in a tank's append-only event ledger.
///
/// Events are immutable once created; there is deliberately no API to
/// edit or delete a ledger entry in place (corrections are new events).
public struct TankEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let tankID: UUID
    public let timestamp: Date
    public let payload: TankEventPayload

    public init(
        id: UUID = UUID(),
        tankID: UUID,
        timestamp: Date,
        payload: TankEventPayload
    ) {
        self.id = id
        self.tankID = tankID
        self.timestamp = timestamp
        self.payload = payload
    }
}

/// A tank's event ledger: an append-only, chronologically ordered view of
/// `TankEvent`s.
///
/// The only mutator is `append`. There is no remove, replace, or sort-in-
/// place API — history corrections happen by appending new events, which
/// is the product contract for an honest event history.
public struct EventLedger: Codable, Equatable, Sendable {
    /// Events in the order they were appended (guaranteed non-decreasing
    /// by timestamp at append time; consumers should still treat this as
    /// a multiset keyed on timestamp).
    public private(set) var events: [TankEvent]

    public init(events: [TankEvent] = []) {
        // Normalize to chronological order once at construction; after
        // this point the array is append-only.
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Appends an event whose timestamp is >= every existing event.
    /// Appending an out-of-order (older) event is rejected so the ledger
    /// never silently rewrites the past.
    public mutating func append(_ event: TankEvent) {
        precondition(
            events.last.map { $0.timestamp <= event.timestamp } ?? true,
            "EventLedger is append-only: cannot append an event older than the newest entry"
        )
        events.append(event)
    }

    /// Convenience: append and return the updated ledger (for value-style
    /// chaining).
    public func appending(_ event: TankEvent) -> EventLedger {
        var copy = self
        copy.append(event)
        return copy
    }

    /// Events that remain in effect after applying append-only corrections
    /// ("Undo"). Correction rows themselves are audit history, not
    /// husbandry activity, so every derivation should read from this
    /// instead of `events` directly.
    public var effectiveEvents: [TankEvent] {
        let retracted = Set(events.compactMap { event -> UUID? in
            guard case let .correction(targetEventID, _) = event.payload else { return nil }
            return targetEventID
        })
        return events.filter { event in
            guard !retracted.contains(event.id) else { return false }
            if case .correction = event.payload { return false }
            return true
        }
    }
}
