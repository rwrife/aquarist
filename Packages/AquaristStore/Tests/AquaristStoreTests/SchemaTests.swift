import Foundation
import GRDB
import Testing
import AquaristKit
import AquaristStore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite("AquaristStore current schema")
struct SchemaTests {
    @Test("fresh DB applies every migration through schema v2")
    func freshVersion() throws {
        let store = try AquaristStore.inMemory()
        let applied = try aquaristStoreAppliedSchemaVersion(store.db)
        #expect(applied == 2)
        #expect(applied == AquaristStoreSchema.currentVersion)
    }

    @Test("migrator is idempotent")
    func idempotent() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(configuration: config)
        try AquaristStoreSchema.migrator.migrate(db)
        try AquaristStoreSchema.migrator.migrate(db)
        #expect(try aquaristStoreAppliedSchemaVersion(db) == 2)
    }

    @Test("required tables and columns exist")
    func tablesAndColumns() throws {
        let store = try AquaristStore.inMemory()
        let columns = try store.db.read { reader in
            [
                "tanks": try reader.columns(in: "tanks").map(\.name),
                "tank_events": try reader.columns(in: "tank_events").map(\.name),
                "reference_bands": try reader.columns(in: "reference_bands").map(\.name),
            ]
        }
        #expect(columns["tanks"]?.contains("created_at") == true)
        #expect(columns["tanks"]?.contains("kind") == true)
        #expect(columns["tanks"]?.contains("notes") == true)
        #expect(columns["tank_events"]?.contains("payload_json") == true)
        #expect(columns["tank_events"]?.contains("test_parameter") == true)
        #expect(columns["reference_bands"]?.contains("tank_id") == true)
    }

    @Test("tank_events are append-only rows")
    func eventAppendOnlyShape() throws {
        let store = try AquaristStore.inMemory()
        let tank = Tank(id: UUID(), name: "A", volume: nil, createdAt: date(0))
        try store.tanks.upsert(tank)
        try store.events.append(TankEvent(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, tankID: tank.id, timestamp: date(10), payload: .note("first")))
        try store.events.append(TankEvent(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, tankID: tank.id, timestamp: date(20), payload: .note("second")))

        let rowCount = try store.db.read { reader in
            try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM tank_events WHERE tank_id = ?", arguments: [tank.id.uuidString]) ?? -1
        }
        #expect(rowCount == 2)
    }
}

@Suite("AquaristStore cascade semantics")
struct CascadeTests {
    @Test("deleting a tank cascades to events and reference bands")
    func deleteTankCascade() throws {
        let store = try AquaristStore.inMemory()
        let tank = Tank(id: UUID(), name: "Cascade", volume: TankVolume.parse("200 L"), createdAt: date(0))
        try store.tanks.upsert(tank)
        try store.events.append(TankEvent(tankID: tank.id, timestamp: date(100), payload: .testReading(parameter: "pH", rawValue: "7.8", note: nil)))
        try store.referenceBands.upsert(ReferenceBand(parameter: "pH", label: "target", rawLow: "7.2", rawHigh: "7.9"), for: tank.id)

        try store.db.write { writer in
            try writer.execute(sql: "DELETE FROM tanks WHERE id = ?", arguments: [tank.id.uuidString])
        }

        let counts = try store.db.read { reader in
            [
                "tanks": try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM tanks") ?? -1,
                "tank_events": try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM tank_events") ?? -1,
                "reference_bands": try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM reference_bands") ?? -1,
            ]
        }
        #expect(counts["tanks"] == 0)
        #expect(counts["tank_events"] == 0)
        #expect(counts["reference_bands"] == 0)
    }
}
