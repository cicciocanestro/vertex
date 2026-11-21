# Changelog

## [1.17.6] — 2026-11-21

### English
- **Settings search**: a field above the settings rail filters sections by their localized title, ignoring case and accents; an empty query shows everything and a no-match query says so instead of leaving a blank rail.
- **Diagnostics checklist**: the network diagnostics window starts with a four-row summary (listening, UPnP/NAT-PMP, SOCKS5, DHT) with ok/warning/error/info status, so the first question ("is anything wrong?") is answered before the detailed cards.
- **Bridge mutation fuzzing**: the suite now throws 300 mutated magnets and 60 mutated `.torrent` files at a real session, keeping the snapshot decodable; it runs under the address/thread sanitizers in CI.
- **UI coverage**: render states for the empty library, loading, unavailable engine and success/error toasts, plus the two settings-search states. Line coverage 62.2% → 64.0% locally.
- **Flakes found by the stress harness**: the two-torrent setup waits for full progress (the seeding state can lag behind the piece check), the reachability tester reports a partial result after two stable polls instead of waiting for all 15, and the queue test asserts "one running, one queued" instead of which torrent wins the slot. `waitForCompletion` now has a 90s ceiling.
- **50-run stability**: `Scripts/stress-tests.sh` builds once and runs the suite 50 times; the run found and fixed the flakes above before turning green.

### Italiano
- **Ricerca nelle impostazioni**: un campo sopra il rail filtra le sezioni per titolo localizzato, ignorando maiuscole e accenti; una ricerca vuota mostra tutto e una senza risultati lo dice invece di lasciare il rail vuoto.
- **Checklist diagnostica**: la finestra di diagnostica rete inizia con un riepilogo a quattro righe (ascolto, UPnP/NAT-PMP, SOCKS5, DHT) con stato ok/attenzione/errore/info, così la prima domanda ("c'è qualcosa che non va?") ha risposta prima delle schede dettagliate.
- **Fuzz mutazionale del bridge**: la suite invia 300 magnet e 60 file `.torrent` mutati a una sessione reale, verificando che lo snapshot resti decodificabile; gira sotto i sanitizer ASan/TSan in CI.
- **Copertura UI**: stati di rendering per libreria vuota, caricamento, motore non disponibile e toast successo/errore, più i due stati della ricerca impostazioni. Copertura righe 62,2% → 64,0% in locale.
- **Flake trovati dallo stress harness**: il setup dei due torrent aspetta il progresso completo (lo stato seeding può arrivare dopo il check dei pezzi), il tester di raggiungibilità riporta un risultato parziale dopo due poll stabili invece di aspettare tutti e 15, e il test della coda verifica "uno attivo, uno in coda" invece di quale torrent vince lo slot. `waitForCompletion` ha ora un tetto di 90 s.
- **Stabilità su 50 run**: `Scripts/stress-tests.sh` compila una volta ed esegue la suite 50 volte; il ciclo ha trovato e fatto correggere i flake prima di diventare verde.

## [1.17.5] — 2026-11-21

### English
- **Settings sheet split**: the 1052-line file is now a 73-line shell plus content (436), rows (432) and models (137) files, all under 800 lines; no behavior change, all sections still rendered by the suite.
- **Stability harness**: `Scripts/stress-tests.sh N` runs the whole suite repeatedly, keeping logs in `.build/stress`; 20 consecutive runs were green locally (100 tests each), on top of the TSan/ASan jobs in CI.
- **IPv6 country flags**: the bundled DB-IP Lite data now includes IPv6 (369,798 ranges, 479 KB). Endpoints are parsed with `inet_pton`; private/ULA, link-local, multicast and IPv4-mapped addresses are handled, and the inspector shows the flag for IPv6 peers too.
- **Repository hygiene**: `Models.swift` is split into `TorrentModels`, `SessionModels` and `ListModels`; a `.swift-format` baseline (4 spaces, 120 columns, multiline strings untouched) is enforced in CI with `--strict`; release notes older than 1.11.0 moved to `CHANGELOG-archive.md`; the stale Swift 6 report and the unused `captionSemiboldText` token are gone.
- **Tap automation without a PAT**: the Homebrew tap repository now has an hourly workflow that reads the latest Vertex release with its own token and updates `Casks/vertex.rb` (version + checksum). The optional step in the Vertex release job remains for immediate updates when `HOMEBREW_TAP_TOKEN` is configured.

### Italiano
- **SettingsSheet diviso**: il file da 1052 righe ora è uno shell da 73 più content (436), rows (432) e models (137), tutti sotto le 800 righe; nessun cambio di comportamento, tutte le sezioni restano renderizzate dalla suite.
- **Harness di stabilità**: `Scripts/stress-tests.sh N` esegue la suite ripetutamente, con log in `.build/stress`; 20 run consecutivi verdi in locale (100 test ciascuno), oltre ai job TSan/ASan della CI.
- **Bandiere IPv6**: i dati DB-IP Lite inclusi ora coprono anche IPv6 (369.798 range, 479 KB). Gli endpoint sono interpretati con `inet_pton`; indirizzi privati/ULA, link-local, multicast e IPv4-mapped sono gestiti, e l'inspector mostra la bandiera anche per i peer IPv6.
- **Igiene del repository**: `Models.swift` è diviso in `TorrentModels`, `SessionModels` e `ListModels`; una baseline `.swift-format` (4 spazi, 120 colonne, stringhe multiriga intatte) è imposta in CI con `--strict`; le note di release precedenti alla 1.11.0 sono in `CHANGELOG-archive.md`; rimossi il report obsoleto su Swift 6 e il token inutilizzato `captionSemiboldText`.
- **Tap automatico senza PAT**: il repository del tap Homebrew ha ora un workflow orario che legge l'ultima release di Vertex con il proprio token e aggiorna `Casks/vertex.rb` (versione + checksum). Lo step opzionale nel job di release di Vertex resta per l'aggiornamento immediato quando `HOMEBREW_TAP_TOKEN` è configurato.

## [1.17.4] — 2026-11-21

### English
- **Fuzzing beyond escaping**: the harness now also checks save-path normalization (trim, `~`, file→folder) and a deterministic Swift fuzzer feeds 10,000 mutated snapshot/detail payloads to the JSON decoders. 96 tests.
- **SBOM and dependency advisories**: `Scripts/generate-sbom.sh` emits a CycloneDX 1.5 SBOM from the same hashes `build-deps.sh` verifies; CI uploads it with every build and attaches it to releases. A weekly workflow queries OSV for the pinned versions and fails only on HIGH/CRITICAL findings (Boost 1.92.0 currently reports two low/medium OSS-Fuzz findings in modules Vertex does not use).
- **Stable signing**: the three signing secrets are configured, so CI builds and releases use the self-signed identity instead of ad-hoc. Gatekeeper still warns: removing that requires a Developer ID and notarization.

### Italiano
- **Fuzzing oltre l'escaping**: l'harness ora verifica anche la normalizzazione dei percorsi (trim, `~`, file→cartella) e un fuzzer Swift deterministico invia 10.000 payload mutati di snapshot/dettaglio ai decoder JSON. 96 test.
- **SBOM e avvisi sulle dipendenze**: `Scripts/generate-sbom.sh` produce un SBOM CycloneDX 1.5 dagli stessi hash verificati da `build-deps.sh`; la CI lo carica a ogni build e lo allega alle release. Un workflow settimanale interroga OSV per le versioni fissate e fallisce solo su HIGH/CRITICAL (Boost 1.92.0 ha due segnalazioni OSS-Fuzz low/medium in moduli che Vertex non usa).
- **Firma stabile**: i tre secret di firma sono configurati, quindi build e release CI usano l'identità self-signed invece della firma ad-hoc. Gatekeeper avvisa ancora: per toglierlo servono Developer ID e notarizzazione.

## [1.17.3] — 2026-11-21

### English
- **UI coverage**: the headless renderer now walks every settings section, the three inspector tabs with real trackers/peers, the row states (downloading, seeding, queued, error), the file-mode add sheet and an empty status bar. Line coverage rises from 56.1% to 62.2% locally, and the CI floor moves from 54.5% to 60.5%.

### Italiano
- **Copertura UI**: il renderer headless ora percorre tutte le sezioni delle impostazioni, i tre tab dell'inspector con tracker/peer reali, gli stati delle righe (download, seed, in coda, errore), la sheet di aggiunta in modalità file e una status bar vuota. La copertura righe sale dal 56,1% al 62,2% in locale e la soglia CI passa dal 54,5% al 60,5%.

## [1.17.2] — 2026-11-20

### English
- **Presentation logic leaves the views**: peer-flag labels, tracker input validation, file-priority labels and the diagnostics rules (UPnP disabled reason, external port to probe) now live in `Utilities/Presentation.swift` with unit tests. The inspector and the diagnostics window call the shared code instead of duplicating switches; the project's line coverage rises from 55.4% to 56.1% locally.
- **Fuzzing for the snapshot encoder**: `Fuzz/strings_fuzzer.cpp` drives `json_escape` and the RFC 3629 UTF-8 validator with the invariants the encoder relies on (no unescaped quote/backslash, no raw control bytes, output always valid UTF-8, plain ASCII unchanged). `Scripts/run-fuzz.sh` uses libFuzzer when the toolchain ships it and falls back to a seeded mutation driver under ASan/UBSan; CI runs it for 60 s on every non-tag build. Locally: 10.2 million mutations in 40 s with no violation.

### Italiano
- **La logica di presentazione esce dalle viste**: etichette dei flag peer, validazione del tracker, etichette delle priorità file e regole della diagnostica (motivo UPnP disattivato, porta esterna da testare) ora vivono in `Utilities/Presentation.swift` con test unitari. Inspector e diagnostica chiamano il codice condiviso invece di duplicare gli switch; la copertura righe sale dal 55,4% al 56,1% in locale.
- **Fuzzing per l'encoder dello snapshot**: `Fuzz/strings_fuzzer.cpp` esercita `json_escape` e il validatore UTF-8 RFC 3629 con gli invarianti su cui conta l'encoder (niente virgolette o backslash non escapati, niente byte di controllo grezzi, output sempre UTF-8 valido, ASCII semplice invariato). `Scripts/run-fuzz.sh` usa libFuzzer quando la toolchain lo include e altrimenti un driver mutazionale con ASan/UBSan; la CI lo esegue per 60 s su ogni build non di release. In locale: 10,2 milioni di mutazioni in 40 s senza violazioni.

## [1.17.1] — 2026-11-20

### English
#### Security & Reliability
- **Network leak test**: a loopback tracker stub and a SOCKS5 stub add a magnet whose only tracker is the direct stub, then assert that with the proxy enabled the tracker receives **zero** direct TCP connections while the proxy is contacted. The inverse run without a proxy requires the tracker to be reached, so the negative assertion cannot pass vacuously. This proves the fail-closed promise at the network level, not just at the bridge.
- **Sanitizers on every change**: the entire suite runs under ThreadSanitizer and AddressSanitizer in CI on every non-tag build (`Scripts/run-sanitizers.sh thread|address`). 91 tests pass under both; the pinned C++ dependencies stay uninstrumented on purpose, so the report covers the Swift code and the bridge we own.
- **DMG creation survives a busy runner**: `hdiutil create` intermittently returns "Resource busy" when another job is releasing a volume. The script retries three times with a short backoff instead of failing a green build.

#### Notes
- The snapshot benchmark keeps its p95 ceiling only outside sanitizers: instrumented builds measure the instrumentation (56 ms under ASan, 154 ms under TSan), not the poll.

### Italiano
#### Sicurezza e Affidabilità
- **Test di leak di rete**: un tracker su loopback e uno stub SOCKS5 aggiungono un magnet che ha come unico tracker lo stub diretto, poi verificano che con il proxy attivo il tracker riceva **zero** connessioni TCP dirette mentre il proxy viene contattato. L'esecuzione inversa senza proxy richiede che il tracker sia raggiunto, quindi l'asserzione negativa non può passare per caso. È la promessa fail-closed provata a livello di rete, non solo sul bridge.
- **Sanitizer su ogni modifica**: l'intera suite gira sotto ThreadSanitizer e AddressSanitizer in CI su ogni build non di release (`Scripts/run-sanitizers.sh thread|address`). 91 test passano con entrambi; le dipendenze C++ fissate restano volutamente non strumentate, così il report copre il codice Swift e il bridge nostro.
- **La DMG sopravvive a un runner occupato**: `hdiutil create` ogni tanto restituisce "Resource busy" mentre un altro job rilascia un volume. Lo script ritenta tre volte con un breve backoff invece di far fallire una build verde.

#### Note
- Il benchmark dello snapshot mantiene la soglia p95 solo fuori dai sanitizer: le build strumentate misurano la strumentazione (56 ms con ASan, 154 ms con TSan), non il poll.

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


## Archive

Le release dalla 1.10.2 in giù sono in [CHANGELOG-archive.md](CHANGELOG-archive.md).
