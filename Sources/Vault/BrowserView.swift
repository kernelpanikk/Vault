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
    var isFolder: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
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
    static let itemType = "local.vault.item"
    static let dropTypes = [UTType(importedAs: itemType), .fileURL]

    var root: URL { vault.mountURL }

    func reload() {
        guard state == .unlocked else { return }
        usedSpace = ByteCountFormatter.string(fromByteCount: vault.sizeOnDisk, countStyle: .file) + " usati"
        tree = [Folder(url: root, children: subfolders(root))]
        items = list(folder ?? root)
        selection.formIntersection(items)
    }

    private func list(_ dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles)) ?? []
        return urls.sorted { a, b in
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
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            selection.formSymmetricDifference([url])
        } else if flags.contains(.shift), let anchor, let a = items.firstIndex(of: anchor), let b = items.firstIndex(of: url) {
            selection = Set(items[min(a, b)...max(a, b)])
        } else {
            selection = [url]
        }
        anchor = url
    }

    func open(_ url: URL) {
        if url.isFolder { folder = url } else if url.isMedia { viewing = url }
    }

    func newFolder() {
        guard state == .unlocked else { return }
        let url = unique((folder ?? root).appending(path: "Nuova cartella"))
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch { return fail(error) }
        reload()
        selection = [url]
        renaming = url
    }

    func rename(_ url: URL, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard url.isUnder(root), !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), name != url.lastPathComponent else { return }
        do { try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name)) } catch { fail(error) }
        reload()
    }

    func deleteSelection() {
        for url in selection where url.isUnder(root) && url.path != root.path {
            do { try FileManager.default.removeItem(at: url) } catch { fail(error) }
        }
        reload()
    }

    /// Drops from the Finder import (copy); drops from inside the app move.
    func drop(_ providers: [NSItemProvider], into dir: URL) -> Bool {
        Task {
            var outside: [URL] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(Self.itemType),
                   let data = try? await provider.loadItem(forTypeIdentifier: Self.itemType) as? Data {
                    move(URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), into: dir)
                } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    outside.append(url)
                }
            }
            if !outside.isEmpty { await importFiles(outside, into: dir) }
            reload()
        }
        return true
    }

    private func move(_ source: URL, into dir: URL) {
        guard source.isUnder(root), source.path != root.path, dir.isUnder(root), !dir.isUnder(source),
              source.deletingLastPathComponent().path != dir.path else { return }
        do { try FileManager.default.moveItem(at: source, to: unique(dir.appending(path: source.lastPathComponent))) } catch { fail(error) }
    }

    /// Drag payload visible only to this process, so nothing can be dragged out in clear.
    func provider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.itemType, visibility: .ownProcess) { done in
            done(Data(url.path.utf8), nil)
            return nil
        }
        return provider
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
        if copied.count < sources.count { problem = "\(sources.count - copied.count) elementi non importati." }
        if !copied.isEmpty { originals = copied }
    }

    func importPanel() {
        guard state == .unlocked else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Importa"
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
        panel.prompt = "Esporta qui"
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
    @State private var renameTarget: URL?
    @State private var newName = ""
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        let count = model.selection.count
        NavigationSplitView {
            List(selection: $model.folder) {
                OutlineGroup(model.tree, children: \.children) { node in
                    Label {
                        Text(node.url == model.root ? "Archivio" : node.url.lastPathComponent).font(Theme.label)
                    } icon: {
                        Theme.icon("folder").foregroundStyle(model.folder == node.url ? Theme.brass : Theme.inkMuted)
                    }
                    .onDrop(of: AppModel.dropTypes, isTargeted: nil) { model.drop($0, into: node.url) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .safeAreaInset(edge: .bottom) {
                Text(model.usedSpace).font(Theme.meta).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.space4)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: Theme.sidebarW, max: 320)
        } detail: {
            content
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
        .navigationTitle(model.folder.map { $0 == model.root ? "Archivio" : $0.lastPathComponent } ?? "Archivio")
        .toolbar { toolbar }
        .confirmationDialog("Eliminare \(count) \(count == 1 ? "elemento" : "elementi") per sempre?", isPresented: $model.confirmDelete) {
            Button("Elimina \(count) \(count == 1 ? "elemento" : "elementi")", role: .destructive) { model.deleteSelection() }
        } message: {
            Text("Non finiscono nel Cestino e non si possono recuperare.")
        }
        .alert("Rinomina", isPresented: present($model.renaming)) {
            TextField("Nome", text: $newName)
            Button("Rinomina") { if let renameTarget { model.rename(renameTarget, to: newName) } }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: model.renaming) { _, url in
            if let url { renameTarget = url; newName = url.lastPathComponent }
        }
        .alert("Esportare \(count) \(count == 1 ? "elemento" : "elementi")?", isPresented: $model.confirmExport) {
            Button("Scegli cartella…") { model.export() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le copie fuori da Vault non sono cifrate e restano visibili nel Finder.")
        }
        .alert("Spostare gli originali nel Cestino?", isPresented: present($model.originals)) {
            Button("Sposta nel Cestino") { model.trashOriginals() }
            Button("Lascia dove sono", role: .cancel) {}
        } message: {
            Text("Le copie sono già cifrate in Vault. Poi svuota il Cestino; le foto della libreria Foto vanno eliminate da Foto.")
        }
        .alert(model.problem ?? "", isPresented: present($model.problem)) {
            Button("Chiudi") {}
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.busy { ProgressView().controlSize(.small) }
            Button { model.newFolder() } label: { Label { Text("Nuova cartella") } icon: { Theme.icon("folder-plus", size: 20) } }
                .help("Nuova cartella (⇧⌘N)")
            Button { model.importPanel() } label: { Label { Text("Importa") } icon: { Theme.icon("import", size: 20) } }
                .help("Importa (⌘O)")
            if !listView {
                Slider(value: $thumbSize, in: Theme.thumbRange).tint(Theme.brass).frame(width: 100).help("Dimensione miniature")
            }
            Picker("Vista", selection: $listView) {
                Label { Text("Griglia") } icon: { Theme.icon("grid") }.tag(false)
                Label { Text("Elenco") } icon: { Theme.icon("list") }.tag(true)
            }
            .pickerStyle(.segmented)
            Button { model.lock() } label: { Label { Text("Blocca") } icon: { Theme.icon("lock", size: 20) } }
                .help("Blocca (⌘L)")
        }
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty { empty } else if listView { table } else { grid }
    }

    /// EmptyState inside a DropZone: one teaching sentence, one action.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            Theme.icon(targeted ? "import" : "eye-off", size: 32).foregroundStyle(targeted ? Theme.brass : Theme.inkMuted)
            Text(targeted ? "Rilascia per nascondere" : "Ancora niente qui").font(Theme.title).foregroundStyle(Theme.ink)
            Text("Trascina foto e video dal Finder in questa finestra. Dopo l'importazione puoi spostare gli originali nel Cestino.")
                .font(Theme.headline.weight(.regular)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.space2) {
                Button { model.importPanel() } label: {
                    HStack(spacing: Theme.space2) { Theme.icon("import"); Text("Scegli file…") }
                }
                .buttonStyle(PrimaryButton())
                Text("oppure premi ⌘O").font(Theme.meta).foregroundStyle(Theme.inkMuted)
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
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize), spacing: Theme.space2)], spacing: Theme.space2) {
                ForEach(model.items) { url in
                    Tile(url: url, selected: model.selection.contains(url))
                        .onTapGesture(count: 2) { model.open(url) }
                        .simultaneousGesture(TapGesture().onEnded { model.select(url); focused = true })
                        .onDrag { model.provider(for: url) }
                        .onDrop(of: url.isFolder ? AppModel.dropTypes : [], isTargeted: nil) { model.drop($0, into: url) }
                }
            }
            .padding(Theme.space6)
        }
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = []; focused = true })
    }

    private var table: some View {
        @Bindable var model = model
        return Table(of: URL.self, selection: $model.selection) {
            TableColumn("Nome") { url in
                Label { Text(url.lastPathComponent).font(Theme.body) } icon: {
                    Theme.icon(url.isFolder ? "folder" : url.isVideo ? "video" : "image").foregroundStyle(Theme.inkMuted)
                }
            }
            TableColumn("Tipo") { url in
                Text(url.isFolder ? "Cartella" : url.type.localizedDescription ?? "").font(Theme.body).foregroundStyle(Theme.inkMuted)
            }
            TableColumn("Dimensione") { url in
                Text(url.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(url.size), countStyle: .file)).font(Theme.meta)
            }
            TableColumn("Modificato") { url in Text(url.modified, format: .dateTime).font(Theme.meta) }
        } rows: {
            ForEach(model.items) { url in
                TableRow(url).itemProvider { model.provider(for: url) }
            }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
            if urls.count == 1, let url = urls.first { model.open(url) }
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
    @State private var image: NSImage?
    @State private var duration: String?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.surface)
            .overlay {
                if url.isFolder {
                    VStack(spacing: Theme.space2) {
                        Theme.icon("folder", size: 32).foregroundStyle(Theme.inkMuted)
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
                    .strokeBorder(selected ? Theme.brass : Theme.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
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
