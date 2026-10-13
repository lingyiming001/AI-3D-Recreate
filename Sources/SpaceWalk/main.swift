import SwiftUI

@main
struct SpaceWalkApp: App {
    var body: some Scene {
        WindowGroup("SpaceWalk") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
