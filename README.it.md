# Vertex

[English](README.md) · **Italiano**

**Client BitTorrent nativo per macOS**, scritto in SwiftUI e basato su libtorrent 2.1.
Niente Electron, niente pubblicità, nessuna telemetria. Open source con licenza MIT.

[![Release](https://img.shields.io/github/v/release/cicciocanestro/vertex?display_name=tag&sort=semver)](https://github.com/cicciocanestro/vertex/releases/latest)
[![Licenza: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Piattaforma](https://img.shields.io/badge/platform-macOS%2015%2B%20arm64-lightgrey)](#requisiti)
[![CI](https://github.com/cicciocanestro/vertex/actions/workflows/ci.yml/badge.svg)](https://github.com/cicciocanestro/vertex/actions/workflows/ci.yml)

![Interfaccia di Vertex](docs/screenshot.jpg)

## Download

[**Scarica l'ultima DMG**](https://github.com/cicciocanestro/vertex/releases/latest)

1. Apri la DMG.
2. Trascina **Vertex** nella cartella **Applicazioni**.
3. Al primo avvio macOS potrebbe chiedere una conferma (vedi sotto).

### Firma e notarizzazione

La release attuale è **firmata ad-hoc e non notarizzata**. Su un altro Mac Gatekeeper può
bloccare il primo avvio:

- fai clic destro su **Vertex** nel Finder e scegli **Apri**, oppure
- vai in **Impostazioni di Sistema → Privacy e Sicurezza** e scegli **Apri comunque**.

La firma Developer ID, l'hardened runtime e la notarizzazione Apple sono il prossimo passo
per la distribuzione. Fino ad allora, aspettati questa conferma una tantum.

### Requisiti

- **macOS 15.0 (Sequoia)** o successivo.
- **Apple Silicon (arm64)**. La build attuale non è universale; Intel non è ancora
  supportato.

Verifica il download con il checksum pubblicato:

```bash
shasum -a 256 -c Vertex-*.dmg.sha256
```

## Caratteristiche

- Interfaccia nativa **SwiftUI** con tema chiaro, scuro e di sistema.
- Motore **libtorrent 2.1**: DHT, PEX, LSD, UPnP/NAT-PMP, tracker HTTP/UDP, magnet link,
  torrent v1 e v2.
- Aggiunta da magnet, file `.torrent`, trascinamento, appunti, Finder o browser.
- Ricerca, filtri, ordinamento e pannello dettagli con statistiche, file/priorità e tracker.
- Pausa/ripresa, download sequenziale, resume data ed errori visibili.
- Limiti globali di velocità, porta, DHT, PEX, LSD e UPnP/NAT-PMP.
- **Diagnostica rete**: porta effettiva, IP locale, stato dei mapping e raggiungibilità TCP.
- Interfaccia in italiano o inglese in base alla lingua di sistema.
- **Nessuna telemetria**. Le uniche connessioni sono quelle BitTorrent e, solo quando avvii
  il test porta, api.ipify.org e check-host.net.
- Bundle autosufficiente: libtorrent e OpenSSL sono inclusi nell'app.

## Compilazione dai sorgenti

```bash
git clone https://github.com/cicciocanestro/vertex.git
cd vertex
./build.sh
open dist/Vertex.app
```

Per compilare servono Xcode Command Line Tools con Swift 5.10+ (testato con Swift 6.4) e
CMake 3.20+. La prima build compila le dipendenze fissate in `Scripts/deps.env`; le build
successive riusano `.build/vertex-deps`. Non serve alcuna libreria Homebrew a runtime.

```bash
./build.sh          # build release
./build.sh debug    # build debug
./build.sh test     # suite di test automatica
```

## Utilizzo

### Aggiungere un torrent

- **Aggiungi** nell'intestazione, oppure `⌘N` / `⌘O`.
- Incolla un magnet o scegli/trascina un file `.torrent`; il trascinamento funziona anche
  sulla finestra principale.
- I magnet aperti dal browser o dal Finder vengono gestiti da Vertex.
- La destinazione viene validata: un percorso file usa la cartella che lo contiene; una
  cartella non scrivibile produce un errore e il torrent non viene aggiunto.
- Le opzioni della finestra di aggiunta (cartella, avvio in pausa, sequenziale) valgono solo
  per quel torrent.

### Gestione dei torrent

- Pausa/ripresa, rimozione con o senza cancellazione dei file, **Mostra nel Finder**, copia
  del magnet e download sequenziale.
- Selezionando un torrent si apre il pannello dettagli con statistiche, priorità dei file e
  tracker.
- In caso di errore, il messaggio reale è visibile nella riga; messaggio e percorso sono
  nel pannello dettagli.

### Diagnostica rete

- Si apre dalla porta nella barra di stato, da **Impostazioni → Rete → Diagnostica rete**
  oppure con `⌘⇧D`.
- Mostra porta effettiva, IP locale, stato UPnP/NAT-PMP e nodi DHT. Gli errori di mapping
  sono separati per TCP e UDP, con il trasporto che li ha prodotti.
- **Testa porta** verifica la raggiungibilità TCP tramite check-host.net; l'IP pubblico
  viene inviato solo quando avvii il test. Il traffico UDP/uTP non è verificato.
- Se la porta risulta chiusa, abilita UPnP/NAT-PMP o inoltra TCP/UDP verso l'IP locale;
  controlla anche di non essere dietro CGNAT.

### Impostazioni

- Cartella di download, limiti globali di velocità, porta di ascolto, DHT, PEX, LSD,
  UPnP/NAT-PMP.
- Avvio in pausa e sequenziale predefiniti per i nuovi torrent; le scelte nella finestra di
  aggiunta restano valide solo per quel torrent.
- Tema scuro, chiaro o di sistema.
- DHT e LSD si applicano subito. Cambiare PEX ricrea la sessione libtorrent in background e
  ripristina i torrent attivi dal resume data. Porta e limiti vengono validati e i valori
  non validi vengono segnalati.
- Per un uso domestico normale lascia attivi DHT, PEX, LSD e UPnP. Disattiva DHT/PEX/LSD per
  ridurre la scoperta dei peer e UPnP su router non fidati. BitTorrent non è anonimo.

### Scorciatoie

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

Pausa/Riprendi e Rimuovi agiscono sul torrent selezionato; senza selezione mostrano un
avviso.

### Dove salva i dati

- Download predefinito: `~/Downloads/Vertex`
- Stato e resume data: `~/Library/Application Support/Vertex/resume`
- Preferenze: `UserDefaults` (`app.vertex.torrent`)

Non è presente alcuna telemetria. L'app non è sandboxed e accede alle cartelle scelte e
alla cartella di download.

## Dettagli tecnici

### Riproducibilità e provenienza

- URL e SHA-256 di ogni dipendenza sono fissati in `Scripts/deps.env`.
- L'intera chiusura delle dipendenze viene copiata nell'app e verificata da
  `Scripts/verify-bundle.sh`.
- Il toolchain canonico è registrato in `Scripts/toolchain.env` e controllato dalla CI; i
  tag di release usano `Scripts/check-toolchain.sh --strict`.
- La DMG pubblicata è l'artefatto compilato e checksummato dalla CI. App e DMG locali non
  sono attese identiche bit-per-bit: Xcode/SDK, CMake, immagine del runner, percorso del
  checkout e timestamp HFS+/UDIF possono cambiare i byte.
- Usa il `.dmg.sha256` pubblicato per verificare l'artefatto canonico. Non confrontare
  l'hash di una DMG locale con l'asset CI.

### DMG e release

```bash
./Scripts/make-dmg.sh            # ricompila e crea la DMG
./Scripts/make-dmg.sh --no-build # usa dist/Vertex.app esistente
```

La DMG contiene l'app, il link ad **Applicazioni**, il file bilingue `Leggimi.txt` e
l'icona del volume. Produce:

- `Vertex-<versione>-macOS<minimo>-<architettura>.dmg`
- `Vertex-...dmg.sha256`

Lo script verifica firma, dipendenze, `minos` e architettura prima di creare la DMG e dopo
averla montata.

La pubblicazione è gestita dalla CI: i push su `main` producono un artefatto di build, solo
i tag `v*` creano una GitHub Release. Il tag deve corrispondere a `Info.plist`; gli asset
pubblicati non vengono sovrascritti. La DMG attuale è solo arm64; una release universale
richiede dipendenze per entrambe le architetture.

### Architettura

- `Sources/CTorrent` — bridge C++/C verso libtorrent: sessione, aggiunta torrent, snapshot
  JSON, dettagli file/tracker, resume data, priorità, validazione percorsi e comandi.
- `Sources/VertexKit` — libreria principale:
  - `Engine/TorrentEngine.swift` — polling serializzato del motore e stato pubblicato;
  - `Engine/PortReachabilityTester.swift` — test TCP esterno;
  - `Views/` — lista, righe, inspector, sheet di aggiunta, impostazioni, diagnostica, status bar;
  - `Utilities/` — validazione input, drag&drop, localizzazione, rete;
  - `Design/` — palette, componenti condivisi, chrome delle modali;
  - `Models/` — modelli snapshot, filtri, ordinamento, formattazione;
  - `DebugSupport.swift` — dati demo e cattura schermo, solo DEBUG.
- `Sources/Vertex` — entry point SwiftUI (`@main`, AppDelegate, gestione URL, finestra).
- `Tests/VertexTests` — suite automatica, inclusi test d'integrazione libtorrent su loopback.
- `Tests/Fixtures` — torrent deterministici v1/v2.
- `Scripts/` — build dipendenze fissate, verifica bundle, DMG, controllo localizzazioni,
  controllo toolchain e test runner.
- `Resources/` — `Info.plist`, localizzazioni e licenze di terze parti.
- `.github/workflows/ci.yml` — build/test su push e PR; release sui tag.

### Sviluppo e test

```bash
./Scripts/check-toolchain.sh --warn  # toolchain locale non canonico ammesso
./build.sh debug
./build.sh test
./Scripts/build-deps.sh --force      # ricompila le dipendenze fissate
```

`./build.sh test` produce `dist/test-results.xml` (JUnit) e `dist/coverage/` (testo e
LCOV). La CI carica entrambi. La suite copre formattatori, decodifica snapshot JSON,
modelli, preferenze, ciclo vitale del bridge C++, engine (aggiunta, dettaglio, priorità,
pausa/ripresa, riavvio PEX, shutdown), raggiungibilità rete con loader HTTP finto e routing
dei comandi. I test d'integrazione su loopback coprono trasferimenti v1/v2, ricaricamento
del resume, priorità file, rimozione e failure path senza tracker esterni. Le viste SwiftUI
e le varianti modali vengono renderizzate off-screen con `ImageRenderer`; lo smoke test
UPnP/NAT-PMP gira solo con `VERTEX_TEST_UPNP=1` in CI.

Le build DEBUG offrono dati demo e cattura finestra (`VERTEX_DEMO=1`,
`VERTEX_SNAPSHOT=/percorso/immagine.png`).

## Limitazioni

- macOS 15.0+ su Apple Silicon (arm64); per Intel serve una build universale con dipendenze
  per entrambe le architetture.
- Firma ad-hoc, non notarizzata: su un altro Mac aspettati la conferma di Gatekeeper.
- Interfaccia in italiano o inglese in base alla lingua di sistema; nessuna altra lingua.
- Client volutamente minimale: niente RSS, ricerca torrent integrata o scheduler.
- Non c'è un limite di rapporto: il seed continua finché non metti in pausa o rimuovi il
  torrent.
- Non è supportato lo spostamento dei dati di un torrent già aggiunto.
- La DMG è specifica per l'architettura del Mac di build (arm64 su Apple Silicon).

## Contribuire

Issue e pull request sono benvenute. Prima di aprire una PR esegui `./build.sh test` e
mantieni allineati README e tabelle di localizzazione italiano/inglese.

## Changelog

Le modifiche tra le versioni sono documentate in [`CHANGELOG.md`](CHANGELOG.md).

## Licenza

Vertex è distribuito con **licenza MIT**: vedi [`LICENSE`](LICENSE).

Le librerie incluse mantengono le proprie licenze:

- **libtorrent-rasterbar** — BSD 3-Clause
- **OpenSSL** — Apache License 2.0
- **Boost** (solo header in fase di compilazione) — Boost Software License 1.0

I testi completi sono in [`Resources/Licenses/`](Resources/Licenses) e
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Sono inclusi anche nel bundle e
raggiungibili da **Vertex → Licenze open source**.
