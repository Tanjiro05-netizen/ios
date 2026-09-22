import PDFKit
import SwiftUI

/// How the text edition is presented: one continuous editorial scroll
/// (the web edition), one-section-per-page ebook pages, or the print
/// facsimile through the in-app PDF viewer.
enum ReaderViewMode: String, CaseIterable, Identifiable {
    case scroll
    case pages
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: "Scroll"
        case .pages: "Pages"
        case .pdf: "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .scroll: "text.justify"
        case .pages: "book"
        case .pdf: "doc.richtext"
        }
    }
}

/// The fullscreen text-edition reading surface: the whole book as one
/// scrolling editorial column with a sticky chapter header, a crimson
/// progress rule and a numbered contents rail, in the manner of the
/// website's TextEditionReader. Sections come from
/// digital_library_books.text_edition.
struct TextEditionReaderScreen: View {
    let book: Book
    let edition: TextEdition

    @Environment(ReadingActivityStore.self) private var readingActivity
    @Environment(\.dismiss) private var dismiss
    private let readerDefaults = UserDefaults.standard
    private let libraryClient = LibraryClient()

    @State private var activeSectionIndex = 0
    @State private var progress: Double = 0
    @State private var isShowingContents = false
    @State private var isShowingReaderSettings = false
    @State private var didRestorePosition = false
    @State private var sectionOrigins: [Int: CGFloat] = [:]
    @State private var pageTurnIsForward = true
    @State private var scrollProxy: ScrollViewProxy?
    @State private var pdfDocument: PDFDocument?
    @State private var pdfPageCount = 0
    @State private var didLoadPDF = false
    @State private var isLoadingPDF = false
    @State private var pdfErrorMessage: String?
    @AppStorage("ios.reader.fontSize") private var fontSize: Double = 18
    @AppStorage("ios.reader.theme") private var readerThemeRawValue = ReaderTheme.night.rawValue
    @AppStorage("ios.reader.viewMode") private var viewModeRawValue = ReaderViewMode.scroll.rawValue

    /// The website hides the synthetic heading of a leading front-matter section.
    private static let frontMatterTitle = "Front matter"
    /// How far past the sticky header a section must scroll before it counts
    /// as current (website: sticky toolbar height + one line of lookahead).
    private static let activeSectionThreshold: CGFloat = 120

    private var sections: [TextEditionSection] { edition.sections }

    private var fontScale: CGFloat { fontSize / 17 }

    private var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRawValue) ?? .night
    }

    private var readerThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { readerTheme },
            set: { readerThemeRawValue = $0.rawValue }
        )
    }

    private var viewMode: ReaderViewMode {
        ReaderViewMode(rawValue: viewModeRawValue) ?? .scroll
    }

    private var viewModeBinding: Binding<ReaderViewMode> {
        Binding(
            get: { viewMode },
            set: { switchViewMode(to: $0) }
        )
    }

    /// PDF mode is only offered for titles that actually ship a print file.
    private var availableModes: [ReaderViewMode] {
        book.pdfFilename == nil
            ? [.scroll, .pages]
            : ReaderViewMode.allCases
    }

    private var currentSectionTitle: String {
        if viewMode == .pdf { return book.title }
        guard sections.indices.contains(activeSectionIndex) else { return book.title }
        return sections[activeSectionIndex].title ?? "Section \(activeSectionIndex + 1)"
    }

    private var chapterCounter: String {
        switch viewMode {
        case .pdf:
            var counter = "PDF edition"
            if pdfPageCount > 0 { counter = "PDF · \(pdfPageCount) pages" }
            return counter
        case .pages:
            return String(
                format: "Page %02d of %02d",
                min(activeSectionIndex + 1, max(sections.count, 1)),
                max(sections.count, 1)
            )
        case .scroll:
            var counter = String(
                format: "%02d / %02d",
                min(activeSectionIndex + 1, max(sections.count, 1)),
                sections.count
            )
            if let minutes = edition.readingMinutes {
                counter += " · \(minutes) min"
            }
            return counter
        }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .scroll: scrollReader
            case .pages: pagedReader
            case .pdf: pdfReader
            }
        }
        .background(Color(hex: readerTheme.backgroundHex).ignoresSafeArea())
        // The app root pins its own preferred scheme, which would otherwise
        // resolve .primary/.secondary against the wrong appearance and leave
        // prose unreadable — pin the environment to the reading theme instead.
        .environment(\.colorScheme, readerTheme == .paper ? .light : .dark)
        .preferredColorScheme(readerTheme == .paper ? .light : .dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isShowingContents) {
            TextEditionContentsSheet(
                sections: sections,
                currentIndex: activeSectionIndex,
                onSelect: { index in
                    jump(to: index, proxy: scrollProxy)
                }
            )
        }
        .sheet(isPresented: $isShowingReaderSettings) {
            ReaderSettingsSheet(fontSize: $fontSize, theme: readerThemeBinding)
        }
        .onChange(of: activeSectionIndex) { _, newIndex in
            if viewMode == .pages {
                progress = Double(newIndex + 1) / Double(max(sections.count, 1))
            }
            persistProgress(to: newIndex)
        }
    }

    // MARK: - Scroll mode (continuous web-style column)

    private var scrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    bookHeader
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section, index: index)
                        if index < sections.count - 1 {
                            sectionDivider
                        }
                    }
                    Color.clear
                        .frame(height: 120)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color(hex: readerTheme.textHex))
            }
            .coordinateSpace(name: "textEditionScroll")
            .onPreferenceChange(SectionOriginPreferenceKey.self) { origins in
                sectionOrigins = origins
                updateActiveSection(from: origins)
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                let scrollable = geometry.contentSize.height - geometry.containerSize.height
                guard scrollable > 0 else { return 0 }
                let offset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                return min(max(offset / scrollable, 0), 1)
            } action: { _, newValue in
                progress = newValue
            }
            .safeAreaInset(edge: .top, spacing: 0) { stickyHeader }
            .overlay(alignment: .bottom) { toolbar }
            .onAppear {
                scrollProxy = proxy
                restorePosition()
                jump(to: activeSectionIndex, proxy: proxy, animated: false)
            }
        }
    }

    // MARK: - Pages mode (ebook page turns, one section per page)

    private var pagedReader: some View {
        ZStack {
            if sections.indices.contains(activeSectionIndex) {
                pagedSectionView(sections[activeSectionIndex], index: activeSectionIndex)
                    .id(activeSectionIndex)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: pageTurnIsForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: pageTurnIsForward ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.easeInOut(duration: 0.28), value: activeSectionIndex)
        .simultaneousGesture(pageTurnDragGesture)
        .overlay(alignment: .leading) { pageTapZone(forward: false) }
        .overlay(alignment: .trailing) { pageTapZone(forward: true) }
        .safeAreaInset(edge: .top, spacing: 0) { stickyHeader }
        .overlay(alignment: .bottom) { toolbar }
        .onAppear {
            restorePosition()
            progress = Double(activeSectionIndex + 1) / Double(max(sections.count, 1))
        }
    }

    private var pageTurnDragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 56, abs(horizontal) > abs(vertical) * 1.6 else { return }
                turnPage(horizontal < 0 ? 1 : -1)
            }
    }

    private func pageTapZone(forward: Bool) -> some View {
        Color.clear
            .frame(width: 56)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 110)
            .contentShape(Rectangle())
            .onTapGesture { turnPage(forward ? 1 : -1) }
            .accessibilityHidden(true)
    }

    private func pagedSectionView(_ section: TextEditionSection, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showsSectionTitle(section, index: index) {
                    Text(section.title ?? "")
                        .font(sectionHeadingFont(section.level))
                        .foregroundStyle(Color(hex: readerTheme.headingHex))
                        .padding(.bottom, 4)
                }
                StudyMarkdownDocument(markdown: section.md, bodyFontSize: fontSize)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color(hex: readerTheme.textHex))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(index + 1) of \(sections.count)")
    }

    private func turnPage(_ delta: Int) {
        let target = activeSectionIndex + delta
        guard sections.indices.contains(target) else { return }
        pageTurnIsForward = delta > 0
        withAnimation(.easeInOut(duration: 0.28)) {
            activeSectionIndex = target
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - PDF mode (print facsimile in PDFKit)

    private var pdfReader: some View {
        Group {
            if let pdfDocument {
                TextEditionPDFPageView(
                    document: pdfDocument,
                    readerTheme: readerTheme,
                    progress: $progress,
                    pageCount: $pdfPageCount
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let pdfErrorMessage {
                ContentUnavailableView {
                    Label("PDF unavailable", systemImage: "doc.questionmark")
                } description: {
                    Text(pdfErrorMessage)
                } actions: {
                    Button("Try again") {
                        Task { await loadPDF() }
                    }
                }
            } else {
                ProgressView("Opening the print edition…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { stickyHeader }
        .overlay(alignment: .bottom) { toolbar }
        .task(id: book.id) {
            guard viewMode == .pdf, !didLoadPDF, pdfDocument == nil else { return }
            await loadPDF()
        }
    }

    private func loadPDF() async {
        guard !isLoadingPDF, !didLoadPDF else { return }
        guard let pdfFilename = book.pdfFilename else {
            pdfErrorMessage = "This title does not ship a print PDF."
            return
        }
        isLoadingPDF = true
        pdfErrorMessage = nil
        defer { isLoadingPDF = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: libraryClient.pdfURL(filename: pdfFilename))
            guard let document = PDFDocument(data: data) else {
                pdfErrorMessage = "The PDF file could not be opened."
                return
            }
            pdfDocument = document
            pdfPageCount = document.pageCount
            didLoadPDF = true
        } catch {
            pdfErrorMessage = "The PDF could not be downloaded. Check your connection and try again."
        }
    }

    // MARK: - Column pieces

    private var bookHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.title)
                .font(.system(size: 30 * fontScale, weight: .semibold, design: .serif))
                .foregroundStyle(Color(hex: readerTheme.headingHex))
                .padding(.top, 26)
            HStack(spacing: 8) {
                if let author = book.author, !author.isEmpty {
                    Text(author)
                }
                if edition.readingMinutes != nil, book.author?.isEmpty == false {
                    Text("·")
                }
                if let minutes = edition.readingMinutes {
                    Text("\(minutes) min read")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sectionView(_ section: TextEditionSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsSectionTitle(section, index: index) {
                Text(section.title ?? "")
                    .font(sectionHeadingFont(section.level))
                    .foregroundStyle(Color(hex: readerTheme.headingHex))
                    .padding(.bottom, 4)
            }
            StudyMarkdownDocument(markdown: section.md, bodyFontSize: fontSize)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SectionOriginReporter(index: index))
        .id(section.id)
    }

    private var sectionDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Brand.separator.opacity(0.6))
                .frame(height: 1)
            Rectangle()
                .fill(Brand.redSoft)
                .frame(width: 6, height: 6)
                .rotationEffect(.degrees(45))
            Rectangle()
                .fill(Brand.separator.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    // MARK: - Sticky chrome

    private var stickyHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .toolbarIconChrome()
            }
            .glassSurface(cornerRadius: 9)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text(currentSectionTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapterCounter)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if viewMode != .pdf {
                Button {
                    adjustFont(-1)
                } label: {
                    Image(systemName: "minus")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .disabled(fontSize <= 14)
                .accessibilityLabel("Smaller text")

                Button {
                    adjustFont(1)
                } label: {
                    Image(systemName: "plus")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .disabled(fontSize >= 28)
                .accessibilityLabel("Larger text")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // One continuous bar flush with the top of the screen: the theme
        // surface bleeds up through the status bar region and the crimson
        // progress rule rides the screen's absolute top edge, as on the
        // website where the rule rides the toolbar's top edge.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(hex: readerTheme.backgroundHex)
                headerProgressRule
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var headerProgressRule: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Brand.separator.opacity(0.5))
                    .frame(height: 2)
                Rectangle()
                    .fill(Brand.redSoft.opacity(0.9))
                    .frame(width: max(proxy.size.width * progress, 0), height: 2)
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if viewMode == .pages {
                Button {
                    turnPage(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .disabled(activeSectionIndex == 0)
                .accessibilityLabel("Previous page")

                Text("Page \(min(activeSectionIndex + 1, max(sections.count, 1))) / \(max(sections.count, 1))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 86)

                Button {
                    turnPage(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .disabled(activeSectionIndex >= sections.count - 1)
                .accessibilityLabel("Next page")
            }

            Spacer(minLength: 0)

            if viewMode != .pdf {
                Button {
                    isShowingContents = true
                } label: {
                    Image(systemName: "list.bullet")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .accessibilityLabel("Contents")

                Button {
                    savePlace()
                } label: {
                    Image(systemName: "bookmark")
                        .toolbarIconChrome()
                }
                .glassSurface(cornerRadius: 9)
                .accessibilityLabel("Save reading place to notebook")
            }

            Button {
                isShowingReaderSettings = true
            } label: {
                Image(systemName: "textformat")
                    .toolbarIconChrome()
            }
            .glassSurface(cornerRadius: 9)
            .accessibilityLabel("Reader settings")

            viewOptionsMenu
        }
        .padding(10)
        .glassSurface(cornerRadius: 14, interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Reading-format switcher: continuous scroll, ebook pages, or the
    /// print PDF facsimile when the title ships one.
    private var viewOptionsMenu: some View {
        Menu {
            Picker("Reading format", selection: viewModeBinding) {
                ForEach(availableModes) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
        } label: {
            Image(systemName: viewMode.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("Reading format options")
        }
        .glassSurface(cornerRadius: 9)
        .accessibilityIdentifier("reader.format-menu")
        .accessibilityLabel("Reading format options")
    }

    // MARK: - Behavior

    private func switchViewMode(to mode: ReaderViewMode) {
        guard mode != viewMode, availableModes.contains(mode) else { return }
        viewModeRawValue = mode.rawValue
        switch mode {
        case .pages:
            progress = Double(activeSectionIndex + 1) / Double(max(sections.count, 1))
        case .pdf:
            progress = 0
            if pdfDocument == nil, pdfErrorMessage == nil {
                Task { await loadPDF() }
            }
        case .scroll:
            break
        }
    }

    private func showsSectionTitle(_ section: TextEditionSection, index: Int) -> Bool {
        guard let title = section.title, !title.isEmpty else { return false }
        if index == 0, title == Self.frontMatterTitle { return false }
        return true
    }

    private func sectionHeadingFont(_ level: Int?) -> Font {
        switch level ?? 2 {
        case 1: .system(size: 23 * fontScale, weight: .semibold, design: .serif)
        case 2: .system(size: 21 * fontScale, weight: .semibold, design: .serif)
        default: .system(size: 18 * fontScale, weight: .semibold, design: .serif)
        }
    }

    private func adjustFont(_ delta: Double) {
        fontSize = min(max(fontSize + delta, 14), 28)
    }

    private func updateActiveSection(from origins: [Int: CGFloat]) {
        var active = 0
        for (index, originY) in origins where originY <= Self.activeSectionThreshold {
            if index > active { active = index }
        }
        if active != activeSectionIndex {
            activeSectionIndex = active
        }
    }

    private func restorePosition() {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        let saved = readerDefaults.integer(forKey: readerProgressKey)
        let index = min(max(saved, 0), max(sections.count - 1, 0))
        activeSectionIndex = index
    }

    private func jump(to index: Int, proxy: ScrollViewProxy?, animated: Bool = true) {
        guard sections.indices.contains(index) else { return }
        pageTurnIsForward = index > activeSectionIndex
        activeSectionIndex = index
        guard let proxy else { return }
        let delay: UInt64 = animated ? 250 : 150
        Task {
            try? await Task.sleep(for: .milliseconds(delay))
            withAnimation(.easeInOut(duration: animated ? 0.3 : 0.0)) {
                proxy.scrollTo(sections[index].id, anchor: .top)
            }
        }
    }

    private func persistProgress(to index: Int) {
        guard didRestorePosition else { return }
        readerDefaults.set(index, forKey: readerProgressKey)
        readingActivity.upsertProgress(
            book: book,
            chapterTitle: sections.indices.contains(index) ? sections[index].title : nil,
            chapterIndex: index,
            chapterCount: sections.count
        )
        SystemSnapshotPublisher.publishContinueReading(readingActivity.continueReading.first)
        Task {
            await SearchIndexService.shared.indexContinueReading(readingActivity.continueReading)
        }
    }

    private func savePlace() {
        let sectionLabel = "Section \(activeSectionIndex + 1) of \(max(sections.count, 1))"
        let detail = "\(sectionLabel) · \(currentSectionTitle)"
        _ = readingActivity.saveQuote(
            text: currentSectionTitle,
            sourceTitle: book.title,
            sourceDetail: detail,
            routeBookId: book.id
        )
        Task {
            await SearchIndexService.shared.indexQuotes(readingActivity.quotes)
        }
    }

    private var readerProgressKey: String {
        "ios.reader.textSection.\(book.id)"
    }
}

/// Reports a section's vertical origin inside the scroll coordinate space so
/// the header and contents sheet can scroll-spy without polling.
private struct SectionOriginReporter: View {
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SectionOriginPreferenceKey.self,
                value: [index: proxy.frame(in: .named("textEditionScroll")).minY]
            )
        }
    }
}

private struct SectionOriginPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        for (key, originY) in nextValue() {
            value[key] = originY
        }
    }
}

/// Continuous PDFKit surface for the print facsimile: auto-scaled pages,
/// vertical flow, theme-matched backdrop, and page-changed reporting so the
/// crimson header rule tracks reading position like the text modes.
private struct TextEditionPDFPageView: UIViewRepresentable {
    let document: PDFDocument
    let readerTheme: ReaderTheme
    @Binding var progress: Double
    @Binding var pageCount: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = UIColor(Color(hex: readerTheme.backgroundHex))
        view.document = document
        pageCount = document.pageCount
        context.coordinator.attach(view: view, progress: $progress)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.backgroundColor = UIColor(Color(hex: readerTheme.backgroundHex))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        private var observer: NSObjectProtocol?
        private weak var view: PDFView?
        private var document: PDFDocument?
        private var progress: Binding<Double>?

        func attach(view: PDFView, progress: Binding<Double>) {
            guard observer == nil else { return }
            self.view = view
            self.document = view.document
            self.progress = progress
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                self?.reportProgress()
            }
        }

        private func reportProgress() {
            guard let view, let document, let progress else { return }
            guard let page = view.currentPage else { return }
            let index = document.index(for: page)
            guard index >= 0, document.pageCount > 0 else { return }
            progress.wrappedValue = Double(index + 1) / Double(document.pageCount)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// Numbered contents rail mirroring the website's chapter rail: crimson
/// tabular numerals, indentation for sub-sections, checkmark on the current
/// section.
private struct TextEditionContentsSheet: View {
    let sections: [TextEditionSection]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        onSelect(index)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(index == currentIndex ? Brand.redSoft : .secondary)
                            Text(section.title ?? "Section \(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .padding(.leading, (section.level ?? 1) > 1 ? 14 : 0)
                            Spacer()
                            if index == currentIndex {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
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

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
