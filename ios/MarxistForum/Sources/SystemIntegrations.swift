import CoreSpotlight
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class DeepLinkDispatcher {
    static let shared = DeepLinkDispatcher()

    var pending: AppDeepLink?

    func open(_ url: URL) {
        guard let deepLink = AppDeepLink(url: url) else { return }
        open(deepLink)
    }

    func open(_ deepLink: AppDeepLink) {
        pending = deepLink
    }

    func consume() {
        pending = nil
    }
}

enum SystemSnapshotPublisher {
    static func publishDailyQuote(_ quote: DailyQuote, date: Date = Date()) {
        let dateKey = DateFormatter.systemSnapshotDay.string(from: date)
        SystemIntegrationStore.updateSnapshot { snapshot in
            snapshot.dailyQuote = DailyQuoteSnapshot(
                text: quote.text,
                source: quote.source,
                detail: quote.detail,
                dateKey: dateKey
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func publishContinueReading(_ item: ContinueReadingItem?) {
        SystemIntegrationStore.updateSnapshot { snapshot in
            snapshot.continueReading = item.map {
                ContinueReadingSnapshot(
                    bookId: $0.bookId,
                    title: $0.title,
                    author: $0.author,
                    chapterTitle: $0.chapterTitle,
                    progress: $0.progress,
                    updatedAt: $0.updatedAt
                )
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func publishCurrentAudiobook(
        _ audiobook: Audiobook?,
        currentTime: Double,
        duration: Double,
        speed: Float,
        chapterTitle: String?,
        isPlaying: Bool,
        reloadWidgets: Bool = true
    ) {
        SystemIntegrationStore.updateSnapshot { snapshot in
            snapshot.currentAudiobook = audiobook.map {
                CurrentAudiobookSnapshot(
                    id: $0.id,
                    title: $0.title,
                    author: $0.author,
                    narrator: $0.narrator,
                    coverUrl: $0.coverUrl,
                    currentTime: currentTime,
                    duration: duration,
                    speed: speed,
                    chapterTitle: chapterTitle,
                    isPlaying: isPlaying,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            }
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func publishLatestSubstack(_ posts: [SubstackArticle]) {
        let updates = posts.prefix(3).map {
            LatestUpdateSnapshot(
                id: "substack-\($0.slug)",
                kind: .substack,
                title: $0.title,
                subtitle: $0.author ?? AppConstants.substackAuthorName,
                detail: $0.displayDate,
                deepLinkURL: AppDeepLink.substackArticle(slug: $0.slug).url,
                updatedAt: $0.publishedAt
            )
        }
        mergeLatestUpdates(kind: .substack, updates: updates)
    }

    static func publishLatestThreads(_ threads: [Thread]) {
        let updates = threads.prefix(3).map {
            LatestUpdateSnapshot(
                id: "thread-\($0.id)",
                kind: .forum,
                title: $0.title,
                subtitle: $0.author?.username ?? $0.anonymousName ?? "Forum",
                detail: $0.content.strippedMarkdown.clipped(80),
                deepLinkURL: AppDeepLink.thread(id: $0.id).url,
                updatedAt: $0.createdAt
            )
        }
        mergeLatestUpdates(kind: .forum, updates: updates)
    }

    private static func mergeLatestUpdates(kind: LatestUpdateSnapshot.Kind, updates: [LatestUpdateSnapshot]) {
        SystemIntegrationStore.updateSnapshot { snapshot in
            snapshot.latestUpdates.removeAll { $0.kind == kind }
            snapshot.latestUpdates.append(contentsOf: updates)
            snapshot.latestUpdates = Array(snapshot.latestUpdates.prefix(6))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@MainActor
final class SearchIndexService {
    static let shared = SearchIndexService()

    private init() {}

    func indexBooks(_ books: [Book]) async {
        await replace(domain: "book", with: books.map { item in
            makeItem(
                identifier: AppDeepLink.book(id: item.id).searchableItemIdentifier ?? "book:\(item.id)",
                domain: "book",
                title: item.title,
                subtitle: item.author,
                description: item.description,
                keywords: [item.author, item.category, item.era, item.language].compactMap { $0 },
                deepLink: .book(id: item.id)
            )
        })
    }

    func indexAudiobooks(_ audiobooks: [Audiobook]) async {
        await replace(domain: "audiobook", with: audiobooks.map { item in
            makeItem(
                identifier: AppDeepLink.audiobook(id: item.id).searchableItemIdentifier ?? "audiobook:\(item.id)",
                domain: "audiobook",
                title: item.title,
                subtitle: item.author ?? item.narrator,
                description: item.description,
                keywords: [item.author, item.narrator, item.category].compactMap { $0 },
                deepLink: .audiobook(id: item.id)
            )
        })
    }

    func indexSubstack(_ posts: [SubstackArticle]) async {
        await replace(domain: "substack", with: posts.map { post in
            makeItem(
                identifier: AppDeepLink.substackArticle(slug: post.slug).searchableItemIdentifier ?? "substack:\(post.slug)",
                domain: "substack",
                title: post.title,
                subtitle: post.author ?? AppConstants.substackAuthorName,
                description: post.excerpt ?? post.contentHtml?.strippedHTML.clipped(260),
                keywords: post.categories,
                deepLink: .substackArticle(slug: post.slug)
            )
        })
    }

    func indexThreads(_ threads: [Thread]) async {
        await replace(domain: "thread", with: threads.map { thread in
            makeItem(
                identifier: AppDeepLink.thread(id: thread.id).searchableItemIdentifier ?? "thread:\(thread.id)",
                domain: "thread",
                title: thread.title,
                subtitle: thread.author?.username ?? thread.anonymousName ?? "Forum",
                description: thread.content.strippedMarkdown.clipped(260),
                keywords: [thread.categorySlug],
                deepLink: .thread(id: thread.id)
            )
        })
    }

    func indexQuotes(_ quotes: [QuoteNotebookItem]) async {
        await replace(domain: "quote", with: quotes.map { quote in
            makeItem(
                identifier: "quote:\(quote.id)",
                domain: "quote",
                title: quote.sourceTitle,
                subtitle: quote.sourceDetail,
                description: quote.text,
                keywords: [quote.sourceTitle, quote.sourceDetail].compactMap { $0 },
                deepLink: quote.routeBookId.map { .book(id: $0) } ?? .quoteNotebook
            )
        })
    }

    func indexContinueReading(_ items: [ContinueReadingItem]) async {
        await replace(domain: "continue", with: items.map { item in
            makeItem(
                identifier: "continue:\(item.bookId)",
                domain: "continue",
                title: item.title,
                subtitle: item.author,
                description: item.chapterTitle,
                keywords: [item.author, item.chapterTitle].compactMap { $0 },
                deepLink: .book(id: item.bookId)
            )
        })
    }

    private func makeItem(
        identifier: String,
        domain: String,
        title: String,
        subtitle: String?,
        description: String?,
        keywords: [String],
        deepLink: AppDeepLink
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = [subtitle, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        attributes.keywords = keywords.filter { !$0.isEmpty }
        attributes.contentURL = deepLink.url
        attributes.metadataModificationDate = Date()

        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domain,
            attributeSet: attributes
        )
    }

    private func replace(domain: String, with items: [CSSearchableItem]) async {
        await delete(domain: domain)
        await index(items)
    }

    private func delete(domain: String) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            print("Spotlight delete failed: \(error)")
        }
    }

    private func index(_ items: [CSSearchableItem]) async {
        guard !items.isEmpty else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                CSSearchableIndex.default().indexSearchableItems(items) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            print("Spotlight indexing failed: \(error)")
        }
    }
}

enum NotificationCategoryRegistrar {
    static func register() {
        let openThread = UNNotificationAction(
            identifier: "OPEN_THREAD",
            title: "Open Thread",
            options: [.foreground]
        )
        let openArticle = UNNotificationAction(
            identifier: "OPEN_ARTICLE",
            title: "Open Article",
            options: [.foreground]
        )
        let continueReading = UNNotificationAction(
            identifier: "CONTINUE_READING",
            title: "Continue Reading",
            options: [.foreground]
        )
        let viewNotifications = UNNotificationAction(
            identifier: "VIEW_NOTIFICATIONS",
            title: "View Alerts",
            options: [.foreground]
        )

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: "THREAD_ACTIVITY",
                actions: [openThread, viewNotifications],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "CONTINUE_READING",
                actions: [continueReading],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "NEW_ARTICLE",
                actions: [openArticle],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "FOLLOWED_USER_ACTIVITY",
                actions: [openThread, viewNotifications],
                intentIdentifiers: [],
                options: []
            )
        ]

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    static func deepLink(from userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) -> AppDeepLink? {
        if actionIdentifier == "VIEW_NOTIFICATIONS" {
            return .notifications
        }
        if actionIdentifier == "CONTINUE_READING" {
            return .continueReading
        }
        if let string = userInfo["deep_link"] as? String,
           let url = URL(string: string),
           let deepLink = AppDeepLink(url: url) {
            return deepLink
        }
        if let threadId = userInfo["thread_id"] as? String, !threadId.isEmpty {
            return .thread(id: threadId)
        }
        if let slug = (userInfo["article_slug"] as? String) ?? (userInfo["substack_slug"] as? String), !slug.isEmpty {
            return .substackArticle(slug: slug)
        }
        if let bookId = userInfo["book_id"] as? String, !bookId.isEmpty {
            return .book(id: bookId)
        }
        if let audiobookId = userInfo["audiobook_id"] as? String, !audiobookId.isEmpty {
            return .audiobook(id: audiobookId)
        }
        if let userId = userInfo["user_id"] as? String, !userId.isEmpty {
            return .userProfile(id: userId)
        }
        return nil
    }
}

private extension DateFormatter {
    static let systemSnapshotDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
