# ADR 0002 — Lo snapshot legge `state_update_alert`, non N `status()`

Stato: accettato (2026-11-21)

## Contesto

Ogni poll produce uno snapshot JSON completo per la UI. La prima versione
chiamava `handle.status(query)` per ogni torrent: con 300 torrent erano 300
query dentro `vt_snapshot_json`, tutte sotto `VT_LOCK_SESSION`, anche quando
nulla era cambiato. Il costo cresceva con la libreria, non con l'attività, e
bloccava il mutex della sessione mentre la UI aspettava il JSON.

libtorrent sa pubblicare solo i torrent cambiati:
`session::post_torrent_updates(...)` genera una `state_update_alert` con gli
stati aggiornati.

## Decisione

- `vt_session_poll` chiama `post_torrent_updates` con
  `query_name | query_save_path | query_accurate_download_counters`.
- Le `state_update_alert` riempiono `status_cache`, indicizzata dall'infohash
  esadecimale.
- `vt_snapshot_json` legge la cache. Solo per le chiavi assenti (primo poll
  dopo un resume) chiama `handle.status(query)` una volta e memorizza il
  risultato; la cache viene svuotata quando supera `2 * handle + 64`.
- Ogni torrent è serializzato in uno `ostringstream` locale e poi appeso al
  documento: un'eccezione a metà non può troncare il JSON degli altri.
- `alert_errors` è una coda drenata dallo snapshot, così un errore non viene
  sovrascritto o perso tra due poll.

## Conseguenze

- In regime stazionario il costo è O(aggiornamenti) + O(N) di serializzazione,
  non più O(N) query.
- Il primo poll dopo un resume resta O(N) (cache fredda): è il prezzo per non
  interrogare mai un handle due volte.
- La cache è per-sessione; viene eliminata con la sessione e non richiede
  invalidazioni manuali.
- Misura nel test `Snapshot: 300 torrent e cache degli aggiornamenti`:
  p50 ≈ 1,0 ms, p95 ≈ 1,2 ms in locale (build debug). Il budget di 50 ms
  protegge dal ritorno al percorso O(N); sotto ASan/TSan il budget non si
  applica perché ogni accesso è strumentato, ma i numeri restano stampati.
- Il test riprende un torrent e verifica che lo snapshot rifletta il cambio,
  così una cache che non si aggiorna fallisce.

## Alternative scartate

- **`status()` per ogni torrent a ogni poll**: semplice, ma O(N) sotto mutex.
- **Delta incrementali fino al layer Swift**: avrebbe spostato la stessa
  complessità nella UI, che avrebbe comunque dovuto mantenere una cache.
- **Aumentare l'intervallo di poll**: non riduce il costo per poll e peggiora
  la reattività.
