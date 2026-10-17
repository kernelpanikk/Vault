import AVKit
import SwiftUI

/// In-app viewer: files are never handed to Preview or QuickTime (they'd land in Recents).
struct Viewer: View {
    @Environment(AppModel.self) private var model
    let url: URL
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var zoom = 1.0
    @State private var pinch = 1.0

    private var media: [URL] { model.items.filter(\.isMedia) }

    var body: some View {
        ZStack {
            Theme.viewerBackground
            if url.isVideo {
                VideoPlayer(player: player)
            } else if let image {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: geo.size.width * zoom * pinch, height: geo.size.height * zoom * pinch)
                    }
                    .scrollIndicators(zoom > 1 ? .automatic : .hidden)
                    .gesture(MagnifyGesture()
                        .onChanged { pinch = $0.magnification }
                        .onEnded { zoom = clamp(zoom * $0.magnification); pinch = 1 })
                    .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2 }
                }
            }
        }
        .overlay(alignment: .top) { controls }
        .task(id: url) {
            zoom = 1
            player?.pause()
            player = nil
            image = nil
            if url.isVideo {
                player = AVPlayer(url: url)
                player?.play()
            } else {
                let url = url
                image = await Task.detached { NSImage(contentsOf: url) }.value
            }
        }
        .onDisappear { player?.pause() }
    }

    private var controls: some View {
        HStack(spacing: Theme.gap) {
            Button { model.viewing = nil } label: { Image(systemName: "xmark") }
                .keyboardShortcut(.cancelAction)
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            if !url.isVideo {
                Button { zoom = clamp(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-")
                Button { zoom = clamp(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=")
                // Space closes images like Quick Look; in videos it stays play/pause.
                Button("") { model.viewing = nil }
                    .keyboardShortcut(.space, modifiers: []).frame(width: 0).opacity(0)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.gap * 1.5)
        .padding(.vertical, Theme.gap / 2)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(Theme.gap)
    }

    private func step(_ offset: Int) {
        guard let index = media.firstIndex(of: url), media.indices.contains(index + offset) else { return }
        model.viewing = media[index + offset]
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 1), 8) }
}
