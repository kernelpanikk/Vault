# Vault — regole del progetto

## Cos'è
App macOS personale (SwiftUI) che custodisce foto e video in un
sparsebundle APFS cifrato AES-256. Sblocco con Touch ID o master password.
Solo locale. Al blocco il volume viene smontato.

## Vincoli non negoziabili
- Zero dipendenze esterne. Solo framework Apple.
- Zero rete: niente URLSession, niente telemetria.
- La crittografia la fa hdiutil. Non scrivere crittografia propria.
- Passphrase solo via stdin (-stdinpass), mai in argomenti o log.
- Mount con -nobrowse -noautoopen e mountpoint dentro Application Support.
- Miniature solo in RAM (NSCache) con ImageIO/AVFoundation.
  Vietato QLThumbnailGenerator e qualsiasi cache su disco.
- window.sharingType = .none; niente state restoration; niente NSDocument.
- Nessun file temporaneo in chiaro fuori dal volume montato.
- Ogni evento di blocco chiama un'unica funzione lock() (AppModel, VaultApp.swift).
- Drag and drop: ogni elemento si trascina come file URL. Rilasciato dentro
  l'app viene spostato, nel Finder o in un'altra app viene esportato in chiaro
  (scelta dell'utente, 17 Oct 2026, al posto del divieto iniziale).

## Decisioni dalla Fase 0 (17 Oct 2026)
- Niente Xcode installato e SwiftPM delle Command Line Tools rotto
  (PackageDescription non corrisponde a swiftc 6.3): si compila con swiftc
  diretto in scripts/build-app.sh (firma ad-hoc + Hardened Runtime).
  Test = eseguibile con assert in Tests/main.swift.
- Keychain data-protection con biometryCurrentSet dà -34018 senza team di
  firma, e il Keychain di login mostrava finestre di sistema a ogni sblocco.
  Soluzione: password sigillata (HPKE, CryptoKit) con una chiave Secure Enclave
  biometryCurrentSet, salvata in Application Support/Vault/touchid (Unlock.swift).
- Archivio HFS+ da 200 GB, non APFS: su APFS hdiutil compact recupera ~1%
  dello spazio cancellato (misurato 4 MB su 300), su HFS+ quasi tutto.
  Compattazione alla chiusura (applicationWillTerminate) e da menu.
- mdutil -i off richiede root: si usa solo .metadata_never_index.

## Stile
- Ponytail: il minimo codice che funziona. Prima API di sistema.
- Token di design solo in Theme.swift, presi dal design system "Vault"
  (claude.ai/artifact/21hQm2FSHgtY5X8UWwFkbm): colori OKLCH convertiti in sRGB,
  Hanken Grotesk + IBM Plex Mono in Resources/Fonts, icone SVG in Resources/Icons,
  icona app Resources/AppIcon.icns da design/vault-mark.svg.
- Testi in italiano (regola del progetto), ma con le regole di contenuto del
  design system: verbi specifici, conseguenze esplicite, niente "OK".
- Solo build di debug: VAULT_DIR=<cartella> usa un archivio di prova,
  VAULT_TEST_PASSWORD=<pw> lo sblocca da solo (per screenshot).
- Testi UI in italiano, brevi.

## Comandi
- Build: scripts/build-app.sh [--debug] [--install]  → build/Vault.app
- Test: scripts/test.sh
- Checklist: scripts/leakcheck.sh [nome-file]

## Dopo ogni fase
1. Build e test verdi
2. /ponytail-review
3. /security-review
4. Checklist anti-leak (docs/checklist.md)
5. Commit
