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
| Rete locale / ISP | Osserva connessioni in chiaro | Il proxy SOCKS5 è **fail-closed**: senza host la sessione non parte, non c'è fallback silenzioso |
| Processo locale non privilegiato | Legge file nella home | Password in Portachiavi per default; file opzionale `0600`, dichiarato non cifrato |
| Sito che distribuisce il DMG | Sostituisce il binario | Firma (ad-hoc o self-signed) + checksum SHA-256 pubblicato + Cask che rimuove la quarantena |
| Malware con accesso alla sessione utente | Modifica i file di resume | `fsync` su file e directory prima della rinomina atomica; i file corrotti vengono messi in quarantena `.bad` |

## Fuori perimetro (accettato)

- **Nessuna notarizzazione**: senza account Developer l'app non ha una firma
  Apple. Gatekeeper mostra un avviso la prima volta; il README spiega "Apri
  comunque" e la Cask evita la quarantena. Non è una protezione contro un
  attaccante che può già scrivere nel DMG.
- **Nessun sandboxing**: l'app legge la cartella Download e la libreria scelta
  dall'utente; non c'è App Sandbox (la distribuzione è fuori Mac App Store).
- **IPv6 non mappato nelle bandiere**: la tabella GeoIP è IPv4-only; i peer IPv6
  mostrano la bandiera generica. Non è un rischio per la privacy: la lookup è
  offline, nessun IP lascia la macchina.
- **DHT e tracker sono visibili al primo salto**: il proxy li copre quando è
  attivo, ma un utente che lo disattiva accetta di esporre il proprio IP.

## Regole di verifica

- `Scripts/verify-bundle.sh` controlla ogni Mach-O, non usa `codesign --deep`.
- La release pubblica un `.sha256` accanto al DMG; la Cask usa quel checksum.
- Il test `Bridge: chiamate concorrenti sulla stessa sessione` garantisce che
  due thread non producano uno snapshot corrotto.
- Il test `Proxy fail-closed` garantisce che un proxy richiesto e senza host
  faccia fallire la creazione invece di partire in chiaro.
