import SwiftUI
import RestoreEngine

/// Before/after split-slider: the "after" image fills the frame; the "before" image is revealed
/// to the left of a draggable divider. While an image is still processing (no after yet), shows
/// the before image with a status overlay.
struct BeforeAfterView: View {
    let before: NSImage?
    let after: NSImage?
    let status: BatchItemStatus

    @State private var fraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                if let after {
                    fit(after)
                    if let before {
                        fit(before)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: max(0, w * fraction))
                            }
                        handle(in: geo.size)
                        labels
                    }
                } else if let before {
                    fit(before).opacity(0.6)
                    statusOverlay
                } else {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    fraction = min(1, max(0, v.location.x / w))
                }
            )
        }
        .padding(16)
    }

    private func fit(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(in size: CGSize) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: 2)
            .overlay(
                Circle().fill(.white).frame(width: 26, height: 26)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption2).foregroundStyle(.black))
                    .shadow(radius: 2)
            )
            .position(x: size.width * fraction, y: size.height / 2)
            .allowsHitTesting(false)
    }

    private var labels: some View {
        VStack {
            HStack {
                tag("Before"); Spacer(); tag("After")
            }
            Spacer()
        }
        .padding(8)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule()).foregroundStyle(.primary)
    }

    private var statusOverlay: some View {
        VStack(spacing: 8) {
            if case .processing = status { ProgressView() }
            Image(systemName: status.symbol).font(.title2).foregroundStyle(status.tint)
            Text(status.label).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
