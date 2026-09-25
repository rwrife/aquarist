import Foundation

/// The result of a domain derivation: either a computed value or an
/// explicit `.unknown`. Unknown-safe by contract — a derivation never
/// substitutes a default number for missing data.
public enum Derivation<Value: Equatable & Sendable & Codable>: Equatable, Codable, Sendable {
    case known(Value)
    case unknown
}
