# Migrazione Swift 6 e tipografia di sistema

Questo documento registra due interventi di modernizzazione architetturale:
1. **Swift 6 language mode**: completato (package in `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, 69/69 test passati, 0 errori, 0 warning di concorrenza).
2. **Tipografia di sistema (Dynamic Type)**: pianificato e non eseguito.

## 1. Swift 6 language mode (Completato)

Il package è configurato con `swift-tools-version: 6.0` e `swiftLanguageModes: [.v6]`.
Tutte le verifiche di isolamento e thread-safety del compilatore Swift 6 sono attive e superate:

- **Fogli e utility AppKit**: `OpenPanelFactory` e `AppAppearance` isolati su `@MainActor`.
- **Drag & Drop**: handler di `NSItemProvider` in `TorrentDropHandler` tipizzati con `@Sendable @MainActor` e `TorrentDropItem: Sendable`.
- **`UIState` e viste**: `UIState<Value>` e `DotGridCache` isolati su `@MainActor`.
- **Status bar**: soglia `compactWidthThreshold` contrassegnata `nonisolated` per l'uso nella closure Sendable di `onGeometryChange`.
- **Engine**: azzeramento errori proxy e chiamate bridge su `sessionQueue` protetti da `SessionPointerBox`.
- **Test runner & EngineTests**: contatori in `TestRunner` marcati `nonisolated(unsafe)`, `onMain` vincolato a `T: Sendable`, e callback asincrone isolate con `AsyncBox` su `@MainActor`.

Risultato verifiche:
- Compilazione target `CTorrent`, `VertexKit`, `Vertex`, `VertexTestRunner`: pulita (0 warning di concorrenza).
- Suite di test: 69/69 test superati (`./build.sh test`).
- Bundle `.app` e verifica Mach-O: superati (`./build.sh`).

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
