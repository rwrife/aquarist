import AquaristKit
import AquaristStore
import Foundation
import Observation

@Observable
final class AquaristModel {
    struct UndoCandidate: Equatable {
        let eventID: UUID
        let tankID: UUID
        let summary: String
    }

    private let store: AquaristStore?

    private(set) var tanks: [Tank] = []
    private(set) var eventsByTank: [UUID: [TankEvent]] = [:]
    private(set) var undoCandidate: UndoCandidate?
    var errorMessage: String?

    private init(store: AquaristStore?, startupError: String? = nil) {
        self.store = store
        self.errorMessage = startupError
        reload()
    }

    static func make() -> AquaristModel {
        do {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                return AquaristModel(store: try AquaristStore.inMemory())
            }

            let fileManager = FileManager.default
            let directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Aquarist", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return AquaristModel(
                store: try AquaristStore.open(at: directory.appendingPathComponent("aquarist.sqlite"))
            )
        } catch {
            return AquaristModel(
                store: nil,
                startupError: "Aquarist could not open local storage: \(error.localizedDescription)"
            )
        }
    }

    func events(for tankID: UUID) -> [TankEvent] {
        eventsByTank[tankID] ?? []
    }

    func reload() {
        guard let store else { return }
        do {
            let loadedTanks = try store.tanks.allTanks()
            var events: [UUID: [TankEvent]] = [:]
            for tank in loadedTanks {
                events[tank.id] = try store.events.events(for: tank.id)
            }
            tanks = loadedTanks
            eventsByTank = events
        } catch {
            errorMessage = "Aquarist could not read local data: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveTank(_ tank: Tank) -> Bool {
        guard let store else { return false }
        do {
            try store.tanks.upsert(tank)
            reload()
            return true
        } catch {
            errorMessage = "Tank could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func append(_ payload: TankEventPayload, to tankID: UUID, summary: String) -> Bool {
        guard let store else { return false }
        let event = TankEvent(tankID: tankID, timestamp: .now, payload: payload)
        do {
            try store.events.append(event)
            undoCandidate = UndoCandidate(eventID: event.id, tankID: tankID, summary: summary)
            reload()
            return true
        } catch {
            errorMessage = "Log entry could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func undoLastLog() {
        guard let store, let candidate = undoCandidate else { return }
        do {
            try store.events.append(TankEvent(
                tankID: candidate.tankID,
                timestamp: .now,
                payload: .correction(targetEventID: candidate.eventID, note: "Undo")
            ))
            undoCandidate = nil
            reload()
        } catch {
            errorMessage = "The last log could not be undone: \(error.localizedDescription)"
        }
    }
}

extension Tank {
    func historyStatus(events: [TankEvent], now: Date = .now, calendar: Calendar = .current) -> TankHistoryStatus {
        let ledger = EventLedger(events: events)
        let water = Derivations.daysSinceWaterChange(ledger: ledger, now: now, calendar: calendar)
        let dose = Derivations.lastDoseAgeInDays(ledger: ledger, now: now, calendar: calendar)
        return switch (water, dose) {
        case (.unknown, .unknown): .unknown
        case (.known, .known): .recorded
        default: .partial
        }
    }
}

enum TankHistoryStatus: Equatable {
    case unknown
    case partial
    case recorded

    var title: String {
        switch self {
        case .unknown: "History unknown"
        case .partial: "History partial"
        case .recorded: "Maintenance ages recorded"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .recorded: "clock.badge.checkmark.fill"
        }
    }

    var accessibilityLabel: String {
        "Status: \(title)"
    }
}

extension Derivation where Value == Int {
    func ageText(noun: String) -> String {
        switch self {
        case .unknown:
            "\(noun): Unknown"
        case .known(0):
            "\(noun): Today"
        case .known(1):
            "\(noun): 1 day ago"
        case let .known(days):
            "\(noun): \(days) days ago"
        }
    }
}
