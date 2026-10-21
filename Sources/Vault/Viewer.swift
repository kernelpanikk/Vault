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
    @State private var arrows: Any?

    private var media: [URL] { model.items.filter(\.isMedia) }

    var body: some View {
        ZStack {
            Theme.viewerBackground
            if url.isVideo {
                PlayerView(player: player)
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
        .onAppear {
            // ← → browse the folder even while the video player has focus (it would use them to seek).
            arrows = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) else { return event }
                switch event.keyCode {
                case 123: step(-1); return nil
                case 124: step(1); return nil
                default: return event
                }
            }
        }
        .onDisappear {
            player?.pause()
            if let arrows { NSEvent.removeMonitor(arrows) }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.space3) {
            Button { model.viewing = nil } label: { Theme.icon("close") }
                .keyboardShortcut(.cancelAction).help("Close")
            Button { step(-1) } label: { Image(systemName: "chevron.left") }.help("Previous")
            Button { step(1) } label: { Image(systemName: "chevron.right") }.help("Next")
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            if !url.isVideo {
                Button { zoom = clamp(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-").help("Zoom Out")
                Button { zoom = clamp(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=").help("Zoom In")
                // Space closes images like Quick Look; in videos it stays play/pause.
                Button("") { model.viewing = nil }
                    .keyboardShortcut(.space, modifiers: []).frame(width: 0).opacity(0)
            }
        }
        .buttonStyle(.borderless)
        .font(Theme.meta)
        .foregroundStyle(Theme.onScrim)
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
        .background(Theme.scrim, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .padding(Theme.space4)
    }

    private func step(_ offset: Int) {
        // reads model.viewing, not `url`: the key monitor keeps the copy of this view from when it appeared
        guard let current = model.viewing, let index = media.firstIndex(of: current),
              media.indices.contains(index + offset) else { return }
        model.viewing = media[index + offset]
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 1), 8) }
}

/// AppKit player. SwiftUI's VideoPlayer crashes on launch of the view (AVKit/SwiftUI overlay
/// built with the macOS 26 SDK running on macOS 27), so it is never used.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = false // PiP would show vault content outside the app
        view.showsSharingServiceButton = false      // sharing would hand the clear file to AirDrop, Mail…
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}
