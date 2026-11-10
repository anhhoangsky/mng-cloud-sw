import Foundation

/// Library grouping mode. The persisted values match the PWA's
/// `localStorage.mng.layout.v2`.
public enum LibraryLayout: String, CaseIterable, Sendable {
    case years
    case months
    case all

    public static let storageKey = "mng.layout.v2"

    /// `stored_layout()` falls back to `All`, not `Years`.
    public init(stored value: String?) {
        switch value {
        case LibraryLayout.years.rawValue:
            self = .years
        case LibraryLayout.months.rawValue:
            self = .months
        default:
            self = .all
        }
    }
}

/// Media kind chips shown above the library timeline.
public enum ItemKindFilter: String, CaseIterable, Sendable {
    case all
    case photo
    case video
    case live

    /// API `type` value; `nil` omits the parameter.
    public var apiValue: String? {
        switch self {
        case .all: nil
        case .photo: "photo"
        case .video: "video"
        case .live: "live"
        }
    }
}

/// One library selection: grouping mode plus the drill-down filters.
///
/// The PWA keeps the year and month filters when a kind chip switches the
/// layout back to the timeline, so this type preserves them as well.
public struct LibraryFilterState: Equatable, Sendable {
    public var layout: LibraryLayout
    public var kind: ItemKindFilter
    public var year: Int?
    public var month: Int?

    public init(
        layout: LibraryLayout = .all,
        kind: ItemKindFilter = .all,
        year: Int? = nil,
        month: Int? = nil
    ) {
        self.layout = layout
        self.kind = kind
        self.year = year
        self.month = month
    }

    public var isTimeline: Bool { layout == .all }

    /// True when a year/month drill-down is active, which hides the PWA's
    /// "Chọn" affordance.
    public var hasDateFilter: Bool { year != nil || month != nil }

    /// Segmented control: changing the grouping clears the drill-down filters
    /// but keeps the kind chip, exactly like `set_layout()`.
    public mutating func selectLayout(_ next: LibraryLayout) {
        layout = next
        year = nil
        month = nil
    }

    /// Kind chips always return to the timeline and keep the current date
    /// drill-down (the PWA keeps `year_filter`/`month_filter`).
    public mutating func selectKind(_ next: ItemKindFilter) {
        kind = next
        layout = .all
    }

    /// Year card: show that year's months.
    public mutating func open(year next: Int) {
        year = next
        month = nil
        layout = .months
    }

    /// Month card: show that month's timeline.
    public mutating func open(year nextYear: Int, month nextMonth: Int) {
        year = nextYear
        month = nextMonth
        layout = .all
    }

    /// "Tất cả các năm" in the months drill-down.
    public mutating func showAllYears() {
        year = nil
        month = nil
    }

    /// Summary chip dismiss: clear dates and kind, keep the grouping mode.
    public mutating func clearFilters() {
        year = nil
        month = nil
        kind = .all
    }

    /// The PWA's filter summary chip: `Tháng 11 2026 · Video`.
    public var summary: String? {
        var parts: [String] = []
        if let year, let month {
            parts.append("Tháng \(month) \(year)")
        } else if let year {
            parts.append("Năm \(year)")
        }
        switch kind {
        case .all:
            break
        case .photo:
            parts.append("Ảnh")
        case .video:
            parts.append("Video")
        case .live:
            parts.append("Live Photo")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func itemFilters(cloud: String?, offset: Int, limit: Int? = nil) -> ItemFilters {
        ItemFilters(
            cloud: cloud,
            kind: kind.apiValue,
            year: year,
            month: month,
            limit: limit,
            offset: offset
        )
    }
}

/// Newest-first items grouped into the timeline's sticky month sections.
public struct MonthSection: Identifiable, Equatable, Sendable {
    public let key: String
    public let year: Int
    public let month: Int
    public let items: [Item]

    public var id: String { key }

    public init(key: String, year: Int, month: Int, items: [Item]) {
        self.key = key
        self.year = year
        self.month = month
        self.items = items
    }
}

public enum LibraryGrouping {
    /// Preserve the API's newest-first order while inserting a section at every
    /// year/month boundary, matching `group_by_month()` in the PWA.
    public static func byMonth(_ items: [Item]) -> [MonthSection] {
        var builders: [(year: Int, month: Int, items: [Item])] = []
        for item in items {
            let same = builders.last.map {
                $0.year == item.year && $0.month == item.month
            } ?? false
            if same {
                builders[builders.count - 1].items.append(item)
            } else {
                builders.append((year: item.year, month: item.month, items: [item]))
            }
        }
        return builders.map {
            MonthSection(
                key: "\($0.year)-\($0.month)",
                year: $0.year,
                month: $0.month,
                items: $0.items
            )
        }
    }
}

/// One optimistically removed row, remembering where to put it back.
public struct RemovedItem: Equatable, Sendable {
    public let index: Int
    public let item: Item

    public init(index: Int, item: Item) {
        self.index = index
        self.item = item
    }
}

/// Merge rules for the 120-item timeline pages.
///
/// The API returns newest first. Pages are appended at the bottom, which keeps
/// the SwiftUI scroll position stable while older photos arrive. Duplicate ids
/// are dropped so a refresh racing a page request cannot show a tile twice.
public struct LibraryPage: Equatable, Sendable {
    public private(set) var items: [Item]
    public private(set) var total: Int64

    public init(items: [Item] = [], total: Int64 = 0) {
        self.items = items
        self.total = max(0, total)
    }

    public var count: Int { items.count }
    public var hasMore: Bool { Int64(items.count) < total }

    public func item(id: Int64) -> Item? {
        items.first { $0.id == id }
    }

    public mutating func replace(with response: ItemsResponse) {
        items = response.items
        total = max(0, response.total)
    }

    public mutating func append(_ response: ItemsResponse) {
        var seen = Set(items.map(\.id))
        for item in response.items where seen.insert(item.id).inserted {
            items.append(item)
        }
        total = max(0, response.total)
    }

    /// Remove deleted rows and remember their positions for rollback.
    @discardableResult
    public mutating func remove(ids: Set<Int64>) -> [RemovedItem] {
        guard !ids.isEmpty else { return [] }
        var removed: [RemovedItem] = []
        var kept: [Item] = []
        kept.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if ids.contains(item.id) {
                removed.append(RemovedItem(index: index, item: item))
            } else {
                kept.append(item)
            }
        }
        items = kept
        total = max(0, total - Int64(removed.count))
        return removed
    }

    /// Restore failed deletes at their original positions and restore the count.
    public mutating func restore(_ removed: [RemovedItem]) {
        guard !removed.isEmpty else { return }
        var present = Set(items.map(\.id))
        var restored = 0
        for entry in removed.sorted(by: { $0.index < $1.index }) {
            guard present.insert(entry.item.id).inserted else { continue }
            items.insert(entry.item, at: min(max(0, entry.index), items.count))
            restored += 1
        }
        total += Int64(restored)
    }

    public mutating func setFavorite(ids: Set<Int64>, value: Bool) {
        guard !ids.isEmpty else { return }
        for index in items.indices where ids.contains(items[index].id) {
            items[index].favorite = value
        }
    }

    public mutating func setFavorite(id: Int64, value: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].favorite = value
    }
}
