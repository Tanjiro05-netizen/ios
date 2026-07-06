import AVFoundation
import Foundation
import ImageIO
import MediaPlayer
import Observation
import Security
import SwiftUI
import UIKit

private struct KeychainStore {
    enum StoreError: LocalizedError {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                "Keychain operation failed with status \(status)."
            }
        }
    }

    let service: String

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.unhandledStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.unhandledStatus(addStatus)
            }
        default:
            throw StoreError.unhandledStatus(updateStatus)
        }
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
@Observable
final class AuthStore {
    var session: AuthSession?
    var guestSession: GuestSession?
    var profile: Profile?
    var isLoading = true
    var errorMessage: String?
    var statusMessage: String?

    private let client = SupabaseRESTClient()
    private let forumClient = ForumClient()
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.marxist.forum.auth")
    private let sessionKey = "ios.auth.session"
    private let guestKey = "ios.auth.guest"

    var accessToken: String? { session?.accessToken }
    var userId: String? { session?.user.id }
    var isGuest: Bool { guestSession != nil }
    var isAuthenticated: Bool { session != nil || guestSession != nil }
    var displayName: String { profile?.username ?? session?.user.email ?? guestSession?.username ?? "Reader" }

    func restore() async {
        defer { isLoading = false }

        if restoreStoredSession() {
            await refreshProfile()
        } else if let data = defaults.data(forKey: guestKey),
                  let guest = try? JSONDecoder.supabase.decode(GuestSession.self, from: data) {
            guestSession = guest
            profile = Profile(id: guest.id, username: guest.username, avatarUrl: nil, website: nil, updatedAt: guest.createdAt, bio: "Browsing as guest", ideology: nil, bannerUrl: nil, role: "guest", isCertified: false, isAdmin: false, hasInviteAccess: false, inviteCodeUsed: nil)
        }
        PushRegistrationService.shared.configure(userId: userId, accessToken: accessToken)
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let signedIn = try await client.authSignIn(email: email, password: password)
            try saveSession(signedIn)
            session = signedIn
            guestSession = nil
            defaults.removeObject(forKey: guestKey)
            await refreshProfile()
            PushRegistrationService.shared.configure(userId: userId, accessToken: accessToken)
            await PushRegistrationService.shared.registerIfPossible()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String, username: String, inviteCode: String) async {
        errorMessage = nil
        statusMessage = nil
        do {
            if let created = try await client.authSignUp(email: email, password: password, username: username, inviteCode: inviteCode) {
                try saveSession(created)
                session = created
                await refreshProfile()
            }
            statusMessage = "Account created. Check your email if confirmation is enabled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithApple(idToken: String, nonce: String?) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let signedIn = try await client.authSignInWithApple(idToken: idToken, nonce: nonce)
            try saveSession(signedIn)
            session = signedIn
            guestSession = nil
            defaults.removeObject(forKey: guestKey)
            await refreshProfile()
            PushRegistrationService.shared.configure(userId: userId, accessToken: accessToken)
            await PushRegistrationService.shared.registerIfPossible()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func browseAsGuest() {
        let guest = GuestSession(id: "guest-\(UUID().uuidString)", username: Self.makeGuestName(), createdAt: ISO8601DateFormatter().string(from: Date()))
        guestSession = guest
        session = nil
        profile = Profile(id: guest.id, username: guest.username, avatarUrl: nil, website: nil, updatedAt: guest.createdAt, bio: "Browsing as guest", ideology: nil, bannerUrl: nil, role: "guest", isCertified: false, isAdmin: false, hasInviteAccess: false, inviteCodeUsed: nil)
        keychain.delete(account: sessionKey)
        defaults.removeObject(forKey: sessionKey)
        if let data = try? JSONEncoder.supabase.encode(guest) {
            defaults.set(data, forKey: guestKey)
        }
    }

    func signOut() async {
        if let token = session?.accessToken {
            await client.authSignOut(accessToken: token)
        }
        session = nil
        guestSession = nil
        profile = nil
        keychain.delete(account: sessionKey)
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: guestKey)
        PushRegistrationService.shared.configure(userId: nil, accessToken: nil)
    }

    func refreshProfile() async {
        guard let userId else { return }
        do {
            profile = try await forumClient.fetchProfile(id: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSession(_ session: AuthSession) throws {
        let data = try JSONEncoder.supabase.encode(session)
        try keychain.set(data, for: sessionKey)
        defaults.removeObject(forKey: sessionKey)
    }

    private func restoreStoredSession() -> Bool {
        if let data = try? keychain.data(for: sessionKey),
           let restored = try? JSONDecoder.supabase.decode(AuthSession.self, from: data) {
            session = restored
            guestSession = nil
            return true
        }

        guard let legacyData = defaults.data(forKey: sessionKey),
              let restored = try? JSONDecoder.supabase.decode(AuthSession.self, from: legacyData) else {
            return false
        }
        session = restored
        guestSession = nil
        try? keychain.set(legacyData, for: sessionKey)
        defaults.removeObject(forKey: sessionKey)
        return true
    }

    private static func makeGuestName() -> String {
        let adjectives = ["Red", "Brave", "Patient", "Bright", "Kind", "Quiet", "Keen"]
        let nouns = ["Reader", "Comrade", "Scholar", "Worker", "Archivist", "Historian"]
        return "\(adjectives.randomElement()!)\(nouns.randomElement()!)\(Int.random(in: 10...99))"
    }
}

@MainActor
@Observable
final class SettingsStore {
    var settings = AppSettings()
    private let defaults = UserDefaults.standard

    func restore() {
        if let data = defaults.data(forKey: "ios.settings"),
           let restored = try? JSONDecoder.supabase.decode(AppSettings.self, from: data) {
            settings = restored
        }
    }

    func save() {
        if let data = try? JSONEncoder.supabase.encode(settings) {
            defaults.set(data, forKey: "ios.settings")
        }
    }
}

@MainActor
@Observable
final class DownloadStore {
    var downloads: [DownloadedEpub] = []
    var activeDownloadId: String?
    var errorMessage: String?

    private let defaults = UserDefaults.standard

    func restore() {
        if let data = defaults.data(forKey: "ios.epub.downloads"),
           let restored = try? JSONDecoder.supabase.decode([DownloadedEpub].self, from: data) {
            downloads = restored.filter { FileManager.default.fileExists(atPath: $0.localPath) }
        }
    }

    func cached(bookId: String) -> DownloadedEpub? {
        downloads.first { $0.bookId == bookId }
    }

    func cache(book: Book, remoteURL: URL) async -> DownloadedEpub? {
        if let existing = cached(bookId: book.id) { return existing }
        guard let epubFilename = book.epubFilename else { return nil }

        activeDownloadId = book.id
        defer { activeDownloadId = nil }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            let directory = try epubDirectory()
            let destination = directory.appending(path: epubFilename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)

            let size = (response.expectedContentLength > 0) ? Int(response.expectedContentLength) : nil
            let entry = DownloadedEpub(
                bookId: book.id,
                title: book.title,
                author: book.author,
                epubFilename: epubFilename,
                localPath: destination.path,
                cachedAt: ISO8601DateFormatter().string(from: Date()),
                fileSize: size
            )
            downloads.removeAll { $0.bookId == book.id }
            downloads.append(entry)
            save()
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func remove(_ entry: DownloadedEpub) {
        try? FileManager.default.removeItem(atPath: entry.localPath)
        downloads.removeAll { $0.bookId == entry.bookId }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder.supabase.encode(downloads) {
            defaults.set(data, forKey: "ios.epub.downloads")
        }
    }

    private func epubDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "epub_cache", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}

@MainActor
@Observable
final class ReadingActivityStore {
    var continueReading: [ContinueReadingItem] = []
    var quotes: [QuoteNotebookItem] = []

    private let defaults = UserDefaults.standard
    private let progressKey = "ios.reader.continue"
    private let quotesKey = "ios.reader.quotes"

    func restore() {
        if let data = defaults.data(forKey: progressKey),
           let restored = try? JSONDecoder.supabase.decode([ContinueReadingItem].self, from: data) {
            continueReading = restored
        }
        if let data = defaults.data(forKey: quotesKey),
           let restored = try? JSONDecoder.supabase.decode([QuoteNotebookItem].self, from: data) {
            quotes = restored
        }
    }

    func upsertProgress(book: Book, chapterTitle: String?, chapterIndex: Int, chapterCount: Int) {
        let safeCount = max(chapterCount, 1)
        let safeIndex = min(max(chapterIndex, 0), safeCount - 1)
        let progress = Double(safeIndex + 1) / Double(safeCount)
        let item = ContinueReadingItem(
            bookId: book.id,
            title: book.title,
            author: book.author,
            chapterTitle: chapterTitle,
            chapterIndex: safeIndex,
            chapterCount: safeCount,
            progress: progress,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        continueReading.removeAll { $0.bookId == book.id }
        continueReading.insert(item, at: 0)
        if continueReading.count > 12 {
            continueReading = Array(continueReading.prefix(12))
        }
        saveProgress()
    }

    @discardableResult
    func saveQuote(text: String, sourceTitle: String, sourceDetail: String? = nil, routeBookId: String? = nil) -> QuoteNotebookItem? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !cleanSource.isEmpty else { return nil }

        let now = ISO8601DateFormatter().string(from: Date())
        if let existingIndex = quotes.firstIndex(where: {
            $0.text.caseInsensitiveCompare(cleanText) == .orderedSame
                && $0.sourceTitle.caseInsensitiveCompare(cleanSource) == .orderedSame
        }) {
            var existing = quotes.remove(at: existingIndex)
            existing.createdAt = now
            existing.sourceDetail = sourceDetail ?? existing.sourceDetail
            existing.routeBookId = routeBookId ?? existing.routeBookId
            quotes.insert(existing, at: 0)
            saveQuotes()
            return existing
        }

        let item = QuoteNotebookItem(
            id: UUID().uuidString,
            text: cleanText,
            sourceTitle: cleanSource,
            sourceDetail: sourceDetail,
            routeBookId: routeBookId,
            createdAt: now
        )
        quotes.insert(item, at: 0)
        if quotes.count > 150 {
            quotes = Array(quotes.prefix(150))
        }
        saveQuotes()
        return item
    }

    func quoteExists(text: String, sourceTitle: String) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return quotes.contains {
            $0.text.caseInsensitiveCompare(cleanText) == .orderedSame
                && $0.sourceTitle.caseInsensitiveCompare(cleanSource) == .orderedSame
        }
    }

    func removeQuote(_ item: QuoteNotebookItem) {
        quotes.removeAll { $0.id == item.id }
        saveQuotes()
    }

    private func saveProgress() {
        if let data = try? JSONEncoder.supabase.encode(continueReading) {
            defaults.set(data, forKey: progressKey)
        }
    }

    private func saveQuotes() {
        if let data = try? JSONEncoder.supabase.encode(quotes) {
            defaults.set(data, forKey: quotesKey)
        }
    }
}

@MainActor
struct NowPlayingCommandHandlers {
    var play: () -> Void
    var pause: () -> Void
    var toggle: () -> Void
    var seek: (Double) -> Void
    var skip: (Double) -> Void
    var nextChapter: () -> Void
    var previousChapter: () -> Void
    var setSpeed: (Float) -> Void
}

@MainActor
final class NowPlayingController {
    private var session: MPNowPlayingSession?
    private var commandCenter: MPRemoteCommandCenter?
    private var audiobook: Audiobook?
    private var chapters: [AudiobookChapter] = []
    private var artwork: MPMediaItemArtwork?
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var isPlaying = false
    private var speed: Float = 1
    private var currentChapterIndex = -1
    private var artworkTask: Task<Void, Never>?

    func configure(
        player: AVPlayer,
        audiobook: Audiobook,
        chapters: [AudiobookChapter],
        handlers: NowPlayingCommandHandlers
    ) {
        clear()
        self.audiobook = audiobook
        self.chapters = chapters
        duration = audiobook.durationSeconds ?? 0
        currentTime = 0
        currentChapterIndex = AudioChapterMath.currentIndex(time: 0, chapters: chapters)

        let session = MPNowPlayingSession(players: [player])
        self.session = session
        commandCenter = session.remoteCommandCenter
        configureCommands(commandCenter: session.remoteCommandCenter, handlers: handlers, hasChapters: chapters.count > 1)
        UIApplication.shared.beginReceivingRemoteControlEvents()

        publishNowPlayingInfo()
        updateArtwork(from: audiobook.coverUrl)
    }

    func updatePlaybackState(
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        speed: Float,
        currentChapterIndex: Int
    ) {
        self.currentTime = max(0, currentTime)
        self.duration = max(duration, self.duration)
        self.isPlaying = isPlaying
        self.speed = speed
        self.currentChapterIndex = currentChapterIndex
        publishNowPlayingInfo()
    }

    func updateArtwork(from urlString: String?) {
        artworkTask?.cancel()
        guard let urlString, let url = URL(string: urlString) else {
            artwork = nil
            publishNowPlayingInfo()
            return
        }

        artworkTask = Task { [weak self] in
            guard let image = await NowPlayingArtworkLoader.load(url: url) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self?.publishNowPlayingInfo()
            }
        }
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        if let commandCenter {
            removeCommandTargets(commandCenter)
        }
        commandCenter = nil
        session = nil
        audiobook = nil
        chapters = []
        artwork = nil
        currentChapterIndex = -1
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    static func makeMetadata(
        audiobook: Audiobook,
        chapters: [AudiobookChapter],
        artwork: MPMediaItemArtwork?,
        currentTime: Double,
        duration: Double,
        isPlaying: Bool,
        speed: Float,
        currentChapterIndex: Int
    ) -> [String: Any] {
        let clampedDuration = max(duration, audiobook.durationSeconds ?? 0)
        let clampedTime = max(0, min(currentTime, max(clampedDuration, currentTime)))
        let currentChapter = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : nil
        let artist = audiobook.author ?? audiobook.narrator ?? "Marxist Forum"

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: audiobook.title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: currentChapter?.title ?? "Audiobook",
            MPMediaItemPropertyGenre: audiobook.category ?? "Audiobook",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clampedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed)
        ]

        if clampedDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = clampedDuration
        }
        if !chapters.isEmpty {
            info[MPNowPlayingInfoPropertyChapterNumber] = max(currentChapterIndex + 1, 1)
            info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        return info
    }

    private func publishNowPlayingInfo() {
        guard let audiobook else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = Self.makeMetadata(
            audiobook: audiobook,
            chapters: chapters,
            artwork: artwork,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            speed: speed,
            currentChapterIndex: currentChapterIndex
        )
    }

    private func configureCommands(
        commandCenter: MPRemoteCommandCenter,
        handlers: NowPlayingCommandHandlers,
        hasChapters: Bool
    ) {
        removeCommandTargets(commandCenter)

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in handlers.play() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in handlers.toggle() }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            Task { @MainActor in handlers.skip(interval) }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            Task { @MainActor in handlers.skip(-interval) }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in handlers.seek(event.positionTime) }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = hasChapters
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.nextChapter() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = hasChapters
        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.previousChapter() }
            return .success
        }

        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 2.0]
        commandCenter.changePlaybackRateCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in handlers.setSpeed(event.playbackRate) }
            return .success
        }
    }

    private func removeCommandTargets(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackRateCommand.removeTarget(nil)
    }
}

private enum NowPlayingArtworkLoader {
    static func load(url: URL) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return nil }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            return await Task.detached(priority: .utility) {
                downsample(data: data, pixelSize: 640)
            }.value
        } catch {
            return nil
        }
    }

    private static func downsample(data: Data, pixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

@MainActor
@Observable
final class AudioPlayerModel {
    var current: Audiobook?
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var speed: Float = 1.0
    var expanded = false
    var sleepTimerEndDate: Date?
    var sleepTimerRemaining: TimeInterval = 0
    private var sortedChapters: [AudiobookChapter] = []

    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored private var audioSessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var lastResumePersistedTime: Double = -1

    init() {
        observeAudioSession()
    }

    var progress: Double {
        duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    var chapters: [AudiobookChapter] {
        sortedChapters
    }

    var currentChapterIndex: Int {
        AudioChapterMath.currentIndex(time: currentTime, chapters: chapters)
    }

    var currentChapter: AudiobookChapter? {
        let index = currentChapterIndex
        return index >= 0 && index < chapters.count ? chapters[index] : nil
    }

    var nextChapter: AudiobookChapter? {
        let index = currentChapterIndex + 1
        return index >= 0 && index < chapters.count ? chapters[index] : nil
    }

    var hasSleepTimer: Bool {
        sleepTimerEndDate != nil && sleepTimerRemaining > 0
    }

    func restoreLastSession() async {
        guard current == nil else { return }
        let snapshot = SystemIntegrationStore.loadSnapshot().currentAudiobook
        guard let snapshot else { return }
        do {
            guard let audiobook = try await AudiobookClient().fetchAudiobook(id: snapshot.id) else { return }
            speed = snapshot.speed
            load(audiobook, autoplay: false, present: false)
            seek(to: snapshot.currentTime)
            expanded = false
        } catch {
            print("Audio restore failed: \(error)")
        }
    }

    func load(_ audiobook: Audiobook, autoplay: Bool = true, present: Bool = true) {
        cleanup()
        configureAudioSession()
        current = audiobook
        sortedChapters = (audiobook.chapters ?? []).sorted { $0.startSeconds < $1.startSeconds }
        duration = audiobook.durationSeconds ?? 0
        currentTime = 0
        guard let url = URL(string: audiobook.audioUrl) else { return }
        let player = AVPlayer(playerItem: AVPlayerItem(url: url))
        self.player = player
        nowPlaying.configure(
            player: player,
            audiobook: audiobook,
            chapters: sortedChapters,
            handlers: commandHandlers
        )
        if autoplay {
            player.playImmediately(atRate: speed)
        }
        isPlaying = autoplay
        observeTime()
        expanded = present
        updateNowPlayingState()
    }

    func togglePlay() {
        guard player != nil else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let player else { return }
        configureAudioSession()
        player.playImmediately(atRate: speed)
        isPlaying = true
        updateNowPlayingState()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingState()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let targetSeconds = clampedPlaybackTime(seconds)
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentTime = targetSeconds
        player.seek(to: target)
        updateNowPlayingState()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func cycleSpeed() {
        let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        let index = speeds.firstIndex(of: speed) ?? 1
        setSpeed(speeds[(index + 1) % speeds.count])
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingState()
    }

    func jumpToChapter(_ index: Int) {
        guard index >= 0 && index < chapters.count else { return }
        seek(to: chapters[index].startSeconds)
    }

    func jumpToNextChapter() {
        guard !chapters.isEmpty else { return }
        jumpToChapter(min(currentChapterIndex + 1, chapters.count - 1))
    }

    func jumpToPreviousChapter() {
        guard !chapters.isEmpty else { return }
        let targetIndex: Int
        if let currentChapter, currentTime - currentChapter.startSeconds > 6 {
            targetIndex = currentChapterIndex
        } else {
            targetIndex = max(currentChapterIndex - 1, 0)
        }
        jumpToChapter(targetIndex)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        guard let minutes else {
            sleepTimerEndDate = nil
            sleepTimerRemaining = 0
            return
        }
        let remaining = TimeInterval(minutes * 60)
        sleepTimerEndDate = Date().addingTimeInterval(remaining)
        sleepTimerRemaining = remaining
        startSleepTimerTick()
    }

    private func observeTime() {
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let previousChapterIndex = self.currentChapterIndex
                let previousDuration = self.duration
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player?.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                if self.currentChapterIndex != previousChapterIndex || abs(self.duration - previousDuration) > 0.5 {
                    self.updateNowPlayingState()
                }
                if abs(self.currentTime - self.lastResumePersistedTime) >= 10 {
                    self.lastResumePersistedTime = self.currentTime
                    self.persistAudioSnapshot(reloadWidgets: false)
                }
            }
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session failed: \(error)")
        }
    }

    private func cleanup() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        sleepTimerTask?.cancel()
        sleepTimerEndDate = nil
        sleepTimerRemaining = 0
        player?.pause()
        player = nil
        timeObserver = nil
        sortedChapters = []
        isPlaying = false
        nowPlaying.clear()
    }

    private var commandHandlers: NowPlayingCommandHandlers {
        NowPlayingCommandHandlers(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlay() },
            seek: { [weak self] seconds in self?.seek(to: seconds) },
            skip: { [weak self] seconds in self?.skip(by: seconds) },
            nextChapter: { [weak self] in self?.jumpToNextChapter() },
            previousChapter: { [weak self] in self?.jumpToPreviousChapter() },
            setSpeed: { [weak self] speed in self?.setSpeed(speed) }
        )
    }

    private func updateNowPlayingState() {
        nowPlaying.updatePlaybackState(
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            speed: speed,
            currentChapterIndex: currentChapterIndex
        )
        persistAudioSnapshot(reloadWidgets: true)
    }

    private func persistAudioSnapshot(reloadWidgets: Bool) {
        SystemSnapshotPublisher.publishCurrentAudiobook(
            current,
            currentTime: currentTime,
            duration: duration,
            speed: speed,
            chapterTitle: currentChapter?.title,
            isPlaying: isPlaying,
            reloadWidgets: reloadWidgets
        )
    }

    private func clampedPlaybackTime(_ seconds: Double) -> Double {
        let upperBound = duration > 0 ? duration : max(current?.durationSeconds ?? 0, seconds)
        return max(0, min(seconds, upperBound))
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioSessionObservers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task { @MainActor in self?.handleInterruption(typeValue: typeValue, optionValue: optionValue) }
            }
        )
        audioSessionObservers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
                let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task { @MainActor in self?.handleRouteChange(reasonValue: reasonValue) }
            }
        )
    }

    private func handleInterruption(typeValue: UInt?, optionValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue ?? 0)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) {
                play()
            } else {
                updateNowPlayingState()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            updateNowPlayingState()
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    private func startSleepTimerTick() {
        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let endDate = self.sleepTimerEndDate else { return }
                let remaining = max(0, endDate.timeIntervalSinceNow)
                self.sleepTimerRemaining = remaining
                if remaining <= 0 {
                    self.pause()
                    self.sleepTimerEndDate = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

@MainActor
@Observable
final class RouterPath {
    var path: [Route] = []
    var presentedSheet: SheetDestination?

    func navigate(to route: Route) {
        path.append(route)
    }

    func reset() {
        path = []
        presentedSheet = nil
    }
}

@MainActor
@Observable
final class TabRouter {
    private var routers: [AppTab: RouterPath] = [:]

    func router(for tab: AppTab) -> RouterPath {
        if let router = routers[tab] {
            return router
        }
        let router = RouterPath()
        routers[tab] = router
        return router
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        let router = router(for: tab)
        return Binding(get: { router.path }, set: { router.path = $0 })
    }
}
