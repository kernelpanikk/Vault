import Foundation

struct VaultError: LocalizedError {
    let errorDescription: String?
}

/// The encrypted sparsebundle. All crypto is done by hdiutil.
struct Vault {
    let dir: URL
    var bundleURL: URL { dir.appending(path: "vault.sparsebundle") }
    var mountURL: URL { dir.appending(path: ".mnt") }

    static let standard: Vault = {
        #if DEBUG // lets a debug build run on a throwaway vault: VAULT_DIR=/tmp/x Vault.app/Contents/MacOS/Vault
        if let dir = ProcessInfo.processInfo.environment["VAULT_DIR"] { return Vault(dir: URL(fileURLWithPath: dir)) }
        #endif
        return Vault(dir: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Vault"))
    }()

    /// Real space the encrypted bundle takes on the Mac (the volume itself reports its 200 GB maximum).
    var sizeOnDisk: Int64 {
        let files = FileManager.default.enumerator(at: bundleURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        return (files?.allObjects as? [URL] ?? []).reduce(0) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
    }

    var exists: Bool { FileManager.default.fileExists(atPath: bundleURL.path) }

    /// A mounted volume has a different device number from its parent folder.
    var isMounted: Bool {
        let device = { (try? FileManager.default.attributesOfItem(atPath: $0))?[.systemNumber] as? Int }
        guard let mnt = device(mountURL.path), let parent = device(dir.path) else { return false }
        return mnt != parent
    }

    func create(password: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try hdiutil(["create", "-size", "200g", "-type", "SPARSEBUNDLE", "-fs", "JHFS+", // HFS+: hdiutil compact reclaims deleted space, APFS barely
                     "-encryption", "AES-256", "-stdinpass", "-volname", "Vault", bundleURL.path], stdin: password)
    }

    func mount(password: String) throws {
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        do {
            try hdiutil(["attach", bundleURL.path, "-stdinpass", "-nobrowse", "-noautoopen", "-noverify",
                         "-mountpoint", mountURL.path], stdin: password)
        } catch {
            rmdir(mountURL.path)
            throw error
        }
        // mdutil -i off needs root; this marker keeps Spotlight out without it.
        FileManager.default.createFile(atPath: mountURL.appending(path: ".metadata_never_index").path, contents: nil)
    }

    /// Gives back to the Mac the space of deleted files. Only works on a detached vault.
    func compact(password: String) throws {
        try hdiutil(["compact", bundleURL.path, "-stdinpass", "-batteryallowed"], stdin: password)
    }

    func unmount() {
        if isMounted { try? hdiutil(["detach", mountURL.path, "-force"]) }
        // rmdir only removes an empty dir, never vault contents.
        // shortcut: while the app runs, macOS may keep the (empty) mountpoint busy, so it can stay until the next launch.
        rmdir(mountURL.path)
    }

    private func hdiutil(_ args: [String], stdin: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = args
        let input = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try input.fileHandleForWriting.close()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw VaultError(errorDescription: message) }
    }
}

extension URL {
    /// Files macOS keeps in every volume or folder by itself, never imported by the user.
    var isSystemFile: Bool {
        let name = lastPathComponent
        return name.hasPrefix("._") || name.hasPrefix(".HFS+ Private") || [
            ".DS_Store", ".metadata_never_index", ".fseventsd", ".Trashes", ".Spotlight-V100", ".TemporaryItems",
            ".DocumentRevisions-V100", ".journal", ".journal_info_block", ".VolumeIcon.icns", ".com.apple.timemachine.donotpresent",
        ].contains(name)
    }

    /// A move inside the vault that changes something: not the root, not into itself or its own folder.
    func canMove(into dir: URL, root: URL) -> Bool {
        isUnder(root) && path != root.path && dir.isUnder(root) && !dir.isUnder(self)
            && deletingLastPathComponent().path != dir.path
    }

    var parentFolder: URL { URL(fileURLWithPath: deletingLastPathComponent().path, isDirectory: true) }

    /// True for `root` itself or anything below it, after resolving `..`.
    func isUnder(_ root: URL) -> Bool {
        let path = standardizedFileURL.path, rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
