import Foundation

/// CSV export for per-tank ledgers and per-parameter reading series.
///
/// Output is RFC 4180 compliant: fields containing commas, double quotes, or
/// newlines are quoted; embedded quotes are doubled. Timestamps are ISO 8601
/// in UTC (no fractional seconds — husbandry logs do not need sub-second
/// precision). No network, no permissions; the app target hands the resulting
/// string to the system share sheet.
public enum CSVExport {

    // MARK: - Per-tank ledger

    /// Full chronological ledger for one tank. Columns are stable across
    /// app versions so external tools can parse them.
    public static func tankLedgerCSV(tank: Tank, events: [TankEvent]) -> String {
        let header = [
            "tank_name", "event_id", "timestamp", "kind",
            "parameter", "value", "substance", "amount",
            "species", "quantity", "percent", "liters",
            "equipment", "target_event_id", "note",
        ]
        var rows = [header.joined(separator: ",")]
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            rows.append(row(for: tank, event: event))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Per-parameter reading series

    /// A single parameter's chronological reading series for one tank.
    /// Includes both the user's verbatim raw value and the strict parse
    /// result (empty when the raw text is unparseable — the domain's
    /// unknown-safe semantics are preserved in the export).
    public static func readingSeriesCSV(
        tank: Tank,
        parameter: String,
        points: [Derivations.ReadingPoint]
    ) -> String {
        let header = ["tank_name", "parameter", "timestamp", "raw_value", "parsed_value"]
        var rows = [header.joined(separator: ",")]
        for point in points {
            let parsed = point.parsedValue.map { "\($0)" } ?? ""
            rows.append([
                csvQuote(tank.name),
                csvQuote(parameter),
                csvQuote(iso8601(point.timestamp)),
                csvQuote(point.rawValue),
                csvQuote(parsed),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func row(for tank: Tank, event: TankEvent) -> String {
        let kind: String
        var parameter = ""
        var value = ""
        var substance = ""
        var amount = ""
        var species = ""
        var quantity = ""
        var percent = ""
        var liters = ""
        var equipment = ""
        var targetEventID = ""
        var note = ""

        switch event.payload {
        case let .waterChange(p, l, n):
            kind = "waterChange"
            percent = p.map { "\($0)" } ?? ""
            liters = l.map { "\($0)" } ?? ""
            note = n ?? ""
        case let .testReading(p, v, n):
            kind = "testReading"
            parameter = p
            value = v
            note = n ?? ""
        case let .dose(s, a, n):
            kind = "dose"
            substance = s
            amount = a ?? ""
            note = n ?? ""
        case let .livestockAdded(s, q, n):
            kind = "livestockAdded"
            species = s
            quantity = "\(q)"
            note = n ?? ""
        case let .livestockRemoved(s, q, n):
            kind = "livestockRemoved"
            species = s
            quantity = "\(q)"
            note = n ?? ""
        case let .livestockObserved(s, n):
            kind = "livestockObserved"
            species = s
            note = n ?? ""
        case let .equipment(name, n):
            kind = "equipment"
            equipment = name
            note = n ?? ""
        case let .note(n):
            kind = "note"
            note = n
        case let .correction(target, n):
            kind = "correction"
            targetEventID = target.uuidString
            note = n ?? ""
        }

        return [
            csvQuote(tank.name),
            csvQuote(event.id.uuidString),
            csvQuote(iso8601(event.timestamp)),
            csvQuote(kind),
            csvQuote(parameter),
            csvQuote(value),
            csvQuote(substance),
            csvQuote(amount),
            csvQuote(species),
            csvQuote(quantity),
            csvQuote(percent),
            csvQuote(liters),
            csvQuote(equipment),
            csvQuote(targetEventID),
            csvQuote(note),
        ].joined(separator: ",")
    }

    /// RFC 4180 quoting: quote when the field contains a comma, double
    /// quote, or newline; double any embedded quotes.
    static func csvQuote(_ field: String) -> String {
        let needsQuoting = field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// ISO 8601 UTC timestamp, second granularity. Fresh formatter per
    /// call to avoid the Swift 6 non-Sendable global trap.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
