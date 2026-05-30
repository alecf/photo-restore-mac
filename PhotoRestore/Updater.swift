import SwiftUI
import Sparkle

/// Wraps Sparkle's updater so the app can check for updates (automatically on a daily schedule
/// per Info.plist, and manually via the menu). The feed + public key live in Info.plist.
final class UpdaterController: ObservableObject {
    let updater: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updater.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}

/// "Check for Updates…" menu command, enabled only when Sparkle is ready.
struct CheckForUpdatesCommand: View {
    @ObservedObject var controller: UpdaterController
    var body: some View {
        Button("Check for Updates…") { controller.checkForUpdates() }
            .disabled(!controller.canCheckForUpdates)
    }
}
