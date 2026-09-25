import Foundation

/// A user-owned aquarium tank record.
///
/// Value type; the app mutates by producing a new `Tank` (updated copy),
/// never by mutating shared state. `volume == nil` means unknown and every
/// volume-dependent derivation must render `.unknown`.
public struct Tank: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var volume: TankVolume?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        volume: TankVolume? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.volume = volume
        self.createdAt = createdAt
    }
}
