# Audit del repository — 2026-11-21

Scope: documentazione, file non tracciati, simboli Swift/C++ orfani, chiavi di
preferenza, script, risorse, coerenza delle fixture e delle localizzazioni.

Metodo (comandi eseguiti sul repository reale):

- `git ls-files` + `du -k` per i file tracciati e le dimensioni;
- conteggio dei riferimenti per `PrefKey`, membri `static`, viste, funzioni
  `private`, API `vt_*`;
- `swift build -Xcc -Wunused-function` per il bridge;
- `Scripts/check-localization.sh`; `shasum -a 256` sulle fixture;
- `git status --ignored` per distinguere artefatti locali da file del repo.

## Pulizia eseguita

| Intervento | Dettaglio |
|---|---|
| Rimosso `docs/swift6-and-typography.md` | Descriveva `sessionQueue`/`SessionPointerBox` e 69 test: obsoleto dopo il refactor dell'actor. |
| Commenti aggiornati | Tre commenti in `TorrentEngine+Actions.swift` e `+Settings.swift` parlavano ancora di "session queue". |
| `CHANGELOG-archive.md` | Le release fino alla 1.10.2 sono state spostate qui; `CHANGELOG.md` passa da 1903 a 437 righe. |
| `default.profraw` | Artefatto locale non tracciato, eliminato. |
| DMG locali | Rimosse 1.15.0, 1.16.0 e 1.17.0 da `dist/` (ignorate da git). |

## Esito dei controlli

| Controllo | Esito |
|---|---|
| Chiavi `PrefKey` | 25/25 usate, nessuna chiave o default orfano. |
| Membri `Preferences` | Tutti usati (`migrateLegacyProxyPassword`, `rawDownloadPath`, …). |
| Viste SwiftUI | Tutte referenziate; nessuna vista morta. |
| API `vt_*` | Ogni funzione dichiarata in `vertex_torrent.h` è chiamata da Swift o dai test. |
| C++ (`-Wunused-function`) | Nessuna funzione o variabile statica non usata. |
| Script | Tutti i 25 file in `Scripts/` sono usati da build, CI, README o altri script. |
| Risorse | `Resources/Licenses` è copiata in blocco dal `build.sh`; GeoIP e plist sono usati. |
| Fixture | Gli SHA-256 in `Tests/Fixtures/README.md` corrispondono ai due `.torrent`. |
| Localizzazioni | 348 chiavi EN/IT, 0 orfane. |
| Documentazione | `docs/screenshot.jpg` è l'immagine di testa dei README; `queue-and-limits.md`, ADR e threat model sono attuali. |

## Unico orfano trovato

**`Typography.captionSemiboldText`** — `Sources/VertexKit/Design/Typography.swift:43`.
Zero riferimenti in `Sources/` e `Tests/`. Impatto: nullo (un token in più).
Proposta: rimuovere la riga, un commit senza effetti sul comportamento.

## Osservazioni minori

1. `THIRD_PARTY_NOTICES.md` indica "OpenSSL 3.5.x" mentre `Scripts/deps.env`
   fissa `3.5.9`. Non è un errore, ma rendere la versione esatta rende il
   confronto con l'SBOM immediato.
2. `HANDOFF.txt` non è tracciato per scelta (`.gitignore`): è un documento di
   lavoro locale, non un artefatto del repository.
3. `dist/`, `.build/`, `.DS_Store`, `.vscode/` e `Resources/AppIcon.icns` sono
   artefatti ignorati o generati: non richiedono pulizia nel repository.
4. La normalizzazione dei percorsi non è duplicata: `Preferences.resolvedDownloadPath`
   chiama `vt_normalize_save_path`, quindi la regola vive solo nel bridge.

## Piano approvabile

1. Rimuovere `captionSemiboldText` (basso rischio, 1 riga).
2. Allineare la versione OpenSSL nel notice a `3.5.9` (opzionale, documentale).
3. Nessun altro intervento: non ci sono script, viste, chiavi o API morte.
