import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct Folder: Identifiable, Hashable {
    let url: URL
    var children: [Folder]?
    var id: URL { url }
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}

extension URL {
    var isFolder: Bool { hasDirectoryPath } // vault URLs are built with isDirectory (see list), so no disk access
    var type: UTType { UTType(filenameExtension: pathExtension) ?? .data }
    var isVideo: Bool { type.conforms(to: .audiovisualContent) }
    var isMedia: Bool { type.conforms(to: .image) || isVideo }
    var size: Int { (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    var modified: Date { (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
}

/// First free name: "foto.jpg", "foto 2.jpg", "foto 3.jpg"…
func unique(_ url: URL) -> URL {
    let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
    var candidate = url, n = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = dir.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
        n += 1
    }
    return candidate
}

// MARK: - File operations

extension AppModel {
    static let dropTypes: [UTType] = [.fileURL]

    /// Folder URLs are always built as directories, so the same folder compares equal wherever it came from.
    var root: URL { URL(fileURLWithPath: vault.mountURL.path, isDirectory: true) }

    /// Reads every band of the bundle, so only after unlock, import and delete, never on navigation.
    func refreshUsedSpace() {
        usedSpace = String(localized: "\(ByteCountFormatter.string(fromByteCount: vault.sizeOnDisk, countStyle: .file)) used")
    }

    func reload() {
        guard state == .unlocked else { return }
        tree = [Folder(url: root, children: subfolders(root))]
        items = list(folder ?? root)
        selection.formIntersection(items)
    }

    private func list(_ dir: URL) -> [URL] {
        // Hidden items the user imported are shown; only the volume's own bookkeeping files are not.
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])) ?? []
        return urls.filter { !$0.isSystemFile }.map {
            URL(fileURLWithPath: $0.path, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }.sorted { a, b in
            a.isFolder != b.isFolder ? a.isFolder
                : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    private func subfolders(_ dir: URL) -> [Folder]? {
        let folders = list(dir).filter(\.isFolder).map { Folder(url: $0, children: subfolders($0)) }
        return folders.isEmpty ? nil : folders
    }

    /// Finder-style click: plain, ⌘ toggles, ⇧ extends from the last click.
    func select(_ url: URL) {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags // the click's own modifiers
        if flags.contains(.command) {
            selection.formSymmetricDifference([url])
        } else if flags.contains(.shift), let anchor, let a = items.firstIndex(of: anchor), let b = items.firstIndex(of: url) {
            selection = Set(items[min(a, b)...max(a, b)])
        } else {
            selection = [url]
        }
        anchor = url
    }

    func openParent() {
        guard state == .unlocked, let folder, folder.path != root.path else { return }
        self.folder = folder.parentFolder
    }

    func open(_ url: URL) {
        if url.isFolder { folder = url } else if url.isMedia { viewing = url }
    }

    func newFolder() {
        guard state == .unlocked else { return }
        let url = URL(fileURLWithPath: unique((folder ?? root).appending(path: String(localized: "New Folder"))).path, isDirectory: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch { return fail(error) }
        reload()
        selection = [url]
        renaming = url
    }

    func rename(_ url: URL, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard url.isUnder(root), name != url.lastPathComponent else { return }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !URL(fileURLWithPath: name).isSystemFile else {
            problem = String(localized: "“\(name)” isn't a valid name.")
            return
        }
        do { try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name)) } catch { fail(error) }
        reload()
    }

    /// Delete and export act on these items; both ask for confirmation first.
    func askDelete(_ urls: Set<URL>) {
        guard state == .unlocked, !urls.isEmpty, renaming == nil else { return } // ⌘⌫ while renaming edits the text
        selection = urls
        confirmDelete = true
    }

    func askExport(_ urls: Set<URL>) {
        guard state == .unlocked, !urls.isEmpty else { return }
        selection = urls
        confirmExport = true
    }

    func deleteSelection() {
        for url in selection where url.isUnder(root) && url.path != root.path {
            do { try FileManager.default.removeItem(at: url) } catch { fail(error) }
        }
        reload()
        refreshUsedSpace()
    }

    /// Files already in the vault move; files from the Finder are imported (copied).
    func drop(_ providers: [NSItemProvider], into dir: URL) -> Bool {
        Task {
            var outside: [URL] = []
            for provider in providers {
                guard let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { continue }
                if url.isUnder(root) { move(url, into: dir) } else { outside.append(url) }
            }
            if !outside.isEmpty { await importFiles(outside, into: dir) }
            reload()
        }
        return true
    }

    private func move(_ source: URL, into dir: URL) {
        guard source.canMove(into: dir, root: root) else { return }
        do { try FileManager.default.moveItem(at: source, to: unique(dir.appending(path: source.lastPathComponent))) } catch { fail(error) }
    }

    func importFiles(_ urls: [URL], into dir: URL) async {
        let sources = urls.filter { !$0.isUnder(root) }
        guard state == .unlocked, dir.isUnder(root), !sources.isEmpty else { return }
        busy = true
        let copied = await Task.detached {
            sources.filter { (try? FileManager.default.copyItem(at: $0, to: unique(dir.appending(path: $0.lastPathComponent)))) != nil }
        }.value
        busy = false
        reload()
        refreshUsedSpace()
        if copied.count < sources.count { problem = String(localized: "\(sources.count - copied.count) items couldn't be imported.") }
        if !copied.isEmpty { originals = copied }
    }

    func importPanel() {
        guard state == .unlocked else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Import")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        Task { await importFiles(panel.urls, into: folder ?? root) }
    }

    func trashOriginals() {
        for url in originals ?? [] {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { fail(error) }
        }
        originals = nil
    }

    func export() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Export Here")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let dest = panel.url, !dest.isUnder(root) else { return }
        for url in selection {
            do { try FileManager.default.copyItem(at: url, to: unique(dest.appending(path: url.lastPathComponent))) } catch { fail(error) }
        }
    }

    private func fail(_ error: Error) { problem = error.localizedDescription }
}

// MARK: - Views

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("thumbSize") private var thumbSize = Theme.thumbDefault
    @AppStorage("listView") private var listView = false
    @State private var targeted = false
    @State private var dropFolder: URL?   // folder under a drag, highlighted
    @State private var gridWidth: CGFloat = 0
    @State private var cursor: URL?       // moving end of a Shift+arrow selection; `anchor` is the fixed end
    @State private var renameTarget: URL?
    @State private var newName = ""
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        let count = model.selection.count
        NavigationSplitView {
            List(selection: $model.folder) {
                OutlineGroup(model.tree, children: \.children) { node in sidebarRow(node.url) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .safeAreaInset(edge: .bottom) {
                Label(model.usedSpace, systemImage: "internaldrive").font(Theme.meta).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.space4)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: Theme.sidebarW, max: 320)
        } detail: {
            content
                .safeAreaInset(edge: .top, spacing: 0) { breadcrumbs }
                .background(Theme.bg)
                .onDrop(of: AppModel.dropTypes, isTargeted: $targeted) { model.drop($0, into: model.folder ?? model.root) }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.return) {
                    guard model.selection.count == 1 else { return .ignored }
                    model.renaming = model.selection.first
                    return .handled
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { arrow($0) }
                .onKeyPress(.space) {
                    guard let url = model.items.first(where: { model.selection.contains($0) && $0.isMedia }) else { return .ignored }
                    model.viewing = url
                    return .handled
                }
                .onCommand(#selector(NSResponder.selectAll(_:))) { model.selection = Set(model.items) }
                .onAppear { focused = true }
        }
        .tint(Theme.brass)
        .overlay { if let url = model.viewing { Viewer(url: url) } }
        .navigationTitle(model.folder.map { $0 == model.root ? String(localized: "Library") : $0.lastPathComponent } ?? String(localized: "Library"))
        .toolbar { toolbar }
        .confirmationDialog("Delete \(count) items forever?", isPresented: $model.confirmDelete) {
            Button("Delete \(count) items", role: .destructive) { model.deleteSelection() }
                .keyboardShortcut(.defaultAction) // Return confirms (user's choice); Esc still cancels
        } message: {
            Text("They won't go to the Trash and can't be recovered.")
        }
        .alert("Rename", isPresented: present($model.renaming)) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renameTarget { model.rename(renameTarget, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: model.renaming) { _, url in
            if let url { renameTarget = url; newName = url.lastPathComponent }
        }
        .alert("Export \(count) items?", isPresented: $model.confirmExport) {
            Button("Choose Folder…") { model.export() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copies outside Vault aren't encrypted and stay visible in Finder.")
        }
        .alert("Move the originals to the Trash?", isPresented: present($model.originals)) {
            Button("Move to Trash") { model.trashOriginals() }
            Button("Keep Originals", role: .cancel) {}
        } message: {
            Text("The copies are already encrypted in Vault. Empty the Trash afterwards; photos from the Photos library must be deleted in Photos.")
        }
        .alert(model.problem ?? "", isPresented: present($model.problem)) {
            Button("Close") {}
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.busy { ProgressView().controlSize(.small) }
            Button { model.newFolder() } label: { Label { Text("New Folder") } icon: { Theme.icon("folder-plus", size: 20) } }
                .help("New Folder (⇧⌘N)")
            Button { model.importPanel() } label: { Label { Text("Import") } icon: { Theme.icon("import", size: 20) } }
                .help("Import (⌘O)")
            if !listView {
                HStack(spacing: Theme.space1) {
                    Theme.icon("image", size: 12).foregroundStyle(Theme.inkMuted)
                    Slider(value: $thumbSize, in: Theme.thumbRange).tint(Theme.brass).frame(width: 120)
                    Theme.icon("image", size: 20).foregroundStyle(Theme.inkMuted)
                }
                .help("Thumbnail Size")
                .accessibilityLabel("Thumbnail Size")
            }
            Picker("View", selection: $listView) {
                Label { Text("Grid") } icon: { Theme.icon("grid") }.tag(false)
                Label { Text("List") } icon: { Theme.icon("list") }.tag(true)
            }
            .pickerStyle(.segmented)
            Button { model.lock() } label: { Label { Text("Lock") } icon: { Theme.icon("lock", size: 20) } }
                .help("Lock (⌘L)")
        }
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty { empty } else if listView { table } else { grid }
    }

    /// EmptyState inside a DropZone: one teaching sentence, one action.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            Theme.icon(targeted ? "import" : "eye-off", size: 32).foregroundStyle(targeted ? Theme.brass : Theme.inkMuted)
            Text(targeted ? "Drop to hide" : "Nothing here yet").font(Theme.title).foregroundStyle(Theme.ink)
            Text("Drag photos and videos from Finder into this window. After importing, you can move the originals to the Trash.")
                .font(Theme.headline.weight(.regular)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: Theme.space2) {
                Button { model.importPanel() } label: {
                    HStack(spacing: Theme.space2) { Theme.icon("import"); Text("Choose Files…") }
                }
                .buttonStyle(PrimaryButton())
                Text("or press ⌘O").font(Theme.meta).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(Theme.space12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .fill(targeted ? Theme.brassSubtle : .clear)
                .strokeBorder(targeted ? Theme.brass : Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .padding(Theme.space6)
        }
        .animation(Theme.quick, value: targeted)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize), spacing: Theme.space2)],
                          alignment: .leading, spacing: Theme.space2) {
                    ForEach(model.items) { url in
                        Tile(url: url, selected: model.selection.contains(url), dropTarget: dropFolder == url)
                            .id(url)
                            .onTapGesture(count: 2) { model.open(url) }
                            .simultaneousGesture(TapGesture().onEnded { model.select(url); cursor = nil; focused = true })
                            .draggable(containerItemID: url)
                            // Right-click acts on the selection when the tile is part of it, else on the tile alone.
                            .contextMenu { menu(for: model.selection.contains(url) ? model.selection : [url]) }
                            .onDrop(of: url.isFolder ? AppModel.dropTypes : [], isTargeted: target(url)) { model.drop($0, into: url) }
                    }
                }
                .padding(Theme.space6)
                // Dragging a selected tile drags the whole selection, as file URLs (moved in-app, copied outside).
                .dragContainer(for: URL.self) { ids in ids }
                .dragContainerSelection(model.items.filter { model.selection.contains($0) })
            }
            .onChange(of: cursor ?? model.anchor) { _, url in if let url { proxy.scrollTo(url) } }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = []; focused = true })
    }

    /// Path from the library root to the open folder; each crumb opens its folder and accepts drops.
    private var breadcrumbs: some View {
        var trail = [model.folder ?? model.root]
        while let last = trail.last, last.path != model.root.path, last.isUnder(model.root) {
            trail.append(last.parentFolder)
        }
        let crumbs = Array(trail.reversed())
        return HStack(spacing: Theme.space1) {
            ForEach(crumbs.indices, id: \.self) { i in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkMuted) }
                crumb(crumbs[i], current: i == crumbs.count - 1)
            }
        }
        .padding(.horizontal, Theme.space6 - 6)
        .padding(.vertical, Theme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func crumb(_ url: URL, current: Bool) -> some View {
        Button { if !current { model.folder = url } } label: {
            HStack(spacing: Theme.space1) {
                Theme.icon("folder", size: 14)
                Text(url.path == model.root.path ? String(localized: "Library") : url.lastPathComponent).lineLimit(1)
            }
            .font(Theme.label)
            .foregroundStyle(current ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(dropFolder == url ? Theme.brassSubtle : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: AppModel.dropTypes, isTargeted: target(url)) { model.drop($0, into: url) }
    }

    private func sidebarRow(_ url: URL) -> some View {
        let active = model.folder == url || dropFolder == url
        return Label {
            Text(url == model.root ? String(localized: "Library") : url.lastPathComponent).font(Theme.label)
        } icon: {
            Theme.icon("folder").foregroundStyle(active ? Theme.brass : Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowBackground(dropFolder == url ? RoundedRectangle(cornerRadius: Theme.radiusMd).fill(Theme.brassSubtle) : nil)
        .onDrop(of: AppModel.dropTypes, isTargeted: target(url)) { model.drop($0, into: url) }
    }

    /// Arrow keys move the selection through the grid (up/down jump one row); with Shift they extend it.
    private func arrow(_ press: KeyPress) -> KeyPress.Result {
        let items = model.items
        guard !listView, !items.isEmpty else { return .ignored }
        let columns = max(1, Int((gridWidth - 2 * Theme.space6 + Theme.space2) / (thumbSize + Theme.space2)))
        let step = [KeyEquivalent.leftArrow: -1, .rightArrow: 1, .upArrow: -columns, .downArrow: columns][press.key] ?? 0
        let current = (cursor ?? model.anchor).flatMap { items.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? 0
        if press.modifiers.contains(.shift), let start = model.anchor.flatMap({ items.firstIndex(of: $0) }) {
            model.selection = Set(items[min(start, next)...max(start, next)])
        } else {
            model.selection = [items[next]]
            model.anchor = items[next]
        }
        cursor = items[next]
        return .handled
    }

    /// Highlights a folder (grid tile or sidebar row) while something is dragged over it.
    private func target(_ url: URL) -> Binding<Bool> {
        Binding { dropFolder == url } set: { over in
            if over { dropFolder = url } else if dropFolder == url { dropFolder = nil }
        }
    }

    private var table: some View {
        @Bindable var model = model
        return Table(of: URL.self, selection: $model.selection) {
            TableColumn("Name") { url in
                Label { Text(url.lastPathComponent).font(Theme.body) } icon: {
                    Theme.icon(url.isFolder ? "folder" : url.isVideo ? "video" : "image").foregroundStyle(url.isFolder ? Theme.brass : Theme.inkMuted)
                }
            }
            TableColumn("Kind") { url in
                Text(url.isFolder ? String(localized: "Folder") : url.type.localizedDescription ?? "").font(Theme.body).foregroundStyle(Theme.inkMuted)
            }
            TableColumn("Size") { url in
                Text(url.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(url.size), countStyle: .file)).font(Theme.meta)
            }
            TableColumn("Modified") { url in Text(url.modified, format: .dateTime).font(Theme.meta) }
        } rows: {
            ForEach(model.items) { url in
                TableRow(url).draggable(url) // file URL: moved when dropped in the app, exported in clear outside
            }
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: URL.self) { urls in menu(for: urls) } primaryAction: { urls in
            if urls.count == 1, let url = urls.first { model.open(url) }
        }
    }

    private func menu(for urls: Set<URL>) -> some View {
        Group { menuItems(for: urls) }.labelStyle(.titleAndIcon) // context menus hide the icons otherwise
    }

    @ViewBuilder private func menuItems(for urls: Set<URL>) -> some View {
        if urls.count == 1, let url = urls.first {
            Button("Open", systemImage: "eye") { model.open(url) }
            Button("Rename", systemImage: "pencil") { model.selection = urls; model.renaming = url }
            Divider()
        }
        if !urls.isEmpty {
            Button("Export…", systemImage: "square.and.arrow.up") { model.askExport(urls) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.askDelete(urls) }
        }
    }

    private func present<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding { value.wrappedValue != nil } set: { if !$0 { value.wrappedValue = nil } }
    }
}

/// MediaTile: square, `radius-sm`, no caption on media; selection = brass outline + check badge.
struct Tile: View {
    let url: URL
    let selected: Bool
    var dropTarget = false
    @State private var image: NSImage?
    @State private var duration: String?
    @State private var hovered = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.surface)
            .overlay {
                if url.isFolder {
                    VStack(spacing: Theme.space2) {
                        Theme.icon("folder", size: 40).foregroundStyle(Theme.brass)
                        Text(url.lastPathComponent).font(Theme.label).foregroundStyle(Theme.ink)
                            .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, Theme.space2)
                    }
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Theme.icon(url.isVideo ? "video" : "image", size: 24).foregroundStyle(Theme.inkMuted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .overlay(alignment: .bottomLeading) {
                if url.isVideo {
                    HStack(spacing: Theme.space1) {
                        Theme.icon("play", size: 12)
                        if let duration { Text(duration) }
                    }
                    .font(Theme.meta).foregroundStyle(Theme.onScrim)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.scrim, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .padding(Theme.space1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Theme.icon("check", size: 14).foregroundStyle(Theme.onBrass)
                        .frame(width: 20, height: 20).background(Theme.brass, in: Circle()).padding(Theme.space1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .strokeBorder(selected || dropTarget ? Theme.brass : hovered ? Theme.lineStrong : Theme.line,
                                  style: StrokeStyle(lineWidth: selected || dropTarget ? 2 : 1, dash: dropTarget ? [6, 4] : []))
            }
            .background(dropTarget ? Theme.brassSubtle : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(Theme.quick, value: hovered)
            .help(url.lastPathComponent)
            .task(id: url) {
                guard url.isMedia else { return }
                image = await Thumbnails.shared.image(for: url)
                if url.isVideo, let time = try? await AVURLAsset(url: url).load(.duration), time.isNumeric {
                    let seconds = Int(time.seconds)
                    duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
                }
            }
    }
}
