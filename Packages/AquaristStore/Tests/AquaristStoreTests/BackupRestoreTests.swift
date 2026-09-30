import Foundation
import GRDB
import Testing
import AquaristKit
@testable import AquaristStore

private func fd(_ y: Int, _ mo: Int, _ day: Int, _ h: Int = 12) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .gmt
    var comp = DateComponents()
    comp.year = y; comp.month = mo; comp.day = day; comp.hour = h
    return cal.date(from: comp)!
}

// MARK: - Backup / restore round-trip through the GRDB store

@Suite("Store backup + restore round-trip")
struct BackupRestoreTests {

    private func seed(_ store: AquaristStore) throws -> (Tank, TankEvent, TankEvent, ReferenceBand) {
        let tank = Tank(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "75 Reef",
            volume: TankVolume.parse("~75 gal")!,
            kind: .saltwater,
            createdAt: fd(2026, 1, 1),
            notes: "corner tank"
        )
        let band = ReferenceBand(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            parameter: "pH", label: "my norm", rawLow: "7.2", rawHigh: "7.9"
        )
        let water = TankEvent(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            tankID: tank.id,
            timestamp: fd(2026, 5, 1),
            payload: .waterChange(percentOfVolume: 25, volumeLiters: nil, note: "25%")
        )
        let reading = TankEvent(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            tankID: tank.id,
            timestamp: fd(2026, 5, 2),
            payload: .testReading(parameter: "pH", rawValue: "7.8", note: nil)
        )
        try store.tanks.upsert(tank)
        try store.events.append(water)
        try store.events.append(reading)
        try store.referenceBands.upsert(band, for: tank.id)
        return (tank, water, reading, band)
    }

    @Test("export reads back every persisted record with its associations")
    func exportCompleteness() throws {
        let store = try AquaristStore.inMemory()
        let (tank, water, reading, band) = try seed(store)

        let document = try store.backupDocument()
        #expect(document.schemaVersion == BackupDocument.currentVersion)
        #expect(document.tanks == [tank])
        #expect(Set(document.events.map(\.id)) == Set([water.id, reading.id]))
        #expect(document.bands.count == 1)
        #expect(document.bands[0].band == band)
        #expect(document.bands[0].tankID == tank.id)
    }

    @Test("backup JSON → restore into a fresh store reproduces identical queries")
    func roundTripThroughJSON() throws {
        let source = try AquaristStore.inMemory()
        let (tank, _, _, _) = try seed(source)

        let data = try BackupCodec.encode(try source.backupDocument())
        // Round-trip preview works on the exact artifact the share sheet sees.
        let preview = try BackupCodec.preview(data)
        #expect(preview.tankCount == 1 && preview.eventCount == 2 && preview.bandCount == 1)

        let target = try AquaristStore.inMemory()
        let foreign = Tank(id: UUID(), name: "Will be replaced")
        try target.tanks.upsert(foreign)
        try target.events.append(TankEvent(tankID: foreign.id, timestamp: fd(2026, 6, 1), payload: .note("gone")))

        try target.restore(try BackupCodec.decode(data))

        #expect(try target.tanks.allTanks() == [tank])
        #expect(try target.events.events(for: tank.id).count == 2)
        #expect(try target.referenceBands.bands(for: tank.id) == [
            ReferenceBand(
                id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                parameter: "pH", label: "my norm", rawLow: "7.2", rawHigh: "7.9"
            ),
        ])
        // The foreign tank and its event are gone (full replace semantics).
        #expect(try target.tanks.tank(id: foreign.id) == nil)
        #expect(try target.events.events(for: foreign.id).isEmpty)
        // Indexed per-parameter series still works after restore.
        let series = try target.events.readingSeries(tankID: tank.id, parameter: "pH")
        #expect(series.map(\.rawValue) == ["7.8"])
    }

    @Test("restore replaces all three tables atomically")
    func restoreWipesEverything() throws {
        let source = try AquaristStore.inMemory()
        try seed(source)
        let document = try source.backupDocument()

        let target = try AquaristStore.inMemory()
        for name in ["A", "B", "C"] {
            let extra = Tank(id: UUID(), name: name)
            try target.tanks.upsert(extra)
            try target.events.append(TankEvent(tankID: extra.id, timestamp: .init(), payload: .note("x")))
            try target.referenceBands.upsert(ReferenceBand(parameter: "pH", label: "x"), for: extra.id)
        }
        #expect(try target.storageUsage().rows.tanks == 3)

        try target.restore(document)
        let usage = try target.storageUsage().rows
        #expect(usage.tanks == 1)
        #expect(usage.tankEvents == 2)
        #expect(usage.referenceBands == 1)
    }

    @Test("an insert failure mid-restore rolls back and leaves prior data intact")
    func restoreRollback() throws {
        let source = try AquaristStore.inMemory()
        let (tank, _, _, _) = try seed(source)
        let goodDocument = try source.backupDocument()

        let target = try AquaristStore.inMemory()
        try target.restore(goodDocument)
        let before = try target.tanks.allTanks()
        #expect(before == [tank])

        // A document whose event references an absent tank fails the FK
        // check mid-restore. The DELETE phase already emptied the tables,
        // so only a real transaction rollback can preserve the prior data.
        let orphaned = BackupDocument(
            schemaVersion: goodDocument.schemaVersion,
            exportedAt: goodDocument.exportedAt,
            tanks: [],
            events: [TankEvent(
                tankID: tank.id,
                timestamp: fd(2026, 7, 1),
                payload: .note("orphan")
            )],
            bands: []
        )
        #expect(throws: (any Error).self) {
            try target.restore(orphaned)
        }
        // Rolled back: the previous data is still readable and unchanged.
        #expect(try target.tanks.allTanks() == before)
        let usage = try target.storageUsage().rows
        #expect(usage.tanks == 1 && usage.tankEvents == 2 && usage.referenceBands == 1)
    }
}
