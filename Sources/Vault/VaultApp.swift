import SwiftUI

@main
struct VaultApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Vault", id: "main") {
            RootView().environment(delegate.model)
        }
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands { VaultCommands(model: delegate.model) }

        Settings { SettingsView() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group { if model.state == .unlocked { BrowserView() } else { LockView() } }
            .tint(Theme.brass)
            .containerBackground(Theme.bg, for: .window) // title bar shares the window ground
    }
}

@MainActor @Observable
final class AppModel {
    enum State { case setup, locked, unlocked }

    let vault = Vault.standard
    private(set) var state: State
    var error: String?
    var busy = false

    // Browser state; the file operations live in BrowserView.swift.
    var folder: URL? { didSet { selection = []; reload() } }
    var selection: Set<URL> = []
    var anchor: URL?
    var items: [URL] = []
    var tree: [Folder] = []
    var viewing: URL?
    var renaming: URL?
    var confirmDelete = false
    var confirmExport = false
    var originals: [URL]?
    var problem: String?
    var usedSpace = ""

    private var password: String?     // kept only while unlocked, to compact after unmounting
    private var locks = 0             // bumped by every lock(), so an unlock still mounting knows it was cancelled
    private var countAtActivation = 0 // pasteboard changeCount when the app last came to the front
    private var ownCount: Int?        // changeCount right after something was copied inside the app

    init() {
        vault.unmount() // a crash or force quit may have left the volume mounted
        state = vault.exists ? .locked : .setup
    }

    func unlock(password: String, remember: Bool = true) async {
        busy = true
        error = nil
        defer { busy = false }
        let vault = vault, create = state == .setup, locksBefore = locks
        do {
            try await Task.detached {
                if create { try vault.create(password: password) }
                try vault.mount(password: password)
            }.value
        } catch {
            if create && vault.exists { state = .locked }
            self.error = create ? "Impossibile creare l'archivio." : "Password errata."
            return
        }
        guard locks == locksBefore else { return vault.unmount() } // sleep or lock screen arrived while mounting
        if remember { TouchID.save(password) }
        self.password = password
        countAtActivation = NSPasteboard.general.changeCount
        state = .unlocked
        folder = root
        refreshUsedSpace()
    }

    func unlockWithBiometrics() async {
        guard state == .locked, !busy, TouchID.available, let password = await TouchID.load() else { return }
        await unlock(password: password, remember: false)
    }

    /// The single exit point: every lock event ends here.
    func lock(compact: Bool = false) {
        locks += 1
        guard state == .unlocked else { return }
        let password = self.password
        self.password = nil
        viewing = nil
        renaming = nil
        selection = []
        items = []
        tree = []
        Thumbnails.shared.clear()
        clearPasteboard()
        vault.unmount()
        state = .locked
        if compact, let password { try? vault.compact(password: password) }
    }

    /// Menu version: compacts in the background; `busy` keeps the lock screen from unlocking meanwhile.
    func lockAndCompact() {
        guard state == .unlocked, let password else { return }
        lock()
        busy = true
        let vault = vault
        Task {
            await Task.detached { try? vault.compact(password: password) }.value
            busy = false
        }
    }

    func appDidBecomeActive() { countAtActivation = NSPasteboard.general.changeCount }

    func appDidResignActive() {
        let count = NSPasteboard.general.changeCount
        if count != countAtActivation { ownCount = count } // copied while Vault was in front
    }

    /// Clears only what came from the vault; copies made in other apps stay.
    private func clearPasteboard() {
        let pasteboard = NSPasteboard.general
        let copiedHere = (NSApp.isActive && pasteboard.changeCount != countAtActivation) || pasteboard.changeCount == ownCount
        let vaultFiles = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.contains { $0.isUnder(root) } == true
        if copiedHere || vaultFiles { pasteboard.clearContents() }
        ownCount = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var idleTimer: Timer?
    private var sigterm: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) { Theme.registerFonts() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // kill/pkill send SIGTERM, which skips applicationWillTerminate: route it through a normal quit.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { NSApp.terminate(nil) }
        sigterm?.resume()
        UserDefaults.standard.register(defaults: ["lockMinutes": 5, "NSQuitAlwaysKeepsWindows": false])
        let lock: @Sendable (Notification) -> Void = { [model] _ in MainActor.assumeIsolated { model.lock() } }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willPowerOffNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main, using: lock)
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main, using: lock)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated {
                model.appDidResignActive()
                if UserDefaults.standard.bool(forKey: "lockOnBackground") { model.lock() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.appDidBecomeActive() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow else { return }
                window.isRestorable = false
                #if !DEBUG // debug builds stay capturable for screenshots during development
                window.sharingType = .none
                #endif
            }
        }
        // shortcut: system-wide idle time, so a long video with no input also locks. Fine for a vault.
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [model] _ in
            MainActor.assumeIsolated {
                let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
                if idle > Double(UserDefaults.standard.integer(forKey: "lockMinutes") * 60) { model.lock() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.lock(compact: true) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct VaultCommands: Commands {
    let model: AppModel

    var body: some Commands {
        let locked = model.state != .unlocked
        CommandGroup(replacing: .newItem) {
            Button("Nuova cartella") { model.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(locked)
            Button("Cartella superiore") { model.openParent() }
                .keyboardShortcut(.upArrow, modifiers: .command).disabled(locked)
            Button("Importa…") { model.importPanel() }
                .keyboardShortcut("o").disabled(locked)
            Button("Esporta…") { model.confirmExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(locked || model.selection.isEmpty)
            Divider()
            Button("Elimina") { model.confirmDelete = true }
                .keyboardShortcut(.delete).disabled(locked || model.selection.isEmpty)
            Divider()
            Button("Blocca") { model.lock() }
                .keyboardShortcut("l").disabled(locked)
            Button("Blocca e compatta") { model.lockAndCompact() }
                .disabled(locked)
        }
    }
}

struct SettingsView: View {
    @AppStorage("lockMinutes") private var minutes = 5
    @AppStorage("lockOnBackground") private var onBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            Stepper("Blocca dopo \(minutes) min di inattività", value: $minutes, in: 1...60)
            Toggle("Blocca quando passi a un'altra app", isOn: $onBackground)
        }
        .font(Theme.body)
        .tint(Theme.brass)
        .padding(Theme.space6)
        .fixedSize() // window sized to its content, so nothing is clipped
    }
}
