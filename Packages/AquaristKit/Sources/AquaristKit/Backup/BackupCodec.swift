import Foundation

/// A reference band paired with the tank it belongs to.
///
/// `ReferenceBand` itself has no tank back-reference (the repository keys
/// bands by `tankID`). A backup must preserve that association, so the
/// backup document stores bands in this wrapper.
public struct BackupReferenceBand: Codable, Equatable, Sendable, Identifiable {
    public let tankID: UUID
    public let band: ReferenceBand

    public var id: UUID { band.id }

    public init(tankID: UUID, band: ReferenceBand) {
        self.tankID = tankID
        self.band = band
    }
}

/// The full on-disk shape of a versioned Aquarist backup.
///
/// A backup is a self-describing JSON document: `schemaVersion` lets a future
/// decoder migrate older archives, and the payload covers every persisted
/// domain record — tanks, append-only events, and reference bands. Nothing is
/// interpreted or summarized here; every user string is carried verbatim so a
/// restored app echoes exactly what the user recorded.
public struct BackupDocument: Codable, Equatable, Sendable {
    /// Backward-compatible schema version. Bump only when the payload shape
    /// changes; the decoder must keep accepting all previously shipped
    /// versions.
    public static let currentVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let tanks: [Tank]
    public let events: [TankEvent]
    public let bands: [BackupReferenceBand]

    public init(
        schemaVersion: Int = BackupDocument.currentVersion,
        exportedAt: Date = Date(),
        tanks: [Tank],
        events: [TankEvent],
        bands: [BackupReferenceBand]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.tanks = tanks
        self.events = events
        self.bands = bands
    }
}

/// A non-destructive, count-and-identity-only preview of a backup archive.
///
/// The restore flow shows this first and replaces the local store only after
/// an explicit user confirmation. `tankNames` is included verbatim (name
/// only — no derived status) so the preview can list what would be restored.
public struct BackupPreview: Equatable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let tankCount: Int
    public let eventCount: Int
    public let bandCount: Int
    public let tankNames: [String]

    public init(
        schemaVersion: Int,
        exportedAt: Date,
        tankCount: Int,
        eventCount: Int,
        bandCount: Int,
        tankNames: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.tankCount = tankCount
        self.eventCount = eventCount
        self.bandCount = bandCount
        self.tankNames = tankNames
    }
}

/// Errors thrown by backup encode/decode.
public enum BackupCodecError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

/// Versioned JSON backup codec for the full Aquarist domain.
///
/// The encoder emits deterministic output (sorted keys, no trailing state)
/// so two backups of the same data are byte-identical — this is what makes
/// the round-trip property tests meaningful and the artifact diffable.
public enum BackupCodec {

    // MARK: - Encoding

    /// Encodes a complete backup document to JSON `Data`.
    public static func encode(
        tanks: [Tank],
        events: [TankEvent],
        bands: [BackupReferenceBand],
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = BackupDocument(
            schemaVersion: BackupDocument.currentVersion,
            exportedAt: exportedAt,
            tanks: tanks,
            events: events,
            bands: bands
        )
        let encoder = makeEncoder()
        return try encoder.encode(document)
    }

    /// Encodes an existing document (used by tests to re-serialize a decode).
    public static func encode(_ document: BackupDocument) throws -> Data {
        try makeEncoder().encode(document)
    }

    // MARK: - Decoding

    /// Decodes a backup document, refusing versions the current build does
    /// not understand.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = makeDecoder()
        let document = try decoder.decode(BackupDocument.self, from: data)
        guard document.schemaVersion <= BackupDocument.currentVersion else {
            throw BackupCodecError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard document.schemaVersion >= 1 else {
            throw BackupCodecError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }

    /// A non-destructive preview of a backup archive, without mutating any
    /// store. Used by the restore confirmation screen.
    public static func preview(_ data: Data) throws -> BackupPreview {
        let document = try decode(data)
        return BackupPreview(
            schemaVersion: document.schemaVersion,
            exportedAt: document.exportedAt,
            tankCount: document.tanks.count,
            eventCount: document.events.count,
            bandCount: document.bands.count,
            tankNames: document.tanks.map(\.name)
        )
    }

    // MARK: - Encoder/decoder factory

    /// A fresh encoder with deterministic (sorted-key) output. Dates use
    /// Foundation's default double-since-reference encoding, which round-trips
    /// exactly and matches the strategy the rest of the domain models use.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    /// A fresh decoder matching the encoder.
    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
