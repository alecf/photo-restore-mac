import Foundation
import RestoreEngine

/// Installs the Core ML models into the same Application Support location the app reads, so a
/// local build launches ready (skips the in-app "Install from Folder…" step). Run as a plain
/// command-line tool, `Bundle.main.bundleIdentifier` is nil, so ModelStore falls back to the
/// app's id (com.alecf.PhotoRestore) — i.e. it writes exactly where the app looks.
///
/// Usage: swift run prepare-models <folder-with-.mlmodel-files>
@main
struct PrepareModels {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: swift run prepare-models <models-dir>\n".utf8))
            exit(2)
        }
        let dir = URL(fileURLWithPath: args[1])
        let store = ModelStore()
        do {
            print("installing models from \(dir.path) …")
            let ready = try await store.importLocalModels(from: dir)
            let isReady = await store.isReady()
            print("installed: \(ready.joined(separator: ", "))")
            print(isReady ? "✓ ready — launch the app" : "✗ still missing some models")
            exit(isReady ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
