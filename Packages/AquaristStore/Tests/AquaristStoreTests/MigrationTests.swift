import Foundation
import GRDB
import Testing
import AquaristKit
import AquaristStore

private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v1.sqlite")
}

private func migratedFixture() throws -> (store: AquaristStore, fileURL: URL) {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AquaristStore-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let fileURL = tmpDir.appendingPathComponent("aquarist.sqlite")
    try FileManager.default.copyItem(at: fixtureURL(), to: fileURL)

    var config = Configuration()
    config.foreignKeysEnabled = true
    let db = try DatabaseQueue(path: fileURL.path, configuration: config)
    try AquaristStoreSchema.migrator.migrate(db)
    return (AquaristStore(db: db), fileURL)
}

private func fixedUUID(_ hex: String) -> UUID { UUID(uuidString: hex)! }

private let tankID = fixedUUID("11111111-1111-1111-1111-111111111111")
private let secondTankID = fixedUUID("22222222-2222-2222-2222-222222222222")

@Suite("Migration from committed v1 fixture")
struct MigrationTests {
    @Test("fixture upgrades to current schema version")
    func fixtureUpgrades() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let applied = try aquaristStoreAppliedSchemaVersion(store.db)
        #expect(applied == AquaristStoreSchema.currentVersion)
        #expect(applied == 1)
    }

    @Test("fixture data survives migration")
    func fixtureDataSurvives() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let tanks = try store.tanks.allTanks()
        #expect(tanks.map(\.id).contains(tankID))
        #expect(tanks.map(\.id).contains(secondTankID))

        let events = try store.events.events(for: tankID)
        #expect(events.count == 3)
        #expect(events.contains { event in
            if case let .testReading(parameter, raw, _) = event.payload {
                return parameter == "pH" && raw == "7.8"
            }
            return false
        })

        let series = try store.events.readingSeries(tankID: tankID, parameter: "NO3")
        #expect(series.map(\.rawValue) == ["20", "10 ppm"])

        let bands = try store.referenceBands.bands(for: tankID)
        #expect(bands.map(\.parameter).sorted() == ["NO3", "pH"])

        let usage = try store.storageUsage()
        #expect(usage.rows.tanks == 2)
        #expect(usage.rows.tankEvents == 4)
        #expect(usage.rows.referenceBands == 3)
        #expect(usage.databaseBytes > 0)
    }

    @Test("appending after migration works")
    func appendAfterMigration() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try store.events.append(TankEvent(tankID: tankID, timestamp: Date(timeIntervalSince1970: 9_999), payload: .note("post-migration")))
        let events = try store.events.events(for: tankID)
        #expect(events.last?.payload == .note("post-migration"))
    }

    @Test("cascade still works after migration")
    func cascadeAfterMigration() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try store.db.write { writer in
            try writer.execute(sql: "DELETE FROM tanks WHERE id = ?", arguments: [tankID.uuidString])
        }

        #expect(try store.events.events(for: tankID).isEmpty)
        #expect(try store.referenceBands.bands(for: tankID).isEmpty)

        let remaining = try store.tanks.allTanks()
        #expect(remaining.map(\.id) == [secondTankID])
    }
}
