import Foundation
import SwiftUI
import UIKit

enum AppFeatureFlags {
    static let forumEnabled = false
    static let sciencePilotEnabled = true
    static let writtenCourseSubmissionsEnabled = false
    static let examinerGradingEnabled = false
    static let supportTipsEnabled = false
    static let educationalVideosEnabled = false
    static let unreviewedAssessmentContentEnabled = false
}

enum AppConstants {
    static let supabaseURL = URL(string: "https://yghsprwrzgfegvfbjmkq.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlnaHNwcndyemdmZWd2ZmJqbWtxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEyNzc0MTMsImV4cCI6MjA2Njg1MzQxM30.a_jILFYVfP-Z7DVkskrOM9O4Z44qJ20d5tYXwQH09jc"
    static let substackPublicationURL = URL(string: "https://acc2049.substack.com")!
    static let substackFeedURL = URL(string: "https://acc2049.substack.com/feed")!
    static let substackAuthorName = "☭/Acc"
    static let substackAuthorProfileURL = URL(string: "https://substack.com/@leninistwarrior")!
    static let publicSiteURL = URL(string: "https://tanjiro05-netizen.github.io/ios/")!
    static let privacyPolicyURL = publicSiteURL.appending(path: "privacy.html")
    static let supportURL = publicSiteURL.appending(path: "support.html")
    static let accountAndDataURL = publicSiteURL.appending(path: "account-and-data.html")
    static let termsURL = publicSiteURL.appending(path: "terms.html")
}

enum Brand {
    static let red = Color("AccentFill")
    static let redSoft = Color("AccentLabel")
    static let canvas = Color("AppCanvas")
    static let surface = Color("AppSurface")
    static let ink = Color(uiColor: .label)
    static let paper = canvas
    static let muted = Color(uiColor: .secondaryLabel)
    static let panel = surface
    static let separator = Color(uiColor: .separator)
    static let subtleFill = Color(uiColor: .tertiarySystemFill)
    static let controlFill = Color(uiColor: .secondarySystemFill)
    static let onAccent = Color.white
}

struct Profile: Identifiable, Codable, Hashable {
    let id: String
    var username: String?
    var avatarUrl: String?
    var website: String?
    var updatedAt: String?
    var bio: String?
    var ideology: String?
    var bannerUrl: String?
    var role: String?
    var isCertified: Bool?
    var isAdmin: Bool?
    var hasInviteAccess: Bool?
    var inviteCodeUsed: String?
}

struct Thread: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var content: String
    var categorySlug: String
    var authorId: String?
    var createdAt: String
    var updatedAt: String?
    var commentCount: Int?
    var likeCount: Int?
    var viewCount: Int?
    var repostCount: Int?
    var isPinned: Bool?
    var isLocked: Bool?
    var anonymousName: String?
    var quotedThreadId: String?
    var author: Profile?
}

struct Comment: Identifiable, Codable, Hashable {
    let id: String
    var threadId: String
    var content: String
    var authorId: String?
    var parentId: String?
    var createdAt: String
    var updatedAt: String?
    var likeCount: Int?
    var isDeleted: Bool?
    var anonymousName: String?
    var author: Profile?
}

struct NotificationItem: Identifiable, Codable, Hashable {
    let id: String
    var userId: String?
    var type: String?
    var sourceUserId: String?
    var threadId: String?
    var commentId: String?
    var contentPreview: String?
    var isRead: Bool?
    var createdAt: String?
    var sourceUser: Profile?
}

struct TextEditionSection: Identifiable, Codable, Hashable {
    var id: String
    var title: String?
    var level: Int?
    var md: String

    init(id: String, title: String? = nil, level: Int? = nil, md: String = "") {
        self.id = id
        self.title = title
        self.level = level
        self.md = md
    }
}

/// digital_library_books.text_edition — the reflowable reading edition
/// (markdown sections produced from txt/PDF sources) that powers the
/// fullscreen text reader, mirroring the website's text-edition reader.
struct TextEdition: Codable, Hashable {
    var sections: [TextEditionSection]
    var readingMinutes: Int?
    var source: String?
    var generatedAt: String?

    init(
        sections: [TextEditionSection] = [],
        readingMinutes: Int? = nil,
        source: String? = nil,
        generatedAt: String? = nil
    ) {
        self.sections = sections
        self.readingMinutes = readingMinutes
        self.source = source
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        struct RawSection: Codable {
            var id: String?
            var title: String?
            var level: Int?
            var md: String?
        }
        let rawSections = try container.decodeIfPresent([RawSection].self, forKey: .sections) ?? []
        // Hand-built editions can omit section ids; fall back to the website's
        // index-based scheme so anchors stay stable within an edition.
        sections = rawSections.enumerated().map { index, raw in
            TextEditionSection(id: raw.id ?? "s\(index)", title: raw.title, level: raw.level, md: raw.md ?? "")
        }
        readingMinutes = try container.decodeIfPresent(Int.self, forKey: .readingMinutes)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
    }
}

struct Book: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var author: String?
    var year: Int?
    var description: String?
    var coverImageUrl: String?
    var pdfFilename: String?
    var epubFilename: String?
    var pages: Int?
    var downloads: Int?
    var createdAt: String?
    var category: String?
    var era: String?
    var language: String?
    var isOfficial: Bool?
    var uploadedBy: String?
    var uploader: Profile?
    var textEdition: TextEdition? = nil
}

struct AudiobookChapter: Codable, Hashable {
    var title: String
    var startSeconds: Double
}

struct Audiobook: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var author: String?
    var narrator: String?
    var description: String?
    var coverUrl: String?
    var audioUrl: String
    var durationSeconds: Double?
    var category: String?
    var isFeatured: Bool?
    var sortOrder: Int?
    var chapters: [AudiobookChapter]?
    var createdAt: String?
}

struct SubstackSource: Codable, Hashable {
    var title: String
    var url: String
    var feedUrl: String?
    var authorName: String?
    var authorProfileUrl: String?

    static let fallback = SubstackSource(
        title: "☭/Acc's Substack",
        url: AppConstants.substackPublicationURL.absoluteString,
        feedUrl: AppConstants.substackFeedURL.absoluteString,
        authorName: AppConstants.substackAuthorName,
        authorProfileUrl: AppConstants.substackAuthorProfileURL.absoluteString
    )
}

struct SubstackArticle: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var slug: String
    var url: String
    var publishedAt: String
    var author: String?
    var excerpt: String?
    var contentHtml: String?
    var imageUrl: String?
    var categories: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case slug
        case url
        case publishedAt
        case author
        case excerpt
        case contentHtml
        case imageUrl
        case categories
    }

    var publishedDate: Date? {
        Self.parseDate(publishedAt)
    }

    var displayDate: String {
        guard let publishedDate else { return "Undated" }
        return publishedDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var primaryCategory: String {
        categories.first ?? "Substack"
    }

    init(
        id: String,
        title: String,
        slug: String,
        url: String,
        publishedAt: String,
        author: String? = nil,
        excerpt: String? = nil,
        contentHtml: String? = nil,
        imageUrl: String? = nil,
        categories: [String] = []
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.url = url
        self.publishedAt = publishedAt
        self.author = author
        self.excerpt = excerpt
        self.contentHtml = contentHtml
        self.imageUrl = imageUrl
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Substack post"
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        contentHtml = try container.decodeIfPresent(String.self, forKey: .contentHtml)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
    }

    func normalized() -> SubstackArticle {
        var copy = self
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.title.isEmpty {
            copy.title = "Untitled Substack post"
        }
        copy.slug = copy.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.slug.isEmpty {
            copy.slug = Self.slug(from: copy.url, fallbackTitle: copy.title)
        }
        if copy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.id = copy.url.isEmpty ? copy.slug : copy.url
        }
        copy.author = (copy.author?.isEmpty == false) ? copy.author : AppConstants.substackAuthorName
        copy.contentHtml = Self.cleanContentHTML(copy.contentHtml ?? "")
        if copy.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            copy.excerpt = Self.excerpt(from: copy.contentHtml ?? "")
        }
        copy.excerpt = copy.excerpt?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.imageUrl = Self.sanitizedImageURL(copy.imageUrl)
        let cleanCategories = copy.categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.categories = cleanCategories.isEmpty
            ? Self.inferredCategories(title: copy.title, excerpt: copy.excerpt ?? "")
            : cleanCategories
        return copy
    }

    static func cleanContentHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(div|section|aside|form)[^>]*(subscribe|subscription|signup|email)[^>]*>[\s\S]*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<input[^>]*(email|Type your email)[^>]*\/?>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<button[^>]*>\s*Subscribe\s*</button>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\son\w+=(["']).*?\1"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\son\w+=\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s(href|src)=(["'])javascript:[\s\S]*?\2"#, with: " $1=\"#\"", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func excerpt(from html: String) -> String {
        let stripped = html.strippedHTML.decodedHTMLEntities
        guard stripped.count > 280 else { return stripped }
        return String(stripped.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func inferredCategories(title: String, excerpt: String) -> [String] {
        let haystack = "\(title) \(excerpt)".lowercased()
        if haystack.range(of: #"\bshort note\b"#, options: .regularExpression) != nil {
            return ["Short Notes"]
        }
        if haystack.range(of: #"science|dialectic|invariance|technical|prolegomena|mathematics|physics|stem"#, options: .regularExpression) != nil {
            return ["Foundations of Science"]
        }
        return ["Personal"]
    }

    private static func sanitizedImageURL(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard value.contains("substackcdn.com/image/fetch/"), let markerRange = value.range(of: "/https") else {
            return value
        }
        let encoded = String(value[markerRange.upperBound...])
        let decoded = "https" + (encoded.removingPercentEncoding ?? encoded)
        return decoded.hasPrefix("https://") ? decoded : value
    }

    private static func slug(from url: String, fallbackTitle: String) -> String {
        if let parsedURL = URL(string: url) {
            let parts = parsedURL.path.split(separator: "/").map(String.init)
            if let postIndex = parts.firstIndex(of: "p"), parts.indices.contains(postIndex + 1) {
                return parts[postIndex + 1]
            }
        }
        return fallbackTitle.slugified
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return dateParsers.parse(value)
    }

    private static let dateParsers = SubstackDateParsers()
}

private final class SubstackDateParsers: @unchecked Sendable {
    private let lock = NSLock()
    private let rfc1123DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
    private let isoDateFormatter = ISO8601DateFormatter()

    func parse(_ value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return rfc1123DateFormatter.date(from: value) ?? isoDateFormatter.date(from: value)
    }
}

struct SubstackPayload: Codable, Hashable {
    var source: SubstackSource?
    var posts: [SubstackArticle]
    var error: String?

    enum CodingKeys: String, CodingKey {
        case source
        case posts
        case error
    }

    init(source: SubstackSource? = nil, posts: [SubstackArticle], error: String? = nil) {
        self.source = source
        self.posts = posts
        self.error = error
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var decodedPosts: [SubstackArticle] = []
            while !unkeyed.isAtEnd {
                decodedPosts.append(try unkeyed.decode(SubstackArticle.self))
            }
            source = nil
            posts = decodedPosts
            error = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(SubstackSource.self, forKey: .source)
        posts = try container.decodeIfPresent([SubstackArticle].self, forKey: .posts) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct Board: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let fullName: String
    let description: String
    let systemImage: String

    static let all: [Board] = [
        .init(slug: "t", name: "theory", fullName: "Theory", description: "Marxist theory and philosophy", systemImage: "books.vertical"),
        .init(slug: "r", name: "reading", fullName: "Reading", description: "Study groups and discussions", systemImage: "book.pages"),
        .init(slug: "o", name: "organizing", fullName: "Organizing", description: "Praxis and action", systemImage: "person.3"),
        .init(slug: "h", name: "history", fullName: "History", description: "Historical analysis", systemImage: "building.columns"),
        .init(slug: "c", name: "current", fullName: "Current Events", description: "News and analysis", systemImage: "globe.europe.africa"),
        .init(slug: "m", name: "meta", fullName: "Meta", description: "Site feedback", systemImage: "bubble.left.and.bubble.right"),
        .init(slug: "x", name: "random", fullName: "Random", description: "Off-topic", systemImage: "shuffle")
    ]
}

struct UserStats: Codable, Hashable {
    var threadCount: Int
    var commentCount: Int
    var likesReceived: Int
    var repostCount: Int

    static let empty = UserStats(threadCount: 0, commentCount: 0, likesReceived: 0, repostCount: 0)
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSettings: Codable, Hashable {
    var pushNotifications = true
    var emailNotifications = true
    var appearance = AppAppearance.system
    var dataSaver = false
    var showIdeologyBadges = true
    var emailMarketingEnabled = false
    var emailCommentReplies = true
    var emailThreadActivity = true
    var emailWeeklyDigest = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case pushNotifications
        case emailNotifications
        case appearance
        case dataSaver
        case showIdeologyBadges
        case emailMarketingEnabled
        case emailCommentReplies
        case emailThreadActivity
        case emailWeeklyDigest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pushNotifications = try container.decodeIfPresent(Bool.self, forKey: .pushNotifications) ?? true
        emailNotifications = try container.decodeIfPresent(Bool.self, forKey: .emailNotifications) ?? true
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        dataSaver = try container.decodeIfPresent(Bool.self, forKey: .dataSaver) ?? false
        showIdeologyBadges = try container.decodeIfPresent(Bool.self, forKey: .showIdeologyBadges) ?? true
        emailMarketingEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailMarketingEnabled) ?? false
        emailCommentReplies = try container.decodeIfPresent(Bool.self, forKey: .emailCommentReplies) ?? true
        emailThreadActivity = try container.decodeIfPresent(Bool.self, forKey: .emailThreadActivity) ?? true
        emailWeeklyDigest = try container.decodeIfPresent(Bool.self, forKey: .emailWeeklyDigest) ?? false
    }
}

struct DailyQuote: Identifiable, Hashable {
    let id: String
    let text: String
    let source: String
    let detail: String

    static let all: [DailyQuote] = [
        .init(
            id: "marx-feuerbach-11",
            text: "The philosophers have only interpreted the world, in various ways; the point is to change it.",
            source: "Karl Marx",
            detail: "Theses on Feuerbach"
        ),
        .init(
            id: "lenin-theory",
            text: "Without revolutionary theory there can be no revolutionary movement.",
            source: "V. I. Lenin",
            detail: "What Is To Be Done?"
        ),
        .init(
            id: "manifesto-history",
            text: "The history of all hitherto existing society is the history of class struggles.",
            source: "Karl Marx and Friedrich Engels",
            detail: "The Communist Manifesto"
        ),
        .init(
            id: "engels-necessity",
            text: "Freedom is the recognition of necessity.",
            source: "Friedrich Engels",
            detail: "Anti-Duhring"
        ),
        .init(
            id: "marx-ruthless",
            text: "Ruthless criticism of all that exists.",
            source: "Karl Marx",
            detail: "Letter to Ruge"
        )
    ]

    static var today: DailyQuote {
        quote(for: Date())
    }

    static func quote(for date: Date, calendar: Calendar = .current) -> DailyQuote {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[abs(day) % all.count]
    }
}

struct GuestSession: Codable, Hashable {
    var id: String
    var username: String
    var createdAt: String
}

struct AuthSession: Codable, Hashable {
    var accessToken: String
    var refreshToken: String?
    var user: SupabaseUser
}

struct SupabaseUser: Codable, Hashable {
    var id: String
    var email: String?
}

struct DownloadedEpub: Codable, Identifiable, Hashable {
    var id: String { bookId }
    var bookId: String
    var title: String
    var author: String?
    var epubFilename: String
    var localPath: String
    var cachedAt: String
    var fileSize: Int?
}

struct DownloadedAudiobook: Codable, Identifiable, Hashable {
    var id: String { audiobookId }
    var audiobookId: String
    var title: String
    var author: String?
    var filename: String
    var cachedAt: String
    var fileSize: Int?
    var audiobook: Audiobook?
}

struct ContinueReadingItem: Codable, Identifiable, Hashable {
    var id: String { bookId }
    var bookId: String
    var title: String
    var author: String?
    var chapterTitle: String?
    var chapterIndex: Int
    var chapterCount: Int
    var progress: Double
    var updatedAt: String
}

struct QuoteNotebookItem: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var sourceTitle: String
    var sourceDetail: String?
    var routeBookId: String?
    var createdAt: String
}

enum LibraryScope: String, CaseIterable, Identifiable {
    case official
    case community

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum LegalKind: String, Codable, Hashable, Identifiable {
    case terms
    case privacy
    case guidelines

    var id: String { rawValue }
    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Privacy Policy"
        case .guidelines: "Community Guidelines"
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case library
    case audiobooks
    case study
    case substack
    case forum
    case notifications
    case profile

    var id: String { rawValue }

    static let bottomBarTabs: [AppTab] = [
        .library,
        .audiobooks,
        .study,
        .substack,
        .forum,
        .profile
    ]

    var title: String {
        switch self {
        case .library: "Library"
        case .audiobooks: "Audio"
        case .study: "Study"
        case .substack: "Substack"
        case .forum: "Forum"
        case .notifications: "Alerts"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .audiobooks: "headphones"
        case .study: "graduationcap"
        case .substack: "newspaper"
        case .forum: "bubble.left.and.bubble.right"
        case .notifications: "bell"
        case .profile: "person.crop.circle"
        }
    }
}

enum Route: Hashable {
    case notifications
    case settings
    case studyCollection(kind: StudyContentKind)
    case studyCourse(id: String)
    case studyCourseDocument(courseID: String, kind: StudyCourseDocumentKind)
    case studyLesson(courseID: String, moduleID: String, lessonID: String)
    case studyCourseOrientation(courseID: String)
    case studyCourseSection(courseID: String, moduleID: String, lessonID: String, blockID: String)
    case studyCourseSource(courseID: String, resourceName: String, resourceFirstSourcePage: Int, firstPage: Int, lastPage: Int)
    case studyScienceActivity(courseID: String, activityID: String)
    case studyScienceAssessment(courseID: String, assessmentID: String)
    case studyScienceVideo(courseID: String, videoID: String)
    case studyAssignment(id: String)
    case studyCourseMarking(courseID: String)
    case studyAssignmentMarking(submissionID: String)
    case studyExamMarking(submissionID: String)
    case studyCourseExam(id: String)
    case studyGuide(id: String)
    case studyReadingGuide(id: String)
    case studyReadingGuideChunk(guideID: String, chunkID: String)
    case studyDaily
    case studyExercises
    case studyPractice
    case studyQuestionCatalogue
    case studyQuiz(attemptID: UUID)
    case studyResults(attemptID: UUID)
    case studyReview
    case studyDiagnostic
    case studyProgress
    case studyExams
    case studyExamInstructions(examID: String)
    case studyGlossary
    case bookReader(id: String)
    case substackArticle(slug: String)
    case threadDetail(id: String)
    case userProfile(id: String)
    case quoteNotebook
    case support
    case changePassword
    case emailPreferences
    case legal(LegalKind)
}

enum SheetDestination: Identifiable, Hashable {
    case createThread(boardSlug: String?)
    case audioPlayer
    case editProfile

    var id: String {
        switch self {
        case .createThread: "createThread"
        case .audioPlayer: "audioPlayer"
        case .editProfile: "editProfile"
        }
    }
}

enum AudioChapterMath {
    static func currentIndex(time: Double, chapters: [AudiobookChapter]) -> Int {
        guard !chapters.isEmpty else { return -1 }
        for index in stride(from: chapters.count - 1, through: 0, by: -1) {
            if time >= chapters[index].startSeconds {
                return index
            }
        }
        return 0
    }
}

extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension String {
    var strippedMarkdown: String {
        replacingOccurrences(of: #"[*_`>#]"#, with: "", options: .regularExpression)
    }

    var strippedHTML: String {
        replacingOccurrences(of: #"(?is)<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodedHTMLEntities: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }
        return attributed.string
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    var slugified: String {
        let value = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(value.prefix(90))
    }

    func clipped(_ limit: Int) -> String {
        count > limit ? String(prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..." : self
    }
}
