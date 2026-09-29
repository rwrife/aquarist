import Foundation

/// Workspace presentation modes supported by the Aquarist layout seam.
///
/// Today's shipping runtime resolves strictly to `.singlePane` on iPhone.
/// `.unfoldedTwoPaneTarget` models the design target (wall control surface beside
/// selected-tank ledger/charts) without touching or assuming unavailable fold APIs.
public enum TankWorkspaceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case singlePane
    case unfoldedTwoPaneTarget
}

/// Logical regions available in the workspace layout hierarchy.
public enum TankWorkspaceRegion: String, Codable, CaseIterable, Equatable, Sendable {
    case wallControlSurface
    case detailLedger
}

/// The state continuity contract preserved across transitions and fold simulation.
public struct TankWorkspaceContinuity: Codable, Equatable, Sendable {
    public var selectedTankID: UUID?
    public var wallScrollAnchorTankID: UUID?
    public var detailScrollAnchorEventID: UUID?

    public init(
        selectedTankID: UUID? = nil,
        wallScrollAnchorTankID: UUID? = nil,
        detailScrollAnchorEventID: UUID? = nil
    ) {
        self.selectedTankID = selectedTankID
        self.wallScrollAnchorTankID = wallScrollAnchorTankID
        self.detailScrollAnchorEventID = detailScrollAnchorEventID
    }
}

/// Pure state machine for workspace region mapping and fold-simulation continuity.
public struct TankWorkspaceLayoutState: Codable, Equatable, Sendable {
    public var mode: TankWorkspaceMode
    public var continuity: TankWorkspaceContinuity

    public init(
        mode: TankWorkspaceMode = .singlePane,
        continuity: TankWorkspaceContinuity = TankWorkspaceContinuity()
    ) {
        self.mode = mode
        self.continuity = continuity
    }

    public var selectedTankID: UUID? {
        continuity.selectedTankID
    }

    public var visibleRegions: [TankWorkspaceRegion] {
        switch mode {
        case .singlePane:
            if continuity.selectedTankID != nil {
                return [.detailLedger]
            } else {
                return [.wallControlSurface]
            }
        case .unfoldedTwoPaneTarget:
            return [.wallControlSurface, .detailLedger]
        }
    }

    public mutating func selectTank(_ id: UUID?) {
        continuity.selectedTankID = id
    }

    public mutating func updateWallScrollAnchor(_ id: UUID?) {
        continuity.wallScrollAnchorTankID = id
    }

    public mutating func updateDetailScrollAnchor(_ id: UUID?) {
        continuity.detailScrollAnchorEventID = id
    }

    public mutating func transition(to newMode: TankWorkspaceMode) {
        self.mode = newMode
    }
}
