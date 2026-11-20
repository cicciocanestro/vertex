# Changelog

## [1.17.0] — 2026-11-20

### English
#### Features
- **The session has one owner**: a new `SessionController` actor owns the libtorrent pointer. Creation, polling, detail reads and commands all run through it, off the main thread; the old serial queue, pointer box and poll counters are gone. A stale result from a previous session can no longer be applied to the new one.
- **Adaptive polling**: 800 ms while data is moving or a download is unfinished, 1.6 s for an idle library, 2.5 s when the app is in the background.
- **Snapshot built from state updates**: libtorrent now reports only the torrents that changed (`post_torrent_updates` + `state_update_alert`) instead of querying every handle on every poll. Measured on this machine with 300 idle torrents: p50 1.0 ms, p95 1.2 ms for the whole poll + JSON encode (debug bridge). A benchmark test keeps the O(N) regression out.

#### Security & Reliability
- **Stable signing without a Developer account**: CI can import a self-signed certificate from secrets (`Scripts/make-signing-cert.sh` / `import-signing-cert.sh`), giving the bundle a stable identity so macOS stops treating every update as a different app. It does not remove the Gatekeeper warning: that still requires a Developer ID and notarization.
- **Optional file storage for the SOCKS5 password**: a `0600` file in Application Support next to the Keychain, opt-in from Settings, written and migrated on a serial queue. The UI states that the file is not encrypted.
- **Bridge hardening**: every public entry point takes a mutex, so any caller (app, CLI, tests) can share one session safely; asynchronous errors are queued (up to 8) instead of overwriting each other; resume data is capped at 10 MiB, `fsync`ed before the atomic rename, and a corrupt/oversize file is quarantined as `.bad` instead of silently discarded.
- **Fail-closed proxy left as is**: a missing host still fails the session, and changing the proxy closes the peers opened before the change.

#### Build, CI & Docs
- **Warnings are errors in CI** and the coverage floor is now 54.5% (54.6% on the CI toolchain, 55.4% locally). CI compiles with `-warnings-as-errors` on the canonical Swift 6.1 toolchain.
- **89 tests** (was 80): malformed magnet/oversize input, invalid detail ids, the 300-torrent snapshot benchmark with cache-freshness checks, the adaptive polling policy and drag-and-drop validation.
- **Documentation**: `docs/adr/0001-session-actor.md` records the ownership decision and `docs/threat-model.md` lists assets, adversaries, mitigations and what stays out of scope.
- **Structure**: `TorrentEngine+Actions` was split into actions and settings, both under 800 lines; structured `os.Logger` categories log session lifecycle and failures with dynamic values marked private.

#### Known limits
- No notarization: without an Apple Developer account the first launch still needs "Open Anyway"; the Homebrew Cask removes the quarantine.
- Country flags cover IPv4 only; IPv6 peers show the generic badge (the lookup is offline in both cases).

### Italiano
#### Novità e Funzionalità
- **La sessione ha un solo proprietario**: un nuovo actor `SessionController` possiede il puntatore libtorrent. Creazione, polling, lettura dettagli e comandi passano tutti da lì, fuori dal main thread; la vecchia coda seriale, la scatola del puntatore e i contatori dei poll non esistono più. Un risultato della sessione precedente non può più essere applicato a quella nuova.
- **Polling adattivo**: 800 ms quando i dati si muovono o un download è incompleto, 1,6 s per una libreria inattiva, 2,5 s con l'app in background.
- **Snapshot costruito dagli aggiornamenti di stato**: libtorrent segnala solo i torrent cambiati (`post_torrent_updates` + `state_update_alert`) invece di interrogare ogni handle a ogni poll. Misurato su questa macchina con 300 torrent inattivi: p50 1,0 ms, p95 1,2 ms per poll + codifica JSON (bridge debug). Un test benchmark impedisce il ritorno al percorso O(N).

#### Sicurezza e Affidabilità
- **Firma stabile senza account Developer**: la CI può importare un certificato self-signed dai secret (`Scripts/make-signing-cert.sh` / `import-signing-cert.sh`), dando al bundle un'identità stabile così macOS non tratta ogni aggiornamento come un'app diversa. Non rimuove l'avviso di Gatekeeper: per quello servono Developer ID e notarizzazione.
- **Storage su file opzionale per la password SOCKS5**: file `0600` in Application Support accanto al Portachiavi, attivabile dalle Impostazioni, scritto e migrato su una coda seriale. L'interfaccia dichiara che il file non è cifrato.
- **Bridge più solido**: ogni entry point pubblico prende un mutex, quindi qualsiasi chiamante (app, CLI, test) può condividere una sessione in sicurezza; gli errori asincroni finiscono in coda (fino a 8) invece di sovrascriversi; il resume data è limitato a 10 MiB, `fsync`ato prima della rinomina atomica e un file corrotto o troppo grande viene messo in quarantena `.bad` invece di essere scartato in silenzio.
- **Proxy fail-closed invariato**: un host mancante fa fallire la sessione e cambiare proxy chiude i peer aperti prima della modifica.

#### Build, CI e Documentazione
- **I warning sono errori in CI** e la soglia di copertura è ora 54,5% (54,6% sulla toolchain CI, 55,4% in locale). La CI compila con `-warnings-as-errors` sulla toolchain canonica Swift 6.1.
- **89 test** (erano 80): magnet malformati e input enormi, id di dettaglio inesistenti, benchmark dello snapshot con 300 torrent e verifica della freschezza della cache, politica di polling adattivo e validazione del drag&drop.
- **Documentazione**: `docs/adr/0001-session-actor.md` registra la decisione di ownership e `docs/threat-model.md` elenca beni, avversari, mitigazioni e ciò che resta fuori perimetro.
- **Struttura**: `TorrentEngine+Actions` è stato diviso in azioni e impostazioni, entrambi sotto le 800 righe; categorie `os.Logger` strutturate registrano ciclo di vita e fallimenti con i valori dinamici marcati privati.

#### Limiti noti
- Nessuna notarizzazione: senza account Apple Developer il primo avvio richiede ancora "Apri comunque"; la Cask di Homebrew rimuove la quarantena.
- Le bandiere coprono solo IPv4; i peer IPv6 mostrano il badge generico (la lookup è offline in entrambi i casi).

## [1.16.0] — 2026-11-20

### English
#### Features
- **Offline country flags for peers**: the Inspector peer list now shows an ISO country flag for IPv4 peers and a local-network badge for LAN addresses. The table is generated from DB-IP Lite (CC BY 4.0) by `Scripts/build-geoip.sh` and bundled at build time, so no peer address ever leaves the machine. Adds ~656 KB to the bundle; attribution is in `THIRD_PARTY_NOTICES.md` and the in-app licenses.
- **Clearer Inspector**: the download folder is always visible (selectable path with a reveal button), and the four identical icon circles are replaced by a Pause/Resume control plus a "More actions" menu (Finder, Move files, Copy magnet, Remove).
- **Selected rows read at a glance**: a leading mint bar and a stronger fill, so the active row is visible in the light theme too.

#### Security & Reliability
- **SOCKS5 actually fails closed**: enabling or changing the proxy now closes the peer connections opened before the change; applying settings alone kept them running over the real address. A proxy request without a host fails explicitly instead of silently configuring clearnet, both at runtime and at session creation.
- **Keychain**: "no item" is now distinct from "read failed", so a transient failure no longer caches an empty password for the whole process. The engine retries off the main thread with backoff and re-applies the configuration; writes from the settings sheet no longer run on the main actor.
- **Engine lifecycle**: a PEX restart diffs against the configuration used to create the session (no port rebind or UPnP reset on every toggle), the fallback branch applies edits made during the restart, and a session that cannot be restored shows the retry view instead of an empty library. Add/move completions are always answered, commands and batch operations report when they cannot be queued or when individual torrents fail, and a storage move is confirmed only when the save path actually changes.

#### Build, Release & CI
- **Atomic builds**: the app is assembled in a staging bundle and swapped in only after verification, so a failed build no longer destroys the last good artifact; a failed dependency build restores the previous prefix instead of deleting it.
- **Release pipeline**: new lint job (`bash -n`, ShellCheck errors) and plist/strings validation; dependency cache disabled on tags; opt-in signed-release gate; notarization is mandatory when enabled; idempotent release uploads. `verify-bundle.sh` verifies every Mach-O individually, and `notarize.sh` derives the expected DMG, verifies the app inside the mounted image, uses a timeout, dumps notary logs on rejection, retries stapling and runs `spctl`.

#### Accessibility & UI
- Modals use minimum sizes with a scrollable settings rail, the window minimum is 900×640, Esc closes settings/diagnostics, and Return no longer closes the settings sheet while editing a field.
- VoiceOver: selected state announced for filter chips, segmented controls and the settings rail; torrent rows expose state, progress and pause/remove actions; error and success toasts are announced.
- Contrast and typography: readable muted text for the paused state, neutral pills, an accent bar on toasts with two-line details, and clearer row metrics.

#### Tests
- 80 tests (was 74), including the GeoIP table, proxy peer-drop/empty-host and add-during-shutdown. Flaky patterns removed: ephemeral ports, stable-window assertions instead of fixed sleeps, complete preference backup, escaped JSON fixtures. Coverage no longer fails a green suite, and a clean release build works again.

### Italiano
#### Novità e Funzionalità
- **Bandiere dei paesi offline per i peer**: la lista Peer dell'Inspector mostra la bandiera ISO per i peer IPv4 e un badge di rete locale per gli indirizzi LAN. La tabella è generata da DB-IP Lite (CC BY 4.0) con `Scripts/build-geoip.sh` e inclusa nel bundle in fase di build: nessun indirizzo dei peer lascia la macchina. Aggiunge ~656 KB al bundle; l'attribuzione è in `THIRD_PARTY_NOTICES.md` e nelle licenze dell'app.
- **Inspector più chiaro**: la cartella di download è sempre visibile (percorso selezionabile con pulsante di apertura) e i quattro cerchi-icona identici diventano un controllo Pausa/Riprendi più un menu "Altre azioni" (Finder, Sposta file, Copia magnet, Rimuovi).
- **Righe selezionate leggibili a colpo d'occhio**: barra laterale mint e riempimento più deciso, così la riga attiva si distingue anche in tema chiaro.

#### Sicurezza e Affidabilità
- **SOCKS5 davvero fail-closed**: attivare o cambiare il proxy ora chiude le connessioni peer aperte prima della modifica; applicare solo le impostazioni le lasciava attive sull'indirizzo reale. Una richiesta di proxy senza host fallisce esplicitamente invece di configurare il clearnet in silenzio, sia a runtime sia alla creazione della sessione.
- **Portachiavi**: "nessun elemento" è ora distinto da "lettura fallita", quindi un errore transitorio non memorizza più una password vuota per tutto il processo. L'engine ritenta fuori dal main con backoff e riapplica la configurazione; le scritture dal foglio impostazioni non girano più sul main actor.
- **Ciclo di vita del motore**: il riavvio PEX confronta con la configurazione usata per creare la sessione (niente rebind della porta né reset UPnP a ogni toggle), il ramo di fallback applica le modifiche fatte durante il riavvio e una sessione non ripristinabile mostra la vista di retry invece di una libreria vuota. Le completion di aggiunta/spostamento rispondono sempre, comandi e operazioni batch segnalano quando non possono essere accodati o quando singoli torrent falliscono, e lo spostamento è confermato solo quando il percorso di salvataggio cambia davvero.

#### Build, Rilascio e CI
- **Build atomiche**: l'app viene assemblata in un bundle di staging e sostituita solo dopo la verifica, quindi una build fallita non distrugge più l'ultimo artefatto valido; una build delle dipendenze fallita ripristina il prefix precedente invece di cancellarlo.
- **Pipeline di rilascio**: nuovo job di lint (`bash -n`, errori ShellCheck) e validazione di plist/strings; cache delle dipendenze disabilitata sui tag; gate opzionale per le release firmate; notarizzazione obbligatoria quando abilitata; upload di release idempotente. `verify-bundle.sh` verifica ogni Mach-O singolarmente e `notarize.sh` deriva la DMG attesa, verifica l'app dentro l'immagine montata, usa un timeout, scarica i log in caso di rifiuto, ritenta lo stapling ed esegue `spctl`.

#### Accessibilità e UI
- Le modali usano dimensioni minime con rail delle impostazioni scrollabile, il minimo della finestra è 900×640, Esc chiude impostazioni/diagnostica e Return non chiude più il foglio impostazioni mentre si modifica un campo.
- VoiceOver: stato selezionato annunciato per chip filtro, controlli segmentati e rail impostazioni; le righe torrent espongono stato, progresso e azioni pausa/rimuovi; i toast di errore e successo vengono annunciati.
- Contrasto e tipografia: testo attenuato leggibile per lo stato in pausa, pillole neutre, barra d'accento sui toast con dettaglio su due righe e metriche di riga più chiare.

#### Test
- 80 test (erano 74), inclusi tabella GeoIP, chiusura peer/assenza host nel proxy e aggiunta durante lo shutdown. Rimossi i pattern fragili: porte effimere, verifiche su finestra temporale al posto di sleep fissi, backup completo delle preferenze, fixture JSON con escaping. La coverage non fa più fallire una suite verde e la build release pulita funziona di nuovo.

## [1.15.0] — 2026-11-19

### English
#### Features
- **Multi-selection & batch actions**: select multiple torrents in the list with `⌘`-click (toggle), `⇧`-click / `⇧↑`/`⇧↓` (contiguous range), or `⌘A` (select all visible rows when the list has focus). Includes a contextual batch bar above the list, multi-row context menus, and batch `⌘P` (pause/resume) and `⌘⌫` (remove with confirmation).
- **Live Peers tab in Inspector**: new **Peers** tab alongside *Files* and *Trackers* showing connected peers' client software, selectable `IP:port`, completion percentage, discovery source (`DHT`, `PEX`, `LSD`, `Tracker`), BitTorrent state flags (`D`, `d`, `U`, `u`, `O`, `S`, `I`, `P`, `E` with localized tooltips), and live download/upload rates.
- **Optional macOS completion notifications**: new **Settings → Behavior → Completion notifications** toggle (`UNUserNotificationCenter`). Verifies the app bundle's code signature via `Security` (`SecStaticCode`), safely staying disabled on ad-hoc/CLI builds and activating automatically when signed with a Developer ID.

#### Security, Persistence & Fixes
- **Zero-window SOCKS5 startup configuration**: added `vt_session_create_configured`, applying SOCKS5 proxy settings and `anonymous_mode` directly inside the initial `lt::settings_pack` before `lt::session` starts and before `.resume` files are loaded, eliminating any startup clearnet window.
- **Race-free resume flush on quit**: `vt_session_destroy` now drains and writes any `save_resume_data_alert` already queued prior to shutdown (fixing the `need_save_resume_data()` race on rapid `⌘Q`), and `vt_control` triggers immediate resume persistence on pause/resume/dequeue/sequential changes.
- **Safe storage relocation**: `vt_move_storage` checks for existing target files beforehand and uses `fail_if_exist` instead of `always_replace_files`, preventing silent overwrites.
- **Dynamic User-Agent version**: `Vertex/<version>` is now passed dynamically from `AppInfo.version` at session startup.
- **Row layout & release script**: calibrated `TorrentRow` wide-metrics threshold on row width (`>= 780 pt`) and hardened `Scripts/update-homebrew-tap.sh` to always fetch the canonical GitHub Release `.sha256` when run locally.

### Italiano
#### Novità e Funzionalità
- **Selezione multipla e azioni di gruppo**: seleziona più torrent nella lista con `⌘`-clic (aggiungi/rimuovi), `⇧`-clic / `⇧↑`/`⇧↓` (intervallo contiguo) o `⌘A` (seleziona tutti i torrent visibili quando la lista ha il focus). Include barra contestuale rapida sopra la lista, menu contestuale multiplo e supporto batch per `⌘P` (pausa/riprendi) e `⌘⌫` (rimozione con conferma).
- **Tab *Peer* in tempo reale nell'Inspector**: nuovo terzo tab **Peer** accanto a *File* e *Tracker* con software client remoto, `IP:porta` copiabile, percentuale di completamento, sorgente (`DHT`, `PEX`, `LSD`, `Tracker`), flag di stato BitTorrent (`D`, `d`, `U`, `u`, `O`, `S`, `I`, `P`, `E` con tooltip localizzato) e velocità `↓`/`↑` in tempo reale.
- **Notifiche native macOS opzionali al completamento**: nuova preferenza **Impostazioni → Comportamento → Notifiche di completamento** (`UNUserNotificationCenter`). Verifica staticamente la firma del bundle tramite `Security` (`SecStaticCode`), restando disattivata in sicurezza sulle build ad-hoc/CLI e attivandosi automaticamente sui bundle firmati con Developer ID.

#### Sicurezza, Persistenza e Correzioni
- **Configurazione SOCKS5 fin dal primo istante d'avvio**: introdotta `vt_session_create_configured`, che applica proxy SOCKS5 e `anonymous_mode` direttamente nella `lt::settings_pack` iniziale prima dell'avvio di `lt::session` e del caricamento dei `.resume`, azzerando qualsiasi finestra di traffico in chiaro all'avvio.
- **Flush `.resume` senza race condition in chiusura**: `vt_session_destroy` drena e salva su disco anche i `save_resume_data_alert` già accodati prima dello shutdown (risolvendo la race su `need_save_resume_data()` in caso di `⌘Q` immediato), e `vt_control` avvia il salvataggio immediato su pausa/ripresa/coda/sequenziale.
- **Spostamento file sicuro**: `vt_move_storage` controlla preventivamente la presenza di file omonimi nella cartella di destinazione e usa `fail_if_exist` al posto di `always_replace_files`, evitando sovrascritture silenziose.
- **User-Agent dinamico**: la versione `Vertex/<version>` viene ora passata dinamicamente da `AppInfo.version` alla creazione della sessione.
- **Layout riga e script di rilascio**: ricalibrata la soglia delle colonne estese di `TorrentRow` sulla larghezza effettiva della riga (`>= 780 pt`) e messo in sicurezza `Scripts/update-homebrew-tap.sh` affinché in locale scarichi sempre il `.sha256` canonico dalla GitHub Release.

## [1.14.2] — 2026-11-18

### English
#### Localization, Accessibility & Fixes
- **Grammar & agreement**: fixed plural/singular concordances across the application when counts equal 1:
  - Active torrents in status bar (`Active: 1` / `1 attivo` instead of `1 attivi`).
  - DHT node counter (`DHT · 1 node` / `DHT · 1 nodo` instead of `1 nodes` / `1 nodi`).
  - Network reachability external node checks (`Port reachable (%ld of %ld external node)` / `Porta raggiungibile da 1 nodo esterno...`).
  - Multi-file inspector selection counter (`1 of %ld selected` / `1 di %ld selezionato`).
- **Runtime error translation**:
  - Introduced `RuntimeErrorLocalizer` mapping POSIX disk errors (space, permissions, I/O), libtorrent data verification failures, SOCKS5 proxy handshake alerts, and UPnP/NAT-PMP router errors to the active UI language.
  - Eliminated false positive duplicate errors in `localizedError` (filesystem errors are no longer flagged as duplicate torrents) and mapped `"Parametri non validi."` properly.
  - Intercepted raw libtorrent bdecode and metadata errors (`missing info-hash`, `missing info-dictionary`, `not a dictionary`, `bencoded`, etc.) into localized user-friendly messages.
- **Accessibility & VoiceOver**:
  - Added localized accessibility labels and tooltips to the search field clear button, toast dismissal button, and add sheet clear button.
  - Accessible labels for settings numeric/decimal inputs and toggles.
  - Unified accessibility element reading for the `"Completed · Paused"` state pill.
- **Table cleanup & Info.plist**:
  - Removed 11 dead/orphaned keys from `Localizable.strings`.
  - Added document type UTI mapping (`org.bittorrent.torrent`) in `InfoPlist.strings` and synchronized base values in `Info.plist`.
  - Upgraded `Scripts/check-localization.sh` to enforce format specifier parity, identity mapping, and absence of orphaned keys.
  - Fully bilingual `README.txt` (Licenses) and `THIRD_PARTY_NOTICES.md`.

### Italiano
#### Localizzazione, Accessibilità e Correzioni
- **Grammatica e concordanze**: corrette le concordanze singolare/plurale in tutta l'applicazione per valori unitari:
  - Torrent attivi nella barra di stato (`1 attivo` anziché `1 attivi`).
  - Contatore nodi DHT (`DHT · 1 nodo` anziché `DHT · 1 nodi`).
  - Diagnostica raggiungibilità porta (`Porta raggiungibile da 1 nodo esterno...` e `Nessun nodo esterno ha raggiunto la porta (1 verificato)...`).
  - Contatore selezione file nell'inspector (`1 di %ld selezionato` anziché `selezionati`).
- **Traduzione errori a runtime**:
  - Introdotto `RuntimeErrorLocalizer` che traduce gli errori POSIX su disco (spazio esaurito, permessi, I/O), fallimenti di verifica hash/pezzi corrotti, alert di handshake SOCKS5 ed errori UPnP/NAT-PMP nella lingua dell'interfaccia.
  - Eliminati i falsi positivi per torrent duplicato in `localizedError` (errori generici di filesystem non vengono più scambiati per torrent duplicati) e tradotti correttamente `"Parametri non validi."`.
  - Intercettati gli errori grezzi di bdecode e metadati di libtorrent (`missing info-hash`, `missing info-dictionary`, `not a dictionary`, `bencoded`, ecc.) traducendoli in messaggi comprensibili.
- **Accessibilità e VoiceOver**:
  - Aggiunte etichette VoiceOver e tooltip localizzati ai pulsanti di svuotamento ricerca, chiusura toast e svuotamento campo magnet.
  - Etichette accessibili per campi numerici/decimali e interruttori nelle Impostazioni.
  - Lettura unificata della pillola di stato `"Completato · In pausa"` per VoiceOver.
- **Pulizia tabelle e Info.plist**:
  - Rimosse 11 chiavi orfane da `Localizable.strings`.
  - Mappato l'UTI dei documenti (`org.bittorrent.torrent`) in `InfoPlist.strings` e sincronizzati i valori base in `Info.plist`.
  - Potenziato `Scripts/check-localization.sh` con verifica di corrispondenza specifier, identità chiavi italiane e rifiuto chiavi orfane.
  - Resi bilingui `README.txt` (Licenze) e `THIRD_PARTY_NOTICES.md`.

## [1.14.1] — 2026-11-15

### English
#### Localization & UI
- **Complete bilingual localization coverage**: audited and localized all missing UI strings throughout the application, ensuring 100% parity between Italian and English interfaces:
  - System menu bar (`AppCommands`): localized all menus (*Torrent*, *View*, *File*, *About*, *Settings*).
  - Modal headers (`ModalHeader`): dynamically localized titles and subtitles across Settings, Network Diagnostics, and Add Torrent sheets.
  - Initial and empty state views (`EmptyStateView`, `NoResultsView`, `DropOverlay`): localized all empty library prompts, search reset buttons, and drag-and-drop feedback.
  - Contextual menus and inspector (`TorrentRow`, `InspectorView`): localized reannounce, reveal, magnet copy, storage move, details header, and error status banners.
  - Settings sheet (`SettingsSheet`): localized active torrent limit suffix (`0 = all` / `0 = tutti`), folder selection prompt, and navigation buttons.
  - Accessibility labels: mapped formatted VoiceOver share ratio strings (`LF("rapporto %@", ...)`).
- **Fully bilingual changelog**: translated and formatted all 45 historical release entries in `CHANGELOG.md` with dedicated English and Italian sections.

### Italiano
#### Localizzazione e UI
- **Copertura integrale della localizzazione bilingue**: revisionate e localizzate tutte le stringhe dell'interfaccia utente, garantendo parità al 100% tra italiano e inglese:
  - Barra dei menu di sistema (`AppCommands`): localizzati tutti i menu (*Torrent*, *Vista*, *File*, *Informazioni*, *Impostazioni*).
  - Intestazioni delle modali (`ModalHeader`): titoli e sottotitoli tradotti dinamicamente nelle schermate Impostazioni, Diagnostica rete e Aggiungi torrent.
  - Viste di stato iniziale e vuoto (`EmptyStateView`, `NoResultsView`, `DropOverlay`): tradotti tutti i messaggi per libreria vuota, azzeramento filtri e overlay di rilascio drag-and-drop.
  - Menu contestuali e inspector (`TorrentRow`, `InspectorView`): localizzati i comandi annuncia ai tracker, mostra nel Finder, copia magnet, sposta file, intestazione dettagli e banner di errore.
  - Scheda Impostazioni (`SettingsSheet`): localizzato il suffisso per i torrent attivi (`0 = tutti` / `0 = all`), selezione cartella e pulsanti di navigazione.
  - Etichette di accessibilità: mappate le stringhe formattate per VoiceOver del rapporto di condivisione (`LF("rapporto %@", ...)`).
- **Changelog interamente bilingue**: tradotte e formattate tutte le 45 versioni storiche in `CHANGELOG.md` con sezioni dedicate in italiano e in inglese.

## [1.14.0] — 2026-11-13

### English
#### Features
- **Move storage while downloading or seeding (`move_storage`)**:
  - Added `vt_move_storage` command in the C++ bridge and native support for `storage_moved_alert`, with immediate resume data updates and persistence.
  - New **"Move Files…"** option accessible from the row context menu, the *Torrent* system menu, and the Inspector (dedicated button with `folder.badge.gearshape` icon).
  - The operation is asynchronous, non-blocking for the user interface, and displays a toast notification with a quick action to reveal the new folder in Finder.
- **Share ratio limit to stop seeding automatically**:
  - New preference under **Settings → Behavior → Stop seeding at ratio** (`0.0 = never`).
  - Automatically pauses completed torrents once the target share ratio is reached and notifies about seed completion.
  - Respects manual user intent: if a torrent past the threshold is explicitly resumed, it is not repeatedly re-paused in a loop.

#### Improvements & Tests
- Updated bilingual documentation (`README.md`, `README.it.md`) reflecting support for moving files and ratio limits.
- Extended the test suite with 2 new scenarios (71 tests total): preference validation test for ratio limit and end-to-end loopback transfer integration test with physical disk storage relocation and bit-for-bit file verification.

### Italiano
#### Novità e Funzionalità
- **Spostamento file su disco a download/seed iniziato (`move_storage`)**:
  - Aggiunto il comando `vt_move_storage` nel bridge C++ e il supporto nativo a `storage_moved_alert`, con aggiornamento e persistenza immediata del resume data.
  - Nuova opzione **"Sposta file…"** raggiungibile dal menu contestuale della riga, dal menu di sistema *Torrent* e dall'Inspector (pulsante dedicato con icona `folder.badge.gearshape`).
  - L'operazione è asincrona, non blocca l'interfaccia utente e mostra una notifica toast con azione rapida per aprire la nuova cartella nel Finder.
- **Limite di share ratio per fermare il seeding in automatico**:
  - Nuova preferenza **Impostazioni → Comportamento → Ferma seed al rapporto** (`0.0 = mai`).
  - Mette automaticamente in pausa i torrent completati una volta raggiunto il rapporto di condivisione target e notifica l'avvenuto completamento del seed.
  - Rispetta le azioni manuali dell'utente: se un torrent oltre la soglia viene ripreso esplicitamente, non viene rimesso in pausa a ciclo continuo.

#### Migliorie e Test
- Aggiornata la documentazione bilingue (`README.md`, `README.it.md`) riflettendo il supporto a spostamento file e limite di ratio.
- Estesa la suite di test con 2 nuovi scenari (71 test totali): test di validazione preferenze per il limite di ratio e test d'integrazione di trasferimento su loopback con spostamento effettivo dello storage su disco e verifica bit-per-bit dei file.

## [1.13.0] — 2026-11-11

### English
#### Features
- **Force start queued torrents**: introduced `force_start` command in the C++ bridge and engine.
  The row context menu now includes "Start Now (Ignore Queue)" and the Inspector features a
  dedicated primary "Start Now" button, allowing immediate downloads by bypassing queue limits
  without modifying global preferences.
- **Fully asynchronous directory I/O**: moved folder validation and creation (`preparedDestination`)
  entirely to the serial background `sessionQueue`, removing all synchronous disk and stat operations
  from the `MainActor` when adding `.torrent` files and magnet links to prevent UI freezes on SMB shares,
  NAS volumes, or slow external drives.

#### Fixes & Robustness
- **Immediate file priority persistence**: `vt_set_file_priority` and `vt_set_all_file_priorities` now trigger
  immediate resume data persistence (`save_info_dict`), ensuring exclusions ("Do Not Download") or high
  priorities survive premature app termination before periodic auto-saves.
- **SOCKS5 proxy probe throttling**: reduced TCP probe frequency to ~8 s when the proxy is healthy (keeping
  ~2.4 s during error states), eliminating rapid reconnect log spam on Tor daemons and local proxies.
- **Diagnostics and port test**: disabled external port testing when an active SOCKS5 proxy is configured
  (non-applicable and a source of confusion for anonymized traffic) with contextual explanations for split-tunneling setups.
- **C++ User-Agent & Fingerprint**: synchronized with the current application release version.
- **Test suite**: fixed defaults dictionary backup/restore in `PreferencesTests` and added integration coverage
  for `force_start`.

#### Appearance & Graphics
- **Progress details on paused/queued rows**: downloaded bytes and progress percentage are now always displayed
  for partial torrents even in wide window mode, preventing progress metrics from disappearing.
- **Consistent ratio on completed torrents**: the center column in wide windows displays the actual ratio (`×...`)
  instead of the clock/dash placeholder for all completed torrents.
- **Cleaner horizontal progress tracks**: `ProgressTrack` is no longer drawn for torrents at 0% progress or waiting for metadata.
- **Files Inspector**: added dedicated semantic icons by file type (video, audio, text, archives, images) and individual numeric percentage indicators.
- **Light theme contrast & depth**: raised search field with white background and subtle drop shadows on torrent cards.

### Italiano
#### Novità e Funzionalità
- **Avvio forzato dei torrent in coda**: introdotto il comando `force_start` nel bridge C++ e nell'engine.
  Nel menu contestuale della riga compare ora "Avvia ora (ignora coda)" e nell'Inspector il pulsante
  primario dedicato "Avvia ora", consentendo di avviare immediatamente un download scavalcando i limiti di coda
  senza dover modificare le preferenze globali.
- **I/O cartelle completamente asincrono**: spostata la validazione e creazione cartelle (`preparedDestination`)
  interamente sulla coda seriale di background `sessionQueue`, rimuovendo ogni operazione di disco e stat
  sincrona dal `MainActor` durante l'aggiunta di file `.torrent` e link magnet per prevenire qualsiasi freeze
  della UI su volumi SMB, NAS o dischi esterni lenti.

#### Correzioni e Robustezza
- **Persistenza immediata priorità file**: `vt_set_file_priority` e `vt_set_all_file_priorities` richiedono ora
  il salvataggio immediato del resume data (`save_info_dict`), garantendo che le esclusioni ("Non scaricare") o le
  priorità alte sopravvivano anche a una chiusura anticipata dell'app prima del salvataggio periodico.
- **Throttling sonda proxy SOCKS5**: ridotta la frequenza del probe TCP a ~8 s quando il proxy è sano (mantenendo
  ~2,4 s in stato di errore), eliminando il log di connessioni/disconnessioni rapide ripetute su demoni Tor e proxy locali.
- **Diagnostica e test porta**: disabilitato il test porta esterno in presenza di proxy SOCKS5 attivo (non applicabile
  e fonte di potenziale confusione per il traffico anonimizzato) con spiegazione contestuale per configurazioni split-tunneling.
- **User-Agent C++ e Fingerprint**: sincronizzati con la versione corrente dell'applicazione.
- **Test suite**: corretto il backup/restore del dizionario dei defaults in `PreferencesTests` e aggiunta copertura
  d'integrazione per `force_start`.

#### Aspetto e Grafica
- **Dettaglio progresso nelle righe in pausa/coda**: mostrati sempre i byte scaricati e la percentuale per torrent parziali
  anche in modalità finestra estesa (`wide`), evitando che il progresso scompaia dalla riga.
- **Rapporto coerente sui completati**: la colonna centrale nelle finestre estese mostra il rapporto effettivo (`×...`)
  invece del segnaposto orologio con trattino per tutti i torrent completati.
- **Pulizia visiva tracce orizzontali**: `ProgressTrack` non viene più disegnata per i torrent allo 0% o in attesa di metadati.
- **Inspector file**: aggiunte icone semantiche dedicate per tipo di file (video, audio, testo, archivi, immagini) e indicatore
  della percentuale numerica individuale.
- **Profondità e contrasto tema chiaro**: campo di ricerca con sfondo bianco rialzato e micro-ombre morbide sulle card dei torrent.

## [1.12.0] — 2026-11-11

### English
#### Accessibility & Typography
- **System Semantic Typography (Dynamic Type)**: migrated `Typography` from fixed-point
  values (8…13.5 pt) to system semantic text styles (`Font.system(.largeTitle/.title2/.title3/.headline/.body/.subheadline/.callout/.caption/.caption2)`
  with `.rounded` and `.monospaced` variants), removing all direct `.system(size:)` calls
  from views and enabling accessibility scaling across the entire application.
- **Adaptive layouts for columns and controls**:
  - `TorrentRow`: replaced fixed widths for metrics and speed columns (`82 / 62 / 66 / 88 pt`)
    with `frame(minWidth:)` + `.fixedSize(horizontal: true, vertical: false)` and `.layoutPriority(1)`
    on the title/metadata column.
  - `StatusBarView`: converted fixed height (`40 pt`) to `frame(minHeight: 40)` with vertical
    padding and `.fixedSize` on information clusters, maintaining compact threshold below `1120 pt`.
  - `SettingsSheet`: made the sidebar flexible (`minWidth: 168, idealWidth: 176, maxWidth: 210`) and
    converted numeric and proxy fields to `frame(minWidth:maxWidth:minHeight:)` with `.layoutPriority(1)`
    on descriptive labels.
  - `InspectorView`, `HeaderBar`, `AddTorrentSheet`, `NetworkDiagnosticsView`, `Components`,
    `ModalChrome`, `SegmentedPicker`: converted buttons, chips, segmented pickers, and search fields
    to `minHeight` with vertical padding.
- **Rendering verification & tests**: extended `ViewRenderingSupport` with headless minimum-width
  variants (`980 pt`) in `.dynamicTypeSize(.large)` and `.dynamicTypeSize(.xxLarge)` and added `DEBUG`
  overrides for `VERTEX_DYNAMIC_TYPE`, `VERTEX_WINDOW_WIDTH`, and `VERTEX_WINDOW_HEIGHT`.

### Italiano
#### Accessibilità e Tipografia
- **Tipografia semantica di sistema (Dynamic Type)**: migrata `Typography` dai valori a dimensione
  fissa (8…13.5 pt) ai text style semantici di sistema (`Font.system(.largeTitle/.title2/.title3/.headline/.body/.subheadline/.callout/.caption/.caption2)`
  con varianti `.rounded` e `.monospaced`), rimuovendo tutte le dichiarazioni `.system(size:)` dirette
  dalle viste e abilitando lo scaling di accessibilità su tutta l'applicazione.
- **Layout adattivi per colonne e controlli**:
  - `TorrentRow`: sostituite le larghezze fisse delle metriche e della colonna velocità (`82 / 62 / 66 / 88 pt`)
    con `frame(minWidth:)` + `.fixedSize(horizontal: true, vertical: false)` e `.layoutPriority(1)`
    sulla colonna del titolo/metadati.
  - `StatusBarView`: convertita l'altezza fissa (`40 pt`) in `frame(minHeight: 40)` con padding
    verticale e `.fixedSize` sui gruppi informativi, mantenendo la soglia compatta sotto `1120 pt`.
  - `SettingsSheet`: resa elastica la sidebar (`minWidth: 168, idealWidth: 176, maxWidth: 210`) e
    convertiti i campi numerici e proxy a `frame(minWidth:maxWidth:minHeight:)` con `.layoutPriority(1)`
    sulle etichette descrittive.
  - `InspectorView`, `HeaderBar`, `AddTorrentSheet`, `NetworkDiagnosticsView`, `Components`,
    `ModalChrome`, `SegmentedPicker`: convertiti pulsanti, chip, picker segmentati e campi di ricerca
    a `minHeight` con padding verticale.
- **Test e verifica di rendering**: esteso `ViewRenderingSupport` con varianti headless a larghezza
  minima (`980 pt`) in `.dynamicTypeSize(.large)` e `.dynamicTypeSize(.xxLarge)` e aggiunti in `DEBUG`
  gli override `VERTEX_DYNAMIC_TYPE`, `VERTEX_WINDOW_WIDTH` e `VERTEX_WINDOW_HEIGHT`.

## [1.11.0] — 2026-11-10

### English
#### Architecture & Concurrency
- **Migration to Swift 6 language mode**: package adopts `swift-tools-version: 6.0` and
  `swiftLanguageModes: [.v6]`, enabling complete static data race verification
  (`strict concurrency`) across all modules (`CTorrent`, `VertexKit`, `Vertex`, `VertexTestRunner`).
- **`@MainActor` isolation**: formalized main-thread isolation on `OpenPanelFactory`
  (file and folder pickers), `AppAppearance` (app and window appearance management),
  view local state (`UIState<Value>`, `DotGridCache`), and associated handlers.
- **Thread safety & `Sendable` types**:
  - `TorrentDropHandler` adopts `@Sendable @MainActor` closures and conforms `TorrentDropItem` to `Sendable`,
    ensuring safe drag-and-drop file and magnet transfers between AppKit threads and the UI.
  - Safe synchronization of the C++ session pointer (`vt_session*`) between the engine and the dedicated
    serial queue using `SessionPointerBox`.
  - The `compactWidthThreshold` in `StatusBarView` is declared `nonisolated` for compliant
    usage within the `Sendable` closure of `.onGeometryChange`.
- **Modernized test suite**:
  - Introduced `AsyncBox` to isolate and synchronize asynchronous callback assertions on `@MainActor`
    without region data races.
  - Test runner counters protected with `nonisolated(unsafe)` and `onMain` constrained to `Sendable` types.
- **Build requirements**: updated source build requirement to Swift 6.0+
  (included in Xcode 16.0+ and Command Line Tools for macOS Sequoia).

### Italiano
#### Architettura e Concorrenza
- **Migrazione a Swift 6 language mode**: il package adotta `swift-tools-version: 6.0` e
  `swiftLanguageModes: [.v6]`, abilitando la verifica statica completa contro i data race
  (`strict concurrency`) su tutti i moduli (`CTorrent`, `VertexKit`, `Vertex`, `VertexTestRunner`).
- **Isolamento `@MainActor`**: esplicitato l'isolamento del thread principale su `OpenPanelFactory`
  (pannelli di selezione file e cartelle), `AppAppearance` (gestione aspetto dell'app e delle finestre),
  sullo stato locale delle viste (`UIState<Value>`, `DotGridCache`) e sugli handler associati.
- **Thread-safety e tipi `Sendable`**:
  - `TorrentDropHandler` adotta closure `@Sendable @MainActor` ed estende `TorrentDropItem` a `Sendable`,
    garantendo il passaggio sicuro dei file e magnet trascinati tra i thread di AppKit e la UI.
  - Sincronizzazione sicura del puntatore di sessione C++ (`vt_session*`) tra il motore e la coda seriale
    dedicata tramite `SessionPointerBox`.
  - La soglia `compactWidthThreshold` in `StatusBarView` è dichiarata `nonisolated` per l'uso
    conforme nella closure `Sendable` di `.onGeometryChange`.
- **Suite di test modernizzata**:
  - Introdotto `AsyncBox` per isolare e sincronizzare le asserzioni delle callback asincrone su `@MainActor`
    senza data race di regione.
  - Contatori del test runner protetti con `nonisolated(unsafe)` e `onMain` vincolato a tipi `Sendable`.
- **Requisiti di build**: aggiornato il requisito per la compilazione dai sorgenti a Swift 6.0+
  (incluso in Xcode 16.0+ e Command Line Tools per macOS Sequoia).

## [1.10.2] — 2026-11-10

### English
#### Appearance & Graphics
- **Distinct paused completed state**: when a 100% completed torrent is manually paused,
  the outer ring remains 100% green while the inner icon displays a grey pause `⏸` instead
  of the checkmark `✓`, and the status pill displays "Completed" in green alongside "· Paused"
  in subtle grey, clearly conveying at a glance that the torrent is both completed and paused.

### Italiano
#### Aspetto e Grafica
- **Stato completato in pausa distinto**: quando un torrent completato al 100% viene fermato in
  pausa manuale, il cerchio esterno rimane verde al 100% ma l'icona interna mostra la pausa `⏸` in
  grigio anziché la spunta `✓`, e la pillola indica "Completato" in verde affiancato da "· In pausa"
  in grigio tenue, rendendo evidente a colpo d'occhio che il torrent è sia finito sia fermato.

## [1.10.1] — 2026-11-10

### English
#### Appearance & Graphics
- **"Completed" ring and status**: introduced a natural green circular ring with checkmark ✓
  (`TorrentPhase.completed`) for all 100% finished torrents, both when manually paused and
  when active without uploading peers (`uploadRate == 0 B/s`).
  The purple `Seeding` ring (↑) activates dynamically whenever uploading is underway.
- **Row progress track**: aligned the horizontal progress bar (`ProgressTrack`) exclusively
  with the content area (with a 69 pt leading inset), eliminating overlap and visual clipping over the `ProgressRing`.
- **Settings modal**: resized modal height to 540 pt (from 700 pt) to eliminate bottom dead space
  and prevent the modal from hugging window borders at minimum dimensions.
- **Inspector details**: the Inspector header reuses the row's colored status pill and the statistics grid is made more compact.
- **Light theme filters**: increased contrast for unselected filter chips in light theme.

#### Fixes
- **Queued torrent control consistency**: in the row context menu and Inspector, the pause button for a queued torrent explicitly displays "Exclude from Queue" (instead of "Resume" or "Pause").
- **Tracker error localization**: translated and mapped tracker editor bridge error messages in Italian and English ("Tracker URL is too long", "Invalid tracker URL", "Too many trackers").
- **Resume data persistence for trackers**: `vt_set_trackers` explicitly triggers immediate resume data persistence (`save_info_dict`), ensuring persistence even on immediate app quits.
- **Size consistency with skipped files**: for torrents with files set to "Skip", size and downloaded bytes reflect only wanted files (`total_wanted`), matching the percentage progress.
- **SOCKS5 Proxy TCP probe**: added guards checking host, port, and enabled state when asynchronous probe results arrive to prevent overwriting status with stale responses.
- **Localization script**: extended `check-localization.sh` to automatically verify C++ error strings assigned to `last_error`.

### Italiano
#### Aspetto e Grafica
- **Anello e stato "Completato"**: introdotta la comparsa naturale dell'anello circolare verde con
  spunta ✓ (`TorrentPhase.completed`) per tutti i torrent completati al 100%, sia quando sono
  fermati in pausa manuale, sia quando sono attivi ma senza peer in upload (`uploadRate == 0 B/s`).
  L'anello viola `In seed` (↑) si attiva dinamicamente quando c'è upload in corso.
- **Traccia di avanzamento nella riga**: allineata la barra orizzontale di progresso (`ProgressTrack`)
  esclusivamente all'area dei contenuti (con rientro di 69 pt a sinistra), eliminando l'intersezione
  e il taglio visivo sul `ProgressRing`.
- **Modale Impostazioni**: altezza riproporzionata a 540 pt (anziché 700 pt) per eliminare lo spazio
  vuoto inferiore ed evitare che la modale tocchi quasi i bordi della finestra a dimensioni minime.
- **Dettagli Inspector**: l'intestazione dell'Inspector riutilizza la pillola di stato colorata
  della riga e la griglia delle statistiche è resa più compatta.
- **Filtri in tema chiaro**: aumentato il contrasto dei chip di filtro non selezionati nel tema chiaro.

#### Corretto
- **Coerenza controlli torrent in coda**: nel menu contestuale della riga e nell'Inspector il pulsante
  di pausa per un torrent in coda indica esplicitamente "Escludi dalla coda" (anziché "Riprendi" o "Pausa").
- **Localizzazione errori tracker**: tradotti e mappati in italiano e inglese i messaggi di errore
  del bridge per il tracker editor ("URL del tracker troppo lungo", "URL del tracker non valido", "Troppi tracker").
- **Persistenza resume data per i tracker**: `vt_set_trackers` richiede esplicitamente il salvataggio
  immediato del resume data (`save_info_dict`), garantendo la persistenza anche in caso di chiusura immediata.
- **Coerenza dimensione con file esclusi**: per torrent con file impostati su "Skip", dimensione e byte
  scaricati riflettono i soli file richiesti (`total_wanted`), allineandosi al progresso percentuale.
- **Sonda TCP Proxy SOCKS5**: aggiunta guardia su host, porta e stato attivo all'arrivo dei risultati
  della sonda asincrona per prevenire sovrascritture di stato con vecchie risposte.
- **Script di localizzazione**: `check-localization.sh` esteso alla verifica automatica delle stringhe
  di errore C++ assegnate a `last_error`.

## [1.10.0] — 2026-11-09

### English
#### Features
- **Active torrents queue**: new setting under **Performance → Active Torrents** (0 = all
  together). Above the limit, torrents wait and the row shows the **Queued** badge;
  when a slot frees up, they start automatically in order of addition.
  - The limit is enforced by libtorrent with `active_limit`/`active_downloads`/`active_seeds`
    (new `vt_set_active_limit`), with `dont_count_slow_torrents` disabled so the number of active
    rows always matches the setting.
  - Torrents are now **auto-managed**: manual pause exits the queue (`unset auto_managed`),
    so the queue manager does not restart them; ▶ puts them back in queue.
  - On a queued torrent row, the pause button means **Exclude from Queue** (new `dequeue` command),
    not "stop a transfer" (there is none running).
  - Queued torrents no longer end up under "Paused": they remain in the list filter where they will run
    (Downloading or Seeding), so "Paused" continues to mean "stopped by user".
  - After pause, resume, exclusion, and removal, slots are reassigned immediately (`nudge_auto_manage`);
    libtorrent's periodic recalculation remains at 30 s.

#### Developer Notes
- `docs/queue-and-limits.md` documents the implementation, known limits (single global limit,
  non-reorderable FIFO order, counters treating queue as paused), and test-covered invariants.
- **Compatibility**: zero migration required. Existing installations have `maxActiveTorrents = 0`
  (all torrents active), keeping 1.9.2 behavior until a limit is set. Resumed torrents preserve
  previous session flags; a torrent that was manually paused in 1.9.2 remains paused (does not enter queue).

### Italiano
#### Novità
- **Coda dei torrent attivi**: nuova impostazione **Prestazioni → Torrent attivi** (0 = tutti
  insieme). Sopra il limite i torrent restano in attesa e la riga mostra la pill **In coda**;
  quando uno slot si libera partono da soli, in ordine di aggiunta.
  - Il limite è applicato da libtorrent con `active_limit`/`active_downloads`/`active_seeds`
    (nuova `vt_set_active_limit`), con `dont_count_slow_torrents` disattivato perché il numero
    di righe attive corrisponda sempre all'impostazione.
  - I torrent ora sono **auto-managed**: una pausa manuale esce dalla coda
    (`unset auto_managed`), quindi il gestore non li riavvia più; ▶ li rimette in coda.
  - Sulla riga di un torrent in coda il pulsante di pausa significa **Escludi dalla coda**
    (nuovo comando `dequeue`), non "ferma un trasferimento" (non ce n'è uno in corso).
  - I torrent in coda non finiscono più in "In pausa": restano nel filtro della lista in cui
    gireranno (Download o Seed), così "In pausa" continua a significare "fermato da te".
  - Dopo pausa, ripresa, esclusione e rimozione lo slot viene riassegnato subito
    (`nudge_auto_manage`); il ricalcolo periodico di libtorrent resta a 30 s.

#### Note per gli sviluppatori
- `docs/queue-and-limits.md` descrive l'implementazione, i limiti noti (limite unico, ordine
  FIFO non riordinabile, contatori che contano la coda come pausa) e le invarianti coperte dai
  test.
- **Compatibilità**: nessuna migrazione. Le installazioni esistenti hanno
  `maxActiveTorrents = 0` (tutti i torrent attivi), quindi il comportamento resta quello della
  1.9.2 finché non si imposta un limite. I torrent ripresi dalla resume data mantengono i flag
  della sessione precedente; un torrent che nella 1.9.2 era in pausa manuale resta in pausa
  (non entra in coda).

## [1.9.2] — 2026-11-09

### English
#### Fixes
- **"Completed" filter**: libtorrent reports a finished torrent as *seeder* (state 5) and
  reserves state 4 for complete downloads with filtered files, causing the chip to remain at 0 and
  rendering `TorrentPhase.completed` dead code. `Torrent.phase` now distinguishes pure seeders
  (5) from complete downloads with excluded files (4), and "Completed" is the single overlapping
  filter: it counts all finished torrents, including seeding ones, matching qBittorrent and
  Transmission behavior. "Downloading", "Seeding", and "Paused" remain mutually exclusive and row
  badges are unaffected.
- **Sort by name**: the arrow inverted sorting logic compared to other criteria (Z→A with an upward
  arrow). Now `ascending` has consistent meaning across all criteria, and choosing "Name" starts with
  A→Z (`TorrentSort.defaultAscending`).
- **Non-blocking torrent addition**: `vt_add_magnet` and `vt_add_torrent_file` execute on `sessionQueue`;
  the result — including duplicates — returns to `AddTorrentSheet` via callback, which closes only when
  a torrent is accepted. Previously, `.torrent` parsing and bridge calls blocked the main thread, and the
  sheet dismissed even on failure.
- **Bridge**: `write_resume_impl` rejects an empty `resume_dir` (which used to write `<hash>.resume`
  into the process working directory); removed unreachable `peer_connect_alert` branch because the
  `connect` category is not enabled in the alert mask (proxy error resets remain handled by the TCP probe).
- **Accessibility**: hidden row actions are excluded from the accessibility tree; the "Remove…"
  context menu item routes through the same trash confirmation instead of deleting immediately.

#### Appearance
- **Light theme contrast**: accent colors were tuned for dark backgrounds and had text contrast
  between 1.4:1 and 3.2:1 on light backgrounds (mint 1.44, green 1.50, amber 1.71, coral 2.43,
  blue 2.65, violet 3.18). `Palette` now exposes `mintText`/`violetText`/`coralText`/`amberText`/
  `greenText`/`blueText` variants (≥5.2:1) used by speed indicators, status badges, errors, proxy badges,
  and statistics; saturated colors remain reserved for rings, gradients, and fills.
- **Default theme**: set to "System" instead of "Dark", preventing a Mac in light mode from launching
  the app in dark mode.
- **Typography**: 25 typographic tokens with 0.2–0.5 pt spacing increments are consolidated into six
  steps (8/9/10/10.5/11/12); introduced new `rowTitle`/`rowMeta` tokens for torrent rows.
- **Row progress bar**: thin (2.5 pt) track anchored at the bottom of the card, rendered only when
  progress is available; the ring remains the primary indicator.

### Italiano
#### Corretto
- **Filtro "Completati"**: libtorrent riporta un torrent finito come *seeder* (state 5) e
  riserva lo stato 4 ai download completi con pezzi filtrati, quindi il chip restava a 0 e
  `TorrentPhase.completed` era codice morto. `Torrent.phase` ora distingue il seeder puro
  (5) dal download completo con file esclusi (4), e "Completati" è l'unico filtro
  sovrapposto: conta tutti i torrent finiti, seed compresi, come fanno qBittorrent e
  Transmission. "Download", "Seed" e "In pausa" restano mutuamente esclusivi e le pill di
  riga non cambiano.
- **Ordinamento per nome**: la freccia invertiva il criterio rispetto agli altri
  ordinamenti (Z→A con la freccia in su). Ora `ascending` significa la stessa cosa per tutti
  i criteri e selezionare "Nome" parte da A→Z (`TorrentSort.defaultAscending`).
- **Aggiunta non bloccante**: `vt_add_magnet`/`vt_add_torrent_file` girano su `sessionQueue`;
  l'esito — duplicato compreso — arriva a `AddTorrentSheet` via callback, che chiude solo a
  torrent accettato. Prima il parsing del `.torrent` e la chiamata al bridge bloccavano il
  main thread, e la sheet si chiudeva anche quando l'aggiunta falliva.
- **Bridge**: `write_resume_impl` rifiuta una `resume_dir` vuota (scriveva `<hash>.resume`
  nella working directory del processo); rimosso il ramo `peer_connect_alert`, irraggiungibile
  perché la categoria `connect` non è nella maschera degli alert (il reset dell'errore proxy
  resta affidato alla sonda TCP).
- **Accessibilità**: le azioni di riga nascoste escono dal tree di accessibilità; il menu
  contestuale "Rimuovi…" passa dalla stessa conferma del cestino invece di eliminare subito.

#### Aspetto
- **Contrasto nel tema chiaro**: i colori accentati erano tarati sul fondo scuro e come testo
  stavano tra 1,4:1 e 3,2:1 sul fondo chiaro (mint 1,44, verde 1,50, ambra 1,71, corallo 2,43,
  blu 2,65, viola 3,18). `Palette` espone ora le varianti `mintText`/`violetText`/`coralText`/
  `amberText`/`greenText`/`blueText` (≥5,2:1) usate da velocità, pill di stato, errori, badge
  proxy e statistiche; i colori saturi restano per ring, gradienti e riempimenti.
- **Tema di default**: "Sistema" invece di "Scuro", così un Mac in tema chiaro non apre
  l'app in scuro.
- **Tipografia**: i 25 token a 0,2–0,5 pt di distanza sono consolidati in sei gradini
  (8/9/10/10,5/11/12); nuovi token `rowTitle`/`rowMeta` per la riga del torrent.
- **Barra di progresso nella riga**: traccia sottile (2,5 pt) ancorata al fondo della card,
  disegnata solo mentre c'è progresso da mostrare; il ring resta l'indicatore principale.

## [1.9.1] — 2026-11-09

### English
#### Fixes
- **List focus ring**: removed system blue glow introduced with keyboard navigation;
  focus remains indicated by the selected row.
- **Launch & appearance**: saved appearance is now applied in `applicationWillFinishLaunching`
  and window chrome in `viewDidMoveToWindow`, preventing a visible first-frame transition
  on initial launch following an update.

### Italiano
#### Corretto
- **Focus ring della lista**: rimosso l'alone blu di sistema introdotto con la navigazione
  da tastiera; il focus resta indicato dalla riga selezionata.
- **Avvio e aspetto**: l'aspetto salvato viene applicato in `applicationWillFinishLaunching`
  e il chrome della finestra in `viewDidMoveToWindow`, evitando la transizione visibile
  del primo frame al primo avvio dopo l'aggiornamento.

## [1.9.0] — 2026-11-09

### English
#### Features
- **Sidebar settings**: vertical rail with Folders, Performance, Network, SOCKS5 Proxy,
  Behavior, Appearance, and About; each section features its own panel and scroll view,
  ensuring Proxy and trailing sections are never hidden below the fold.
- **Resizable Inspector**: drag handle between list and details (320–520 pt), resize cursor,
  and adjustable action for VoiceOver.
- **Revamped torrent list**: per-row status pills (Metadata, Downloading, Seeding, Paused,
  Completed), hidden zero speeds, ratio (`×…`) in the right column, extended columns
  (size, time/ratio, peers/seeds) on wide windows, inline version in header, and consistent sort controls.
- **Three-level file priorities**: Skip / Normal / High per file, with dedicated menus and icons in the inspector.
- **Actionable toasts**: addition → "Open Folder", completion → "Reveal in Finder"; remain visible for 7 s and dismiss upon action.
- **Non-blocking launch**: libtorrent session is initialized on `sessionQueue`, with loading placeholder and persistent error view with "Retry".
- **Keyboard navigation**: `↑`/`↓` navigate list selection and scroll the selected row into view.
- **Responsive status bar**: compact layout below 1120 pt; speed limits are shown in KB/s as typed and speeds no longer wrap.
- **Accessibility**: VoiceOver labels on icon buttons and "Reduce Motion" honored by all animations (selection, hover, toasts, modals, filters, sidebar, buttons).
- **Diagnostics**: disabled UPnP/NAT-PMP state (by user choice or active proxy) is distinguished from mapping errors, eliminating false alarms.

#### Fixes
- **SOCKS5 authentication (RFC 1929)**: when the **Username** field is populated, the bridge configures
  libtorrent with `socks5_pw` type, ensuring credentials are sent. Without username, it defaults to `socks5`.
  Actual status is exposed in the snapshot (`proxy.auth`) and in Network Diagnostics as an `RFC 1929` badge.
- **UPnP/NAT-PMP leak prevention with active proxy**: port, limits, DHT, or interface updates no longer
  re-enable router mapping (`vt_apply_settings_ex` forces mapping off while proxy is active).
- **SOCKS5 errors**: proxy alerts reported by libtorrent are no longer cleared by the TCP reachability probe;
  the badge also reflects handshake errors.
- **Proxy probe**: replaced `Darwin.select`/`fd_set` with `poll`, removing the `FD_SETSIZE` limit and out-of-bounds write risks.
- **UI**: contrast of secondary text and borders in light theme, ETA "—" for seeding torrents, filter counters always visible, limits shown in KB/s as typed, sparkline hidden when traffic is zero.

#### Robustness
- **Opening files from Finder**: AppDelegate waits (up to 5 s) for session readiness before consuming `.torrent`/magnet files, preventing drops during asynchronous launch.
- **Toast deduplication**: addition errors are no longer shown twice (synchronous return + `alert_error`).
- **Modals**: `⌘O` and `⌘F` are ignored while a modal is open; the underlying view is disabled so focus cannot escape the modal.

#### Security
- **Proxy password in Keychain**: SOCKS5 password is no longer saved in plaintext in `UserDefaults`;
  it is migrated to the Keychain on first launch (removed from defaults only after successful write) and debounced when edited in Settings.

### Italiano
#### Novità
- **Impostazioni a sidebar**: rail verticale con Cartelle, Prestazioni, Rete, Proxy SOCKS5,
  Comportamento, Aspetto, Informazioni; ogni sezione ha il proprio pannello e il proprio
  scroll, quindi Proxy e le sezioni finali non restano più nascoste sotto la piega.
- **Inspector ridimensionabile**: maniglia di trascinamento tra lista e dettagli (320–520 pt),
  cursore di resize e azione regolabile per VoiceOver.
- **Lista torrent rinnovata**: pill di stato per riga (Metadati, Download, Seed, In pausa,
  Completato), velocità a zero nascoste, rapporto (`×…`) nella colonna di destra, colonne
  estese (dimensione, tempo/rapporto, peer/seed) sulle finestre larghe, versione inline
  nell'header e controllo di ordinamento coerente.
- **Priorità file a tre livelli**: Skip / Normale / Alta per singolo file, con menu e icone
  dedicate nell'inspector.
- **Toast azionabili**: aggiunta → “Apri cartella”, completamento → “Mostra nel Finder”;
  restano visibili 7 s e si chiudono dopo l'azione.
- **Avvio non bloccante**: la sessione libtorrent viene creata su `sessionQueue`, con
  placeholder di caricamento e vista di errore persistente con “Riprova”.
- **Navigazione da tastiera**: `↑`/`↓` spostano la selezione nella lista e portano la riga
  selezionata in vista.
- **Barra di stato responsive**: layout compatto sotto 1120 pt; i limiti sono mostrati in
  KB/s come digitati e le velocità non vanno più a capo.
- **Accessibilità**: etichette VoiceOver sui pulsanti a icona e “Riduci movimento” rispettato
  da tutte le animazioni (selezione, hover, toast, modali, filtri, sidebar, pulsanti).
- **Diagnostica**: lo stato UPnP/NAT-PMP disattivato (per scelta o per proxy) è distinto
  dall'errore di mapping, senza falsi allarmi.

#### Corretto
- **Autenticazione SOCKS5 (RFC 1929)**: con il campo **Utente** compilato il bridge configura
  libtorrent con il tipo `socks5_pw`, quindi le credenziali vengono realmente inviate. Senza
  username resta `socks5`. Lo stato effettivo è esposto nello snapshot (`proxy.auth`) e nella
  Diagnostica rete come badge `RFC 1929`.
- **Anti-leak UPnP/NAT-PMP con proxy attivo**: un aggiornamento di porta, limiti, DHT o
  interfaccia non riattiva più la mappatura sul router (`vt_apply_settings_ex` forza la
  disattivazione finché il proxy è attivo).
- **Errori SOCKS5**: gli alert del proxy riportati da libtorrent non vengono più cancellati
  dalla sonda TCP di raggiungibilità; il badge riflette anche gli errori di handshake.
- **Sonda proxy**: `Darwin.select`/`fd_set` sostituiti da `poll`, eliminando il limite
  `FD_SETSIZE` e il rischio di scritture fuori bounds.
- **UI**: contrasto di testi secondari e bordi nel tema chiaro, ETA “—” per i torrent in seed,
  contatori dei filtri sempre visibili, limite mostrato in KB/s come digitato, sparkline
  nascosta quando il traffico è zero.

#### Robustezza
- **Apertura file da Finder**: l'AppDelegate attende (max 5 s) che la sessione sia pronta
  prima di consumare i `.torrent`/magnet, evitando di perderli durante l'avvio asincrono.
- **Deduplica dei toast**: un errore di aggiunta non viene più mostrato due volte (ritorno
  sincrono + `alert_error`).
- **Modali**: `⌘O` e `⌘F` sono ignorati mentre una modale è aperta; la vista sottostante è
  disabilitata, così il focus non esce dalla modale.

#### Sicurezza
- **Password proxy nel Portachiavi**: la password SOCKS5 non è più salvata in chiaro in
  `UserDefaults`; viene migrata al Keychain al primo avvio (rimossa solo dopo una scrittura
  riuscita) e salvata con debounce dal pannello Impostazioni.

## [1.8.3] — 2026-11-08

### English
#### Diagnostics & UX
- **Automatic SOCKS5 green badge restoration on proxy restart**: when Tor or the SOCKS5
  proxy is restarted following an outage, the active TCP probe immediately clears both the
  recorded error in Swift and the error state in the C++ bridge (`vt_clear_proxy_error`).
  The badge reverts to mint green instantly without remaining frozen in the previous poll's error state.

### Italiano
#### Diagnostica e UX
- **Ripristino automatico badge SOCKS5 verde al riavvio del proxy**: quando Tor o il
  proxy SOCKS5 vengono riaccesi dopo un'interruzione, la sonda TCP attiva pulisce
  immediatamente sia l'errore registrato in Swift sia lo stato d'errore nel bridge
  C++ (`vt_clear_proxy_error`). Il badge torna verde menta all'istante senza
  rimanere congelato sullo stato d'errore del poll precedente.

## [1.8.2] — 2026-11-07

### English
#### Diagnostics & UX
- **Active SOCKS5 proxy health check**: added periodic asynchronous TCP reachability checks
  to the configured proxy server (e.g. Tor on `127.0.0.1:9050`).
  If the proxy is shut down or unresponsive, the `SOCKS5` badge in the status bar and the
  card in `NetworkDiagnosticsView` immediately turn coral/warning with the corresponding
  error message, reverting to green as soon as the proxy resumes operation.

### Italiano
#### Diagnostica e UX
- **Health-check attivo del proxy SOCKS5**: aggiunto un controllo TCP asincrono e
  periodico verso il server/proxy configurato (ad es. Tor su `127.0.0.1:9050`).
  Se il proxy viene spento o non risponde, il badge `SOCKS5` nella barra di stato
  e la card in `NetworkDiagnosticsView` diventano immediatamente corallo/avviso
  con il messaggio di errore, tornando verdi appena il proxy riprende a funzionare.

## [1.8.1] — 2026-11-07

### English
#### Security & UX
- **Strict Kill-Switch with `anonymous_mode`**: when the SOCKS5 proxy is active, libtorrent
  enables `anonymous_mode = true`. If the SOCKS5 server (or Tor) drops or is offline, all
  existing and future connections are terminated immediately without falling back to plaintext
  connections (total fail-closed behavior).
- **Proxy warning badge and diagnostics**: captured `lt::socks5_alert` in the C++ bridge;
  if the proxy is unreachable or rejects connections, the `SOCKS5` badge in the status bar
  turns coral (`Theme.coral`) with an alert icon and explicit tooltip. The card in
  `NetworkDiagnosticsView` also reflects the connection error state.

### Italiano
#### Sicurezza e UX
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

### English
Privacy & anonymity release: comprehensive SOCKS5 proxy support (Tor, VPN proxies, SSH tunnels).

#### Features
- **SOCKS5 Proxy**: new option in Network Settings to route all torrent traffic through a SOCKS5
  proxy (with optional RFC 1929 authentication support).
- **Anti-Leak / Fail-Closed**: libtorrent routes all tracker connections, peer connections, and hostname
  resolutions through the configured proxy (`proxy_hostnames`, `proxy_tracker_connections`, `proxy_peer_connections`).
  UPnP and NAT-PMP are automatically disabled to prevent router local IP leaks.
- **Diagnostics and StatusBar**: proxy status display in `NetworkDiagnosticsView` and SOCKS5 indicator in `StatusBarView`.

#### C++ Bridge
- New `vt_apply_proxy_settings` API dynamically configuring libtorrent proxy settings.
- Proxy state (`enabled`, `type`, `hostname`, `port`) included in the JSON snapshot.

#### Tests
- SOCKS5 configuration tests in `CTorrentBridgeTests`.
- Live integration test `SOCKS5 Proxy live: routing fail-closed con proxy non raggiungibile`
  in `TorrentIntegrationTests`. Automated test suite: 63/63 passed.

### Italiano
Release privacy & anonimato: supporto completo per proxy SOCKS5 (Tor, VPN proxy, tunnel SSH).

#### Novità
- **Proxy SOCKS5**: nuova opzione nelle impostazioni di rete per instradare tutto il
  traffico torrent verso un proxy SOCKS5 (con supporto opzionale all'autenticazione RFC 1929).
- **Anti-Leak / Fail-Closed**: libtorrent instrada tutte le connessioni verso tracker, peer
  e risoluzione degli hostname attraverso il proxy configurato (`proxy_hostnames`,
  `proxy_tracker_connections`, `proxy_peer_connections`). UPnP e NAT-PMP vengono
  automaticamente disabilitati per prevenire leak dell'IP locale del router.
- **Diagnostica e StatusBar**: visualizzazione dello stato proxy in `NetworkDiagnosticsView`
  e indicatore SOCKS5 nella `StatusBarView`.

#### Bridge C++
- Nuova API `vt_apply_proxy_settings` che configura a caldo il proxy libtorrent.
- Inclusione dello stato proxy (`enabled`, `type`, `hostname`, `port`) nello snapshot JSON.

#### Test
- Test di configurazione SOCKS5 in `CTorrentBridgeTests`.
- Test d'integrazione live `SOCKS5 Proxy live: routing fail-closed con proxy non raggiungibile`
  in `TorrentIntegrationTests`. Suite automatica: 63/63 test superati.

## [1.7.0] — 2026-11-06

### English
Architectural release: complete modularization of `TorrentEngine` and live regression tests on network binding and kill-switch.

#### Architecture & Maintenance
- **`TorrentEngine` modularization**: split the monolithic file into four specialized files without altering concurrency guarantees or `sessionQueue` semantics:
  - `Preferences.swift`: keys, defaults, preferences validation, and session configuration;
  - `TorrentEngine.swift`: `@Published` reactive state, session lifecycle, and serial queue primitives;
  - `TorrentEngine+Polling.swift`: polling loop management, `PollState`, snapshots, and detail loading;
  - `TorrentEngine+Actions.swift`: user commands, file management, and applied preferences.

#### Tests
- **WireGuard binding live test**: new integration test verifying runtime fail-closed behavior (no data leaks) upon tunnel interface shutdown and subsequent deterministic download resumption upon address restoration.
- **Dynamic `bindAddress` test**: verified dynamic switching of listening address in `EngineTests` with `listenError` handling and automatic recovery.
- Automated test suite: 61/61 passed.

### Italiano
Release architetturale: modularizzazione completa di `TorrentEngine` e test di
regressione live sul binding di rete e kill-switch.

#### Architettura e Manutenzione
- **Modularizzazione di `TorrentEngine`**: diviso il file monolitico in quattro
  file specializzati senza alterare la concorrenza né le garanzie di `sessionQueue`:
  - `Preferences.swift`: chiavi, default, validazione preferenze e configurazione di sessione;
  - `TorrentEngine.swift`: stato reattivo `@Published`, ciclo vitale della sessione e primitive di coda seriale;
  - `TorrentEngine+Polling.swift`: gestione del loop di polling, `PollState`, snapshot e caricamento dettagli;
  - `TorrentEngine+Actions.swift`: comandi utente, gestione file e preferenze applicate.

#### Test
- **Test live sul binding WireGuard**: nuovo test d'integrazione che verifica a caldo
  il comportamento fail-closed (nessun leak di dati) alla caduta dell'interfaccia tunnel
  e la successiva ripresa deterministica del download al ripristino dell'indirizzo.
- **Test dinamico `bindAddress`**: verifica della commutazione a caldo dell'indirizzo di
  ascolto in `EngineTests` con gestione di `listenError` e ripristino automatico.
- Suite automatica: 61/61 test superati.

## [1.6.2] — 2026-11-05

### English
#### Fixes
- **Port and counter formatting**: removed thousands grouping separators from `IP:port`
  in the Network Diagnostics panel (`Text(verbatim:)` on `"\(publicIP):\(testPort)"`, which
  under Italian locale displayed e.g. `89.168.20.17:51.413` instead of `89.168.20.17:51413`)
  and from numeric counter badges.

### Italiano
#### Correzioni
- **Formattazione porta e contatori**: rimosso il separatore delle migliaia da
  `IP:porta` nel pannello Diagnostica rete (`Text(verbatim:)` su
  `"\(publicIP):\(testPort)"`, che con localizzazione italiana mostrava es.
  `89.168.20.17:51.413` invece di `89.168.20.17:51413`) e dai badge numerici di
  conteggio.

## [1.6.1] — 2026-11-04

### English
Responsiveness release: instant application termination.

#### Performance
- **Instant window dismissal**: `applicationShouldTerminate` hides windows immediately (`orderOut`)
  upon receiving `Cmd-Q`, while resume saving and engine shutdown continue in the background.
- **Exit tracker timeout**: libtorrent `stop_tracker_timeout` reduced from 5 s to 1 s to prevent
  slow or unreachable trackers from hanging process shutdown.
- **Resume saving in `vt_session_destroy`**: replaced fixed polling (`sleep_for(40ms)`) with reactive
  `wait_for_alert` and skipped regenerating resume data already updated on disk (`!need_save_resume_data()`).

### Italiano
Release di reattività: chiusura dell'applicazione istantanea.

#### Prestazioni
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

### English
Feature and concurrency release: reversible sorting in filter bar, quick "Select All / None" file selection in details, and fully asynchronous user operations on session queue.

#### Features
- **Reversible sorting**: dedicated button in filter bar reverses ascending/descending order for all criteria (Recent, Name, Size, Progress, Speed); reselecting active menu item also toggles order direction.
- **Quick file selection ("Select All / None")**: multi-file torrent details panel displays a toolbar with selected file counts and `Select All` / `Select None` buttons, backed by an atomic bulk call in the C++ bridge (`vt_set_all_file_priorities` / `prioritize_files`).

#### Performance & Concurrency
- **Asynchronous operations on `sessionQueue`**: `pause`, `resume`, `reannounce`, `toggleSequential`, `remove`, `setFilePriority`, `setAllFilePriorities`, `copyMagnet`, and `applySettings` are queued asynchronously on `sessionQueue` (`enqueueSessionOperation`) with atomic `vt_last_error` retrieval, preventing synchronous waits on `@MainActor` while polls are inflight.

#### Tests
- Extended `ModelsTests` (reverse sorting across all criteria) and `EngineTests` (bulk file priorities and asynchronous commands). Suite 60/60 passed; 221 aligned localized keys (IT/EN).

### Italiano
Release funzionale e di concorrenza: ordinamento invertibile nella barra filtri,
selezione rapida "Tutti / Nessuno" dei file nei dettagli e operazioni utente
completamente asincrone sulla coda di sessione.

#### Novità
- **Ordinamento invertibile**: nella barra filtri un pulsante dedicato inverte
  l'ordine crescente/decrescente per tutti i criteri (Recenti, Nome, Dimensione,
  Progresso, Velocità); anche riselezionare la voce attiva nel menu inverte la
  direzione.
- **Selezione rapida file ("Tutti / Nessuno")**: nel pannello dettagli dei
  torrent multi-file compare una barra con il conteggio dei file selezionati e i
  pulsanti `Tutti` e `Nessuno`, supportati da una chiamata bulk atomica nel
  bridge C++ (`vt_set_all_file_priorities` / `prioritize_files`).

#### Prestazioni e Concorrenza
- **Operazioni asincrone su `sessionQueue`**: `pause`, `resume`, `reannounce`,
  `toggleSequential`, `remove`, `setFilePriority`, `setAllFilePriorities`,
  `copyMagnet` e `applySettings` vengono accodate in modo asincrono su
  `sessionQueue` (`enqueueSessionOperation`) con lettura atomica di
  `vt_last_error`, evitando qualsiasi attesa sincrona sul `@MainActor` mentre un
  poll è in volo.

#### Test
- Estesi `ModelsTests` (ordinamento invertito per tutti i criteri) ed
  `EngineTests` (priorità file bulk e comandi asincroni). Suite 60/60; 221 chiavi
  localizzate allineate (IT/EN).

## [1.5.9] — 2026-11-04

### English
Polish release: sparkline decay to zero following transfer completion, unified RFC 3629 UTF-8 validator and `getifaddrs`, comprehensive bridge validation error mapping, and consistent UI dividers.

#### Fixes
- **Idle sparkline**: when transfers end and speeds drop to `0 B/s`, history continues appending zero samples until the curve flattens to zero before skipping idle polls, preventing the status bar graph from remaining frozen on the last wave.
- **Localized errors**: mapped C++ bridge validation messages (`exceeds maximum size`, `not a regular file`, `cannot stat`, `Invalid parameters`, invalid or unwritable destination folder) in `TorrentEngine.localizedError(_:)` to Italian and English localized keys.

#### Maintenance
- **UTF-8 / C++ Detail**: unified RFC 3629 state machine into `utf8_sequence_length`, shared between `is_valid_utf8` and `json_escape`; in `vt_detail_json` the `metadata` flag is retrieved directly from `handle.torrent_file()` without an extra `handle.status()` call.
- **Network interfaces**: `LocalNetwork.primaryIPv4Address()` reuses `ipv4Interfaces()`, eliminating the secondary `getifaddrs`/`getnameinfo` loop.
- **Engine & UI**: `toast` made `private(set)`, removed unreachable `deinit` in `TorrentEngine`, and replaced remaining 1 px manual dividers with `Hairline(palette:)` in `InspectorView` and `StatusBarView`.

#### Tests
- New test in `EngineTests` verifying zero decay in `downloadHistory` after traffic ceases and subsequent suspension of idle updates. Suite 60/60 passed.

### Italiano
Release di rifinitura: decay della sparkline a zero dopo un trasferimento,
unificazione del validatore UTF-8 RFC 3629 e di `getifaddrs`, mappatura completa
degli errori di validazione del bridge e uniformità dei divisori UI.

#### Correzioni
- **Sparkline in idle**: quando un trasferimento termina e le velocità scendono a
  `0 B/s`, la history continua ad aggiungere campioni nulli finché la curva non
  si appiattisce a zero prima di attivare lo skip dell'idle poll, evitando che il
  grafico nella barra di stato resti congelato sull'ultima onda.
- **Errori localizzati**: mappati in `TorrentEngine.localizedError(_:)` i messaggi
  di validazione del bridge C++ (`exceeds maximum size`, `not a regular file`,
  `cannot stat`, `Parametri non validi`, cartella di destinazione non valida o non
  scrivibile) sulle chiavi localizzate in italiano e inglese.

#### Manutenzione
- **UTF-8 / Dettaglio C++**: unificata la macchina a stati RFC 3629 in
  `utf8_sequence_length`, condivisa tra `is_valid_utf8` e `json_escape`; in
  `vt_detail_json` il flag `metadata` viene ricavato direttamente da
  `handle.torrent_file()` senza una seconda chiamata a `handle.status()`.
- **Interfacce di rete**: `LocalNetwork.primaryIPv4Address()` riutilizza
  `ipv4Interfaces()` eliminando il secondo loop `getifaddrs`/`getnameinfo`.
- **Engine e UI**: `toast` reso `private(set)`, rimosso il `deinit` irraggiungibile
  in `TorrentEngine` e sostituiti gli ultimi divisori manuali da 1 px con
  `Hairline(palette:)` in `InspectorView` e `StatusBarView`.

#### Test
- Nuovo test in `EngineTests` che verifica lo scorrimento a zero di
  `downloadHistory` dopo il termine del traffico e il successivo arresto delle
  pubblicazioni in idle. Suite 60/60.

## [1.5.8] — 2026-11-04

### English
Reliability release: multiple shutdown completions, diagnostic session creation errors, encoded `request_id`, and DMG without deprecation warnings.

#### Fixes
- **Shutdown**: all completion handlers requested during shutdown are queued and invoked; a secondary request no longer overwrites the first during PEX session restarts.
- **Session creation**: `vt_session_create_full` returns error messages to the caller; directory creation uses `std::error_code` and file system errors (including `FileManager` errors) route to toast notifications instead of being reduced to "engine unavailable".
- **Port diagnostics**: `request_id` from check-host.net is URL-path-encoded as a single path segment, preventing special characters from distorting request URLs.
- **Localization**: torrent removal dialog and network diagnostics text explicitly use `L()`; keys were already present in both languages.

#### Tests
- New tests covering concurrent completions during PEX restart, session creation failure with invalid paths, and `request_id` encoding. Suite 60/60 passed.

#### Tools
- **DMG without warnings**: `Scripts/make-dmg.sh` uses `diskutil image create/attach` and `diskutil eject` when available (macOS 26+), eliminating `hdiutil` deprecation warnings; macOS 15 runners retain fallback to `hdiutil`.

### Italiano
Release di affidabilità: completion di shutdown multiple, errori di creazione sessione
diagnostici, `request_id` codificato e DMG senza warning di deprecazione.

#### Correzioni
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

#### Test
- Nuovi test per completion concorrenti durante il riavvio PEX, errore di creazione
  sessione con percorso non valido e codifica del `request_id`. Suite 60/60.

#### Strumenti
- **DMG senza warning**: `Scripts/make-dmg.sh` usa `diskutil image create/attach` e
  `diskutil eject` quando disponibili (macOS 26+), eliminando i warning di deprecazione
  di `hdiutil`; sulle runner macOS 15 resta il fallback a `hdiutil`.

## [1.5.7] — 2026-11-03

### English
Robustness release: strict UTF-8 validation in bridge, zero-wait shutdown, and off-main-actor detail loading.

#### Fixes
- **UTF-8 / JSON**: `json_escape` validates RFC 3629 and replaces non-compliant bytes or sequences with `�`; exported `vt_json_escape` and `vt_is_valid_utf8`.
- **Shutdown**: a `save_resume_data_failed_alert` with valid handle but unrequested id no longer decrements `pending`; prevents prematurely releasing another torrent's slot and exiting before save completion. Invalid handles remain tolerated to avoid hanging the final 3-second timeout.
- **Detail loading**: `loadDetail` uses `sessionQueue.async` and no longer blocks `MainActor`; `pollNowForTesting` preserves deterministic synchronous execution.

#### Tests
- New UTF-8 test covering ASCII, emoji, 2/3/4-byte overlong sequences, surrogates, values beyond U+10FFFF, isolated continuation bytes, and truncated sequences.
- `EngineTests` wait for asynchronous detail updates using `waitUntil`. Suite 58/58 passed.

### Italiano
Release di robustezza: validazione UTF-8 rigorosa nel bridge, shutdown senza attese
inutili e caricamento del dettaglio fuori dal main actor.

#### Correzioni
- **UTF-8 / JSON**: `json_escape` valida RFC 3629 e sostituisce byte o sequenze non
  conformi con `�`; esportate `vt_json_escape` e `vt_is_valid_utf8`.
- **Shutdown**: un `save_resume_data_failed_alert` con handle valido ma id non richiesto
  non decrementa più `pending`; evita di liberare lo slot di un altro torrent e di
  uscire prima del salvataggio. Gli handle invalidi restano perdonati per non bloccare
  i 3 secondi finali.
- **Dettaglio**: `loadDetail` usa `sessionQueue.async` e non blocca più il MainActor;
  `pollNowForTesting` mantiene il percorso sincrono deterministico.

#### Test
- Nuovo test UTF-8 con ASCII, emoji, overlong 2/3/4 byte, surrogati, valori oltre
  U+10FFFF, continuation isolate e sequenze troncate.
- `EngineTests` attendono il dettaglio asincrono con `waitUntil`. Suite 58/58.

## [1.5.6] — 2026-11-03

### English
Bugfix release: restores unknown ETA sentinel, previously zeroed out by JSON clamping in 1.5.4. No changes to core features; suite advances to 57 tests.

#### Fixes
- **Unknown ETA**: `Torrent.init(from:)` no longer clamps `eta` to zero. The bridge emits
  `-1` when ETA cannot be computed (paused torrents, metadata retrieval, checking, or zero payload rate);
  clamping to zero caused the inspector to display "Completed" under "Time Remaining" for unfinished torrents.
  The sentinel remains `-1` (values below are mapped to `-1`) and the UI correctly displays "—".

#### Tests
- New test "Snapshot JSON Decoding: unknown ETA preserves -1": decodes a paused torrent and one without metadata, verifying that `eta` remains `-1` and `Fmt.eta` yields "—". Suite 57/57 passed.

### Italiano
Release di correzione: ripristina il sentinella dell'ETA sconosciuta, azzerato dal clamp
JSON introdotto nella 1.5.4. Nessuna modifica alle funzioni principali; la suite passa a
57 test.

#### Correzioni
- **ETA sconosciuta**: `Torrent.init(from:)` non clampa più `eta` a zero. Il bridge emette
  `-1` quando l'ETA non è calcolabile (torrent in pausa, in recupero metadati, in verifica
  o senza velocità di payload); con il clamp a zero l'inspector mostrava "Completato" in
  "Tempo rimasto" per torrent non finiti. Il sentinella resta `-1` (valori inferiori
  vengono riportati a `-1`) e la UI torna a mostrare "—".

#### Test
- Nuovo test "Snapshot JSON Decoding: ETA sconosciuta conserva -1": decodifica un torrent
  in pausa e uno senza metadati, verifica che `eta` resti `-1` e che `Fmt.eta` restituisca
  "—". Suite 57/57.

## [1.5.5] — 2026-11-03

### English
#### Fixes
- **Asynchronous errors**: `last_error` remains reserved for synchronous operations;
  `add_torrent`/`torrent_error` use `last_alert_error`, exposed in snapshot as `alert_error`
  and displayed once by the UI without overwriting current error state.
- **Paste magnet**: if clipboard does not contain a magnet link, only the add dialog opens without redundant error toast.
- **Configuration**: preference validation executes once on launch; `currentConfiguration()` only reads.
  Settings are applied only when modified, and save path is touched only when changed.
- **Paths**: Swift utilizes `vt_normalize_save_path`, matching C++ engine normalization (trim, `~`, file/`.torrent`, fallback).

#### Performance
- **Torrent list**: exclusive category is computed once per torrent; filtering and counting remain single-pass.
- **Details**: file progress uses libtorrent piece granularity (`piece_granularity`), lighter than per-block estimates.
- **Idle polling**: state publication is skipped when `PollState` is unchanged and details refresh every 15 polls instead of every 3; history uses a single helper.

#### Maintenance
- **Build**: `--show-bin-path` is queried after the single build step, avoiding a second compilation pass.
- **C++ bridge**: single macro for the catch/`last_error` contract.
- **Scripts**: shared `macho_dependencies` and `macho_rpaths` in `Scripts/lib/macho.sh`, used by `build.sh`, `build-deps.sh`, and `verify-bundle.sh`.
- **CI**: dependency cache key includes `Scripts/app.env` and `Scripts/lib/macho.sh`.
- **UI**: `Typography` scale and replacement of 89 repeated hardcoded fonts; verified demo screenshots for Settings and Diagnostics.

### Italiano
#### Correzioni
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

#### Prestazioni
- **Lista torrent**: la categoria esclusiva viene calcolata una volta per torrent;
  filtro e conteggi restano in una sola passata.
- **Dettaglio**: il progresso dei file usa la granularità pezzo di libtorrent
  (`piece_granularity`), più economica delle stime per blocco.
- **Poll in idle**: la pubblicazione è saltata quando `PollState` non cambia e il
  dettaglio si aggiorna ogni 15 poll invece di ogni 3; la history usa un helper unico.

#### Manutenzione
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

### English
#### Security
- **Preferences**: `validateAllPreferences()` verifies port, speed limits, bind address,
  appearance, and download path on launch. Corrupted plists or migration bugs leaving out-of-range
  values are reset to defaults before the engine reads them, preventing broken configurations from launching the session.
- **JSON decoding**: `Torrent.init(from:)` clamps `progress` to [0,1] and counters to non-negative values
  before reaching the UI and sorting pipeline.
- **UTF-8**: `is_valid_utf8` validates strings prior to `json_escape`, preventing undecodable JSON in Swift.
- **Tests**: test coverage for preferences validation on startup.

### Italiano
#### Sicurezza
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

### English
#### Security
- **Bind address**: `isValidIPv4` rejects `0.0.0.0`, loopback (`127.x`), link-local (`169.254.x`),
  shortened forms (`192.168.1`), and leading zeros (`192.168.001.001`): only canonical literal addresses bind the engine.
- **Magnet**: `vt_add_magnet` rejects magnet URIs exceeding 8 KiB before passing to libtorrent.
- **Torrent files**: `vt_add_torrent_file` canonicalizes paths, verifies regular file status, and caps size at 10 MiB before loading.

### Italiano
#### Sicurezza
- **Bind address**: `isValidIPv4` rifiuta ora `0.0.0.0`, loopback (`127.x`),
  link-local (`169.254.x`), forme corte (`192.168.1`) e leading zeros
  (`192.168.001.001`): solo indirizzi letterali e canonici vincolano l'engine.
- **Magnet**: `vt_add_magnet` rifiuta URI magnet superiori a 8 KiB prima di
  passarli a libtorrent.
- **File torrent**: `vt_add_torrent_file` canonicalizza il percorso, verifica
  che sia un file regolare e ne cappa la dimensione a 10 MiB prima del caricamento.

## [1.5.2] — 2026-11-02

### English
#### Security
- **vt_control**: the `action` string incoming from the Swift layer is mapped to an
  `enum class ControlAction` (explicit allowlist) and handled via exhaustive `switch`.
  Any unrecognized action is rejected as `unknown`. Removed `if/else` chain vulnerable to command injection.

### Italiano
#### Sicurezza
- **vt_control**: la stringa `action` in arrivo dal layer Swift viene mappata a un
  `enum class ControlAction` (allowlist esplicita) e gestita tramite `switch`
  esaurivo. Ogni stringa non riconosciuta viene rifiutata come `unknown`. Rimossa
  la catena `if/else` vulnerabile a command injection.

## [1.5.1] — 2026-11-02

### English
#### Fixes
- **Network**: `LocalNetwork` applies identical exclusion rules (loopback and link-local `169.254.x.x`)
  both to binding selection and diagnostics, ensuring unusable addresses never leak into either list.
- **Engine**: `lastAppliedPollID` counter resets when sessions are recreated (e.g. on PEX toggles),
  keeping stale poll guards effective rather than relying on global monotonic counters.
- **Bridge**: `find_handle` resolves SHA-1 ids in O(1) via `session::find_torrent` instead of iterating
  over all torrents and formatting hex strings; V2 hashes (64 hex characters) use general lookup.
- **Bridge**: `removed_ids` maintains an `unordered_set` alongside the deque, ensuring O(1) membership checks and removals.

#### Deduplication
- **UI**: `SegmentedPicker` is now a generic component under `Sources/VertexKit/Design/SegmentedPicker.swift`,
  reused across the three views where it was previously duplicated (InspectorView, SettingsSheet, AddTorrentSheet).
- **Preferences**: `currentConfiguration()` writes to `UserDefaults` only when normalization actually alters values, not on every call.
- **State**: libtorrent codes `1`/`2`/`7` are replaced by `LibtorrentStateCode` enum in `Models.swift`, utilized in both `Torrent.phase` and completion toasts.

#### Performance
- **Idle polling**: `PollState` conforms to `Equatable`; polling skips publication when payload is identical to prior state; chart history stops appending during idle.
- **Settings**: `vt_set_default_save_path` is called only when download folder changes, avoiding redundant `create_directories` + `access(W_OK)` syscalls on unrelated field changes.

#### Documentation
- `HANDOFF.txt` §17 synchronized with technical debt state: 12 entries marked resolved or partially resolved.

#### Tests
- 55 tests, all passed.

### Italiano
#### Correzioni
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

#### Duplicazione
- **UI**: `SegmentedPicker` è ora un componente generico in
  `Sources/VertexKit/Design/SegmentedPicker.swift`, riutilizzato dalle tre viste
  che lo avevano duplicato (InspectorView, SettingsSheet, AddTorrentSheet).
- **Preferenze**: `currentConfiguration()` scrive su `UserDefaults` solo quando la
  normalizzazione modifica effettivamente il valore, non a ogni chiamata.
- **Stato**: i codici libtorrent `1`/`2`/`7` sono sostituiti dall'enum
  `LibtorrentStateCode` in `Models.swift`, usato sia in `Torrent.phase` sia nel
  toast di completamento.

#### Prestazioni
- **Poll in idle**: `PollState` è `Equatable` e il poll salta la pubblicazione
  quando il payload è identico a quello precedente; gli storici dei grafici
  si fermano in idle invece di appendere a ogni poll.
- **Impostazioni**: `vt_set_default_save_path` viene chiamato solo quando la
  cartella di download è cambiata, evitando un syscall `create_directories` +
  `access(W_OK)` a ogni debounce di un campo non correlato.

#### Documentazione
- `HANDOFF.txt` §17 sincronizzato con lo stato reale del debito tecnico: 12 voci
  segnate come risolte o parzialmente risolte dai punti precedenti.

#### Test
- 55 test, tutti superati.

## [1.5.0] — 2026-10-30

### English
#### Additions
- **Binding to local address**: new "Network Interface" setting binds the engine to a single IPv4 address,
  configuring both `listen_interfaces` and `outgoing_interfaces`. libtorrent drops incoming traffic on other interfaces,
  enabling client usage behind CGNAT with WireGuard tunnels and VPS port forwarding.
- Diagnostics: displays bound address and reports `listen_failed_alert` messages when binding fails (e.g. tunnel inactive).
  The client does not fall back to other interfaces.
- Bridge: `vt_session_create_full` and `vt_apply_settings_ex` accept `bind_address`; snapshot exposes `bind_address` and `listen_error`.
- Status bar: port icon switches to a shield badge when bound to an address.

#### Tests
- 55 tests, all passed: local address binding, unavailable address error handling, dynamic binding removal, preference normalization, and bound diagnostics rendering.

### Italiano
#### Aggiunte
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

#### Test
- 55 test, tutti superati: ascolto su un indirizzo locale, errore su un indirizzo non
  disponibile, rimozione dell'associazione a caldo, normalizzazione della preferenza e
  rendering della diagnostica associata.

## [1.4.0] — 2026-10-28

### English
#### Changes
- Exclusive list filters: each torrent belongs to a single category, with "Paused" taking precedence;
  a seeding torrent is no longer double-counted in "Completed".
- Diagnostics: `vt_set_file_priority` validates index and priority, `vt_apply_settings_ex` and priority catch-alls populate `last_error`, tracker statistics support V2.
- Deduplication: centralized magnet/.torrent input handling, drag-and-drop, picker panels, portmap state, path normalization, and modal chromes.
- Performance: all `vt_*` bridge calls route through a serial queue; polling no longer blocks MainActor and stale poll results are dropped.
- Cleanup: removed unused forward declarations, parameters, and plist keys; build hashes computed once; shared helpers for test stubs.
- Tests: load smoke test with 5,000 synthetic torrents and 100 consecutive polls.

### Italiano
#### Modifiche
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

### English
Maintenance release focused on snapshot payload optimization and polling overhead. No changes to core features; automated test suite remains at 51 tests.

#### Maintenance
- Lighter snapshot: removed `state`, `files`, `total_download`, and `total_upload` fields never read by UI. State uses `state_code` and file count comes from details.
- Polling: removed `query_torrent_file` and per-torrent `torrent_file` locks; `find_handle` directly uses info hashes.
- Magnet: URI constructed from minimal `add_torrent_params` without serializing resume data.
- Resume: directory created once and recreated only if saving fails.
- UI: `DotGrid` caches paths by dimension; filtering and counters calculated in a single pass.
- Cleanup: removed unused parameters, unused callbacks, redundant `#if DEBUG` branches, and test warnings.
- Build: `build.sh` verifies `Info.plist` and `Scripts/app.env` declare matching minimum macOS versions.

### Italiano
Release di manutenzione focalizzata sul payload dello snapshot e sul costo del
polling. Nessuna modifica alle funzioni principali; la suite automatica resta a
51 test.

#### Manutenzione
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

### English
Maintenance release: no changes to core features, but reduced duplication in UI state, C++ bridge, and build scripts. Automated suite advances to 51 tests.

#### Maintenance
- Single source of truth for preferences (`PrefDefault`) shared by defaults registration, `@AppStorage`, and theme.
- Unified UI state: torrent selection in engine, modals in single `ActiveModal`, polling snapshots in unified `PollState`, and single-pass filter counts.
- Debounced settings application with immediate flush on panel dismissal.
- Filtering, search, and sorting pipeline moved to models and covered by unit tests.
- C++ bridge: shared helpers for torrent addition, network settings, and port mapping reset; removed `vt_session_create`, `vt_session_create_ex`, and `vt_apply_settings` in favor of `vt_session_create_full` and `vt_apply_settings_ex`.
- Application parameters centralized in `Scripts/app.env` and consumed by build, DMG creation, bundle verification, and CI. New localization parity check in CI.
- Removed dead code and unused APIs; aligned README and fixtures.

#### Tests
- New `EngineTests` suite with isolated libtorrent sessions: magnet and file additions, selection and details, file priorities, pause/resume, commands on removed torrents, PEX session restart, and asynchronous shutdown.
- Targeted test for cleared detail view when torrent reading fails or stale responses arrive.
- New `PortReachabilityTests` suite with injected HTTP loader: open and closed ports, HTTP errors, invalid services, missing nodes, partial timeouts, resets, empty IP, non-HTTP responses, and malformed payloads.
- Headless rendering of critical SwiftUI views via `ImageRenderer`, extended to `RootView`, top bar and filters, empty states, no results, and drop overlays.
- New `AppCommandsTests` suite: verifies command → notification mapping, filter payloads, `NotificationCenter` posting, `RootView` notification routing, and menu bar tree construction.
- Headless rendering variants of `RootView` with settings, diagnostics, add sheets, removal confirmations, details, drop overlays, empty search results, and filters. Network diagnostics rendered in mapped, partially errored, unmapped, and global error UPnP/NAT-PMP states.
- UPnP/NAT-PMP smoke test executed only when `VERTEX_TEST_UPNP=1` (configured in CI): does not require actual router mapping and validates snapshot consistency. Locally the gate remains closed, creating no router port mappings.
- Test hooks and suites available exclusively in DEBUG: release builds remain untouched.

### Italiano
Release di manutenzione: nessuna modifica alle funzioni principali, ma meno
duplicazione nello stato dell'interfaccia, nel bridge C++ e negli script di
build. La suite automatica passa a 51 test.

#### Manutenzione
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

#### Test
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

### English
Minor stabilization release for user interface and network diagnostics.

#### Fixes
- Details panel no longer retains stale data when reading updated torrent information fails: resets to empty state rather than displaying obsolete values.
- UPnP and NAT-PMP port mapping errors are separated for TCP and UDP, explicitly indicating the transport protocol that triggered them. Successful mapping on one protocol no longer clears errors from the other.
- Default download folder for C++ session updates immediately when changed in preferences, ensuring torrents added without explicit path and resume data restores use the current destination.

#### Tests
- Added separate error decoding for TCP and UDP port mapping errors.
- Added C++ bridge test for default save path updates and its application when adding magnet links without destination.

### Italiano
Piccola release di stabilizzazione dell'interfaccia e della diagnostica di rete.

#### Corretto
- Il pannello dettagli non mantiene più i dati del torrent selezionato quando la lettura
  aggiornata fallisce: viene svuotato invece di mostrare informazioni obsolete.
- Gli errori di mappatura UPnP/NAT-PMP sono separati per TCP e UDP e indicano il trasporto
  che li ha prodotti. Un mapping riuscito non cancella più l'errore dell'altro protocollo.
- La cartella di download predefinita della sessione C++ viene aggiornata quando cambia
  nelle preferenze, così anche i torrent aggiunti senza percorso esplicito e il
  caricamento dei resume data usano la destinazione corrente.

#### Test
- Aggiunta la decodifica degli errori di mappatura separati per TCP e UDP.
- Aggiunto un test del bridge per l'aggiornamento della cartella di salvataggio
  predefinita e per il suo uso nell'aggiunta di un magnet senza destinazione.

## [1.3.6] — 2026-10-27

### English
Bugfix release for libtorrent session lifecycle and network settings validation.

#### Fixes
- Session destruction (PEX toggle and app termination) no longer runs on the main thread: saving resume data no longer blocks the UI for up to 3 seconds.
- PEX toggles recreate the session in the background; if the new session fails to start, Vertex restores the previous setting and session when possible.
- Port and speed limits are validated before application. Invalid values are rejected and trigger error messages.
- Errors returned by `vt_apply_settings_ex` are no longer ignored.
- Diagnostics displays DHT as disabled when the corresponding toggle is off.
- Updated startup error message: no longer references external libtorrent installations, which are bundled.

#### Tests
- Added validation for KB/s speed limits and port numbers.
- Added integration test for resume data reloading after PEX toggle.

### Italiano
Release di correzione per il ciclo di vita della sessione libtorrent e la validazione
delle impostazioni di rete.

#### Corretto
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

#### Test
- Aggiunta la validazione dei limiti KB/s e delle porte.
- Aggiunto un test d'integrazione per il ricaricamento del resume dopo un cambio PEX.

## [1.3.5] — 2026-10-26

### English
Release dedicated to discovery feature controls and CI infrastructure update to Node.js 24.

#### Fixes
- Separated controls for DHT, Peer Exchange, and Local Service Discovery.
- PEX toggle now genuinely enables or disables the `ut_pex` extension by recreating the libtorrent session with resume data, rather than solely toggling `enable_dht`.
- Added LSD toggle, dynamically applied via `enable_lsd`.

#### CI
- Updated GitHub Actions to versions running Node.js 24 runtime (`checkout` 7.0.1, `cache` 6.1.0, `upload-artifact` 7.0.2, `download-artifact` 8.0.2), removing Node.js 20 deprecation notices.

### Italiano
Release dedicata al controllo delle funzioni di discovery e all'aggiornamento
dell'infrastruttura CI a Node.js 24.

#### Corretto
- Separati i controlli DHT, Peer Exchange e Local Service Discovery.
- Il toggle PEX ora abilita o disabilita realmente l'estensione `ut_pex` ricreando la
  sessione libtorrent con resume data, invece di limitarsi a cambiare `enable_dht`.
- Aggiunto il toggle LSD, applicato a caldo tramite `enable_lsd`.

#### CI
- Aggiornate le GitHub Actions a versioni con runtime Node.js 24
  (`checkout` 7.0.1, `cache` 6.1.0, `upload-artifact` 7.0.2,
  `download-artifact` 8.0.2), eliminando gli avvisi di deprecazione di Node.js 20.

## [1.3.4] — 2026-10-26

### English
Release focused on integration testing, coverage reporting, and reproducible build toolchains in matching CI environments.

#### Documentation
- Clarified reproducibility scope: pinned dependency source code and canonical build produced by CI, without claiming bit-for-bit identical app or DMG binaries on arbitrary machines. Local DMG builds are not directly comparable to published assets.

#### Tests
- Added deterministic loopback integration tests with two libtorrent sessions: v1/v2 transfers, pause/resume, resume after restart, file priorities, removal with `delete_files`, multiple torrents, and failure paths.
- Added v1/v2 torrent fixtures in `Tests/Fixtures`, without external trackers or networks.
- `./build.sh test` produces JUnit reports (`dist/test-results.xml`) and LLVM/LCOV coverage (`dist/coverage/`); CI uploads both artifacts.
- Pause/resume test verifies state transitions without depending on local peer reconnection, preventing timeouts on slower CI runners.

#### Build & CI
- Added `Scripts/toolchain.env` with canonical Xcode, CMake, macOS, and runner image versions.
- Added `Scripts/check-toolchain.sh`: CI uses `--strict` mode on release tags and reports discrepancies on development builds.
- CI explicitly selects Xcode 16.4 and no longer installs unversioned CMake; cached dependencies are invalidated on toolchain changes.
- Pinned GitHub Actions to immutable SHAs.

### Italiano
Release focalizzata su test d'integrazione, report coverage e toolchain di build
riproducibile a parità di ambiente CI.

#### Documentazione
- Chiarita la portata della riproducibilità: sorgenti delle dipendenze fissati e build
  canonica prodotta dalla CI, senza la promessa di app o DMG identici bit-per-bit su
  macchine arbitrarie. Una DMG locale non è confrontabile con l'asset pubblicato.

#### Test
- Aggiunti test d'integrazione deterministici su loopback con due sessioni libtorrent:
  trasferimenti v1/v2, pausa/ripresa, resume dopo riavvio, priorità file, rimozione con
  `delete_files`, torrent multipli e failure path.
- Aggiunte fixture torrent v1/v2 in `Tests/Fixtures`, senza tracker o rete esterna.
- `./build.sh test` produce ora un report JUnit (`dist/test-results.xml`) e coverage
  LLVM/LCOV (`dist/coverage/`); la CI carica entrambi gli artefatti.
- Il test pausa/ripresa verifica la transizione di stato senza dipendere dalla
  riconnessione del peer locale, evitando un timeout su runner CI più lenti.

#### Build e CI
- Aggiunto `Scripts/toolchain.env` con Xcode, CMake, macOS e immagine runner canonici.
- Aggiunto `Scripts/check-toolchain.sh`: la CI usa la modalità `--strict` sui tag di
  release e segnala le differenze sulle build di sviluppo.
- La CI seleziona esplicitamente Xcode 16.4 e non installa più CMake senza versione
  fissata; le dipendenze in cache vengono invalidate quando cambia il toolchain.
- Le GitHub Actions sono fissate a SHA immutabili.

## [1.3.3] — 2026-10-25

### English
#### Additions
- Pinned engine dependencies built from source: `Scripts/deps.env` pins libtorrent 2.1.2, OpenSSL 3.5.9, and Boost 1.92.0 with SHA-256 checksums.
- `Scripts/build-deps.sh` builds dependencies from source targeting macOS 15.0 and installs them into `.build/vertex-deps`; Homebrew bottles are no longer used.
- `Scripts/verify-bundle.sh` verifies bundle self-sufficiency: zero Homebrew dependencies or build paths, presence of all bundled dylibs, `minos` matching `Info.plist`, uniform architecture, and valid code signature. Executed by `build.sh`, `make-dmg.sh`, and CI.
- C++ bridge tests decode real JSON snapshots with `VertexSnapshot` in addition to verifying libtorrent session lifecycle.
- Tag-driven CI/CD workflow: pushes to `main` build verified artifacts; only `v*` tags trigger GitHub Releases. Published release assets are never overwritten.

#### Changes
- Minimum deployment target bumped to **macOS 15.0** across `Package.swift`, `Info.plist`, README, CI, and packaging scripts.
- `build.sh` copies full dylib closure for the engine and rewrites paths generically without hardcoded OpenSSL versions.
- `make-dmg.sh` verifies bundle integrity both before creating DMG and after mounting it.
- CI runner updated to `macos-15`, with cache for pinned dependencies.
- Updated `THIRD_PARTY_NOTICES.md` and licensing for OpenSSL 3.5.x.

#### Fixes
- macOS 14 DMG from 1.3.2 could link Homebrew OpenSSL 3 or contain dylibs targeting macOS 27. Bundle verification blocks both issues.

### Italiano
#### Aggiunto
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

#### Modificato
- Requisito minimo portato a **macOS 15.0** in `Package.swift`, `Info.plist`, README,
  CI e script di packaging.
- `build.sh` copia l'intera chiusura delle dylib del motore e riscrive i percorsi in
  modo generico, senza versioni hardcoded di OpenSSL.
- `make-dmg.sh` verifica il bundle sia prima di creare la DMG sia dopo averla montata.
- Runner CI aggiornato a `macos-15`, con cache delle dipendenze fissate.
- `THIRD_PARTY_NOTICES.md` e le licenze aggiornati a OpenSSL 3.5.x.

#### Corretto
- Il DMG macOS 14 della 1.3.2 poteva dipendere da OpenSSL 3 di Homebrew, oppure
  contenere dylib compilate per macOS 27. La nuova verifica blocca entrambi i casi.

## [1.3.2] — 2026-10-25

### English
#### Additions
- Automated versioned test runner (`VertexTestRunner`, executable via `./build.sh test`) covering formatters, models, snapshot JSON deserialization, preferences, and `CTorrent` C++ bridge lifecycle.
- GitHub Actions CI/CD workflow running on `macos-14` (Apple Silicon M1) runner building, testing, and verifying bundle integrity on every commit and pull request.
- Modular architecture with `VertexKit` library target and `package` access level in SwiftPM.
- Quick local test command: `./build.sh test`.

#### Changes
- Minimum deployment target set to macOS 14.0 in `Package.swift`.
- Explicitly set `TORRENT_ABI_VERSION=2` for C++ bridge compilation.

### Italiano
#### Aggiunto
- Suite di test automatica versionata (`VertexTestRunner`, eseguibile con `./build.sh test`)
  che copre formattatori, modelli, deserializzazione snapshot JSON, preferenze e ciclo vitale
  del bridge C++ `CTorrent`.
- Workflow di CI/CD con GitHub Actions su runner `macos-14` (Apple Silicon M1) che compila,
  esegue i test e valida l'integrità del bundle ad ogni commit e pull request.
- Architettura modulare con il target libreria `VertexKit` e visibilità `package` in SwiftPM.
- Comando `./build.sh test` per l'esecuzione rapida dei test locali.

#### Modificato
- Deployment target minimo configurato su macOS 14.0 in `Package.swift`.
- Impostato esplicitamente `TORRENT_ABI_VERSION=2` per la compilazione del bridge C++.

## [1.3.1] — 2026-10-24

### English
#### Additions
- Application version and build number displayed in window header, under Settings → About, and in About Vertex dialog.

#### Fixes
- Newly added torrents no longer start in paused state when "Start paused" option is disabled: libtorrent's `add_torrent_params::default_flags` includes `paused`; the bridge now explicitly clears this flag when pause is not requested.

### Italiano
#### Aggiunto
- La versione dell’app (versione e build) è visibile nell’intestazione, in Impostazioni →
  Informazioni e nel pannello Informazioni su Vertex.

#### Corretto
- I nuovi torrent non partono più in pausa quando l’opzione “Avvia in pausa” è disattivata:
  `add_torrent_params::default_flags` di libtorrent include `paused`; ora il bridge lo
  azzera esplicitamente quando la pausa non è richiesta.

## [1.3.0] — 2026-10-23

### English
#### Additions
- Bilingual user interface: Italian when system language is Italian, English for all other system languages (with fallback to English). UI strings, engine messages, errors, formats, and document names localized via `Localizable.strings` and `InfoPlist.strings`.
- Documentation: English README (`README.md`, default on GitHub) and Italian README (`README.it.md`), with language switching links.

#### Fixes
- Ports and counts no longer use thousands grouping separators; settings numeric fields do not display number grouping.

### Italiano
#### Aggiunto
- Interfaccia bilingue: italiano se il sistema è in italiano, inglese per qualsiasi altra
  lingua (con fallback sull’inglese). Sono localizzati testi della UI, messaggi del motore,
  errori, formati e nomi dei documenti tramite `Localizable.strings` e `InfoPlist.strings`.
- Documentazione: README in inglese (`README.md`, predefinito su GitHub) e in italiano
  (`README.it.md`), con link per cambiare lingua.

#### Corretto
- Porte e conteggi non usano più il separatore delle migliaia; il campo numerico delle
  Impostazioni non mostra raggruppamenti.

## [1.2.3] — 2026-10-22

### English
#### Fixes
- Network diagnostics: port mapping error on one transport protocol no longer resets port mapping on the other. UPnP and NAT-PMP indices both restart from 0, so mapping matching now compares both transport and index.
- Progress bar and ETA no longer stutter with large piece sizes: snapshot queries `query_accurate_download_counters` again.
- Opening a magnet link or `.torrent` file while the application is already running no longer opens a second window: main scene is a single `Window` rather than a `WindowGroup`.
- `⌘P` and `⌘⌫` shortcuts no longer trigger on the first torrent when nothing is selected, do not trigger behind Settings/Diagnostics/Add sheets, and show an alert if no torrent is selected.
- `build.sh` no longer ignores `codesign` errors, signs dylibs and the app without `--deep`, and validates bundle integrity.
- Port reachability probe sends `Vertex/<version>` as User-Agent instead of `Vertex/1.1`.

### Italiano
#### Corretto
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

### English
#### Fixes
- Session retains metadata across restarts: resume data now includes info dict (`save_info_dict`). Previously, torrents added from files returned without metadata (0 size, no files) until re-fetched; paused torrents remained without metadata.
- Temporary toast notifications remain visible above Settings and Diagnostics sheets.
- Settings (⌘,) opens properly even when the Network Diagnostics sheet is already open.

#### Changes
- Lighter polling: torrent status is requested once per poll and only for active fields, without pieces/verified pieces or distributed copies estimates.
- Removed torrents list waiting for late alerts is capped (256-entry FIFO).
- `make-dmg.sh` unmounts DMG and cleans up staging directory even on build failures.
- Drag & drop updated to `loadObject(ofClass:)`: zero deprecation warnings on macOS 27.

### Italiano
#### Corretto
- La sessione riprende i metadati dopo il riavvio: il resume data include ora l’info dict
  (`save_info_dict`). Prima i torrent aggiunti da file tornavano senza metadati (dimensione 0,
  nessun file) fino a un nuovo recupero; i torrent in pausa restavano senza metadati.
- I messaggi temporanei (toast) restano visibili sopra i pannelli Impostazioni e Diagnostica.
- Impostazioni (⌘,) si apre correttamente anche con il pannello Diagnostica aperto.

#### Modificato
- Polling più leggero: lo stato dei torrent viene richiesto una sola volta per poll e solo
  per i campi usati, senza pieces/verified pieces né stime di copie distribuite.
- La lista dei torrent rimossi in attesa di alert tardivi è limitata (FIFO da 256 voci).
- `make-dmg.sh` smonta la DMG e rimuove lo staging anche in caso di errore.
- Drag & drop aggiornato a `loadObject(ofClass:)`: nessun warning di deprecazione su macOS 27.

## [1.2.1] — 2026-10-22

### English
#### Fixes
- Network diagnostics: displayed and copied endpoint uses mapped external port when available, rather than solely local port.
- UPnP/NAT-PMP port mapping: error on one mapping no longer resets the other protocol; matching occurs by mapping index.
- More robust local IP detection: excludes virtual/tunnel interfaces and link-local addresses, correctly identifies RFC 1918 range.
- Completion toast: checking torrents are no longer counted as active for completion toasts, even when paused.

### Italiano
#### Corretto
- Diagnostica rete: l’endpoint visualizzato e copiato usa la porta esterna mappata quando
  disponibile, non solo la porta locale.
- Mapping UPnP/NAT-PMP: un errore su un mapping non azzera più anche l’altro protocollo;
  il matching avviene tramite l’indice del mapping.
- Rilevamento IP locale più robusto: escluse interfacce virtuali/tunnel e link-local,
  intervallo RFC 1918 corretto.
- Completamento: i torrent in verifica non vengono più conteggiati come attivi per il
  toast, anche quando sono in pausa.

## [1.2] — 2026-10-22

### English
#### Additions
- **Network Diagnostics** panel with actual port, local IP, UPnP/NAT-PMP status, and external TCP reachability testing via check-host.net.
- Access to diagnostics from status bar port button, from Settings → Network, and via `⌘⇧D`.
- CGNAT notice and instructions for port forwarding / UPnP in diagnostics panel.
- C++ bridge exposes effective port, listening state, and UPnP/NAT-PMP mapping status.

#### Changes
- Saved UPnP/NAT-PMP setting applied on launch.
- README and release notes updated with network diagnostics.

### Italiano
#### Aggiunto
- Pannello **Diagnostica rete** con porta effettiva, IP locale, stato UPnP/NAT-PMP e test TCP
  di raggiungibilità esterna tramite check-host.net.
- Accesso alla diagnostica dalla porta nella barra di stato, da Impostazioni → Rete e con `⌘⇧D`.
- Avviso CGNAT e istruzioni per port forwarding / UPnP nel pannello.
- Il bridge espone porta effettiva, stato di ascolto e mapping UPnP/NAT-PMP.

#### Modificato
- L’impostazione UPnP/NAT-PMP salvata viene applicata all’avvio.
- README e note di release aggiornati con la diagnostica di rete.

## [1.1] — 2026-10-21

### English
#### Additions
- Handling of `magnet:` links opened from browser or Finder, with URI scheme registration.
- Bring application to foreground when receiving an external link.

#### Fixes
- Late resume alerts no longer recreate files of deleted torrents, including during shutdown.
- Resume button clears error state prior to restarting torrents.
- Clearer message for already existing torrents.
- "Download completed" toast no longer displays for torrents already complete at launch.
- Speed limits and listening port validated to prevent overflows and invalid values.
- Details panel no longer redraws unnecessarily on every poll.

#### Changes
- Destination folder, start paused, and sequential download options in add sheet apply only to current torrent; defaults remain in Settings.
- Optimized details panel updates.

### Italiano
#### Aggiunto
- Gestione dei link `magnet:` aperti dal browser o dal Finder, con registrazione dello schema.
- Apertura dell'app in primo piano quando arriva un link esterno.

#### Corretto
- Gli alert di resume tardivi non ricreano più i file dei torrent rimossi, nemmeno durante la chiusura.
- Il pulsante Riprendi azzera lo stato di errore prima di riavviare un torrent.
- Messaggio più chiaro per i torrent già presenti.
- Il toast “Download completato” non viene più mostrato per torrent già completi al lancio.
- I limiti di velocità e la porta di ascolto vengono validati per evitare overflow e valori non validi.
- Il pannello dettagli non viene più ridisegnato inutilmente a ogni poll.

#### Modificato
- Cartella di destinazione, avvio in pausa e download sequenziale nella finestra di aggiunta valgono solo per il torrent corrente; i default restano nelle Impostazioni.
- Aggiornamento del pannello dettagli ottimizzato.

## [1.0] — 2026-10-21

### English
- Initial public release of Vertex: native macOS BitTorrent client powered by libtorrent 2.1,
  featuring magnet/`.torrent` handling, search, filters, resume data, file priorities, trackers,
  speed limits, and light/dark/system themes.

#### Developer Notes
- `docs/swift6-and-typography.md` records measurements for Swift 6 migration
  (`-strict-concurrency=complete`: 45 warnings across 7 files, with order of work) and the roadmap
  for transitioning from fixed-point fonts to system text styles.
- `docs/queue-and-limits.md` contains the queue/limits design for torrents (recommended option:
  libtorrent auto-manager, highlighting the critical edge case of manually pausing a queued torrent)
  and invariants to verify. Unimplemented in this release.
- Release 1.9.2 does not alter data format: resume data and preferences remain compatible with 1.9.1.
  Keys `uiFilter`/`uiSort`/`uiSortAscending`/`uiInspectorWidth` are created on first use; default
  appearance switches to "System" only for new installations (existing user choices are preserved).

### Italiano
- Prima release pubblica di Vertex: client BitTorrent nativo per macOS con libtorrent 2.1,
  gestione magnet/file `.torrent`, ricerca, filtri, resume data, priorità dei file, tracker,
  limiti di velocità e tema chiaro/scuro/sistema.

#### Note per gli sviluppatori
- `docs/swift6-and-typography.md` registra la misura della migrazione a Swift 6
  (`-strict-concurrency=complete`: 45 warning in 7 file, con l'ordine di lavoro) e il piano
  per passare dai font a dimensione fissa ai text style di sistema.
- `docs/queue-and-limits.md` contiene il design della coda/limiti per torrent (opzione
  consigliata: auto-manager di libtorrent, con il punto critico della pausa manuale su un
  torrent in coda) e le invarianti da verificare. Non è implementata.
- La release 1.9.2 non cambia il formato dei dati: resume data e preferenze sono compatibili
  con la 1.9.1. Le chiavi `uiFilter`/`uiSort`/`uiSortAscending`/`uiInspectorWidth` vengono
  create al primo utilizzo; l'aspetto predefinito passa a "Sistema" solo per le installazioni
  nuove (chi ha già scelto un tema lo mantiene).

