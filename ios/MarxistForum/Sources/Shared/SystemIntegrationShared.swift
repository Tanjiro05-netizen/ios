import Foundation

enum AppGroup {
    static let identifier = "group.com.marxist.forum"
}

enum AppDeepLink: Hashable {
    case library
    case audiobooks
    case substack
    case forum
    case notifications
    case profile
    case book(id: String)
    case audiobook(id: String)
    case substackArticle(slug: String)
    case thread(id: String)
    case userProfile(id: String)
    case dailyQuote
    case continueReading
    case quoteNotebook
    case support
    case search(query: String)

    static let scheme = "marxistforum"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let host = url.host?.lowercased()
        let pathValue = url.pathComponents
            .filter { $0 != "/" }
            .first?
            .removingPercentEncoding
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = queryItems.first { $0.name == "query" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch host {
        case "library":
            self = .library
        case "audiobooks":
            self = .audiobooks
        case "substack":
            if let pathValue, !pathValue.isEmpty {
                self = .substackArticle(slug: pathValue)
            } else {
                self = .substack
            }
        case "forum":
            self = .forum
        case "notifications":
            self = .notifications
        case "profile":
            self = .profile
        case "book":
            guard let pathValue, !pathValue.isEmpty else { return nil }
            self = .book(id: pathValue)
        case "audiobook":
            guard let pathValue, !pathValue.isEmpty else { return nil }
            self = .audiobook(id: pathValue)
        case "thread":
            guard let pathValue, !pathValue.isEmpty else { return nil }
            self = .thread(id: pathValue)
        case "user":
            guard let pathValue, !pathValue.isEmpty else { return nil }
            self = .userProfile(id: pathValue)
        case "daily-quote":
            self = .dailyQuote
        case "continue-reading":
            self = .continueReading
        case "quotes":
            self = .quoteNotebook
        case "support":
            self = .support
        case "search":
            self = .search(query: query ?? "")
        default:
            return nil
        }
    }

    init?(searchableItemIdentifier: String) {
        let parts = searchableItemIdentifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "book":
            self = .book(id: parts[1])
        case "audiobook":
            self = .audiobook(id: parts[1])
        case "substack":
            self = .substackArticle(slug: parts[1])
        case "thread":
            self = .thread(id: parts[1])
        case "quote":
            self = .quoteNotebook
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .library:
            components.host = "library"
        case .audiobooks:
            components.host = "audiobooks"
        case .substack:
            components.host = "substack"
        case .forum:
            components.host = "forum"
        case .notifications:
            components.host = "notifications"
        case .profile:
            components.host = "profile"
        case .book(let id):
            components.host = "book"
            components.path = "/\(id)"
        case .audiobook(let id):
            components.host = "audiobook"
            components.path = "/\(id)"
        case .substackArticle(let slug):
            components.host = "substack"
            components.path = "/\(slug)"
        case .thread(let id):
            components.host = "thread"
            components.path = "/\(id)"
        case .userProfile(let id):
            components.host = "user"
            components.path = "/\(id)"
        case .dailyQuote:
            components.host = "daily-quote"
        case .continueReading:
            components.host = "continue-reading"
        case .quoteNotebook:
            components.host = "quotes"
        case .support:
            components.host = "support"
        case .search(let query):
            components.host = "search"
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                components.queryItems = [URLQueryItem(name: "query", value: query)]
            }
        }

        return components.url!
    }

    var searchableItemIdentifier: String? {
        switch self {
        case .book(let id):
            "book:\(id)"
        case .audiobook(let id):
            "audiobook:\(id)"
        case .substackArticle(let slug):
            "substack:\(slug)"
        case .thread(let id):
            "thread:\(id)"
        case .quoteNotebook:
            "quote:notebook"
        default:
            nil
        }
    }
}

struct DailyQuoteSnapshot: Codable, Hashable {
    var text: String
    var source: String
    var detail: String
    var dateKey: String
}

struct ContinueReadingSnapshot: Codable, Hashable {
    var bookId: String
    var title: String
    var author: String?
    var chapterTitle: String?
    var progress: Double
    var updatedAt: String
}

struct CurrentAudiobookSnapshot: Codable, Hashable {
    var id: String
    var title: String
    var author: String?
    var narrator: String?
    var coverUrl: String?
    var currentTime: Double
    var duration: Double
    var speed: Float
    var chapterTitle: String?
    var isPlaying: Bool
    var updatedAt: String
}

struct LatestUpdateSnapshot: Codable, Hashable {
    enum Kind: String, Codable {
        case substack
        case forum
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var detail: String?
    var deepLinkURL: URL
    var updatedAt: String
}

struct SystemIntegrationSnapshot: Codable, Hashable {
    var dailyQuote: DailyQuoteSnapshot?
    var continueReading: ContinueReadingSnapshot?
    var currentAudiobook: CurrentAudiobookSnapshot?
    var latestUpdates: [LatestUpdateSnapshot]

    static let empty = SystemIntegrationSnapshot(
        dailyQuote: nil,
        continueReading: nil,
        currentAudiobook: nil,
        latestUpdates: []
    )
}

enum SystemIntegrationStore {
    private static let snapshotKey = "system.integration.snapshot.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func loadSnapshot() -> SystemIntegrationSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(SystemIntegrationSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: SystemIntegrationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func updateSnapshot(_ mutate: (inout SystemIntegrationSnapshot) -> Void) {
        var snapshot = loadSnapshot()
        mutate(&snapshot)
        saveSnapshot(snapshot)
    }
}
