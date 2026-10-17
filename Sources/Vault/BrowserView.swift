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
    var icon: NSImage { NSWorkspace.shared.icon(for: isFolder ? .folder : type) } // type icon, never a Quick Look preview
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
        NavigationSplitView {
            List(selection: $model.folder) {
                OutlineGroup(model.tree, children: \.children) { node in
                    Label(node.url == model.root ? "Archivio" : node.url.lastPathComponent, systemImage: "folder")
                        .onDrop(of: AppModel.dropTypes, isTargeted: nil) { model.drop($0, into: node.url) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(model.usedSpace).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.gap)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            content
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
        .overlay { if let url = model.viewing { Viewer(url: url) } }
        .navigationTitle(model.folder.map { $0 == model.root ? "Archivio" : $0.lastPathComponent } ?? "Archivio")
        .toolbar { toolbar }
        .confirmationDialog("Eliminare \(model.selection.count) elementi?", isPresented: $model.confirmDelete) {
            Button("Elimina", role: .destructive) { model.deleteSelection() }
        } message: {
            Text("L'eliminazione è definitiva.")
        }
        .alert("Rinomina", isPresented: present($model.renaming)) {
            TextField("Nome", text: $newName)
            Button("Rinomina") { if let renameTarget { model.rename(renameTarget, to: newName) } }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: model.renaming) { _, url in
            if let url { renameTarget = url; newName = url.lastPathComponent }
        }
        .alert("Esportare \(model.selection.count) elementi?", isPresented: $model.confirmExport) {
            Button("Esporta…") { model.export() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le copie esportate non sono cifrate.")
        }
        .alert("Spostare gli originali nel Cestino?", isPresented: present($model.originals)) {
            Button("Sposta nel Cestino") { model.trashOriginals() }
            Button("Lascia dove sono", role: .cancel) {}
        } message: {
            Text("Poi svuota il Cestino. Le foto della libreria Foto vanno eliminate da Foto.")
        }
        .alert(model.problem ?? "", isPresented: present($model.problem)) {
            Button("OK") {}
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.busy { ProgressView().controlSize(.small) }
            Button { model.newFolder() } label: { Label("Nuova cartella", systemImage: "folder.badge.plus") }
            Button { model.importPanel() } label: { Label("Importa", systemImage: "square.and.arrow.down") }
            if !listView {
                Slider(value: $thumbSize, in: Theme.thumbRange).frame(width: 100).help("Dimensione miniature")
            }
            Picker("Vista", selection: $listView) {
                Label("Icone", systemImage: "square.grid.2x2").tag(false)
                Label("Elenco", systemImage: "list.bullet").tag(true)
            }
            .pickerStyle(.segmented)
            Button { model.lock() } label: { Label("Blocca", systemImage: "lock") }
                .help("Blocca (⌘L)")
        }
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty { empty } else if listView { table } else { grid }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Trascina qui foto e video", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Oppure usa Importa (⌘O).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.radius * 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(Theme.padding)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSize), spacing: Theme.gap)], spacing: Theme.gap) {
                ForEach(model.items) { url in
                    Cell(url: url, size: thumbSize, selected: model.selection.contains(url))
                        .onTapGesture(count: 2) { model.open(url) }
                        .simultaneousGesture(TapGesture().onEnded { model.select(url); focused = true })
                        .onDrag { model.provider(for: url) }
                        .onDrop(of: url.isFolder ? AppModel.dropTypes : [], isTargeted: nil) { model.drop($0, into: url) }
                }
            }
            .padding(Theme.gap)
        }
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.selection = []; focused = true })
    }

    private var table: some View {
        @Bindable var model = model
        return Table(of: URL.self, selection: $model.selection) {
            TableColumn("Nome") { url in
                Label { Text(url.lastPathComponent) } icon: { Image(nsImage: url.icon).resizable().frame(width: 16, height: 16) }
            }
            TableColumn("Tipo") { url in Text(url.isFolder ? "Cartella" : url.type.localizedDescription ?? "") }
            TableColumn("Dimensione") { url in
                Text(url.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(url.size), countStyle: .file))
            }
            TableColumn("Modificato") { url in Text(url.modified, format: .dateTime) }
        } rows: {
            ForEach(model.items) { url in
                TableRow(url).itemProvider { model.provider(for: url) }
            }
        }
        .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
            if urls.count == 1, let url = urls.first { model.open(url) }
        }
    }

    private func present<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding { value.wrappedValue != nil } set: { if !$0 { value.wrappedValue = nil } }
    }
}

struct Cell: View {
    let url: URL
    let size: Double
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Thumb(url: url)
                .frame(width: size, height: size)
                .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: Theme.radius))
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? Color.accentColor : .clear, in: Capsule())
        }
        .frame(width: size)
        .contentShape(Rectangle())
    }
}

struct Thumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? url.icon)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius / 2))
            .overlay(alignment: .bottomTrailing) {
                if url.isVideo { Image(systemName: "play.circle.fill").foregroundStyle(.white).shadow(radius: 2).padding(6) }
            }
            .padding(6)
            .task(id: url) { if url.isMedia { image = await Thumbnails.shared.image(for: url) } }
    }
}
