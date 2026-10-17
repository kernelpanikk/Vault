# Checklist anti-leak

Rifarla dopo ogni modifica che tocca file o blocco. `scripts/leakcheck.sh <nome-file>`
esegue le voci marcate (auto); le altre sono a mano. Usare la build Release
(`scripts/build-app.sh`): solo lì la finestra è esclusa dagli screenshot.

| | Voce | Come |
|---|---|---|
| [ ] | Da bloccata: in `~/Library/Application Support/Vault/` c'è solo `vault.sparsebundle`, nessun volume montato | auto |
| [ ] | Da sbloccata: il volume non è nella barra laterale del Finder, né sulla scrivania, né in `/Volumes` | auto (`/Volumes`) + a mano |
| [ ] | `mdfind` con il nome di un file importato non restituisce nulla | auto |
| [ ] | Nessuna miniatura nuova nella cache di Quick Look | auto |
| [ ] | ⌘⇧3 con l'app aperta: la finestra esce vuota | a mano |
| [ ] | ⌘Q, poi riapri: compare lo sblocco, nessuna anteprima del contenuto | a mano |
| [ ] | Chiudi il coperchio o blocca lo schermo (⌃⌘Q): al ritorno l'app è bloccata | a mano |
| [ ] | Forza l'uscita da Monitoraggio Attività, riapri: il volume viene smontato subito | a mano, poi auto |
| [ ] | `ps aux \| grep hdiutil` durante lo sblocco: la password non compare | auto (lanciarlo mentre sblocchi) |
| [ ] | Dopo l'import con "Sposta nel Cestino": gli originali non sono più in Download/Scrivania | a mano |
| [ ] | Touch ID annullato tre volte: resta la password, nessun crash | a mano |
| [ ] | Rete: l'app non apre connessioni | auto (`lsof -i`) |
| [ ] | Trascina un file dall'app al Finder: non succede nulla | a mano |

## Da ricordare
- Il Cestino va svuotato dopo "Sposta nel Cestino"; Foto ha la sua libreria.
- FileVault attivo protegge lo swap.
- Backup: Time Machine copia il sparsebundle cifrato. A mano: copiarlo con l'app bloccata.
- Spazio dopo molte eliminazioni: `hdiutil compact ~/Library/Application\ Support/Vault/vault.sparsebundle` ad app bloccata.
