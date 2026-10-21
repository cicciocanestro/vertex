# Vertex

Client BitTorrent nativo per macOS, scritto in SwiftUI e basato su libtorrent.
Interfaccia essenziale, tema scuro/chiaro, dettagli animati e gestione completa di magnet e file `.torrent`.

## Funzionalità

- Motore **libtorrent 2.1**: DHT, PEX, LSD, UPnP/NAT-PMP, tracker HTTP/UDP, magnet link, torrent v1 e v2.
- Aggiunta da link magnet, file `.torrent`, trascinamento, appunti o doppio clic nel Finder.
- Download, seed, pausa/ripresa, verifica file e recupero metadati.
- Ricerca istantanea, filtri (tutti, download, seed, completati, in pausa) e ordinamento.
- Pannello dettagli con statistiche, elenco file con priorità e stato dei tracker.
- Limiti globali di velocità, porta di ascolto, DHT, UPnP/NAT-PMP.
- Tema scuro, chiaro o di sistema.
- Ripresa automatica della sessione al riavvio tramite resume data.
- Bundle autosufficiente: libtorrent e OpenSSL sono inclusi nell'app.

## Requisiti

- **macOS 27.0** — le librerie Homebrew di questo ambiente sono compilate con SDK 27.
  Per supportare versioni precedenti di macOS è necessario ricompilare libtorrent con un
  deployment target più basso.
- Xcode Command Line Tools con Swift 6.4.
- Homebrew e le dipendenze del motore:

```bash
brew install libtorrent-rasterbar boost openssl@4
```

Lo script rileva automaticamente il prefisso Homebrew (`brew --prefix`).
In assenza di Homebrew in `/opt/homebrew`, esporta `HOMEBREW_PREFIX` prima della build.

## Compilazione

```bash
./build.sh          # build release
./build.sh debug    # build debug
open dist/Vertex.app
```

Lo script:

1. compila il pacchetto Swift;
2. crea `dist/Vertex.app`;
3. genera l'icona se manca;
4. copia `libtorrent` e OpenSSL dentro `Contents/Frameworks`;
5. riscrive i percorsi delle dylib e applica una firma ad-hoc;
6. verifica che il bundle non dipenda più da Homebrew.

## Scorciatoie

| Azione | Scorciatoia |
| --- | --- |
| Aggiungi file `.torrent` | `⌘O` |
| Aggiungi link magnet | `⌘N` |
| Incolla magnet dagli appunti | `⌘⇧V` |
| Cerca | `⌘F` |
| Pausa / riprendi | `⌘P` |
| Rimuovi torrent | `⌘⌫` |
| Mostra nel Finder | `⌘⇧R` |
| Copia link magnet | `⌘⇧C` |
| Mostra / nascondi dettagli | `⌘I` |
| Filtri | `⌘1` … `⌘5` |
| Impostazioni | `⌘,` |

## Dove salva i dati

- Download predefinito: `~/Downloads/Vertex`
- Stato e resume data: `~/Library/Application Support/Vertex/resume`
- Preferenze: `UserDefaults` (`app.vertex.torrent`)

La cartella di download e i limiti si possono cambiare dalle impostazioni.

## Architettura

- `Sources/CTorrent` — bridge C++/C verso libtorrent: sessione, aggiunta torrent,
  snapshot JSON, dettagli file/tracker, resume data, priorità e comandi.
- `Sources/Vertex` — app SwiftUI:
  - `Engine/TorrentEngine.swift` — polling del motore e stato pubblicato;
  - `Views/` — lista, righe, pannello dettagli, modali, barra di stato;
  - `Design/` — palette adattiva, componenti, animazioni;
  - `Models/` e `Utilities/` — modelli e formattazione italiana.
- `Sources/Vertex/DebugSupport.swift` — dati demo e cattura schermo, solo build DEBUG.
- `Scripts/make-icon.swift` — genera l'icona `.icns` con CoreGraphics.
- `Resources/Info.plist` — bundle, associazione `.torrent`, versione minima.

## Note

- La firma è ad-hoc: se l'app viene spostata su un altro Mac potrebbe essere necessario
  scegliere “Apri comunque” dal menu contestuale del Finder. Per la distribuzione
  conviene firmare con Developer ID e notarizzare.
- Nessuna telemetria: le uniche connessioni di rete sono quelle del motore BitTorrent.
- libtorrent è distribuito con licenza BSD.
