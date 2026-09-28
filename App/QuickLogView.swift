import AquaristKit
import SwiftUI
import UIKit

enum QuickLogKind: String, Identifiable, CaseIterable {
    case waterChange = "Water Change"
    case testReading = "Test Reading"
    case dose = "Dose"
    case livestock = "Livestock"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .waterChange: "drop.fill"
        case .testReading: "testtube.2"
        case .dose: "pills.fill"
        case .livestock: "fish.fill"
        }
    }
}

struct TankDetailView: View {
    @Bindable var model: AquaristModel
    let tankID: UUID

    @State private var activeSheet: QuickLogKind?
    @State private var editorContext: TankEditorContext?

    private var tank: Tank? {
        model.tanks.first { $0.id == tankID }
    }

    var body: some View {
        Group {
            if let tank {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(tank: tank)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Wet-Hands Quick Log")
                                .font(.headline)

                            Text("Log at the tank in three taps or fewer.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                ForEach(QuickLogKind.allCases) { kind in
                                    Button {
                                        activeSheet = kind
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: kind.systemImage)
                                                .font(.title3)
                                                .frame(width: 32)
                                                .accessibilityHidden(true)
                                            Text(kind.rawValue)
                                                .font(.body.weight(.semibold))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                                .accessibilityHidden(true)
                                        }
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity, minHeight: 56)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("quick.\(kind.accessibilitySuffix)")
                                }
                            }
                        }

                        if let undo = model.undoCandidate, undo.tankID == tank.id {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(undo.summary)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Logged just now")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Undo") {
                                    model.undoLastLog()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("detail.undo")
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(tank.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            editorContext = .edit(tank.id)
                        }
                        .accessibilityIdentifier("tank.edit")
                    }
                }
                .sheet(item: $activeSheet) { kind in
                    QuickLogSheetView(
                        model: model,
                        tank: tank,
                        kind: kind,
                        onDismiss: { activeSheet = nil }
                    )
                }
                .sheet(item: $editorContext) { context in
                    TankEditorView(
                        model: model,
                        context: context,
                        onSaved: { editorContext = nil },
                        onCancel: { editorContext = nil }
                    )
                }
            } else {
                ContentUnavailableView("Tank Missing", systemImage: "questionmark")
            }
        }
    }

    @ViewBuilder
    private func header(tank: Tank) -> some View {
        let events = model.events(for: tank.id)
        let ledger = EventLedger(events: events)
        let waterAge = Derivations.daysSinceWaterChange(ledger: ledger, now: .now, calendar: .current)
        let doseAge = Derivations.lastDoseAgeInDays(ledger: ledger, now: .now, calendar: .current)
        let status = tank.historyStatus(events: events)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.title, systemImage: status.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(status.accessibilityLabel)
                Spacer()
                Text(tank.kind.displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(waterAge.ageText(noun: "Water change"))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.waterAge")

            Text(doseAge.ageText(noun: "Last dose"))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text("Volume: \(tank.volume?.rawInput ?? "Unknown")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !tank.notes.isEmpty {
                Text(tank.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension QuickLogKind {
    var accessibilitySuffix: String {
        switch self {
        case .waterChange: "waterChange"
        case .testReading: "testReading"
        case .dose: "dose"
        case .livestock: "livestock"
        }
    }
}

private enum QuickLogAccessibilityFocus: Hashable {
    case waterChangePercent
    case testParameter
    case doseSubstance
    case livestockActivity
}

struct QuickLogSheetView: View {
    @Bindable var model: AquaristModel
    let tank: Tank
    let kind: QuickLogKind
    let onDismiss: () -> Void

    @AccessibilityFocusState private var accessibilityFocus: QuickLogAccessibilityFocus?

    // Water change state (defaults to 25% for true one-tap logging)
    @State private var waterChangePercent: Decimal = 25
    @State private var waterChangeNote: String = ""

    // Test reading state
    @State private var testParameter: String = "pH"
    @State private var testRawValue: String = ""
    @State private var testNote: String = ""

    // Dose state
    @State private var doseSubstance: String = ""
    @State private var doseAmount: String = ""
    @State private var doseNote: String = ""

    // Livestock state
    @State private var livestockAction: LivestockAction = .added
    @State private var livestockSpecies: String = ""
    @State private var livestockQuantity: Int = 1
    @State private var livestockNote: String = ""

    enum LivestockAction: String, CaseIterable, Identifiable {
        case added = "Added"
        case removed = "Removed"
        case observed = "Observed"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .waterChange:
                    waterChangeSection
                case .testReading:
                    testReadingSection
                case .dose:
                    doseSection
                case .livestock:
                    livestockSection
                }
            }
            .navigationTitle(kind.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHint("Dismisses without saving this log entry.")
                        .accessibilityIdentifier("quick.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle, action: save)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!canSave)
                        .accessibilityHint("Saves this event and returns to tank detail.")
                        .accessibilityIdentifier("quick.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            accessibilityFocus = initialAccessibilityFocus
        }
    }

    @ViewBuilder
    private var waterChangeSection: some View {
        Section("Amount") {
            Picker("Percent of tank", selection: $waterChangePercent) {
                Text("10%").tag(Decimal(10))
                Text("25%").tag(Decimal(25))
                Text("50%").tag(Decimal(50))
                Text("75%").tag(Decimal(75))
            }
            .pickerStyle(.segmented)
            .accessibilityFocused($accessibilityFocus, equals: .waterChangePercent)
            .accessibilityIdentifier("quick.wcPercent")

            if let vol = tank.volume {
                let liters = vol.liters(forPercentOfVolume: waterChangePercent)
                Text("Approx \(liters) L based on your tank size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Optional note") {
            TextField("e.g. rinsed prefilter", text: $waterChangeNote)
                .accessibilityIdentifier("quick.wcNote")
        }
    }

    @ViewBuilder
    private var testReadingSection: some View {
        Section("Reading") {
            Picker("Parameter", selection: $testParameter) {
                ForEach(["pH", "NO3", "NO2", "NH3/NH4", "GH", "KH", "Salinity", "Temp"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .accessibilityFocused($accessibilityFocus, equals: .testParameter)
            .accessibilityIdentifier("quick.testParameter")

            TextField("Recorded value (e.g. 7.4 or 20 ppm)", text: $testRawValue)
                .accessibilityIdentifier("quick.testRawValue")
            Text("Stored verbatim. Aquarist never alters your entered value.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Optional note") {
            TextField("e.g. liquid kit, 5 min wait", text: $testNote)
                .accessibilityIdentifier("quick.testNote")
        }
    }

    @ViewBuilder
    private var doseSection: some View {
        Section("Substance") {
            TextField("Substance name (e.g. Liquid fertilizer)", text: $doseSubstance)
                .accessibilityFocused($accessibilityFocus, equals: .doseSubstance)
                .accessibilityIdentifier("quick.doseSubstance")
            TextField("Amount (e.g. 5 ml or 2 squirts)", text: $doseAmount)
                .accessibilityIdentifier("quick.doseAmount")
        }

        Section("Optional note") {
            TextField("e.g. post-water change dose", text: $doseNote)
                .accessibilityIdentifier("quick.doseNote")
        }
    }

    @ViewBuilder
    private var livestockSection: some View {
        Section("Event") {
            Picker("Activity", selection: $livestockAction) {
                ForEach(LivestockAction.allCases) { action in
                    Text(action.rawValue).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityFocused($accessibilityFocus, equals: .livestockActivity)
            .accessibilityIdentifier("quick.livestockAction")

            TextField("Species (e.g. Cardinal tetra)", text: $livestockSpecies)
                .accessibilityIdentifier("quick.livestockSpecies")

            if livestockAction != .observed {
                Stepper("Quantity: \(livestockQuantity)", value: $livestockQuantity, in: 1...500)
                    .accessibilityIdentifier("quick.livestockQuantity")
            }
        }

        Section("Optional note") {
            TextField("e.g. from local swap", text: $livestockNote)
                .accessibilityIdentifier("quick.livestockNote")
        }
    }

    private var initialAccessibilityFocus: QuickLogAccessibilityFocus {
        switch kind {
        case .waterChange: .waterChangePercent
        case .testReading: .testParameter
        case .dose: .doseSubstance
        case .livestock: .livestockActivity
        }
    }

    private var saveButtonTitle: String {
        switch kind {
        case .waterChange: "Save \(waterChangePercent)% Water Change"
        case .testReading: "Save Reading"
        case .dose: "Save Dose"
        case .livestock: "Save Livestock Event"
        }
    }

    private var canSave: Bool {
        switch kind {
        case .waterChange:
            true
        case .testReading:
            !testRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .dose:
            !doseSubstance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .livestock:
            !livestockSpecies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        let noteOrNil: (String) -> String? = {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let payload: TankEventPayload
        let summary: String

        switch kind {
        case .waterChange:
            payload = .waterChange(
                percentOfVolume: waterChangePercent,
                volumeLiters: nil,
                note: noteOrNil(waterChangeNote)
            )
            summary = "Water change (\(waterChangePercent)%) logged"

        case .testReading:
            payload = .testReading(
                parameter: testParameter,
                rawValue: testRawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                note: noteOrNil(testNote)
            )
            summary = "Test reading (\(testParameter): \(testRawValue)) logged"

        case .dose:
            let substance = doseSubstance.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = noteOrNil(doseAmount)
            payload = .dose(substance: substance, amount: amount, note: noteOrNil(doseNote))
            summary = "Dose (\(substance)) logged"

        case .livestock:
            let species = livestockSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = noteOrNil(livestockNote)
            switch livestockAction {
            case .added:
                payload = .livestockAdded(species: species, quantity: livestockQuantity, note: note)
                summary = "Added \(livestockQuantity) \(species)"
            case .removed:
                payload = .livestockRemoved(species: species, quantity: livestockQuantity, note: note)
                summary = "Removed \(livestockQuantity) \(species)"
            case .observed:
                payload = .livestockObserved(species: species, note: note)
                summary = "Observed \(species)"
            }
        }

        if model.append(payload, to: tank.id, summary: summary) {
            onDismiss()
        }
    }
}
