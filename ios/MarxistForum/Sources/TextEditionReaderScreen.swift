import SwiftUI

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

    @State private var activeSectionIndex = 0
    @State private var progress: Double = 0
    @State private var isShowingContents = false
    @State private var isShowingReaderSettings = false
    @State private var didRestorePosition = false
    @State private var sectionOrigins: [Int: CGFloat] = [:]
    @AppStorage("ios.reader.fontSize") private var fontSize: Double = 18
    @AppStorage("ios.reader.theme") private var readerThemeRawValue = ReaderTheme.night.rawValue

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

    private var currentSectionTitle: String {
        guard sections.indices.contains(activeSectionIndex) else { return book.title }
        return sections[activeSectionIndex].title ?? "Section \(activeSectionIndex + 1)"
    }

    private var chapterCounter: String {
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

    var body: some View {
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
            .onAppear { restorePosition(proxy) }
            .onChange(of: activeSectionIndex) { _, newIndex in
                persistProgress(to: newIndex)
            }
            .sheet(isPresented: $isShowingContents) {
                TextEditionContentsSheet(
                    sections: sections,
                    currentIndex: activeSectionIndex,
                    onSelect: { index in
                        jump(to: index, proxy: proxy)
                    }
                )
            }
            .sheet(isPresented: $isShowingReaderSettings) {
                ReaderSettingsSheet(fontSize: $fontSize, theme: readerThemeBinding)
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
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .glassButtonStyle()
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

            Button {
                adjustFont(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .glassButtonStyle()
            .disabled(fontSize <= 14)
            .accessibilityLabel("Smaller text")

            Button {
                adjustFont(1)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .glassButtonStyle()
            .disabled(fontSize >= 28)
            .accessibilityLabel("Larger text")
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
            Button {
                isShowingContents = true
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 30, height: 30)
            }
            .glassButtonStyle()
            .accessibilityLabel("Contents")

            Button {
                savePlace()
            } label: {
                Image(systemName: "bookmark")
                    .frame(width: 30, height: 30)
            }
            .glassButtonStyle()
            .accessibilityLabel("Save reading place to notebook")

            Button {
                isShowingReaderSettings = true
            } label: {
                Image(systemName: "textformat")
                    .frame(width: 30, height: 30)
            }
            .glassButtonStyle()
            .accessibilityLabel("Reader settings")
        }
        .padding(10)
        .glassSurface(cornerRadius: 14, interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Behavior

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

    private func restorePosition(_ proxy: ScrollViewProxy) {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        let saved = readerDefaults.integer(forKey: readerProgressKey)
        let index = min(max(saved, 0), max(sections.count - 1, 0))
        activeSectionIndex = index
        guard index > 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            proxy.scrollTo(sections[index].id, anchor: .top)
        }
    }

    private func jump(to index: Int, proxy: ScrollViewProxy?) {
        guard let proxy, sections.indices.contains(index) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.3)) {
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
