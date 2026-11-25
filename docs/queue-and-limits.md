# Coda e limiti per torrent

Stato: **implementato** (opzione A, senza `queue_position` nell'interfaccia).

## Cosa fa

Impostazione **Prestazioni → Torrent attivi**: `0` = tutti insieme (default, comportamento
identico a prima), `1…1000` = al massimo N torrent attivi contemporaneamente. Gli altri
restano in attesa e la riga mostra la pill **In coda**; quando uno slot si libera partono da
soli, in ordine di aggiunta.

## Come è fatto

libtorrent ha già la coda, ma funziona solo sui torrent **auto-managed**. Vertex li
disabilitava (`params.flags &= ~auto_managed`) proprio per non avere una pausa
indistinguibile da quella dell'utente. L'implementazione cambia il modello:

| Stato | `paused` | `auto_managed` | Significato |
|---|---|---|---|
| attivo | no | sì | sta scaricando o seminando |
| in coda | sì | sì | l'auto-manager lo ha fermato: aspetta uno slot |
| pausa manuale | sì | no | fermato dall'utente, fuori dalla coda |

`Torrent.phase` diventa quindi `.queued` quando `paused && autoManaged`, e
`TorrentPhase.paused` resta "fermato da te". I filtri non aggiungono una categoria: un torrent
in coda appartiene al bucket in cui girerà (`Download` o `Seed`), così "In pausa" non mente.

### Punti del codice

- `vt_set_active_limit(session, max_active)`: `max_active > 0` → `active_limit`,
  `active_downloads`, `active_seeds` = N (il target di libtorrent è
  `min(downloads + seeds, limit)`, quindi N è un tetto totale); `<= 0` → `-1` su tutti e tre.
  **Attenzione**: `active_limit = 0` in libtorrent mette *tutti* i torrent in pausa, per questo
  "illimitato" è `-1` (mappato a `INT_MAX` da `get_int_setting`). `dont_count_slow_torrents`
  è disattivato: altrimenti i torrent lenti non conterebbero e il numero di righe attive non
  corrisponderebbe all'impostazione.
- `add_torrent_common`: `paused` → `paused` + **`auto_managed` off**; altrimenti `paused` off
  + `auto_managed` on. Senza questo, l'auto-manager riavvierebbe i torrent aggiunti "in pausa".
- `vt_control`: `pause` toglie `auto_managed` (pausa manuale reale), `resume` rimette
  `auto_managed` e chiama `handle.resume()` solo se `max_active <= 0` (altrimenti lascia che
  l'auto-manager assegni lo slot senza scavalcare il tetto), `force_start` toglie `auto_managed`
  e avvia subito, `dequeue` toglie `auto_managed` lasciando `paused` (esci dalla coda).
- `set_flags(auto_managed)` in libtorrent schedula già `trigger_auto_manage()`; riapplicare lo
  stesso intero in `settings_pack` era un no-op ed è stato rimosso.
- Snapshot: nuovo campo `auto_managed`; il decode Swift lo tratta come opzionale, così uno
  snapshot precedente resta valido.

## Limiti noti (accettati)

- **Un solo numero**, non limiti separati per download e seed: è il caso d'uso reale (banda),
  e mantiene l'interfaccia a una riga.
- **Ordine FIFO** per `sequence_number` (aggiunta), non riordinabile: `queue_position` non è
  esposto. Se servirà, il bridge deve aggiungere il campo e la UI un drag.
- I contatori dello snapshot contano i torrent in coda come `paused` (`active`/`paused_count`
  restano complementari); non c'è un contatore dedicato.
- Sul track il pulsante di pausa, per un torrent in coda, significa **Escludi dalla coda**.
  Per avviare subito ignorando il limite è disponibile l'opzione **Avvia ora (ignora coda)** nel menu
  contestuale e nell'Inspector.
- Il ricalcolo periodico di libtorrent resta a 30 s; il nudge copre i casi interattivi, ma un
  torrent che *finisce* di scaricare libera il suo slot solo al passaggio successivo (il
  torrent resta comunque attivo come seed).

## Test

- `Coda: limite dei torrent attivi, dequeue e ripresa` (integrazione, sessione reale):
  limite 2 → entrambi attivi; limite 1 → uno in coda; `dequeue` → resta fermo e fuori dalla
  coda; `resume` → torna in coda; pausa dell'attivo → il queued parte da solo; limite 0 →
  nessuno in coda.
- `Coda: fase queued, categoria e decodifica` (modello): fase, `isQueued`, categoria nei
  filtri, decodifica con e senza il campo `auto_managed`.
- `Limite torrent attivi: validazione` + startup validation in `PreferencesTests`.
