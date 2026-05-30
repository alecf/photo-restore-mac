import SwiftUI

@main
struct PhotoRestoreApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}
