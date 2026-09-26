import Foundation
import AquaristKit
import AquaristStore

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: fixture-seed <output.sqlite>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: outputURL)

func id(_ value: String) -> UUID { UUID(uuidString: value)! }
func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

let tankID = id("11111111-1111-1111-1111-111111111111")
let secondTankID = id("22222222-2222-2222-2222-222222222222")

let store = try AquaristStore.open(at: outputURL)
try store.tanks.upsert(Tank(
    id: tankID,
    name: "Fixture Reef",
    volume: TankVolume.parse("approx 75 gal"),
    createdAt: date(1_000)
))
try store.tanks.upsert(Tank(
    id: secondTankID,
    name: "Fixture Quarantine",
    volume: nil,
    createdAt: date(2_000)
))

let events: [TankEvent] = [
    TankEvent(
        id: id("33333333-3333-3333-3333-333333333333"),
        tankID: tankID,
        timestamp: date(3_000),
        payload: .testReading(parameter: "NO3", rawValue: "20", note: nil)
    ),
    TankEvent(
        id: id("44444444-4444-4444-4444-444444444444"),
        tankID: tankID,
        timestamp: date(4_000),
        payload: .testReading(parameter: "pH", rawValue: "7.8", note: "fixture")
    ),
    TankEvent(
        id: id("55555555-5555-5555-5555-555555555555"),
        tankID: tankID,
        timestamp: date(5_000),
        payload: .testReading(parameter: "NO3", rawValue: "10 ppm", note: nil)
    ),
    TankEvent(
        id: id("66666666-6666-6666-6666-666666666666"),
        tankID: secondTankID,
        timestamp: date(6_000),
        payload: .note("Fixture quarantine note")
    ),
]
for event in events { try store.events.append(event) }

let bands: [(ReferenceBand, UUID)] = [
    (ReferenceBand(id: id("77777777-7777-7777-7777-777777777777"), parameter: "pH", label: "fixture target", rawLow: "7.2", rawHigh: "7.9"), tankID),
    (ReferenceBand(id: id("88888888-8888-8888-8888-888888888888"), parameter: "NO3", label: "fixture max", rawLow: nil, rawHigh: "20"), tankID),
    (ReferenceBand(id: id("99999999-9999-9999-9999-999999999999"), parameter: "pH", label: "quarantine reference", rawLow: nil, rawHigh: nil), secondTankID),
]
for (band, owner) in bands { try store.referenceBands.upsert(band, for: owner) }

let usage = try store.storageUsage()
let expected = StorageUsage.TableCounts(tanks: 2, tankEvents: 4, referenceBands: 3)
guard usage.rows == expected else {
    fatalError("seed verification failed: \(usage.rows) != \(expected)")
}
print("Seeded \(outputURL.path): \(usage.rows)")
