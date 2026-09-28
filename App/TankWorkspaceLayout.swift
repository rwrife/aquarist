import AquaristKit
import Foundation
import SwiftUI

/// Single seam for mapping workspace modes to visible UI regions.
///
/// Runtime today always resolves to the existing single-pane `NavigationStack`
/// experience on iPhone. The workspace selection and scroll anchors live in
/// `TankWorkspaceLayoutState` (AquaristKit) so the continuity contract is
/// unit-testable and survives mode changes; a future native dual-screen API
/// would switch `workspace.mode` behind this seam without touching the domain
/// or store layers. No fold APIs are used or assumed.
struct TankWorkspaceLayout: View {
    @Bindable var model: AquaristModel
    @State private var workspace = TankWorkspaceLayoutState()
    @State private var path: [UUID] = []

    var body: some View {
        TankWallView(
            model: model,
            path: $path,
            workspace: $workspace
        )
        .onChange(of: path) { _, newPath in
            workspace.selectTank(newPath.last)
        }
    }
}

#Preview {
    TankWorkspaceLayout(model: .make())
}
