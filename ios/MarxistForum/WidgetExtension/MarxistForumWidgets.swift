import SwiftUI
import WidgetKit

struct MarxistForumWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: SystemIntegrationSnapshot
}

struct MarxistForumWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MarxistForumWidgetEntry {
        MarxistForumWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MarxistForumWidgetEntry) -> Void) {
        completion(MarxistForumWidgetEntry(date: Date(), snapshot: SystemIntegrationStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MarxistForumWidgetEntry>) -> Void) {
        let entry = MarxistForumWidgetEntry(date: Date(), snapshot: SystemIntegrationStore.loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DailyQuoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyQuoteWidget", provider: MarxistForumWidgetProvider()) { entry in
            DailyQuoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Quote")
        .description("Show today's MarxistInfo quote.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReadingWidget", provider: MarxistForumWidgetProvider()) { entry in
            ContinueReadingWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Reading")
        .description("Jump back into your latest book.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CurrentAudiobookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentAudiobookWidget", provider: MarxistForumWidgetProvider()) { entry in
            CurrentAudiobookWidgetView(entry: entry)
        }
        .configurationDisplayName("Current Audiobook")
        .description("Open your current audiobook.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LatestUpdatesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestUpdatesWidget", provider: MarxistForumWidgetProvider()) { entry in
            LatestUpdatesWidgetView(entry: entry)
        }
        .configurationDisplayName("Latest Updates")
        .description("Open the latest article or forum thread.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DailyQuoteWidgetView: View {
    let entry: MarxistForumWidgetEntry

    var body: some View {
        WidgetPanel(url: AppDeepLink.dailyQuote.url) {
            if let quote = entry.snapshot.dailyQuote {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Daily Quote", systemImage: "quote.bubble")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(quote.text)
                        .font(.headline)
                        .lineLimit(5)
                    Spacer(minLength: 0)
                    Text(quote.source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                EmptyWidgetState(title: "Daily Quote", systemImage: "quote.bubble", message: "Open the app to load today's quote.")
            }
        }
    }
}

struct ContinueReadingWidgetView: View {
    let entry: MarxistForumWidgetEntry

    var body: some View {
        let url = entry.snapshot.continueReading.map { AppDeepLink.book(id: $0.bookId).url } ?? AppDeepLink.continueReading.url
        WidgetPanel(url: url) {
            if let item = entry.snapshot.continueReading {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Continue Reading", systemImage: "book")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)
                    Text(item.chapterTitle ?? item.author ?? "Reader")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ProgressView(value: min(max(item.progress, 0), 1))
                        .tint(.red)
                }
            } else {
                EmptyWidgetState(title: "Continue Reading", systemImage: "book", message: "Read a book to start tracking progress.")
            }
        }
    }
}

struct CurrentAudiobookWidgetView: View {
    let entry: MarxistForumWidgetEntry

    var body: some View {
        let url = entry.snapshot.currentAudiobook.map { AppDeepLink.audiobook(id: $0.id).url } ?? AppDeepLink.audiobooks.url
        WidgetPanel(url: url) {
            if let item = entry.snapshot.currentAudiobook {
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.isPlaying ? "Playing" : "Paused", systemImage: "headphones")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)
                    Text(item.chapterTitle ?? item.author ?? item.narrator ?? "Audiobook")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if item.duration > 0 {
                        ProgressView(value: min(max(item.currentTime / item.duration, 0), 1))
                            .tint(.red)
                    }
                }
            } else {
                EmptyWidgetState(title: "Audiobooks", systemImage: "headphones", message: "Choose an audiobook in the app.")
            }
        }
    }
}

struct LatestUpdatesWidgetView: View {
    let entry: MarxistForumWidgetEntry

    var body: some View {
        WidgetPanel(url: entry.snapshot.latestUpdates.first?.deepLinkURL ?? AppDeepLink.substack.url) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Latest Updates", systemImage: "newspaper")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)

                if entry.snapshot.latestUpdates.isEmpty {
                    EmptyWidgetState(title: "No Updates", systemImage: "newspaper", message: "Open the app to refresh articles.")
                } else {
                    ForEach(entry.snapshot.latestUpdates.prefix(3), id: \.id) { update in
                        Link(destination: update.deepLinkURL) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(update.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(update.subtitle ?? update.detail ?? update.kind.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct WidgetPanel<Content: View>: View {
    let url: URL
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .widgetURL(url)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.052, blue: 0.052),
                        Color(red: 0.12, green: 0.04, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

struct EmptyWidgetState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

@main
struct MarxistForumWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyQuoteWidget()
        ContinueReadingWidget()
        CurrentAudiobookWidget()
        LatestUpdatesWidget()
    }
}
