# Audit tecnico Vertex

Data: 2026-10-27
Commit analizzato: `df7f54a` (Release 1.3.8)
Stato: **nessuna modifica al codice applicata**. Questo documento è in attesa di approvazione.

## Metodo

Analisi statica di `Sources/`, `Tests/`, `Scripts/`, `Resources/` e `.github/`, più:

- `swift build -c debug` (riuscita, un solo warning nel codice dei test);
- `./build.sh test` (51/51 test superati, coverage generata in `dist/coverage/`);
- `./Scripts/check-localization.sh` (206 chiavi en/it allineate);
- verifica automatica che tutte le 206 chiavi siano referenziate nei sorgenti e che tutte le 96 chiamate `L()`/`LF()` abbiano una chiave;
- `shellcheck -S warning` su `build.sh` e `Scripts/*.sh` (nessun avviso);
- ricerca puntuale di simboli, campi JSON, parametri e include non usati.

Copertura attuale: 79,93% righe, 69,71% funzioni, 62,82% regioni.

## Sintesi

Il progetto è in buono stato: la suite passa, la build è pulita, le localizzazioni sono coerenti e non ci sono segreti o artefatti di build tracciati. I problemi residui sono soprattutto:

1. **una chiamata C++ sincrona sul MainActor a ogni poll** (scalabilità con molti torrent);
2. **tripla validazione della destinazione** (Swift, Swift engine, C++), con rischio di divergenza;
3. **payload JSON e campi modello mai letti** (`state`, `files`, `total_download`/`total_upload`);
4. **duplicazione nelle viste SwiftUI** (card, header/footer modali, pannelli di scelta cartella, drop);
5. **alcuni errori C++ non valorizzano `last_error`**, quindi la UI perde il motivo reale.

Nessuna di queste voci è un blocco di release. Le fasi A e B sono a basso rischio; la fase E richiede una decisione architetturale separata.

---

## Priorità 1 — Rischi funzionali e di scalabilità

### 1. Poll sincrono sul MainActor

`TorrentEngine.poll()` esegue in sequenza, sul MainActor:

- `vt_session_poll(session)` (drena alert libtorrent);
- `vt_snapshot_json(session)` (serializza tutti i torrent);
- `JSONDecoder.decode(VertexSnapshot.self, ...)`.

Riferimenti: `Sources/VertexKit/Engine/TorrentEngine.swift:763-830`.

Con molti torrent, una sessione libtorrent grande o un disco lento, il frame della UI può saltare. Lo stesso vale per:

- `loadDetail` → `vt_detail_json` sincrono (`TorrentEngine.swift:886-897`);
- `addMagnet`/`addTorrentFile` → parsing e I/O sincroni sul main (`TorrentEngine.swift:450-540`).

**Proposta:** introdurre una coda seriale dedicata alle chiamate `vt_*` (la stessa già usata per create/destroy), con pubblicazione dei risultati sul main. La coda è necessaria perché `vt_session` mantiene stato mutabile (`last_error`, stato portmap, `dht_nodes`) e oggi è protetto solo dal fatto che tutto gira sul main. Va fatto insieme a un test di carico leggero (es. 200 torrent finti) per misurare la latenza del poll.

**Rischio:** medio. **Impatto:** alto con molti torrent, nullo con pochi.

### 2. Tripla validazione della destinazione

Le stesse regole (file → cartella padre, `.torrent` → cartella padre, fallback, creazione directory, controllo scrivibilità) sono implementate in tre punti:

- `Preferences.resolvedDownloadPath` — `TorrentEngine.swift:52-80`;
- `TorrentEngine.preparedDestination` — `TorrentEngine.swift:905-930`;
- `prepared_save_path` nel bridge C++ — `Sources/CTorrent/vertex_torrent.cpp:105-150`;
- più `vt_set_default_save_path` — `vertex_torrent.cpp:1154-1191`.

Le semantiche non sono identiche: Swift espande `~`, il C++ no; Swift controlla `isWritableFile`, il C++ usa `access(W_OK)`; i casi symlink e percorsi relativi possono divergere. Oggi il C++ fa da rete di sicurezza, ma ogni modifica va replicata a mano.

**Proposta:** definire un contratto esplicito: Swift valida e normalizza sempre il percorso; il C++ mantiene solo il fallback di sicurezza (documentato e coperto da test). In alternativa, estrarre un unico helper C++ usato da `prepared_save_path` e `vt_set_default_save_path`. Aggiungere test per symlink, percorso relativo, file `.torrent` e directory non scrivibile.

**Rischio:** basso. **Impatto:** medio (evita regressioni future).

### 3. Errori C++ non propagati alla UI

- `vt_apply_settings_ex` restituisce `-1` senza valorizzare `session->last_error` (`vertex_torrent.cpp:1116-1151`). La UI mostra solo “Il motore BitTorrent ha rifiutato la configurazione”, perdendo il motivo.
- `vt_set_file_priority` ha un `catch (...)` che non imposta `last_error` (`vertex_torrent.cpp:1108-1113`) e non valida `file_index` né `priority`; il cast a `uint8_t` tronca valori fuori range.

**Proposta:** impostare `last_error` in tutti i rami di errore e validare `file_index >= 0` e `priority` nell'intervallo supportato da libtorrent (0...7). La UI continuerà a mostrare un messaggio localizzato, ma con il dettaglio corretto.

**Rischio:** basso. **Impatto:** medio sulla diagnosticabilità.

### 4. Statistiche tracker solo per info hash V1

`vt_detail_json` legge `tracker.endpoints.front().info_hashes[lt::protocol_version::V1]` (`vertex_torrent.cpp:826-842`). Per torrent V2-only o ibridi in cui l'endpoint non ha V1, `message`, `peers` e `seeds` restano a `-1`/vuoti.

**Proposta:** scegliere l'info hash disponibile (V1, altrimenti V2) o aggregare i valori; aggiungere un'asserzione sul fixture V2 già presente in `Tests/Fixtures`.

**Rischio:** basso. **Impatto:** medio per i torrent V2.

---

## Priorità 2 — Codice morto, obsoleto o ridondante

### 5. Campo JSON `state` e `state_string` mai usati

Il bridge emette `"state":"downloading"` (`vertex_torrent.cpp:363`) tramite `state_string` (`vertex_torrent.cpp:140-152`), ma `Torrent.CodingKeys` non decodifica `state`: usa `state_code` e `Torrent.phase` (`Models.swift:97-114`). Il campo è quindi payload morto e duplica una seconda mappatura stato → stringa.

**Proposta:** rimuovere `state_string` e il campo `"state"` dallo snapshot; aggiornare il JSON di test in `ModelsTests.swift:30`. `state_code` resta l'unica fonte.

### 6. `files` e `query_torrent_file` costosi e quasi inutili

`append_torrent_json` fa `status.torrent_file.lock()` (`vertex_torrent.cpp:337`) e il poll richiede `query_torrent_file` (`vertex_torrent.cpp:719-722`) solo per calcolare `size` e `files`. Il campo `Torrent.files` è usato **solo** da `DemoData` in DEBUG (`DebugSupport.swift:153`); `size` è disponibile anche da `status.total`.

**Proposta:** rimuovere `files` dal modello/JSON e il flag `query_torrent_file` (usare `status.total`). Questo elimina un lock per torrent a ogni poll (0,8 s) ed è l'ottimizzazione concreta più semplice. Se in futuro servirà il conteggio file, ricavarlo dal dettaglio già caricato.

### 7. Totali di sessione mai letti

`SessionStats.totalDownload` e `totalUpload` (`Models.swift:167-168`, `208-209`, `237-238`) vengono popolati da snapshot e demo (`TorrentEngine.swift:846-847`, `ViewRenderingSupport.swift:160-161`) ma nessuna vista li legge.

**Proposta:** o mostrarli (es. nella status bar o nella diagnostica) o rimuoverli dal modello e dal JSON. Preferibile rimuoverli finché non servono.

### 8. Parametri e proprietà non usati

- `HeaderBar.onAddFile` è dichiarato (`HeaderBar.swift:8`) e passato (`RootView.swift:268`) ma mai usato nel body.
- `BridgeSession.requestedPort` è assegnato (`IntegrationTestSupport.swift:185,198`) ma mai letto.
- `HeaderBar` ha `.onSubmit {}` vuoto (`HeaderBar.swift:69`).

**Proposta:** rimuovere i primi due e l'`onSubmit` vuoto, oppure implementare il comportamento previsto (Invio nella ricerca).

### 9. `#if DEBUG` ridondanti e ramo irraggiungibile

- `VertexApp.scheduleSnapshotIfNeeded` è già dentro `#if DEBUG` (`VertexApp.swift:90`) e contiene un secondo `#if DEBUG` con `#else NSApp.terminate(nil)` (`VertexApp.swift:128-132`): il ramo `#else` è irraggiungibile.
- `DebugSupport.swift` ha due blocchi `#if DEBUG` consecutivi (`DebugSupport.swift:1` e `:148`).

**Proposta:** rimuovere il `#if DEBUG` interno e il ramo `#else`; unire i due blocchi di `DebugSupport`.

### 10. Include non necessari o impliciti

- `<libtorrent/hex.hpp>` (`vertex_torrent.cpp:7`) non è usato: `to_hex` è implementato a mano.
- `std::snprintf` è usato in `json_escape` ma `<cstdio>` non è incluso esplicitamente.
- `lt::tcp::endpoint` è usato in `vt_add_peer` ma l'header del socket non è incluso esplicitamente.

**Proposta:** rimuovere `hex.hpp`, aggiungere `<cstdio>` e l'include esplicito del socket. È una pulizia di portabilità, non cambia il comportamento.

### 11. `StatusBarView` ignora `PrefDefault`

`StatusBarView` usa valori letterali per i default di `@AppStorage` (`StatusBarView.swift:13-15`), mentre `SettingsSheet` e `NetworkDiagnosticsView` usano `PrefDefault`. Se cambiano i default, la status bar resta indietro.

**Proposta:** usare `PrefDefault.dhtEnabled`, `PrefDefault.downloadLimitKB`, `PrefDefault.uploadLimitKB`.

### 12. Due fonti per la versione minima di macOS

`Resources/Info.plist:60-61` dichiara `LSMinimumSystemVersion`, `Scripts/app.env:13` dichiara `VERTEX_MIN_MACOS`. `build.sh:44` legge il plist, `make-dmg.sh:22` legge `app.env`. Oggi coincidono (15.0), ma una modifica a una sola delle due non viene bloccata.

**Proposta:** aggiungere in `build.sh` o in CI un confronto esplicito tra `PlistBuddy` e `VERTEX_MIN_MACOS`; oppure generare il valore del plist da `app.env`.

### 13. OpenSSL hardcoded per arm64

`Scripts/build-deps.sh:171` usa `./Configure darwin64-arm64-cc`, mentre l'architettura arriva da `VERTEX_ARCH` (`app.env:14`). Se un domani si cambia architettura, la build di OpenSSL non segue la configurazione.

**Proposta:** mappare `VERTEX_ARCH` al target OpenSSL (`darwin64-arm64-cc` / `darwin64-x86_64-cc`) o fallire esplicitamente se l'architettura non è supportata.

### 14. Artefatti locali residui

`default.profraw` nella root e `.DS_Store` sotto `Sources/` sono già ignorati da Git, ma restano nel workspace e possono confondere. Anche `Resources/AppIcon.icns` e `Resources/AppIcon.iconset/` sono generati e ignorati.

**Proposta:** rimuoverli localmente (nessuna modifica al repository).

---

## Priorità 2 — Duplicazione

### 15. Gestione drop duplicata

`RootView.handleRootDrop` (`RootView.swift:455-490`) e `AddTorrentSheet.handleDrop` (`AddTorrentSheet.swift:420-450`) ripetono:

- `hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)`;
- controllo `pathExtension == "torrent"`;
- `loadObject(ofClass: NSString.self)` e prefisso `magnet:`;
- dispatch sul main.

**Proposta:** estrarre un `TorrentDropHandler` (o funzioni libere) che restituisca un enum `DropItem` (`torrent(URL)`, `magnet(String)`) e lasci alle viste solo la decisione di cosa fare.

### 16. Configurazione `NSOpenPanel` ripetuta quattro volte

- `RootView.chooseTorrentFile` — `RootView.swift:429`;
- `AddTorrentSheet.chooseFile` — `AddTorrentSheet.swift:457`;
- `AddTorrentSheet.chooseDestination` — `AddTorrentSheet.swift:474`;
- `SettingsSheet.chooseFolder` — `SettingsSheet.swift:489`.

Tutte configurano `canChooseFiles`, `canChooseDirectories`, `allowsMultipleSelection`, `prompt`, `allowedContentTypes`.

**Proposta:** due factory (`makeTorrentOpenPanel`, `makeDirectoryOpenPanel`) in un file di supporto AppKit.

### 17. Chrome delle card ripetuto

Il pattern `RoundedRectangle(cornerRadius:style:).fill(palette.card)` + overlay con `palette.stroke` compare almeno dieci volte: `NetworkDiagnosticsView.swift:158-199,327-333`, `SettingsSheet.swift:240-246`, `InspectorView.swift:207-213`, `AddTorrentSheet.swift:341-347`, `EmptyStateView.swift:52-58`, ecc.

**Proposta:** un `ViewModifier` `.card(palette:radius:)` (e una variante `cardHover`) che centralizzi fill, stroke e `allowsHitTesting(false)`. Riduce il rischio di bordi/raggi incoerenti.

### 18. Divisori duplicati

`rowDivider` è definito in `SettingsSheet.swift:433` e `NetworkDiagnosticsView.swift:437`; `divider` in `StatusBarView.swift:115`. Sono tre varianti dello stesso `Rectangle().fill(palette.stroke)`.

**Proposta:** un componente `PaletteDivider` con parametri per altezza/larghezza e padding.

### 19. Header e footer modali duplicati

`SettingsSheet.header` (`:195`) e `NetworkDiagnosticsView.header` (`:53`) ripetono la tile gradiente + titolo/sottotitolo + `IconButton` di chiusura. I footer (`SettingsSheet:461`, `NetworkDiagnosticsView:412`) ripetono pannello, bordo superiore e pulsante di chiusura.

**Proposta:** `ModalHeader(icon:title:subtitle:onClose:)` e `ModalFooter(content:onClose:)`.

### 20. Mappatura comandi in quattro punti

Aggiungere un comando richiede di modificare:

1. l'enum `AppCommand` (`AppCommands.swift:24-36`);
2. l'array `AppCommand.notifications` (`:38-52`);
3. lo switch `AppCommand.notification` (`:53-67`);
4. lo switch `RootEventHandlerActions.handle` (`RootView.swift:508-530`).

L'array e lo switch sono due rappresentazioni della stessa informazione.

**Proposta:** una singola tabella statica `[(AppCommand, Notification.Name)]` da cui derivare `notifications` e `notification`, oppure un protocollo con `CaseIterable` per i casi senza payload. Il test `AppCommandsTests.notificationMapping` continuerà a coprire la mappatura.

### 21. `applyDemoSnapshot` duplica la costruzione dello stato

`TorrentEngine.applyDemoSnapshot` (`:839-878`) ripete la costruzione di `PollState`: dizionario per id, history, azzeramento detail, `hasLoadedSnapshot`. La stessa logica è in `poll` (`:805-831`).

**Proposta:** estrarre `apply(torrents:stats:downloadHistory:uploadHistory:)` usato da entrambi.

### 22. Doppia assegnazione in `select`

`TorrentEngine.select` assegna `detail = nil` (`:579`) e poi di nuovo nello `else` (`:583`).

**Proposta:** rimuovere il ramo `else` ridondante.

### 23. Fixture v1/v2 con gli stessi file

`IntegrationFixture.files` restituisce lo stesso array per `.v1` e `.v2` (`IntegrationTestSupport.swift:46-52`); anche `bytes(for:)` non dipende dal caso.

**Proposta:** un'unica implementazione condivisa, lasciando al caso solo `name`, `rootName` e `torrentURL`. In alternativa, rendere i due fixture realmente diversi (sarebbe più utile per i test V2).

### 24. Setup degli integration test ripetuto

Otto test in `TorrentIntegrationTests.swift` ripetono `IntegrationWorkspace` + `makeSeed` + `makeLeech` + `defer close` (`:46-374`).

**Proposta:** un helper `withSwarm(_ fixture:) { seed, leech in ... }` che gestisca workspace e chiusure. Riduce il rischio di dimenticare un `close()`.

### 25. Stub di `PortReachabilityTests` ripetuti

Otto test ripetono lo stesso switch su `api.ipify.org`, `/check-tcp`, `/check-result/<id>` (`PortReachabilityTests.swift:46-323`).

**Proposta:** una factory `makeTester(nodes:results:)` o una mappa `path → (status, data)`; i test dichiarano solo la risposta che vogliono simulare.

### 26. Boilerplate JSON nei test

`ModelsTests` ripete tre volte `guard let data = json.data(using: .utf8)` (`:44-48`, `:120-124`, `:144-148`); `CTorrentBridgeTests` ripete tre volte la decodifica dello snapshot (`:34-45`, `:76-80`, `:109-113`).

**Proposta:** helper `decodeSnapshot(_:)` e `decodeDetail(_:)` in `TestSupport`.

### 27. `EngineTests.waitUntil` duplica `TestsSupport.waitFor`

`EngineTests.waitUntil` (`:300-310`) implementa lo stesso ciclo con `RunLoop.main.run` già presente in `TestsSupport.waitFor` (`IntegrationTestSupport.swift:150-163`).

**Proposta:** usare un solo helper, eventualmente con un parametro per il run loop.

### 28. Verifica bundle tripla

`build.sh:139` chiama `verify-bundle.sh`; `make-dmg.sh:29` lo richiama prima della DMG e `:127` dopo il mount. È difesa intenzionale, ma nel percorso comune il bundle viene verificato tre volte.

**Proposta:** nessuna modifica necessaria; documentare che è intenzionale. Se si vuole ridurre il tempo, `make-dmg.sh --no-build` può saltare la prima verifica (già fatta da `build.sh`) e mantenere solo quella post-mount.

---

## Priorità 3 — Ottimizzazioni

### 29. `find_handle` interroga campi non necessari

`find_handle` chiama `handle.status(query_name | query_save_path)` per ogni torrent, ma usa solo l'info hash (`vertex_torrent.cpp:197-208`).

**Proposta:** usare `handle.info_hashes()` (libtorrent 2.x) o `handle.status()` senza flag. Evita l'estrazione di nome e save path per ogni comando e per ogni dettaglio.

### 30. `vt_magnet_uri` serializza il resume completo

`lt::make_magnet_uri(handle.get_resume_data())` (`vertex_torrent.cpp:900`) costruisce un blob di resume data solo per generare il magnet.

**Proposta:** usare l'overload `lt::make_magnet_uri(handle)` (disponibile in libtorrent 2.x) o costruire l'URI dagli info hash già presenti. Il comando è raro (copia manuale), quindi l'impatto è basso, ma elimina un'allocazione inutile.

### 31. `write_resume_impl` crea la directory a ogni salvataggio

`fs::create_directories(resume_dir)` viene chiamata a ogni resume (`vertex_torrent.cpp:308`), cioè ogni 20 s per torrent.

**Proposta:** creare la directory una volta in `vt_session_create_full` e ricrearla solo se il salvataggio fallisce con `ENOENT`.

### 32. `DotGrid` ridisegna centinaia di ellissi

`DotGrid` (`Theme.swift:112-135`) costruisce un `Path` con un ciclo annidato (circa 50×30 = 1500 ellissi) a ogni draw. Poiché `RootView` osserva `pollState`, il body viene rivalutato ogni 0,8 s e il Canvas può ridisegnare la griglia.

**Proposta:** memorizzare il `Path` per dimensione (o usare un'immagine tile ripetuta). È un guadagno CPU/GPU modesto ma costante.

### 33. Due passate su tutti i torrent a ogni render

`FilterBar.filterCounts()` (`HeaderBar.swift:130-145`) scorre tutti i torrent per ogni filtro; `RootView.filteredTorrents` (`RootView.swift:340-350`) filtra e ordina di nuovo.

**Proposta:** calcolare i conteggi nella stessa passata del filtro, oppure memoizzare `(torrents, filter, search, sort) → (visibili, conteggi)`. Con poche centinaia di torrent è trascurabile; con migliaia evita due ordinamenti.

### 34. Caricamento resume sincrono all'avvio

`vt_session_create_full` legge e decodifica tutti i `.resume` in modo sincrono (`vertex_torrent.cpp:440-490`). È già off-main nell'engine, ma ritarda `isReady` con molti torrent.

**Proposta:** valutare caricamento parallelo o lazy; prima però misurare con un test di carico. Non è urgente.

### 35. `Fmt.bytes` e formattazione per riga

`Fmt.bytes` usa `String(format:locale:)` e viene chiamato più volte per ogni riga (`downloaded`, `size`, `rate`). Con molte righe visibili è lavoro ripetuto.

**Proposta:** profilare prima di ottimizzare; se necessario, cache per valore o formattazione manuale. Non è un problema attuale.

### 36. Coda alert e frequenza di drain

La coda alert è impostata a 1000 (`vertex_torrent.cpp:427`) e viene drenata ogni 0,8 s. Un flood di alert (molti torrent, errori ripetuti) può superare la coda e perdere eventi.

**Proposta:** monitorare in un test di carico; eventualmente aumentare la coda o drenare più spesso. Non c'è evidenza attuale di overflow.

---

## Priorità 3 — Test, build e pulizia

### 37. Warning nei test

`AppCommandsTests.menuConstruction` usa `try MainActor.assumeIsolated` senza chiamate throwing (`AppCommandsTests.swift:193`), producendo un warning del compilatore.

**Proposta:** rimuovere `try` e la firma `throws` (o aggiungere un'asserzione throwing).

### 38. `rootName` e `name` derivabili

`IntegrationFixture.rootName` (`:28-36`) e `name` (`:39-43`) restituiscono stringhe correlate. Si può derivare `rootName` da `name` o viceversa.

**Proposta:** una sola proprietà base e una computed property.

### 39. Warning del linker

I warning su `/Library/Developer/CommandLineTools/Developer/...` e `/Library/Developer/CommandLineTools/Developer/usr/lib` dipendono dall'ambiente CLT locale, non dal repository. Non vanno “corretti” nel codice; spariscono con Xcode completo o con un ambiente CLT allineato.

### 40. Copertura non uniforme

Dati da `dist/coverage/coverage.txt`:

- totale: 79,93% righe;
- `AppAppearance.swift`: 0%;
- `DebugSupport.swift`: 1,82% (codice demo, accettabile);
- `AddTorrentSheet.swift`: 63,02%;
- `RootView.swift`: 63,12%;
- `TorrentEngine.swift`: 71,22%.

Non è un difetto, ma se si toccano le viste conviene aggiungere rendering headless per i percorsi scoperti (drop, scelta cartella, stato di errore nell'aggiunta).

---

## Cosa non cambierei

Queste scelte sono deliberate e vanno mantenute salvo decisione esplicita:

- **JSON costruito a mano nel bridge** (`ostringstream` + `json_escape`): evita dipendenze e mantiene il controllo sui campi. Non sostituire con una libreria senza necessità.
- **`try/catch` in ogni entry point C++**: il bridge non deve lanciare eccezioni verso Swift.
- **`UIState` + `@StateObject` invece di `@State`**: i Command Line Tools non includono il plugin delle macro SwiftUI.
- **Scena `Window` singola**: evita la seconda finestra all'apertura di magnet/.torrent.
- **Distruzione/creazione sessione fuori dal main**: è la correzione della 1.3.6, non regredire.
- **Doppia verifica del bundle**: è difesa intenzionale contro bundle non autosufficienti.
- **Firma ad-hoc**: non c'è un'identità Developer ID; non cambiare senza certificato e notarizzazione.
- **Dipendenze fissate ai sorgenti**: non tornare a Homebrew.
- **Chiavi di localizzazione in italiano**: è la strategia documentata (it = identità, en = traduzione); non invertirla.

---

## Piano di intervento proposto

Ogni fase è indipendente e può essere approvata separatamente. Dopo ogni fase: `./build.sh test`, `./build.sh`, `./Scripts/check-localization.sh`, e verifica che il warning di build non aumenti.

### Fase A — Pulizia sicura (nessun cambio di comportamento)

Voci: 5, 8, 9, 10, 11, 12, 14, 22, 37, 38.

- rimozione `state`/`state_string` e aggiornamento del JSON di test;
- rimozione `HeaderBar.onAddFile`, `BridgeSession.requestedPort`, `onSubmit` vuoto;
- semplificazione `#if DEBUG` e unione blocchi demo;
- include espliciti e rimozione `hex.hpp`;
- `StatusBarView` allineato a `PrefDefault`;
- check di coerenza `Info.plist` ↔ `app.env`;
- rimozione doppia assegnazione in `select`;
- fix warning nei test;
- derivazione `rootName`/`name`.

**Rischio:** molto basso. **Verifica:** suite 51/51, diff limitato a rimozioni.

### Fase B — Payload e poll

Voci: 6, 7, 29, 30, 31, 32, 33.

- rimozione `files` dal JSON/modello e di `query_torrent_file`;
- rimozione o utilizzo dei totali di sessione;
- `find_handle` senza query inutili;
- `vt_magnet_uri` senza resume data;
- directory resume creata una volta;
- `DotGrid` con Path memorizzato;
- conteggi filtro in una passata.

**Rischio:** basso. **Verifica:** test di decoding aggiornati, suite 51/51, confronto dimensione snapshot prima/dopo con un test di carico.

### Fase C — Correttezza e diagnostica

Voci: 3, 4, 13.

- `last_error` in `vt_apply_settings_ex` e `vt_set_file_priority`;
- validazione `file_index`/`priority`;
- tracker V2;
- OpenSSL target derivato da `VERTEX_ARCH`.

**Rischio:** basso/medio. **Verifica:** nuovi test su errori e su fixture V2; suite completa.

### Fase D — Duplicazione UI e test

Voci: 15-21, 23-27.

- `TorrentDropHandler`;
- factory `NSOpenPanel`;
- `Card` modifier, `PaletteDivider`, `ModalHeader`/`ModalFooter`;
- tabella unica comandi;
- `apply(...)` condiviso nell'engine;
- helper per fixture e stub dei test.

**Rischio:** basso/medio (rendering). **Verifica:** rendering headless già presente; suite 51/51; controllo visivo con demo/screenshot.

### Fase E — Architettura del poll (decisione separata)

Voce: 1 (ed eventualmente 34, 36).

- coda seriale per tutte le chiamate `vt_*`;
- pubblicazione sul main;
- test di carico con molti torrent;
- misurazione del frame time.

**Rischio:** medio/alto. **Verifica:** suite completa, test di stress, nessun crash su shutdown/restart PEX.

---

## Richiesta di approvazione

Opzioni:

- **A** — approva Fase A + B (pulizia e payload/poll, basso rischio);
- **B** — approva A + B + C (aggiunge correttezza e diagnostica);
- **C** — approva A + B + C + D (include il refactoring UI/test);
- **D** — approva tutto, inclusa la Fase E architetturale;
- **E** — nessuna modifica: usa il report come elenco da valutare.

Consiglio: partire da **A + B**, verificare il diff, poi decidere C e D separatamente. La Fase E va trattata come un lavoro a sé, con un test di carico prima e dopo.

---

## Stato di implementazione

Data: 2026-10-27. Approvate e applicate: **Fase A + Fase B**.

### Fase A completata

- rimosso `state`/`state_string` dal bridge e dal JSON di test;
- rimossi `HeaderBar.onAddFile`, `BridgeSession.requestedPort` e l'`onSubmit` vuoto;
- semplificati i blocchi `#if DEBUG` in `VertexApp` e `DebugSupport`;
- aggiunti gli include espliciti (`<cstdio>`, `<libtorrent/socket.hpp>`) e rimosso `<libtorrent/hex.hpp>`;
- `StatusBarView` usa `PrefDefault`;
- `build.sh` verifica che `Info.plist` e `Scripts/app.env` dichiarino la stessa versione minima di macOS;
- rimossa la doppia assegnazione in `TorrentEngine.select`;
- corretto il warning di `AppCommandsTests`;
- `IntegrationFixture.rootName` derivato da `name`;
- rimossi `default.profraw` e i `.DS_Store` locali.

### Fase B completata

- rimosso `files` dal modello/JSON e `query_torrent_file` dal poll;
- rimossi `total_download`/`total_upload` da bridge, modello e test;
- `find_handle` usa `handle.info_hashes()` senza interrogare nome e save path;
- `vt_magnet_uri` costruisce un `add_torrent_params` minimale invece di serializzare il resume data (l'overload `make_magnet_uri(handle)` è deprecato in libtorrent 2.1);
- la directory di resume viene creata una volta e ricreata solo se il salvataggio fallisce;
- `DotGrid` memorizza il `Path` per dimensione;
- `TorrentListPipeline.applyWithCounts` calcola torrent visibili e conteggi dei filtri in una sola passata; `FilterBar` riceve i conteggi già pronti.

### Verifica

- `swift build -c debug`: riuscita, nessun warning del codice (restano solo i warning del linker sull'ambiente CLT locale);
- `./build.sh test`: **51/51** test superati;
- `./build.sh`: release e bundle verificati (`macOS 15.0`, `arm64`);
- `./Scripts/check-localization.sh`: 206/206 chiavi allineate;
- `shellcheck -S warning build.sh Scripts/*.sh`: nessun avviso.

### Ancora aperte (alla 2026-10-27)

- **Fase C**: propagazione `last_error` in `vt_apply_settings_ex`/`vt_set_file_priority`, validazione priorità, tracker V2, OpenSSL target derivato da `VERTEX_ARCH`. La propagazione `last_error` e la validazione priorità sono state volutamente ripristinate per non uscire dall'approvazione A+B.
- **Fase D**: refactoring UI/test e rimozione delle duplicazioni.
- **Fase E**: coda seriale per il poll e test di carico.

---

## Aggiornamento 2026-10-28

Approvate e applicate anche RED-01, Fase C, Fase D, Fase E e la pulizia a basso rischio.
Il lavoro è stato pubblicato nella release **1.4.0** (build 17).

### RED-01 — filtri esclusivi

`TorrentFilter.matches` usa `Torrent.phase` come unica fonte: ogni torrent appartiene a
una sola categoria, la pausa prevale, un torrent in seed sta in "Seed" e non in
"Completati"; "Download" include metadati e verifica. La somma dei badge coincide con il
numero di torrent. Test aggiornati con un caso per ogni fase e verifica di partizione.

### Fase C — correttezza e diagnostica

- `vt_set_file_priority` valida `file_index` e `priority` (0...7) e valorizza `last_error`
  nel catch-all;
- `vt_apply_settings_ex` valorizza `last_error` con il messaggio dell'eccezione;
- `vt_detail_json` sceglie le statistiche tracker V2 quando V1 non ha dati o quando V2 ha
  scrape disponibili;
- `Scripts/build-deps.sh` deriva il target OpenSSL da `VERTEX_ARCH` e fallisce su
  architetture non supportate;
- aggiunte asserzioni sul dettaglio del fixture V2 e sulla priorità fuori range.

### Fase D — duplicazione

- `TorrentInput` centralizza il riconoscimento magnet/.torrent;
- `TorrentDropHandler` condivide il drag&drop tra finestra e sheet;
- `OpenPanelFactory` centralizza i quattro `NSOpenPanel`;
- `Preferences.startPaused`/`sequentialDefault` eliminano le letture dirette duplicate;
- `portmap_state` in C++ raggruppa stato, mapping ed errore TCP/UDP;
- `normalized_save_path` condivide la normalizzazione C++ tra add e resume;
- `ModalHeader`, `ModalFooterBar`, `Hairline` e `vertexCard` riducono il chrome duplicato;
- `SessionStats.effectivePort`, `AppInfo` e `Preferences.suggestedDownloadPath` eliminano
  altri duplicati;
- helper condiviso per gli stub HTTP dei test.

### Fase E — performance

`TorrentEngine` usa un'unica coda seriale per tutte le chiamate `vt_*`. Il poll esegue
`vt_session_poll`, serializzazione e decodifica fuori dal main actor; i risultati vengono
pubblicati sul main con un identificatore di poll e una generazione di sessione, così i
risultati obsoleti non sovrascrivono lo stato. Le operazioni sincrone (add, controlli,
impostazioni, dettaglio) sono serializzate sulla stessa coda. Aggiunti uno smoke test con
5.000 torrent sintetici sulla pipeline e 100 poll consecutivi nel test dell'engine.

### Pulizia a basso rischio

- rimosse le forward declaration inutilizzate in `vertex_torrent.cpp`;
- rimosso il parametro `palette` non usato da `RootView.content`;
- rimosse `NSHighResolutionCapable` e `NSSupportsAutomaticGraphicsSwitching` da `Info.plist`;
- `build-deps.sh` calcola una sola volta gli hash di lock e script;
- `NetworkDiagnosticsView` riusa `isTesting` invece di ripetere `if case .running`.

### Verifica

- `swift build -c debug`: riuscita, nessun warning del codice;
- `./build.sh test`: **51/51** test superati;
- `./build.sh`: release e bundle verificati (`macOS 15.0`, `arm64`);
- `./Scripts/check-localization.sh`: 206/206 chiavi allineate;
- `shellcheck -S warning build.sh Scripts/*.sh`: nessun avviso;
- screenshot demo di Impostazioni e Diagnostica catturati e controllati dopo il refactor
  del chrome.

### Ancora aperte

`DUP-07`, `DUP-08`, `DUP-10`, `RED-02`, `RED-03`, `RED-05`, `RED-06` (parte concorrente),
`RED-07`, `RED-10`, `OPT-01`, `OPT-02`, `OPT-04`, `OPT-05`, `OPT-06`, `OPT-07`; restano
anche typography/SegmentedPicker e un confronto screenshot completo su tutte le varianti.
