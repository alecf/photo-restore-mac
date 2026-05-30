import SwiftUI
import RestoreEngine

/// The working layout once photos are queued: toolbar, before/after viewer for the selected
/// image, a filmstrip of all queued images, and an always-available settings inspector (the
/// modern macOS "drawer") that applies to whatever restores next.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = true

    private var selected: UIItem? { model.selectedItem }

    private var hasQueued: Bool {
        model.items.contains { if case .queued = $0.status { return true }; return false }
    }

    var body: some View {
        VStack(spacing: 0) {
            viewer
            Divider()
            FilmstripView(model: model)
                .frame(height: 132)
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

                Button { showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Settings")
            }
        }
        .inspector(isPresented: $showSettings) {
            SettingsView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
        }
        .navigationTitle("Photo Restore")
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
                status: item.status,
                divergences: model.divergences(for: item.appliedConfig)
            )
            .id(item.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            Color(nsColor: .underPageBackgroundColor)
        }
    }
}
