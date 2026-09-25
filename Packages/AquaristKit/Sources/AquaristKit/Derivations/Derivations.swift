import Foundation

/// Unknown-safe, DST-safe derivations over a tank's event ledger.
///
/// Every function here:
/// - takes an explicit `now` and `Calendar` (no hidden clocks — tests can
///   cross DST boundaries deterministically);
/// - returns `.unknown` when the underlying data is missing, never a
///   default number;
/// - performs day/week math through `Calendar` (era-based day and week
///   boundaries), so a 23- or 25-hour wall-clock day never shifts a result.
public enum Derivations {

    // MARK: - Days since water change

    /// Whole calendar days between the most recent water-change event and
    /// `now` (same day → 0). `.unknown` when the ledger has no water
    /// changes at all.
    public static func daysSinceWaterChange(
        ledger: EventLedger,
        now: Date,
        calendar: Calendar
    ) -> Derivation<Int> {
        guard let last = lastWaterChange(in: ledger) else { return .unknown }
        return .known(calendar.dayDistance(from: last.timestamp, to: now))
    }

    // MARK: - Day streak

    /// Consecutive calendar days (ending at `now`'s day) that contain at
    /// least one ledger event. `.unknown` for an empty ledger; `0` when
    /// the most recent event day is not `now`'s day.
    public static func dayStreak(
        ledger: EventLedger,
        now: Date,
        calendar: Calendar
    ) -> Derivation<Int> {
        guard !ledger.events.isEmpty else { return .unknown }

        let loggedDays = Set(ledger.events.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: now)
        guard loggedDays.contains(today) else { return .known(0) }

        var streak = 1
        var cursor = today
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor),
              loggedDays.contains(previous) {
            streak += 1
            cursor = previous
        }
        return .known(streak)
    }

    // MARK: - Weekly water-change volume totals (DST-safe)

    /// One bucket per calendar week.
    public struct WeeklyWaterChangeTotal: Equatable, Sendable {
        /// First instant of the week per `calendar.firstWeekday`/week rules.
        public let weekStart: Date
        /// `.known(liters)` when every contributing event resolved to a
        /// liter amount; `.unknown` when any contributing event was a
        /// percent-of-volume with no tank volume to convert against.
        public let liters: Derivation<Decimal>
    }

    /// Sum of water-change volumes per calendar week for the most recent
    /// `weekCount` weeks ending with `now`'s week (inclusive, oldest
    /// first).
    ///
    /// A water change contributes its explicit `volumeLiters`, or — when
    /// only `percentOfVolume` was logged — `percent × tank.volume` when
    /// the tank volume is known. Percent-only events with an unknown tank
    /// volume make that week `.unknown` (never silently skipped or zeroed).
    /// Weeks inside the window with no water changes report `.known(0)`.
    public static func weeklyWaterChangeTotals(
        ledger: EventLedger,
        tank: Tank,
        now: Date,
        calendar: Calendar,
        weekCount: Int
    ) -> [WeeklyWaterChangeTotal] {
        precondition(weekCount > 0, "weekCount must be positive")

        let thisWeekStart = weekStart(for: now, calendar: calendar)
        guard let firstWeekStart = calendar.date(
            byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeekStart
        ) else {
            return []
        }

        // Index water-change events by their week start.
        var buckets: [Date: [TankEvent]] = [:]
        for event in ledger.events {
            guard case .waterChange = event.payload else { continue }
            let ws = weekStart(for: event.timestamp, calendar: calendar)
            buckets[ws, default: []].append(event)
        }

        var results: [WeeklyWaterChangeTotal] = []
        var cursor = firstWeekStart
        for _ in 0..<weekCount {
            let events = buckets[cursor] ?? []
            var total = Decimal(0)
            var unresolvedPercentOnly = false
            for event in events {
                guard case let .waterChange(percent, liters, _) = event.payload else { continue }
                if let liters {
                    total += liters
                } else if let percent, let volume = tank.volume {
                    total += volume.liters(forPercentOfVolume: percent)
                } else {
                    unresolvedPercentOnly = true
                }
            }
            results.append(
                WeeklyWaterChangeTotal(
                    weekStart: cursor,
                    liters: unresolvedPercentOnly ? .unknown : .known(total)
                )
            )
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? cursor
        }
        return results
    }

    // MARK: - Last-dose age

    /// Whole calendar days between the most recent dose event and `now`
    /// (same day → 0). `.unknown` when no dose has ever been logged.
    public static func lastDoseAgeInDays(
        ledger: EventLedger,
        now: Date,
        calendar: Calendar
    ) -> Derivation<Int> {
        guard let last = ledger.events.last(where: {
            if case .dose = $0.payload { return true }
            return false
        }) else {
            return .unknown
        }
        return .known(calendar.dayDistance(from: last.timestamp, to: now))
    }

    // MARK: - Per-parameter raw reading series

    /// One point of a raw trend series. `parsedValue` is a convenience
    /// parse of the user's verbatim `rawValue`; it is `nil` when the user
    /// text does not parse — the raw text is still echoed.
    public struct ReadingPoint: Codable, Equatable, Sendable {
        public let timestamp: Date
        public let rawValue: String
        public let parsedValue: Decimal?
    }

    /// Raw, chronological per-parameter reading series — no smoothing,
    /// no modeling, no aggregation. `.unknown` when the parameter has no
    /// readings at all.
    public static func readingSeries(
        parameter: String,
        ledger: EventLedger
    ) -> Derivation<[ReadingPoint]> {
        let points: [ReadingPoint] = ledger.events.compactMap { event in
            guard case let .testReading(eventParameter, rawValue, _) = event.payload,
                  eventParameter == parameter else { return nil }
            return ReadingPoint(
                timestamp: event.timestamp,
                rawValue: rawValue,
                parsedValue: StrictDecimal.parse(rawValue)
            )
        }
        guard !points.isEmpty else { return .unknown }
        return .known(points)
    }

    // MARK: - Livestock roster (current state derived from roster events)

    /// Per-species present-count derived from add/remove events.
    /// Removals can never push a count below zero (the ledger stays
    /// honest; an over-removal clamps display at 0 but the events remain).
    public static func livestockRoster(
        ledger: EventLedger
    ) -> [String: Int] {
        var roster: [String: Int] = [:]
        for event in ledger.events {
            switch event.payload {
            case let .livestockAdded(species, quantity, _):
                roster[species, default: 0] += quantity
            case let .livestockRemoved(species, quantity, _):
                roster[species, default: 0] = max(0, (roster[species] ?? 0) - quantity)
            default:
                break
            }
        }
        return roster.filter { $0.value > 0 }
    }

    // MARK: - Helpers

    private static func lastWaterChange(in ledger: EventLedger) -> TankEvent? {
        ledger.events.last {
            if case .waterChange = $0.payload { return true }
            return false
        }
    }

    private static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        // Calendar-based stepping: DST-safe.
        return calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
    }
}

private extension Calendar {
    /// Whole calendar days between two dates, counting day boundaries
    /// (not 24-hour periods) — DST-safe by construction.
    func dayDistance(from earlier: Date, to later: Date) -> Int {
        let start = startOfDay(for: earlier)
        let end = startOfDay(for: later)
        return dateComponents([.day], from: start, to: end).day ?? 0
    }
}
