# Coda e limiti per torrent — design

Stato: **non implementato**. Questo documento esiste perché la decisione non venga
improvvisata: è la feature con più interazioni delicate rimasta aperta, e va fatta
con una policy esplicita.

## Perché non è un `settings_pack` in più

libtorrent ha già una coda (`active_limit`, `active_downloads`, `active_seeds`,
`dont_count_slow_torrents`) ma funziona solo sui torrent **auto-managed**. Vertex li
disabilita di proposito:

```cpp
params.flags &= ~lt::torrent_flags::auto_managed;   // vt_add_torrent_common e resume
```

Il motivo è che la pausa decisa dall'auto-manager non è distinguibile dalla pausa
dell'utente: `torrent_flags::paused` è un flag solo, e la UI mostrerebbe "In pausa" un
torrent che l'utente non ha mai messo in pausa (e il pulsante ▶ lo riprenderebbe
scavalcando la coda).

## Opzione A (consigliata): riabilitare l'auto-manager

1. Bridge: esporre `is_auto_managed` e `queue_position` nello snapshot (due campi).
2. `Torrent`: `autoManaged: Bool`, `queuePosition: Int`.
3. `TorrentPhase`: aggiungere `.queued` — `autoManaged && !paused && stato di attesa`
   (libtorrent riporta `queued_for_checking`/`paused` con `auto_managed` attivo).
4. Pulsante pausa: se il torrent è `.queued`, la pressione deve **disabilitare
   l'auto-manager** per quel torrent (`handle.unset_flags(auto_managed)`) e non
   commutare `paused`. Questo è il punto che evita il "riprendo ma non parte".
5. Impostazioni → Prestazioni: tre campi (`Limite attivi`, `Download attivi`, `Seed
   attivi`), 0 = illimitato, applicati con `apply_settings` (sono a caldo).
6. Rimozione: se un torrent viene rimosso, la coda si ricalcola da sola (libtorrent).

Costo stimato: ~60 righe di bridge, ~80 di engine/modelli, ~120 di UI, 4–5 test
(snapshot con `active_limit`, transizione queued→downloading, pausa manuale su un
torrent in coda, interazione con il kill-switch dell'interfaccia).

## Opzione B (sconsigliata): coda gestita da Vertex

Vertex tiene un `Set<String> queuedIDs`, mette in pausa i torrent in eccesso e li
riprende quando si libera spazio.

Perché è peggio:
- richiede di distinguere pausa "di coda" e pausa manuale in ogni percorso (poll,
  restart PEX, ripresa dopo errore, riapertura da Finder);
- se l'app termina con torrent in coda, i resume data li fissano in pausa e al
  riavvio non si sa più quali riprendere;
- duplica una logica che libtorrent ha già, con più superficie di bug.

Se serve comunque, la policy minima è: limite per numero di torrent **non completati**
attivi, sospensione dei più recenti (per `added`), ripresa in ordine di aggiunta, e una
voce "Riprendi sempre questo torrent" nella riga per escluderlo dalla coda.

## Interazioni da verificare in ogni caso

- **Kill-switch interfaccia** (`bindAddress`): un torrent in coda non deve risultare
  "in errore" quando l'indirizzo sparisce.
- **Proxy SOCKS5**: la sonda di raggiungibilità non deve riprendere torrent in coda.
- **Limiti di velocità**: sono globali ed entrano in `apply_link_settings`; la coda non
  deve riscriverli.
- **`remove` con `delete_files`**: rimuovere un torrent in coda non deve creare resume
  data tardivi (già coperto da `removed_ids`).
- **Snapshot**: `active` e `paused_count` devono continuare a sommare a `torrents.count`;
  un terzo stato richiede un contatore dedicato (`queued_count`) e un test di invariante.
