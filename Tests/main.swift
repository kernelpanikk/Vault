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

    vault.unmount()
    check(!vault.isMounted, "smontato")
    check(!FileManager.default.fileExists(atPath: vault.mountURL.path), "da bloccato resta solo il sparsebundle")

    try vault.mount(password: "correct horse")
    check((try? String(contentsOf: vault.mountURL.appending(path: "a.txt"), encoding: .utf8)) == "ciao", "dati persistiti")
} catch {
    check(false, "hdiutil: \(error.localizedDescription)")
}

vault.unmount()
try? FileManager.default.removeItem(at: vault.dir)
exit(failures == 0 ? 0 : 1)
