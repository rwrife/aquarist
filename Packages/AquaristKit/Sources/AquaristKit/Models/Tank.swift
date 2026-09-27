import Foundation

/// User-owned tank category. It is descriptive only and never drives a
/// chemistry, safety, or husbandry verdict.
public enum TankKind: String, Codable, CaseIterable, Equatable, Sendable {
    case freshwater
    case saltwater
    case brackish
    case other

    public var displayName: String {
        switch self {
        case .freshwater: "Freshwater"
        case .saltwater: "Saltwater"
        case .brackish: "Brackish"
        case .other: "Other"
        }
    }
}

/// A user-owned aquarium tank record.
///
/// Value type; the app mutates by producing a new `Tank` (updated copy),
/// never by mutating shared state. `volume == nil` means unknown and every
/// volume-dependent derivation must render `.unknown`.
public struct Tank: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var volume: TankVolume?
    public var kind: TankKind
    public var createdAt: Date
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        volume: TankVolume? = nil,
        kind: TankKind = .freshwater,
        createdAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.volume = volume
        self.kind = kind
        self.createdAt = createdAt
        self.notes = notes
    }
}
