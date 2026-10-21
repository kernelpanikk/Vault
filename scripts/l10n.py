# Writes Resources/<lang>.lproj from the tables below. Usage: python3 scripts/l10n.py Resources
# Row order: it fr zh-Hans es de ja pt-BR
import os, sys, plistlib
LANGS = ["it", "fr", "zh-Hans", "es", "de", "ja", "pt-BR"]
T = {
"Couldn't create the vault.": ["Impossibile creare l'archivio.", "Impossible de créer le coffre.", "无法创建保险库。", "No se pudo crear la bóveda.", "Der Tresor konnte nicht erstellt werden.", "保管庫を作成できませんでした。", "Não foi possível criar o cofre."],
"Wrong password.": ["Password errata.", "Mot de passe incorrect.", "密码错误。", "Contraseña incorrecta.", "Falsches Passwort.", "パスワードが違います。", "Senha incorreta."],
"New Folder": ["Nuova cartella", "Nouveau dossier", "新建文件夹", "Nueva carpeta", "Neuer Ordner", "新規フォルダ", "Nova pasta"],
"Enclosing Folder": ["Cartella superiore", "Dossier parent", "上层文件夹", "Carpeta superior", "Übergeordneter Ordner", "親フォルダ", "Pasta superior"],
"Import…": ["Importa…", "Importer…", "导入…", "Importar…", "Importieren …", "読み込む…", "Importar…"],
"Export…": ["Esporta…", "Exporter…", "导出…", "Exportar…", "Exportieren …", "書き出す…", "Exportar…"],
"Delete": ["Elimina", "Supprimer", "删除", "Eliminar", "Löschen", "削除", "Apagar"],
"Lock": ["Blocca", "Verrouiller", "锁定", "Bloquear", "Sperren", "ロック", "Bloquear"],
"Lock and Compact": ["Blocca e compatta", "Verrouiller et compacter", "锁定并压缩", "Bloquear y compactar", "Sperren und komprimieren", "ロックして圧縮", "Bloquear e compactar"],
"General": ["Generali", "Général", "通用", "General", "Allgemein", "一般", "Geral"],
"Language": ["Lingua", "Langue", "语言", "Idioma", "Sprache", "言語", "Idioma"],
"Restart Vault to use the new language.": ["Riavvia Vault per usare la nuova lingua.", "Redémarrez Vault pour utiliser la nouvelle langue.", "重新启动 Vault 以使用新语言。", "Reinicia Vault para usar el nuevo idioma.", "Starte Vault neu, um die neue Sprache zu verwenden.", "新しい言語を使うには Vault を再起動してください。", "Reinicie o Vault para usar o novo idioma."],
"Restart Now": ["Riavvia ora", "Redémarrer", "立即重新启动", "Reiniciar ahora", "Jetzt neu starten", "今すぐ再起動", "Reiniciar agora"],
"Security": ["Sicurezza", "Sécurité", "安全性", "Seguridad", "Sicherheit", "セキュリティ", "Segurança"],
"Lock after inactivity": ["Blocca dopo inattività", "Verrouiller après inactivité", "闲置后锁定", "Bloquear tras inactividad", "Sperren nach Inaktivität", "操作がないときにロック", "Bloquear após inatividade"],
"%lld min": ["%lld min", "%lld min", "%lld 分钟", "%lld min", "%lld Min.", "%lld 分", "%lld min"],
"Lock when switching to another app": ["Blocca quando passi a un'altra app", "Verrouiller en passant à une autre app", "切换到其他 App 时锁定", "Bloquear al cambiar a otra app", "Sperren beim Wechsel zu einer anderen App", "ほかのアプリに切り替えたらロック", "Bloquear ao mudar para outro app"],
"Create your vault": ["Crea l'archivio", "Créez votre coffre", "创建保险库", "Crea tu bóveda", "Tresor erstellen", "保管庫を作成", "Crie seu cofre"],
"Vault is locked": ["Vault è bloccato", "Vault est verrouillé", "Vault 已锁定", "Vault está bloqueado", "Vault ist gesperrt", "Vault はロックされています", "O Vault está bloqueado"],
"Choose a master password. If you forget it, your files can't be recovered.": ["Scegli la master password. Se la dimentichi, i file non si recuperano.", "Choisissez un mot de passe principal. Si vous l'oubliez, vos fichiers seront irrécupérables.", "请设置主密码。如果忘记，文件将无法恢复。", "Elige una contraseña maestra. Si la olvidas, no podrás recuperar los archivos.", "Wähle ein Master-Passwort. Wenn du es vergisst, sind die Dateien verloren.", "マスターパスワードを設定してください。忘れるとファイルは復元できません。", "Escolha uma senha mestra. Se esquecê-la, os arquivos não poderão ser recuperados."],
"Encrypted on this Mac only": ["Cifrato solo su questo Mac", "Chiffré uniquement sur ce Mac", "仅在此 Mac 上加密存储", "Cifrado solo en este Mac", "Nur auf diesem Mac verschlüsselt", "この Mac 上でのみ暗号化", "Criptografado apenas neste Mac"],
"Unlock with Touch ID": ["Sblocca con Touch ID", "Déverrouiller avec Touch ID", "使用触控 ID 解锁", "Desbloquear con Touch ID", "Mit Touch ID entsperren", "Touch ID でロック解除", "Desbloquear com Touch ID"],
"or use your master password": ["oppure usa la master password", "ou utilisez le mot de passe principal", "或使用主密码", "o usa la contraseña maestra", "oder Master-Passwort verwenden", "またはマスターパスワードを使用", "ou use a senha mestra"],
"Master password (at least 8 characters)": ["Master password (almeno 8 caratteri)", "Mot de passe principal (8 caractères min.)", "主密码（至少 8 个字符）", "Contraseña maestra (mín. 8 caracteres)", "Master-Passwort (mind. 8 Zeichen)", "マスターパスワード（8文字以上）", "Senha mestra (mín. 8 caracteres)"],
"Master password": ["Master password", "Mot de passe principal", "主密码", "Contraseña maestra", "Master-Passwort", "マスターパスワード", "Senha mestra"],
"Repeat password": ["Ripeti la password", "Confirmez le mot de passe", "再次输入密码", "Repite la contraseña", "Passwort wiederholen", "パスワードを再入力", "Repita a senha"],
"Create Vault": ["Crea archivio", "Créer le coffre", "创建保险库", "Crear bóveda", "Tresor erstellen", "保管庫を作成", "Criar cofre"],
"Unlock": ["Sblocca", "Déverrouiller", "解锁", "Desbloquear", "Entsperren", "ロック解除", "Desbloquear"],
"Use Password": ["Usa password", "Utiliser le mot de passe", "使用密码", "Usar contraseña", "Passwort verwenden", "パスワードを使用", "Usar senha"],
"unlock your vault": ["sbloccare l'archivio", "déverrouiller votre coffre", "解锁保险库", "desbloquear tu bóveda", "deinen Tresor zu entsperren", "保管庫のロックを解除", "desbloquear seu cofre"],
"%@ used": ["%@ usati", "%@ utilisés", "已用 %@", "%@ usados", "%@ belegt", "%@ 使用中", "%@ usados"],
"“%@” isn't a valid name.": ["“%@” non è un nome valido.", "« %@ » n'est pas un nom valide.", "“%@”不是有效的名称。", "“%@” no es un nombre válido.", "„%@“ ist kein gültiger Name.", "“%@”は有効な名前ではありません。", "“%@” não é um nome válido."],
"Import": ["Importa", "Importer", "导入", "Importar", "Importieren", "読み込む", "Importar"],
"Export Here": ["Esporta qui", "Exporter ici", "导出到此处", "Exportar aquí", "Hierhin exportieren", "ここに書き出す", "Exportar aqui"],
"Library": ["Archivio", "Bibliothèque", "资料库", "Biblioteca", "Mediathek", "ライブラリ", "Biblioteca"],
"They won't go to the Trash and can't be recovered.": ["Non finiscono nel Cestino e non si possono recuperare.", "Ils ne passent pas par la Corbeille et sont irrécupérables.", "它们不会移到废纸篓，也无法恢复。", "No irán a la Papelera y no se podrán recuperar.", "Sie landen nicht im Papierkorb und sind nicht wiederherstellbar.", "ゴミ箱には入らず、復元できません。", "Eles não vão para o Lixo e não poderão ser recuperados."],
"Rename": ["Rinomina", "Renommer", "重新命名", "Renombrar", "Umbenennen", "名前を変更", "Renomear"],
"Name": ["Nome", "Nom", "名称", "Nombre", "Name", "名前", "Nome"],
"Cancel": ["Annulla", "Annuler", "取消", "Cancelar", "Abbrechen", "キャンセル", "Cancelar"],
"Choose Folder…": ["Scegli cartella…", "Choisir un dossier…", "选择文件夹…", "Elegir carpeta…", "Ordner auswählen …", "フォルダを選択…", "Escolher pasta…"],
"Copies outside Vault aren't encrypted and stay visible in Finder.": ["Le copie fuori da Vault non sono cifrate e restano visibili nel Finder.", "Les copies hors de Vault ne sont pas chiffrées et restent visibles dans le Finder.", "Vault 之外的副本不会加密，并会显示在“访达”中。", "Las copias fuera de Vault no están cifradas y quedan visibles en el Finder.", "Kopien außerhalb von Vault sind unverschlüsselt und im Finder sichtbar.", "Vault の外のコピーは暗号化されず、Finder に表示されます。", "As cópias fora do Vault não são criptografadas e ficam visíveis no Finder."],
"Move the originals to the Trash?": ["Spostare gli originali nel Cestino?", "Placer les originaux dans la Corbeille ?", "将原件移到废纸篓？", "¿Mover los originales a la Papelera?", "Originale in den Papierkorb legen?", "オリジナルをゴミ箱に入れますか？", "Mover os originais para o Lixo?"],
"Move to Trash": ["Sposta nel Cestino", "Placer dans la Corbeille", "移到废纸篓", "Mover a la Papelera", "In den Papierkorb", "ゴミ箱に入れる", "Mover para o Lixo"],
"Keep Originals": ["Lascia dove sono", "Garder les originaux", "保留原件", "Conservar originales", "Originale behalten", "オリジナルを残す", "Manter originais"],
"The copies are already encrypted in Vault. Empty the Trash afterwards; photos from the Photos library must be deleted in Photos.": ["Le copie sono già cifrate in Vault. Poi svuota il Cestino; le foto della libreria Foto vanno eliminate da Foto.", "Les copies sont déjà chiffrées dans Vault. Videz ensuite la Corbeille ; les photos de la photothèque doivent être supprimées dans Photos.", "副本已在 Vault 中加密。之后请清倒废纸篓；“照片”图库中的照片需在“照片”中删除。", "Las copias ya están cifradas en Vault. Después vacía la Papelera; las fotos de la fototeca se eliminan desde Fotos.", "Die Kopien sind bereits in Vault verschlüsselt. Leere danach den Papierkorb; Fotos aus der Fotos-Mediathek musst du in Fotos löschen.", "コピーはすでに Vault で暗号化されています。あとでゴミ箱を空にしてください。写真ライブラリの写真は“写真”で削除する必要があります。", "As cópias já estão criptografadas no Vault. Depois esvazie o Lixo; fotos da biblioteca do Fotos devem ser apagadas no Fotos."],
"Close": ["Chiudi", "Fermer", "关闭", "Cerrar", "Schließen", "閉じる", "Fechar"],
"New Folder (⇧⌘N)": ["Nuova cartella (⇧⌘N)", "Nouveau dossier (⇧⌘N)", "新建文件夹 (⇧⌘N)", "Nueva carpeta (⇧⌘N)", "Neuer Ordner (⇧⌘N)", "新規フォルダ (⇧⌘N)", "Nova pasta (⇧⌘N)"],
"Import (⌘O)": ["Importa (⌘O)", "Importer (⌘O)", "导入 (⌘O)", "Importar (⌘O)", "Importieren (⌘O)", "読み込む (⌘O)", "Importar (⌘O)"],
"Thumbnail Size": ["Dimensione anteprime", "Taille des vignettes", "缩略图大小", "Tamaño de miniaturas", "Miniaturgröße", "サムネールのサイズ", "Tamanho das miniaturas"],
"View": ["Vista", "Présentation", "显示", "Visualización", "Darstellung", "表示", "Visualização"],
"Grid": ["Griglia", "Grille", "网格", "Cuadrícula", "Raster", "グリッド", "Grade"],
"List": ["Elenco", "Liste", "列表", "Lista", "Liste", "リスト", "Lista"],
"Lock (⌘L)": ["Blocca (⌘L)", "Verrouiller (⌘L)", "锁定 (⌘L)", "Bloquear (⌘L)", "Sperren (⌘L)", "ロック (⌘L)", "Bloquear (⌘L)"],
"Drop to hide": ["Rilascia per nascondere", "Déposez pour masquer", "松开以隐藏", "Suelta para ocultar", "Zum Verbergen loslassen", "ドロップして隠す", "Solte para ocultar"],
"Nothing here yet": ["Ancora niente qui", "Rien pour l'instant", "这里还没有内容", "Aún no hay nada", "Noch nichts hier", "まだ何もありません", "Nada aqui ainda"],
"Drag photos and videos from Finder into this window. After importing, you can move the originals to the Trash.": ["Trascina foto e video dal Finder in questa finestra. Dopo l'importazione puoi spostare gli originali nel Cestino.", "Faites glisser des photos et vidéos depuis le Finder dans cette fenêtre. Après l'import, vous pourrez placer les originaux dans la Corbeille.", "将照片和视频从“访达”拖到此窗口。导入后可以将原件移到废纸篓。", "Arrastra fotos y vídeos desde el Finder a esta ventana. Tras importarlos, puedes mover los originales a la Papelera.", "Ziehe Fotos und Videos aus dem Finder in dieses Fenster. Nach dem Import kannst du die Originale in den Papierkorb legen.", "Finder から写真やビデオをこのウインドウにドラッグしてください。読み込んだあと、オリジナルをゴミ箱に入れられます。", "Arraste fotos e vídeos do Finder para esta janela. Depois de importar, você pode mover os originais para o Lixo."],
"Choose Files…": ["Scegli file…", "Choisir des fichiers…", "选择文件…", "Elegir archivos…", "Dateien auswählen …", "ファイルを選択…", "Escolher arquivos…"],
"or press ⌘O": ["oppure premi ⌘O", "ou appuyez sur ⌘O", "或按下 ⌘O", "o pulsa ⌘O", "oder ⌘O drücken", "または ⌘O を押す", "ou pressione ⌘O"],
"Kind": ["Tipo", "Type", "种类", "Tipo", "Art", "種類", "Tipo"],
"Size": ["Dimensione", "Taille", "大小", "Tamaño", "Größe", "サイズ", "Tamanho"],
"Modified": ["Modificato", "Modifié", "修改日期", "Modificado", "Geändert", "変更日", "Modificado"],
"Folder": ["Cartella", "Dossier", "文件夹", "Carpeta", "Ordner", "フォルダ", "Pasta"],
"Open": ["Apri", "Ouvrir", "打开", "Abrir", "Öffnen", "開く", "Abrir"],
"Previous": ["Precedente", "Précédent", "上一个", "Anterior", "Zurück", "前へ", "Anterior"],
"Next": ["Successivo", "Suivant", "下一个", "Siguiente", "Weiter", "次へ", "Próximo"],
"Zoom Out": ["Riduci", "Zoom arrière", "缩小", "Reducir", "Verkleinern", "縮小", "Reduzir"],
"Offline": ["Offline", "Hors ligne", "离线", "Sin conexión", "Offline", "オフライン", "Offline"],
"Zoom In": ["Ingrandisci", "Zoom avant", "放大", "Ampliar", "Vergrößern", "拡大", "Ampliar"],
}
# Plurals: key -> {lang: (one, other)}; zh-Hans and ja use only "other".
P = {
"Delete %lld items forever?": {"en": ("Delete %lld item forever?", "Delete %lld items forever?"),
  "it": ("Eliminare %lld elemento per sempre?", "Eliminare %lld elementi per sempre?"), "fr": ("Supprimer définitivement %lld élément ?", "Supprimer définitivement %lld éléments ?"),
  "zh-Hans": (None, "要永久删除 %lld 个项目吗？"), "es": ("¿Eliminar %lld elemento para siempre?", "¿Eliminar %lld elementos para siempre?"),
  "de": ("%lld Objekt endgültig löschen?", "%lld Objekte endgültig löschen?"), "ja": (None, "%lld 項目を完全に削除しますか？"),
  "pt-BR": ("Apagar %lld item para sempre?", "Apagar %lld itens para sempre?")},
"Delete %lld items": {"en": ("Delete %lld item", "Delete %lld items"), "it": ("Elimina %lld elemento", "Elimina %lld elementi"),
  "fr": ("Supprimer %lld élément", "Supprimer %lld éléments"), "zh-Hans": (None, "删除 %lld 个项目"), "es": ("Eliminar %lld elemento", "Eliminar %lld elementos"),
  "de": ("%lld Objekt löschen", "%lld Objekte löschen"), "ja": (None, "%lld 項目を削除"), "pt-BR": ("Apagar %lld item", "Apagar %lld itens")},
"Export %lld items?": {"en": ("Export %lld item?", "Export %lld items?"), "it": ("Esportare %lld elemento?", "Esportare %lld elementi?"),
  "fr": ("Exporter %lld élément ?", "Exporter %lld éléments ?"), "zh-Hans": (None, "要导出 %lld 个项目吗？"), "es": ("¿Exportar %lld elemento?", "¿Exportar %lld elementos?"),
  "de": ("%lld Objekt exportieren?", "%lld Objekte exportieren?"), "ja": (None, "%lld 項目を書き出しますか？"), "pt-BR": ("Exportar %lld item?", "Exportar %lld itens?")},
"%lld items couldn't be imported.": {"en": ("%lld item couldn't be imported.", "%lld items couldn't be imported."),
  "it": ("%lld elemento non importato.", "%lld elementi non importati."), "fr": ("%lld élément n'a pas pu être importé.", "%lld éléments n'ont pas pu être importés."),
  "zh-Hans": (None, "%lld 个项目无法导入。"), "es": ("No se pudo importar %lld elemento.", "No se pudieron importar %lld elementos."),
  "de": ("%lld Objekt konnte nicht importiert werden.", "%lld Objekte konnten nicht importiert werden."), "ja": (None, "%lld 項目を読み込めませんでした。"),
  "pt-BR": ("%lld item não pôde ser importado.", "%lld itens não puderam ser importados.")},
}
out = sys.argv[1]
esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
for lang in ["en"] + LANGS:
    d = os.path.join(out, f"{lang}.lproj"); os.makedirs(d, exist_ok=True)
    if lang != "en":
        i = LANGS.index(lang)
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write("/* Generated table: keys are the English strings in Sources/Vault. */\n")
            for k, v in T.items(): f.write(f'"{esc(k)}" = "{esc(v[i])}";\n')
    plurals = {}
    for k, forms in P.items():
        one, other = forms[lang]
        rule = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld", "other": other}
        if one: rule["one"] = one
        plurals[k] = {"NSStringLocalizedFormatKey": "%#@n@", "n": rule}
    with open(os.path.join(d, "Localizable.stringsdict"), "wb") as f: plistlib.dump(plurals, f)
print(len(T), "strings,", len(P), "plurals")
