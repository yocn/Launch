import Foundation

public enum SearchService {
    public static func results(
        for query: String,
        in apps: [CatalogApp],
        hidden: Set<AppIdentity>
    ) -> [CatalogApp] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps
            .filter { !hidden.contains($0.identity) }
            .filter { app in
                guard !trimmedQuery.isEmpty else {
                    return true
                }
                return matches(trimmedQuery, value: app.displayName)
                    || matches(trimmedQuery, value: app.identity.bundleIdentifier ?? "")
            }
            .sorted(by: appSort)
    }

    private static func matches(_ query: String, value: String) -> Bool {
        value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
