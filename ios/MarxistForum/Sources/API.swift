import Foundation
import UIKit
import UserNotifications

enum APIError: LocalizedError {
    case invalidURL
    case server(Int, String)
    case emptyResponse
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid Supabase URL."
        case .server(let code, let body):
            "Supabase request failed (\(code)): \(body)"
        case .emptyResponse:
            "Supabase returned an empty response."
        case .authenticationRequired:
            "Your session has expired. Please sign in again."
        }
    }

    var isUnauthorized: Bool {
        if case .server(let code, _) = self {
            return code == 401
        }
        return false
    }
}

enum SubstackError: LocalizedError {
    case archiveMissing
    case feed(String)

    var errorDescription: String? {
        switch self {
        case .archiveMissing:
            "The bundled Substack archive is missing."
        case .feed(let message):
            message
        }
    }
}

struct EmptyPayload: Codable {}

struct ReadingProgressRemote: Codable {
    var userId: String
    var bookId: String
    var title: String
    var author: String?
    var chapterTitle: String?
    var chapterIndex: Int
    var chapterCount: Int
    var progress: Double
    var updatedAt: String
}

struct ReadingQuoteRemote: Codable {
    var userId: String
    var quoteId: String
    var text: String
    var sourceTitle: String
    var sourceDetail: String?
    var routeBookId: String?
    var createdAt: String
    var updatedAt: String
}

extension AuthSession {
    var accessTokenExpirationDate: Date? {
        let components = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return nil }

        var encodedPayload = String(components[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload.append(String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4))

        guard encodedPayload.count <= 16_384,
              let payload = Data(base64Encoded: encodedPayload),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let expiration = object["exp"] as? NSNumber,
              expiration.doubleValue.isFinite else {
            return nil
        }
        return Date(timeIntervalSince1970: expiration.doubleValue)
    }

    func preservingRefreshToken(from previous: AuthSession) -> AuthSession {
        guard refreshToken?.isEmpty != false else { return self }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: previous.refreshToken,
            user: user
        )
    }
}

/// Short-lived in-memory cache for archive content.  Views are recreated when
/// switching tabs, so keeping the cache outside individual clients prevents a
/// tab change from turning into another round-trip to Supabase.
@MainActor
private final class ArchiveContentCache {
    static let shared = ArchiveContentCache()

    struct Entry<Value> {
        let value: Value
        let date: Date
    }

    let listLifetime: TimeInterval = 60
    let detailLifetime: TimeInterval = 300

    var books: [String: Entry<[Book]>] = [:]
    var bookDetails: [String: Entry<Book>] = [:]
    var categories: Entry<[String]>?
    var audiobooks: Entry<[Audiobook]>?
    var audiobookDetails: [String: Entry<Audiobook>] = [:]
    var substack: Entry<SubstackLoadResult>?
    var threads: [String: Entry<[Thread]>] = [:]
    var threadDetails: [String: Entry<Thread>] = [:]
    var comments: [String: Entry<[Comment]>] = [:]
    var notifications: [String: Entry<[NotificationItem]>] = [:]

    func isFresh(_ date: Date, lifetime: TimeInterval) -> Bool {
        Date().timeIntervalSince(date) < lifetime
    }
}

final class SupabaseRESTClient: @unchecked Sendable {
    let baseURL: URL
    let anonKey: String
    private let urlSession: URLSession

    init(
        baseURL: URL = AppConstants.supabaseURL,
        anonKey: String = AppConstants.supabaseAnonKey,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.urlSession = urlSession
    }

    func fetchArray<T: Decodable>(
        table: String,
        queryItems: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> [T] {
        try await request(path: "/rest/v1/\(table)", queryItems: queryItems, method: "GET", body: Optional<EmptyPayload>.none, accessToken: accessToken)
    }

    func insert<T: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        returning: T.Type,
        accessToken: String? = nil,
        prefer: String = "return=representation"
    ) async throws -> [T] {
        try await request(
            path: "/rest/v1/\(table)",
            queryItems: [URLQueryItem(name: "select", value: "*")],
            method: "POST",
            body: body,
            accessToken: accessToken,
            prefer: prefer
        )
    }

    func update<Body: Encodable>(
        table: String,
        filters: [URLQueryItem],
        body: Body,
        accessToken: String? = nil
    ) async throws {
        let _: EmptyPayload = try await request(
            path: "/rest/v1/\(table)",
            queryItems: filters,
            method: "PATCH",
            body: body,
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    func delete(table: String, filters: [URLQueryItem], accessToken: String? = nil) async throws {
        let _: EmptyPayload = try await request(
            path: "/rest/v1/\(table)",
            queryItems: filters,
            method: "DELETE",
            body: Optional<EmptyPayload>.none,
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    func upsert<Body: Encodable>(table: String, body: Body, accessToken: String) async throws {
        let _: EmptyPayload = try await request(
            path: "/rest/v1/\(table)",
            queryItems: [],
            method: "POST",
            body: body,
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func rpc<T: Decodable, Body: Encodable>(
        function: String,
        body: Body,
        returning: T.Type = T.self,
        accessToken: String
    ) async throws -> T {
        try await request(
            path: "/rest/v1/rpc/\(function)",
            queryItems: [],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
    }

    func authSignIn(email: String, password: String) async throws -> AuthSession {
        let body = ["email": email, "password": password]
        return try await request(path: "/auth/v1/token", queryItems: [URLQueryItem(name: "grant_type", value: "password")], method: "POST", body: body)
    }

    func authRefresh(refreshToken: String) async throws -> AuthSession {
        struct RefreshBody: Encodable {
            var refreshToken: String
        }

        return try await request(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken)
        )
    }

    func authSignUp(email: String, password: String, username: String?, inviteCode: String?) async throws -> AuthSession? {
        struct SignUpBody: Encodable {
            var email: String
            var password: String
            var data: [String: String]
        }
        struct SignUpResponse: Decodable {
            var accessToken: String?
            var refreshToken: String?
            // GoTrue returns an access-token response (with a nested user)
            // when autoconfirm is enabled, but a user object directly when
            // email confirmation is required. Keeping this optional lets the
            // same response type decode both documented shapes.
            var user: SupabaseUser?
        }

        let body = SignUpBody(
            email: email,
            password: password,
            data: [
                "user_name": username ?? "",
                "invite_code": inviteCode ?? ""
            ]
        )
        let response: SignUpResponse = try await request(
            path: "/auth/v1/signup",
            queryItems: [],
            method: "POST",
            body: body
        )
        guard let accessToken = response.accessToken,
              !accessToken.isEmpty,
              let user = response.user else {
            // Email confirmation can return a user without creating a session.
            return nil
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            user: user
        )
    }

    func authSignInWithApple(idToken: String, nonce: String?) async throws -> AuthSession {
        struct SignInBody: Encodable {
            var provider: String
            var token: String
            var nonce: String?
        }

        let body = SignInBody(provider: "apple", token: idToken, nonce: nonce)
        return try await request(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            method: "POST",
            body: body
        )
    }

    func authSignOut(accessToken: String) async {
        do {
            let _: EmptyPayload = try await request(path: "/auth/v1/logout", queryItems: [], method: "POST", body: Optional<EmptyPayload>.none, accessToken: accessToken)
        } catch {
            // Local sign-out should proceed even when the remote session is already gone.
        }
    }

    func exchangeAppleAuthorizationCode(accessToken: String, authorizationCode: String) async throws {
        struct Body: Encodable {
            var authorizationCode: String
        }

        let _: EmptyPayload = try await request(
            path: "/functions/v1/apple-token-exchange",
            queryItems: [],
            method: "POST",
            body: Body(authorizationCode: authorizationCode),
            accessToken: accessToken
        )
    }

    func deleteAccount(accessToken: String) async throws {
        let _: EmptyPayload = try await request(
            path: "/functions/v1/delete-account",
            queryItems: [],
            method: "POST",
            body: Optional<EmptyPayload>.none,
            accessToken: accessToken
        )
    }

    func publicStorageURL(bucket: String = "library", filename: String) -> URL {
        baseURL
            .appending(path: "storage/v1/object/public")
            .appending(path: bucket)
            .appending(path: filename)
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body? = nil,
        accessToken: String? = nil,
        prefer: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.supabase.encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw APIError.server(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty {
            if T.self == EmptyPayload.self {
                return EmptyPayload() as! T
            }
            throw APIError.emptyResponse
        }
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }
}

@MainActor
final class LibraryClient {
    private let client: SupabaseRESTClient
    private let cache = ArchiveContentCache.shared

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchBooks(scope: LibraryScope, category: String?, search: String, forceRefresh: Bool = false) async throws -> [Book] {
        let key = "\(scope.rawValue)|\(category ?? "")|\(search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        if !forceRefresh,
           let cached = cache.books[key],
           cache.isFresh(cached.date, lifetime: cache.listLifetime) {
            return cached.value
        }

        var items = [
            // text_edition is deliberately excluded: editions are hundreds of
            // kilobytes each, and the reader fetches them via fetchBook(id:).
            URLQueryItem(
                name: "select",
                value: "id,title,author,year,description,cover_image_url,pdf_filename,epub_filename,pages,downloads,created_at,category,era,language,is_official"
            ),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "is_official", value: "eq.\(scope == .official ? "true" : "false")")
        ]
        if let category, !category.isEmpty {
            items.append(URLQueryItem(name: "category", value: "eq.\(category)"))
        }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let escaped = trimmed.replacingOccurrences(of: ",", with: " ")
            items.append(URLQueryItem(name: "or", value: "(title.ilike.*\(escaped)*,author.ilike.*\(escaped)*,description.ilike.*\(escaped)*)"))
        }
        let books: [Book] = try await client.fetchArray(table: "digital_library_books", queryItems: items)
        cache.books[key] = .init(value: books, date: Date())
        return books
    }

    func fetchBook(id: String, forceRefresh: Bool = false) async throws -> Book? {
        if !forceRefresh,
           let cached = cache.bookDetails[id],
           cache.isFresh(cached.date, lifetime: cache.detailLifetime) {
            return cached.value
        }

        let books: [Book] = try await client.fetchArray(
            table: "digital_library_books",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "limit", value: "1")]
        )
        if let book = books.first {
            cache.bookDetails[id] = .init(value: book, date: Date())
        }
        return books.first
    }

    func fetchCategories(forceRefresh: Bool = false) async throws -> [String] {
        if !forceRefresh,
           let cached = cache.categories,
           cache.isFresh(cached.date, lifetime: cache.detailLifetime) {
            return cached.value
        }

        let books: [Book] = try await client.fetchArray(
            table: "digital_library_books",
            queryItems: [
                URLQueryItem(name: "select", value: "category"),
                URLQueryItem(name: "category", value: "not.is.null"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )
        let categories = Array(Set(books.compactMap(\.category))).sorted()
        cache.categories = .init(value: categories, date: Date())
        return categories
    }

    func epubURL(filename: String) -> URL {
        client.publicStorageURL(filename: filename)
    }

    func pdfURL(filename: String) -> URL {
        client.publicStorageURL(filename: filename)
    }
}

@MainActor
final class AudiobookClient {
    private let client: SupabaseRESTClient
    private let cache = ArchiveContentCache.shared

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchAudiobooks(forceRefresh: Bool = false) async throws -> [Audiobook] {
        if !forceRefresh,
           let cached = cache.audiobooks,
           cache.isFresh(cached.date, lifetime: cache.listLifetime) {
            return cached.value
        }

        let audiobooks: [Audiobook] = try await client.fetchArray(
            table: "audiobooks",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "order", value: "sort_order.asc")]
        )
        cache.audiobooks = .init(value: audiobooks, date: Date())
        for audiobook in audiobooks {
            cache.audiobookDetails[audiobook.id] = .init(value: audiobook, date: Date())
        }
        return audiobooks
    }

    func fetchAudiobook(id: String, forceRefresh: Bool = false) async throws -> Audiobook? {
        if !forceRefresh,
           let cached = cache.audiobookDetails[id],
           cache.isFresh(cached.date, lifetime: cache.detailLifetime) {
            return cached.value
        }

        let rows: [Audiobook] = try await client.fetchArray(
            table: "audiobooks",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        if let audiobook = rows.first {
            cache.audiobookDetails[id] = .init(value: audiobook, date: Date())
        }
        return rows.first
    }
}

struct SubstackLoadResult: Hashable {
    var source: SubstackSource
    var posts: [SubstackArticle]
    var feedError: String?
    var archiveError: String?
}

@MainActor
final class SubstackClient {
    private let cache = ArchiveContentCache.shared

    func loadPosts(forceRefresh: Bool = false) async -> SubstackLoadResult {
        if !forceRefresh,
           let cached = cache.substack,
           cache.isFresh(cached.date, lifetime: cache.listLifetime) {
            return cached.value
        }

        // The bundled archive is local and should be visible immediately. The
        // live feed refreshes in the background instead of holding the whole
        // Substack page behind a potentially slow edge function.
        let archive = Self.fetchArchiveResult()
        guard let archivePayload = try? archive.get() else {
            let live = await Self.fetchLiveResult()
            let livePayload = try? live.get()
            let result = SubstackLoadResult(
                source: livePayload?.source ?? .fallback,
                posts: livePayload?.posts ?? [],
                feedError: live.failureMessage,
                archiveError: archive.failureMessage
            )
            cache.substack = .init(value: result, date: Date())
            return result
        }

        let initial = SubstackLoadResult(
            source: archivePayload.source ?? .fallback,
            posts: archivePayload.posts,
            feedError: nil,
            archiveError: archive.failureMessage
        )
        cache.substack = .init(value: initial, date: Date())

        Task { @MainActor in
            let live = await Self.fetchLiveResult()
            guard let livePayload = try? live.get() else { return }
            let refreshed = SubstackLoadResult(
                source: livePayload.source ?? .fallback,
                posts: Self.merge(livePosts: livePayload.posts, archivePosts: archivePayload.posts),
                feedError: nil,
                archiveError: archive.failureMessage
            )
            self.cache.substack = .init(value: refreshed, date: Date())
        }
        return initial
    }

    private static func fetchArchiveResult() -> Result<SubstackPayload, Error> {
        do {
            return .success(try fetchBundledArchive())
        } catch {
            return .failure(error)
        }
    }

    private static func fetchLiveResult() async -> Result<SubstackPayload, Error> {
        do {
            return .success(try await fetchLiveFeed())
        } catch {
            return .failure(error)
        }
    }

    private static func fetchBundledArchive() throws -> SubstackPayload {
        guard let url = Bundle.main.url(forResource: "substack-archive", withExtension: "json") else {
            throw SubstackError.archiveMissing
        }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder.supabase.decode(SubstackPayload.self, from: data)
        return SubstackPayload(
            source: payload.source,
            posts: payload.posts.map { $0.normalized() },
            error: payload.error
        )
    }

    private static func fetchLiveFeed() async throws -> SubstackPayload {
        let url = AppConstants.supabaseURL.appending(path: "functions/v1/substack-feed")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue(AppConstants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConstants.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw SubstackError.feed("Live Substack feed failed with \(statusCode).")
        }
        let payload = try JSONDecoder.supabase.decode(SubstackPayload.self, from: data)
        if let error = payload.error, !error.isEmpty {
            throw SubstackError.feed(error)
        }
        return SubstackPayload(
            source: payload.source,
            posts: payload.posts.map { $0.normalized() },
            error: payload.error
        )
    }

    nonisolated static func merge(livePosts: [SubstackArticle], archivePosts: [SubstackArticle]) -> [SubstackArticle] {
        var bySlug: [String: SubstackArticle] = [:]

        for post in archivePosts.map({ $0.normalized() }) where !post.slug.isEmpty {
            bySlug[post.slug] = post
        }

        for post in livePosts.map({ $0.normalized() }) where !post.slug.isEmpty {
            if let existing = bySlug[post.slug] {
                var merged = post
                if merged.imageUrl == nil {
                    merged.imageUrl = existing.imageUrl
                }
                if merged.contentHtml?.isEmpty != false {
                    merged.contentHtml = existing.contentHtml
                }
                if merged.excerpt?.isEmpty != false {
                    merged.excerpt = existing.excerpt
                }
                bySlug[post.slug] = merged.normalized()
            } else {
                bySlug[post.slug] = post
            }
        }

        return bySlug.values.sorted {
            ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
        }
    }
}

enum GlobalSearchSection: String, CaseIterable, Identifiable {
    case books
    case audiobooks
    case substack
    case forum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .books: "Library"
        case .audiobooks: "Audio"
        case .substack: "Substack"
        case .forum: "Forum"
        }
    }
}

enum GlobalSearchTarget: Hashable {
    case book(id: String)
    case audiobook(Audiobook)
    case substack(slug: String)
    case thread(id: String)
}

struct GlobalSearchResult: Identifiable, Hashable {
    let id: String
    let section: GlobalSearchSection
    let title: String
    let subtitle: String
    let detail: String?
    let imageURL: String?
    let systemImage: String
    let target: GlobalSearchTarget
}

private struct SubstackSearchDocument {
    let post: SubstackArticle
    let searchableText: String
}

enum GlobalSearchMatcher {
    static func matches(_ values: [String?], query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return values
            .compactMap { $0 }
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(normalizedQuery)
    }
}

@MainActor
final class GlobalSearchClient {
    private let libraryClient = LibraryClient()
    private let audiobookClient = AudiobookClient()
    private let substackClient = SubstackClient()
    private let forumClient = ForumClient()

    private var cachedAudiobooks: [Audiobook]?
    private var cachedSubstackDocuments: [SubstackSearchDocument]?
    private var cachedThreads: [Thread]?

    func search(query: String) async -> [GlobalSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        if AppFeatureFlags.forumEnabled {
            async let books = searchBooks(query: trimmed)
            async let audiobooks = searchAudiobooks(query: trimmed)
            async let substack = searchSubstack(query: trimmed)
            async let threads = searchThreads(query: trimmed)
            let (bookResults, audiobookResults, substackResults, threadResults) = await (books, audiobooks, substack, threads)
            return bookResults + audiobookResults + substackResults + threadResults
        }

        async let books = searchBooks(query: trimmed)
        async let audiobooks = searchAudiobooks(query: trimmed)
        async let substack = searchSubstack(query: trimmed)
        let (bookResults, audiobookResults, substackResults) = await (books, audiobooks, substack)
        return bookResults + audiobookResults + substackResults
    }

    private func searchBooks(query: String) async -> [GlobalSearchResult] {
        do {
            async let official = libraryClient.fetchBooks(scope: .official, category: nil, search: query)
            async let community = libraryClient.fetchBooks(scope: .community, category: nil, search: query)
            let (officialBooks, communityBooks) = try await (official, community)
            return Array((officialBooks + communityBooks).uniqued(by: \.id).prefix(8)).map { book in
                GlobalSearchResult(
                    id: "book-\(book.id)",
                    section: .books,
                    title: book.title,
                    subtitle: book.author ?? "Unknown Author",
                    detail: [book.category, book.year.map(String.init)].compactMap { $0 }.joined(separator: " · ").nilIfBlank,
                    imageURL: book.coverImageUrl,
                    systemImage: "books.vertical",
                    target: .book(id: book.id)
                )
            }
        } catch {
            return []
        }
    }

    private func searchAudiobooks(query: String) async -> [GlobalSearchResult] {
        do {
            let audiobooks: [Audiobook]
            if let cachedAudiobooks {
                audiobooks = cachedAudiobooks
            } else {
                audiobooks = try await audiobookClient.fetchAudiobooks()
                cachedAudiobooks = audiobooks
            }
            return audiobooks
                .filter {
                    GlobalSearchMatcher.matches(
                        [$0.title, $0.author, $0.narrator, $0.description, $0.category],
                        query: query
                    )
                }
                .prefix(8)
                .map { audiobook in
                    GlobalSearchResult(
                        id: "audio-\(audiobook.id)",
                        section: .audiobooks,
                        title: audiobook.title,
                        subtitle: audiobook.author ?? audiobook.narrator ?? "Audiobook",
                        detail: audiobook.durationSeconds.map(formatTime),
                        imageURL: audiobook.coverUrl,
                        systemImage: "headphones",
                        target: .audiobook(audiobook)
                    )
                }
        } catch {
            return []
        }
    }

    private func searchSubstack(query: String) async -> [GlobalSearchResult] {
        let documents: [SubstackSearchDocument]
        if let cachedSubstackDocuments {
            documents = cachedSubstackDocuments
        } else {
            let loaded = await substackClient.loadPosts()
            documents = loaded.posts.map { post in
                SubstackSearchDocument(
                    post: post,
                    searchableText: [
                        post.title,
                        post.excerpt ?? "",
                        post.author ?? "",
                        post.categories.joined(separator: " "),
                        post.contentHtml?.strippedHTML ?? ""
                    ]
                    .joined(separator: " ")
                )
            }
            cachedSubstackDocuments = documents
        }

        return documents
            .filter {
                $0.searchableText.localizedCaseInsensitiveContains(query)
            }
            .prefix(8)
            .map { document in
                let post = document.post
                return GlobalSearchResult(
                    id: "substack-\(post.slug)",
                    section: .substack,
                    title: post.title,
                    subtitle: post.author ?? AppConstants.substackAuthorName,
                    detail: post.displayDate,
                    imageURL: post.imageUrl,
                    systemImage: "newspaper",
                    target: .substack(slug: post.slug)
                )
            }
    }

    private func searchThreads(query: String) async -> [GlobalSearchResult] {
        do {
            let threads: [Thread]
            if let cachedThreads {
                threads = cachedThreads
            } else {
                threads = try await forumClient.fetchThreads(board: nil, sort: "recent")
                cachedThreads = threads
            }
            return threads
                .filter {
                    GlobalSearchMatcher.matches(
                        [$0.title, $0.content, $0.author?.username, $0.categorySlug],
                        query: query
                    )
                }
                .prefix(8)
                .map { thread in
                    GlobalSearchResult(
                        id: "thread-\(thread.id)",
                        section: .forum,
                        title: thread.title,
                        subtitle: thread.author?.username ?? thread.anonymousName ?? "Forum",
                        detail: thread.content.strippedMarkdown.clipped(90),
                        imageURL: thread.author?.avatarUrl,
                        systemImage: "bubble.left.and.bubble.right",
                        target: .thread(id: thread.id)
                    )
                }
        } catch {
            return []
        }
    }
}

private extension Result {
    var failureMessage: String? {
        guard case .failure(let error) = self else { return nil }
        return error.localizedDescription
    }
}

private extension Array {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen: Set<ID> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class ForumClient {
    private let client: SupabaseRESTClient
    private let cache = ArchiveContentCache.shared

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchThreads(board: String?, sort: String, forceRefresh: Bool = false) async throws -> [Thread] {
        let key = "\(board ?? "*")|\(sort)"
        if !forceRefresh,
           let cached = cache.threads[key],
           cache.isFresh(cached.date, lifetime: cache.listLifetime) {
            return cached.value
        }

        var items = [
            URLQueryItem(name: "select", value: "*,author:profiles!forum_threads_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
            URLQueryItem(name: "order", value: "is_pinned.desc"),
            URLQueryItem(name: "order", value: sort == "popular" ? "like_count.desc" : "created_at.desc"),
            URLQueryItem(name: "limit", value: "30")
        ]
        if let board {
            items.append(URLQueryItem(name: "category_slug", value: "eq.\(board)"))
        }
        let threads: [Thread] = try await client.fetchArray(table: "forum_threads", queryItems: items)
        cache.threads[key] = .init(value: threads, date: Date())
        for thread in threads {
            cache.threadDetails[thread.id] = .init(value: thread, date: Date())
        }
        return threads
    }

    func fetchThread(id: String, forceRefresh: Bool = false) async throws -> Thread? {
        if !forceRefresh,
           let cached = cache.threadDetails[id],
           cache.isFresh(cached.date, lifetime: cache.detailLifetime) {
            return cached.value
        }

        let rows: [Thread] = try await client.fetchArray(
            table: "forum_threads",
            queryItems: [
                URLQueryItem(name: "select", value: "*,author:profiles!forum_threads_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        if let thread = rows.first {
            cache.threadDetails[id] = .init(value: thread, date: Date())
        }
        return rows.first
    }

    func fetchComments(threadId: String, forceRefresh: Bool = false) async throws -> [Comment] {
        if !forceRefresh,
           let cached = cache.comments[threadId],
           cache.isFresh(cached.date, lifetime: cache.detailLifetime) {
            return cached.value
        }

        let comments: [Comment] = try await client.fetchArray(
            table: "forum_comments",
            queryItems: [
                URLQueryItem(name: "select", value: "*,author:profiles!forum_comments_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
                URLQueryItem(name: "thread_id", value: "eq.\(threadId)"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ]
        )
        cache.comments[threadId] = .init(value: comments, date: Date())
        return comments
    }

    func fetchProfile(id: String) async throws -> Profile? {
        let rows: [Profile] = try await client.fetchArray(
            table: "profiles",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "limit", value: "1")]
        )
        return rows.first
    }

    func updateProfile(id: String, username: String, accessToken: String?) async throws {
        struct Body: Encodable {
            var username: String
        }

        try await client.update(
            table: "profiles",
            filters: [URLQueryItem(name: "id", value: "eq.\(id)")],
            body: Body(username: username),
            accessToken: accessToken
        )
    }

    func createThread(title: String, content: String, category: String, auth: AuthStore) async throws {
        struct Body: Encodable {
            var title: String
            var content: String
            var categorySlug: String
            var authorId: String?
            var anonymousName: String?
        }
        let body = Body(title: title, content: content, categorySlug: category, authorId: auth.userId, anonymousName: auth.guestSession?.username)
        let _: [Thread] = try await client.insert(table: "forum_threads", body: body, returning: Thread.self, accessToken: auth.accessToken)
    }
}

@MainActor
final class ReadingSyncClient {
    private let client: SupabaseRESTClient

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchProgress(userId: String, accessToken: String) async throws -> [ReadingProgressRemote] {
        try await client.fetchArray(
            table: "reading_progress",
            queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "updated_at.desc"),
                URLQueryItem(name: "limit", value: "200")
            ],
            accessToken: accessToken
        )
    }

    func fetchQuotes(userId: String, accessToken: String) async throws -> [ReadingQuoteRemote] {
        try await client.fetchArray(
            table: "reading_quotes",
            queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "updated_at.desc"),
                URLQueryItem(name: "limit", value: "300")
            ],
            accessToken: accessToken
        )
    }

    func upsertProgress(_ item: ContinueReadingItem, userId: String, accessToken: String) async throws {
        let remote = ReadingProgressRemote(
            userId: userId,
            bookId: item.bookId,
            title: item.title,
            author: item.author,
            chapterTitle: item.chapterTitle,
            chapterIndex: item.chapterIndex,
            chapterCount: item.chapterCount,
            progress: item.progress,
            updatedAt: item.updatedAt
        )
        try await client.upsert(table: "reading_progress", body: remote, accessToken: accessToken)
    }

    func upsertQuote(_ item: QuoteNotebookItem, userId: String, accessToken: String) async throws {
        let remote = ReadingQuoteRemote(
            userId: userId,
            quoteId: item.id,
            text: item.text,
            sourceTitle: item.sourceTitle,
            sourceDetail: item.sourceDetail,
            routeBookId: item.routeBookId,
            createdAt: item.createdAt,
            updatedAt: item.createdAt
        )
        try await client.upsert(table: "reading_quotes", body: remote, accessToken: accessToken)
    }

    func deleteQuote(id: String, userId: String, accessToken: String) async throws {
        try await client.delete(
            table: "reading_quotes",
            filters: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "quote_id", value: "eq.\(id)")
            ],
            accessToken: accessToken
        )
    }
}

@MainActor
final class NotificationClient {
    private let client: SupabaseRESTClient

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchNotifications(userId: String, accessToken: String?, forceRefresh: Bool = false) async throws -> [NotificationItem] {
        if !forceRefresh,
           let cached = ArchiveContentCache.shared.notifications[userId],
           ArchiveContentCache.shared.isFresh(cached.date, lifetime: ArchiveContentCache.shared.listLifetime) {
            return cached.value
        }

        let notifications: [NotificationItem] = try await client.fetchArray(
            table: "forum_notifications",
            queryItems: [
                URLQueryItem(name: "select", value: "id,type,content_preview,is_read,created_at,thread_id,comment_id,source_user:profiles!forum_notifications_source_user_id_fkey(id,username,avatar_url)"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")
            ],
            accessToken: accessToken
        )
        ArchiveContentCache.shared.notifications[userId] = .init(value: notifications, date: Date())
        return notifications
    }

    func unreadCount(userId: String, accessToken: String?) async -> Int {
        do {
            let rows: [NotificationItem] = try await client.fetchArray(
                table: "forum_notifications",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,type,created_at"),
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "is_read", value: "eq.false")
                ],
                accessToken: accessToken
            )
            return rows.count
        } catch {
            return 0
        }
    }

    func markRead(notificationId: String, accessToken: String?) async {
        struct Body: Encodable {
            var isRead: Bool
        }

        do {
            try await client.update(
                table: "forum_notifications",
                filters: [URLQueryItem(name: "id", value: "eq.\(notificationId)")],
                body: Body(isRead: true),
                accessToken: accessToken
            )
        } catch {
            print("Marking notification read failed: \(error)")
        }
    }
}

@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()
    private let client = SupabaseRESTClient()
    var userId: String?
    var accessToken: String?

    func configure(userId: String?, accessToken: String?) {
        self.userId = userId
        self.accessToken = accessToken
    }

    func registerIfPossible() async {
        guard userId != nil else { return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    func save(deviceToken: String) async {
        guard let userId else { return }
        struct Body: Encodable {
            var userId: String
            var platform: String
            var provider: String
            var token: String
            var enabled: Bool
            var lastSeenAt: String
        }
        do {
            let body = Body(userId: userId, platform: "ios", provider: "apns", token: deviceToken, enabled: true, lastSeenAt: ISO8601DateFormatter().string(from: Date()))
            let _: [EmptyPayload] = try await client.insert(table: "push_tokens", body: body, returning: EmptyPayload.self, accessToken: accessToken, prefer: "return=minimal,resolution=merge-duplicates")
        } catch {
            print("Saving APNs token failed: \(error)")
        }
    }
}
