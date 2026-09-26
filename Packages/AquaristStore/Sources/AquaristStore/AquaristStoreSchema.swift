import Foundation
import GRDB
import AquaristKit

public enum AquaristStoreError: Error, Equatable, Sendable {
    case corruptPayload(table: String, id: UUID, underlying: String)
    case parentNotFound(table: String, id: UUID)
}

public enum AquaristStoreSchema {
    public static let migrationIdentifiers: [String] = ["v1"]
    public static var currentVersion: Int { migrationIdentifiers.count }

    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "tanks") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("name", .text).notNull()
                table.column("volume_liters", .text)
                table.column("volume_is_approximate", .boolean)
                table.column("volume_raw_input", .text)
                table.column("created_at", .datetime).notNull()
            }

            try db.create(table: "tank_events") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("tank_id", .text).notNull()
                    .references("tanks", onDelete: .cascade)
                table.column("timestamp", .datetime).notNull()
                table.column("payload_type", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("test_parameter", .text)
            }
            try db.create(
                index: "tank_events_tank_timestamp",
                on: "tank_events",
                columns: ["tank_id", "timestamp"]
            )
            try db.create(
                index: "tank_events_tank_parameter",
                on: "tank_events",
                columns: ["tank_id", "test_parameter", "timestamp"]
            )

            try db.create(table: "reference_bands") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("tank_id", .text).notNull()
                    .references("tanks", onDelete: .cascade)
                table.column("parameter", .text).notNull()
                table.column("label", .text).notNull()
                table.column("raw_low", .text)
                table.column("raw_high", .text)
            }
            try db.create(
                index: "reference_bands_tank_parameter",
                on: "reference_bands",
                columns: ["tank_id", "parameter"]
            )
        }
        return migrator
    }()
}

public func aquaristStoreAppliedSchemaVersion(_ db: DatabaseReader) throws -> Int {
    try db.read { reader in
        try AquaristStoreSchema.migrator.appliedMigrations(reader).count
    }
}
