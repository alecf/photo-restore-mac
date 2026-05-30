import SwiftUI
import RestoreEngine

/// The working layout once photos are queued: a window toolbar (so controls sit in the
/// title-bar area, not under it), a before/after viewer for the selected image, and a
/// filmstrip of all queued images.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    private var selected: UIItem? {
        model.items.first { $0.id == model.selectedID } ?? model.items.first
    }

    private var hasQueued: Bool {
        model.items.contains { if case .queued = $0.status { return true }; return false }
    }

    var body: some View {
        VStack(spacing: 0) {
            viewer
            Divider()
            FilmstripView(model: model)
                .frame(height: 124)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.chooseOutputDirectory() } label: {
                    Label(outputLabel, systemImage: "folder")
                }
                .help("Choose where restored photos are saved")
            }
            ToolbarItem(placement: .principal) {
                if model.total > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                            .frame(width: 120)
                        Text("\(model.completed) / \(model.total)")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.isRunning ? model.pause() : model.start() } label: {
                    Label(model.isRunning ? "Pause" : "Start",
                          systemImage: model.isRunning ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!hasQueued && !model.isRunning)

                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Settings")
            }
        }
        .navigationTitle("Photo Restore")
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
    }

    private var outputLabel: String {
        if let name = model.outputDirectory?.lastPathComponent, !name.isEmpty { return name }
        return "Output folder"
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
