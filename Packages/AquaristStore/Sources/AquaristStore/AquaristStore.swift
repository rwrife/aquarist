import Foundation
import GRDB
import AquaristKit

/// A migrated Aquarist database plus its repository handles.
public struct AquaristStore: Sendable {
    public let db: any DatabaseWriter
    public let tanks: any TankRepository
    public let events: any TankEventRepository
    public let referenceBands: any ReferenceBandRepository

    public init(db: any DatabaseWriter) {
        self.db = db
        self.tanks = GRDBTankRepository(db: db)
        self.events = GRDBTankEventRepository(db: db)
        self.referenceBands = GRDBReferenceBandRepository(db: db)
    }

    /// Opens (creating when absent) and migrates an on-disk store.
    public static func open(at url: URL) throws -> AquaristStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let db = try DatabaseQueue(path: url.path, configuration: configuration)
        try AquaristStoreSchema.migrator.migrate(db)
        return AquaristStore(db: db)
    }

    /// Creates a migrated in-memory database for tests and previews.
    public static func inMemory() throws -> AquaristStore {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let db = try DatabaseQueue(configuration: configuration)
        try AquaristStoreSchema.migrator.migrate(db)
        return AquaristStore(db: db)
    }

    /// Exports the complete local dataset as a versioned backup document.
    ///
    /// Reads every tank, every event (including append-only corrections —
    /// a backup is a full history copy, not a derivation), and every
    /// reference band with its tank association preserved.
    public func backupDocument() throws -> BackupDocument {
        let allTanks = try tanks.allTanks()
        var allEvents: [TankEvent] = []
        var allBands: [BackupReferenceBand] = []
        for tank in allTanks {
            allEvents.append(contentsOf: try events.events(for: tank.id))
            allBands.append(contentsOf: try referenceBands.bands(for: tank.id)
                .map { BackupReferenceBand(tankID: tank.id, band: $0) })
        }
        return BackupDocument(
            exportedAt: Date(),
            tanks: allTanks,
            events: allEvents,
            bands: allBands
        )
    }

    /// Replaces the entire local dataset with a backup document's contents.
    ///
    /// Callers must obtain explicit user confirmation FIRST — this wipes all
    /// local tanks, events, and bands in a single transaction before
    /// inserting the archive's rows. If any insert fails, the whole
    /// transaction rolls back and the previous data is untouched. The
    /// ledger's append-only contract is about normal in-app usage; restoring
    /// the user's own archive is the documented bulk-replace path.
    public func restore(_ document: BackupDocument) throws {
        try db.write { writer in
            try writer.execute(sql: "DELETE FROM reference_bands")
            try writer.execute(sql: "DELETE FROM tank_events")
            try writer.execute(sql: "DELETE FROM tanks")
            for tank in document.tanks {
                try writer.execute(
                    sql: """
                    INSERT INTO tanks (
                        id, name, volume_liters, volume_is_approximate,
                        volume_raw_input, kind, created_at, notes
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        tank.id.uuidString, tank.name,
                        tank.volume.map { "\($0.liters)" },
                        tank.volume?.isApproximate,
                        tank.volume?.rawInput,
                        tank.kind.rawValue,
                        tank.createdAt,
                        tank.notes,
                    ]
                )
            }
            for event in document.events {
                let encoded = try TankEventPayloadCodec.encode(event.payload)
                try writer.execute(
                    sql: """
                    INSERT INTO tank_events (id, tank_id, timestamp, payload_type, payload_json, test_parameter)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        event.id.uuidString, event.tankID.uuidString, event.timestamp,
                        encoded.type, encoded.json, encoded.testParameter,
                    ]
                )
            }
            for entry in document.bands {
                try writer.execute(
                    sql: """
                    INSERT INTO reference_bands (id, tank_id, parameter, label, raw_low, raw_high)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        entry.band.id.uuidString, entry.tankID.uuidString, entry.band.parameter,
                        entry.band.label, entry.band.rawLow, entry.band.rawHigh,
                    ]
                )
            }
        }
    }

    /// Queryable row counts plus SQLite's allocated database size.
    public func storageUsage() throws -> StorageUsage {
        try db.read { reader in
            func count(_ table: String) throws -> Int {
                try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            let pageCount: Int = try Int.fetchOne(reader, sql: "PRAGMA page_count") ?? 0
            let pageSize: Int = try Int.fetchOne(reader, sql: "PRAGMA page_size") ?? 0
            return StorageUsage(
                rows: StorageUsage.TableCounts(
                    tanks: try count("tanks"),
                    tankEvents: try count("tank_events"),
                    referenceBands: try count("reference_bands")
                ),
                databaseBytes: pageCount * pageSize
            )
        }
    }
}
