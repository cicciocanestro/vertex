# Migrazione Swift 6 e tipografia di sistema

Questo documento registra due interventi di modernizzazione architetturale:
1. **Swift 6 language mode**: completato (package in `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, 69/69 test passati, 0 errori, 0 warning di concorrenza).
2. **Tipografia di sistema (Dynamic Type)**: completato (tutti i 5 passi eseguiti: token semantici in `Typography`, migrazione viste, layout adattivi per colonne e controlli, verifica snapshot `.large`/`.xxLarge` a 980 pt e rimozione token a dimensione fissa).

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

## 2. Text style di sistema (Dynamic Type — Completato)

`Typography` è stata migrata dai token a dimensione fissa (8…13.5 pt) ai text style semantici di sistema (`Font.system(.largeTitle/.title2/.title3/.headline/.body/.subheadline/.callout/.caption/.caption2)` con le relative varianti `.rounded` e `.monospaced`), abilitando lo scaling di accessibilità e Dynamic Type su tutte le viste dell'applicazione.

### Adeguamenti di layout

- **`TorrentRow`**: sostituite le larghezze rigide (`frame(width: 82 / 62 / 66 / 88)`) con `frame(minWidth:)` + `.fixedSize(horizontal: true, vertical: false)` per le metriche e la colonna velocità, assegnando `.layoutPriority(1)` alla colonna principale con titolo e metadati.
- **`StatusBarView`**: sostituito `frame(height: 40)` fisso con `frame(minHeight: 40)` + padding verticale, aggiunto `.lineLimit(1)` e `.fixedSize(horizontal: true, vertical: false)` ai gruppi informativi, mantenendo la soglia `compactWidthThreshold` (1120 pt).
- **`SettingsSheet`**: sidebar resa elastica (`frame(minWidth: 168, idealWidth: 176, maxWidth: 210)` con `.fixedSize(horizontal: true, vertical: false)`), righe con `TextField`/`SecureField` convertite a `frame(minWidth:maxWidth:minHeight:)` e `.layoutPriority(1)` sulle etichette descrittive.
- **`InspectorView`**: griglia a due colonne con `Typography.smallRoundedSemiboldText` e `minimumScaleFactor(0.75)`, header e controlli convertiti a `minHeight` e `.layoutPriority(1)` per file e tracker.
- **Componenti condivisi (`Components`, `ModalChrome`, `SegmentedPicker`, `HeaderBar`, `AddTorrentSheet`, `NetworkDiagnosticsView`)**: convertiti pulsanti, chip, picker segmentati e campi di ricerca da `frame(height:)` fisso a `frame(minHeight:)` con padding verticale, rimuovendo ogni `.system(size:)` diretto dalle viste.

### Piano

1. [x] **Passo 1 (Completato)**: Aggiungere a `Typography` i token basati su text style **accanto** a quelli
   attuali (`heroText`, `modalTitleText`, `bodyLargeRegularText`, `bodyText`, `captionText`, `microText`, …).
2. [x] **Passo 2 (Completato)**: Convertire una vista alla volta partendo da quelle senza larghezze fisse
   (`EmptyStateView`, `NoResultsView`, `EngineUnavailableView`, `LoadingStateView`, `DropOverlay`, toast, `ModalChrome`).
3. [x] **Passo 3 (Completato)**: Per le righe con colonne fisse (`TorrentRow`, `StatusBarView`, `SettingsSheet`, `InspectorView`, `HeaderBar`, `AddTorrentSheet`, `NetworkDiagnosticsView`): sostituire `frame(width:)` / `frame(height:)` fissi con `frame(minWidth:)` / `frame(minHeight:)` + `layoutPriority`.
4. [x] **Passo 4 (Completato)**: Verificare con `VERTEX_SNAPSHOT` e con `ViewRenderingSupport` a `.dynamicTypeSize(.large/.xxLarge)` e con la finestra alla larghezza minima (`WindowMetrics.minimumWidth` = 980 pt).
5. [x] **Passo 5 (Completato)**: Rimuovere i token di testo a dimensione fissa da `Typography`, lasciando solo i text style semantici e i token per le icone decorative/proporzionali.
