# Vault

App macOS personale per custodire foto e video in un archivio cifrato.
Si sblocca con Touch ID o con la master password. Tutto resta sul Mac:
niente rete, niente cloud, niente telemetria.

## Come funziona

- L'archivio è uno sparsebundle cifrato AES-256 creato e montato da `hdiutil`.
  Vault non contiene crittografia propria.
- La passphrase passa a `hdiutil` solo via stdin, mai negli argomenti o nei log.
- Il volume si monta in Application Support con `-nobrowse -noautoopen`:
  non compare nel Finder né sulla scrivania.
- Touch ID: la password è sigillata con una chiave Secure Enclave legata
  alle impronte attuali. Se cambiano le impronte serve di nuovo la password.
- Al blocco il volume viene smontato. Le miniature vivono solo in RAM.
- La finestra è esclusa da screenshot e registrazioni dello schermo.
- Alla chiusura l'archivio viene compattato per recuperare lo spazio dei file eliminati.

## Cosa fa

- Griglia ed elenco con miniature, cartelle, breadcrumb cliccabile
- Visualizzatore per foto e video (Spazio)
- Importa, esporta, rinomina, sposta, elimina
- Drag and drop: dentro l'app sposta, verso Finder o altre app esporta in chiaro

| Scorciatoia | Azione |
|---|---|
| ⌘O | Importa |
| ⇧⌘E | Esporta |
| ⇧⌘N | Nuova cartella |
| ⌘↑ | Cartella superiore |
| ⌘⌫ | Elimina |
| ⌘= / ⌘− | Zoom nel visualizzatore |
| ⌘L | Blocca |

## Requisiti

- macOS 26, Apple Silicon, Touch ID opzionale
- Command Line Tools con `swiftc` (Xcode non serve)
- Zero dipendenze esterne: solo framework Apple

## Build

```bash
scripts/build-app.sh            # build/Vault.app
scripts/build-app.sh --install  # copia in /Applications
scripts/test.sh                 # test
scripts/leakcheck.sh            # checklist anti-leak (docs/checklist.md)
```

La firma è ad-hoc con Hardened Runtime.

Solo nelle build di debug (`--debug`): `VAULT_DIR=<cartella>` usa un archivio
di prova, `VAULT_TEST_PASSWORD=<pw>` lo sblocca da solo.

## Struttura

```
Sources/Vault/   app SwiftUI (VaultApp: AppModel e lock(), Vault: hdiutil, Unlock: Touch ID)
Tests/main.swift test con assert
Resources/       icone, font, Info.plist
design/          sorgenti grafici
docs/            checklist anti-leak
```
