# Vertex

**Client BitTorrent nativo per macOS**, scritto in SwiftUI e basato su libtorrent.
Interfaccia minimale con tema chiaro/scuro/sistema, pannello dettagli, ricerca, filtri
e gestione completa di magnet link e file `.torrent`.

![Interfaccia di Vertex](docs/screenshot.jpg)

## Caratteristiche

- Motore **libtorrent 2.1**: DHT, PEX, LSD, UPnP/NAT-PMP, tracker HTTP/UDP, magnet link,
  torrent v1 e v2.
- Aggiunta da link magnet, file `.torrent`, trascinamento, appunti o doppio clic nel Finder.
- Download, seed, pausa/ripresa, verifica dei file e recupero dei metadati.
- Ricerca istantanea, filtri (tutti, download, seed, completati, in pausa) e ordinamento.
- Pannello dettagli con statistiche, file con priorità e stato dei tracker.
- Limiti globali di velocità, porta di ascolto, DHT, UPnP/NAT-PMP.
- Tema scuro, chiaro o di sistema, applicato immediatamente.
- Ripresa automatica della sessione tramite resume data, con validazione dei percorsi.
- Errori visibili con messaggio e percorso nel pannello dettagli.
- Bundle autosufficiente: libtorrent e OpenSSL sono inclusi nell'app.

## Requisiti

- **macOS 27.0** — le librerie Homebrew attualmente utilizzate sono compilate con SDK 27.
  Per supportare versioni precedenti di macOS è necessario ricompilare libtorrent con un
  deployment target più basso.
- **Xcode Command Line Tools** con Swift 6.x (testato con Swift 6.4). Non serve Xcode completo.
- **Homebrew** e le dipendenze del motore:

```bash
brew install libtorrent-rasterbar boost openssl@4
```

Testato su Apple Silicon. Su Intel lo script rileva il prefisso Homebrew con
`brew --prefix`; l'app non è stata testata su Intel.

## Installazione

```bash
git clone https://github.com/cicciocanestro/vertex.git
cd vertex
brew install libtorrent-rasterbar boost openssl@4
./build.sh
open dist/Vertex.app
```

`build.sh` genera anche l'icona se manca, copia le licenze nel bundle e verifica che
l'app non dipenda più da Homebrew.

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
4. copia `libtorrent`, OpenSSL e le licenze dentro il bundle;
5. riscrive i percorsi delle dylib e applica una firma ad-hoc;
6. verifica che il bundle non dipenda più da Homebrew.

Se esegui `swift build` senza `build.sh` e Homebrew non è in `/opt/homebrew`, esporta
prima `HOMEBREW_PREFIX`:

```bash
export HOMEBREW_PREFIX="$(brew --prefix)"
swift build -c release
```

## Utilizzo

### Aggiungere un torrent

- Pulsante **Aggiungi** nell'intestazione, oppure `⌘N` / `⌘O`.
- Nella finestra di aggiunta puoi incollare un link magnet o scegliere/trascinare un
  file `.torrent`; il trascinamento funziona anche sul resto della finestra.
- La cartella di destinazione viene validata: se viene indicato un file, viene usata la
  cartella che lo contiene; se non è scrivibile, l'app torna alla destinazione predefinita.
- Puoi scegliere se avviare subito il download o tenerlo in pausa, e se usare il download
  sequenziale.

### Gestione dei torrent

- Pausa/ripresa, rimozione con o senza cancellazione dei file, “Mostra nel Finder”,
  copia del link magnet e download sequenziale.
- Selezionando un torrent si apre il pannello dettagli con statistiche, file (con priorità)
  e tracker.
- In caso di errore, il messaggio reale e il percorso coinvolto sono visibili nella riga
  e nel pannello dettagli.

### Impostazioni

- Cartella di download, limiti globali di download/upload, porta di ascolto,
  DHT, UPnP/NAT-PMP.
- Avvio in pausa e download sequenziale predefiniti per i nuovi torrent.
- Tema scuro, chiaro o di sistema.
- La cartella di download vale per i nuovi torrent; i torrent già aggiunti mantengono
  il proprio percorso.

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

Non è presente alcuna telemetria: le uniche connessioni di rete sono quelle del motore
BitTorrent. L'app non è sandboxed e accede alle cartelle scelte e alla cartella di download.

## Architettura

- `Sources/CTorrent` — bridge C++/C verso libtorrent: sessione, aggiunta torrent,
  snapshot JSON, dettagli file/tracker, resume data, priorità, validazione dei percorsi
  e comandi.
- `Sources/Vertex` — app SwiftUI:
  - `Engine/TorrentEngine.swift` — polling del motore e stato pubblicato;
  - `Views/` — lista, righe, pannello dettagli, finestra di aggiunta, impostazioni,
    barra di stato;
  - `Design/` — palette adattiva, componenti, animazioni;
  - `Models/` e `Utilities/` — modelli e formattazione italiana.
- `Sources/Vertex/DebugSupport.swift` — dati demo e cattura schermo, solo build DEBUG.
- `Scripts/make-icon.swift` — genera l'icona `.icns` con CoreGraphics.
- `Resources/Info.plist` — bundle, associazione `.torrent`, versione minima.
- `Resources/Licenses/` — testi delle licenze incluse nel bundle.

## Sviluppo

```bash
./build.sh debug
```

Nelle build DEBUG sono disponibili dati demo e la cattura automatica della finestra
(`VERTEX_DEMO=1`, `VERTEX_SNAPSHOT=/percorso/immagine.png`). Non è inclusa una suite di
test automatica: il bridge C++ è stato verificato con un harness dedicato per aggiunta,
pausa, resume, priorità dei file e rimozione.

## Limitazioni

- macOS 27.0 con le librerie Homebrew attuali; per versioni precedenti va ricompilato
  libtorrent con un deployment target inferiore.
- Firma ad-hoc, non notarizzata: su un altro Mac potrebbe essere necessario scegliere
  “Apri comunque” dal menu contestuale del Finder. Per la distribuzione conviene firmare
  con Developer ID e notarizzare.
- Interfaccia solo in italiano.
- Client volutamente minimale: nessun RSS, ricerca torrent integrata, scheduler o limite
  automatico di rapporto.
- Il seed continua finché il torrent non viene messo in pausa.
- Non è presente lo spostamento dei dati di un torrent già aggiunto.

## Licenza

Vertex è distribuito con **licenza MIT**: vedi [`LICENSE`](LICENSE).

Le librerie incluse mantengono le proprie licenze:

- **libtorrent-rasterbar** — BSD 3-Clause
- **OpenSSL** — Apache License 2.0
- **Boost** (solo header in fase di compilazione) — Boost Software License 1.0

I testi completi sono in [`Resources/Licenses/`](Resources/Licenses) e in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Sono inclusi anche nel bundle e
raggiungibili da **Vertex → Licenze open source**.
