#!/bin/zsh
# Automatic part of docs/checklist.md. Usage: scripts/leakcheck.sh [nome-di-un-file-importato]
dir="$HOME/Library/Application Support/Vault"

echo "== Cartella dell'app (da bloccata: solo vault.sparsebundle e touchid)"
ls -a "$dir"
echo "== Volume del vault montato (da bloccata: nessuno)"
mount | grep -F "Vault/.mnt" || echo "nessuno"
echo "== /Volumes (il vault non deve comparire)"
ls /Volumes
if [[ -n "${1:-}" ]]; then
    echo "== Spotlight per '$1' (deve essere vuoto)"
    mdfind -name "$1" 2>/dev/null
fi
echo "== hdiutil in esecuzione (la password non deve comparire)"
ps aux | grep -v grep | grep hdiutil || echo "nessuno"
echo "== Connessioni di rete di Vault (deve essere vuoto)"
pid=$(pgrep -x Vault) && lsof -i -a -p $pid || echo "nessuna"
echo "== Miniature Quick Look più recenti del vault (deve essere vuoto)"
find "$TMPDIR/../C/com.apple.QuickLook.thumbnailcache" -type f -newer "$dir/vault.sparsebundle" 2>/dev/null | head
