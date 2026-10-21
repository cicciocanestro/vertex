# Changelog

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
