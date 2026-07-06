import Foundation
import UIKit
import UserNotifications

enum APIError: LocalizedError {
    case invalidURL
    case server(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid Supabase URL."
        case .server(let code, let body):
            "Supabase request failed (\(code)): \(body)"
        case .emptyResponse:
            "Supabase returned an empty response."
        }
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

final class SupabaseRESTClient: @unchecked Sendable {
    let baseURL: URL
    let anonKey: String

    init(baseURL: URL = AppConstants.supabaseURL, anonKey: String = AppConstants.supabaseAnonKey) {
        self.baseURL = baseURL
        self.anonKey = anonKey
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

    func authSignIn(email: String, password: String) async throws -> AuthSession {
        let body = ["email": email, "password": password]
        return try await request(path: "/auth/v1/token", queryItems: [URLQueryItem(name: "grant_type", value: "password")], method: "POST", body: body)
    }

    func authSignUp(email: String, password: String, username: String?, inviteCode: String?) async throws -> AuthSession? {
        struct SignUpBody: Encodable {
            var email: String
            var password: String
            var data: [String: String]
        }

        let body = SignUpBody(
            email: email,
            password: password,
            data: [
                "user_name": username ?? "",
                "invite_code": inviteCode ?? ""
            ]
        )
        return try await requestOptional(path: "/auth/v1/signup", queryItems: [], method: "POST", body: body)
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

    func publicStorageURL(bucket: String = "library", filename: String) -> URL {
        baseURL
            .appending(path: "storage/v1/object/public")
            .appending(path: bucket)
            .appending(path: filename)
    }

    private func requestOptional<T: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body? = nil,
        accessToken: String? = nil,
        prefer: String? = nil
    ) async throws -> T? {
        do {
            return try await request(path: path, queryItems: queryItems, method: method, body: body, accessToken: accessToken, prefer: prefer)
        } catch APIError.emptyResponse {
            return nil
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)
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

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchBooks(scope: LibraryScope, category: String?, search: String) async throws -> [Book] {
        var items = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "40"),
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
        return try await client.fetchArray(table: "digital_library_books", queryItems: items)
    }

    func fetchBook(id: String) async throws -> Book? {
        let books: [Book] = try await client.fetchArray(
            table: "digital_library_books",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "limit", value: "1")]
        )
        return books.first
    }

    func fetchCategories() async throws -> [String] {
        let books: [Book] = try await client.fetchArray(
            table: "digital_library_books",
            queryItems: [URLQueryItem(name: "select", value: "category"), URLQueryItem(name: "category", value: "not.is.null")]
        )
        return Array(Set(books.compactMap(\.category))).sorted()
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

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchAudiobooks() async throws -> [Audiobook] {
        try await client.fetchArray(
            table: "audiobooks",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "order", value: "sort_order.asc")]
        )
    }

    func fetchAudiobook(id: String) async throws -> Audiobook? {
        let rows: [Audiobook] = try await client.fetchArray(
            table: "audiobooks",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return rows.first
    }
}

struct SubstackLoadResult: Hashable {
    var source: SubstackSource
    var posts: [SubstackArticle]
    var feedError: String?
    var archiveError: String?
}

final class SubstackClient: Sendable {
    func loadPosts() async -> SubstackLoadResult {
        async let archiveResult = Self.fetchArchiveResult()
        async let liveResult = Self.fetchLiveResult()
        let archive = await archiveResult
        let live = await liveResult

        let archivePayload = try? archive.get()
        let livePayload = try? live.get()
        let posts = Self.merge(
            livePosts: livePayload?.posts ?? [],
            archivePosts: archivePayload?.posts ?? []
        )

        return SubstackLoadResult(
            source: livePayload?.source ?? archivePayload?.source ?? .fallback,
            posts: posts,
            feedError: live.failureMessage,
            archiveError: archive.failureMessage
        )
    }

    private static func fetchArchiveResult() async -> Result<SubstackPayload, Error> {
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

    static func merge(livePosts: [SubstackArticle], archivePosts: [SubstackArticle]) -> [SubstackArticle] {
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

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchThreads(board: String?, sort: String) async throws -> [Thread] {
        var items = [
            URLQueryItem(name: "select", value: "*,author:profiles!forum_threads_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
            URLQueryItem(name: "order", value: "is_pinned.desc"),
            URLQueryItem(name: "order", value: sort == "popular" ? "like_count.desc" : "created_at.desc"),
            URLQueryItem(name: "limit", value: "30")
        ]
        if let board {
            items.append(URLQueryItem(name: "category_slug", value: "eq.\(board)"))
        }
        return try await client.fetchArray(table: "forum_threads", queryItems: items)
    }

    func fetchThread(id: String) async throws -> Thread? {
        let rows: [Thread] = try await client.fetchArray(
            table: "forum_threads",
            queryItems: [
                URLQueryItem(name: "select", value: "*,author:profiles!forum_threads_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return rows.first
    }

    func fetchComments(threadId: String) async throws -> [Comment] {
        try await client.fetchArray(
            table: "forum_comments",
            queryItems: [
                URLQueryItem(name: "select", value: "*,author:profiles!forum_comments_author_id_fkey(id,username,avatar_url,ideology,is_certified)"),
                URLQueryItem(name: "thread_id", value: "eq.\(threadId)"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ]
        )
    }

    func fetchProfile(id: String) async throws -> Profile? {
        let rows: [Profile] = try await client.fetchArray(
            table: "profiles",
            queryItems: [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "limit", value: "1")]
        )
        return rows.first
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
final class NotificationClient {
    private let client: SupabaseRESTClient

    init(client: SupabaseRESTClient = .init()) {
        self.client = client
    }

    func fetchNotifications(userId: String, accessToken: String?) async throws -> [NotificationItem] {
        try await client.fetchArray(
            table: "forum_notifications",
            queryItems: [
                URLQueryItem(name: "select", value: "id,type,content_preview,is_read,created_at,thread_id,comment_id,source_user:profiles!forum_notifications_source_user_id_fkey(id,username,avatar_url)"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")
            ],
            accessToken: accessToken
        )
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
