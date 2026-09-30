import AquaristKit
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Your-data screen: versioned JSON backup, CSV history export via the
/// system share sheet, and restore with a previewed, explicitly-confirmed
/// replace. Zero network by design — everything leaves through the iOS
/// share sheet (Files, Mail, …) which the user controls; the app itself
/// holds no network or entitlement-driven permissions.
struct DataExportView: View {
    let model: AquaristModel

    @State private var shareFiles: [URL] = []
    @State private var showShare = false
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var restoreData: Data?
    @State private var restorePreview: BackupPreview?
    @State private var restoreError: String?
    @State private var showRestoreConfirm = false
    @State private var restoreDone: String?

    var body: some View {
        List {
            Section("Backup") {
                Button {
                    exportBackup()
                } label: {
                    Label("Export JSON backup", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("data.exportBackup")

                Button {
                    importBackup()
                } label: {
                    Label("Restore from backup", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canMutateStore)
                .accessibilityIdentifier("data.restoreBackup")
            }

            Section("CSV export") {
                Button {
                    exportCSV()
                } label: {
                    Label("Export ledgers and reading series", systemImage: "tablecells")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.tanks.isEmpty)
                .accessibilityIdentifier("data.exportCSV")

                if model.tanks.isEmpty {
                    Text("Create a tank first — CSV export covers per-tank ledgers and per-parameter series.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text("Backups and exports leave the device only through the share sheet you control. Aquarist has no network access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Your Data")
        .sheet(isPresented: $showShare) {
            if !shareFiles.isEmpty {
                ShareSheet(items: shareFiles)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Restore this backup?", isPresented: $showRestoreConfirm) {
            Button("Replace Everything", role: .destructive) {
                performRestore()
            }
            Button("Cancel", role: .cancel) { clearRestore() }
        } message: {
            Text(restorePreviewMessage)
        }
        .alert("Restore failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .alert("Restore complete", isPresented: Binding(
            get: { restoreDone != nil },
            set: { if !$0 { restoreDone = nil } }
        )) {
            Button("OK", role: .cancel) { restoreDone = nil }
        } message: {
            Text(restoreDone ?? "")
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var restorePreviewMessage: String {
        guard let preview = restorePreview else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let names = preview.tankNames.isEmpty
            ? "none"
            : preview.tankNames.joined(separator: ", ")
        return """
        Backup from \(formatter.string(from: preview.exportedAt)) — \
        \(preview.tankCount) tank(s), \(preview.eventCount) event(s), \
        \(preview.bandCount) reference band(s): \(names).

        This replaces everything currently stored in Aquarist. This cannot be undone.
        """
    }

    // MARK: - JSON backup export

    private func exportBackup() {
        do {
            let document = try model.backupDocument()
            let data = try BackupCodec.encode(document)
            let url = try stagedFile(name: "aquarist-backup-\(Self.stamp()).json", data: data)
            shareFiles = [url]
            showShare = true
        } catch {
            exportError = "Backup could not be created: \(error.localizedDescription)"
        }
    }

    // MARK: - CSV export

    private func exportCSV() {
        do {
            var urls: [URL] = []
            for tank in model.tanks {
                let events = model.events(for: tank.id)
                let ledgerCSV = CSVExport.tankLedgerCSV(tank: tank, events: events)
                urls.append(try stagedFile(
                    name: "aquarist-\(Self.fileSafe(tank.name))-ledger-\(Self.stamp()).csv",
                    data: Data(ledgerCSV.utf8)
                ))

                let ledger = EventLedger(events: events)
                let parameters = Set(ledger.effectiveEvents.compactMap { event -> String? in
                    if case let .testReading(parameter, _, _) = event.payload { return parameter }
                    return nil
                }).sorted()
                for parameter in parameters {
                    if case let .known(points) = Derivations.readingSeries(parameter: parameter, ledger: ledger) {
                        let seriesCSV = CSVExport.readingSeriesCSV(
                            tank: tank, parameter: parameter, points: points
                        )
                        urls.append(try stagedFile(
                            name: "aquarist-\(Self.fileSafe(tank.name))-\(Self.fileSafe(parameter))-series-\(Self.stamp()).csv",
                            data: Data(seriesCSV.utf8)
                        ))
                    }
                }
            }
            shareFiles = urls
            showShare = true
        } catch {
            exportError = "CSV export could not be created: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore (preview first, replace only on explicit confirm)

    private func importBackup() {
        showImporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        clearRestore()
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                restoreData = data
                restorePreview = try BackupCodec.preview(data)
                showRestoreConfirm = true
            } catch {
                restoreError = "This file could not be read as an Aquarist backup: \(error.localizedDescription)"
            }
        case let .failure(error):
            restoreError = "No file selected: \(error.localizedDescription)"
        }
    }

    private func performRestore() {
        defer { clearRestore() }
        guard let data = restoreData else { return }
        do {
            let document = try BackupCodec.decode(data)
            try model.restore(from: document)
            restoreDone = "Restored \(document.tanks.count) tank(s), \(document.events.count) event(s), and \(document.bands.count) reference band(s)."
        } catch {
            restoreError = "Restore failed and existing data was left untouched: \(error.localizedDescription)"
        }
    }

    private func clearRestore() {
        restoreData = nil
        restorePreview = nil
    }

    // MARK: - File staging (share sheet input lives in the temporary dir)

    private func stagedFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AquaristExport-\(Self.stamp())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func fileSafe(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let mapped = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return mapped.isEmpty ? "item" : mapped
    }
}

/// Minimal UIActivityViewController wrapper — share sheet only, no custom
/// permission handling (the system owns everything the user picks).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
