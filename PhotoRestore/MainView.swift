import SwiftUI
import RestoreEngine

/// The working layout once photos are queued: top bar, before/after viewer for the selected
/// image, and a filmstrip of all queued images.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    private var selected: UIItem? {
        model.items.first { $0.id == model.selectedID } ?? model.items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            viewer
            Divider()
            FilmstripView(model: model)
                .frame(height: 124)
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.chooseOutputDirectory() } label: {
                Label(outputLabel, systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle)
            }
            .help("Choose where restored photos are saved")

            Spacer()

            if model.total > 0 {
                Text("\(model.completed) / \(model.total)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                    .frame(width: 120)
            }

            Button { model.isRunning ? model.pause() : model.start() } label: {
                Label(model.isRunning ? "Pause" : "Start",
                      systemImage: model.isRunning ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.items.allSatisfy { if case .queued = $0.status { return false }; return true })

            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("Settings")
        }
        .padding(12)
    }

    private var outputLabel: String {
        model.outputDirectory?.lastPathComponent.isEmpty == false
            ? model.outputDirectory!.lastPathComponent
            : "Output: next to originals"
    }

    @ViewBuilder private var viewer: some View {
        if let item = selected {
            BeforeAfterView(
                before: model.beforeImage(for: item),
                after: item.afterPreview,
                status: item.status
            )
            .id(item.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Color(nsColor: .underPageBackgroundColor)
        }
    }
}
