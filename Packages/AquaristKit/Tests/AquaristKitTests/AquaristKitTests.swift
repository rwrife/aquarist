import Foundation
import Testing
@testable import AquaristKit

// MARK: - Test helpers

/// Fixed reference instants used across suites.
enum Fixture {
    /// 2026-03-07 23:30 America/New_York (EST, UTC-5) — the Saturday
    /// night before US spring-forward (2026-03-08 02:00 → 03:00).
    static func date(
        _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0,
        timeZone: TimeZone = .gmt
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d; comp.hour = h; comp.minute = mi
        return cal.date(from: comp)!
    }

    static let newYork = TimeZone(identifier: "America/New_York")!

    static let tankID = UUID(uuidString: "0F0F0F0F-0F0F-0F0F-0F0F-0F0F0F0F0F0F")!

    static func event(
        _ timestamp: Date,
        _ payload: TankEventPayload,
        id: UUID = UUID()
    ) -> TankEvent {
        TankEvent(id: id, tankID: tankID, timestamp: timestamp, payload: payload)
    }
}

// MARK: - Workspace layout seam

@Suite("Tank workspace layout — region mapping and continuity")
struct TankWorkspaceLayoutTests {
    @Test("single-pane maps the wall and selected detail to one region at a time")
    func singlePaneRegionMapping() {
        let tankID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        var state = TankWorkspaceLayoutState()

        #expect(state.mode == .singlePane)
        #expect(state.visibleRegions == [.wallControlSurface])

        state.selectTank(tankID)
        #expect(state.visibleRegions == [.detailLedger])

        state.selectTank(nil)
        #expect(state.visibleRegions == [.wallControlSurface])
    }

    @Test("simulated fold transitions preserve selection and both scroll anchors")
    func foldSimulationPreservesContinuity() throws {
        let tankID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let eventID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var state = TankWorkspaceLayoutState()
        state.selectTank(tankID)
        state.updateWallScrollAnchor(tankID)
        state.updateDetailScrollAnchor(eventID)
        let continuity = state.continuity

        state.transition(to: .unfoldedTwoPaneTarget)
        #expect(state.visibleRegions == [.wallControlSurface, .detailLedger])
        #expect(state.continuity == continuity)

        state.transition(to: .singlePane)
        #expect(state.visibleRegions == [.detailLedger])
        #expect(state.continuity == continuity)

        let restored = try JSONDecoder().decode(
            TankWorkspaceLayoutState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(restored == state)
    }
}

// MARK: - Models: Codable round-trip + append-only

@Suite("Models — Codable round-trip")
struct ModelCodableTests {
    @Test("Tank round-trips with a parsed volume")
    func tankRoundTrip() throws {
        let tank = Tank(
            name: "75 Reef",
            volume: TankVolume.parse("approx 75 gal")!,
            createdAt: Fixture.date(2026, 1, 1)
        )
        let data = try JSONEncoder().encode(tank)
        let decoded = try JSONDecoder().decode(Tank.self, from: data)
        #expect(decoded == tank)
        // Verbatim raw input survives the round-trip.
        #expect(decoded.volume?.rawInput == "approx 75 gal")
    }

    @Test("Tank with unknown volume round-trips as nil, not a default")
    func tankUnknownVolumeRoundTrip() throws {
        let tank = Tank(name: "Quarantine", volume: nil)
        let data = try JSONEncoder().encode(tank)
        let decoded = try JSONDecoder().decode(Tank.self, from: data)
        #expect(decoded.volume == nil)
    }

    @Test("Tank kind + notes round-trip verbatim")
    func tankRegistryFieldsRoundTrip() throws {
        let tank = Tank(
            name: "Mangrove",
            volume: TankVolume.parse("20 gal"),
            kind: .brackish,
            createdAt: Fixture.date(2026, 2, 2),
            notes: "  low-flow shelf  "
        )
        let data = try JSONEncoder().encode(tank)
        let decoded = try JSONDecoder().decode(Tank.self, from: data)
        #expect(decoded.kind == .brackish)
        #expect(decoded.notes == "  low-flow shelf  ")
        #expect(decoded == tank)
    }

    @Test("Every event payload kind round-trips")
    func payloadRoundTrip() throws {
        let ts = Fixture.date(2026, 5, 1, 8, 30)
        let payloads: [TankEventPayload] = [
            .waterChange(percentOfVolume: 25, volumeLiters: nil, note: "25%"),
            .waterChange(percentOfVolume: nil, volumeLiters: 50, note: nil),
            .testReading(parameter: "pH", rawValue: "7.8", note: nil),
            .testReading(parameter: "NO3", rawValue: "n/a", note: "meter glitch"),
            .dose(substance: "Excel", amount: "5 drops", note: nil),
            .livestockAdded(species: "Cardinal tetra", quantity: 6, note: nil),
            .livestockRemoved(species: "Cardinal tetra", quantity: 1, note: "death"),
            .livestockObserved(species: "Nerite snail", note: "spawned"),
            .equipment(name: "Canister filter", note: "serviced"),
            .note("Ran light 6h only"),
            .correction(targetEventID: UUID(), note: "Undo"),
        ]
        for payload in payloads {
            let event = TankEvent(tankID: Fixture.tankID, timestamp: ts, payload: payload)
            let decoded = try JSONDecoder().decode(
                TankEvent.self, from: JSONEncoder().encode(event)
            )
            #expect(decoded == event)
        }
    }

    @Test("Ledger encodes events in chronological order and decodes equal")
    func ledgerRoundTrip() throws {
        var ledger = EventLedger()
        ledger.append(Fixture.event(Fixture.date(2026, 2, 1), .note("first")))
        ledger.append(Fixture.event(Fixture.date(2026, 2, 2), .note("second")))
        let decoded = try JSONDecoder().decode(
            EventLedger.self, from: JSONEncoder().encode(ledger)
        )
        #expect(decoded == ledger)
        #expect(decoded.events.map(\.payload) == [.note("first"), .note("second")])
    }
}

@Suite("Ledger — append-only corrections")
struct LedgerCorrectionTests {
    @Test("correction preserves audit rows and retracts target from derivations")
    func correction() {
        let waterChange = Fixture.event(
            Fixture.date(2026, 5, 1),
            .waterChange(percentOfVolume: 25, volumeLiters: nil, note: nil)
        )
        let correction = Fixture.event(
            Fixture.date(2026, 5, 2),
            .correction(targetEventID: waterChange.id, note: "Undo")
        )
        let ledger = EventLedger(events: [waterChange, correction])

        #expect(ledger.events.count == 2)
        #expect(ledger.effectiveEvents.isEmpty)
        #expect(Derivations.daysSinceWaterChange(
            ledger: ledger,
            now: Fixture.date(2026, 5, 3),
            calendar: Calendar(identifier: .gregorian)
        ) == .unknown)
    }
}

@Suite("Ledger — append-only contract")
struct AppendOnlyLedgerTests {
    @Test("construction normalizes out-of-order input to chronological order")
    func constructionSorts() {
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 3, 3), .note("later")),
            Fixture.event(Fixture.date(2026, 3, 1), .note("earlier")),
        ])
        #expect(ledger.events.map(\.timestamp) == [
            Fixture.date(2026, 3, 1), Fixture.date(2026, 3, 3),
        ])
    }

    @Test("no mutation API exists — only append/appending produce changes")
    func appendOnlySurface() {
        // Compile-time contract: EventLedger is a value type whose only
        // mutator is `append`. This test documents that the history array
        // cannot be replaced through the public interface.
        var ledger = EventLedger()
        ledger.append(Fixture.event(Fixture.date(2026, 4, 1), .note("only entry")))
        #expect(ledger.events.count == 1)
    }
}

// MARK: - Volume parsing

@Suite("TankVolume — parse + percent math")
struct TankVolumeTests {
    @Test("exact liter input parses with approximate flag false")
    func exactLiters() {
        let v = TankVolume.parse("200 L")
        #expect(v?.liters == 200)
        #expect(v?.isApproximate == false)
        #expect(v?.rawInput == "200 L")
    }

    @Test("tilde and word approximations set the flag")
    func approximate() {
        #expect(TankVolume.parse("~200 litres")?.isApproximate == true)
        #expect(TankVolume.parse("approx 75 gal")?.isApproximate == true)
        #expect(TankVolume.parse("about 26.5 gal")?.isApproximate == true)
    }

    @Test("unit conversions use exact constants")
    func conversions() {
        let gal = TankVolume.parse("10 gal")!
        #expect(gal.liters == Decimal(string: "37.85411784")!)
        let ml = TankVolume.parse("1500ml")!
        #expect(ml.liters == 1.5)
    }

    @Test("comma-grouped numbers parse; malformed numbers return nil")
    func numberEdges() {
        #expect(TankVolume.parse("1,000 L")?.liters == 1000)
        #expect(TankVolume.parse("not a volume") == nil)
        #expect(TankVolume.parse("200") == nil)          // no unit
        #expect(TankVolume.parse("200 furlongs") == nil) // unknown unit
        #expect(TankVolume.parse("") == nil)
        #expect(TankVolume.parse("0 L") == nil)          // zero is not a tank
        #expect(TankVolume.parse("-5 L") == nil)         // negative impossible
    }

    @Test("percent-of-volume math is exact for typical inputs")
    func percentMath() {
        let v = TankVolume.parse("200 L")!
        #expect(v.liters(forPercentOfVolume: 25) == 50)
        #expect(v.liters(forPercentOfVolume: Decimal(string: "12.5")!) == 25)
        let gal = TankVolume.parse("75 gal")!
        let tenPercent = gal.liters(forPercentOfVolume: 10)
        #expect(tenPercent == Decimal(string: "28.39058838")!) // exact Decimal chain
    }
}

// MARK: - Reference band: verbatim echo, user-statement semantics

@Suite("ReferenceBand — verbatim echo, no verdicts")
struct ReferenceBandTests {
    @Test("all user text is stored and echoed verbatim, including whitespace and odd units")
    func verbatimEcho() {
        let band = ReferenceBand(
            parameter: "pH ",
            label: "  my tank's “norm” ",
            rawLow: " 7.2 ",
            rawHigh: "7.9 ppm-ish"
        )
        #expect(band.parameter == "pH ")
        #expect(band.label == "  my tank's “norm” ")
        #expect(band.rawLow == " 7.2 ")
        #expect(band.rawHigh == "7.9 ppm-ish")

        let decoded = try! JSONDecoder().decode(
            ReferenceBand.self, from: JSONEncoder().encode(band)
        )
        #expect(decoded == band)
    }

    @Test("membership compares only numbers the user themselves entered")
    func membership() {
        let band = ReferenceBand(parameter: "pH", label: "norm", rawLow: "7.2", rawHigh: "7.9")
        #expect(band.membership(ofReadingRawValue: "7.8") == .matchesUserBand)
        #expect(band.membership(ofReadingRawValue: " 7.2 ") == .matchesUserBand) // inclusive bounds
        #expect(band.membership(ofReadingRawValue: "8.1") == .outsideUserBand)
        #expect(band.membership(ofReadingRawValue: "n/a") == .unknown)
    }

    @Test("unparseable band bounds render unknown, never a guess")
    func unknownBand() {
        #expect(ReferenceBand(parameter: "pH", label: "x").membership(ofReadingRawValue: "7") == .unknown)
        let words = ReferenceBand(parameter: "pH", label: "x", rawLow: "kinda low", rawHigh: nil)
        #expect(words.membership(ofReadingRawValue: "7.0") == .unknown)
        // One-sided band: only the stated side is checked.
        let lowOnly = ReferenceBand(parameter: "NO3", label: "keep under", rawLow: nil, rawHigh: "20")
        #expect(lowOnly.membership(ofReadingRawValue: "10") == .matchesUserBand)
        #expect(lowOnly.membership(ofReadingRawValue: "40") == .outsideUserBand)
    }
}

// MARK: - Derivations

@Suite("Derivations — unknown-safe")
struct DerivationUnknownTests {
    @Test("empty ledger: every derivation reports .unknown, never a default number")
    func emptyLedger() {
        let ledger = EventLedger()
        let cal = Calendar(identifier: .gregorian)
        let now = Fixture.date(2026, 6, 1)
        #expect(Derivations.daysSinceWaterChange(ledger: ledger, now: now, calendar: cal) == .unknown)
        #expect(Derivations.dayStreak(ledger: ledger, now: now, calendar: cal) == .unknown)
        #expect(Derivations.lastDoseAgeInDays(ledger: ledger, now: now, calendar: cal) == .unknown)
        #expect(Derivations.readingSeries(parameter: "pH", ledger: ledger) == .unknown)
    }

    @Test("percent-only water change with unknown tank volume → week is .unknown")
    func percentWithoutVolumeUnknown() {
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 6, 1), .waterChange(percentOfVolume: 25, volumeLiters: nil, note: nil)),
        ])
        let tank = Tank(name: "No volume", volume: nil)
        let totals = Derivations.weeklyWaterChangeTotals(
            ledger: ledger, tank: tank,
            now: Fixture.date(2026, 6, 3), calendar: gregorian, weekCount: 1
        )
        #expect(totals.count == 1)
        #expect(totals[0].liters == .unknown)
    }

    @Test("explicit liters and percent×volume both contribute; empty weeks report 0")
    func weeklyTotalsMix() {
        let tank = Tank(name: "Reef", volume: TankVolume.parse("200 L"))
        let ledger = EventLedger(events: [
            // Week of Mon 2026-06-01: 25% of 200 L = 50 L
            Fixture.event(Fixture.date(2026, 6, 2), .waterChange(percentOfVolume: 25, volumeLiters: nil, note: nil)),
            // Same week: explicit 10 L
            Fixture.event(Fixture.date(2026, 6, 3), .waterChange(percentOfVolume: nil, volumeLiters: 10, note: nil)),
        ])
        let totals = Derivations.weeklyWaterChangeTotals(
            ledger: ledger, tank: tank,
            now: Fixture.date(2026, 6, 3), calendar: gregorian, weekCount: 3
        )
        #expect(totals.count == 3)
        #expect(totals[0].liters == .known(0))     // two weeks earlier
        #expect(totals[1].liters == .known(0))
        #expect(totals[2].liters == .known(60))    // current week 50 + 10
    }

    @Test("last-dose age same day is 0; no dose ever is .unknown")
    func lastDoseAge() {
        let cal = Calendar(identifier: .gregorian)
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 7, 10, 9), .dose(substance: "Excel", amount: nil, note: nil)),
        ])
        #expect(Derivations.lastDoseAgeInDays(ledger: ledger, now: Fixture.date(2026, 7, 10, 21), calendar: cal) == .known(0))
        #expect(Derivations.lastDoseAgeInDays(ledger: ledger, now: Fixture.date(2026, 7, 13, 8), calendar: cal) == .known(3))
        let noDoses = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 7, 1), .note("nothing dosed")),
        ])
        #expect(Derivations.lastDoseAgeInDays(ledger: noDoses, now: Fixture.date(2026, 7, 13), calendar: cal) == .unknown)
    }
}

private let gregorian: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .gmt
    cal.firstWeekday = 2 // weeks start Monday for these fixtures
    return cal
}()

// MARK: - DST safety

@Suite("Derivations — DST-safe calendar math")
struct DSTSafetyTests {
    /// US spring-forward 2026: Sun 2026-03-08, 02:00 EST → 03:00 EDT.
    /// A wall-clock interval of ~26h spans 2 calendar days — a naive
    /// 24-hour division returns 1 and fails.
    @Test("days-since crosses spring-forward correctly (26 real hours, 2 calendar days)")
    func springForwardDaysSince() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Fixture.newYork
        let ledger = EventLedger(events: [
            Fixture.event(
                Fixture.date(2026, 3, 7, 23, 30, timeZone: Fixture.newYork),
                .waterChange(percentOfVolume: 50, volumeLiters: 100, note: nil)
            ),
        ])
        let now = Fixture.date(2026, 3, 9, 1, 30, timeZone: Fixture.newYork)
        // Sanity: the wall-clock span really is < 27h (i.e. not 48h).
        let spanHours = now.timeIntervalSince(Fixture.date(2026, 3, 7, 23, 30, timeZone: Fixture.newYork)) / 3600
        // Spring-forward shortens the day: the span is ~25 real hours —
        // far under 48h, so naive 24-hour division would wrongly say 1.
        #expect(spanHours > 24 && spanHours < 26)
        #expect(Derivations.daysSinceWaterChange(ledger: ledger, now: now, calendar: cal) == .known(2))
    }

    /// US fall-back 2026: Sun 2026-11-01, 02:00 EDT → 01:00 EST.
    /// ~50h of real time still means 2 calendar days.
    @Test("days-since crosses fall-back correctly (50 real hours, 2 calendar days)")
    func fallBackDaysSince() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Fixture.newYork
        let ledger = EventLedger(events: [
            Fixture.event(
                Fixture.date(2026, 10, 31, 23, 0, timeZone: Fixture.newYork),
                .waterChange(percentOfVolume: nil, volumeLiters: 30, note: nil)
            ),
        ])
        let now = Fixture.date(2026, 11, 2, 1, 30, timeZone: Fixture.newYork)
        #expect(Derivations.daysSinceWaterChange(ledger: ledger, now: now, calendar: cal) == .known(2))
    }

    @Test("weekly buckets keep events in the right week across the DST spring-forward")
    func weeklyBucketsAcrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Fixture.newYork
        cal.firstWeekday = 2 // Monday-start weeks

        let before = Fixture.date(2026, 3, 7, 23, 0, timeZone: Fixture.newYork)   // Sat, week A
        let after = Fixture.date(2026, 3, 9, 1, 0, timeZone: Fixture.newYork)     // Mon, week B
        let ledger = EventLedger(events: [
            Fixture.event(before, .waterChange(percentOfVolume: nil, volumeLiters: 40, note: nil)),
            Fixture.event(after, .waterChange(percentOfVolume: nil, volumeLiters: 10, note: nil)),
        ])
        let tank = Tank(name: "T", volume: TankVolume.parse("200 L"))
        let totals = Derivations.weeklyWaterChangeTotals(
            ledger: ledger, tank: tank, now: after, calendar: cal, weekCount: 2
        )
        #expect(totals.count == 2)
        #expect(totals[0].liters == .known(40)) // Saturday's bucket
        #expect(totals[1].liters == .known(10)) // Monday's bucket, after DST
    }

    @Test("day streak survives a DST day (23-hour day still counts as a day)")
    func streakAcrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Fixture.newYork
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 3, 6, 22, timeZone: Fixture.newYork), .note("fri")),
            Fixture.event(Fixture.date(2026, 3, 7, 23, 30, timeZone: Fixture.newYork), .note("sat")),
            Fixture.event(Fixture.date(2026, 3, 8, 23, timeZone: Fixture.newYork), .note("sun, short day")),
        ])
        let now = Fixture.date(2026, 3, 8, 23, 45, timeZone: Fixture.newYork)
        #expect(Derivations.dayStreak(ledger: ledger, now: now, calendar: cal) == .known(3))
    }
}

// MARK: - Streak & trend specifics

@Suite("Derivations — streak + raw trend series")
struct StreakAndTrendTests {
    @Test("streak is 0 when the newest event day is not today; resets across a gap")
    func streakBreaks() {
        let cal = Calendar(identifier: .gregorian)
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 8, 1), .note("a")),
            Fixture.event(Fixture.date(2026, 8, 2), .note("b")),
            Fixture.event(Fixture.date(2026, 8, 5), .note("c")),
        ])
        // Today = Aug 5 → streak covers Aug 5 only (Aug 4 missing).
        #expect(Derivations.dayStreak(ledger: ledger, now: Fixture.date(2026, 8, 5, 23), calendar: cal) == .known(1))
        // Today = Aug 6 → streak 0 even though history exists.
        #expect(Derivations.dayStreak(ledger: ledger, now: Fixture.date(2026, 8, 6, 1), calendar: cal) == .known(0))
    }

    @Test("trend series is raw and chronological — no smoothing, unparseable text retained")
    func rawSeries() {
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 9, 1), .testReading(parameter: "NO3", rawValue: "20", note: nil)),
            Fixture.event(Fixture.date(2026, 9, 3), .testReading(parameter: "pH", rawValue: "7.8", note: nil)),
            Fixture.event(Fixture.date(2026, 9, 5), .testReading(parameter: "NO3", rawValue: "10 ppm", note: nil)),
            Fixture.event(Fixture.date(2026, 9, 8), .testReading(parameter: "NO3", rawValue: "5", note: nil)),
        ])
        let series = Derivations.readingSeries(parameter: "NO3", ledger: ledger)
        guard case .known(let points) = series else {
            Issue.record("expected known series"); return
        }
        #expect(points.count == 3)
        #expect(points.map(\.rawValue) == ["20", "10 ppm", "5"]) // verbatim, chronological
        #expect(points[1].parsedValue == nil)                     // unparseable stays nil
        #expect(points[0].parsedValue == 20)
        // Other parameters never leak into the series.
        #expect(Derivations.readingSeries(parameter: "PO4", ledger: ledger) == .unknown)
    }
}

// MARK: - Livestock roster derivation (feed-forward for issue #6)

@Suite("Derivations — livestock roster")
struct LivestockRosterTests {
    @Test("adds and removes compose into a present-count roster")
    func roster() {
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 1, 1), .livestockAdded(species: "Tetra", quantity: 6, note: nil)),
            Fixture.event(Fixture.date(2026, 2, 1), .livestockRemoved(species: "Tetra", quantity: 2, note: nil)),
            Fixture.event(Fixture.date(2026, 3, 1), .livestockAdded(species: "Cory", quantity: 4, note: nil)),
            Fixture.event(Fixture.date(2026, 4, 1), .livestockRemoved(species: "Tetra", quantity: 4, note: nil)),
            Fixture.event(Fixture.date(2026, 5, 1), .livestockObserved(species: "Cory", note: "healthy")),
        ])
        let roster = Derivations.livestockRoster(ledger: ledger)
        #expect(roster == ["Cory": 4]) // Tetra fully removed; observed-only species absent
    }

    @Test("over-removal clamps at zero without corrupting history")
    func overRemoval() {
        let ledger = EventLedger(events: [
            Fixture.event(Fixture.date(2026, 1, 1), .livestockAdded(species: "Snail", quantity: 1, note: nil)),
            Fixture.event(Fixture.date(2026, 1, 2), .livestockRemoved(species: "Snail", quantity: 5, note: "miscount")),
            Fixture.event(Fixture.date(2026, 1, 3), .livestockAdded(species: "Snail", quantity: 2, note: nil)),
        ])
        #expect(Derivations.livestockRoster(ledger: ledger) == ["Snail": 2])
        #expect(ledger.events.count == 3) // history untouched
    }
}
