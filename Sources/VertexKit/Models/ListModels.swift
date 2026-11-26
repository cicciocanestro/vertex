import Foundation

/// Row density for the torrent list. Compact fits more rows without changing
/// what a row shows; it only tightens spacing, padding and the progress ring.
package enum ListDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .comfortable: return L("Comoda")
        case .compact: return L("Compatta")
        }
    }

    package var rowSpacing: CGFloat {
        switch self {
        case .comfortable: return 7
        case .compact: return 4
        }
    }

    package var rowPadding: CGFloat {
        switch self {
        case .comfortable: return 9
        case .compact: return 5
        }
    }

    package var ringSize: CGFloat {
        switch self {
        case .comfortable: return 42
        case .compact: return 36
        }
    }
}

package enum TorrentFilter: String, CaseIterable, Identifiable {
    case all
    case downloading
    case seeding
    case completed
    case paused

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .all: return L("Tutti")
        case .downloading: return L("Download")
        case .seeding: return L("Seed")
        case .completed: return L("Completati")
        case .paused: return L("In pausa")
        }
    }

    /// The category that owns a torrent for the purpose of the counts.
    /// `Torrent.phase` is the source of truth: manual pause prevails, "Download"
    /// includes metadata and verification, active upload (`uploadRate > 0`) owns
    /// "Seed", and finished idle/filtered torrents fall under `.completed`.
    package static func category(for torrent: Torrent) -> TorrentFilter {
        switch torrent.phase {
        case .downloading, .metadata, .checking:
            return .downloading
        case .seeding:
            return .seeding
        case .completed:
            return .completed
        case .paused, .completedPaused:
            return .paused
        // A queued torrent is not stopped by the user: it waits for a slot in the
        // bucket it belongs to, so "In pausa" keeps meaning "paused by you".
        case .queued:
            if torrent.finished {
                return torrent.seeding ? .seeding : .completed
            }
            return .downloading
        }
    }

    /// "Download", "Seed" and "In pausa" are exclusive (pause prevails), and
    /// the torrents owned by `.completed` form a fourth group, so every torrent
    /// is counted exactly once by the three primary buckets plus `.completed`.
    ///
    /// `.completed` is nevertheless the one *overlapping* filter: it matches
    /// every finished torrent, including the ones listed under "Seed". Without
    /// the overlap the chip would be empty for a normal library, because
    /// libtorrent reports a fully downloaded torrent as a pure seeder (state 5)
    /// and never as "completed" — a finished download only reaches state 4 when
    /// some files are skipped.
    package func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all:
            return true
        case .completed:
            return torrent.finished || Self.category(for: torrent) == .completed
        default:
            return Self.category(for: torrent) == self
        }
    }
}

package enum TorrentSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case size
    case progress
    case speed

    package var id: String { rawValue }

    package var label: String {
        switch self {
        case .recent: return L("Recenti")
        case .name: return L("Nome")
        case .size: return L("Dimensione")
        case .progress: return L("Progresso")
        case .speed: return L("Velocità")
        }
    }

    package var icon: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat"
        case .size: return "externaldrive"
        case .progress: return "chart.bar"
        case .speed: return "speedometer"
        }
    }

    /// Direction used when the user picks this criterion. Names read A→Z; the
    /// other criteria start from the most useful end (newest, largest, fastest),
    /// which is what the arrow in the filter bar then shows.
    package var defaultAscending: Bool {
        self == .name
    }
}

package struct TorrentListResult {
    package let torrents: [Torrent]
    package let counts: [TorrentFilter: Int]
}

/// Arrow-key navigation over the visible torrent list. Kept next to the list
/// pipeline so the bounds logic can be tested without a hosted view.
package enum TorrentListNavigation {
    package static func nextIndex(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return min(max(current + delta, 0), count - 1)
    }
}

/// Multi-selection state transitions (`Click`, `⌘-Click`, `⇧-Click`, `⌘A`).
/// Pure value logic so selection invariants are unit-testable without AppKit.
package enum TorrentListSelection {
    package struct State: Equatable {
        package var selectedIDs: Set<String>
        package var anchorID: String?

        package init(selectedIDs: Set<String> = [], anchorID: String? = nil) {
            self.selectedIDs = selectedIDs
            self.anchorID = anchorID
        }
    }

    package static func handleClick(
        on clickedID: String,
        in visibleIDs: [String],
        current: Set<String>,
        anchor: String?,
        command: Bool,
        shift: Bool
    ) -> State {
        if shift,
            let anchor,
            let anchorIndex = visibleIDs.firstIndex(of: anchor),
            let clickedIndex = visibleIDs.firstIndex(of: clickedID)
        {
            let lower = min(anchorIndex, clickedIndex)
            let upper = max(anchorIndex, clickedIndex)
            let range = Set(visibleIDs[lower...upper])
            let combined = command ? current.union(range) : range
            return State(selectedIDs: combined, anchorID: anchor)
        }

        if command {
            var next = current
            if next.contains(clickedID) {
                next.remove(clickedID)
                let nextAnchor = (anchor == clickedID) ? next.first : anchor
                return State(selectedIDs: next, anchorID: nextAnchor)
            } else {
                next.insert(clickedID)
                return State(selectedIDs: next, anchorID: clickedID)
            }
        }

        return State(selectedIDs: [clickedID], anchorID: clickedID)
    }

    package static func selectAll(in visibleIDs: [String], currentAnchor: String?) -> State {
        guard !visibleIDs.isEmpty else { return State() }
        let anchor =
            (currentAnchor != nil && visibleIDs.contains(currentAnchor!))
            ? currentAnchor
            : visibleIDs.first
        return State(selectedIDs: Set(visibleIDs), anchorID: anchor)
    }
}

/// Filtering and sorting applied by the torrent list. It lives in the model
/// layer so the behaviour can be tested without rendering `RootView`.
package enum TorrentListPipeline {
    package static func apply(
        to torrents: [Torrent],
        filter: TorrentFilter,
        search: String,
        sort: TorrentSort,
        ascending: Bool = false
    ) -> [Torrent] {
        applyWithCounts(
            to: torrents,
            filter: filter,
            search: search,
            sort: sort,
            ascending: ascending
        ).torrents
    }

    /// Returns the visible torrents and the per-filter counts in a single pass
    /// over the list, so `FilterBar` does not traverse it again.
    package static func applyWithCounts(
        to torrents: [Torrent],
        filter: TorrentFilter,
        search: String,
        sort: TorrentSort,
        ascending: Bool = false
    ) -> TorrentListResult {
        var counts = Dictionary(
            uniqueKeysWithValues: TorrentFilter.allCases.map { ($0, 0) }
        )
        var list: [Torrent] = []
        list.reserveCapacity(torrents.count)

        for torrent in torrents {
            let category = TorrentFilter.category(for: torrent)
            counts[.all, default: 0] += 1
            // "Completati" is the overlapping bucket: it counts every finished
            // torrent, so the three primary buckets stay exclusive and still
            // cover the whole list between them.
            if category == .completed || torrent.finished {
                counts[.completed, default: 0] += 1
            }
            if category != .completed {
                counts[category, default: 0] += 1
            }

            guard filter.matches(torrent) else { continue }
            if !search.isEmpty,
                !torrent.name.localizedCaseInsensitiveContains(search),
                !torrent.id.localizedCaseInsensitiveContains(search)
            {
                continue
            }
            list.append(torrent)
        }

        switch sort {
        case .recent:
            list.sort {
                if $0.added == $1.added { return $0.id < $1.id }
                return ascending ? ($0.added < $1.added) : ($0.added > $1.added)
            }
        case .name:
            // `ascending` means the same thing for every criterion: the value
            // grows down the list (A→Z here, smallest first elsewhere).
            let target: ComparisonResult = ascending ? .orderedAscending : .orderedDescending
            list.sort {
                let cmp = $0.name.localizedStandardCompare($1.name)
                if cmp == .orderedSame { return $0.id < $1.id }
                return cmp == target
            }
        case .size:
            list.sort {
                if $0.size == $1.size { return $0.id < $1.id }
                return ascending ? ($0.size < $1.size) : ($0.size > $1.size)
            }
        case .progress:
            list.sort {
                if $0.displayProgress == $1.displayProgress { return $0.id < $1.id }
                return ascending ? ($0.displayProgress < $1.displayProgress) : ($0.displayProgress > $1.displayProgress)
            }
        case .speed:
            list.sort {
                let lhsDown = UInt64(max($0.downloadRate, 0))
                let lhsUp = UInt64(max($0.uploadRate, 0))
                let rhsDown = UInt64(max($1.downloadRate, 0))
                let rhsUp = UInt64(max($1.uploadRate, 0))
                let (lhsSum, lhsOverflow) = lhsDown.addingReportingOverflow(lhsUp)
                let (rhsSum, rhsOverflow) = rhsDown.addingReportingOverflow(rhsUp)
                let lhsTotal = lhsOverflow ? UInt64.max : lhsSum
                let rhsTotal = rhsOverflow ? UInt64.max : rhsSum
                if lhsTotal != rhsTotal {
                    return ascending ? (lhsTotal < rhsTotal) : (lhsTotal > rhsTotal)
                }
                if $0.downloadRate != $1.downloadRate {
                    return ascending ? ($0.downloadRate < $1.downloadRate) : ($0.downloadRate > $1.downloadRate)
                }
                return $0.id < $1.id
            }
        }

        return TorrentListResult(torrents: list, counts: counts)
    }
}

package struct ToastMessage: Identifiable, Equatable {
    package enum Kind {
        case success
        case error
        case info
    }

    /// Optional action rendered inside the toast. The view stays presentation
    /// only: the root view performs the side effect.
    package enum Action: Equatable {
        case reveal(path: String)
        case openFolder(path: String)
    }

    package let id: UUID
    package let kind: Kind
    package let text: String
    package let detail: String?
    package let actionTitle: String?
    package let action: Action?

    package init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        detail: String? = nil,
        actionTitle: String? = nil,
        action: Action? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }
}
