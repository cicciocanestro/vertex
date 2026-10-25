# Vertex

[English](README.md) · **Italiano**

**Client BitTorrent nativo per macOS**, scritto in SwiftUI e basato su libtorrent.
Interfaccia minimale con tema chiaro/scuro/sistema, pannello dettagli, ricerca, filtri
e gestione completa di magnet link e file `.torrent`.

![Interfaccia di Vertex](docs/screenshot.jpg)

## Caratteristiche

- Motore **libtorrent 2.1**: DHT, PEX, LSD, UPnP/NAT-PMP, tracker HTTP/UDP, magnet link,
  torrent v1 e v2.
- Interfaccia in **italiano o inglese**: italiano se il sistema è in italiano, inglese per
  qualsiasi altra lingua.
- Versione e build dell'app visibili nell'intestazione e in Impostazioni → Informazioni.
- Aggiunta da link magnet, file `.torrent`, trascinamento, appunti, doppio clic nel Finder
  o link magnet aperti dal browser (schema `magnet` registrato).
- Download, seed, pausa/ripresa, verifica dei file e recupero dei metadati.
- Ricerca istantanea, filtri (tutti, download, seed, completati, in pausa) e ordinamento.
- Pannello dettagli con statistiche, file con priorità e stato dei tracker.
- Limiti globali di velocità, porta di ascolto, DHT, UPnP/NAT-PMP.
- Pannello **Diagnostica rete**: porta effettiva, IP locale, stato UPnP/NAT-PMP e test TCP di
  raggiungibilità esterna.
- Tema scuro, chiaro o di sistema, applicato immediatamente.
- Ripresa automatica della sessione tramite resume data, con validazione dei percorsi.
- Errori visibili con messaggio e percorso nel pannello dettagli.
- Bundle autosufficiente: libtorrent e OpenSSL sono inclusi nell'app.

## Requisiti

- **macOS 15.0** (Sequoia) o successivo su Apple Silicon (arm64).
- **Xcode Command Line Tools** con Swift 6.x (testato con Swift 6.4). Non serve Xcode completo.
- **CMake 3.20+** per compilare le dipendenze del motore. Su macOS si installa con
  `brew install cmake`; non serve alcuna libreria Homebrew a runtime.

Le dipendenze (`libtorrent`, OpenSSL e gli header Boost) sono **versioni fissate**
in `Scripts/deps.env` e vengono compilate dai sorgenti con deployment target
macOS 15.0. Non vengono usate le bottiglie Homebrew: la build è quindi
riproducibile e il bundle finale non dipende da percorsi esterni.

Al primo `./build.sh` la compilazione delle dipendenze può richiedere alcuni minuti;
le build successive riutilizzano `.build/vertex-deps`.

Testato su Apple Silicon. La build è `arm64`; per una release universale servono
dipendenze compilate per entrambe le architetture e l'app non è stata testata su Intel.

## Installazione

Se è disponibile una release, scarica la DMG dalla sezione
[**Releases**](https://github.com/cicciocanestro/vertex/releases), aprila e trascina
**Vertex** nella cartella Applicazioni.

In alternativa, compila dai sorgenti:

```bash
git clone https://github.com/cicciocanestro/vertex.git
cd vertex
./build.sh
open dist/Vertex.app
```

`build.sh` compila le dipendenze fissate, genera l'icona se manca, copia le licenze
nel bundle, riscrive i percorsi delle dylib e verifica che l'app sia autosufficiente.

## Compilazione

```bash
./build.sh          # build release
./build.sh debug    # build debug
./build.sh test     # esecuzione suite di test automatica
open dist/Vertex.app
```

Lo script:

1. compila le dipendenze fissate in `Scripts/deps.env` (se non già presenti);
2. compila il pacchetto Swift;
3. crea `dist/Vertex.app`;
4. genera l'icona se manca;
5. copia `libtorrent`, OpenSSL e le licenze dentro il bundle;
6. riscrive i percorsi delle dylib e applica una firma ad-hoc;
7. verifica che il bundle non contenga dipendenze esterne e che il `minos` dei
   binari non superi quello dichiarato in `Info.plist`.

Se esegui `swift build` senza `build.sh`, compila prima le dipendenze e passa il
prefix:

```bash
./Scripts/build-deps.sh
export VERTEX_DEPS_PREFIX="$PWD/.build/vertex-deps"
swift build -c release
```

Per forzare la ricompilazione delle dipendenze:

```bash
./build.sh release --rebuild-deps
```

## Release DMG

```bash
./Scripts/make-dmg.sh            # ricompila e crea la DMG
./Scripts/make-dmg.sh --no-build # usa dist/Vertex.app esistente
```

Produce in `dist/`:

- `Vertex-<versione>-macOS<versione minima>-<architettura>.dmg`
- `Vertex-...dmg.sha256`

La DMG contiene `Vertex.app`, un collegamento ad **Applicazioni**, il file `Leggimi.txt`
e l'icona del volume. Le licenze sono incluse nell'app e raggiungibili dal menu
**Vertex → Licenze open source**. Lo script verifica firma, dipendenze, `minos` e
architettura sia prima di creare la DMG sia dopo averla montata, poi genera il
checksum SHA-256.

La build è `arm64` su Apple Silicon. Per una release universale servono dipendenze
compilate per entrambe le architetture; la build Intel non è testata.

La pubblicazione è gestita dalla CI: i push su `main` producono un artefatto di build,
mentre solo i tag `v*` creano una GitHub Release. Il tag deve corrispondere alla
versione in `Info.plist`; gli asset pubblicati non vengono sovrascritti.

La firma dell'app è **ad-hoc** perché l'ambiente di build non dispone di un certificato
Developer ID. La DMG è quindi distribuibile, ma su un altro Mac potrebbero comparire gli
avvisi Gatekeeper descritti nelle note. Per una distribuzione pubblica senza avvisi serve
firmare con Developer ID, abilitare l'hardened runtime e notarizzare l'app con
`notarytool` e `stapler` prima di creare la DMG.

## Utilizzo

### Aggiungere un torrent

- Pulsante **Aggiungi** nell'intestazione, oppure `⌘N` / `⌘O`.
- Nella finestra di aggiunta puoi incollare un link magnet o scegliere/trascinare un
  file `.torrent`; il trascinamento funziona anche sul resto della finestra.
- I link magnet aperti dal browser o dal Finder vengono gestiti dall'app come client
  BitTorrent.
- La cartella di destinazione viene validata: se viene indicato un file, viene usata la
  cartella che lo contiene; se non è scrivibile, l'app torna alla destinazione predefinita.
- Le opzioni della finestra di aggiunta (cartella, avvio in pausa, download sequenziale)
  valgono **solo per quel torrent**. I valori predefiniti si configurano nelle Impostazioni.

### Gestione dei torrent

- Pausa/ripresa, rimozione con o senza cancellazione dei file, “Mostra nel Finder”,
  copia del link magnet e download sequenziale.
- Selezionando un torrent si apre il pannello dettagli con statistiche, file (con priorità)
  e tracker.
- In caso di errore, il messaggio reale e il percorso coinvolto sono visibili nella riga
  e nel pannello dettagli.

### Diagnostica rete

- Si apre dal numero di porta nella barra di stato, da **Impostazioni → Rete → Diagnostica
  rete**, oppure con `⌘⇧D`.
- Mostra porta effettiva, IP locale, stato delle mappature UPnP/NAT-PMP e nodi DHT.
- **Testa porta** verifica la raggiungibilità TCP tramite check-host.net: l’IP pubblico
  viene inviato al servizio solo quando avvii il test. Il traffico UDP/uTP non è verificato.
- Se la porta risulta chiusa, abilita UPnP/NAT-PMP sul router o inoltra TCP e UDP verso
  l’IP locale; verifica anche di non essere dietro CGNAT.

### Impostazioni

- Cartella di download, limiti globali di download/upload, porta di ascolto,
  DHT, UPnP/NAT-PMP.
- Avvio in pausa e download sequenziale predefiniti per i nuovi torrent; le scelte fatte
  nella finestra di aggiunta valgono solo per il singolo torrent.
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
| Diagnostica rete | `⌘⇧D` |
| Filtri | `⌘1` … `⌘5` |
| Impostazioni | `⌘,` |

Pausa/Riprendi e Rimuovi agiscono sul torrent selezionato; senza selezione mostrano un avviso.

## Dove salva i dati

- Download predefinito: `~/Downloads/Vertex`
- Stato e resume data: `~/Library/Application Support/Vertex/resume`
- Preferenze: `UserDefaults` (`app.vertex.torrent`)

Non è presente alcuna telemetria. Le uniche connessioni di rete sono quelle del motore
BitTorrent e, solo quando avvii il test porta, quelle verso api.ipify.org e check-host.net.
L'app non è sandboxed e accede alle cartelle scelte e alla cartella di download.

## Architettura

- `Sources/CTorrent` — bridge C++/C verso libtorrent: sessione, aggiunta torrent,
  snapshot JSON, dettagli file/tracker, resume data, priorità, validazione dei percorsi
  e comandi.
- `Sources/VertexKit` — libreria interna con la logica dell'applicazione:
  - `Engine/TorrentEngine.swift` — polling del motore e stato pubblicato;
  - `Engine/PortReachabilityTester.swift` — test TCP esterno tramite check-host.net;
  - `Views/` — lista, righe, pannello dettagli, finestra di aggiunta, impostazioni,
    diagnostica rete, barra di stato;
  - `Utilities/NetworkInfo.swift` — rilevamento dell’IP locale;
  - `Utilities/Localization.swift` — helper `L`/`LF` per le stringhe dinamiche;
  - `Design/` — palette adattiva, componenti, animazioni;
  - `Models/` e `Utilities/` — modelli e formattazione;
  - `DebugSupport.swift` — dati demo e cattura schermo, solo build DEBUG.
- `Sources/Vertex` — punto di ingresso dell'app SwiftUI (`@main`, AppDelegate, apertura URL e finestra).
- `Tests/VertexTests` — suite di test automatica (`VertexTestRunner`).
- `.github/workflows/ci.yml` — workflow di CI/CD: build e test su push/PR, release solo su tag.
- `Scripts/deps.env` — versioni e checksum SHA-256 delle dipendenze del motore.
- `Scripts/build-deps.sh` — compila libtorrent, OpenSSL e gli header Boost con target macOS 15.
- `Scripts/verify-bundle.sh` — verifica autosufficienza, `minos`, architettura e firma del bundle.
- `Scripts/make-icon.swift` — genera l'icona `.icns` con CoreGraphics.
- `Scripts/make-dmg.sh` — crea la DMG distribuibile con checksum SHA-256.
- `Resources/Info.plist` — bundle, associazione `.torrent`, versione minima.
- `Resources/en.lproj`, `Resources/it.lproj` — stringhe UI e InfoPlist in inglese e italiano.
- `Resources/Licenses/` — testi delle licenze incluse nel bundle.

## Sviluppo

```bash
./build.sh debug
./build.sh test
./Scripts/build-deps.sh --force   # ricompila le dipendenze fissate
```

Una suite di test automatica (`VertexTestRunner`, eseguibile con `./build.sh test`) copre la formattazione, la decodifica dei JSON di snapshot, i filtri/ordinamenti dei modelli, le preferenze e il ciclo vitale del bridge C++. Il workflow di CI/CD viene eseguito automaticamente su GitHub Actions ad ogni push e pull request (`.github/workflows/ci.yml`); i tag `v*` pubblicano la release.

Nelle build DEBUG sono disponibili dati demo e la cattura automatica della finestra
(`VERTEX_DEMO=1`, `VERTEX_SNAPSHOT=/percorso/immagine.png`).

## Limitazioni

- macOS 15.0 o successivo su Apple Silicon (arm64); per Intel serve una build universale con dipendenze compilate per entrambe le architetture.
- Firma ad-hoc, non notarizzata: su un altro Mac potrebbe essere necessario scegliere
  “Apri comunque” dal menu contestuale del Finder. Per la distribuzione conviene firmare
  con Developer ID e notarizzare.
- Interfaccia in italiano o inglese in base alla lingua di sistema; non sono previste
  altre traduzioni.
- Client volutamente minimale: nessun RSS, ricerca torrent integrata, scheduler o limite
  automatico di rapporto.
- Il seed continua finché il torrent non viene messo in pausa.
- Non è presente lo spostamento dei dati di un torrent già aggiunto.
- La DMG generata è specifica per l'architettura del Mac di build (arm64 su Apple Silicon).

## Changelog

Le modifiche tra le versioni sono documentate in [`CHANGELOG.md`](CHANGELOG.md).

## Licenza

Vertex è distribuito con **licenza MIT**: vedi [`LICENSE`](LICENSE).

Le librerie incluse mantengono le proprie licenze:

- **libtorrent-rasterbar** — BSD 3-Clause
- **OpenSSL** — Apache License 2.0
- **Boost** (solo header in fase di compilazione) — Boost Software License 1.0

I testi completi sono in [`Resources/Licenses/`](Resources/Licenses) e in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Sono inclusi anche nel bundle e
raggiungibili da **Vertex → Licenze open source**.
