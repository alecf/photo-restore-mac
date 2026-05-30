import SwiftUI
import RestoreEngine

/// Horizontal tray of every queued image with a status badge — the way to peruse a 100+ batch
/// while the viewer shows one before/after at a time. Click to select; thumbnails are lazy and
/// downsampled.
struct FilmstripView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 10) {
                ForEach(model.items) { item in
                    cell(item)
                        .onTapGesture { model.selectedID = item.id }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func cell(_ item: UIItem) -> some View {
        let selected = item.id == model.selectedID
        return VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = model.thumbnail(for: item) {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                Image(systemName: item.status.symbol)
                    .font(.caption2.weight(.bold))
                    .symbolEffect(.pulse, isActive: isProcessing(item.status))
                    .padding(3)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(item.status.tint)
                    .padding(4)
                    .help(item.status.label)
            }
            Text(item.input.lastPathComponent)
                .font(.caption2).lineLimit(1).truncationMode(.middle)
                .frame(width: 84)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .accessibilityLabel("\(item.input.lastPathComponent), \(item.status.label)")
    }

    private func isProcessing(_ s: BatchItemStatus) -> Bool {
        if case .processing = s { return true }; return false
    }
}
