import Foundation
import GRDB
import AquaristKit

// MARK: - Protocols

public protocol TankRepository: Sendable {
    /// Upserts the tank's current-state row (create or full replace).
    func upsert(_ tank: Tank) throws
    func tank(id: UUID) throws -> Tank?
    /// All tanks, ordered by name.
    func allTanks() throws -> [Tank]
}

public protocol TankEventRepository: Sendable {
    /// Appends an event row. Insert-only — there is no update/delete.
    /// Throws `.parentNotFound` when the tank does not exist.
    func append(_ event: TankEvent) throws
    /// A tank's full ledger, oldest first.
    func events(for tankID: UUID) throws -> [TankEvent]
    /// Raw chronological reading series for one parameter of one tank.
    func readingSeries(tankID: UUID, parameter: String) throws -> [Derivations.ReadingPoint]
}

public protocol ReferenceBandRepository: Sendable {
    /// Upserts a reference band for a tank (create or replace by id).
    func upsert(_ band: ReferenceBand, for tankID: UUID) throws
    /// All reference bands for a tank.
    func bands(for tankID: UUID) throws -> [ReferenceBand]
}

// MARK: - Storage usage

public struct StorageUsage: Equatable, Sendable {
    public struct TableCounts: Equatable, Sendable {
        public var tanks: Int
        public var tankEvents: Int
        public var referenceBands: Int

        public init(tanks: Int, tankEvents: Int, referenceBands: Int) {
            self.tanks = tanks
            self.tankEvents = tankEvents
            self.referenceBands = referenceBands
        }
    }

    public var rows: TableCounts
    public var databaseBytes: Int

    public init(rows: TableCounts, databaseBytes: Int) {
        self.rows = rows
        self.databaseBytes = databaseBytes
    }
}

// MARK: - Payload codec

/// Encodes/decodes `TankEventPayload` to/from the `payload_json` column,
/// plus a discriminator string (`payload_type`) and an optional
/// `test_parameter` projection used for the indexed per-parameter query.
enum TankEventPayloadCodec {
    static func encode(_ payload: TankEventPayload) throws -> (type: String, json: String, testParameter: String?) {
        let data = try JSONEncoder().encode(payload)
        // Canonicalize key order for deterministic fixture DB generation and
        // stable diffs; decode stays fully compatible with regular JSON.
        let object = try JSONSerialization.jsonObject(with: data)
        let canonicalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: canonicalData, encoding: .utf8) else {
            throw AquaristStoreError.corruptPayload(table: "tank_events", id: UUID(), underlying: "non-UTF8 payload encoding")
        }
        let type: String
        var testParameter: String?
        switch payload {
        case .waterChange: type = "waterChange"
        case let .testReading(parameter, _, _):
            type = "testReading"
            testParameter = parameter
        case .dose: type = "dose"
        case .livestockAdded: type = "livestockAdded"
        case .livestockRemoved: type = "livestockRemoved"
        case .livestockObserved: type = "livestockObserved"
        case .equipment: type = "equipment"
        case .note: type = "note"
        case .correction: type = "correction"
        }
        return (type, json, testParameter)
    }

    static func decode(json: String, table: String, id: UUID) throws -> TankEventPayload {
        guard let data = json.data(using: .utf8) else {
            throw AquaristStoreError.corruptPayload(table: table, id: id, underlying: "non-UTF8 stored payload")
        }
        do {
            return try JSONDecoder().decode(TankEventPayload.self, from: data)
        } catch {
            throw AquaristStoreError.corruptPayload(table: table, id: id, underlying: String(describing: error))
        }
    }
}

// MARK: - GRDB implementations

public struct GRDBTankRepository: TankRepository {
    let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func upsert(_ tank: Tank) throws {
        try db.write { writer in
            try writer.execute(
                sql: """
                INSERT INTO tanks (
                    id, name, volume_liters, volume_is_approximate,
                    volume_raw_input, kind, created_at, notes
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    volume_liters = excluded.volume_liters,
                    volume_is_approximate = excluded.volume_is_approximate,
                    volume_raw_input = excluded.volume_raw_input,
                    kind = excluded.kind,
                    created_at = excluded.created_at,
                    notes = excluded.notes
                """,
                arguments: [
                    tank.id.uuidString, tank.name,
                    tank.volume.map { "\($0.liters)" },
                    tank.volume?.isApproximate,
                    tank.volume?.rawInput,
                    tank.kind.rawValue,
                    tank.createdAt,
                    tank.notes,
                ]
            )
        }
    }

    public func tank(id: UUID) throws -> Tank? {
        try db.read { reader in
            guard let row = try Row.fetchOne(reader, sql: "SELECT * FROM tanks WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return Self.tank(from: row)
        }
    }

    public func allTanks() throws -> [Tank] {
        try db.read { reader in
            try Row.fetchAll(reader, sql: "SELECT * FROM tanks ORDER BY name COLLATE NOCASE").map(Self.tank(from:))
        }
    }

    static func tank(from row: Row) -> Tank {
        let volume: TankVolume?
        if let litersText: String = row["volume_liters"], let liters = Decimal(string: litersText) {
            volume = TankVolume(
                liters: liters,
                isApproximate: row["volume_is_approximate"] ?? false,
                rawInput: row["volume_raw_input"] ?? ""
            )
        } else {
            volume = nil
        }
        let rawKind: String = row["kind"] ?? "freshwater"
        let kind = TankKind(rawValue: rawKind) ?? .other
        return Tank(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            volume: volume,
            kind: kind,
            createdAt: row["created_at"],
            notes: row["notes"] ?? ""
        )
    }
}

public struct GRDBTankEventRepository: TankEventRepository {
    let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func append(_ event: TankEvent) throws {
        try db.write { writer in
            guard try Int.fetchOne(
                writer, sql: "SELECT COUNT(*) FROM tanks WHERE id = ?", arguments: [event.tankID.uuidString]
            ) == 1 else {
                throw AquaristStoreError.parentNotFound(table: "tanks", id: event.tankID)
            }
            let encoded = try TankEventPayloadCodec.encode(event.payload)
            try writer.execute(
                sql: """
                INSERT INTO tank_events (id, tank_id, timestamp, payload_type, payload_json, test_parameter)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString, event.tankID.uuidString, event.timestamp,
                    encoded.type, encoded.json, encoded.testParameter,
                ]
            )
        }
    }

    public func events(for tankID: UUID) throws -> [TankEvent] {
        try db.read { reader in
            try Row.fetchAll(
                reader,
                sql: "SELECT * FROM tank_events WHERE tank_id = ? ORDER BY timestamp, id",
                arguments: [tankID.uuidString]
            ).map(Self.event(from:))
        }
    }

    public func readingSeries(tankID: UUID, parameter: String) throws -> [Derivations.ReadingPoint] {
        // Read the tank's complete ledger so append-only corrections can
        // retract a reading without mutating or deleting its original row;
        // the raw-value -> parsed-value rule stays in `Derivations`, so the
        // store can never drift from the domain's unknown-safe semantics.
        let events = try events(for: tankID)
        guard case .known(let points) = Derivations.readingSeries(
            parameter: parameter, ledger: EventLedger(events: events)
        ) else {
            return []
        }
        return points
    }

    static func event(from row: Row) throws -> TankEvent {
        let id = UUID(uuidString: row["id"])!
        let payload = try TankEventPayloadCodec.decode(json: row["payload_json"], table: "tank_events", id: id)
        return TankEvent(
            id: id,
            tankID: UUID(uuidString: row["tank_id"])!,
            timestamp: row["timestamp"],
            payload: payload
        )
    }
}

public struct GRDBReferenceBandRepository: ReferenceBandRepository {
    let db: any DatabaseWriter
    public init(db: any DatabaseWriter) { self.db = db }

    public func upsert(_ band: ReferenceBand, for tankID: UUID) throws {
        try db.write { writer in
            guard try Int.fetchOne(
                writer, sql: "SELECT COUNT(*) FROM tanks WHERE id = ?", arguments: [tankID.uuidString]
            ) == 1 else {
                throw AquaristStoreError.parentNotFound(table: "tanks", id: tankID)
            }
            try writer.execute(
                sql: """
                INSERT INTO reference_bands (id, tank_id, parameter, label, raw_low, raw_high)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    parameter = excluded.parameter,
                    label = excluded.label,
                    raw_low = excluded.raw_low,
                    raw_high = excluded.raw_high
                """,
                arguments: [
                    band.id.uuidString, tankID.uuidString, band.parameter,
                    band.label, band.rawLow, band.rawHigh,
                ]
            )
        }
    }

    public func bands(for tankID: UUID) throws -> [ReferenceBand] {
        try db.read { reader in
            try Row.fetchAll(
                reader,
                sql: "SELECT * FROM reference_bands WHERE tank_id = ? ORDER BY parameter COLLATE NOCASE",
                arguments: [tankID.uuidString]
            ).map { row in
                ReferenceBand(
                    id: UUID(uuidString: row["id"])!,
                    parameter: row["parameter"],
                    label: row["label"],
                    rawLow: row["raw_low"],
                    rawHigh: row["raw_high"]
                )
            }
        }
    }
}
