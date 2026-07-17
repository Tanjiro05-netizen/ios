import SwiftUI
import UIKit
import CoreSpotlight
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationCategoryRegistrar.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            await PushRegistrationService.shared.save(deviceToken: token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType,
           let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           let deepLink = AppDeepLink(searchableItemIdentifier: identifier) {
            Task { @MainActor in DeepLinkDispatcher.shared.open(deepLink) }
            return true
        }
        if let url = userActivity.webpageURL, let deepLink = AppDeepLink(url: url) {
            Task { @MainActor in DeepLinkDispatcher.shared.open(deepLink) }
            return true
        }
        return false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let deepLink = NotificationCategoryRegistrar.deepLink(from: userInfo, actionIdentifier: response.actionIdentifier) else {
            return
        }
        await MainActor.run {
            DeepLinkDispatcher.shared.open(deepLink)
        }
    }
}

@main
struct MarxistForumApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthStore()
    @State private var settings = SettingsStore()
    @State private var downloads = DownloadStore()
    @State private var audioDownloads = AudiobookDownloadStore()
    @State private var audio = AudioPlayerModel()
    @State private var readingActivity = ReadingActivityStore()
    @State private var deepLinks = DeepLinkDispatcher.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(settings)
                .environment(downloads)
                .environment(audioDownloads)
                .environment(audio)
                .environment(readingActivity)
                .environment(deepLinks)
                .preferredColorScheme(settings.settings.appearance.preferredColorScheme)
                .task {
                    downloads.restore()
                    audioDownloads.restore()
                    readingActivity.restore()
                    SystemSnapshotPublisher.publishDailyQuote(.today)
                    SystemSnapshotPublisher.publishContinueReading(readingActivity.continueReading.first)
                    await auth.restore()
                    await audio.restoreLastSession()
                }
                .onOpenURL { url in
                    deepLinks.open(url)
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ReadingActivityStore.self) private var readingActivity

    var body: some View {
        ZStack {
            ScreenBackground()
            if auth.isLoading {
                ProgressView("Opening archive")
                    .padding(24)
                    .glassSurface()
            } else if auth.isAuthenticated {
                AppView()
            } else {
                LoginScreen()
            }
        }
        .task(id: auth.userId) {
            guard let userId = auth.userId, let accessToken = auth.accessToken else { return }
            await readingActivity.synchronize(userId: userId, accessToken: accessToken)
        }
    }
}

struct AppView: View {
    @State private var selectedTab: AppTab = .library
    @State private var tabRouter = TabRouter()
    @State private var isGlobalSearchPresented = false
    @State private var globalSearchInitialQuery = ""
    @Environment(AudioPlayerModel.self) private var audio
    @Environment(ReadingActivityStore.self) private var readingActivity
    @Environment(DeepLinkDispatcher.self) private var deepLinks
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let router = tabRouter.router(for: selectedTab)
        @Bindable var bindableRouter = router

        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    iPadSidebar
                } detail: {
                    navigationStack(for: selectedTab)
                }
            } else if #available(iOS 26.0, *) {
                nativeTabShell(router: router)
            } else {
                navigationStack(for: selectedTab)
                    .safeAreaInset(edge: .bottom) {
                        if router.path.isEmpty {
                            VStack(spacing: 8) {
                                MiniPlayerBar()
                                LiquidTabBar(selectedTab: $selectedTab)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                            }
                            .animation(.snappy(duration: 0.22), value: audio.current?.id)
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if horizontalSizeClass == .regular, router.path.isEmpty {
                MiniPlayerBar()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }
        }
        .environment(router)
        .sheet(item: $bindableRouter.presentedSheet) { sheet in
            sheetDestination(sheet)
        }
        .sheet(isPresented: $isGlobalSearchPresented) {
            GlobalSearchScreen(initialQuery: globalSearchInitialQuery) { result in
                openSearchResult(result)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .tint(Brand.redSoft)
        .sheet(isPresented: Binding(get: { audio.expanded }, set: { audio.expanded = $0 })) {
                AudioPlayerScreen()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: deepLinks.pending) { _, link in
            guard let link else { return }
            handleDeepLink(link)
            deepLinks.consume()
        }
    }

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                navigationStack(for: .library)
            }
            Tab("Audio", systemImage: "headphones", value: AppTab.audiobooks) {
                navigationStack(for: .audiobooks)
            }
            Tab("Substack", systemImage: "newspaper", value: AppTab.substack) {
                navigationStack(for: .substack)
            }
            Tab("Forum", systemImage: "bubble.left.and.bubble.right", value: AppTab.forum) {
                navigationStack(for: .forum)
            }
            Tab("Alerts", systemImage: "bell", value: AppTab.notifications) {
                navigationStack(for: .notifications)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                navigationStack(for: .profile)
            }
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func nativeTabShell(router: RouterPath) -> some View {
        if router.path.isEmpty, audio.current != nil {
            nativeTabView
                .tabBarMinimizeBehavior(.never)
                .tabViewBottomAccessory {
                    MiniPlayerBar(isTabAccessory: true)
                        .animation(.snappy(duration: 0.22), value: audio.current?.id)
                }
        } else {
            nativeTabView
                .tabBarMinimizeBehavior(.never)
        }
    }

    private func navigationStack(for tab: AppTab) -> some View {
        let router = tabRouter.router(for: tab)
        return NavigationStack(path: tabRouter.binding(for: tab)) {
            tabContent(tab)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isGlobalSearchPresented = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .toolbarIconChrome()
                        }
                        .glassButtonStyle()
                        .accessibilityLabel("Global search")
                    }
                }
        }
        .environment(router)
    }

    private var iPadSidebar: some View {
        List {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Brand.redSoft : .primary)
                .accessibilityLabel(tab.title)
            }
        }
        .navigationTitle("MarxistInfo")
    }

    private func openSearchResult(_ result: GlobalSearchResult) {
        isGlobalSearchPresented = false
        switch result.target {
        case .book(let id):
            selectedTab = .library
            tabRouter.router(for: .library).navigate(to: .bookReader(id: id))
        case .audiobook(let audiobook):
            selectedTab = .audiobooks
            audio.load(audiobook)
        case .substack(let slug):
            selectedTab = .substack
            tabRouter.router(for: .substack).navigate(to: .substackArticle(slug: slug))
        case .thread(let id):
            selectedTab = .forum
            tabRouter.router(for: .forum).navigate(to: .threadDetail(id: id))
        }
    }

    private func handleDeepLink(_ link: AppDeepLink) {
        switch link {
        case .library:
            selectedTab = .library
            tabRouter.router(for: .library).reset()
        case .audiobooks:
            selectedTab = .audiobooks
            tabRouter.router(for: .audiobooks).reset()
        case .substack:
            selectedTab = .substack
            tabRouter.router(for: .substack).reset()
        case .forum:
            selectedTab = .forum
            tabRouter.router(for: .forum).reset()
        case .notifications:
            selectedTab = .notifications
            tabRouter.router(for: .notifications).reset()
        case .profile:
            selectedTab = .profile
            tabRouter.router(for: .profile).reset()
        case .book(let id):
            selectedTab = .library
            tabRouter.router(for: .library).navigate(to: .bookReader(id: id))
        case .audiobook(let id):
            selectedTab = .audiobooks
            Task { await openAudiobook(id: id) }
        case .substackArticle(let slug):
            selectedTab = .substack
            tabRouter.router(for: .substack).navigate(to: .substackArticle(slug: slug))
        case .thread(let id):
            selectedTab = .forum
            tabRouter.router(for: .forum).navigate(to: .threadDetail(id: id))
        case .userProfile(let id):
            selectedTab = .profile
            tabRouter.router(for: .profile).navigate(to: .userProfile(id: id))
        case .dailyQuote:
            selectedTab = .library
            tabRouter.router(for: .library).reset()
        case .continueReading:
            selectedTab = .library
            if let item = readingActivity.continueReading.first {
                tabRouter.router(for: .library).navigate(to: .bookReader(id: item.bookId))
            }
        case .quoteNotebook:
            selectedTab = .profile
            tabRouter.router(for: .profile).navigate(to: .quoteNotebook)
        case .support:
            selectedTab = .profile
            tabRouter.router(for: .profile).navigate(to: .support)
        case .search(let query):
            globalSearchInitialQuery = query
            isGlobalSearchPresented = true
        }
    }

    private func openAudiobook(id: String) async {
        do {
            if let audiobook = try await AudiobookClient().fetchAudiobook(id: id) {
                audio.load(audiobook)
            } else {
                audio.expanded = true
            }
        } catch {
            if let cached = AudiobookOfflineCache.entries().first(where: { $0.audiobookId == id })?.audiobook {
                audio.load(cached)
            } else {
                audio.expanded = true
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .library: LibraryScreen()
        case .audiobooks: AudiobooksScreen()
        case .substack: SubstackScreen()
        case .forum: ForumScreen()
        case .notifications: NotificationsScreen()
        case .profile: ProfileScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .settings:
            SettingsScreen()
        case .bookReader(let id):
            ReaderScreen(bookId: id)
        case .substackArticle(let slug):
            SubstackArticleScreen(slug: slug)
        case .threadDetail(let id):
            ThreadDetailScreen(threadId: id)
        case .userProfile(let id):
            UserProfileScreen(userId: id)
        case .quoteNotebook:
            QuoteNotebookScreen()
        case .support:
            SupportScreen()
        case .changePassword:
            ChangePasswordScreen()
        case .emailPreferences:
            EmailPreferencesScreen()
        case .legal(let kind):
            LegalScreen(kind: kind)
        }
    }

    @ViewBuilder
    private func sheetDestination(_ sheet: SheetDestination) -> some View {
        NavigationStack {
            switch sheet {
            case .createThread(let boardSlug):
                CreateThreadScreen(boardSlug: boardSlug)
            case .audioPlayer:
                AudioPlayerScreen()
            case .editProfile:
                EditProfileScreen()
            }
        }
    }
}
