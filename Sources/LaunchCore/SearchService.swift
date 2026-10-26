import Foundation

public enum SearchService {
    public static func results(
        for query: String,
        in items: [LaunchItem],
        hidden: Set<ItemIdentity>
    ) -> [LaunchItem] {
        SearchIndex(items: items).results(for: query, hidden: hidden)
    }
}

// 拼音在应用列表变化时算好，输入时只做匹配
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let item: LaunchItem
        let syllables: [String]
        let fileName: String
    }

    private enum Rank: Int, Comparable {
        case namePrefix
        case fromStart
        case elsewhere

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let entries: [Entry]

    public init(items: [LaunchItem]) {
        entries = items.map { item in
            Entry(
                item: item,
                syllables: SearchName.syllables(of: item.displayName),
                fileName: item.application.map { URL(fileURLWithPath: $0.identity.path).deletingPathExtension().lastPathComponent }
                    ?? Self.searchTarget(item)
            )
        }
    }

    public func results(for query: String, hidden: Set<ItemIdentity>) -> [LaunchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = Array(SearchName.normalized(trimmed))
        return entries
            .filter { !hidden.contains($0.item.identity) }
            .compactMap { entry -> (LaunchItem, Rank)? in
                guard !trimmed.isEmpty else {
                    return (entry.item, .elsewhere)
                }
                return Self.rank(of: entry, query: trimmed, compact: compact).map { (entry.item, $0) }
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 < rhs.1 : itemSort(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    private static func rank(of entry: Entry, query: String, compact: [Character]) -> Rank? {
        let name = entry.item.displayName
        if contains(name, query, anchored: true) {
            return .namePrefix
        }
        if matchesSyllables(entry.syllables, compact, from: 0) || contains(entry.fileName, query, anchored: true) {
            return .fromStart
        }
        if contains(name, query)
            || contains(entry.fileName, query)
            || contains(entry.item.application?.identity.bundleIdentifier ?? "", query)
            || entry.syllables.indices.dropFirst().contains(where: { matchesSyllables(entry.syllables, compact, from: $0) }) {
            return .elsewhere
        }
        return nil
    }

    private static func searchTarget(_ item: LaunchItem) -> String {
        guard case .website(let url) = item.target else { return "" }
        return url.host ?? ""
    }

    private static func contains(_ value: String, _ query: String, anchored: Bool = false) -> Bool {
        var options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if anchored {
            options.insert(.anchored)
        }
        return value.range(of: query, options: options) != nil
    }

    // 从第 start 个音节起，每个音节可只取拼音开头的一部分（全拼、首字母、混拼）
    private static func matchesSyllables(_ syllables: [String], _ query: [Character], from start: Int) -> Bool {
        guard !query.isEmpty else {
            return false
        }
        func consume(_ offset: Int, _ index: Int) -> Bool {
            if offset == query.count {
                return true
            }
            guard index < syllables.count else {
                return false
            }
            let syllable = Array(syllables[index])
            var length = 0
            while length < syllable.count, offset + length < query.count, syllable[length] == query[offset + length] {
                length += 1
            }
            for taken in stride(from: length, to: 0, by: -1) where consume(offset + taken, index + 1) {
                return true
            }
            return false
        }
        return consume(0, start)
    }
}
