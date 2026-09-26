import Foundation
import GRDB

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
