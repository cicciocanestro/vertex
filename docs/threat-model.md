# Modello di minaccia

Vertex è un client BitTorrent nativo che dichiara di non inviare telemetria.
Questo documento elenca cosa protegge, da chi e cosa resta fuori perimetro.

## Beni da proteggere

1. **Indirizzo IP dell'utente** verso peer, tracker e DHT.
2. **Contenuto dei download** e nomi dei file (rivelano interessi e abitudini).
3. **Password SOCKS5**, salvata nel Portachiavi o in un file `0600`.
4. **Integrità del bundle**: l'app distribuita non deve essere sostituita o
   modificata da terzi.

## Avversari

| Avversario | Capacità | Mitigazione |
|---|---|---|
| Peer malevoli nel swarm | Inviano messaggi BEP malformati, nomi con escape, metadati enormi | Parsing libtorrent, limiti sul `.resume`, escaping JSON nel bridge |
| Rete locale / ISP | Osserva connessioni in chiaro | Il proxy SOCKS5 è **fail-closed**: senza host la sessione non parte, non c'è fallback silenzioso; con il proxy attivo DHT e UPnP/NAT-PMP sono disattivati e un eventuale `bindAddress` assente blocca la sessione |
| Processo locale non privilegiato | Legge file nella home | Password in Portachiavi per default; file opzionale creato `0600` in una cartella forzata a `0700` anche se preesistente (con `O_DIRECTORY\|O_NOFOLLOW` + `fchmod`). La lettura usa `O_NOFOLLOW`, `fstat` e `fchmod` sul descrittore: un symlink viene ignorato e il file puntato non viene né letto né modificato; dichiarato non cifrato |
| Sito che distribuisce il DMG | Sostituisce il binario | Firma (ad-hoc o self-signed) + checksum SHA-256 pubblicato + Cask che rimuove la quarantena |
| Malware con accesso alla sessione utente | Modifica i file di resume | Scrittura con `open(O_NOFOLLOW, 0600)` + `fchmod` + `fsync` su file e directory prima della rinomina atomica; lettura con `O_NOFOLLOW` e tetto 10 MiB; i file corrotti o non caricabili vengono messi in quarantena `.bad`; i symlink `.resume` non vengono né enumerati (`symlink_status`) né seguiti |

## Fuori perimetro (accettato)

- **Nessuna notarizzazione**: senza account Developer l'app non ha una firma
  Apple. Gatekeeper mostra un avviso la prima volta; il README spiega "Apri
  comunque" e la Cask evita la quarantena. Non è una protezione contro un
  attaccante che può già scrivere nel DMG.
- **Nessun sandboxing**: l'app legge la cartella Download e la libreria scelta
  dall'utente; non c'è App Sandbox (la distribuzione è fuori Mac App Store).
- **Hardened runtime solo con Developer ID**: le build ad-hoc o self-signed non
  lo abilitano (`--options runtime` richiede un'identità Developer ID) e il
  bundle non ha entitlements.
- **Catena Cask/release**: la Cask rimuove la quarantena e il tap si aggiorna ogni
  ora dall'ultima release, con il checksum pubblicato dalla stessa release. Chi
  compromette la release o il tap raggiunge gli utenti Homebrew senza avviso
  Gatekeeper; il checksum protegge dalla corruzione, non da questo scenario.
- **Test di raggiungibilità della porta**: è l'unica richiesta di rete dell'app
  verso terzi e parte solo su azione dell'utente (Diagnostica rete). Invia l'IP
  pubblico e la porta a `api.ipify.org` e `check-host.net`; è disabilitato con il
  proxy SOCKS5 attivo. "Nessuna telemetria" significa nessun invio automatico.
- **GeoIP offline**: le tabelle IPv4 e IPv6 sono incluse nel bundle; la lookup
  non contatta nessun servizio, nessun IP di peer lascia la macchina. Un IP non
  presente nelle tabelle mostra la bandiera generica.
- **DHT e tracker sono visibili al primo salto senza proxy**: quando il proxy è
  attivo, i tracker passano dal proxy e la DHT è disattivata per evitare query DNS di
  bootstrap in chiaro; un utente che disattiva il proxy accetta di esporre il proprio IP.

## Regole di verifica

- `Scripts/verify-bundle.sh` controlla ogni Mach-O, non usa `codesign --deep`.
- La release pubblica un `.sha256` accanto al DMG; la Cask usa quel checksum.
- Il test `Bridge: chiamate concorrenti sulla stessa sessione` garantisce che
  due thread non producano uno snapshot corrotto.
- Il test `Proxy fail-closed` garantisce che un proxy richiesto e senza host
  faccia fallire la creazione invece di partire in chiaro.
