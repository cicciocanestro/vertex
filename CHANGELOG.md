# Changelog

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
