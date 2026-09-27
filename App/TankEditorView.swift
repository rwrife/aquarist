import AquaristKit
import SwiftUI

enum TankEditorContext: Identifiable, Hashable {
    case create
    case edit(UUID)

    var id: UUID {
        switch self {
        case .create: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        case let .edit(id): id
        }
    }
}

struct TankEditorView: View {
    @Bindable var model: AquaristModel
    let context: TankEditorContext
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var volumeText: String
    @State private var volumeIsApproximate: Bool
    @State private var kind: TankKind
    @State private var startDate: Date
    @State private var notes: String
    @State private var volumeError: String?

    init(
        model: AquaristModel,
        context: TankEditorContext,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let existing: Tank?
        switch context {
        case .create: existing = nil
        case let .edit(id): existing = model.tanks.first { $0.id == id }
        }

        self.model = model
        self.context = context
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _volumeText = State(initialValue: existing?.volume?.rawInput ?? "")
        _volumeIsApproximate = State(initialValue: existing?.volume?.isApproximate ?? false)
        _kind = State(initialValue: existing?.kind ?? .freshwater)
        _startDate = State(initialValue: existing?.createdAt ?? .now)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tank") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("tank.name")

                    Toggle("Approximate volume", isOn: $volumeIsApproximate)
                        .accessibilityIdentifier("tank.volumeApproximate")

                    TextField("Volume (e.g. 200 L or 75 gal)", text: $volumeText)
                        .accessibilityIdentifier("tank.volume")

                    if let volumeError {
                        Text(volumeError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("tank.volumeError")
                    }

                    Picker("Type", selection: $kind) {
                        ForEach(TankKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .accessibilityIdentifier("tank.kind")

                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                        .accessibilityIdentifier("tank.startDate")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("tank.notes")
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("tank.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("tank.save")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var title: String {
        switch context {
        case .create: "New Tank"
        case .edit: "Edit Tank"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let volume: TankVolume?
        if volumeText.isEmpty {
            volume = nil
            volumeError = nil
        } else if let parsed = TankVolume.parse(volumeText) {
            volume = TankVolume(
                liters: parsed.liters,
                isApproximate: parsed.isApproximate || volumeIsApproximate,
                rawInput: parsed.rawInput
            )
            volumeError = nil
        } else {
            volume = nil
            volumeError = "Volume could not be understood. Use an amount with L, litres, ml, or gal."
            return
        }

        let existingTank: Tank? = switch context {
        case .create: nil
        case let .edit(id): model.tanks.first { $0.id == id }
        }

        let tank = Tank(
            id: existingTank?.id ?? UUID(),
            name: trimmedName,
            volume: volume,
            kind: kind,
            createdAt: startDate,
            notes: notes
        )
        if model.saveTank(tank) {
            onSaved()
        }
    }
}
