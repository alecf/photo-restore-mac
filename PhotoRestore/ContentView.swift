import SwiftUI
import UniformTypeIdentifiers
import RestoreEngine

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isTargeted = false

    var body: some View {
        Group {
            if !model.modelsReady {
                SetupView(model: model)
            } else if model.items.isEmpty {
                EmptyDropView(model: model, isTargeted: isTargeted)
            } else {
                MainView(model: model)
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.modelsReady else { return false }
            model.add(urls: urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Shown until the Core ML models are installed: download them (the default), or side-load
/// them from a folder for offline use. The registry's SHA-256s guard integrity either way.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var importing = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 56, weight: .thin)).foregroundStyle(.secondary)
            Text("One-time setup").font(.title2.weight(.semibold))
            Text("Photo Restore needs its restoration models (\(model.modelDownloadSize)).")
                .foregroundStyle(.secondary)
            if model.isPreparing {
                if let progress = model.downloadProgress {
                    ProgressView(value: progress).frame(maxWidth: 320)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(model.setupMessage ?? "Installing…").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Download Models") { Task { await model.downloadModels() } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Button("Install from Folder…") { pickFolder() }
                if let msg = model.setupMessage {
                    Text(msg).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Text("Offline? Install from a folder containing \(ModelRegistry.fileNamesList).")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Install Models"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.importModels(from: url) }
        }
    }
}

/// Welcome / drop target before any photos are added.
struct EmptyDropView: View {
    @ObservedObject var model: AppModel
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drag a photo or folder here").font(.title2.weight(.medium))
            Text("Old scans, faded prints, low-res photos — dropped in, restored out.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Choose Photos…") { pick() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(24)
        )
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        if panel.runModal() == .OK { model.add(urls: panel.urls) }
    }
}

extension BatchItemStatus {
    var symbol: String {
        switch self {
        case .queued: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .queued: return .secondary
        case .processing: return .blue
        case .done: return .green
        case .skipped: return .orange
        case .failed: return .red
        }
    }
    var label: String {
        switch self {
        case .queued: return "Queued"
        case .processing: return "Restoring…"
        case .done: return "Done"
        case .skipped(let r): return "Skipped — \(r)"
        case .failed(let r): return "Failed — \(r)"
        }
    }
}

#Preview { ContentView() }
