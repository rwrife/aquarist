import Foundation
import Testing
@testable import AquaristKit

// MARK: - Backup codec: round-trip, versioning, preview, determinism

private func backupFixture() -> BackupDocument {
    let reefID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let quarID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let tanks = [
        Tank(
            id: reefID,
            name: "75 Reef",
            volume: TankVolume.parse("~75 gal")!,
            kind: .saltwater,
            createdAt: Fixture.date(2026, 1, 1),
            notes: "corner tank, west sun"
        ),
        Tank(
            id: quarID,
            name: "Quarantine \"B\" , deep",
            volume: nil,
            kind: .other,
            createdAt: Fixture.date(2026, 2, 2),
            notes: "user text with \n newline stays verbatim"
        ),
    ]
    let events = [
        Fixture.event(Fixture.date(2026, 5, 1, 8, 30), .waterChange(percentOfVolume: 25, volumeLiters: nil, note: "25%"), id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
        Fixture.event(Fixture.date(2026, 5, 2, 9, 0), .testReading(parameter: "pH", rawValue: "7.8", note: nil), id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
        Fixture.event(Fixture.date(2026, 5, 3, 9, 0), .testReading(parameter: "NO3", rawValue: "n/a", note: "meter glitch"), id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!),
        Fixture.event(Fixture.date(2026, 5, 4, 9, 0), .dose(substance: "Excel", amount: "5 drops", note: nil), id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
        Fixture.event(Fixture.date(2026, 5, 5, 9, 0), .livestockAdded(species: "Cardinal tetra", quantity: 6, note: nil), id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!),
        Fixture.event(Fixture.date(2026, 5, 6, 9, 0), .livestockRemoved(species: "Cardinal tetra", quantity: 1, note: "death"), id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!),
        Fixture.event(Fixture.date(2026, 5, 7, 9, 0), .livestockObserved(species: "Nerite snail", note: "spawned"), id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!),
        Fixture.event(Fixture.date(2026, 5, 8, 9, 0), .equipment(name: "Canister filter", note: "serviced"), id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
        Fixture.event(Fixture.date(2026, 5, 9, 9, 0), .note("Ran light 6h only"), id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!),
        Fixture.event(Fixture.date(2026, 5, 10, 9, 0), .correction(targetEventID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, note: "Undo"), id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!),
    ]
    let bands = [
        BackupReferenceBand(tankID: reefID, band: ReferenceBand(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            parameter: "pH", label: "  my tank's norm ", rawLow: " 7.2 ", rawHigh: "7.9"
        )),
        BackupReferenceBand(tankID: quarID, band: ReferenceBand(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            parameter: "NO3", label: "keep under", rawLow: nil, rawHigh: "20"
        )),
    ]
    return BackupDocument(
        exportedAt: Fixture.date(2026, 6, 1, 12, 0),
        tanks: tanks,
        events: events,
        bands: bands
    )
}

@Suite("BackupCodec — versioned JSON round-trip")
struct BackupCodecTests {
    @Test("a full document round-trips byte-equal after re-encode")
    func fullRoundTrip() throws {
        let document = backupFixture()
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded == document)

        // Re-encoding the decoded document produces identical bytes.
        let reEncoded = try BackupCodec.encode(decoded)
        let originalEncoded = try BackupCodec.encode(document)
        #expect(reEncoded == originalEncoded)
    }

    @Test("every user string survives verbatim: bands, notes, raw inputs")
    func verbatimEcho() throws {
        let document = backupFixture()
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))

        let quarantine = decoded.tanks.first { $0.name.hasPrefix("Quarantine") }
        #expect(quarantine?.notes == "user text with \n newline stays verbatim")
        #expect(quarantine?.name == "Quarantine \"B\" , deep")
        #expect(decoded.tanks.first { $0.name == "75 Reef" }?.volume?.rawInput == "~75 gal")

        let band = decoded.bands.first { $0.band.parameter == "pH" }
        #expect(band?.band.label == "  my tank's norm ")
        #expect(band?.band.rawLow == " 7.2 ")
        #expect(band?.band.rawHigh == "7.9")
        // Band → tank association is preserved.
        #expect(band?.tankID == UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }

    @Test("encode(tanks:events:bands:) matches a hand-built document encoding")
    func convenienceEncoderEquivalence() throws {
        let document = backupFixture()
        let direct = try BackupCodec.encode(
            tanks: document.tanks,
            events: document.events,
            bands: document.bands,
            exportedAt: document.exportedAt
        )
        let documentEncoded = try BackupCodec.encode(document)
        #expect(direct == documentEncoded)
    }

    @Test("schema versions newer than this build are refused, not guessed")
    func futureVersionRefused() {
        let newer = """
        {"schemaVersion": 999, "exportedAt": 0, "tanks": [], "events": [], "bands": []}
        """
        #expect(throws: BackupCodecError.unsupportedSchemaVersion(999)) {
            try BackupCodec.decode(Data(newer.utf8))
        }
        let zero = """
        {"schemaVersion": 0, "exportedAt": 0, "tanks": [], "events": [], "bands": []}
        """
        #expect(throws: BackupCodecError.unsupportedSchemaVersion(0)) {
            try BackupCodec.decode(Data(zero.utf8))
        }
    }

    @Test("current version decodes and preview reports exact counts and names")
    func previewCounts() throws {
        let document = backupFixture()
        let preview = try BackupCodec.preview(BackupCodec.encode(document))
        #expect(preview.schemaVersion == BackupDocument.currentVersion)
        #expect(preview.exportedAt == document.exportedAt)
        #expect(preview.tankCount == 2)
        #expect(preview.eventCount == 10)
        #expect(preview.bandCount == 2)
        #expect(preview.tankNames == ["75 Reef", "Quarantine \"B\" , deep"])
    }

    @Test("preview refuses a future-version archive without throwing it away silently")
    func previewRefusesFutureVersion() {
        let newer = """
        {"schemaVersion": 2, "exportedAt": 0, "tanks": [], "events": [], "bands": []}
        """
        #expect(throws: BackupCodecError.unsupportedSchemaVersion(2)) {
            try BackupCodec.preview(Data(newer.utf8))
        }
    }

    // MARK: Round-trip property over generated documents

    /// Small deterministic PRNG so the property test is reproducible on
    /// Linux CI and macOS CI alike (no hidden system entropy).
    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
            return mixed ^ (mixed >> 31)
        }
        mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    }

    @Test("property: encode∘decode is identity across generated documents", arguments: 0..<40)
    func roundTripProperty(seedOffset: Int) throws {
        var rng = SplitMix64(seed: UInt64(seedOffset) &* 0x1000_0000_0000_0001)
        let tankCount = 1 + rng.int(4)
        var tanks: [Tank] = []
        var events: [TankEvent] = []
        var bands: [BackupReferenceBand] = []

        let rawTexts = [
            "7.8", " n/a ", "12,5", "\"quoted\"", "value,with,commas", "line\nbreak",
            "", "  ", "≈", "-3.5", "0", "1e5", "tab\tvalue", "emoji 🐟 reading",
        ]
        for _ in 0..<tankCount {
            let tankID = UUID(uuidString: String(
                format: "%08X-0000-0000-0000-000000000000", rng.int(0x7FFFFFFF)
            ))!
            tanks.append(Tank(
                id: tankID,
                name: "Tank \(rng.int(1000)) \(rawTexts[rng.int(rawTexts.count)])",
                volume: rng.int(3) == 0 ? nil : TankVolume.parse("\(rng.int(400) + 1) L"),
                kind: TankKind.allCases[rng.int(TankKind.allCases.count)],
                createdAt: Fixture.date(2026, 1 + rng.int(12), 1 + rng.int(28)),
                notes: rawTexts[rng.int(rawTexts.count)]
            ))
            let eventCount = rng.int(6)
            var timestamp = Fixture.date(2026, 1, 1)
            for _ in 0..<eventCount {
                timestamp = timestamp.addingTimeInterval(TimeInterval(1 + rng.int(100_000)))
                let payload: TankEventPayload
                switch rng.int(9) {
                case 0:
                    payload = .waterChange(
                        percentOfVolume: rng.int(2) == 0 ? Decimal(rng.int(100)) : nil,
                        volumeLiters: rng.int(2) == 0 ? Decimal(rng.int(200)) : nil,
                        note: rng.int(2) == 0 ? rawTexts[rng.int(rawTexts.count)] : nil
                    )
                case 1:
                    payload = .testReading(
                        parameter: rawTexts[rng.int(rawTexts.count)],
                        rawValue: rawTexts[rng.int(rawTexts.count)],
                        note: rng.int(2) == 0 ? rawTexts[rng.int(rawTexts.count)] : nil
                    )
                case 2:
                    payload = .dose(
                        substance: rawTexts[rng.int(rawTexts.count)],
                        amount: rng.int(2) == 0 ? rawTexts[rng.int(rawTexts.count)] : nil,
                        note: nil
                    )
                case 3:
                    payload = .livestockAdded(species: "Species \(rng.int(5))", quantity: rng.int(10), note: nil)
                case 4:
                    payload = .livestockRemoved(species: "Species \(rng.int(5))", quantity: rng.int(10), note: rawTexts[rng.int(rawTexts.count)])
                case 5:
                    payload = .livestockObserved(species: "Species \(rng.int(5))", note: rawTexts[rng.int(rawTexts.count)])
                case 6:
                    payload = .equipment(name: rawTexts[rng.int(rawTexts.count)], note: nil)
                case 7:
                    payload = .note(rawTexts[rng.int(rawTexts.count)])
                default:
                    payload = .correction(targetEventID: UUID(), note: nil)
                }
                events.append(TankEvent(tankID: tankID, timestamp: timestamp, payload: payload))
            }
            if rng.int(2) == 0 {
                bands.append(BackupReferenceBand(tankID: tankID, band: ReferenceBand(
                    parameter: rawTexts[rng.int(rawTexts.count)],
                    label: rawTexts[rng.int(rawTexts.count)],
                    rawLow: rng.int(2) == 0 ? rawTexts[rng.int(rawTexts.count)] : nil,
                    rawHigh: rng.int(2) == 0 ? rawTexts[rng.int(rawTexts.count)] : nil
                )))
            }
        }

        let document = BackupDocument(
            exportedAt: Fixture.date(2026, 7, 1),
            tanks: tanks,
            events: events,
            bands: bands
        )
        let encoded = try BackupCodec.encode(document)
        let decoded = try BackupCodec.decode(encoded)
        #expect(decoded == document)
        #expect(try BackupCodec.encode(decoded) == encoded)
    }
}
