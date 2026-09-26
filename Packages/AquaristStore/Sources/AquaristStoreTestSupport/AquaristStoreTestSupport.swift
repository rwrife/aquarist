import Foundation
import AquaristKit
import AquaristStore

// In-memory fakes for app/UI tests: same protocols, same append-only
// semantics as the GRDB implementations, backed by a lock-guarded store.

final class RepoLock: @unchecked Sendable {
    private var lock = NSLock()
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public final class InMemoryTankRepository: TankRepository, @unchecked Sendable {
    private let lock = RepoLock()
    private var stored: [UUID: Tank] = [:]

    public init() {}

    public func upsert(_ tank: Tank) throws {
        lock.withLock { stored[tank.id] = tank }
    }

    public func tank(id: UUID) throws -> Tank? {
        lock.withLock { stored[id] }
    }

    public func allTanks() throws -> [Tank] {
        lock.withLock {
            stored.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func exists(_ id: UUID) -> Bool {
        lock.withLock { stored[id] != nil }
    }

    func removeCascade(_ id: UUID) {
        lock.withLock { stored[id] = nil }
    }
}

public final class InMemoryTankEventRepository: TankEventRepository, @unchecked Sendable {
    private let lock = RepoLock()
    private var events: [TankEvent] = []
    private var tanks: InMemoryTankRepository?

    public init(tanks: InMemoryTankRepository? = nil) {
        self.tanks = tanks
    }

    /// Wires the tank repository this event repository validates parents
    /// against. Call once after constructing both fakes together (see
    /// `InMemoryRepositories`).
    public func attachTanks(_ tanks: InMemoryTankRepository) {
        self.tanks = tanks
    }

    public func append(_ event: TankEvent) throws {
        try lock.withLock {
            guard tanks?.exists(event.tankID) == true else {
                throw AquaristStoreError.parentNotFound(table: "tanks", id: event.tankID)
            }
            events.append(event)
        }
    }

    public func events(for tankID: UUID) throws -> [TankEvent] {
        lock.withLock {
            events.filter { $0.tankID == tankID }
                .sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
        }
    }

    public func readingSeries(tankID: UUID, parameter: String) throws -> [Derivations.ReadingPoint] {
        let tankEvents = try events(for: tankID)
        guard case .known(let points) = Derivations.readingSeries(
            parameter: parameter, ledger: EventLedger(events: tankEvents)
        ) else {
            return []
        }
        return points
    }
}

public final class InMemoryReferenceBandRepository: ReferenceBandRepository, @unchecked Sendable {
    private let lock = RepoLock()
    private var stored: [UUID: [UUID: ReferenceBand]] = [:]
    private var tanks: InMemoryTankRepository?

    public init(tanks: InMemoryTankRepository? = nil) {
        self.tanks = tanks
    }

    public func attachTanks(_ tanks: InMemoryTankRepository) {
        self.tanks = tanks
    }

    public func upsert(_ band: ReferenceBand, for tankID: UUID) throws {
        try lock.withLock {
            guard tanks?.exists(tankID) == true else {
                throw AquaristStoreError.parentNotFound(table: "tanks", id: tankID)
            }
            stored[tankID, default: [:]][band.id] = band
        }
    }

    public func bands(for tankID: UUID) throws -> [ReferenceBand] {
        lock.withLock {
            (stored[tankID] ?? [:]).values
                .sorted { $0.parameter.localizedCaseInsensitiveCompare($1.parameter) == .orderedAscending }
        }
    }
}

/// A bundle of all fakes, pre-wired to share tank-existence checks.
public struct InMemoryRepositories: Sendable {
    public let tanks: InMemoryTankRepository
    public let events: InMemoryTankEventRepository
    public let referenceBands: InMemoryReferenceBandRepository

    public init() {
        let tanks = InMemoryTankRepository()
        let events = InMemoryTankEventRepository(tanks: tanks)
        let referenceBands = InMemoryReferenceBandRepository(tanks: tanks)
        self.tanks = tanks
        self.events = events
        self.referenceBands = referenceBands
    }
}
