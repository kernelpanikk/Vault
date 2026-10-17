// Compiled with Sources/Vault/Vault.swift by scripts/test.sh. Exits non-zero on failure.
import Foundation

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    print(ok ? "ok   \(what)" : "FAIL \(what) (riga \(line))")
    if !ok { failures += 1 }
}
var failures = 0

// Path guard used by every file operation.
let root = URL(fileURLWithPath: "/v/.mnt")
check(URL(fileURLWithPath: "/v/.mnt/a/b.jpg").isUnder(root), "file nel vault")
check(root.isUnder(root), "radice del vault")
check(!URL(fileURLWithPath: "/v/.mnt/../secret").isUnder(root), "rifiuta ..")
check(!URL(fileURLWithPath: "/v/.mntx/a").isUnder(root), "rifiuta prefisso simile")

// Moves inside the vault.
let a = URL(fileURLWithPath: "/v/.mnt/a", isDirectory: true), b = URL(fileURLWithPath: "/v/.mnt/b", isDirectory: true)
check(URL(fileURLWithPath: "/v/.mnt/a/f.jpg").canMove(into: b, root: root), "sposta file in altra cartella")
check(!a.canMove(into: a.appending(path: "sotto"), root: root), "rifiuta cartella dentro se stessa")
check(!URL(fileURLWithPath: "/v/.mnt/f.jpg").canMove(into: root, root: root), "rifiuta spostamento nella stessa cartella")
check(!URL(fileURLWithPath: "/Users/x/f.jpg").canMove(into: b, root: root), "rifiuta file da fuori archivio")
check(!root.canMove(into: b, root: root), "rifiuta la radice")

// Hidden items the user imported stay visible; volume bookkeeping does not.
check(!URL(fileURLWithPath: "/v/.mnt/.segreta").isSystemFile, "cartella nascosta dell'utente visibile")
check(URL(fileURLWithPath: "/v/.mnt/.DS_Store").isSystemFile, ".DS_Store nascosto")
check(URL(fileURLWithPath: "/v/.mnt/.fseventsd").isSystemFile, ".fseventsd nascosto")
check(URL(fileURLWithPath: "/v/.mnt/._foto.jpg").isSystemFile, "AppleDouble nascosto")

// Create / mount / unmount on a throwaway vault.
let vault = Vault(dir: FileManager.default.temporaryDirectory.appending(path: "vault-test-\(UUID().uuidString)"))
defer { vault.unmount(); try? FileManager.default.removeItem(at: vault.dir) }
do {
    try vault.create(password: "correct horse")
    check((try? vault.mount(password: "wrong")) == nil, "password errata rifiutata")
    check(!vault.isMounted, "non montato dopo password errata")

    try vault.mount(password: "correct horse")
    check(vault.isMounted, "montato")
    check(FileManager.default.fileExists(atPath: vault.mountURL.appending(path: ".metadata_never_index").path), "Spotlight escluso")
    try Data("ciao".utf8).write(to: vault.mountURL.appending(path: "a.txt"))
    let big = vault.mountURL.appending(path: "big.bin")
    try Data(count: 80 << 20).write(to: big)
    try FileManager.default.removeItem(at: big)

    vault.unmount()
    check(!vault.isMounted, "smontato")
    check(vault.sizeOnDisk > 0 && vault.sizeOnDisk < 1 << 30, "spazio reale, non il massimo da 200 GB")
    let before = vault.sizeOnDisk
    try vault.compact(password: "correct horse")
    check(vault.sizeOnDisk < before - (60 << 20), "compatta: \(before >> 20) MB → \(vault.sizeOnDisk >> 20) MB")
    check(!FileManager.default.fileExists(atPath: vault.mountURL.path), "da bloccato resta solo il sparsebundle")

    try vault.mount(password: "correct horse")
    check((try? String(contentsOf: vault.mountURL.appending(path: "a.txt"), encoding: .utf8)) == "ciao", "dati persistiti")
} catch {
    check(false, "hdiutil: \(error.localizedDescription)")
}

vault.unmount()
try? FileManager.default.removeItem(at: vault.dir)
exit(failures == 0 ? 0 : 1)
