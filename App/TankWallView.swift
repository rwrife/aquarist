import AquaristKit
import SwiftUI
import UIKit

struct TankWallView: View {
    @Bindable var model: AquaristModel
    @State private var editorContext: TankEditorContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let undo = model.undoCandidate {
                        undoBanner(summary: undo.summary)
                    }

                    if model.tanks.isEmpty {
                        ContentUnavailableView(
                            "No tanks yet",
                            systemImage: "fish",
                            description: Text("Create your first tank to start quick logging at the wall.")
                        )
                        .accessibilityIdentifier("wall.empty")
                    }

                    ForEach(model.tanks) { tank in
                        NavigationLink {
                            TankDetailView(model: model, tankID: tank.id)
                        } label: {
                            TankWallCard(tank: tank, events: model.events(for: tank.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tank.card.\(tank.name)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Tank Wall")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorContext = .create
                    } label: {
                        Label("Add tank", systemImage: "plus")
                    }
                    .accessibilityIdentifier("wall.addTank")
                }
            }
        }
        .sheet(item: $editorContext) { context in
            TankEditorView(
                model: model,
                context: context,
                onSaved: { editorContext = nil },
                onCancel: { editorContext = nil }
            )
        }
        .alert("Storage error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func undoBanner(summary: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.title3)
                .foregroundStyle(.primary)
                .accessibilityLabel("Undo available")

            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                Text("Undo removes it from derived views while keeping append-only history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Undo") {
                model.undoLastLog()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(minHeight: 52)
            .accessibilityIdentifier("wall.undo")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TankWallCard: View {
    let tank: Tank
    let events: [TankEvent]

    var body: some View {
        let ledger = EventLedger(events: events)
        let status = tank.historyStatus(events: events)
        let waterAge = Derivations.daysSinceWaterChange(ledger: ledger, now: .now, calendar: .current)
        let doseAge = Derivations.lastDoseAgeInDays(ledger: ledger, now: .now, calendar: .current)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(statusColor(status))
                    .accessibilityLabel(status.accessibilityLabel)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tank.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(tank.kind.displayName) • \(tank.volume?.rawInput ?? "Volume unknown")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor(status).opacity(0.18), in: Capsule())
            }

            Text(waterAge.ageText(noun: "Water change"))
                .font(.body)
                .foregroundStyle(waterAgeColor(waterAge))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tank.waterAge.\(tank.name)")

            Text(doseAge.ageText(noun: "Last dose"))
                .font(.body)
                .foregroundStyle(waterAgeColor(doseAge))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !tank.notes.isEmpty {
                Text(tank.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func statusColor(_ status: TankHistoryStatus) -> Color {
        switch status {
        case .unknown: .gray
        case .partial: .indigo
        case .recorded: .blue
        }
    }

    private func waterAgeColor(_ age: Derivation<Int>) -> Color {
        switch age {
        case .unknown: .secondary
        case .known: .primary
        }
    }
}

#Preview {
    TankWallView(model: .make())
}
