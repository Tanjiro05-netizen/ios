import AppIntents
import Foundation

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Reading"
    static let description = IntentDescription("Open the most recent book in MarxistInfo.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.continueReading.url))
    }
}

struct PlayCurrentAudiobookIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Current Audiobook"
    static let description = IntentDescription("Open the current audiobook in MarxistInfo.")

    func perform() async throws -> some IntentResult & OpensIntent {
        let snapshot = SystemIntegrationStore.loadSnapshot()
        let link: AppDeepLink = snapshot.currentAudiobook.map { .audiobook(id: $0.id) } ?? .audiobooks
        return .result(opensIntent: OpenURLIntent(link.url))
    }
}

struct OpenDailyQuoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Quote"
    static let description = IntentDescription("Open today's quote in MarxistInfo.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.dailyQuote.url))
    }
}

struct SearchArchiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Search MarxistInfo"
    static let description = IntentDescription("Search books, audiobooks, Substack articles, and forum content.")

    @Parameter(title: "Query")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search MarxistInfo for \(\.$query)")
    }

    init() {
        query = ""
    }

    init(query: String) {
        self.query = query
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.search(query: query).url))
    }
}

struct OpenBookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Book"
    static let description = IntentDescription("Open a book in MarxistInfo.")

    @Parameter(title: "Book")
    var book: BookIntentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$book)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.book(id: book.id).url))
    }
}

struct OpenAudiobookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Audiobook"
    static let description = IntentDescription("Open an audiobook in MarxistInfo.")

    @Parameter(title: "Audiobook")
    var audiobook: AudiobookIntentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$audiobook)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.audiobook(id: audiobook.id).url))
    }
}

struct OpenSubstackArticleIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Article"
    static let description = IntentDescription("Open a Substack article in MarxistInfo.")

    @Parameter(title: "Article")
    var article: ArticleIntentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$article)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.substackArticle(slug: article.id).url))
    }
}

struct OpenThreadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Thread"
    static let description = IntentDescription("Open a forum thread in MarxistInfo.")

    @Parameter(title: "Thread")
    var thread: ThreadIntentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$thread)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppDeepLink.thread(id: thread.id).url))
    }
}

struct MarxistForumShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .red

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "Open my book in \(.applicationName)"
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book"
        )
        AppShortcut(
            intent: PlayCurrentAudiobookIntent(),
            phrases: [
                "Play my audiobook in \(.applicationName)",
                "Continue listening in \(.applicationName)"
            ],
            shortTitle: "Play Audiobook",
            systemImageName: "headphones"
        )
        AppShortcut(
            intent: OpenDailyQuoteIntent(),
            phrases: [
                "Open today's quote in \(.applicationName)",
                "Show my daily quote in \(.applicationName)"
            ],
            shortTitle: "Daily Quote",
            systemImageName: "quote.bubble"
        )
        AppShortcut(
            intent: SearchArchiveIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search the archive in \(.applicationName)"
            ],
            shortTitle: "Search Archive",
            systemImageName: "magnifyingglass"
        )
    }
}

struct BookIntentEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Book")
    static let defaultQuery = BookIntentEntityQuery()

    var id: String
    var title: String
    var subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

struct BookIntentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [BookIntentEntity.ID]) async throws -> [BookIntentEntity] {
        let snapshot = SystemIntegrationStore.loadSnapshot()
        return identifiers.compactMap { id in
            guard snapshot.continueReading?.bookId == id else { return nil }
            return BookIntentEntity(
                id: id,
                title: snapshot.continueReading?.title ?? "Book",
                subtitle: snapshot.continueReading?.author
            )
        }
    }

    func entities(matching string: String) async throws -> [BookIntentEntity] {
        try await suggestedEntities().filter {
            "\($0.title) \($0.subtitle ?? "")".localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [BookIntentEntity] {
        guard let item = SystemIntegrationStore.loadSnapshot().continueReading else { return [] }
        return [BookIntentEntity(id: item.bookId, title: item.title, subtitle: item.author)]
    }
}

struct AudiobookIntentEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Audiobook")
    static let defaultQuery = AudiobookIntentEntityQuery()

    var id: String
    var title: String
    var subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

struct AudiobookIntentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [AudiobookIntentEntity.ID]) async throws -> [AudiobookIntentEntity] {
        let snapshot = SystemIntegrationStore.loadSnapshot()
        return identifiers.compactMap { id in
            guard snapshot.currentAudiobook?.id == id else { return nil }
            return AudiobookIntentEntity(
                id: id,
                title: snapshot.currentAudiobook?.title ?? "Audiobook",
                subtitle: snapshot.currentAudiobook?.author ?? snapshot.currentAudiobook?.narrator
            )
        }
    }

    func entities(matching string: String) async throws -> [AudiobookIntentEntity] {
        try await suggestedEntities().filter {
            "\($0.title) \($0.subtitle ?? "")".localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [AudiobookIntentEntity] {
        guard let item = SystemIntegrationStore.loadSnapshot().currentAudiobook else { return [] }
        return [AudiobookIntentEntity(id: item.id, title: item.title, subtitle: item.author ?? item.narrator)]
    }
}

struct ArticleIntentEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Article")
    static let defaultQuery = ArticleIntentEntityQuery()

    var id: String
    var title: String
    var subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

struct ArticleIntentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [ArticleIntentEntity.ID]) async throws -> [ArticleIntentEntity] {
        SystemIntegrationStore.loadSnapshot().latestUpdates
            .filter { $0.kind == .substack && identifiers.contains($0.deepLinkURL.lastPathComponent) }
            .map { ArticleIntentEntity(id: $0.deepLinkURL.lastPathComponent, title: $0.title, subtitle: $0.subtitle) }
    }

    func entities(matching string: String) async throws -> [ArticleIntentEntity] {
        try await suggestedEntities().filter {
            "\($0.title) \($0.subtitle ?? "")".localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [ArticleIntentEntity] {
        SystemIntegrationStore.loadSnapshot().latestUpdates
            .filter { $0.kind == .substack }
            .map { ArticleIntentEntity(id: $0.deepLinkURL.lastPathComponent, title: $0.title, subtitle: $0.subtitle) }
    }
}

struct ThreadIntentEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Thread")
    static let defaultQuery = ThreadIntentEntityQuery()

    var id: String
    var title: String
    var subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }
}

struct ThreadIntentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [ThreadIntentEntity.ID]) async throws -> [ThreadIntentEntity] {
        SystemIntegrationStore.loadSnapshot().latestUpdates
            .filter { $0.kind == .forum && identifiers.contains($0.deepLinkURL.lastPathComponent) }
            .map { ThreadIntentEntity(id: $0.deepLinkURL.lastPathComponent, title: $0.title, subtitle: $0.subtitle) }
    }

    func entities(matching string: String) async throws -> [ThreadIntentEntity] {
        try await suggestedEntities().filter {
            "\($0.title) \($0.subtitle ?? "")".localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [ThreadIntentEntity] {
        SystemIntegrationStore.loadSnapshot().latestUpdates
            .filter { $0.kind == .forum }
            .map { ThreadIntentEntity(id: $0.deepLinkURL.lastPathComponent, title: $0.title, subtitle: $0.subtitle) }
    }
}
