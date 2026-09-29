import AquaristKit
import Charts
import Foundation
import SwiftUI

private enum HistoryKind: String, CaseIterable, Identifiable {
    case all = "All"
    case water = "Water changes"
    case readings = "Readings"
    case doses = "Doses"
    case livestock = "Livestock"
    case equipment = "Equipment"
    case notes = "Notes"
    case corrections = "Corrections"

    var id: String { rawValue }

    func includes(_ payload: TankEventPayload) -> Bool {
        switch payload {
        case .waterChange: return self == .all || self == .water
        case .testReading: return self == .all || self == .readings
        case .dose: return self == .all || self == .doses
        case .livestockAdded, .livestockRemoved, .livestockObserved:
            return self == .all || self == .livestock
        case .equipment: return self == .all || self == .equipment
        case .note: return self == .all || self == .notes
        case .correction: return self == .all || self == .corrections
        }
    }
}

struct TankReviewView: View {
    let events: [TankEvent]
    let bands: [ReferenceBand]

    @State private var filter: HistoryKind = .all
    @State private var parameter: String = ""

    private var ledger: EventLedger { EventLedger(events: events) }
    private var parameters: [String] {
        Array(Set(ledger.effectiveEvents.compactMap { event -> String? in
            if case let .testReading(parameter, _, _) = event.payload { return parameter }
            return nil
        })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            trends
            roster
            history
        }
        .onChange(of: parameters) { _, values in
            if !values.contains(parameter) { parameter = values.first ?? "" }
        }
        .onAppear { parameter = parameters.first ?? "" }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.title2.bold())
            Picker("Event kind", selection: $filter) {
                ForEach(HistoryKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("history.filter")

            let selected = ledger.events.filter { filter.includes($0.payload) }
            if selected.isEmpty {
                Text(events.isEmpty ? "No events recorded yet." : "No events for this filter.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("history.empty")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(selected) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.payload.reviewTitle).font(.headline)
                            Text(event.timestamp, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            let lines = event.payload.reviewLines
                            ForEach(lines.indices, id: \.self) { index in
                                Text(lines[index]).font(.body).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("history.event.\(event.id.uuidString)")
                    }
                }
            }
        }
    }

    private var trends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading trends").font(.title2.bold())
            if parameters.isEmpty {
                Text("No readings recorded yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("trends.empty")
            } else {
                Picker("Parameter", selection: $parameter) {
                    ForEach(parameters, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("trends.parameter")
                if case let .known(points) = Derivations.readingSeries(parameter: parameter, ledger: ledger) {
                    let runs = Derivations.numericReadingRuns(points: points)
                    if runs.isEmpty {
                        Text("No numeric readings to plot. Recorded text appears below.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("trends.noNumeric")
                    } else {
                        Chart {
                            // Each run ends at an unparseable record. Separate series
                            // prevent Charts from bridging that missing value.
                            ForEach(runs) { run in
                                ForEach(run.points) { point in
                                    LineMark(
                                        x: .value("Date", point.timestamp),
                                        y: .value(parameter, NSDecimalNumber(decimal: point.value).doubleValue),
                                        series: .value("Continuous run", run.id)
                                    )
                                }
                            }
                            ForEach(runs.flatMap(\.points)) { point in
                                PointMark(x: .value("Date", point.timestamp),
                                          y: .value(parameter, NSDecimalNumber(decimal: point.value).doubleValue))
                                    .symbolSize(75)
                                    .accessibilityLabel("\(parameter), \(point.rawValue)")
                                    .accessibilityValue(point.timestamp.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .chartLegend(.hidden)
                        .chartXAxisLabel("Date")
                        .chartYAxisLabel(parameter)
                        .frame(height: 220)
                        .accessibilityLabel("\(parameter) readings by date")
                        .accessibilityIdentifier("trends.chart")
                    }
                    if points.contains(where: { $0.parsedValue == nil }) {
                        Text("Unparseable readings leave gaps in the line; their original text appears below.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("trends.gaps")
                    }
                    Text("Recorded values").font(.headline)
                    ForEach(points.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline) {
                            Text(points[index].timestamp, format: .dateTime.year().month().day().hour().minute())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(points[index].rawValue).textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("trends.reading.\(index)")
                    }
                }
            }
            if !bands.isEmpty {
                Text("Your recorded bands").font(.headline)
                ForEach(bands) { band in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(band.parameter): \(band.label)")
                        if let low = band.rawLow { Text("Low: \(low)") }
                        if let high = band.rawHigh { Text("High: \(high)") }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Livestock roster").font(.title2.bold())
            let entries = Derivations.livestockRosterEntries(ledger: ledger)
            if entries.isEmpty {
                Text("No livestock events recorded yet. Current stock is unknown.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("roster.empty")
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.species).font(.headline)
                        switch entry.quantity {
                        case let .known(quantity): Text("Recorded quantity: \(quantity)")
                        case .unknown: Text("Recorded quantity: Unknown")
                        }
                        if let date = entry.firstAddedAt {
                            Text("First added: \(date.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            Text("First added: Unknown")
                        }
                        Text("Last activity: \(entry.lastActivityAt.formatted(date: .abbreviated, time: .shortened))")
                        ForEach(entry.observations) { observation in
                            VStack(alignment: .leading) {
                                Text("Observed: \(observation.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                if let note = observation.note { Text(note).textSelection(.enabled) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("roster.species.\(entry.species)")
                }
            }
        }
    }
}

private extension TankEventPayload {
    var reviewTitle: String {
        switch self {
        case .waterChange: "Water change"
        case .testReading: "Test reading"
        case .dose: "Dose"
        case .livestockAdded: "Livestock added"
        case .livestockRemoved: "Livestock removed"
        case .livestockObserved: "Livestock observed"
        case .equipment: "Equipment"
        case .note: "Note"
        case .correction: "Correction"
        }
    }

    var reviewLines: [String] {
        switch self {
        case let .waterChange(percent, liters, note):
            return [percent.map { "Percent: \($0)%" }, liters.map { "Volume: \($0) L" }, note].compactMap { $0 }
        case let .testReading(parameter, raw, note):
            return ["\(parameter): \(raw)", note].compactMap { $0 }
        case let .dose(substance, amount, note):
            return [substance, amount, note].compactMap { $0 }
        case let .livestockAdded(species, quantity, note),
             let .livestockRemoved(species, quantity, note):
            return ["\(species): \(quantity)", note].compactMap { $0 }
        case let .livestockObserved(species, note), let .equipment(species, note):
            return [species, note].compactMap { $0 }
        case let .note(text): return [text]
        case let .correction(target, note): return ["Event: \(target.uuidString)", note].compactMap { $0 }
        }
    }
}
