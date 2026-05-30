import SwiftUI
import RestoreEngine

/// Horizontal tray of every queued image with a status badge — peruse a 100+ batch while the
/// viewer shows one before/after at a time. Click to select, drag to reorder, hover to remove,
/// and re-restore a done photo with the current settings.
struct FilmstripView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 10) {
                ForEach(model.items) { item in
                    FilmstripCell(model: model, item: item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}

private struct FilmstripCell: View {
    @ObservedObject var model: AppModel
    let item: UIItem
    @State private var hovering = false

    private var selected: Bool { item.id == model.selectedID }
    private var isDone: Bool { if case .done = item.status { return true }; return false }

    var body: some View {
        VStack(spacing: 4) {
            thumb
                .overlay(alignment: .topLeading) { if hovering { removeButton } }
                .overlay(alignment: .bottomLeading) { if isDone { redoButton } }
                .overlay(alignment: .bottomTrailing) { statusBadge }
            Text(item.input.lastPathComponent)
                .font(.caption2).lineLimit(1).truncationMode(.middle)
                .frame(width: 84)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .onHover { hovering = $0 }
        .onTapGesture { model.selectedID = item.id }
        .draggable(item.id.uuidString) { dragPreview }
        .dropDestination(for: String.self) { ids, _ in
            if let s = ids.first, let uid = UUID(uuidString: s) { model.move(id: uid, before: item.id) }
            return true
        }
        .accessibilityLabel("\(item.input.lastPathComponent), \(item.status.label)")
    }

    private var thumb: some View {
        Group {
            if let t = model.thumbnail(for: item) {
                Image(nsImage: t).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3))
    }

    private var dragPreview: some View {
        (model.thumbnail(for: item).map { Image(nsImage: $0).resizable() } ?? Image(systemName: "photo").resizable())
            .scaledToFill().frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusBadge: some View {
        Image(systemName: item.status.symbol)
            .font(.caption2.weight(.bold))
            .symbolEffect(.pulse, isActive: { if case .processing = item.status { return true }; return false }())
            .padding(3).background(.ultraThinMaterial, in: Circle())
            .foregroundStyle(item.status.tint)
            .padding(4)
            .help(item.status.label)
    }

    /// Re-restore with the current settings. Disabled when those settings match the ones that
    /// produced this result (the output would be identical).
    private var redoButton: some View {
        let enabled = model.canReRestore(item)
        return Button { model.reRestore(item) } label: {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.body)
                .padding(3)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .padding(4)
        .help(enabled ? "Restore again with the current settings"
                      : "Already restored with the current settings")
    }

    private var removeButton: some View {
        Button { model.remove(item) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .padding(3).background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(4)
        .help("Remove from the list")
    }
}
