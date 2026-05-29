import SwiftUI
import UniformTypeIdentifiers
import RestoreEngine

/// Root view. For now it establishes the welcome → work-area skeleton: an empty drop zone
/// that accepts a file or folder, expands the dropped set into decodable images, and lists
/// them. The before/after viewer, filmstrip, live preview, and settings (U8) build on this.
struct ContentView: View {
    @State private var droppedImages: [URL] = []
    @State private var isTargeted = false
    @State private var showImporter = false

    var body: some View {
        Group {
            if droppedImages.isEmpty {
                welcome
            } else {
                workArea
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            ingest(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { ingest(urls) }
        }
        .animation(.easeInOut(duration: 0.2), value: droppedImages.isEmpty)
    }

    // MARK: - States

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Drag a photo or folder here")
                .font(.title2.weight(.medium))
            Text("Old scans, faded prints, low-res photos — dropped in, restored out.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Photos…") { showImporter = true }
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropBackdrop)
        .contentShape(Rectangle())
    }

    private var workArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(droppedImages.count) image\(droppedImages.count == 1 ? "" : "s") ready")
                    .font(.headline)
                Spacer()
                Button("Add More…") { showImporter = true }
                Button("Clear") { droppedImages = [] }
            }
            .padding()

            // Placeholder filmstrip — replaced by the real before/after viewer + tray in U8.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(droppedImages, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "photo")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var dropBackdrop: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            .padding(24)
    }

    // MARK: - Ingest

    /// Expand dropped URLs (files and folders) into the set of images the engine can decode,
    /// recursing folders. Dedup by canonical path; preserves a stable sorted order.
    private func ingest(_ urls: [URL]) {
        var found: [URL] = []
        for url in urls {
            if isDirectory(url) {
                found.append(contentsOf: imageFiles(in: url))
            } else if ImageLoading.canDecode(url: url) {
                found.append(url)
            }
        }
        var seen = Set(droppedImages.map(\.standardizedFileURL))
        for url in found.sorted(by: { $0.path < $1.path }) {
            let key = url.standardizedFileURL
            if seen.insert(key).inserted {
                droppedImages.append(url)
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func imageFiles(in folder: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where ImageLoading.canDecode(url: url) {
            out.append(url)
        }
        return out
    }
}

#Preview {
    ContentView()
        .frame(width: 720, height: 520)
}
