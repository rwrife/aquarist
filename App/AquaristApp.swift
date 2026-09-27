import SwiftUI

@main
struct AquaristApp: App {
    @State private var model = AquaristModel.make()

    var body: some Scene {
        WindowGroup {
            TankWallView(model: model)
        }
    }
}
