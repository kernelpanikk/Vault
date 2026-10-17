import Foundation

struct VaultError: LocalizedError {
    let errorDescription: String?
}

/// The encrypted sparsebundle. All crypto is done by hdiutil.
struct Vault {
    let dir: URL
    var bundleURL: URL { dir.appending(path: "vault.sparsebundle") }
    var mountURL: URL { dir.appending(path: ".mnt") }

    static let standard = Vault(dir: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Vault"))

    var exists: Bool { FileManager.default.fileExists(atPath: bundleURL.path) }

    /// A mounted volume has a different device number from its parent folder.
    var isMounted: Bool {
        let device = { (try? FileManager.default.attributesOfItem(atPath: $0))?[.systemNumber] as? Int }
        guard let mnt = device(mountURL.path), let parent = device(dir.path) else { return false }
        return mnt != parent
    }

    func create(password: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try hdiutil(["create", "-size", "1t", "-type", "SPARSEBUNDLE", "-fs", "APFS",
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

    func unmount() {
        if isMounted { try? hdiutil(["detach", mountURL.path, "-force"]) }
        rmdir(mountURL.path) // only removes an empty dir: never touches vault contents
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
    /// True for `root` itself or anything below it, after resolving `..`.
    func isUnder(_ root: URL) -> Bool {
        let path = standardizedFileURL.path, rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
