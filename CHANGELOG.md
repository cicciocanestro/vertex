# Changelog

## [1.8.2] — 2026-11-07

### Diagnostica e UX
- **Health-check attivo del proxy SOCKS5**: aggiunto un controllo TCP asincrono e
  periodico verso il server/proxy configurato (ad es. Tor su `127.0.0.1:9050`).
  Se il proxy viene spento o non risponde, il badge `SOCKS5` nella barra di stato
  e la card in `NetworkDiagnosticsView` diventano immediatamente corallo/avviso
  con il messaggio di errore, tornando verdi appena il proxy riprende a funzionare.

## [1.8.1] — 2026-11-07

### Sicurezza e UX
- **Kill-Switch rigoroso con `anonymous_mode`**: quando il proxy SOCKS5 è attivo,
  libtorrent imposta `anonymous_mode = true`. Se il server SOCKS5 (o Tor) cade o
  è spento, qualsiasi connessione esistente o futura viene troncata all'istante
  senza fallback sulla connessione in chiaro (fail-closed totale).
- **Badge di warning e diagnostica proxy**: catturato `lt::socks5_alert` nel
  bridge C++; se il proxy è irraggiungibile o rifiuta le connessioni, il badge
  `SOCKS5` nella barra di stato diventa corallo (`Theme.coral`) con icona di
  avviso e tooltip esplicito. Anche la card in `NetworkDiagnosticsView` mostra lo
  stato d'errore di connessione.

## [1.8.0] — 2026-11-07

Release privacy & anonimato: supporto completo per proxy SOCKS5 (Tor, VPN proxy, tunnel SSH).

### Novità
- **Proxy SOCKS5**: nuova opzione nelle impostazioni di rete per instradare tutto il
  traffico torrent verso un proxy SOCKS5 (con supporto opzionale all'autenticazione RFC 1929).
- **Anti-Leak / Fail-Closed**: libtorrent instrada tutte le connessioni verso tracker, peer
  e risoluzione degli hostname attraverso il proxy configurato (`proxy_hostnames`,
  `proxy_tracker_connections`, `proxy_peer_connections`). UPnP e NAT-PMP vengono
  automaticamente disabilitati per prevenire leak dell'IP locale del router.
- **Diagnostica e StatusBar**: visualizzazione dello stato proxy in `NetworkDiagnosticsView`
  e indicatore SOCKS5 nella `StatusBarView`.

### Bridge C++
- Nuova API `vt_apply_proxy_settings` che configura a caldo il proxy libtorrent.
- Inclusione dello stato proxy (`enabled`, `type`, `hostname`, `port`) nello snapshot JSON.

### Test
- Test di configurazione SOCKS5 in `CTorrentBridgeTests`.
- Test d'integrazione live `SOCKS5 Proxy live: routing fail-closed con proxy non raggiungibile`
  in `TorrentIntegrationTests`. Suite automatica: 63/63 test superati.

## [1.7.0] — 2026-11-06

Release architetturale: modularizzazione completa di `TorrentEngine` e test di
regressione live sul binding di rete e kill-switch.

### Architettura e Manutenzione
- **Modularizzazione di `TorrentEngine`**: diviso il file monolitico in quattro
  file specializzati senza alterare la concorrenza né le garanzie di `sessionQueue`:
  - `Preferences.swift`: chiavi, default, validazione preferenze e configurazione di sessione;
  - `TorrentEngine.swift`: stato reattivo `@Published`, ciclo vitale della sessione e primitive di coda seriale;
  - `TorrentEngine+Polling.swift`: gestione del loop di polling, `PollState`, snapshot e caricamento dettagli;
  - `TorrentEngine+Actions.swift`: comandi utente, gestione file e preferenze applicate.

### Test
- **Test live sul binding WireGuard**: nuovo test d'integrazione che verifica a caldo
  il comportamento fail-closed (nessun leak di dati) alla caduta dell'interfaccia tunnel
  e la successiva ripresa deterministica del download al ripristino dell'indirizzo.
- **Test dinamico `bindAddress`**: verifica della commutazione a caldo dell'indirizzo di
  ascolto in `EngineTests` con gestione di `listenError` e ripristino automatico.
- Suite automatica: 61/61 test superati.

## [1.6.2] — 2026-11-05

### Correzioni
- **Formattazione porta e contatori**: rimosso il separatore delle migliaia da
  `IP:porta` nel pannello Diagnostica rete (`Text(verbatim:)` su
  `"\(publicIP):\(testPort)"`, che con localizzazione italiana mostrava es.
  `89.168.20.17:51.413` invece di `89.168.20.17:51413`) e dai badge numerici di
  conteggio.

## [1.6.1] — 2026-11-04

Release di reattività: chiusura dell'applicazione istantanea.

### Prestazioni
- **Chiusura finestra immediata**: `applicationShouldTerminate` nasconde subito
  le finestre (`orderOut`) all'invio di `Cmd-Q`, mentre il salvataggio del
  resume e l'arresto del motore proseguono in background.
- **Timeout tracker in uscita**: `stop_tracker_timeout` di libtorrent ridotto da
  5 s a 1 s per evitare che tracker lenti o irraggiungibili trattengano il
  processo alla chiusura.
- **Salvataggio resume in `vt_session_destroy`**: sostituito il polling fisso
  (`sleep_for(40ms)`) con `wait_for_alert` reattivo e saltata la rigenerazione
  dei resume già aggiornati su disco (`!need_save_resume_data()`).

## [1.6.0] — 2026-11-04

Release funzionale e di concorrenza: ordinamento invertibile nella barra filtri,
selezione rapida "Tutti / Nessuno" dei file nei dettagli e operazioni utente
completamente asincrone sulla coda di sessione.

### Novità
- **Ordinamento invertibile**: nella barra filtri un pulsante dedicato inverte
  l'ordine crescente/decrescente per tutti i criteri (Recenti, Nome, Dimensione,
  Progresso, Velocità); anche riselezionare la voce attiva nel menu inverte la
  direzione.
- **Selezione rapida file ("Tutti / Nessuno")**: nel pannello dettagli dei
  torrent multi-file compare una barra con il conteggio dei file selezionati e i
  pulsanti `Tutti` e `Nessuno`, supportati da una chiamata bulk atomica nel
  bridge C++ (`vt_set_all_file_priorities` / `prioritize_files`).

### Prestazioni e Concorrenza
- **Operazioni asincrone su `sessionQueue`**: `pause`, `resume`, `reannounce`,
  `toggleSequential`, `remove`, `setFilePriority`, `setAllFilePriorities`,
  `copyMagnet` e `applySettings` vengono accodate in modo asincrono su
  `sessionQueue` (`enqueueSessionOperation`) con lettura atomica di
  `vt_last_error`, evitando qualsiasi attesa sincrona sul `@MainActor` mentre un
  poll è in volo.

### Test
- Estesi `ModelsTests` (ordinamento invertito per tutti i criteri) ed
  `EngineTests` (priorità file bulk e comandi asincroni). Suite 60/60; 221 chiavi
  localizzate allineate (IT/EN).

## [1.5.9] — 2026-11-04

Release di rifinitura: decay della sparkline a zero dopo un trasferimento,
unificazione del validatore UTF-8 RFC 3629 e di `getifaddrs`, mappatura completa
degli errori di validazione del bridge e uniformità dei divisori UI.

### Correzioni
- **Sparkline in idle**: quando un trasferimento termina e le velocità scendono a
  `0 B/s`, la history continua ad aggiungere campioni nulli finché la curva non
  si appiattisce a zero prima di attivare lo skip dell'idle poll, evitando che il
  grafico nella barra di stato resti congelato sull'ultima onda.
- **Errori localizzati**: mappati in `TorrentEngine.localizedError(_:)` i messaggi
  di validazione del bridge C++ (`exceeds maximum size`, `not a regular file`,
  `cannot stat`, `Parametri non validi`, cartella di destinazione non valida o non
  scrivibile) sulle chiavi localizzate in italiano e inglese.

### Manutenzione
- **UTF-8 / Dettaglio C++**: unificata la macchina a stati RFC 3629 in
  `utf8_sequence_length`, condivisa tra `is_valid_utf8` e `json_escape`; in
  `vt_detail_json` il flag `metadata` viene ricavato direttamente da
  `handle.torrent_file()` senza una seconda chiamata a `handle.status()`.
- **Interfacce di rete**: `LocalNetwork.primaryIPv4Address()` riutilizza
  `ipv4Interfaces()` eliminando il secondo loop `getifaddrs`/`getnameinfo`.
- **Engine e UI**: `toast` reso `private(set)`, rimosso il `deinit` irraggiungibile
  in `TorrentEngine` e sostituiti gli ultimi divisori manuali da 1 px con
  `Hairline(palette:)` in `InspectorView` e `StatusBarView`.

### Test
- Nuovo test in `EngineTests` che verifica lo scorrimento a zero di
  `downloadHistory` dopo il termine del traffico e il successivo arresto delle
  pubblicazioni in idle. Suite 60/60.

## [1.5.8] — 2026-11-04

Release di affidabilità: completion di shutdown multiple, errori di creazione sessione
diagnostici, `request_id` codificato e DMG senza warning di deprecazione.

### Correzioni
- **Shutdown**: tutte le `completion` richieste durante lo shutdown vengono accodate e
  chiamate; una seconda richiesta non sovrascrive più la prima mentre è in corso un
  riavvio della sessione per PEX.
- **Creazione sessione**: `vt_session_create_full` espone un messaggio d'errore al
  chiamante; la creazione delle directory usa `std::error_code` e gli errori del file
  system (inclusi quelli di `FileManager`) arrivano al toast invece di essere ridotti a
  "motore non disponibile".
- **Diagnostica porta**: il `request_id` di check-host.net viene codificato come singolo
  segmento di path, quindi caratteri speciali non possono alterare l'URL.
- **Localizzazione**: il dialogo di rimozione del torrent e il testo della diagnostica
  di rete usano esplicitamente `L()`; le chiavi erano già presenti in entrambe le lingue.

### Test
- Nuovi test per completion concorrenti durante il riavvio PEX, errore di creazione
  sessione con percorso non valido e codifica del `request_id`. Suite 60/60.

### Strumenti
- **DMG senza warning**: `Scripts/make-dmg.sh` usa `diskutil image create/attach` e
  `diskutil eject` quando disponibili (macOS 26+), eliminando i warning di deprecazione
  di `hdiutil`; sulle runner macOS 15 resta il fallback a `hdiutil`.

## [1.5.7] — 2026-11-03

Release di robustezza: validazione UTF-8 rigorosa nel bridge, shutdown senza attese
inutili e caricamento del dettaglio fuori dal main actor.

### Correzioni
- **UTF-8 / JSON**: `json_escape` valida RFC 3629 e sostituisce byte o sequenze non
  conformi con `\ufffd`; esportate `vt_json_escape` e `vt_is_valid_utf8`.
- **Shutdown**: un `save_resume_data_failed_alert` con handle valido ma id non richiesto
  non decrementa più `pending`; evita di liberare lo slot di un altro torrent e di
  uscire prima del salvataggio. Gli handle invalidi restano perdonati per non bloccare
  i 3 secondi finali.
- **Dettaglio**: `loadDetail` usa `sessionQueue.async` e non blocca più il MainActor;
  `pollNowForTesting` mantiene il percorso sincrono deterministico.

### Test
- Nuovo test UTF-8 con ASCII, emoji, overlong 2/3/4 byte, surrogati, valori oltre
  U+10FFFF, continuation isolate e sequenze troncate.
- `EngineTests` attendono il dettaglio asincrono con `waitUntil`. Suite 58/58.

## [1.5.6] — 2026-11-03

Release di correzione: ripristina il sentinella dell'ETA sconosciuta, azzerato dal clamp
JSON introdotto nella 1.5.4. Nessuna modifica alle funzioni principali; la suite passa a
57 test.

### Correzioni
- **ETA sconosciuta**: `Torrent.init(from:)` non clampa più `eta` a zero. Il bridge emette
  `-1` quando l'ETA non è calcolabile (torrent in pausa, in recupero metadati, in verifica
  o senza velocità di payload); con il clamp a zero l'inspector mostrava "Completato" in
  "Tempo rimasto" per torrent non finiti. Il sentinella resta `-1` (valori inferiori
  vengono riportati a `-1`) e la UI torna a mostrare "—".

### Test
- Nuovo test "Snapshot JSON Decoding: ETA sconosciuta conserva -1": decodifica un torrent
  in pausa e uno senza metadati, verifica che `eta` resti `-1` e che `Fmt.eta` restituisca
  "—". Suite 57/57.

## [1.5.5] — 2026-11-03

### Correzioni
- **Errori asincroni**: `last_error` resta riservato alle operazioni sincrone;
  `add_torrent`/`torrent_error` usano `last_alert_error`, esposto dallo snapshot come
  `alert_error` e mostrato una volta dalla UI, senza sovrascrivere l'errore corrente.
- **Incolla magnet**: se gli appunti non contengono un magnet, si apre solo la finestra
  di aggiunta; niente toast ridondante.
- **Configurazione**: la validazione delle preferenze avviene una volta all'avvio;
  `currentConfiguration()` legge soltanto. Le impostazioni vengono applicate solo se
  cambiate e il percorso di salvataggio viene toccato solo quando cambia.
- **Percorsi**: Swift usa `vt_normalize_save_path`, la stessa normalizzazione C++ del
  motore (trim, `~`, file/`.torrent`, fallback).

### Prestazioni
- **Lista torrent**: la categoria esclusiva viene calcolata una volta per torrent;
  filtro e conteggi restano in una sola passata.
- **Dettaglio**: il progresso dei file usa la granularità pezzo di libtorrent
  (`piece_granularity`), più economica delle stime per blocco.
- **Poll in idle**: la pubblicazione è saltata quando `PollState` non cambia e il
  dettaglio si aggiorna ogni 15 poll invece di ogni 3; la history usa un helper unico.

### Manutenzione
- **Build**: `--show-bin-path` viene interrogato dopo l'unica compilazione, non come
  secondo build.
- **Bridge C++**: un'unica macro per il contratto catch/`last_error`.
- **Script**: `macho_dependencies` e `macho_rpaths` condivisi in `Scripts/lib/macho.sh`,
  usati da `build.sh`, `build-deps.sh` e `verify-bundle.sh`.
- **CI**: la chiave cache delle dipendenze include `Scripts/app.env` e
  `Scripts/lib/macho.sh`.
- **UI**: scala tipografica `Typography` e sostituzione di 89 font hardcoded ripetuti;
  screenshot demo di Impostazioni e Diagnostica verificati.

## [1.5.4] — 2026-11-02

### Sicurezza
- **Preferenze**: `validateAllPreferences()` controlla all'avvio porta, limiti di
  velocità, bind address, aspetto e percorso di download. Un plist corrotto o un
  bug di migrazione che lascia un valore fuori range viene ripristinato alla
  default prima che l'engine lo legga, evitando che una configurazione rotta
  avvii la sessione.
- **Decodifica JSON**: `Torrent.init(from:)` clampa `progress` in [0,1] e i
  contatori a valori non negativi prima che raggiungano la UI e la pipeline di
  ordinamento.
- **UTF-8**: `is_valid_utf8` valida le stringhe prima di `json_escape`, evitando
  JSON non decodificabile da Swift.
- **Test**: copertura della validazione delle preferenze all'avvio.

## [1.5.3] — 2026-11-02

### Sicurezza
- **Bind address**: `isValidIPv4` rifiuta ora `0.0.0.0`, loopback (`127.x`),
  link-local (`169.254.x`), forme corte (`192.168.1`) e leading zeros
  (`192.168.001.001`): solo indirizzi letterali e canonici vincolano l'engine.
- **Magnet**: `vt_add_magnet` rifiuta URI magnet superiori a 8 KiB prima di
  passarli a libtorrent.
- **File torrent**: `vt_add_torrent_file` canonicalizza il percorso, verifica
  che sia un file regolare e ne cappa la dimensione a 10 MiB prima del caricamento.

## [1.5.2] — 2026-11-02

### Sicurezza
- **vt_control**: la stringa `action` in arrivo dal layer Swift viene mappata a un
  `enum class ControlAction` (allowlist esplicita) e gestita tramite `switch`
  esaurivo. Ogni stringa non riconosciuta viene rifiutata come `unknown`. Rimossa
  la catena `if/else` vulnerabile a command injection.

## [1.5.1] — 2026-11-02

### Correzioni
- **Rete**: `LocalNetwork` applica la stessa regola di esclusione (loopback e
  link-local `169.254.x.x`) sia al menu di associazione sia alla diagnostica,
  così un indirizzo non usabile non può più filtrare in nessuna delle due liste.
- **Engine**: il contatore `lastAppliedPollID` viene azzerato quando la sessione
  viene ricreata (es. per il cambio di PEX), così la guardia dei poll obsoleti
  rimane significativa invece di contare sul fatto che il contatore sia monotono.
- **Bridge**: `find_handle` risolve un id SHA-1 in O(1) tramite `session::find_torrent`
  invece di scorrere tutti i torrent e allocare una stringa hex per ciascuno; i
  hash V2 (64 caratteri) scivolano nel percorso generale.
- **Bridge**: `removed_ids` mantiene un `unordered_set` accanto al deque, così i
  test di appartenenza e la rimozione sono O(1) invece di essere lineari.

### Duplicazione
- **UI**: `SegmentedPicker` è ora un componente generico in
  `Sources/VertexKit/Design/SegmentedPicker.swift`, riutilizzato dalle tre viste
  che lo avevano duplicato (InspectorView, SettingsSheet, AddTorrentSheet).
- **Preferenze**: `currentConfiguration()` scrive su `UserDefaults` solo quando la
  normalizzazione modifica effettivamente il valore, non a ogni chiamata.
- **Stato**: i codici libtorrent `1`/`2`/`7` sono sostituiti dall'enum
  `LibtorrentStateCode` in `Models.swift`, usato sia in `Torrent.phase` sia nel
  toast di completamento.

### Prestazioni
- **Poll in idle**: `PollState` è `Equatable` e il poll salta la pubblicazione
  quando il payload è identico a quello precedente; gli storici dei grafici
  si fermano in idle invece di appendere a ogni poll.
- **Impostazioni**: `vt_set_default_save_path` viene chiamato solo quando la
  cartella di download è cambiata, evitando un syscall `create_directories` +
  `access(W_OK)` a ogni debounce di un campo non correlato.

### Documentazione
- `HANDOFF.txt` §17 sincronizzato con lo stato reale del debito tecnico: 12 voci
  segnate come risolte o parzialmente risolte dai punti precedenti.

### Test
- 55 test, tutti superati.

## [1.5.0] — 2026-10-30

### Aggiunte
- **Associazione a un indirizzo locale**: la nuova impostazione «Interfaccia di rete» vincola
  il motore a un solo indirizzo IPv4, impostando sia `listen_interfaces` sia
  `outgoing_interfaces`. libtorrent rifiuta il traffico in arrivo sulle altre interfacce,
  quindi il client resta utilizzabile dietro CGNAT con un tunnel WireGuard e il port
  forwarding su un VPS.
- Diagnostica: mostra l'indirizzo associato e, quando l'ascolto fallisce (per esempio perché
  il tunnel è spento), riporta il messaggio di `listen_failed_alert`. Il client non ripiega
  sulle altre interfacce.
- Bridge: `vt_session_create_full` e `vt_apply_settings_ex` accettano `bind_address`; lo
  snapshot espone `bind_address` e `listen_error`.
- Barra di stato: l'icona della porta diventa uno scudo quando il client è associato a un
  indirizzo.

### Test
- 55 test, tutti superati: ascolto su un indirizzo locale, errore su un indirizzo non
  disponibile, rimozione dell'associazione a caldo, normalizzazione della preferenza e
  rendering della diagnostica associata.

## [1.4.0] — 2026-10-28

### Modifiche
- Filtri della lista esclusivi: ogni torrent ha una sola categoria, con "In pausa" che
  prevale; un torrent in seed non è più contato anche in "Completati".
- Diagnostica: `vt_set_file_priority` valida indice e priorità, `vt_apply_settings_ex` e il
  catch-all della priorità valorizzano `last_error`, le statistiche tracker usano anche V2.
- Duplicazione: input magnet/.torrent, drag&drop, pannelli di scelta, stato portmap,
  normalizzazione dei percorsi e chrome delle modali sono centralizzati.
- Performance: tutte le chiamate `vt_*` passano da una coda seriale; il poll non blocca più
  il main actor e i risultati obsoleti vengono ignorati.
- Pulizia: rimosse forward declaration, parametri e chiavi plist inutilizzati; hash di build
  calcolati una volta; helper condiviso per gli stub dei test.
- Test: smoke di carico con 5.000 torrent sintetici e 100 poll consecutivi.

## [1.3.9] — 2026-10-27

Release di manutenzione focalizzata sul payload dello snapshot e sul costo del
polling. Nessuna modifica alle funzioni principali; la suite automatica resta a
51 test.

### Manutenzione
- Snapshot più leggero: rimossi `state`, `files`, `total_download` e `total_upload`,
  campi mai letti dalla UI. Lo stato usa `state_code` e il conteggio dei file arriva
  dal dettaglio.
- Polling: rimossi `query_torrent_file` e il lock di `torrent_file` per torrent;
  `find_handle` usa direttamente gli info hash.
- Magnet: l'URI viene costruito da un `add_torrent_params` minimale, senza
  serializzare il resume data.
- Resume: la directory viene creata una volta e ricreata solo se il salvataggio
  fallisce.
- UI: `DotGrid` memorizza il percorso per dimensione; filtri e conteggi vengono
  calcolati in una sola passata.
- Pulizia: rimossi parametri e callback inutilizzati, rami `#if DEBUG` ridondanti
  e un warning nei test.
- Build: `build.sh` verifica che `Info.plist` e `Scripts/app.env` dichiarino la
  stessa versione minima di macOS.

## [1.3.8] — 2026-10-27

Release di manutenzione: nessuna modifica alle funzioni principali, ma meno
duplicazione nello stato dell'interfaccia, nel bridge C++ e negli script di
build. La suite automatica passa a 51 test.

### Manutenzione
- Preferenze con un'unica fonte (`PrefDefault`) condivisa da registrazione dei default,
  `@AppStorage` e tema.
- Stato dell'interfaccia unificato: selezione del torrent nell'engine, modali in un solo
  `ActiveModal`, snapshot del polling in un unico `PollState` e conteggi dei filtri in una
  passata.
- Applicazione delle impostazioni con debounce e flush immediato alla chiusura del pannello.
- Pipeline di filtro, ricerca e ordinamento spostata nei modelli e coperta dai test.
- Bridge C++: helper condivisi per aggiunta torrent, impostazioni di rete e reset del
  port mapping; rimossi `vt_session_create`, `vt_session_create_ex` e `vt_apply_settings`
  in favore di `vt_session_create_full` e `vt_apply_settings_ex`.
- Parametri dell'app centralizzati in `Scripts/app.env` e usati da build, DMG, verifica del
  bundle e CI. Nuovo controllo di parità delle localizzazioni in CI.
- Rimossi codice morto e API non più usate; README e fixture allineati.

### Test
- Nuova suite `EngineTests` con sessioni libtorrent isolate: aggiunta da magnet e file,
  selezione e dettaglio, priorità dei file, pausa/ripresa, comandi su torrent rimossi,
  riavvio della sessione per PEX e shutdown asincrono.
- Test mirato per il dettaglio svuotato quando la lettura del torrent fallisce o arriva
  una risposta obsoleta.
- Nuova suite `PortReachabilityTests` con loader HTTP iniettato: porta aperta e chiusa,
  errori HTTP, servizio non valido, nodi assenti, timeout parziali, reset, IP vuoto,
  risposte non HTTP e payload malformati.
- Rendering headless delle viste SwiftUI critiche tramite `ImageRenderer`, ora esteso a
  `RootView`, barra superiore e filtri, stati vuoti, nessun risultato e overlay di drop.
- Nuova suite `AppCommandsTests`: verifica il mapping comando → notifica, il payload dei
  filtri, l'invio sul `NotificationCenter`, il routing delle notifiche di `RootView` e la
  costruzione dell'albero dei menu.
- Rendering headless delle varianti di `RootView` con impostazioni, diagnostica, sheet di
  aggiunta, conferma di rimozione, dettagli, overlay di drop, ricerca senza risultati e
  filtri. La diagnostica di rete viene renderizzata anche negli stati UPnP/NAT-PMP
  mappato, parzialmente in errore, non mappato ed errore globale.
- Smoke test UPnP/NAT-PMP eseguito solo con `VERTEX_TEST_UPNP=1` (impostato in CI): non
  richiede che il router mappi davvero e verifica solo la coerenza dello snapshot. In
  locale il gate resta chiuso, quindi non vengono creati mapping sul router dell'utente.
- Gli hook e le suite sono disponibili solo in DEBUG: il comportamento delle build di
  release resta invariato.

## [1.3.7] — 2026-10-27

Piccola release di stabilizzazione dell'interfaccia e della diagnostica di rete.

### Corretto
- Il pannello dettagli non mantiene più i dati del torrent selezionato quando la lettura
  aggiornata fallisce: viene svuotato invece di mostrare informazioni obsolete.
- Gli errori di mappatura UPnP/NAT-PMP sono separati per TCP e UDP e indicano il trasporto
  che li ha prodotti. Un mapping riuscito non cancella più l'errore dell'altro protocollo.
- La cartella di download predefinita della sessione C++ viene aggiornata quando cambia
  nelle preferenze, così anche i torrent aggiunti senza percorso esplicito e il
  caricamento dei resume data usano la destinazione corrente.

### Test
- Aggiunta la decodifica degli errori di mappatura separati per TCP e UDP.
- Aggiunto un test del bridge per l'aggiornamento della cartella di salvataggio
  predefinita e per il suo uso nell'aggiunta di un magnet senza destinazione.

## [1.3.6] — 2026-10-27

Release di correzione per il ciclo di vita della sessione libtorrent e la validazione
delle impostazioni di rete.

### Corretto
- La distruzione della sessione (cambio PEX e chiusura dell'app) non avviene più sul
  main thread: il salvataggio del resume data non blocca più l'interfaccia per un massimo
  di 3 secondi.
- Il cambio PEX ricrea la sessione in background; se la nuova sessione non parte,
  Vertex ripristina la preferenza e la sessione precedente quando possibile.
- Porta e limiti di velocità vengono validati prima dell'applicazione. I valori non
  validi non vengono applicati e producono un messaggio di errore.
- Gli errori restituiti da `vt_apply_settings_ex` non vengono più ignorati.
- La diagnostica mostra DHT come disattivato quando il relativo toggle è spento.
- Aggiornato il messaggio di errore all'avvio: non fa più riferimento a un'installazione
  esterna di libtorrent, che è inclusa nel bundle.

### Test
- Aggiunta la validazione dei limiti KB/s e delle porte.
- Aggiunto un test d'integrazione per il ricaricamento del resume dopo un cambio PEX.

## [1.3.5] — 2026-10-26

Release dedicata al controllo delle funzioni di discovery e all'aggiornamento
dell'infrastruttura CI a Node.js 24.

### Corretto
- Separati i controlli DHT, Peer Exchange e Local Service Discovery.
- Il toggle PEX ora abilita o disabilita realmente l'estensione `ut_pex` ricreando la
  sessione libtorrent con resume data, invece di limitarsi a cambiare `enable_dht`.
- Aggiunto il toggle LSD, applicato a caldo tramite `enable_lsd`.

### CI
- Aggiornate le GitHub Actions a versioni con runtime Node.js 24
  (`checkout` 7.0.1, `cache` 6.1.0, `upload-artifact` 7.0.2,
  `download-artifact` 8.0.2), eliminando gli avvisi di deprecazione di Node.js 20.

## [1.3.4] — 2026-10-26

Release focalizzata su test d'integrazione, report coverage e toolchain di build
riproducibile a parità di ambiente CI.

### Documentazione
- Chiarita la portata della riproducibilità: sorgenti delle dipendenze fissati e build
  canonica prodotta dalla CI, senza la promessa di app o DMG identici bit-per-bit su
  macchine arbitrarie. Una DMG locale non è confrontabile con l'asset pubblicato.

### Test
- Aggiunti test d'integrazione deterministici su loopback con due sessioni libtorrent:
  trasferimenti v1/v2, pausa/ripresa, resume dopo riavvio, priorità file, rimozione con
  `delete_files`, torrent multipli e failure path.
- Aggiunte fixture torrent v1/v2 in `Tests/Fixtures`, senza tracker o rete esterna.
- `./build.sh test` produce ora un report JUnit (`dist/test-results.xml`) e coverage
  LLVM/LCOV (`dist/coverage/`); la CI carica entrambi gli artefatti.
- Il test pausa/ripresa verifica la transizione di stato senza dipendere dalla
  riconnessione del peer locale, evitando un timeout su runner CI più lenti.

### Build e CI
- Aggiunto `Scripts/toolchain.env` con Xcode, CMake, macOS e immagine runner canonici.
- Aggiunto `Scripts/check-toolchain.sh`: la CI usa la modalità `--strict` sui tag di
  release e segnala le differenze sulle build di sviluppo.
- La CI seleziona esplicitamente Xcode 16.4 e non installa più CMake senza versione
  fissata; le dipendenze in cache vengono invalidate quando cambia il toolchain.
- Le GitHub Actions sono fissate a SHA immutabili.

## [1.3.3] — 2026-10-25

### Aggiunto
- Dipendenze del motore fissate e compilate dai sorgenti: `Scripts/deps.env` fissa
  libtorrent 2.1.2, OpenSSL 3.5.9 e Boost 1.92.0 con checksum SHA-256.
- `Scripts/build-deps.sh` compila le dipendenze dai sorgenti con deployment target
  macOS 15.0 e le installa in `.build/vertex-deps`; non usa più le bottiglie Homebrew.
- `Scripts/verify-bundle.sh` verifica che il bundle sia autosufficiente: nessuna
  dipendenza Homebrew o percorso di build, presenza di ogni dylib inclusa, `minos`
  coerente con `Info.plist`, architettura uniforme e firma valida. Viene eseguito
  da `build.sh`, `make-dmg.sh` e dalla CI.
- Il test del bridge decodifica uno snapshot JSON reale con `VertexSnapshot`, oltre
  a verificare il ciclo di vita della sessione libtorrent.
- Workflow CI/CD guidato dai tag: i push su `main` producono un artefatto verificato,
  mentre solo i tag `v*` creano una GitHub Release. Gli asset pubblicati non vengono
  sovrascritti.

### Modificato
- Requisito minimo portato a **macOS 15.0** in `Package.swift`, `Info.plist`, README,
  CI e script di packaging.
- `build.sh` copia l'intera chiusura delle dylib del motore e riscrive i percorsi in
  modo generico, senza versioni hardcoded di OpenSSL.
- `make-dmg.sh` verifica il bundle sia prima di creare la DMG sia dopo averla montata.
- Runner CI aggiornato a `macos-15`, con cache delle dipendenze fissate.
- `THIRD_PARTY_NOTICES.md` e le licenze aggiornati a OpenSSL 3.5.x.

### Corretto
- Il DMG macOS 14 della 1.3.2 poteva dipendere da OpenSSL 3 di Homebrew, oppure
  contenere dylib compilate per macOS 27. La nuova verifica blocca entrambi i casi.

## [1.3.2] — 2026-10-25

### Aggiunto
- Suite di test automatica versionata (`VertexTestRunner`, eseguibile con `./build.sh test`)
  che copre formattatori, modelli, deserializzazione snapshot JSON, preferenze e ciclo vitale
  del bridge C++ `CTorrent`.
- Workflow di CI/CD con GitHub Actions su runner `macos-14` (Apple Silicon M1) che compila,
  esegue i test e valida l'integrità del bundle ad ogni commit e pull request.
- Architettura modulare con il target libreria `VertexKit` e visibilità `package` in SwiftPM.
- Comando `./build.sh test` per l'esecuzione rapida dei test locali.

### Modificato
- Deployment target minimo configurato su macOS 14.0 in `Package.swift`.
- Impostato esplicitamente `TORRENT_ABI_VERSION=2` per la compilazione del bridge C++.

## [1.3.1] — 2026-10-24

### Aggiunto
- La versione dell’app (versione e build) è visibile nell’intestazione, in Impostazioni →
  Informazioni e nel pannello Informazioni su Vertex.

### Corretto
- I nuovi torrent non partono più in pausa quando l’opzione “Avvia in pausa” è disattivata:
  `add_torrent_params::default_flags` di libtorrent include `paused`; ora il bridge lo
  azzera esplicitamente quando la pausa non è richiesta.

## [1.3.0] — 2026-10-23

### Aggiunto
- Interfaccia bilingue: italiano se il sistema è in italiano, inglese per qualsiasi altra
  lingua (con fallback sull’inglese). Sono localizzati testi della UI, messaggi del motore,
  errori, formati e nomi dei documenti tramite `Localizable.strings` e `InfoPlist.strings`.
- Documentazione: README in inglese (`README.md`, predefinito su GitHub) e in italiano
  (`README.it.md`), con link per cambiare lingua.

### Corretto
- Porte e conteggi non usano più il separatore delle migliaia; il campo numerico delle
  Impostazioni non mostra raggruppamenti.

## [1.2.3] — 2026-10-22

### Corretto
- Diagnostica rete: un errore di mapping su un trasporto non azzera più anche il mapping
  dell’altro. Gli indici UPnP e NAT-PMP ripartono entrambi da 0, quindi ora si confronta
  anche il trasporto oltre all’indice.
- Barra di avanzamento ed ETA non procedono più a scatti con pezzi grandi: lo snapshot
  richiede di nuovo `query_accurate_download_counters`.
- Aprire un link magnet o un file `.torrent` con l’app già attiva non crea più una seconda
  finestra: la scena principale è una `Window` singola invece di una `WindowGroup`.
- `⌘P` e `⌘⌫` non agiscono più sul primo torrent quando non c’è selezione, non agiscono
  dietro Impostazioni/Diagnostica/Aggiungi e mostrano un avviso se manca la selezione.
- `build.sh` non ignora più gli errori di `codesign`, firma le dylib e l’app senza `--deep`
  e verifica il bundle.
- Il test di raggiungibilità invia `Vertex/<versione>` come User-Agent, non più `Vertex/1.1`.

## [1.2.2] — 2026-10-22

### Corretto
- La sessione riprende i metadati dopo il riavvio: il resume data include ora l’info dict
  (`save_info_dict`). Prima i torrent aggiunti da file tornavano senza metadati (dimensione 0,
  nessun file) fino a un nuovo recupero; i torrent in pausa restavano senza metadati.
- I messaggi temporanei (toast) restano visibili sopra i pannelli Impostazioni e Diagnostica.
- Impostazioni (⌘,) si apre correttamente anche con il pannello Diagnostica aperto.

### Modificato
- Polling più leggero: lo stato dei torrent viene richiesto una sola volta per poll e solo
  per i campi usati, senza pieces/verified pieces né stime di copie distribuite.
- La lista dei torrent rimossi in attesa di alert tardivi è limitata (FIFO da 256 voci).
- `make-dmg.sh` smonta la DMG e rimuove lo staging anche in caso di errore.
- Drag & drop aggiornato a `loadObject(ofClass:)`: nessun warning di deprecazione su macOS 27.

## [1.2.1] — 2026-10-22

### Corretto
- Diagnostica rete: l’endpoint visualizzato e copiato usa la porta esterna mappata quando
  disponibile, non solo la porta locale.
- Mapping UPnP/NAT-PMP: un errore su un mapping non azzera più anche l’altro protocollo;
  il matching avviene tramite l’indice del mapping.
- Rilevamento IP locale più robusto: escluse interfacce virtuali/tunnel e link-local,
  intervallo RFC 1918 corretto.
- Completamento: i torrent in verifica non vengono più conteggiati come attivi per il
  toast, anche quando sono in pausa.

## [1.2] — 2026-10-22

### Aggiunto
- Pannello **Diagnostica rete** con porta effettiva, IP locale, stato UPnP/NAT-PMP e test TCP
  di raggiungibilità esterna tramite check-host.net.
- Accesso alla diagnostica dalla porta nella barra di stato, da Impostazioni → Rete e con `⌘⇧D`.
- Avviso CGNAT e istruzioni per port forwarding / UPnP nel pannello.
- Il bridge espone porta effettiva, stato di ascolto e mapping UPnP/NAT-PMP.

### Modificato
- L’impostazione UPnP/NAT-PMP salvata viene applicata all’avvio.
- README e note di release aggiornati con la diagnostica di rete.

## [1.1] — 2026-10-21

### Aggiunto
- Gestione dei link `magnet:` aperti dal browser o dal Finder, con registrazione dello schema.
- Apertura dell'app in primo piano quando arriva un link esterno.

### Corretto
- Gli alert di resume tardivi non ricreano più i file dei torrent rimossi, nemmeno durante la chiusura.
- Il pulsante Riprendi azzera lo stato di errore prima di riavviare un torrent.
- Messaggio più chiaro per i torrent già presenti.
- Il toast “Download completato” non viene più mostrato per torrent già completi al lancio.
- I limiti di velocità e la porta di ascolto vengono validati per evitare overflow e valori non validi.
- Il pannello dettagli non viene più ridisegnato inutilmente a ogni poll.

### Modificato
- Cartella di destinazione, avvio in pausa e download sequenziale nella finestra di aggiunta valgono solo per il torrent corrente; i default restano nelle Impostazioni.
- Aggiornamento del pannello dettagli ottimizzato.

## [1.0] — 2026-10-21

- Prima release pubblica di Vertex: client BitTorrent nativo per macOS con libtorrent 2.1,
  gestione magnet/file `.torrent`, ricerca, filtri, resume data, priorità dei file, tracker,
  limiti di velocità e tema chiaro/scuro/sistema.
