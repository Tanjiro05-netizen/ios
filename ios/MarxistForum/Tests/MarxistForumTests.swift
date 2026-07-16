import MediaPlayer
import XCTest
@testable import MarxistForum

final class MarxistForumTests: XCTestCase {
    func testBookDecodingUsesSnakeCase() throws {
        let json = """
        {
          "id": "1",
          "title": "Capital",
          "author": "Karl Marx",
          "cover_image_url": "https://example.com/cover.jpg",
          "epub_filename": "capital.epub",
          "is_official": true
        }
        """.data(using: .utf8)!

        let book = try JSONDecoder.supabase.decode(Book.self, from: json)
        XCTAssertEqual(book.coverImageUrl, "https://example.com/cover.jpg")
        XCTAssertEqual(book.epubFilename, "capital.epub")
        XCTAssertEqual(book.isOfficial, true)
    }

    func testAudioChapterMath() {
        let chapters = [
            AudiobookChapter(title: "A", startSeconds: 0),
            AudiobookChapter(title: "B", startSeconds: 120),
            AudiobookChapter(title: "C", startSeconds: 400)
        ]
        XCTAssertEqual(AudioChapterMath.currentIndex(time: 0, chapters: chapters), 0)
        XCTAssertEqual(AudioChapterMath.currentIndex(time: 121, chapters: chapters), 1)
        XCTAssertEqual(AudioChapterMath.currentIndex(time: 900, chapters: chapters), 2)
        XCTAssertEqual(AudioChapterMath.currentIndex(time: 0, chapters: []), -1)
    }

    func testSubstackPayloadDecodingAndNormalization() throws {
        let json = """
        {
          "source": {
            "title": "Archive",
            "url": "https://acc2049.substack.com",
            "feedUrl": "https://acc2049.substack.com/feed",
            "authorName": "☭/Acc"
          },
          "posts": [
            {
              "id": "https://acc2049.substack.com/p/the-realm-of-freedom",
              "title": "The Realm of Freedom",
              "slug": "the-realm-of-freedom",
              "url": "https://acc2049.substack.com/p/the-realm-of-freedom",
              "publishedAt": "Wed, 29 Apr 2026 18:15:52 GMT",
              "excerpt": "What do we do when the struggle for survival ends?",
              "contentHtml": "<p>Body</p>",
              "categories": []
            }
          ]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder.supabase.decode(SubstackPayload.self, from: json)
        let post = try XCTUnwrap(payload.posts.first?.normalized())
        XCTAssertEqual(post.slug, "the-realm-of-freedom")
        XCTAssertEqual(post.primaryCategory, "Personal")
        XCTAssertNotNil(post.publishedDate)
    }

    func testSubstackCleanupRemovesSubscribeWidgets() {
        let dirty = """
        <p>Article body.</p>
        <div class="subscription-widget-wrap"><input type="email" placeholder="Type your email"><button>Subscribe</button></div>
        <script>alert("x")</script>
        """

        let cleaned = SubstackArticle.cleanContentHTML(dirty)
        XCTAssertTrue(cleaned.contains("Article body."))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("subscription-widget"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<script"))
    }

    func testSubstackMergePrefersLiveAndPreservesArchiveContent() {
        let archive = SubstackArticle(
            id: "archive",
            title: "Archive Title",
            slug: "shared",
            url: "https://acc2049.substack.com/p/shared",
            publishedAt: "Mon, 01 Jan 2024 10:00:00 GMT",
            excerpt: "Archive excerpt",
            contentHtml: "<p>Archive body</p>",
            imageUrl: "https://example.com/archive.jpg"
        )
        let live = SubstackArticle(
            id: "live",
            title: "Live Title",
            slug: "shared",
            url: "https://acc2049.substack.com/p/shared",
            publishedAt: "Tue, 02 Jan 2024 10:00:00 GMT",
            excerpt: "Live excerpt"
        )

        let merged = SubstackClient.merge(livePosts: [live], archivePosts: [archive])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "Live Title")
        XCTAssertEqual(merged[0].contentHtml, "<p>Archive body</p>")
        XCTAssertEqual(merged[0].imageUrl, "https://example.com/archive.jpg")
    }

    func testGlobalSearchMatcherIsCaseInsensitiveAcrossFields() {
        XCTAssertTrue(GlobalSearchMatcher.matches(["Capital", "Karl Marx", nil], query: "marx"))
        XCTAssertTrue(GlobalSearchMatcher.matches(["Prolegomena", "Jinbu/Leninistwarrior"], query: "LENINIST"))
        XCTAssertFalse(GlobalSearchMatcher.matches(["Dialectics", "Philosophy"], query: "audiobook"))
    }

    func testDailyQuoteSelectionIsStableForADay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 7, day: 6).date)

        XCTAssertEqual(DailyQuote.quote(for: date, calendar: calendar), DailyQuote.quote(for: date, calendar: calendar))
        XCTAssertFalse(DailyQuote.all.isEmpty)
    }

    func testAppAppearanceMapsToPreferredColorScheme() {
        XCTAssertNil(AppAppearance.system.preferredColorScheme)
        XCTAssertEqual(AppAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppSettings().appearance, .system)
    }

    func testLegacyAppSettingsMigrateToSystemAppearanceWithoutDataLoss() throws {
        let legacyJSON = """
        {
          "push_notifications": false,
          "email_notifications": true,
          "dark_mode": true,
          "data_saver": true,
          "show_ideology_badges": false,
          "email_marketing_enabled": true,
          "email_comment_replies": false,
          "email_thread_activity": false,
          "email_weekly_digest": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder.supabase.decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(settings.appearance, .system)
        XCTAssertFalse(settings.pushNotifications)
        XCTAssertTrue(settings.emailNotifications)
        XCTAssertTrue(settings.dataSaver)
        XCTAssertFalse(settings.showIdeologyBadges)
        XCTAssertTrue(settings.emailMarketingEnabled)
        XCTAssertFalse(settings.emailCommentReplies)
        XCTAssertFalse(settings.emailThreadActivity)
        XCTAssertTrue(settings.emailWeeklyDigest)
    }

    @MainActor
    func testSettingsStoreRestoresAppearanceBeforeFirstUse() throws {
        let suiteName = "MarxistForumTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings.appearance, .system)

        store.settings.appearance = .light
        store.settings.dataSaver = true
        store.save()

        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.settings.appearance, .light)
        XCTAssertTrue(restored.settings.dataSaver)

        let roundTripData = try XCTUnwrap(defaults.data(forKey: "ios.settings"))
        let roundTrip = try JSONDecoder.supabase.decode(AppSettings.self, from: roundTripData)
        XCTAssertEqual(roundTrip, restored.settings)
    }

    func testReadingActivityModelsRoundTrip() throws {
        let progress = ContinueReadingItem(
            bookId: "capital",
            title: "Capital",
            author: "Karl Marx",
            chapterTitle: "Commodities",
            chapterIndex: 0,
            chapterCount: 3,
            progress: 1.0 / 3.0,
            updatedAt: "2026-07-06T12:00:00Z"
        )
        let quote = QuoteNotebookItem(
            id: "quote-1",
            text: "Ruthless criticism of all that exists.",
            sourceTitle: "Letter to Ruge",
            sourceDetail: "Daily Card",
            routeBookId: nil,
            createdAt: "2026-07-06T12:00:00Z"
        )

        let encodedProgress = try JSONEncoder.supabase.encode(progress)
        let encodedQuote = try JSONEncoder.supabase.encode(quote)

        XCTAssertEqual(try JSONDecoder.supabase.decode(ContinueReadingItem.self, from: encodedProgress), progress)
        XCTAssertEqual(try JSONDecoder.supabase.decode(QuoteNotebookItem.self, from: encodedQuote), quote)
    }

    func testReadingSyncPayloadUsesOwnershipAndSnakeCaseKeys() throws {
        let payload = ReadingProgressRemote(
            userId: "user-1",
            bookId: "capital",
            title: "Capital",
            author: "Karl Marx",
            chapterTitle: "Commodities",
            chapterIndex: 2,
            chapterCount: 8,
            progress: 0.375,
            updatedAt: "2026-07-06T12:00:00Z"
        )

        let data = try JSONEncoder.supabase.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["user_id"] as? String, "user-1")
        XCTAssertEqual(object["book_id"] as? String, "capital")
        XCTAssertEqual(object["chapter_index"] as? Int, 2)
        XCTAssertEqual(object["updated_at"] as? String, "2026-07-06T12:00:00Z")
    }

    func testAppDeepLinksRoundTrip() throws {
        let links: [AppDeepLink] = [
            .library,
            .audiobooks,
            .substack,
            .forum,
            .notifications,
            .profile,
            .book(id: "capital"),
            .audiobook(id: "audio-1"),
            .substackArticle(slug: "the-realm-of-freedom"),
            .thread(id: "thread-1"),
            .userProfile(id: "user-1"),
            .dailyQuote,
            .continueReading,
            .quoteNotebook,
            .support,
            .search(query: "Marx Lenin")
        ]

        for link in links {
            XCTAssertEqual(AppDeepLink(url: link.url), link)
        }
    }

    func testSearchableIdentifierDeepLinks() {
        XCTAssertEqual(AppDeepLink(searchableItemIdentifier: "book:capital"), .book(id: "capital"))
        XCTAssertEqual(AppDeepLink(searchableItemIdentifier: "audiobook:audio-1"), .audiobook(id: "audio-1"))
        XCTAssertEqual(AppDeepLink(searchableItemIdentifier: "substack:article-slug"), .substackArticle(slug: "article-slug"))
        XCTAssertEqual(AppDeepLink(searchableItemIdentifier: "thread:thread-1"), .thread(id: "thread-1"))
        XCTAssertNil(AppDeepLink(searchableItemIdentifier: "unknown:item"))
    }

    func testSystemIntegrationSnapshotRoundTrip() throws {
        let snapshot = SystemIntegrationSnapshot(
            dailyQuote: DailyQuoteSnapshot(
                text: "Workers of the world, unite!",
                source: "The Communist Manifesto",
                detail: "Daily Card",
                dateKey: "2026-07-06"
            ),
            continueReading: ContinueReadingSnapshot(
                bookId: "capital",
                title: "Capital",
                author: "Karl Marx",
                chapterTitle: "Commodities",
                progress: 0.4,
                updatedAt: "2026-07-06T12:00:00Z"
            ),
            currentAudiobook: CurrentAudiobookSnapshot(
                id: "audio-1",
                title: "Prolegomena",
                author: "Jinbu/Leninistwarrior",
                narrator: nil,
                coverUrl: nil,
                currentTime: 42,
                duration: 900,
                speed: 1.25,
                chapterTitle: "Opening",
                isPlaying: false,
                updatedAt: "2026-07-06T12:00:00Z"
            ),
            latestUpdates: [
                LatestUpdateSnapshot(
                    id: "substack-test",
                    kind: .substack,
                    title: "Article",
                    subtitle: "Author",
                    detail: "Today",
                    deepLinkURL: AppDeepLink.substackArticle(slug: "article").url,
                    updatedAt: "2026-07-06T12:00:00Z"
                )
            ]
        )

        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(SystemIntegrationSnapshot.self, from: encoded), snapshot)
    }

    @MainActor
    func testNowPlayingMetadataContainsAudiobookState() {
        let audiobook = Audiobook(
            id: "audio-1",
            title: "Prolegomena: Communism (Basics)",
            author: "Jinbu/Leninistwarrior",
            narrator: nil,
            description: nil,
            coverUrl: nil,
            audioUrl: "https://example.com/audio.mp3",
            durationSeconds: 2300,
            category: "Theory",
            isFeatured: true,
            sortOrder: 1,
            chapters: nil,
            createdAt: nil
        )
        let chapters = [
            AudiobookChapter(title: "Opening", startSeconds: 0),
            AudiobookChapter(title: "Basics", startSeconds: 120)
        ]

        let metadata = NowPlayingController.makeMetadata(
            audiobook: audiobook,
            chapters: chapters,
            artwork: nil,
            currentTime: 125,
            duration: 2300,
            isPlaying: true,
            speed: 1.25,
            currentChapterIndex: 1
        )

        XCTAssertEqual(metadata[MPMediaItemPropertyTitle] as? String, audiobook.title)
        XCTAssertEqual(metadata[MPMediaItemPropertyArtist] as? String, audiobook.author)
        XCTAssertEqual(metadata[MPMediaItemPropertyAlbumTitle] as? String, "Basics")
        XCTAssertEqual(metadata[MPMediaItemPropertyGenre] as? String, "Theory")
        XCTAssertEqual(metadata[MPMediaItemPropertyPlaybackDuration] as? Double, 2300)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 125)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.25)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyChapterNumber] as? Int, 2)
        XCTAssertEqual(metadata[MPNowPlayingInfoPropertyChapterCount] as? Int, 2)
    }

    @MainActor
    func testNowPlayingCommandHandlersInvokeClosures() {
        var events: [String] = []
        let handlers = NowPlayingCommandHandlers(
            play: { events.append("play") },
            pause: { events.append("pause") },
            toggle: { events.append("toggle") },
            seek: { events.append("seek:\(Int($0))") },
            skip: { events.append("skip:\(Int($0))") },
            nextChapter: { events.append("next") },
            previousChapter: { events.append("previous") },
            setSpeed: { events.append("speed:\($0)") }
        )

        handlers.play()
        handlers.pause()
        handlers.toggle()
        handlers.seek(42)
        handlers.skip(-30)
        handlers.nextChapter()
        handlers.previousChapter()
        handlers.setSpeed(1.5)

        XCTAssertEqual(events, ["play", "pause", "toggle", "seek:42", "skip:-30", "next", "previous", "speed:1.5"])
    }

    func testEpubContainerParserFindsPackageDocument() throws {
        let xml = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.data(using: .utf8)!

        let opfPath = try EpubArchiveParser.parseContainerXML(xml)
        XCTAssertEqual(opfPath, "OEBPS/content.opf")
    }

    func testEpubPackageParserPreservesSpineOrder() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Capital Volume One</dc:title>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="chapter-1" href="Text/chapter-1.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter-2" href="Text/chapter-2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chapter-1"/>
            <itemref idref="chapter-2"/>
          </spine>
        </package>
        """.data(using: .utf8)!

        let package = try EpubArchiveParser.parsePackageDocument(xml)
        XCTAssertEqual(package.title, "Capital Volume One")
        XCTAssertEqual(package.spine, ["chapter-1", "chapter-2"])
        XCTAssertEqual(package.manifest["chapter-1"]?.href, "Text/chapter-1.xhtml")
        XCTAssertEqual(package.manifest["chapter-2"]?.isReadableDocument, true)
    }
}
