import AVKit
import SwiftUI
import WebKit

private enum ScreenSpacing {
    static let horizontal: CGFloat = 16
    static let row: CGFloat = 12
    static let tabBarClearance: CGFloat = 92
    static let tabBarWithMiniPlayerClearance: CGFloat = 164
}

private struct ScrollBottomClearance: View {
    var height: CGFloat = ScreenSpacing.tabBarClearance

    var body: some View {
        Color.clear
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case night
    case sepia
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: "Night"
        case .sepia: "Sepia"
        case .paper: "Paper"
        }
    }

    var systemImage: String {
        switch self {
        case .night: "moon.fill"
        case .sepia: "sun.haze.fill"
        case .paper: "doc.text.fill"
        }
    }

    var backgroundHex: String {
        switch self {
        case .night: "#050505"
        case .sepia: "#17110d"
        case .paper: "#f3eee4"
        }
    }

    var textHex: String {
        switch self {
        case .night: "#ded8d2"
        case .sepia: "#ead8c2"
        case .paper: "#211a17"
        }
    }

    var headingHex: String {
        switch self {
        case .night: "#fff7f2"
        case .sepia: "#fff0dc"
        case .paper: "#130f0d"
        }
    }

    var linkHex: String {
        switch self {
        case .night: "#ffb4a8"
        case .sepia: "#ffb889"
        case .paper: "#9f2525"
        }
    }

    var scheme: String {
        self == .paper ? "light" : "dark"
    }
}

struct LoginScreen: View {
    @Environment(AuthStore.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var inviteCode = ""
    @State private var isCreatingAccount = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Brand.red)
                    Text("Marxist Forum")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                    Text("A native iOS archive for reading, listening, and discussion.")
                        .font(.callout)
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .loginTextFieldChrome()
                    SecureField("Password", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .loginTextFieldChrome()
                    if isCreatingAccount {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .loginTextFieldChrome()
                        TextField("Invite code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .loginTextFieldChrome()
                    }
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Brand.redSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let message = auth.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        Task {
                            if isCreatingAccount {
                                await auth.signUp(email: email, password: password, username: username, inviteCode: inviteCode)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                            Text(isCreatingAccount ? "Create Account" : "Sign In")
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LoginPrimaryButtonStyle(isEnabled: canSubmit))
                    .disabled(!canSubmit)
                    .padding(.top, 2)

                    if !isCreatingAccount {
                        AppleSignInButton()
                    }

                    HStack(spacing: 12) {
                        Button(isCreatingAccount ? "Sign in instead" : "Create account") {
                            withAnimation(.snappy(duration: 0.18)) {
                                isCreatingAccount.toggle()
                            }
                        }
                        .buttonStyle(LoginLinkButtonStyle())

                        Spacer(minLength: 8)

                        Button("Browse as Guest") {
                            auth.browseAsGuest()
                        }
                        .buttonStyle(LoginLinkButtonStyle())
                    }
                    .padding(.top, 2)
                }
                .textFieldStyle(.plain)
                .padding(16)
                .loginPanelChrome()
            }
            .padding(.horizontal, 28)
            .padding(.top, 46)
            .padding(.bottom, 28)
            .frame(maxWidth: 440, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ScreenBackground())
    }
}

private extension View {
    func loginTextFieldChrome() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(Brand.controlFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Brand.separator.opacity(0.72), lineWidth: 1)
            }
    }

    func loginPanelChrome() -> some View {
        self
            .glassSurface(cornerRadius: 14)
    }
}

private struct LoginPrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Brand.onAccent : .secondary)
            .frame(height: 40)
            .background(
                isEnabled ? Brand.red.opacity(configuration.isPressed ? 0.78 : 1) : Brand.controlFill,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Brand.separator.opacity(0.72), lineWidth: 1)
            }
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

private struct LoginLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .foregroundStyle(configuration.isPressed ? Brand.redSoft : .secondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

struct LibraryScreen: View {
    @Environment(RouterPath.self) private var router
    @Environment(DownloadStore.self) private var downloads
    @Environment(AudioPlayerModel.self) private var audio
    @Environment(ReadingActivityStore.self) private var readingActivity
    private let client = LibraryClient()

    @State private var books: [Book] = []
    @State private var categories: [String] = []
    @State private var scope: LibraryScope = .official
    @State private var selectedCategory: String?
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var didLoadInitial = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                DailyQuoteCard(
                    quote: .today,
                    isSaved: readingActivity.quoteExists(text: DailyQuote.today.text, sourceTitle: DailyQuote.today.source),
                    onSave: {
                        _ = readingActivity.saveQuote(
                            text: DailyQuote.today.text,
                            sourceTitle: DailyQuote.today.source,
                            sourceDetail: DailyQuote.today.detail
                        )
                        Task {
                            await SearchIndexService.shared.indexQuotes(readingActivity.quotes)
                        }
                    }
                )
                .padding(.horizontal, ScreenSpacing.horizontal)

                ContinueRail(
                    readingItems: Array(readingActivity.continueReading.prefix(6)),
                    currentAudio: audio.current,
                    onOpenBook: { item in
                        router.navigate(to: .bookReader(id: item.bookId))
                    },
                    onOpenAudio: {
                        audio.expanded = true
                    }
                )
                .padding(.horizontal, ScreenSpacing.horizontal)

                TopFilterBar {
                    LibraryScopeControl(scope: $scope)
                }
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            categoryButton(nil, label: "All")
                            ForEach(categories, id: \.self) { category in
                                categoryButton(category, label: category)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                if isLoading && books.isEmpty {
                    ProgressView("Loading library")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if books.isEmpty {
                    EmptyPanel(systemImage: "books.vertical", title: "No books found", message: errorMessage ?? "Try a different search or filter.")
                        .padding(.horizontal)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(books) { book in
                            Button {
                                router.navigate(to: .bookReader(id: book.id))
                            } label: {
                                BookCard(book: book, isDownloaded: downloads.cached(bookId: book.id) != nil)
                            }
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.965))
                        }
                    }
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    ScrollBottomClearance()
                }
            }
        }
        .navigationTitle("Library")
        .animation(.snappy(duration: 0.24), value: readingActivity.continueReading.map(\.id))
        .animation(.snappy(duration: 0.24), value: audio.current?.id)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.navigate(to: .settings)
                } label: {
                    Image(systemName: "gearshape")
                        .toolbarIconChrome()
                }
                .glassButtonStyle()
            }
        }
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search books")
        .task {
            await loadInitial()
        }
        .task(id: "\(didLoadInitial)-\(searchQuery)") {
            guard didLoadInitial, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await loadBooks()
        }
        .onChange(of: scope) { _, _ in Task { await loadBooks() } }
        .onChange(of: selectedCategory) { _, _ in Task { await loadBooks() } }
        .background(ScreenBackground())
    }

    private func categoryButton(_ category: String?, label: String) -> some View {
        Button(label) {
            selectedCategory = category
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(selectedCategory == category ? Brand.onAccent : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selectedCategory == category ? Brand.red : Brand.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func loadInitial() async {
        guard !didLoadInitial else { return }
        async let categoriesRequest = try? client.fetchCategories()
        await loadBooks()
        didLoadInitial = true
        if let loadedCategories = await categoriesRequest {
            categories = loadedCategories
        }
    }

    private func loadBooks() async {
        isLoading = true
        do {
            let loadedBooks = try await client.fetchBooks(scope: scope, category: selectedCategory, search: searchQuery)
            books = loadedBooks
            errorMessage = nil
            isLoading = false
            Task { await SearchIndexService.shared.indexBooks(loadedBooks) }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private struct LibraryScopeControl: View {
    @Binding var scope: LibraryScope

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LibraryScope.allCases) { item in
                Button {
                    scope = item
                } label: {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(scope == item ? Brand.onAccent : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(scope == item ? Brand.red : Brand.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DailyQuoteCard: View {
    let quote: DailyQuote
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "quote.bubble")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                    .frame(width: 22, height: 22)
                    .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                Spacer()
                Button(action: onSave) {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "quote.bubble")
                        .font(.caption.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(isSaved ? .secondary : Brand.onAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(isSaved ? Brand.subtleFill : Brand.red, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                .disabled(isSaved)
                .accessibilityLabel(isSaved ? "Quote saved" : "Save daily quote")
            }

            Text(quote.text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(quote.source) · \(quote.detail)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassSurface(cornerRadius: 14, interactive: true)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct ContinueRail: View {
    let readingItems: [ContinueReadingItem]
    let currentAudio: Audiobook?
    let onOpenBook: (ContinueReadingItem) -> Void
    let onOpenAudio: () -> Void

    private var hasItems: Bool {
        !readingItems.isEmpty || currentAudio != nil
    }

    var body: some View {
        if hasItems {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue")
                    .font(.headline.weight(.bold))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(readingItems) { item in
                            Button {
                                onOpenBook(item)
                            } label: {
                                ContinueReadingCard(item: item)
                            }
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.96))
                        }

                        if let currentAudio {
                            Button(action: onOpenAudio) {
                                ContinueListeningCard(audiobook: currentAudio)
                            }
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.96))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct ContinueReadingCard: View {
    let item: ContinueReadingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                Text("Reading")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(item.progress * 100))%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.chapterTitle ?? item.author ?? "Saved place")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ReaderProgressLine(progress: item.progress)
        }
        .frame(width: 206, alignment: .leading)
        .padding(12)
        .glassSurface(cornerRadius: 12, interactive: true)
    }
}

struct ContinueListeningCard: View {
    let audiobook: Audiobook
    @Environment(AudioPlayerModel.self) private var audio

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageCover(urlString: audiobook.coverUrl, systemImage: "headphones", maxPixelSize: 240)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.redSoft)
                    Text("Listening")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(audiobook.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                MiniProgressLine(progress: audio.progress)
            }
        }
        .frame(width: 238, alignment: .leading)
        .padding(10)
        .glassSurface(cornerRadius: 12, interactive: true)
    }
}

struct BookCard: View {
    let book: Book
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImageCover(urlString: book.coverImageUrl, systemImage: "book.closed", maxPixelSize: 480)
                .aspectRatio(0.68, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(8)
                    }
                }
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            Text(book.author ?? "Unknown Author")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                if let category = book.category {
                    Text(category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.redSoft)
                }
                Spacer()
                if let year = book.year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .glassSurface(cornerRadius: 12, interactive: true)
    }
}

struct ReaderScreen: View {
    let bookId: String

    @Environment(DownloadStore.self) private var downloads
    @Environment(ReadingActivityStore.self) private var readingActivity
    private let client = LibraryClient()
    private let readerDefaults = UserDefaults.standard

    @State private var book: Book?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shareTarget: ShareTarget?
    @State private var publication: EpubPublication?
    @State private var currentChapterIndex = 0
    @State private var isPreparingEpub = false
    @State private var readerStatusMessage: String?
    @State private var isShowingTOC = false
    @State private var isShowingReaderSettings = false
    @State private var selectedReaderText = ""
    @AppStorage("ios.reader.fontSize") private var fontSize: Double = 18
    @AppStorage("ios.reader.theme") private var readerThemeRawValue = ReaderTheme.night.rawValue

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let currentChapter {
                    EpubChapterWebView(
                        chapterURL: currentChapter.fileURL,
                        fontSize: fontSize,
                        theme: readerTheme,
                        selectedText: $selectedReaderText
                    )
                } else {
                    ReaderWebView(html: readerHTML)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                if let book {
                    readerToolbar(book: book)
                }
            }
        }
        .navigationTitle(book?.title ?? "Reader")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBook() }
        .sheet(item: $shareTarget) { target in
            ShareSheet(items: [target.url])
        }
        .sheet(isPresented: $isShowingTOC) {
            if let publication {
                ReaderTableOfContentsSheet(
                    publication: publication,
                    currentChapterIndex: currentChapterIndex,
                    onSelect: { index in
                        currentChapterIndex = index
                        saveReaderProgress()
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingReaderSettings) {
            ReaderSettingsSheet(fontSize: $fontSize, theme: readerThemeBinding)
        }
        .onChange(of: currentChapterIndex) { _, _ in
            selectedReaderText = ""
            saveReaderProgress()
        }
    }

    private var currentChapter: EpubChapter? {
        guard let publication,
              publication.chapters.indices.contains(currentChapterIndex) else {
            return nil
        }
        return publication.chapters[currentChapterIndex]
    }

    private var readerHTML: String {
        if isLoading {
            return ReaderHTML.page(title: "Loading", subtitle: "Unpacking the text...", body: "")
        }
        if let errorMessage {
            return ReaderHTML.page(title: "Reader unavailable", subtitle: errorMessage, body: book?.description?.strippedMarkdown ?? "")
        }
        guard let book else {
            return ReaderHTML.page(title: "Book unavailable", subtitle: errorMessage ?? "The selected title could not be loaded.", body: "")
        }
        let body = (book.description ?? "This title is ready for native reading. Save the EPUB for offline use, or open the PDF when available.").strippedMarkdown
        let subtitle = isPreparingEpub
            ? (readerStatusMessage ?? "Preparing EPUB…")
            : (book.author ?? "Unknown Author")
        return ReaderHTML.page(title: book.title, subtitle: subtitle, body: body, fontSize: fontSize)
    }

    private var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRawValue) ?? .night
    }

    private var readerThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { readerTheme },
            set: { readerThemeRawValue = $0.rawValue }
        )
    }

    private var readerProgress: Double {
        guard let publication, !publication.chapters.isEmpty else { return 0 }
        return Double(currentChapterIndex + 1) / Double(publication.chapters.count)
    }

    @ViewBuilder
    private func readerToolbar(book: Book) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let publication, let currentChapter {
                HStack(spacing: 12) {
                    Button {
                        currentChapterIndex = max(currentChapterIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .glassButtonStyle()
                    .disabled(currentChapterIndex == 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chapter \(currentChapterIndex + 1) of \(publication.chapters.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(currentChapter.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        currentChapterIndex = min(currentChapterIndex + 1, publication.chapters.count - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .glassButtonStyle()
                    .disabled(currentChapterIndex >= publication.chapters.count - 1)
                }
                ReaderProgressLine(progress: readerProgress)
            } else if let readerStatusMessage {
                Label(readerStatusMessage, systemImage: isPreparingEpub ? "book.pages" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPreparingEpub ? .secondary : Brand.redSoft)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await prepareEpub(book, shareWhenReady: true) }
                } label: {
                    Image(systemName: downloads.cached(bookId: book.id) == nil ? "arrow.down.circle" : "checkmark.circle.fill")
                        .frame(width: 30, height: 30)
                }
                .glassButtonStyle()
                .disabled(book.epubFilename == nil || downloads.activeDownloadId == book.id || isPreparingEpub)
                .accessibilityLabel(downloads.cached(bookId: book.id) == nil ? "Save EPUB" : "EPUB saved")

                if let pdfFilename = book.pdfFilename {
                    Button {
                        shareTarget = ShareTarget(url: client.pdfURL(filename: pdfFilename))
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 30, height: 30)
                    }
                    .glassButtonStyle()
                    .accessibilityLabel("Share PDF")
                }

                if publication != nil {
                    Button {
                        isShowingTOC = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .frame(width: 30, height: 30)
                    }
                    .glassButtonStyle()
                    .accessibilityLabel("Table of contents")
                }

                Button {
                    saveReaderQuote()
                } label: {
                    Image(systemName: selectedReaderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bookmark" : "quote.bubble.fill")
                        .frame(width: 30, height: 30)
                }
                .glassButtonStyle()
                .accessibilityLabel(selectedReaderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Save reading place to notebook" : "Save selected quote")

                Button {
                    isShowingReaderSettings = true
                } label: {
                    Image(systemName: "textformat")
                        .frame(width: 30, height: 30)
                }
                .glassButtonStyle()
                .accessibilityLabel("Reader settings")

                Spacer(minLength: 8)

                Text(readerTheme.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .glassSurface(cornerRadius: 14, interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func loadBook() async {
        isLoading = true
        publication = nil
        readerStatusMessage = nil
        do {
            guard let fetchedBook = try await client.fetchBook(id: bookId) else {
                book = nil
                errorMessage = "The selected title could not be loaded."
                isLoading = false
                return
            }
            book = fetchedBook
            errorMessage = nil
            isLoading = false
            // Show the book immediately. EPUB download/unpacking is optional
            // enrichment and should never hold the first reader frame hostage.
            Task { await prepareEpub(fetchedBook) }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func prepareEpub(_ book: Book, shareWhenReady: Bool = false) async {
        guard let filename = book.epubFilename else {
            readerStatusMessage = "No EPUB file is available for this title."
            return
        }

        isPreparingEpub = true
        readerStatusMessage = downloads.cached(bookId: book.id) == nil ? "Downloading EPUB..." : "Opening saved EPUB..."
        defer { isPreparingEpub = false }

        guard let entry = await downloads.cache(book: book, remoteURL: client.epubURL(filename: filename)) else {
            errorMessage = downloads.errorMessage ?? "The EPUB could not be downloaded."
            readerStatusMessage = nil
            return
        }

        do {
            let localPath = entry.localPath
            let bookId = book.id
            let title = book.title
            readerStatusMessage = "Opening EPUB..."
            let prepared = try await Task.detached(priority: .userInitiated) {
                try await EpubArchiveParser.prepare(
                    bookId: bookId,
                    title: title,
                    epubURL: URL(fileURLWithPath: localPath)
                )
            }.value
            publication = prepared
            currentChapterIndex = min(savedChapterIndex(for: book.id), max(prepared.chapters.count - 1, 0))
            saveReaderProgress()
            readerStatusMessage = nil
            errorMessage = nil
            if shareWhenReady {
                shareTarget = ShareTarget(url: URL(fileURLWithPath: entry.localPath))
            }
        } catch {
            publication = nil
            errorMessage = error.localizedDescription
            readerStatusMessage = nil
        }
    }

    private func saveReaderProgress() {
        guard let book else { return }
        readerDefaults.set(currentChapterIndex, forKey: readerProgressKey(bookId: book.id))
        if let publication {
            readingActivity.upsertProgress(
                book: book,
                chapterTitle: currentChapter?.title,
                chapterIndex: currentChapterIndex,
                chapterCount: publication.chapters.count
            )
            SystemSnapshotPublisher.publishContinueReading(readingActivity.continueReading.first)
            Task {
                await SearchIndexService.shared.indexContinueReading(readingActivity.continueReading)
            }
        }
    }

    private func saveReaderQuote() {
        guard let book else { return }
        let cleanSelection = selectedReaderText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = cleanSelection.isEmpty ? (currentChapter?.title ?? book.title) : cleanSelection
        let chapterDetail: String?
        if let publication {
            let chapterLabel = "Chapter \(currentChapterIndex + 1) of \(publication.chapters.count)"
            if let title = currentChapter?.title {
                chapterDetail = "\(chapterLabel) · \(title)"
            } else {
                chapterDetail = chapterLabel
            }
        } else {
            chapterDetail = book.author
        }
        _ = readingActivity.saveQuote(
            text: text,
            sourceTitle: book.title,
            sourceDetail: chapterDetail,
            routeBookId: book.id
        )
        Task {
            await SearchIndexService.shared.indexQuotes(readingActivity.quotes)
        }
        selectedReaderText = ""
    }

    private func savedChapterIndex(for bookId: String) -> Int {
        readerDefaults.integer(forKey: readerProgressKey(bookId: bookId))
    }

    private func readerProgressKey(bookId: String) -> String {
        "ios.reader.chapter.\(bookId)"
    }
}

struct ReaderHTML {
    static func page(title: String, subtitle: String, body: String, fontSize: Double = 18) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { background:#050505; color:#ded8d2; font-family: -apple-system, Georgia, serif; padding: 72px 24px 128px; line-height:1.65; font-size:\(fontSize)px; }
        h1 { color:#fff; font-family: Georgia, serif; font-size: 32px; line-height:1.1; }
        .sub { color:#ac8884; margin-bottom: 36px; }
        p { max-width: 720px; }
        </style>
        </head>
        <body><h1>\(title)</h1><div class="sub">\(subtitle)</div><p>\(body)</p></body>
        </html>
        """
    }
}

struct ReaderWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loadedHTML: String?
    }
}

struct EpubChapterWebView: UIViewRepresentable {
    let chapterURL: URL
    let fontSize: Double
    let theme: ReaderTheme
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let userContentController = WKUserContentController()
        let selectionScript = """
        (function() {
          var lastSelection = "";
          function postSelection() {
            var selection = "";
            if (window.getSelection) {
              selection = String(window.getSelection()).trim();
            }
            if (selection !== lastSelection) {
              lastSelection = selection;
              window.webkit.messageHandlers.selectedReaderText.postMessage(selection);
            }
          }
          document.addEventListener("selectionchange", postSelection);
          document.addEventListener("mouseup", postSelection);
          document.addEventListener("keyup", postSelection);
          document.addEventListener("touchend", postSelection);
        })();
        """
        userContentController.addUserScript(WKUserScript(source: selectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        userContentController.add(context.coordinator, name: "selectedReaderText")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedChapterURL != chapterURL
                || context.coordinator.loadedFontSize != fontSize
                || context.coordinator.loadedTheme != theme else {
            return
        }

        context.coordinator.loadedChapterURL = chapterURL
        context.coordinator.loadedFontSize = fontSize
        context.coordinator.loadedTheme = theme

        let html = (try? String(contentsOf: chapterURL, encoding: .utf8))
            ?? (try? String(contentsOf: chapterURL, encoding: .isoLatin1))
            ?? ReaderHTML.page(title: "Chapter unavailable", subtitle: chapterURL.lastPathComponent, body: "")
        uiView.loadHTMLString(injectReaderCSS(into: html, fontSize: fontSize, theme: theme), baseURL: chapterURL.deletingLastPathComponent())
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "selectedReaderText")
    }

    private func injectReaderCSS(into html: String, fontSize: Double, theme: ReaderTheme) -> String {
        let css = """
        <style>
        :root { color-scheme: \(theme.scheme); }
        html { background: \(theme.backgroundHex) !important; }
        body {
          background: \(theme.backgroundHex) !important;
          color: \(theme.textHex) !important;
          font-family: -apple-system, BlinkMacSystemFont, Georgia, serif !important;
          font-size: \(fontSize)px !important;
          line-height: 1.68 !important;
          margin: 0 !important;
          padding: 74px 24px 150px !important;
          overflow-wrap: break-word !important;
          -webkit-text-size-adjust: 100%;
        }
        body * { max-width: 100% !important; }
        p, li, blockquote { color: \(theme.textHex) !important; }
        h1, h2, h3, h4, h5, h6 {
          color: \(theme.headingHex) !important;
          font-family: Georgia, serif !important;
          line-height: 1.18 !important;
          margin: 1.15em 0 0.45em !important;
        }
        p { margin: 0 0 1em !important; }
        a { color: \(theme.linkHex) !important; }
        ::selection { background: rgba(200, 30, 30, 0.34) !important; color: \(theme.headingHex) !important; }
        img, svg, video { height: auto !important; max-width: 100% !important; }
        table { display: block !important; overflow-x: auto !important; width: 100% !important; }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.16); margin: 2em 0; }
        </style>
        """

        if let range = html.range(of: "</head>", options: [.caseInsensitive]) {
            var output = html
            output.insert(contentsOf: css, at: range.lowerBound)
            return output
        }

        return """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1">\(css)</head>
        <body>\(html)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedChapterURL: URL?
        var loadedFontSize: Double?
        var loadedTheme: ReaderTheme?
        private var selectedText: Binding<String>

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "selectedReaderText",
                  let text = message.body as? String else {
                return
            }
            selectedText.wrappedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct ReaderProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Brand.controlFill)
                Capsule()
                    .fill(Brand.redSoft.opacity(0.9))
                    .frame(width: proxy.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

struct ReaderTableOfContentsSheet: View {
    let publication: EpubPublication
    let currentChapterIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(publication.chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        onSelect(index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(index == currentChapterIndex ? Brand.redSoft : .secondary)
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if index == currentChapterIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Brand.redSoft)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ReaderSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var theme: ReaderTheme

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme")
                        .font(.headline)
                    HStack(spacing: 10) {
                        ForEach(ReaderTheme.allCases) { option in
                            Button {
                                theme = option
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: option.systemImage)
                                        .font(.headline)
                                    Text(option.title)
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(theme == option ? Brand.onAccent : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(theme == option ? Brand.red : Brand.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Text Size")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 14...28, step: 1)
                        .tint(Brand.redSoft)
                    HStack {
                        Text("A")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("A")
                            .font(.system(size: 28, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(ScreenBackground())
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.redSoft)
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ShareTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct GlobalSearchScreen: View {
    let onOpen: (GlobalSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    private let client = GlobalSearchClient()

    @State private var query = ""
    @State private var results: [GlobalSearchResult] = []
    @State private var isSearching = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(initialQuery: String = "", onOpen: @escaping (GlobalSearchResult) -> Void) {
        self.onOpen = onOpen
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                searchField
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    .padding(.top, 8)

                content
            }
            .background(ScreenBackground())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.redSoft)
                        .buttonStyle(.plain)
                }
            }
            .task {
                isSearchFocused = true
            }
            .task(id: query) {
                await search()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(.secondary)
            TextField("Search archive", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(cornerRadius: 12, interactive: true)
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.count < 2 {
            GlobalSearchLanding()
                .padding(.horizontal, ScreenSpacing.horizontal)
                .padding(.top, 38)
        } else if isSearching && results.isEmpty {
            ProgressView("Searching")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
        } else if results.isEmpty {
            EmptyPanel(systemImage: "magnifyingglass", title: "No results", message: "Nothing matched \"\(trimmedQuery)\".")
                .padding(.horizontal, ScreenSpacing.horizontal)
                .padding(.top, 38)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(GlobalSearchSection.allCases) { section in
                        let rows = results.filter { $0.section == section }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 4)
                                LazyVStack(spacing: 10) {
                                    ForEach(rows) { result in
                                        Button {
                                            dismiss()
                                            onOpen(result)
                                    } label: {
                                        GlobalSearchResultRow(result: result)
                                    }
                                    .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
                                }
                            }
                        }
                        }
                    }
                }
                .padding(.horizontal, ScreenSpacing.horizontal)
                .padding(.bottom, 28)
            }
            .overlay(alignment: .top) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func search() async {
        let trimmed = trimmedQuery
        guard trimmed.count >= 2 else {
            isSearching = false
            results = []
            return
        }

        isSearching = true
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        let found = await client.search(query: trimmed)
        guard !Task.isCancelled else { return }
        withAnimation(.snappy(duration: 0.18)) {
            results = found
            isSearching = false
        }
    }
}

struct GlobalSearchLanding: View {
    private var sections: [GlobalSearchSection] {
        AppFeatureFlags.forumEnabled ? GlobalSearchSection.allCases : [.books, .audiobooks, .substack]
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Brand.redSoft)
            Text("Search archive")
                .font(.headline.weight(.bold))
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassSurface(cornerRadius: 14)
    }
}

struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageCover(urlString: result.imageURL, systemImage: result.systemImage, maxPixelSize: 360)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail = result.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Brand.separator.opacity(0.64), lineWidth: 1)
        }
    }
}

struct SubstackScreen: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.openURL) private var openURL
    private let client = SubstackClient()

    @State private var source = SubstackSource.fallback
    @State private var posts: [SubstackArticle] = []
    @State private var searchQuery = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    private var filteredPosts: [SubstackArticle] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return posts }
        return posts.filter { post in
            [
                post.title,
                post.excerpt ?? "",
                post.author ?? "",
                post.categories.joined(separator: " ")
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let visiblePosts = filteredPosts

        ScrollView {
            LazyVStack(alignment: .leading, spacing: ScreenSpacing.row) {
                SubstackSourceHeader(source: source, count: visiblePosts.count, total: posts.count)
                    .padding(.horizontal, ScreenSpacing.horizontal)

                if let noticeMessage, !noticeMessage.isEmpty {
                    Label(noticeMessage, systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ScreenSpacing.horizontal)
                }

                if isLoading && posts.isEmpty {
                    ProgressView("Loading Substack")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if visiblePosts.isEmpty {
                    EmptyPanel(
                        systemImage: "newspaper",
                        title: "No articles found",
                        message: errorMessage ?? "Try a different search."
                    )
                    .padding(.horizontal, ScreenSpacing.horizontal)
                } else {
                    LazyVStack(spacing: ScreenSpacing.row) {
                        ForEach(visiblePosts) { post in
                            Button {
                                router.navigate(to: .substackArticle(slug: post.slug))
                            } label: {
                                SubstackArticleRow(post: post)
                            }
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.97))
                            .accessibilityHint("Opens the article reader")
                        }
                    }
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    ScrollBottomClearance()
                }
            }
            .padding(.top, 10)
        }
        .navigationTitle("Substack")
        .animation(.snappy(duration: 0.24), value: visiblePosts.map(\.id))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = URL(string: source.url) {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .toolbarIconChrome()
                }
                .glassButtonStyle()
            }
        }
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search articles")
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
        .background(ScreenBackground())
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        let result = await client.loadPosts(forceRefresh: forceRefresh)
        source = result.source
        posts = result.posts
        noticeMessage = result.posts.isEmpty ? nil : result.feedError
        errorMessage = result.posts.isEmpty ? (result.feedError ?? result.archiveError) : nil
        isLoading = false
        Task {
            SystemSnapshotPublisher.publishLatestSubstack(result.posts)
            await SearchIndexService.shared.indexSubstack(result.posts)
        }
    }
}

struct SubstackSourceHeader: View {
    let source: SubstackSource
    let count: Int
    let total: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "newspaper")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.redSoft)
                .frame(width: 34, height: 34)
                .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(total == count ? "\(total) articles" : "\(count) of \(total) articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .glassSurface(cornerRadius: 14, interactive: true)
    }
}

struct SubstackArticleRow: View {
    let post: SubstackArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImageCover(urlString: post.imageUrl, systemImage: "newspaper", maxPixelSize: 360)
                .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(post.primaryCategory)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Brand.redSoft)
                    Text(post.displayDate.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(post.title)
                    .font(.headline)
                    .lineLimit(2)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(post.author ?? AppConstants.substackAuthorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SubstackArticleScreen: View {
    let slug: String

    @Environment(\.openURL) private var openURL
    private let client = SubstackClient()

    @State private var source = SubstackSource.fallback
    @State private var post: SubstackArticle?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shareTarget: ShareTarget?

    var body: some View {
        ZStack(alignment: .bottom) {
            ReaderWebView(html: articleHTML)
                .ignoresSafeArea(edges: .bottom)

            if let post {
                HStack {
                    Button {
                        if let url = URL(string: post.url) {
                            shareTarget = ShareTarget(url: url)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        if let url = URL(string: post.url) {
                            openURL(url)
                        }
                    } label: {
                        Label("Substack", systemImage: "safari")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Brand.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .glassSurface(cornerRadius: 14, interactive: true)
                .padding()
            }
        }
        .navigationTitle(post?.title ?? "Substack")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $shareTarget) { target in
            ShareSheet(items: [target.url])
        }
    }

    private var articleHTML: String {
        if isLoading {
            return SubstackHTML.page(title: "Loading", subtitle: "Opening the article...", body: "")
        }
        guard let post else {
            return SubstackHTML.page(title: "Article unavailable", subtitle: errorMessage ?? "This Substack article could not be loaded.", body: "")
        }
        return SubstackHTML.page(post: post, source: source)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let result = await client.loadPosts()
        source = result.source
        post = result.posts.first { $0.slug == slug }
        if post == nil {
            errorMessage = "This Substack article is not in the archive yet."
        }
    }
}

enum SubstackHTML {
    static func page(post: SubstackArticle, source: SubstackSource) -> String {
        let body = SubstackArticle.cleanContentHTML(post.contentHtml ?? "")
        let fallbackBody = "<p>\((post.excerpt ?? "This article preview is available in the archive.").htmlEscaped)</p>"
        let image = post.imageUrl.map { #"<img class="hero" src="\#($0.htmlEscaped)" alt="">"# } ?? ""
        let author = (post.author ?? source.authorName ?? AppConstants.substackAuthorName).htmlEscaped
        let subtitle = "\(post.primaryCategory) · \(post.displayDate) · \(author)"
        return page(
            title: post.title,
            subtitle: subtitle,
            body: image + (body.isEmpty ? fallbackBody : body)
        )
    }

    static func page(title: String, subtitle: String, body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: dark; }
        body { margin:0; background:#050505; color:#ded8d2; font-family:-apple-system, BlinkMacSystemFont, "SF Pro Text", Georgia, serif; }
        article { max-width:760px; margin:0 auto; padding:72px 22px 128px; line-height:1.68; font-size:18px; }
        h1 { color:#fff; font-family:Georgia, "Times New Roman", serif; font-size:36px; line-height:1.08; letter-spacing:0; margin:0 0 12px; }
        h2, h3 { color:#fff; line-height:1.2; margin-top:32px; }
        .sub { color:#ac8884; margin-bottom:28px; font-size:14px; font-weight:600; letter-spacing:0; font-family:-apple-system, "Apple Symbols", sans-serif; }
        p { margin:0 0 18px; }
        a { color:#ffb4a8; }
        blockquote { margin:24px 0; padding:4px 0 4px 18px; border-left:3px solid #c81e1e; color:#efe7df; }
        img { max-width:100%; height:auto; border-radius:14px; margin:22px 0; }
        img.hero { width:100%; max-height:520px; object-fit:cover; margin:0 0 28px; }
        ul, ol { padding-left:24px; }
        li { margin-bottom:10px; }
        </style>
        </head>
        <body>
        <article>
        <h1>\(title.htmlEscaped)</h1>
        <div class="sub">\(subtitle.htmlEscaped)</div>
        \(body)
        </article>
        </body>
        </html>
        """
    }
}

struct AudiobooksScreen: View {
    @Environment(AudioPlayerModel.self) private var audio
    @Environment(AudiobookDownloadStore.self) private var audioDownloads
    private let client = AudiobookClient()

    @State private var audiobooks: [Audiobook] = []
    @State private var searchQuery = ""
    @State private var category = "All"
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var categories: [String] {
        ["All"] + Array(Set(audiobooks.compactMap(\.category))).sorted()
    }

    private var filtered: [Audiobook] {
        audiobooks.filter { item in
            (category == "All" || item.category == category)
            && (searchQuery.isEmpty || "\(item.title) \(item.author ?? "") \(item.narrator ?? "")".localizedCaseInsensitiveContains(searchQuery))
        }
    }

    var body: some View {
        let visibleAudiobooks = filtered
        let visibleCategories = categories

        ScrollView {
            LazyVStack(alignment: .leading, spacing: ScreenSpacing.row) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleCategories, id: \.self) { item in
                            Button(item) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    category = item
                                }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(category == item ? Brand.onAccent : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(category == item ? Brand.red : Brand.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                        }
                    }
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    .padding(.top, 6)
                }
                if isLoading && visibleAudiobooks.isEmpty {
                    ProgressView("Loading audiobooks")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if visibleAudiobooks.isEmpty {
                    EmptyPanel(systemImage: "headphones", title: "No audiobooks found", message: errorMessage ?? "Try a different search or category.")
                        .padding(.horizontal, ScreenSpacing.horizontal)
                } else {
                    LazyVStack(spacing: ScreenSpacing.row) {
                        ForEach(visibleAudiobooks) { item in
                            AudiobookRow(
                                audiobook: item,
                                isCurrent: audio.current?.id == item.id,
                                isPlaying: audio.current?.id == item.id && audio.isPlaying
                            ) {
                                if audio.current?.id == item.id {
                                    audio.togglePlay()
                                } else {
                                    audio.load(item)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if audio.current?.id == item.id {
                                    audio.expanded = true
                                } else {
                                    audio.load(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    ScrollBottomClearance(height: audio.current == nil ? ScreenSpacing.tabBarClearance : ScreenSpacing.tabBarWithMiniPlayerClearance)
                }
            }
            .padding(.top, 4)
        }
        .navigationTitle("Audiobooks")
        .animation(.snappy(duration: 0.24), value: visibleAudiobooks.map(\.id))
        .animation(.snappy(duration: 0.2), value: audio.current?.id)
        .searchable(text: $searchQuery, prompt: "Search audiobooks")
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
        .background(ScreenBackground())
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        do {
            let loadedAudiobooks = try await client.fetchAudiobooks(forceRefresh: forceRefresh)
            audiobooks = loadedAudiobooks
            errorMessage = nil
            isLoading = false
            Task { await SearchIndexService.shared.indexAudiobooks(loadedAudiobooks) }
        } catch {
            let offline = audioDownloads.downloads.compactMap(\.audiobook)
            if !offline.isEmpty {
                audiobooks = offline
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct AudiobookRow: View {
    let audiobook: Audiobook
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    @Environment(AudiobookDownloadStore.self) private var audioDownloads

    private var isDownloaded: Bool {
        audioDownloads.isDownloaded(audiobook.id)
    }

    private var isDownloading: Bool {
        audioDownloads.activeDownloadId == audiobook.id
    }

    var body: some View {
        HStack(spacing: 12) {
                AsyncImageCover(urlString: audiobook.coverUrl, systemImage: "headphones", maxPixelSize: 240)
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.20), radius: 8, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(audiobook.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(audiobook.author ?? audiobook.narrator ?? "Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let category = audiobook.category {
                        MetricPill(systemImage: "tag", value: category)
                    }
                    if let duration = audiobook.durationSeconds {
                        MetricPill(systemImage: "clock", value: formatTime(duration))
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                if let entry = audioDownloads.cached(audiobookId: audiobook.id) {
                    audioDownloads.remove(entry)
                } else {
                    Task { await audioDownloads.download(audiobook) }
                }
            } label: {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isDownloaded ? Brand.redSoft : .secondary)
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(PressableScaleButtonStyle(scale: 0.9))
            .disabled(isDownloading)
            .accessibilityLabel(isDownloaded ? "Remove download" : "Download for offline listening")
            Button(action: onPlay) {
                PlaybackCircleIcon(isPlaying: isCurrent && isPlaying, size: 34)
            }
            .buttonStyle(PressableScaleButtonStyle(scale: 0.9))
            .accessibilityLabel(isCurrent && isPlaying ? "Pause" : "Play")
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isCurrent ? 1.006 : 1)
        .animation(.snappy(duration: 0.2), value: isCurrent)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.surface.opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCurrent ? Brand.red.opacity(0.42) : Brand.separator.opacity(0.58), lineWidth: 1)
                }
        }
    }
}

struct AudioPlayerScreen: View {
    @Environment(AudioPlayerModel.self) private var audio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScreenBackground()
            if let current = audio.current {
                PlayerAmbientBackground(urlString: current.coverUrl)
                ScrollView {
                    VStack(spacing: 16) {
                        playerHeader
                        AsyncImageCover(urlString: current.coverUrl, systemImage: "headphones", maxPixelSize: 240)
                            .frame(maxWidth: 254, maxHeight: 254)
                            .aspectRatio(1, contentMode: .fit)
                            .scaleEffect(audio.isPlaying ? 1 : 0.985)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.30), radius: 18, y: 10)

                        VStack(spacing: 8) {
                            Text(current.title)
                                .font(.system(size: 22, weight: .bold))
                                .lineLimit(3)
                                .minimumScaleFactor(0.78)
                                .multilineTextAlignment(.center)
                                .frame(width: 318)
                            Text(current.author ?? current.narrator ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let chapter = audio.currentChapter {
                                Text(chapter.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Brand.redSoft)
                            }
                        }
                        .frame(width: 318)

                        VStack(spacing: 8) {
                            PlayerProgressBar(
                                currentTime: audio.currentTime,
                                duration: audio.duration,
                                onSeek: { audio.seek(to: $0) }
                            )
                            HStack {
                                Text(formatTime(audio.currentTime))
                                Spacer()
                                Text("-" + formatTime(max(0, audio.duration - audio.currentTime)))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .frame(width: 318)

                        playerControls
                        nextUpView

                        if !audio.chapters.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Chapters")
                                    .font(.headline)
                                ForEach(Array(audio.chapters.enumerated()), id: \.offset) { index, chapter in
                                    Button {
                                        audio.jumpToChapter(index)
                                    } label: {
                                        HStack {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(index == audio.currentChapterIndex ? Brand.redSoft : .secondary)
                                            Text(chapter.title)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(formatTime(chapter.startSeconds))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(PressableScaleButtonStyle(scale: 0.985))
                                    .padding(10)
                                    .background(index == audio.currentChapterIndex ? Brand.red.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                    .animation(.snappy(duration: 0.2), value: audio.currentChapterIndex)
                                }
                            }
                            .padding(16)
                            .background(Brand.panel.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .frame(width: 324)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            } else {
                EmptyPanel(systemImage: "headphones", title: "Nothing playing", message: "Choose an audiobook to start listening.")
                    .padding()
            }
        }
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.24), value: audio.isPlaying)
        .animation(.snappy(duration: 0.2), value: audio.currentChapterIndex)
    }

    private var playerHeader: some View {
        HStack {
            PlayerTopButton(systemImage: "chevron.down") {
                dismiss()
            }
            Spacer()
            Text(audio.isPlaying ? "NOW PLAYING" : "PAUSED")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            PlayerTopButton(systemImage: "xmark") {
                audio.expanded = false
            }
        }
    }

    private var playerControls: some View {
        HStack(spacing: 14) {
            PlayerSpeedMenu(speed: audio.speed) { speed in
                audio.setSpeed(speed)
            }
            PlayerIconButton(systemImage: "gobackward.30") {
                audio.skip(by: -30)
            }
            Button {
                audio.togglePlay()
            } label: {
                PlayerPrimaryPlayButton(isPlaying: audio.isPlaying)
            }
            .buttonStyle(PressableScaleButtonStyle(scale: 0.92))
            PlayerIconButton(systemImage: "goforward.30") {
                audio.skip(by: 30)
            }
            PlayerSleepMenu(
                remaining: audio.sleepTimerRemaining,
                hasTimer: audio.hasSleepTimer,
                onSelect: { audio.setSleepTimer(minutes: $0) }
            )
            AirPlayRoutePickerButton()
        }
        .frame(width: 318)
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.18), value: audio.speed)
        .animation(.snappy(duration: 0.18), value: audio.hasSleepTimer)
    }

    @ViewBuilder
    private var nextUpView: some View {
        if let nextChapter = audio.nextChapter {
            HStack(spacing: 10) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next chapter")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(nextChapter.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(formatTime(nextChapter.startSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(width: 318)
        }
    }
}

struct AirPlayRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.white.withAlphaComponent(0.9)
        picker.activeTintColor = UIColor(Brand.red)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor.white.withAlphaComponent(0.9)
        uiView.activeTintColor = UIColor(Brand.red)
    }
}

struct PlayerAmbientBackground: View {
    let urlString: String?

    var body: some View {
        ZStack {
            CachedRemoteImage(urlString: urlString, maxPixelSize: 420) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 44)
                    .opacity(0.23)
            } placeholder: {
                EmptyView()
            }
            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.72), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct PlayerIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.9))
    }
}

struct PlayerSpeedMenu: View {
    let speed: Float
    let onSelect: (Float) -> Void

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == speed {
                        Label(formatSpeed(option), systemImage: "checkmark")
                    } else {
                        Text(formatSpeed(option))
                    }
                }
            }
        } label: {
            Text(formatSpeed(speed))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.92))
        .accessibilityLabel("Playback speed")
    }
}

struct PlayerSleepMenu: View {
    let remaining: TimeInterval
    let hasTimer: Bool
    let onSelect: (Int?) -> Void

    var body: some View {
        Menu {
            Button("Off") { onSelect(nil) }
            Divider()
            Button("15 minutes") { onSelect(15) }
            Button("30 minutes") { onSelect(30) }
            Button("45 minutes") { onSelect(45) }
            Button("1 hour") { onSelect(60) }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: hasTimer ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 18, weight: .semibold))
                if hasTimer {
                    Text(sleepTimerLabel(remaining))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(hasTimer ? Brand.redSoft : .white.opacity(0.9))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.92))
        .accessibilityLabel("Sleep timer")
    }

    private func sleepTimerLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        return "\(minutes)m"
    }
}

struct PlayerTopButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.9))
    }
}

struct PlayerPrimaryPlayButton: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(Brand.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Brand.red.opacity(0.24), radius: 12, y: 6)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.18), value: isPlaying)
    }
}

struct PlayerProgressBar: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max((dragProgress ?? currentTime / duration), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 4)
                Capsule()
                    .fill(.white.opacity(0.94))
                    .frame(width: width * progress, height: 4)
                    .animation(.linear(duration: 0.16), value: progress)
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(width * progress - 5, 0), width - 10))
                    .animation(.linear(duration: 0.16), value: progress)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragProgress = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        let finalProgress = min(max(value.location.x / width, 0), 1)
                        onSeek(finalProgress * max(duration, 1))
                        dragProgress = nil
                    }
            )
        }
        .frame(height: 18)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(duration))")
    }
}

struct ForumScreen: View {
    @Environment(RouterPath.self) private var router
    private let client = ForumClient()

    @State private var threads: [Thread] = []
    @State private var selectedBoard: String?
    @State private var isLoading = true
    @State private var sort = "recent"

    var body: some View {
        Group {
            if AppFeatureFlags.forumEnabled {
                feed
            } else {
                ScrollView {
                    EmptyPanel(systemImage: "lock", title: "The Forum is Under Construction", message: "A space for discussion, reading groups, and organisational praxis is being prepared.")
                        .padding()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Board.all) { board in
                            Label(board.description, systemImage: board.systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface()
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Forum")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentedSheet = .createThread(boardSlug: selectedBoard)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .toolbarIconChrome()
                }
                .glassButtonStyle()
            }
        }
        .background(ScreenBackground())
    }

    private var feed: some View {
        List {
            Picker("Sort", selection: $sort) {
                Text("Recent").tag("recent")
                Text("Popular").tag("popular")
            }
            .pickerStyle(.segmented)
            if isLoading && threads.isEmpty {
                ProgressView("Loading forum")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(threads) { thread in
                    ThreadRow(thread: thread)
                        .contentShape(Rectangle())
                        .onTapGesture { router.navigate(to: .threadDetail(id: thread.id)) }
                }
            }
        }
        .task { await loadThreads() }
        .refreshable { await loadThreads(forceRefresh: true) }
        .onChange(of: sort) { _, _ in Task { await loadThreads() } }
    }

    private func loadThreads(forceRefresh: Bool = false) async {
        isLoading = true
        do {
            let loadedThreads = try await client.fetchThreads(board: selectedBoard, sort: sort, forceRefresh: forceRefresh)
            threads = loadedThreads
            isLoading = false
            Task {
                SystemSnapshotPublisher.publishLatestThreads(loadedThreads)
                await SearchIndexService.shared.indexThreads(loadedThreads)
            }
        } catch {
            isLoading = false
        }
    }
}

struct ThreadRow: View {
    let thread: Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("/\(thread.categorySlug)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                Spacer()
                Text(thread.createdAt.clipped(10))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(thread.title)
                .font(.headline)
            Text(thread.content.strippedMarkdown.clipped(180))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                MetricPill(systemImage: "heart", value: "\(thread.likeCount ?? 0)")
                MetricPill(systemImage: "bubble.left", value: "\(thread.commentCount ?? 0)")
                MetricPill(systemImage: "arrow.2.squarepath", value: "\(thread.repostCount ?? 0)")
            }
        }
        .padding(.vertical, 8)
    }
}

struct ThreadDetailScreen: View {
    let threadId: String
    private let client = ForumClient()
    @State private var thread: Thread?
    @State private var comments: [Comment] = []

    var body: some View {
        List {
            if let thread {
                Section {
                    ThreadRow(thread: thread)
                }
            }
            Section("Comments") {
                ForEach(comments) { comment in
                    Text(comment.content)
                        .font(.body)
                }
            }
        }
        .navigationTitle("Thread")
        .task {
            async let threadRequest = try? client.fetchThread(id: threadId)
            async let commentsRequest = try? client.fetchComments(threadId: threadId)
            thread = await threadRequest
            comments = (await commentsRequest) ?? []
        }
    }
}

struct CreateThreadScreen: View {
    let boardSlug: String?
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    private let client = ForumClient()
    @State private var title = ""
    @State private var content = ""
    @State private var board = "t"
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker("Board", selection: $board) {
                ForEach(Board.all) { board in
                    Text(board.fullName).tag(board.slug)
                }
            }
            TextField("Title", text: $title)
            TextEditor(text: $content)
                .frame(minHeight: 220)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Brand.redSoft)
            }
        }
        .navigationTitle("New Thread")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Post") {
                    Task {
                        do {
                            try await client.createThread(title: title, content: content, category: board, auth: auth)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(title.isEmpty || content.isEmpty)
            }
        }
        .onAppear { board = boardSlug ?? "t" }
    }
}

struct NotificationsScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(RouterPath.self) private var router
    private let client = NotificationClient()
    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if auth.isGuest {
                EmptyPanel(systemImage: "bell.slash", title: "Guest mode", message: "Sign in to receive notifications.")
                    .listRowBackground(Color.clear)
            } else if isLoading && notifications.isEmpty {
                ProgressView("Loading alerts")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .listRowBackground(Color.clear)
            } else if notifications.isEmpty && !isLoading {
                EmptyPanel(systemImage: "bell", title: "No notifications", message: "Activity on your threads will appear here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(notifications) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.isRead == false ? "bell.fill" : "bell")
                            .foregroundStyle(item.isRead == false ? Brand.red : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.type?.capitalized ?? "Notification")
                                .font(.headline)
                            Text(item.contentPreview ?? "You have a new notification.")
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let id = item.threadId {
                            router.navigate(to: .threadDetail(id: id))
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
        .background(ScreenBackground())
    }

    private func load(forceRefresh: Bool = false) async {
        guard let userId = auth.userId else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        notifications = (try? await client.fetchNotifications(userId: userId, accessToken: auth.accessToken, forceRefresh: forceRefresh)) ?? []
    }
}

struct ProfileScreen: View {
    @Environment(AuthStore.self) private var auth
    @Environment(RouterPath.self) private var router
    @Environment(ReadingActivityStore.self) private var readingActivity
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletingAccount = false
    @State private var deletionError = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    Image(systemName: auth.isGuest ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Brand.redSoft)
                    Text(auth.displayName)
                        .font(.headline.weight(.bold))
                    Text(auth.profile?.bio ?? (auth.isGuest ? "Browsing as guest" : "Member profile"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .glassSurface(cornerRadius: 14)

                VStack(spacing: 10) {
                    ProfileButton(title: "Quote Notebook", systemImage: "quote.bubble") { router.navigate(to: .quoteNotebook) }
                    if !readingActivity.quotes.isEmpty {
                        Text("\(readingActivity.quotes.count) saved highlights")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .transition(.opacity)
                    }
                    ProfileButton(title: "Settings", systemImage: "gearshape") { router.navigate(to: .settings) }
                    ProfileButton(title: "Support the Archive", systemImage: "heart") { router.navigate(to: .support) }
                    ProfileButton(title: "Email Preferences", systemImage: "envelope.badge") { router.navigate(to: .emailPreferences) }
                    ProfileButton(title: "Change Password", systemImage: "key") { router.navigate(to: .changePassword) }
                    ProfileButton(title: "Community Guidelines", systemImage: "checkmark.seal") { router.navigate(to: .legal(.guidelines)) }
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    if !auth.isGuest {
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label(
                                isDeletingAccount ? "Deleting Account…" : "Delete Account",
                                systemImage: "person.crop.circle.badge.minus"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDeletingAccount)
                    }
                }
                .padding(12)
                .glassSurface(cornerRadius: 14)
            }
            .padding()
        }
        .navigationTitle("Profile")
        .animation(.snappy(duration: 0.22), value: readingActivity.quotes.count)
        .background(ScreenBackground())
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                isDeletingAccount = true
                Task {
                    let deleted = await auth.deleteAccount()
                    if deleted {
                        readingActivity.clearLocalData()
                    } else {
                        deletionError = auth.errorMessage ?? "Account deletion failed. Please try again."
                    }
                    isDeletingAccount = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account, reading sync data, saved quotes, push tokens, and files. This cannot be undone.")
        }
        .alert("Account deletion failed", isPresented: Binding(
            get: { !deletionError.isEmpty },
            set: { if !$0 { deletionError = "" } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError)
        }
    }
}

struct ProfileButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableScaleButtonStyle(scale: 0.98))
        .padding(12)
        .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct QuoteNotebookScreen: View {
    @Environment(ReadingActivityStore.self) private var readingActivity
    @Environment(RouterPath.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ScreenSpacing.row) {
                if readingActivity.quotes.isEmpty {
                    EmptyPanel(
                        systemImage: "quote.bubble",
                        title: "No saved quotes yet",
                        message: "Save the daily card, or select text in the EPUB reader and tap the quote button."
                    )
                    .padding(.horizontal, ScreenSpacing.horizontal)
                    .padding(.top, 18)
                } else {
                    ForEach(readingActivity.quotes) { item in
                        QuoteNotebookRow(
                            item: item,
                            onOpen: item.routeBookId.map { bookId in
                                { router.navigate(to: .bookReader(id: bookId)) }
                            },
                            onDelete: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    readingActivity.removeQuote(item)
                                }
                                Task {
                                    await SearchIndexService.shared.indexQuotes(readingActivity.quotes)
                                }
                            }
                        )
                        .padding(.horizontal, ScreenSpacing.horizontal)
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                    }
                    ScrollBottomClearance()
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle("Notebook")
        .background(ScreenBackground())
    }
}

struct QuoteNotebookRow: View {
    let item: QuoteNotebookItem
    let onOpen: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.text)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.redSoft)
                    .lineLimit(1)
                if let sourceDetail = item.sourceDetail, !sourceDetail.isEmpty {
                    Text(sourceDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                if let onOpen {
                    Button(action: onOpen) {
                        Label("Open", systemImage: "book.pages")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.92))
                .accessibilityLabel("Delete quote")
            }
        }
        .padding(14)
        .background(Brand.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Brand.separator.opacity(0.64), lineWidth: 1)
        }
    }
}

struct UserProfileScreen: View {
    let userId: String
    private let client = ForumClient()
    @State private var profile: Profile?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Brand.redSoft)
            Text(profile?.username ?? "User")
                .font(.headline.weight(.bold))
            Text(profile?.bio ?? "No bio yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScreenBackground())
        .task {
            profile = try? await client.fetchProfile(id: userId)
        }
    }
}

struct EditProfileScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView("Profile editing", systemImage: "person.crop.circle.badge.plus", description: Text("Native profile editing is scaffolded for the next pass."))
            .toolbar {
                Button("Done") { dismiss() }
            }
    }
}

struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(RouterPath.self) private var router

    var body: some View {
        @Bindable var settingsStore = settingsStore
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settingsStore.settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.systemImage)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("System follows your iPhone or iPad appearance automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Push Notifications", isOn: $settingsStore.settings.pushNotifications)
                Toggle("Email Notifications", isOn: $settingsStore.settings.emailNotifications)
            }
            Section("Reading") {
                Toggle("Data Saver", isOn: $settingsStore.settings.dataSaver)
                Toggle("Show Ideology Badges", isOn: $settingsStore.settings.showIdeologyBadges)
            }
            Section("Support") {
                Button("Support the Archive") { router.navigate(to: .support) }
            }
            Section("Legal") {
                Button("Terms of Service") { router.navigate(to: .legal(.terms)) }
                Button("Privacy Policy") { router.navigate(to: .legal(.privacy)) }
                Button("Community Guidelines") { router.navigate(to: .legal(.guidelines)) }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .onChange(of: settingsStore.settings) { _, _ in settingsStore.save() }
    }
}

struct EmailPreferencesScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settingsStore = settingsStore
        Form {
            Toggle("Marketing Email", isOn: $settingsStore.settings.emailMarketingEnabled)
            Toggle("Comment Replies", isOn: $settingsStore.settings.emailCommentReplies)
            Toggle("Thread Activity", isOn: $settingsStore.settings.emailThreadActivity)
            Toggle("Weekly Digest", isOn: $settingsStore.settings.emailWeeklyDigest)
        }
        .navigationTitle("Email Preferences")
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .onChange(of: settingsStore.settings) { _, _ in settingsStore.save() }
    }
}

struct ChangePasswordScreen: View {
    @State private var currentPassword = ""
    @State private var newPassword = ""

    var body: some View {
        Form {
            SecureField("Current password", text: $currentPassword)
            SecureField("New password", text: $newPassword)
            Button("Update Password") {}
                .disabled(true)
            Text("Password changes require a Supabase Auth update call; the native form is scaffolded and intentionally disabled until email confirmation policy is finalized.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Change Password")
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
    }
}

struct LegalScreen: View {
    let kind: LegalKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(kind.title)
                    .font(.title.bold())
                Text(copy)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
            }
            .padding()
        }
        .navigationTitle(kind.title)
        .background(ScreenBackground())
    }

    private var copy: String {
        switch kind {
        case .terms:
            "Use the app respectfully and within applicable law. Accounts may be moderated when they harm the community or undermine the safety of readers and contributors."
        case .privacy:
            "The app uses Supabase for authentication, forum data, notifications, and library metadata. Local reading settings, guest session data, and downloaded EPUB metadata stay on this device."
        case .guidelines:
            "Discuss rigorously, cite generously, avoid harassment, and keep organizing details safe. Moderation tools and verified community workflows remain part of the forum rollout."
        }
    }
}

struct AppPreviewScaffold: View {
    @State private var auth = AuthStore()
    @State private var settings = SettingsStore()
    @State private var downloads = DownloadStore()
    @State private var audioDownloads = AudiobookDownloadStore()
    @State private var audio = AudioPlayerModel()
    @State private var readingActivity = ReadingActivityStore()

    var body: some View {
        RootView()
            .environment(auth)
            .environment(settings)
            .environment(downloads)
            .environment(audioDownloads)
            .environment(audio)
            .environment(readingActivity)
    }
}

#Preview {
    AppPreviewScaffold()
}
