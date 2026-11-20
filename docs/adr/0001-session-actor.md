# ADR 0001 — La sessione libtorrent vive in un actor

Stato: accettato (2026-11-20)

## Contesto

Il bridge C espone un `vt_session*` il cui puntatore va creato, interrogato e
distrutto da un solo posto. La versione precedente lo proteggeva con una coda
seriale (`sessionQueue`), una scatola `SessionPointerBox` e due contatori
(`sessionGeneration`, `pollID`) che dovevano restare coerenti a mano. Ogni
nuova chiamata (CLI, mod, test) poteva rompere quel contratto: il puntatore
era leggibile da qualunque contesto.

## Decisione

Il puntatore appartiene a `SessionController`, un `actor`:

- `create(configuration:)` valida le preferenze, costruisce la configurazione e
  chiama `vt_session_create_configured` sul proprio executor;
- `destroy`, `poll`, `detail` e `perform` sono le uniche porte verso il bridge;
- l'engine conserva solo stato UI e uno specchio sincrono `hasSession` per
  decidere subito se un comando è accettabile.

Il mutex nel bridge resta: la sicurezza non dipende più dalla disciplina dei
chiamanti, e in DEBUG il percorso sincrono dei test (`testPointerBox`) è sicuro
anche se l'actor sta pollando.

## Conseguenze

- Niente più coda, box o contatori: l'isolamento dell'actor sostituisce la
  contabilità manuale.
- Poll e decodifica del dettaglio avvengono fuori dal main actor.
- `pollNowForTesting` resta sincrono; l'alternativa (rendere async tutti i test
  dell'engine) avrebbe aggiunto rumore senza coprire più codice.
- Il costo è un `await` per comando; irrilevante rispetto al lavoro del bridge.

## Alternative scartate

- **GCD con `DispatchQueue.sync`**: già in uso, ma il puntatore restava un
  valore condiviso senza un proprietario espresso.
- **Rendere `OpaquePointer` `Sendable`**: impossibile senza `@unchecked`, che
  avrebbe spostato il problema.
