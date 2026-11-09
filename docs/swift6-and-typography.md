# Migrazione Swift 6 e tipografia di sistema

Questo documento registra due interventi **pianificati e non eseguiti**, con la
misura che giustifica la decisione. Entrambi sono cambiamenti trasversali che
richiedono una revisione visiva e comportamentale completa: vanno fatti in un
ramo dedicato, non insieme a un fix.

## 1. Swift 6 language mode

Il package è in `swift-tools-version: 5.10` (Swift 5 language mode). Con
`swift-tools-version: 6.0` la compilazione si ferma al primo file con errori,
quindi la misura utile si ottiene abilitando il controllo completo in modalità 5:

```bash
swift build -c debug -Xswiftc -strict-concurrency=complete 2>&1 | grep warning:
```

Risultato su questo commit (Swift 6.4.2, macOS 27.2 SDK):

| Area | Warning | Causa |
|---|---|---|
| `Views/OpenPanelFactory.swift` | 15 | `NSOpenPanel` è main-isolated: l'enum non è `@MainActor` |
| `Utilities/TorrentDropHandler.swift` | 12 | closure `@MainActor` catturate in handler `@Sendable` di `NSItemProvider` |
| `Engine/TorrentEngine.swift` | 7 | `var` osservati da `DispatchQueue.async` + `SessionPointerBox` |
| `App/AppAppearance.swift` | 5 | `NSApp.appearance` e `NSApp.windows` da contesto nonisolated |
| `Engine/TorrentEngine+Polling.swift` | 4 | catture di `self` in closure concorrenti |
| `Views/StatusBarView.swift` | 1 | `@AppStorage` in contesto nonisolated |
| `Engine/TorrentEngine+Actions.swift` | 1 | riferimento a `var self` in codice concorrente |
| `Tests/…/TestSupport.swift` | 6 | contatori statici del runner (accettabili) |

### Ordine di lavoro proposto

1. **Fogli di AppKit** — `@MainActor` su `OpenPanelFactory` e `AppAppearance`;
   i chiamanti sono già su main, ma in modalità 6 le funzioni delle viste che li
   usano devono diventarlo esplicitamente.
2. **`TorrentDropHandler`** — rendere i parametri `sending`/`@Sendable` invece di
   catturare closure isolate nell'handler di `NSItemProvider`.
3. **`UIState` e viste** — `UIState` è di fatto main-bound: marcarlo `@MainActor`
   richiede `@MainActor` sugli `init` delle viste (gli `init` SwiftUI non sono
   isolati). È il passo più lungo: ~15 viste.
4. **Engine** — sostituire `DispatchQueue.async` + `DispatchQueue.main.async` con
   `Task { @MainActor in … }` e gli `await` su `sessionQueue`; `SessionPointerBox`
   diventa un `actor` o sparisce (l'engine passa a `await withCheckedContinuation`).
5. **Test runner** — contatori in una classe `@MainActor` o `nonisolated(unsafe)`
   con lock (sono già seriali).

### Cosa NON fare

Non aggiungere `@unchecked Sendable` in blocco per far tacere il compilatore: il
progetto ne ha già due (`SessionPointerBox`, `UIState` indiretto) e sono i punti
in cui un errore di isolamento diventa un data race reale. Meglio arrivare alla
modalità 6 con l'engine convertito a `async`.

## 2. Text style di sistema (Dynamic Type)

`Typography` usa oggi dimensioni fisse (8…13.5 pt) raggruppate in sei gradini.
Il passaggio ai text style (`.body`, `.caption`, …) o a `Font.custom(_:size:relativeTo:)`
darebbe scaling di accessibilità, ma cambia le metriche: `.body` su macOS è 13 pt
contro gli 11 pt usati oggi, e diverse viste hanno colonne a larghezza fissa che
si romperebbero:

- `TorrentRow`: colonne `82 / 62 / 66 / 88 pt`, soglia "wide" a 1180 pt;
- `StatusBarView`: altezza 40 pt, layout compatto sotto 1120 pt;
- `SettingsSheet`: righe con `TextField` da 55–85 pt;
- `InspectorView`: griglia a due colonne con `minimumScaleFactor(0.75)`.

### Piano

1. Aggiungere a `Typography` i token basati su text style **accanto** a quelli
   attuali (`bodyText = .body`, `captionText = .caption`, …).
2. Convertire una vista alla volta partendo da quelle senza larghezze fisse
   (`EmptyStateView`, `NoResultsView`, `EngineUnavailableView`, toast).
3. Per le righe con colonne fisse: sostituire `frame(width:)` con
   `frame(minWidth:)` + `layoutPriority`, oppure passare a `Grid`.
4. Verificare con `VERTEX_SNAPSHOT` a `.dynamicTypeSize(.large/.xxLarge)` e con
   la finestra alla larghezza minima (980 pt).
5. Solo alla fine rimuovere i token a dimensione fissa.

Nel frattempo: nessun nuovo `.system(size:)` nelle viste, usare i token di
`Typography`.
