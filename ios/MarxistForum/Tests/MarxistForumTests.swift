import AuthenticationServices
import MediaPlayer
import SwiftData
import XCTest
@testable import MarxistForum

final class MarxistForumTests: XCTestCase {
    @MainActor
    func testRouterIgnoresRepeatedDestinationTap() {
        let router = RouterPath()

        router.navigate(to: .quoteNotebook)
        router.navigate(to: .quoteNotebook)

        XCTAssertEqual(router.path, [.quoteNotebook])
    }

    func testCancelledAppleSignInDoesNotShowAnError() {
        let error = ASAuthorizationError(.canceled)
        XCTAssertNil(AppleSignInErrorPresentation.message(for: error))
    }

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

    func testAudiobookOfflineCacheFilename() {
        let withExtension = Audiobook(id: "ab1", title: "Capital", audioUrl: "https://cdn.example.com/audio/capital-vol1.m4a")
        XCTAssertEqual(AudiobookOfflineCache.filename(for: withExtension), "ab1-capital-vol1.m4a")

        let withoutExtension = Audiobook(id: "ab2", title: "Manifesto", audioUrl: "https://cdn.example.com/stream")
        XCTAssertEqual(AudiobookOfflineCache.filename(for: withoutExtension), "ab2.mp3")
    }

    func testDownloadedAudiobookRoundTripKeepsMetadata() throws {
        let audiobook = Audiobook(id: "ab1", title: "Capital", author: "Karl Marx", audioUrl: "https://cdn.example.com/a.m4a", durationSeconds: 120, chapters: [AudiobookChapter(title: "Intro", startSeconds: 0)])
        let entry = DownloadedAudiobook(
            audiobookId: audiobook.id,
            title: audiobook.title,
            author: audiobook.author,
            filename: "ab1-a.m4a",
            cachedAt: "2026-07-08T00:00:00Z",
            fileSize: 1024,
            audiobook: audiobook
        )
        let data = try JSONEncoder.supabase.encode([entry])
        let decoded = try JSONDecoder.supabase.decode([DownloadedAudiobook].self, from: data)
        XCTAssertEqual(decoded.first?.audiobook, audiobook)
        XCTAssertEqual(decoded.first?.filename, "ab1-a.m4a")
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
            .study,
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

    func testStudyStaysCentralAndForumStaysVisibleInBottomBar() {
        XCTAssertEqual(
            AppTab.bottomBarTabs,
            [.library, .audiobooks, .study, .substack, .forum, .profile]
        )
        XCTAssertEqual(AppTab.bottomBarTabs[2], .study)
        XCTAssertTrue(AppTab.bottomBarTabs.contains(.forum))
        XCTAssertFalse(AppTab.bottomBarTabs.contains(.notifications))
    }

    func testStudyLandingPageIncludesEveryPlannedFormat() {
        XCTAssertEqual(
            StudyContentKind.allCases,
            [.studyGuides, .readingGuides, .videos, .quizzes, .courses, .exams]
        )
    }

    func testBundledStudyCatalogueDecodesEveryQuestionAndPreservesAuditMetadata() async throws {
        let catalogue = try await Self.loadBundledStudyCatalogue()

        XCTAssertEqual(catalogue.items.count, 529)
        XCTAssertEqual(catalogue.counts.total, 529)
        XCTAssertEqual(catalogue.counts.singleChoice, 370)
        XCTAssertEqual(catalogue.counts.multipleChoice, 159)
        XCTAssertEqual(catalogue.counts.bank1, 158)
        XCTAssertEqual(catalogue.counts.bank2, 371)
        XCTAssertEqual(catalogue.items.filter { $0.type == .singleChoice }.count, 370)
        XCTAssertEqual(catalogue.items.filter { $0.type == .multipleChoice }.count, 159)
        XCTAssertEqual(catalogue.items.filter { $0.bank == .bank1 }.count, 158)
        XCTAssertEqual(catalogue.items.filter { $0.bank == .bank2 }.count, 371)
        XCTAssertEqual(Set(catalogue.items.map(\.id)).count, 529)
        XCTAssertEqual(catalogue.duplicateClusters.count, 12)
        XCTAssertEqual(catalogue.duplicateClusters.values.flatMap { $0 }.count, 27)

        let mixedNumberQuestion = try XCTUnwrap(catalogue.questionsByID["B1-C04-SC-U03"])
        XCTAssertEqual(
            mixedNumberQuestion.source.printedNumber,
            .note("unnumbered between 2 and 3")
        )
        XCTAssertEqual(
            catalogue.items.filter {
                if case .note = $0.source.printedNumber { return true }
                return false
            }.count,
            1
        )
    }

    func testUnreviewedQuestionCatalogueIsVisibleButExcludedFromScoredAttempts() async throws {
        let catalogue = try await Self.loadBundledStudyCatalogue()

        XCTAssertEqual(catalogue.items.count, 529)
        XCTAssertEqual(catalogue.items.filter(\.isApprovedForScoring).count, 0)
        XCTAssertFalse(AppFeatureFlags.unreviewedAssessmentContentEnabled)
        XCTAssertThrowsError(
            try StudyAssessmentEngine.makeAttempt(
                catalogue: catalogue,
                plan: .practiceExam(itemCount: 20),
                seed: 11
            )
        ) { error in
            XCTAssertEqual(error as? StudyAssessmentEngineError, .noEligibleQuestions)
        }
    }

    func testEveryStudyQuestionAnswerUsesItsOwnOptionSet() async throws {
        let catalogue = try await Self.loadBundledStudyCatalogue()

        for question in catalogue.items {
            let optionIDs = Set(question.options.keys)
            let printedAnswerIDs = Set(question.printedAnswer.map(String.init))

            XCTAssertFalse(question.correctOptionIDs.isEmpty, question.id)
            XCTAssertTrue(question.correctOptionIDs.isSubset(of: optionIDs), question.id)
            XCTAssertTrue(printedAnswerIDs.isSubset(of: optionIDs), question.id)
            switch question.type {
            case .singleChoice:
                XCTAssertEqual(question.correctOptionIDs.count, 1, question.id)
            case .multipleChoice:
                XCTAssertGreaterThan(question.correctOptionIDs.count, 1, question.id)
            case .matching, .shortResponse, .reconstruction:
                XCTFail("The canonical standalone catalogue unexpectedly contains a course-only question type: \(question.id)")
            }
        }
    }

    func testStudyScoringRequiresAnExactOptionSetForSingleAndMultipleChoice() async throws {
        let catalogue = try await Self.loadBundledStudyCatalogue()
        let single = try XCTUnwrap(catalogue.items.first { $0.type == .singleChoice })
        let singleCorrect = Array(single.correctOptionIDs)
        let singleWrong = try XCTUnwrap(single.options.keys.first { !single.correctOptionIDs.contains($0) })

        XCTAssertTrue(StudyAssessmentEngine.isCorrect(question: single, selectedOptionIDs: singleCorrect))
        XCTAssertFalse(StudyAssessmentEngine.isCorrect(question: single, selectedOptionIDs: [singleWrong]))
        XCTAssertFalse(
            StudyAssessmentEngine.isCorrect(
                question: single,
                selectedOptionIDs: singleCorrect + [singleWrong]
            )
        )

        let multiple = try XCTUnwrap(
            catalogue.items.first {
                $0.type == .multipleChoice && $0.correctOptionIDs.count < $0.options.count
            }
        )
        let multipleCorrect = multiple.correctOptionIDs.sorted()
        let omittedCorrectOption = Array(multipleCorrect.dropLast())
        let extraWrongOption = try XCTUnwrap(
            multiple.options.keys.first { !multiple.correctOptionIDs.contains($0) }
        )

        XCTAssertTrue(
            StudyAssessmentEngine.isCorrect(
                question: multiple,
                selectedOptionIDs: multipleCorrect.reversed()
            )
        )
        XCTAssertFalse(
            StudyAssessmentEngine.isCorrect(
                question: multiple,
                selectedOptionIDs: omittedCorrectOption
            )
        )
        XCTAssertFalse(
            StudyAssessmentEngine.isCorrect(
                question: multiple,
                selectedOptionIDs: multipleCorrect + [extraWrongOption]
            )
        )
    }

    func testFlaggedQuestionRemainsInCatalogueButNeverEntersGeneratedScoring() async throws {
        let catalogue = try Self.reviewedCatalogue(try await Self.loadBundledStudyCatalogue())
        let flagged = try XCTUnwrap(catalogue.items.first { $0.qaStatus == .flagged })
        XCTAssertEqual(flagged.id, "B1-C04-MC-013")

        let plans: [StudySessionPlan] = [
            .legacyDrill(itemCount: catalogue.items.count),
            .domain(.formationOfCapitalism, itemCount: catalogue.items.count),
            .interleaved(itemCount: catalogue.items.count),
            .diagnostic(itemCount: catalogue.items.count),
            .practiceExam(itemCount: catalogue.items.count)
        ]
        for (offset, plan) in plans.enumerated() {
            let attempt = try StudyAssessmentEngine.makeAttempt(
                catalogue: catalogue,
                plan: plan,
                seed: UInt64(offset + 1)
            )
            XCTAssertFalse(attempt.items.contains { $0.question.id == flagged.id }, plan.id)
            XCTAssertFalse(attempt.items.contains { $0.question.qaStatus == .flagged }, plan.id)
        }

        XCTAssertThrowsError(
            try StudyAssessmentEngine.makeAttempt(
                catalogue: catalogue,
                plan: .review(questionIDs: [flagged.id]),
                seed: 99
            )
        ) { error in
            XCTAssertEqual(error as? StudyAssessmentEngineError, .noEligibleQuestions)
        }
    }

    func testGeneratedStudySessionIsDeterministicAndDuplicateClusterFree() async throws {
        let catalogue = try Self.reviewedCatalogue(try await Self.loadBundledStudyCatalogue())
        let plan = StudySessionPlan.practiceExam(itemCount: catalogue.items.count)
        let attemptID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try StudyAssessmentEngine.makeAttempt(
            catalogue: catalogue,
            plan: plan,
            seed: 7,
            attemptID: attemptID,
            now: now
        )
        let second = try StudyAssessmentEngine.makeAttempt(
            catalogue: catalogue,
            plan: plan,
            seed: 7,
            attemptID: attemptID,
            now: now
        )

        XCTAssertEqual(first.items.map { $0.question.id }, second.items.map { $0.question.id })
        XCTAssertEqual(first.items.map(\.optionOrder), second.items.map(\.optionOrder))
        XCTAssertEqual(Set(first.items.map { $0.question.id }).count, first.items.count)

        let selectedClusterIDs = first.items.compactMap {
            catalogue.duplicateClusterByQuestionID[$0.question.id]
        }
        XCTAssertEqual(Set(selectedClusterIDs).count, selectedClusterIDs.count)
    }

    func testStudyResultThresholdsAreMasteredAt80AndHonorsAt85() async throws {
        let catalogue = try Self.reviewedCatalogue(try await Self.loadBundledStudyCatalogue())

        XCTAssertEqual(StudyAssessmentEngine.masteryThreshold, 0.80)
        XCTAssertEqual(StudyAssessmentEngine.honorsThreshold, 0.85)
        XCTAssertEqual(
            StudyAssessmentEngine.summary(
                for: try scoredAttempt(catalogue: catalogue, correctCount: 15, total: 20)
            ).achievement,
            .needsReview
        )
        XCTAssertEqual(
            StudyAssessmentEngine.summary(
                for: try scoredAttempt(catalogue: catalogue, correctCount: 16, total: 20)
            ).achievement,
            .mastered
        )
        XCTAssertEqual(
            StudyAssessmentEngine.summary(
                for: try scoredAttempt(catalogue: catalogue, correctCount: 17, total: 20)
            ).achievement,
            .honors
        )
    }

    func testItemMasteryRequiresThreeSeparateSuccessfulSessionsAndWrongReopensIt() throws {
        let questionID = "B1-C01-SC-001"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionIDs = try [
            XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201")),
            XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000202")),
            XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000203"))
        ]
        let correct = studyResponse(isCorrect: true)

        var mastery = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: correct,
            attemptID: sessionIDs[0],
            existing: nil,
            at: now
        )
        mastery = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: correct,
            attemptID: sessionIDs[0],
            existing: mastery,
            at: now
        )
        XCTAssertEqual(mastery.successfulSessionIDs.count, 1)
        XCTAssertEqual(mastery.state, .learning)

        mastery = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: correct,
            attemptID: sessionIDs[1],
            existing: mastery,
            at: now
        )
        XCTAssertEqual(mastery.state, .learning)
        mastery = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: correct,
            attemptID: sessionIDs[2],
            existing: mastery,
            at: now
        )
        XCTAssertEqual(mastery.successfulSessionIDs.count, 3)
        XCTAssertEqual(mastery.lifetimeCorrectSessions, 3)
        XCTAssertEqual(mastery.state, .mastered)

        let wrong = studyResponse(isCorrect: false, confidence: .certain)
        mastery = StudyAssessmentEngine.applyingMastery(
            questionID: questionID,
            response: wrong,
            attemptID: UUID(),
            existing: mastery,
            at: now.addingTimeInterval(60)
        )
        XCTAssertEqual(mastery.state, .reopened)
        XCTAssertEqual(mastery.successfulSessionIDs, [])
        XCTAssertEqual(mastery.consecutiveCorrectSessions, 0)
        XCTAssertEqual(mastery.lifetimeCorrectSessions, 3)
        XCTAssertEqual(mastery.confidentWrongCount, 1)
    }

    func testReviewRatingsDeterministicallyMapToOneThreeSevenAndTwentyOneDays() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cardID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let initial = StudyAssessmentEngine.reviewCard(
            for: "B1-C01-SC-001",
            existing: nil,
            at: now,
            cardID: cardID
        )
        XCTAssertEqual(initial.intervalIndex, 0)
        XCTAssertEqual(initial.dueAt.timeIntervalSince(now), 1 * 86_400)

        let baseline = StudyReviewCard(
            id: cardID,
            questionID: initial.questionID,
            createdAt: now,
            dueAt: now,
            intervalIndex: 1,
            state: .scheduled,
            lastRating: nil,
            updatedAt: now
        )
        let expectations: [(StudyReviewRating, Int, Int)] = [
            (.again, 0, 1),
            (.hard, 1, 3),
            (.good, 2, 7),
            (.easy, 3, 21)
        ]

        for (rating, expectedIndex, expectedDays) in expectations {
            let update = StudyAssessmentEngine.scheduleReview(
                card: baseline,
                rating: rating,
                at: now
            )
            XCTAssertEqual(update.card.intervalIndex, expectedIndex, rating.rawValue)
            XCTAssertEqual(
                update.card.dueAt.timeIntervalSince(now),
                TimeInterval(expectedDays * 86_400),
                rating.rawValue
            )
            XCTAssertEqual(update.log.newIntervalIndex, expectedIndex, rating.rawValue)
        }
    }

    func testCurrentLegacySessionPlansNeverAffectItemMastery() {
        let plans: [StudySessionPlan] = [
            .legacyDrill(),
            .domain(.epistemology),
            .interleaved(),
            .diagnostic(),
            .review(questionIDs: ["B1-C01-SC-001"]),
            .practiceExam()
        ]

        XCTAssertEqual(Set(plans.map(\.kind)), Set(StudySessionKind.allCases))
        XCTAssertTrue(plans.allSatisfy { !$0.affectsItemMastery })
    }

    @MainActor
    func testDelayedFeedbackResponseCanBeRevisedAndOnlyLatestSelectionScores() async throws {
        let persistence = InMemoryStudyAssessmentPersistence()
        let store = try await Self.activatedStudyStore(persistence: persistence)
        let attemptID = try await store.startAttempt(plan: .diagnostic(itemCount: 1))
        let question = try XCTUnwrap(store.currentItem(for: attemptID)?.question)
        let incorrectSelection = try incorrectSelection(for: question)

        let firstFeedback = try await store.submitResponse(
            attemptID: attemptID,
            selectedOptionIDs: incorrectSelection,
            confidence: .guess,
            responseDuration: 12
        )
        XCTAssertNil(firstFeedback)
        XCTAssertNil(store.attempt(id: attemptID)?.items.first?.response?.isCorrect)
        XCTAssertEqual(
            Set(store.attempt(id: attemptID)?.items.first?.response?.selectedOptionIDs ?? []),
            incorrectSelection
        )

        let latestFeedback = try await store.submitResponse(
            attemptID: attemptID,
            selectedOptionIDs: question.correctOptionIDs,
            confidence: .certain,
            responseDuration: 4
        )
        XCTAssertNil(latestFeedback)
        let revised = try XCTUnwrap(store.attempt(id: attemptID)?.items.first?.response)
        XCTAssertNil(revised.isCorrect)
        XCTAssertEqual(Set(revised.selectedOptionIDs), question.correctOptionIDs)
        XCTAssertEqual(revised.confidence, .certain)
        XCTAssertEqual(revised.responseDuration, 4)

        let result = try await store.finalizeAttempt(id: attemptID)
        XCTAssertEqual(result.correct, 1)
        XCTAssertEqual(result.total, 1)
        let finalized = try XCTUnwrap(store.attempt(id: attemptID)?.items.first?.response)
        XCTAssertEqual(finalized.isCorrect, true)
        XCTAssertEqual(Set(finalized.selectedOptionIDs), question.correctOptionIDs)
        XCTAssertTrue(store.itemMastery.isEmpty)

        let snapshot = await persistence.snapshot(for: "assessment-tests")
        let persisted = try XCTUnwrap(snapshot)
        XCTAssertEqual(
            persisted.attempts.first?.items.first?.response?.selectedOptionIDs,
            question.correctOptionIDs.sorted()
        )
    }

    @MainActor
    func testReviewRatingPersistsOnAttemptAndRejectsSecondRating() async throws {
        let persistence = InMemoryStudyAssessmentPersistence()
        let store = try await Self.activatedStudyStore(persistence: persistence)
        let question = try XCTUnwrap(store.allQuestions.first { !$0.isFlagged })
        try await store.addToReview(questionID: question.id)
        let card = try XCTUnwrap(store.reviewCards.values.first { $0.questionID == question.id })
        let attemptID = try await store.startAttempt(plan: .review(questionIDs: [question.id]))
        _ = try await store.submitResponse(
            attemptID: attemptID,
            selectedOptionIDs: question.correctOptionIDs,
            confidence: .fairlySure,
            responseDuration: 6
        )

        try await store.rateReviewCard(
            id: card.id,
            rating: .good,
            attemptID: attemptID,
            questionID: question.id
        )
        XCTAssertEqual(
            store.attempt(id: attemptID)?.items.first?.response?.reviewRating,
            .good
        )
        XCTAssertEqual(store.reviewCards[card.id]?.lastRating, .good)
        XCTAssertEqual(store.reviewLogs.count, 1)

        let snapshot = await persistence.snapshot(for: "assessment-tests")
        let persisted = try XCTUnwrap(snapshot)
        XCTAssertEqual(
            persisted.attempts.first { $0.id == attemptID }?.items.first?.response?.reviewRating,
            .good
        )

        do {
            try await store.rateReviewCard(
                id: card.id,
                rating: .easy,
                attemptID: attemptID,
                questionID: question.id
            )
            XCTFail("A response must not be rated twice.")
        } catch {
            XCTAssertEqual(error as? StudyAssessmentEngineError, .reviewAlreadyRated)
        }
        XCTAssertEqual(store.reviewCards[card.id]?.lastRating, .good)
        XCTAssertEqual(store.reviewLogs.count, 1)
    }

    @MainActor
    func testAddToReviewIsIdempotentAndDoesNotShortenRatedInterval() async throws {
        let persistence = InMemoryStudyAssessmentPersistence()
        let store = try await Self.activatedStudyStore(persistence: persistence)
        let question = try XCTUnwrap(store.allQuestions.first { !$0.isFlagged })
        try await store.addToReview(questionID: question.id)
        let initialCard = try XCTUnwrap(store.reviewCards.values.first { $0.questionID == question.id })
        let attemptID = try await store.startAttempt(plan: .review(questionIDs: [question.id]))
        _ = try await store.submitResponse(
            attemptID: attemptID,
            selectedOptionIDs: question.correctOptionIDs,
            confidence: .certain,
            responseDuration: 3
        )
        try await store.rateReviewCard(
            id: initialCard.id,
            rating: .easy,
            attemptID: attemptID,
            questionID: question.id
        )
        let ratedCard = try XCTUnwrap(store.reviewCards[initialCard.id])
        XCTAssertEqual(ratedCard.intervalIndex, 3)
        XCTAssertEqual(ratedCard.lastRating, .easy)

        try await store.addToReview(questionID: question.id)
        try await store.addToReview(questionID: question.id)

        let unchangedCard = try XCTUnwrap(store.reviewCards[initialCard.id])
        XCTAssertEqual(store.reviewCards.count, 1)
        XCTAssertEqual(unchangedCard.id, ratedCard.id)
        XCTAssertEqual(unchangedCard.dueAt, ratedCard.dueAt)
        XCTAssertEqual(unchangedCard.intervalIndex, ratedCard.intervalIndex)
        XCTAssertEqual(unchangedCard.lastRating, ratedCard.lastRating)
        XCTAssertEqual(store.reviewLogs.count, 1)
    }

    @MainActor
    func testImmediateWrongResponseIsNotScheduledAgainDuringFinalization() async throws {
        let persistence = InMemoryStudyAssessmentPersistence()
        let idProvider = StudyTestIDProvider()
        let store = try await Self.activatedStudyStore(
            persistence: persistence,
            idProvider: { idProvider.next() }
        )
        let attemptID = try await store.startAttempt(plan: .legacyDrill(itemCount: 1))
        let question = try XCTUnwrap(store.currentItem(for: attemptID)?.question)
        let feedback = try await store.submitResponse(
            attemptID: attemptID,
            selectedOptionIDs: try incorrectSelection(for: question),
            confidence: .certain,
            responseDuration: 5
        )
        XCTAssertEqual(feedback?.isCorrect, false)
        let scheduledCard = try XCTUnwrap(
            store.reviewCards.values.first { $0.questionID == question.id }
        )
        XCTAssertEqual(idProvider.callCount, 2) // Attempt ID, then correction-card ID.

        let result = try await store.finalizeAttempt(id: attemptID)
        XCTAssertEqual(result.correct, 0)
        XCTAssertEqual(store.reviewCards.count, 1)
        XCTAssertEqual(store.reviewCards[scheduledCard.id]?.dueAt, scheduledCard.dueAt)
        XCTAssertEqual(store.reviewCards[scheduledCard.id]?.intervalIndex, scheduledCard.intervalIndex)
        XCTAssertEqual(idProvider.callCount, 2)
    }

    @MainActor
    func testFailedSubjectActivationCannotOverwriteMismatchedState() async throws {
        let mismatchedState = StudyAssessmentPersistentState(subjectID: "account-a")
        let persistence = InMemoryStudyAssessmentPersistence(
            initialStates: ["account-b": mismatchedState]
        )
        let store = StudyAssessmentStore(
            loader: DataStudyQuestionCatalogueLoader(data: try bundledStudyCatalogueData()),
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            seedProvider: { 29 }
        )

        await store.activate(subjectID: "account-a")
        XCTAssertEqual(store.loadState, .ready)
        await store.activate(subjectID: "account-b")
        guard case .failed = store.loadState else {
            return XCTFail("A mismatched persisted subject must fail activation.")
        }

        do {
            _ = try await store.startAttempt(plan: .legacyDrill(itemCount: 1))
            XCTFail("A failed subject must remain read-only.")
        } catch {
            XCTAssertEqual(error as? StudyAssessmentStoreError, .storeNotReady)
        }

        let preservedSnapshot = await persistence.snapshot(for: "account-b")
        let preserved = try XCTUnwrap(preservedSnapshot)
        XCTAssertEqual(preserved.subjectID, "account-a")
        XCTAssertTrue(preserved.attempts.isEmpty)
    }

    @MainActor
    func testResumedExpiredAttemptRejectsMutationUntilFinalized() async throws {
        let clock = StudyTestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let persistence = InMemoryStudyAssessmentPersistence()
        let loader = StaticStudyQuestionCatalogueLoader(
            catalogue: try Self.reviewedCatalogue(try await Self.loadBundledStudyCatalogue())
        )
        let firstStore = StudyAssessmentStore(
            loader: loader,
            persistence: persistence,
            now: { clock.now },
            seedProvider: { 31 }
        )
        await firstStore.activate(subjectID: "timed-account")
        let attemptID = try await firstStore.startAttempt(
            plan: .practiceExam(itemCount: 1, durationSeconds: 60)
        )
        clock.advance(by: 61)

        let resumedStore = StudyAssessmentStore(
            loader: loader,
            persistence: persistence,
            now: { clock.now },
            seedProvider: { 37 }
        )
        await resumedStore.activate(subjectID: "timed-account")
        XCTAssertEqual(resumedStore.attempt(id: attemptID)?.state, .active)
        let question = try XCTUnwrap(resumedStore.currentItem(for: attemptID)?.question)

        do {
            _ = try await resumedStore.submitResponse(
                attemptID: attemptID,
                selectedOptionIDs: question.correctOptionIDs,
                confidence: .certain,
                responseDuration: 10
            )
            XCTFail("An expired attempt must reject new responses.")
        } catch {
            XCTAssertEqual(error as? StudyAssessmentEngineError, .attemptExpired)
        }
        XCTAssertNil(resumedStore.currentItem(for: attemptID)?.response)

        do {
            try await resumedStore.move(to: 0, in: attemptID)
            XCTFail("An expired attempt must reject navigation changes.")
        } catch {
            XCTAssertEqual(error as? StudyAssessmentEngineError, .attemptExpired)
        }

        let result = try await resumedStore.finalizeAttempt(id: attemptID, allowIncomplete: true)
        XCTAssertEqual(result.correct, 0)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(resumedStore.attempt(id: attemptID)?.state, .completed)
    }

    func testHybridStudyPreviewPackagesUseValidCanonicalReferences() throws {
        let package = try XCTUnwrap(StudyCoursePreview.packages.first)
        XCTAssertTrue(StudyCoursePackageValidator.validate(package).isEmpty)
        XCTAssertEqual(Set(package.courses.map(\.id)), [
            "course.communist-manifesto",
            "course.basic-principles.exam-prep"
        ])
        XCTAssertTrue(package.courses.allSatisfy { $0.publicationStatus == .preview })
    }

    func testLegacyCourseFinalDoesNotRequireSchemaThreeNativeExamFields() throws {
        let preview = try XCTUnwrap(StudyCoursePreview.packages.first)
        let course = try XCTUnwrap(preview.courses.first)
        let legacyFinal = StudyCourseAssessmentBlueprint(
            id: "legacy.course-final",
            title: "Legacy Course Final",
            kind: .courseFinal,
            questionIDs: [],
            requestedQuestionCount: 0,
            durationSeconds: 7_200,
            gradeRole: .summative,
            writtenSections: [],
            totalPoints: 100,
            courseID: course.id
        )
        let legacyPackage = StudyCoursePackage(
            schemaVersion: 1,
            packageID: "legacy.course-package",
            contentVersion: "1.0.0",
            locale: "en",
            minimumAppVersion: "1.0",
            courses: [course],
            studyGuides: [],
            readingGuides: [],
            primaryReadings: [],
            readingLists: [],
            videos: [],
            exerciseSets: [],
            assessments: [legacyFinal],
            glossaryTerms: [],
            bibliographySources: []
        )

        let issues = StudyCoursePackageValidator.validate(legacyPackage)
        XCTAssertTrue(issues.isEmpty, issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n"))
    }

    func testDialecticsCoursePackagePreservesCompleteSourceInventory() throws {
        let package = try loadDialecticsCoursePackage()
        let questions = try XCTUnwrap(package.questions)
        let assignments = try XCTUnwrap(package.assignments)
        let learningPaths = try XCTUnwrap(package.learningPaths)
        let assets = try XCTUnwrap(package.assets)
        let restrictedResources = try XCTUnwrap(package.restrictedResources)
        let modules = package.courses.flatMap(\.modules)
        let lessons = modules.flatMap(\.lessons)
        let blocks = lessons.flatMap(\.blocks)
        let finals = package.assessments.filter { $0.kind == .courseFinal }

        XCTAssertEqual(package.packageID, "Marxist_Info_App_Content_Pack")
        XCTAssertEqual(package.schemaVersion, 3)
        XCTAssertEqual(package.contentVersion, "1.0.0")
        XCTAssertEqual(Set(package.courses.map(\.id)), Set(["PHI111", "PHI211"]))
        XCTAssertEqual(package.courses.count, 2)
        XCTAssertEqual(modules.count, 26)
        XCTAssertEqual(lessons.count, 26)
        XCTAssertEqual(blocks.filter { $0.kind == .lessonContent }.count, 221)
        XCTAssertEqual(blocks.filter { $0.kind == .exercise }.count, 52)
        XCTAssertEqual(blocks.filter { $0.kind == .moduleQuiz }.count, 26)
        XCTAssertEqual(package.exerciseSets.count, 52)
        XCTAssertEqual(package.exerciseSets.flatMap(\.exercises).count, 52)
        XCTAssertEqual(package.assessments.filter { $0.kind == .moduleQuiz }.count, 26)
        XCTAssertEqual(questions.count, 246)
        XCTAssertEqual(questions.filter { $0.examCode == nil }.count, 208)
        XCTAssertEqual(questions.filter { $0.examCode != nil }.count, 38)
        XCTAssertEqual(assignments.count, 11)
        XCTAssertEqual(finals.count, 2)
        XCTAssertEqual(finals.flatMap { $0.examSections ?? [] }.flatMap(\.questions).count, 38)
        XCTAssertEqual(learningPaths.count, 1)
        XCTAssertEqual(assets.count, 0)
        XCTAssertEqual(restrictedResources.count, 2)
        XCTAssertEqual(package.glossaryTerms.count, 103)
        XCTAssertEqual(package.bibliographySources.count, 57)

        let questionCounts = Dictionary(grouping: questions, by: \.type).mapValues(\.count)
        XCTAssertEqual(questionCounts[.singleChoice], 104)
        XCTAssertEqual(questionCounts[.multipleChoice], 26)
        XCTAssertEqual(questionCounts[.matching], 26)
        XCTAssertEqual(questionCounts[.shortResponse], 64)
        XCTAssertEqual(questionCounts[.reconstruction], 26)
        XCTAssertTrue(questions.allSatisfy { $0.source.bank == .course })
        XCTAssertTrue(questions.allSatisfy { $0.qaStatus == .draftNeedsAcademicReview })

        let issues = StudyCoursePackageValidator.validate(package)
        XCTAssertTrue(issues.isEmpty, issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n"))
    }

    func testPHI111LessonsIncludeOptionalCourseLearningSupportsWithoutChangingSchema() throws {
        let package = try loadDialecticsCoursePackage()
        let phi111 = try XCTUnwrap(package.courses.first { $0.id == "PHI111" })
        let phi211 = try XCTUnwrap(package.courses.first { $0.id == "PHI211" })
        let phi111Lessons = phi111.modules.flatMap(\.lessons)

        XCTAssertEqual(package.schemaVersion, 3)
        XCTAssertEqual(phi111Lessons.count, 12)
        XCTAssertTrue(phi111Lessons.allSatisfy { ($0.objectives?.count ?? 0) == 3 })
        XCTAssertTrue(phi111Lessons.allSatisfy { ($0.essentialQuestions?.count ?? 0) == 2 })
        XCTAssertTrue(phi111Lessons.allSatisfy { ($0.reflectionPrompts?.count ?? 0) == 2 })
        XCTAssertTrue(phi211.modules.flatMap(\.lessons).allSatisfy {
            $0.objectives == nil && $0.essentialQuestions == nil && $0.reflectionPrompts == nil
        })
    }

    func testSectionWorkRecordIsVersionScopedAndClampsConfidence() {
        let first = StudySectionWorkRecord(
            subjectID: "guest.local",
            courseID: "PHI111",
            courseVersion: "2.0.0",
            lessonID: "L1",
            blockID: "S1",
            confidence: 8
        )
        let upgraded = StudySectionWorkRecord(
            subjectID: "guest.local",
            courseID: "PHI111",
            courseVersion: "3.0.0",
            lessonID: "L1",
            blockID: "S1",
            confidence: 0
        )

        XCTAssertNotEqual(first.recordID, upgraded.recordID)
        XCTAssertEqual(first.confidence, 5)
        XCTAssertEqual(upgraded.confidence, 1)

        first.update(
            notesMarkdown: "A note",
            reflectionMarkdown: "A reflection",
            summaryMarkdown: "A summary",
            confidence: nil,
            at: Date(timeIntervalSince1970: 123)
        )
        XCTAssertEqual(first.notesMarkdown, "A note")
        XCTAssertNil(first.confidence)
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 123))
    }

    func testDialecticsCourseRelationshipsAndAssessmentPlacementRemainCanonical() throws {
        let package = try loadDialecticsCoursePackage()
        let questions = try XCTUnwrap(package.questions)
        let assignments = try XCTUnwrap(package.assignments)
        let assessments = Dictionary(uniqueKeysWithValues: package.assessments.map { ($0.id, $0) })
        let exerciseSets = Dictionary(uniqueKeysWithValues: package.exerciseSets.map { ($0.id, $0) })

        for course in package.courses {
            XCTAssertEqual(course.publicationStatus, .draftNeedsReview)
            XCTAssertEqual(course.contentMode, "downloadable_versioned_package")
            XCTAssertFalse(try XCTUnwrap(course.primarySubject).isEmpty)
            XCTAssertEqual(course.sourceMetadata?.structuralValidationPassed, true)
            XCTAssertEqual(course.sourceMetadata?.academicVerificationStatus, "not_completed")
            XCTAssertEqual(course.sourceMetadata?.requiredHumanReview?.count, 5)
            XCTAssertEqual(assignments.filter { $0.courseID == course.id }.map(\.weightPercent).reduce(0, +), 60)
            XCTAssertEqual(course.modules.flatMap { $0.assignmentIDs ?? [] }, course.assignmentIDs ?? [])

            let finalID = try XCTUnwrap(course.finalAssessmentID)
            let final = try XCTUnwrap(assessments[finalID])
            XCTAssertEqual(final.kind, .courseFinal)
            XCTAssertEqual(final.courseID, course.id)
            XCTAssertEqual(final.courseWeightPercent, 40)
            XCTAssertEqual(final.totalPoints, 100)
            XCTAssertEqual(final.durationSeconds, 10_800)
            XCTAssertEqual(final.examSections?.flatMap(\.questions).count, 19)
            XCTAssertFalse(try XCTUnwrap(final.sourceMarkdown).isEmpty)
            XCTAssertFalse(try XCTUnwrap(final.candidateInstructionsMarkdown).isEmpty)
            XCTAssertFalse(try XCTUnwrap(final.candidateDeclarationMarkdown).isEmpty)
            XCTAssertTrue(try XCTUnwrap(final.examSections).allSatisfy {
                !$0.questions.isEmpty
                    && !($0.instructionsMarkdown ?? "").isEmpty
                    && $0.questions.allSatisfy { question in
                        question.responseQuestionID.map { responseID in
                            questions.contains { $0.id == responseID && $0.examCode == question.code }
                        } == true
                    }
            })
            XCTAssertFalse(course.modules.flatMap(\.lessons).flatMap(\.blocks).contains { $0.referencedContentID == finalID })

            for module in course.modules {
                XCTAssertEqual(module.sourceVersion, "1.0.0")
                XCTAssertEqual(module.sourceStatus, "draft_needs_academic_review")
                let quizID = try XCTUnwrap(module.moduleQuizID)
                let quiz = try XCTUnwrap(assessments[quizID])
                XCTAssertEqual(quiz.kind, .moduleQuiz)
                XCTAssertEqual(quiz.courseID, course.id)
                XCTAssertEqual(quiz.moduleID, module.id)
                XCTAssertEqual(quiz.questionIDs.count, 8)
                XCTAssertEqual(quiz.recommendedTimeMinimumMinutes, 25)
                XCTAssertEqual(quiz.recommendedTimeMaximumMinutes, 35)
                XCTAssertEqual(module.lessons.first?.blocks.last?.referencedContentID, quizID)
                XCTAssertTrue(quiz.questionIDs.allSatisfy { id in questions.contains { $0.id == id } })
            }
        }

        for block in package.courses.flatMap(\.modules).flatMap(\.lessons).flatMap(\.blocks)
            where block.kind == .exercise {
            let setID = try XCTUnwrap(block.referencedContentID)
            XCTAssertEqual(exerciseSets[setID]?.exercises.count, 1, block.id)
        }

        let path = try XCTUnwrap(package.learningPaths?.first)
        XCTAssertEqual(path.id, "LP-DIALECTICS-HEGEL-MARX")
        XCTAssertEqual(path.courses.map(\.courseID), ["PHI111", "PHI211"])
        XCTAssertEqual(path.courses.map(\.order), [1, 2])
        XCTAssertEqual(package.courses.first { $0.id == "PHI111" }?.recommendedCourseIDs, ["PHI211"])

        let chunks = package.readingGuides.flatMap(\.chunks)
        XCTAssertEqual(chunks.count, 26)
        XCTAssertEqual(Set(chunks.compactMap(\.moduleID)), Set(package.courses.flatMap(\.modules).map(\.id)))
        XCTAssertTrue(chunks.allSatisfy { !($0.bodyMarkdown ?? "").isEmpty })
        XCTAssertTrue(package.courses.allSatisfy {
            !($0.courseSourceMarkdown ?? "").isEmpty
                && !($0.assignmentHandbookMarkdown ?? "").isEmpty
        })
        for course in package.courses {
            let continuousReading = try XCTUnwrap(course.courseSourceMarkdown)
            XCTAssertFalse(continuousReading.contains("[[EXERCISE"), course.id)
            XCTAssertFalse(continuousReading.contains("[[QUIZ"), course.id)
            XCTAssertFalse(continuousReading.contains("[[MILESTONE"), course.id)
            XCTAssertFalse(continuousReading.contains("[[SOLUTIONS"), course.id)

            let solutions = try XCTUnwrap(course.formativeSolutionsMarkdown)
            XCTAssertFalse(solutions.contains("[[SOLUTIONS"), course.id)
            for exercise in package.exerciseSets.flatMap(\.exercises) where exercise.id.hasPrefix(course.id) {
                XCTAssertTrue(solutions.contains(try XCTUnwrap(exercise.solutionMarkdown)), exercise.id)
            }
            for question in questions where question.examCode == nil && question.courses.contains(course.id) && !question.answerNote.isEmpty {
                XCTAssertTrue(solutions.contains(question.answerNote), question.id)
            }
        }
        XCTAssertFalse(package.courses.first { $0.id == "PHI211" }?.conclusionMarkdown?.isEmpty ?? true)
    }

    func testDialecticsFinalsCreateNativeHumanMarkedAttemptsInSourceOrder() throws {
        let package = try loadDialecticsCoursePackage()
        let questions = try Self.reviewedQuestions(try XCTUnwrap(package.questions))
        let catalogue = StudyQuestionCatalogue(
            catalogueVersion: package.contentVersion,
            generatedOn: "source-package",
            sourceFile: package.packageID,
            counts: StudyQuestionCatalogueCounts(
                total: questions.count,
                singleChoice: questions.filter { $0.type == .singleChoice }.count,
                multipleChoice: questions.filter { $0.type == .multipleChoice }.count,
                bank1: 0,
                bank2: 0
            ),
            statusNotice: "Course-source validation",
            adjudicationRegister: [:],
            duplicateClusters: [:],
            items: questions
        )
        try StudyQuestionCatalogueDecoder.validate(catalogue)

        for final in package.assessments.filter({ $0.kind == .courseFinal }) {
            let sections = try XCTUnwrap(final.examSections)
            let selectedIDs = sections.flatMap { section -> [String] in
                if section.responsePolicy == "all" {
                    return section.questions.compactMap(\.responseQuestionID)
                }
                return section.questions.first?.responseQuestionID.map { [$0] } ?? []
            }
            XCTAssertEqual(selectedIDs.count, 13)
            let selectedMarks = sections.reduce(into: 0) { total, section in
                if section.responsePolicy == "all" {
                    total += section.questions.reduce(0) { $0 + $1.points }
                } else {
                    total += section.questions.first?.points ?? 0
                }
            }
            XCTAssertEqual(selectedMarks, 100)

            let plan = StudySessionPlan(
                id: final.id,
                kind: .practiceExam,
                title: final.title,
                requestedItemCount: selectedIDs.count,
                domain: nil,
                requestedQuestionIDs: selectedIDs,
                feedbackPolicy: .afterSubmission,
                durationSeconds: final.durationSeconds,
                affectsItemMastery: false,
                context: StudyAssessmentContext(
                    source: .exam,
                    courseID: try XCTUnwrap(final.courseID),
                    assessmentID: final.id,
                    gradeRole: .summative
                )
            )
            let attempt = try StudyAssessmentEngine.makeAttempt(catalogue: catalogue, plan: plan, seed: 41)
            XCTAssertEqual(attempt.items.map { $0.question.id }, selectedIDs)
            XCTAssertTrue(attempt.items.allSatisfy { $0.question.type == .shortResponse })
            XCTAssertTrue(attempt.items.allSatisfy { $0.question.expectedResponse == nil })
        }
    }

    func testDialecticsCoursesAreNativeOnlyAndRestrictedMarkingGuidesAreExcluded() throws {
        let package = try loadDialecticsCoursePackage()
        let assets = package.assets ?? []
        let restrictedResources = try XCTUnwrap(package.restrictedResources)

        XCTAssertTrue(assets.isEmpty)
        XCTAssertTrue(package.courses.allSatisfy { ($0.assetIDs ?? []).isEmpty })
        XCTAssertTrue((package.assignments ?? []).allSatisfy { $0.sourceAssetID == nil })
        XCTAssertTrue(package.assessments.allSatisfy { $0.sourceAssetID == nil })
        for courseID in ["PHI111", "PHI211"] {
            for suffix in ["coursebook", "handbook", "exam"] {
                XCTAssertNil(Bundle.main.url(forResource: "\(courseID)-\(suffix)", withExtension: "pdf"))
            }
        }
        XCTAssertTrue(restrictedResources.allSatisfy { $0.accessPolicy == .examinerOnly })
        XCTAssertNil(Bundle.main.url(forResource: "marking-guide-restricted", withExtension: "pdf"))
        XCTAssertNil(Bundle.main.url(forResource: "marking-guide-restricted", withExtension: "md"))
    }

    func testDialecticsQuestionsValidateInExistingAssessmentEngine() throws {
        let package = try loadDialecticsCoursePackage()
        let questions = try Self.reviewedQuestions(try XCTUnwrap(package.questions))
        let catalogue = StudyQuestionCatalogue(
            catalogueVersion: package.contentVersion,
            generatedOn: "source-package",
            sourceFile: package.packageID,
            counts: StudyQuestionCatalogueCounts(
                total: questions.count,
                singleChoice: questions.filter { $0.type == .singleChoice }.count,
                multipleChoice: questions.filter { $0.type == .multipleChoice }.count,
                bank1: 0,
                bank2: 0
            ),
            statusNotice: "Course-source validation",
            adjudicationRegister: [:],
            duplicateClusters: [:],
            items: questions
        )
        try StudyQuestionCatalogueDecoder.validate(catalogue)

        for blueprint in package.assessments where blueprint.kind == .moduleQuiz {
            let courseID = try XCTUnwrap(blueprint.courseID)
            let attempt = try StudyAssessmentEngine.makeAttempt(
                catalogue: catalogue,
                plan: blueprint.sessionPlan(courseID: courseID, moduleID: blueprint.moduleID),
                seed: 41
            )
            XCTAssertEqual(attempt.items.map { $0.question.id }, blueprint.questionIDs)
        }
    }

    func testPreviewLessonsDoNotCreateFalseCourseCompletion() throws {
        let course = try XCTUnwrap(
            StudyCoursePreview.packages.flatMap(\.courses)
                .first { $0.id == "course.communist-manifesto" }
        )
        let previewLessonIDs = Set(course.modules.flatMap(\.lessons).map(\.id))
        XCTAssertEqual(StudyLearningProgress.fraction(for: course, completedLessonIDs: previewLessonIDs), 0)
    }

    func testCourseLaunchSelectsTheFirstIncompleteLessonInSyllabusOrder() throws {
        let package = try loadDialecticsCoursePackage()
        let course = try XCTUnwrap(package.courses.first { $0.id == "PHI111" })

        let first = try XCTUnwrap(StudyLearningProgress.nextLesson(for: course, completedLessonIDs: []))
        XCTAssertEqual(first.moduleID, "PHI111-M01")
        XCTAssertEqual(first.moduleNumber, 1)
        XCTAssertEqual(first.lessonID, "PHI111-M01-LESSON")

        let second = try XCTUnwrap(
            StudyLearningProgress.nextLesson(
                for: course,
                completedLessonIDs: ["PHI111-M01-LESSON"]
            )
        )
        XCTAssertEqual(second.moduleID, "PHI111-M02")
        XCTAssertEqual(second.moduleNumber, 2)
        XCTAssertEqual(second.lessonID, "PHI111-M02-LESSON")

        let allLessonIDs = Set(course.modules.flatMap(\.lessons).map(\.id))
        XCTAssertNil(StudyLearningProgress.nextLesson(for: course, completedLessonIDs: allLessonIDs))
        XCTAssertEqual(StudyLearningProgress.firstLesson(for: course)?.lessonID, "PHI111-M01-LESSON")
    }

    func testCourseSectionNavigationPreservesEveryAuthoredSectionInOrder() throws {
        let package = try loadDialecticsCoursePackage()
        let course = try XCTUnwrap(package.courses.first { $0.id == "PHI111" })
        let destinations = StudyLearningProgress.sectionDestinations(for: course)

        XCTAssertEqual(destinations.count, 111)
        XCTAssertEqual(destinations.first?.blockID, "PHI111-M01-S01")
        XCTAssertEqual(destinations.first?.sectionNumber, 1)
        XCTAssertEqual(destinations.first?.sectionCount, 6)
        XCTAssertEqual(destinations.last?.blockID, "PHI111-M12-S12")
        XCTAssertEqual(
            StudyLearningProgress.nextSection(in: course, after: "PHI111-M01-S01")?.blockID,
            "PHI111-M01-S02"
        )
        XCTAssertEqual(
            StudyLearningProgress.previousSection(in: course, before: "PHI111-M01-S02")?.blockID,
            "PHI111-M01-S01"
        )

        let firstLessonID = try XCTUnwrap(course.modules.first?.lessons.first?.id)
        let legacyCompleted = Set([firstLessonID])
        XCTAssertEqual(
            StudyLearningProgress.nextSection(
                for: course,
                completedLessonIDs: legacyCompleted,
                completedRequiredBlockIDs: []
            )?.blockID,
            "PHI111-M02-S01"
        )
        XCTAssertEqual(
            StudyLearningProgress.fraction(
                for: course,
                completedLessonIDs: legacyCompleted,
                completedRequiredBlockIDs: []
            ),
            6.0 / 111.0,
            accuracy: 0.000_001
        )
    }

    func testSectionCompletionUpdatesLegacyLessonCompletionWithoutLosingGranularity() throws {
        let package = try loadDialecticsCoursePackage()
        let course = try XCTUnwrap(package.courses.first { $0.id == "PHI111" })
        let lesson = try XCTUnwrap(course.modules.first?.lessons.first)
        let requiredBlockIDs = StudyLearningProgress.requiredSectionBlockIDs(in: lesson)
        let record = StudyCourseProgressRecord(
            subjectID: "section-progress-test",
            courseID: course.id,
            courseVersion: course.contentVersion
        )

        XCTAssertEqual(requiredBlockIDs.count, 6)
        for blockID in requiredBlockIDs {
            record.setSection(
                blockID,
                completed: true,
                lessonID: lesson.id,
                requiredBlockIDs: requiredBlockIDs
            )
        }

        XCTAssertTrue(record.completedLessonIDs.contains(lesson.id))
        XCTAssertTrue(Set(requiredBlockIDs).isSubset(of: Set(record.completedRequiredBlockIDs)))

        let firstBlockID = try XCTUnwrap(requiredBlockIDs.first)
        record.setSection(
            firstBlockID,
            completed: false,
            lessonID: lesson.id,
            requiredBlockIDs: requiredBlockIDs
        )

        XCTAssertFalse(record.completedLessonIDs.contains(lesson.id))
        XCTAssertFalse(record.completedRequiredBlockIDs.contains(firstBlockID))
        XCTAssertTrue(requiredBlockIDs.dropFirst().allSatisfy(record.completedRequiredBlockIDs.contains))
    }

    func testCourseAssessmentContextRoundTripsWithoutChangingStandalonePlans() throws {
        let standalone = StudySessionPlan.legacyDrill()
        XCTAssertNil(standalone.context)

        let plan = StudySessionPlan(
            id: "manifesto-module-1",
            kind: .domainPractice,
            title: "Module Check",
            requestedItemCount: 5,
            domain: .historicalMaterialism,
            requestedQuestionIDs: ["B1-001"],
            feedbackPolicy: .immediate,
            durationSeconds: nil,
            affectsItemMastery: false,
            context: StudyAssessmentContext(
                source: .course,
                courseID: "course.communist-manifesto",
                moduleID: "course.communist-manifesto.module.bourgeois-proletarians",
                assessmentID: "course.communist-manifesto.quiz.bourgeois-proletarians",
                gradeRole: .formative
            )
        )
        let decoded = try JSONDecoder().decode(StudySessionPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.context?.courseID, "course.communist-manifesto")
        XCTAssertEqual(decoded.context?.gradeRole, .formative)
    }

    func testStudyTabAndForumRemainInExistingBottomNavigation() {
        XCTAssertEqual(AppTab.bottomBarTabs[2], .study)
        XCTAssertTrue(AppTab.bottomBarTabs.contains(.forum))
    }

    func testLearningXPEventsAreStableAndDoNotUseScores() {
        let first = StudyLearningProgress.eventID(
            subjectID: "reader-1",
            kind: .lessonCompleted,
            contentID: "lesson-1",
            version: "1.0"
        )
        let second = StudyLearningProgress.eventID(
            subjectID: "reader-1",
            kind: .lessonCompleted,
            contentID: "lesson-1",
            version: "1.0"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(StudyLearningEventKind.lessonCompleted.points, 10)
        XCTAssertEqual(StudyLearningEventKind.dailyQuizSubmitted.points, 5)
    }

    func testImportedAssignmentsExposeEveryRecoverableSourceRubricCriterion() throws {
        let package = try loadDialecticsCoursePackage()
        let assignments = try XCTUnwrap(package.assignments)

        XCTAssertEqual(assignments.count, 11)
        XCTAssertEqual(assignments.flatMap(\.rubricCriteria).count, 54)
        XCTAssertTrue(assignments.allSatisfy { !$0.rubricCriteria.isEmpty })
        XCTAssertEqual(assignments.first { $0.id == "PHI111-A1" }?.rubricCriteria.first?.title, "Historical and conceptual accuracy")
        XCTAssertEqual(assignments.first { $0.id == "PHI211-A1" }?.rubricCriteria.first?.title, "Primary-text accuracy and source status")
    }

    func testWeightedGradebookKeepsAcademicResultsSeparateFromLearningProgress() throws {
        let package = try loadDialecticsCoursePackage()
        let course = try XCTUnwrap(package.courses.first { $0.id == "PHI111" })
        let assignments = try XCTUnwrap(package.assignments).filter { $0.courseID == course.id }
        let final = try XCTUnwrap(package.assessments.first { $0.id == course.finalAssessmentID })
        var submissions: [StudyAssignmentSubmissionRecord] = []
        var rubricMarks: [StudyRubricMarkRecord] = []

        for assignment in assignments {
            let submission = StudyAssignmentSubmissionRecord(
                subjectID: "learner-1",
                candidateDisplayName: "Learner",
                courseID: course.id,
                assignmentID: assignment.id,
                draftMarkdown: "Submitted work",
                status: .graded
            )
            submissions.append(submission)
            rubricMarks += assignment.rubricCriteria.map { criterion in
                StudyRubricMarkRecord(
                    submissionRecordID: submission.recordID,
                    subjectID: submission.subjectID,
                    courseID: course.id,
                    assignmentID: assignment.id,
                    criterionID: criterion.id,
                    criterionTitle: criterion.title,
                    markedBySubjectID: "examiner-1",
                    level: 4
                )
            }
        }

        let examSubmission = StudyExamSubmissionRecord(
            attemptID: UUID(),
            subjectID: "learner-1",
            candidateDisplayName: "Learner",
            courseID: course.id,
            assessmentID: final.id,
            title: final.title,
            questionIDs: ["Q1"],
            questionCodes: ["A1"],
            prompts: ["Prompt"],
            responses: ["Response"],
            pointValues: [100]
        )
        examSubmission.submissionStatus = .graded
        let examMark = StudyExamQuestionMarkRecord(
            examSubmissionID: examSubmission.recordID,
            questionID: "Q1",
            questionCode: "A1",
            maxPoints: 100,
            markedBySubjectID: "examiner-1",
            awardedPoints: 100
        )

        let snapshot = StudyCourseGradebook.make(
            course: course,
            assignments: assignments,
            assignmentSubmissions: submissions,
            rubricMarks: rubricMarks,
            finalAssessment: final,
            examSubmissions: [examSubmission],
            examMarks: [examMark],
            subjectID: "learner-1",
            readingCompletion: 0.5
        )

        XCTAssertEqual(snapshot.gradedWeightPercent, 100)
        XCTAssertEqual(snapshot.overallPercent, 100)
        XCTAssertEqual(snapshot.academicResult, "Pass")
        XCTAssertEqual(snapshot.readingCompletion, 0.5)
    }

    func testExternalBetaFeatureGatesRemainClosed() {
        XCTAssertFalse(AppFeatureFlags.forumEnabled)
        XCTAssertFalse(AppFeatureFlags.writtenCourseSubmissionsEnabled)
        XCTAssertFalse(AppFeatureFlags.examinerGradingEnabled)
        XCTAssertFalse(AppFeatureFlags.supportTipsEnabled)
        XCTAssertFalse(AppFeatureFlags.educationalVideosEnabled)
        XCTAssertFalse(AppFeatureFlags.unreviewedAssessmentContentEnabled)
    }

    @MainActor
    func testAssessmentDeletionErasesPersistedStateAndClearsActiveSubject() async throws {
        let persistence = InMemoryStudyAssessmentPersistence()
        let store = try await Self.activatedStudyStore(persistence: persistence)
        _ = try await store.startAttempt(plan: .legacyDrill(itemCount: 1))
        let persistedBeforeDeletion = await persistence.snapshot(for: "assessment-tests")
        XCTAssertNotNil(persistedBeforeDeletion)

        try await store.deleteLocalData(for: "assessment-tests")

        let persistedAfterDeletion = await persistence.snapshot(for: "assessment-tests")
        XCTAssertNil(persistedAfterDeletion)
        XCTAssertNil(store.activeSubjectID)
        XCTAssertEqual(store.loadState, .idle)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    @MainActor
    func testSwiftDataDeletionErasesOnlyTheRequestedStudySubject() throws {
        let schema = Schema([
            StudyCourseProgressRecord.self,
            StudyLearningEventRecord.self,
            StudySavedContentRecord.self,
            StudySectionWorkRecord.self,
            StudyAssignmentSubmissionRecord.self,
            StudyRubricMarkRecord.self,
            StudyExamSubmissionRecord.self,
            StudyExamQuestionMarkRecord.self,
            StudyAchievementRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let target = "delete-me"
        let survivor = "keep-me"

        let targetSubmission = StudyAssignmentSubmissionRecord(
            subjectID: target,
            candidateDisplayName: "Target",
            courseID: "PHI111",
            assignmentID: "A1",
            draftMarkdown: "private draft"
        )
        let targetExam = StudyExamSubmissionRecord(
            attemptID: UUID(),
            subjectID: target,
            candidateDisplayName: "Target",
            courseID: "PHI111",
            assessmentID: "FINAL",
            title: "Final",
            questionIDs: ["Q1"],
            questionCodes: ["A1"],
            prompts: ["Prompt"],
            responses: ["private response"],
            pointValues: [100]
        )
        [
            StudyCourseProgressRecord(subjectID: target, courseID: "PHI111", courseVersion: "2.0.0"),
            StudyCourseProgressRecord(subjectID: survivor, courseID: "PHI111", courseVersion: "2.0.0"),
        ].forEach(context.insert)
        context.insert(StudyLearningEventRecord(eventID: "delete-event", subjectID: target, kind: "lesson", contentID: "L1", points: 10))
        context.insert(StudySavedContentRecord(subjectID: target, contentID: "L1", contentKind: "lesson"))
        context.insert(StudySectionWorkRecord(
            subjectID: target,
            courseID: "PHI111",
            courseVersion: "2.0.0",
            lessonID: "L1",
            blockID: "S1",
            notesMarkdown: "private notes"
        ))
        context.insert(StudySectionWorkRecord(
            subjectID: survivor,
            courseID: "PHI111",
            courseVersion: "2.0.0",
            lessonID: "L1",
            blockID: "S1",
            notesMarkdown: "survivor notes"
        ))
        context.insert(targetSubmission)
        context.insert(StudyRubricMarkRecord(
            submissionRecordID: targetSubmission.recordID,
            subjectID: target,
            courseID: "PHI111",
            assignmentID: "A1",
            criterionID: "C1",
            criterionTitle: "Argument",
            markedBySubjectID: "examiner"
        ))
        context.insert(targetExam)
        context.insert(StudyExamQuestionMarkRecord(
            examSubmissionID: targetExam.recordID,
            questionID: "Q1",
            questionCode: "A1",
            maxPoints: 100,
            markedBySubjectID: "examiner"
        ))
        context.insert(StudyAchievementRecord(subjectID: target, achievementID: "first", title: "First", detail: "Test"))
        try context.save()

        try StudyLocalDataEraser.erase(subjectID: target, from: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyCourseProgressRecord>()).map(\.subjectID), [survivor])
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyLearningEventRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudySavedContentRecord>()).isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<StudySectionWorkRecord>()).map(\.subjectID),
            [survivor]
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyAssignmentSubmissionRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyRubricMarkRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyExamSubmissionRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyExamQuestionMarkRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyAchievementRecord>()).isEmpty)
    }

    nonisolated private static func loadBundledStudyCatalogue() async throws -> StudyQuestionCatalogue {
        try await BundledStudyQuestionCatalogueLoader().loadCatalogue()
    }

    nonisolated private static func reviewedCatalogue(_ catalogue: StudyQuestionCatalogue) throws -> StudyQuestionCatalogue {
        StudyQuestionCatalogue(
            catalogueVersion: catalogue.catalogueVersion,
            generatedOn: catalogue.generatedOn,
            sourceFile: catalogue.sourceFile,
            counts: catalogue.counts,
            statusNotice: catalogue.statusNotice,
            adjudicationRegister: catalogue.adjudicationRegister,
            duplicateClusters: catalogue.duplicateClusters,
            items: try reviewedQuestions(catalogue.items)
        )
    }

    nonisolated private static func reviewedQuestions(_ questions: [StudyQuestion]) throws -> [StudyQuestion] {
        let encoded = try JSONEncoder().encode(questions)
        guard var payload = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] else {
            throw CocoaError(.coderInvalidValue)
        }
        for index in payload.indices where payload[index]["qaStatus"] as? String != StudyQuestionQAStatus.flagged.rawValue {
            payload[index]["qaStatus"] = StudyQuestionQAStatus.reviewed.rawValue
        }
        return try JSONDecoder().decode(
            [StudyQuestion].self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private func loadDialecticsCoursePackage() throws -> StudyCoursePackage {
        let resourceURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "Marxist_Info_Dialectics_v1.study-course",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(StudyCoursePackage.self, from: Data(contentsOf: resourceURL))
    }

    @MainActor
    private static func activatedStudyStore(
        persistence: InMemoryStudyAssessmentPersistence,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000),
        idProvider: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws -> StudyAssessmentStore {
        let sourceCatalogue = try await loadBundledStudyCatalogue()
        let store = StudyAssessmentStore(
            loader: StaticStudyQuestionCatalogueLoader(catalogue: try reviewedCatalogue(sourceCatalogue)),
            persistence: persistence,
            now: { now },
            seedProvider: { 17 },
            idProvider: idProvider
        )
        await store.activate(subjectID: "assessment-tests")
        XCTAssertEqual(store.loadState, .ready)
        XCTAssertEqual(store.allQuestions.count, 529)
        return store
    }

    private func bundledStudyCatalogueData() throws -> Data {
        let resourceURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "Marxist_Info_Full_Question_Catalogue",
                withExtension: "json"
            )
        )
        return try Data(contentsOf: resourceURL)
    }

    private func incorrectSelection(for question: StudyQuestion) throws -> Set<String> {
        if question.correctOptionIDs.count > 1 {
            return [try XCTUnwrap(question.correctOptionIDs.sorted().first)]
        }
        return [try XCTUnwrap(
            question.options.keys.sorted().first { !question.correctOptionIDs.contains($0) }
        )]
    }

    private func scoredAttempt(
        catalogue: StudyQuestionCatalogue,
        correctCount: Int,
        total: Int
    ) throws -> StudyAttempt {
        var attempt = try StudyAssessmentEngine.makeAttempt(
            catalogue: catalogue,
            plan: .diagnostic(itemCount: total),
            seed: UInt64(correctCount + 1),
            attemptID: UUID(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        for index in attempt.items.indices {
            let question = attempt.items[index].question
            let correctIDs = question.correctOptionIDs.sorted()
            let selectedIDs: [String]
            if index < correctCount {
                selectedIDs = correctIDs
            } else if correctIDs.count > 1 {
                selectedIDs = Array(correctIDs.dropLast())
            } else {
                selectedIDs = [try XCTUnwrap(
                    question.options.keys.first { !question.correctOptionIDs.contains($0) }
                )]
            }
            attempt.items[index].response = StudyQuestionResponse(
                selectedOptionIDs: selectedIDs,
                confidence: .fairlySure,
                submittedAt: attempt.startedAt,
                responseDuration: 5,
                isCorrect: nil,
                wasAppliedToMastery: false
            )
        }
        return StudyAssessmentEngine.finalizeScoring(attempt, at: attempt.startedAt)
    }

    private func studyResponse(
        isCorrect: Bool,
        confidence: StudyConfidence = .fairlySure
    ) -> StudyQuestionResponse {
        StudyQuestionResponse(
            selectedOptionIDs: [],
            confidence: confidence,
            submittedAt: Date(timeIntervalSince1970: 1_800_000_000),
            responseDuration: 5,
            isCorrect: isCorrect,
            wasAppliedToMastery: false
        )
    }

    private final class StudyTestIDProvider: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0

        var callCount: Int {
            lock.withLock { calls }
        }

        func next() -> UUID {
            lock.withLock { calls += 1 }
            return UUID()
        }
    }

    private final class StudyTestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) {
            self.date = date
        }

        var now: Date {
            lock.withLock { date }
        }

        func advance(by interval: TimeInterval) {
            lock.withLock { date = date.addingTimeInterval(interval) }
        }
    }

    private struct StaticStudyQuestionCatalogueLoader: StudyQuestionCatalogueLoading, Sendable {
        let catalogue: StudyQuestionCatalogue

        func loadCatalogue() async throws -> StudyQuestionCatalogue {
            catalogue
        }
    }
}
