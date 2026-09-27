import Foundation
import Testing
import AquaristKit
import AquaristStore
import AquaristStoreTestSupport

private func d(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private struct Harness {
    let store: AquaristStore
    let fake: InMemoryRepositories
    let tankA: Tank
    let tankB: Tank

    init() throws {
        store = try AquaristStore.inMemory()
        fake = InMemoryRepositories()
        tankA = Tank(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "A", volume: TankVolume.parse("200 L"), createdAt: d(1))
        tankB = Tank(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "B", volume: nil, createdAt: d(2))
        try store.tanks.upsert(tankA)
        try store.tanks.upsert(tankB)
        try fake.tanks.upsert(tankA)
        try fake.tanks.upsert(tankB)
    }
}

@Suite("Repository behavior")
struct RepositoryTests {
    @Test("events(for:) returns chronological ledger order")
    func ledgerOrdering() throws {
        let h = try Harness()
        let late = TankEvent(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, tankID: h.tankA.id, timestamp: d(200), payload: .note("late"))
        let early = TankEvent(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, tankID: h.tankA.id, timestamp: d(100), payload: .note("early"))

        try h.store.events.append(late)
        try h.store.events.append(early)

        let events = try h.store.events.events(for: h.tankA.id)
        #expect(events.map(\.id) == [early.id, late.id])
    }

    @Test("events(for:) filters by tank")
    func perTankFilter() throws {
        let h = try Harness()
        try h.store.events.append(TankEvent(tankID: h.tankA.id, timestamp: d(10), payload: .note("a")))
        try h.store.events.append(TankEvent(tankID: h.tankB.id, timestamp: d(20), payload: .note("b")))

        let a = try h.store.events.events(for: h.tankA.id)
        let b = try h.store.events.events(for: h.tankB.id)

        #expect(a.count == 1)
        #expect(b.count == 1)
        #expect(a[0].tankID == h.tankA.id)
        #expect(b[0].tankID == h.tankB.id)
    }

    @Test("readingSeries returns per-parameter chronological raw points")
    func parameterSeries() throws {
        let h = try Harness()
        try h.store.events.append(TankEvent(tankID: h.tankA.id, timestamp: d(10), payload: .testReading(parameter: "NO3", rawValue: "20", note: nil)))
        try h.store.events.append(TankEvent(tankID: h.tankA.id, timestamp: d(20), payload: .testReading(parameter: "pH", rawValue: "7.8", note: nil)))
        try h.store.events.append(TankEvent(tankID: h.tankA.id, timestamp: d(30), payload: .testReading(parameter: "NO3", rawValue: "10 ppm", note: nil)))

        let points = try h.store.events.readingSeries(tankID: h.tankA.id, parameter: "NO3")
        #expect(points.count == 2)
        #expect(points.map(\.rawValue) == ["20", "10 ppm"])
        #expect(points[0].parsedValue == 20)
        #expect(points[1].parsedValue == nil)
    }

    @Test("reference bands round-trip per tank")
    func referenceBands() throws {
        let h = try Harness()
        let pH = ReferenceBand(parameter: "pH", label: "target", rawLow: "7.2", rawHigh: "7.9")
        let no3 = ReferenceBand(parameter: "NO3", label: "max", rawLow: nil, rawHigh: "20")
        try h.store.referenceBands.upsert(pH, for: h.tankA.id)
        try h.store.referenceBands.upsert(no3, for: h.tankA.id)

        let bands = try h.store.referenceBands.bands(for: h.tankA.id)
        #expect(bands.map(\.parameter).sorted() == ["NO3", "pH"])
    }

    @Test("GRDB repositories and in-memory fakes agree on query results")
    func grdbMatchesInMemory() throws {
        let h = try Harness()
        let events: [TankEvent] = [
            TankEvent(tankID: h.tankA.id, timestamp: d(10), payload: .testReading(parameter: "pH", rawValue: "7.8", note: nil)),
            TankEvent(tankID: h.tankA.id, timestamp: d(20), payload: .testReading(parameter: "pH", rawValue: "7.9", note: nil)),
            TankEvent(tankID: h.tankB.id, timestamp: d(30), payload: .note("other tank")),
        ]
        for event in events {
            try h.store.events.append(event)
            try h.fake.events.append(event)
        }

        let band = ReferenceBand(parameter: "pH", label: "band", rawLow: "7.2", rawHigh: "7.9")
        try h.store.referenceBands.upsert(band, for: h.tankA.id)
        try h.fake.referenceBands.upsert(band, for: h.tankA.id)

        #expect(try h.store.events.events(for: h.tankA.id) == h.fake.events.events(for: h.tankA.id))
        #expect(try h.store.events.readingSeries(tankID: h.tankA.id, parameter: "pH") == h.fake.events.readingSeries(tankID: h.tankA.id, parameter: "pH"))
        #expect(try h.store.referenceBands.bands(for: h.tankA.id) == h.fake.referenceBands.bands(for: h.tankA.id))
    }

    @Test("parent FK validation rejects event/band inserts for missing tank")
    func parentValidation() throws {
        let store = try AquaristStore.inMemory()
        let ghost = UUID()

        #expect(throws: AquaristStoreError.parentNotFound(table: "tanks", id: ghost)) {
            try store.events.append(TankEvent(tankID: ghost, timestamp: d(1), payload: .note("x")))
        }

        #expect(throws: AquaristStoreError.parentNotFound(table: "tanks", id: ghost)) {
            try store.referenceBands.upsert(ReferenceBand(parameter: "pH", label: "x"), for: ghost)
        }
    }

    @Test("storage usage exposes row counts")
    func storageUsage() throws {
        let h = try Harness()
        try h.store.events.append(TankEvent(tankID: h.tankA.id, timestamp: d(10), payload: .note("a")))
        try h.store.referenceBands.upsert(ReferenceBand(parameter: "pH", label: "target"), for: h.tankA.id)

        let usage = try h.store.storageUsage()
        #expect(usage.rows.tanks == 2)
        #expect(usage.rows.tankEvents == 1)
        #expect(usage.rows.referenceBands == 1)
        #expect(usage.databaseBytes >= 0)
    }

    @Test("tank registry fields survive create and edit")
    func registryRoundTrip() throws {
        let store = try AquaristStore.inMemory()
        var tank = Tank(
            name: "Mangrove",
            volume: TankVolume.parse("approx 20 gal"),
            kind: .brackish,
            createdAt: d(123),
            notes: "Low-flow shelf"
        )
        try store.tanks.upsert(tank)
        #expect(try store.tanks.tank(id: tank.id) == tank)

        tank.name = "Mangrove nursery"
        tank.notes = "West shelf"
        try store.tanks.upsert(tank)
        #expect(try store.tanks.tank(id: tank.id) == tank)
    }

    @Test("append-only correction makes a reading ineffective")
    func correctionUndo() throws {
        let h = try Harness()
        let reading = TankEvent(
            tankID: h.tankA.id,
            timestamp: d(10),
            payload: .testReading(parameter: "pH", rawValue: "7.8", note: nil)
        )
        try h.store.events.append(reading)
        try h.store.events.append(TankEvent(
            tankID: h.tankA.id,
            timestamp: d(11),
            payload: .correction(targetEventID: reading.id, note: "Undo")
        ))

        #expect(try h.store.events.events(for: h.tankA.id).count == 2)
        #expect(try h.store.events.readingSeries(tankID: h.tankA.id, parameter: "pH").isEmpty)
    }
}
