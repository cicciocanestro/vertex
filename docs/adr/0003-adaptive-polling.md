# ADR 0003 — Polling adattivo

Stato: accettato (2026-11-21)

## Contesto

Un intervallo fisso è un compromesso sbagliato: 0,8 s costanti consumano CPU
con la libreria ferma o l'app in background, mentre 2,5 s costanti rendono
lenti progresso, rate e grafici durante un download attivo. Il costo di un
poll è basso ma non nullo (≈1 ms con 300 torrent in cache, vedi ADR 0002), e i
grafici hanno bisogno di campioni regolari solo quando c'è traffico.

## Decisione

`TorrentEngine.pollInterval(downloadRate:uploadRate:hasUnfinished:isAppActive:)`
è una funzione pura, non isolata:

- app non attiva → **2,5 s**;
- traffico in entrata o in uscita, oppure almeno un torrent non finito →
  **0,8 s**;
- altrimenti → **1,6 s**.

Il loop in `startPolling` esegue un poll, calcola l'intervallo dallo stato
appena applicato e dorme. Restano due invarianti già presenti:

- un solo poll in volo (`isPollInFlight`);
- i risultati di una generazione precedente vengono scartati
  (`sessionGeneration`), così un resume o una distruzione non applicano uno
  snapshot vecchio.

La sonda TCP del proxy ha una cadenza propria, contata in tick di poll (uno
ogni 10 tick se sana, uno ogni 3 se c'è un errore), quindi non dipende
dall'intervallo scelto.

## Conseguenze

- Età massima del dato: 0,8 s attivo, 1,6 s inattivo, 2,5 s in background.
- Un nuovo download avviato mentre la libreria è inattiva viene rilevato al
  poll successivo (fino a 1,6 s): accettabile, l'utente ha appena agito e la
  riga compare comunque subito per stato ottimistico.
- La policy è coperta da test senza sessione (`EngineTests`); il loop resta
  sottile e non testabile, ma non contiene decisioni.
- `Task.sleep` non riceve leeway: non c'è coalescenza esplicita dei timer.
- In background non si spegne il polling: le notifiche di completamento e i
  badge della status bar hanno bisogno di continuare a funzionare.

## Alternative scartate

- **Intervallo fisso 1 s**: semplice, ma nessun adattamento a idle/background.
- **Solo event-driven**: i grafici di rate richiedono campioni temporali anche
  quando non arrivano eventi.
- **Timer AppKit/Combine**: stessa politica, più plumbing e meno testabile.
