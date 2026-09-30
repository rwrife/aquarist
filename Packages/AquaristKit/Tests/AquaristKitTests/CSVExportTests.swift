import Foundation
import Testing
@testable import AquaristKit

// MARK: - CSV export: quoting, columns, ordering, verbatim user text

@Suite("CSVExport — per-tank ledger")
struct CSVLedgerTests {
    @Test("header is stable and one row per event in chronological order")
    func headerAndOrdering() {
        let tank = Tank(id: Fixture.tankID, name: "Reef", volume: nil, createdAt: Fixture.date(2026, 1, 1))
        let early = Fixture.event(Fixture.date(2026, 5, 1), .note("early"))
        let late = Fixture.event(Fixture.date(2026, 4, 1), .note("late"))
        let csv = CSVExport.tankLedgerCSV(tank: tank, events: [late, early])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(lines.count == 3) // header + 2 events
        let header = lines[0].split(separator: ",")
        #expect(header.first == "tank_name")
        #expect(header.last == "note")
        // Sorted oldest-first even though input was reversed.
        #expect(lines[1].contains("late"))
        #expect(lines[2].contains("early"))
        #expect(csv.hasSuffix("\n"))
    }

    @Test("user text with commas, quotes, and newlines is RFC-4180 quoted")
    func quoting() {
        #expect(CSVExport.csvQuote("plain") == "plain")
        #expect(CSVExport.csvQuote("a,b") == "\"a,b\"")
        #expect(CSVExport.csvQuote("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.csvQuote("two\nlines") == "\"two\nlines\"")
        #expect(CSVExport.csvQuote("") == "")
    }

    @Test("every payload kind populates its own columns and keeps user text verbatim")
    func allKindsColumns() throws {
        let tank = Tank(id: Fixture.tankID, name: "T", volume: nil, createdAt: Fixture.date(2026, 1, 1))
        let target = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let payloads: [TankEventPayload] = [
            .waterChange(percentOfVolume: 25, volumeLiters: 50, note: nil),
            .testReading(parameter: "pH", rawValue: " 7.8 ", note: nil),
            .dose(substance: "Excel", amount: "5 drops", note: nil),
            .livestockAdded(species: "Cory", quantity: 6, note: nil),
            .livestockRemoved(species: "Cory", quantity: 1, note: "death"),
            .livestockObserved(species: "Nerite", note: "spawned"),
            .equipment(name: "Filter", note: "serviced"),
            .note("plain note"),
            .correction(targetEventID: target, note: "Undo"),
        ]
        let base = Fixture.date(2026, 5, 1)
        let events = payloads.enumerated().map { index, payload in
            Fixture.event(base.addingTimeInterval(TimeInterval(index * 60)), payload)
        }
        let csv = CSVExport.tankLedgerCSV(tank: tank, events: events)
        let rows = try csv
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map { try csvFields(from: String($0)) }
        #expect(rows.count == 9)

        #expect(rows[0][3] == "waterChange" && rows[0][10] == "25" && rows[0][11] == "50")
        #expect(rows[1][3] == "testReading" && rows[1][4] == "pH" && rows[1][5] == " 7.8 ")
        #expect(rows[2][3] == "dose" && rows[2][6] == "Excel" && rows[2][7] == "5 drops")
        #expect(rows[3][3] == "livestockAdded" && rows[3][8] == "Cory" && rows[3][9] == "6")
        #expect(rows[4][3] == "livestockRemoved" && rows[4][14] == "death")
        #expect(rows[5][3] == "livestockObserved" && rows[5][14] == "spawned")
        #expect(rows[6][3] == "equipment" && rows[6][12] == "Filter")
        #expect(rows[7][3] == "note" && rows[7][14] == "plain note")
        #expect(rows[8][3] == "correction" && rows[8][13] == target.uuidString)
    }

    @Test("timestamps are ISO 8601 UTC")
    func timestamps() {
        let tank = Tank(id: Fixture.tankID, name: "T", volume: nil, createdAt: Fixture.date(2026, 1, 1))
        let csv = CSVExport.tankLedgerCSV(tank: tank, events: [
            Fixture.event(Fixture.date(2026, 3, 15, 14, 30), .note("x")),
        ])
        #expect(csv.contains("2026-03-15T14:30:00Z"))
    }
}

@Suite("CSVExport — per-parameter reading series")
struct CSVSeriesTests {
    @Test("series carries verbatim raw text; unparseable rows leave parsed blank")
    func verbatimRawAndBlankParse() throws {
        let tank = Tank(id: Fixture.tankID, name: "Reef", volume: nil, createdAt: Fixture.date(2026, 1, 1))
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 5, 1), .testReading(parameter: "pH", rawValue: "7.8", note: nil)),
            Fixture.event(Fixture.date(2026, 5, 2), .testReading(parameter: "pH", rawValue: "high-ish", note: nil)),
        ])
        guard case let .known(points) = Derivations.readingSeries(parameter: "pH", ledger: ledger) else {
            Issue.record("expected a known reading series")
            return
        }
        let csv = CSVExport.readingSeriesCSV(tank: tank, parameter: "pH", points: points)
        let rows = csv.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().map { String($0) }
        #expect(rows.count == 2)
        #expect(rows[0] == "Reef,pH,2026-05-01T12:00:00Z,7.8,7.8")
        #expect(rows[1] == "Reef,pH,2026-05-02T12:00:00Z,high-ish,")
    }

    @Test("empty series exports header only")
    func emptySeries() {
        let tank = Tank(id: Fixture.tankID, name: "T", volume: nil, createdAt: Fixture.date(2026, 1, 1))
        let csv = CSVExport.readingSeriesCSV(tank: tank, parameter: "pH", points: [])
        #expect(csv == "tank_name,parameter,timestamp,raw_value,parsed_value\n")
    }
}

// MARK: - Minimal RFC 4180 field parser used only to inspect exported rows

private func csvFields(from row: String) throws -> [String] {
    var fields: [String] = []
    var current = ""
    var insideQuotes = false
    var iterator = row.makeIterator()
    while let character = iterator.next() {
        switch (character, insideQuotes) {
        case ("\"", false):
            insideQuotes = true
        case ("\"", true):
            if iterator.next() == "\"" {
                current.append("\"") // doubled quote inside quoted field
            } else {
                insideQuotes = false
            }
        case (",", false):
            fields.append(current)
            current = ""
        default:
            current.append(character)
        }
    }
    fields.append(current)
    return fields
}
