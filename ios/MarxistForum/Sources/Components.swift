import ImageIO
import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Brand.separator.opacity(0.72), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(Brand.surface.opacity(0.34), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Brand.separator.opacity(0.72), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                    .padding(6)
                    .foregroundStyle(Brand.onAccent)
                    .glassEffect(.regular.tint(Brand.red).interactive(), in: .rect(cornerRadius: 9))
            } else {
                self
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 9))
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 9))
            } else {
                self.buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 9))
            }
        }
    }

    func toolbarIconChrome() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
}

struct PressableScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct ScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let isDark = colorScheme == .dark

        ZStack {
            LinearGradient(
                colors: isDark
                    ? [
                        Brand.canvas,
                        Color(red: 0.085, green: 0.047, blue: 0.050),
                        Color(red: 0.025, green: 0.026, blue: 0.032)
                    ]
                    : [
                        Brand.canvas,
                        Brand.surface.opacity(0.92),
                        Color(red: 0.925, green: 0.882, blue: 0.824)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Brand.red.opacity(reduceTransparency ? 0 : (isDark ? 0.18 : 0.075)))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -140, y: -260)
            Circle()
                .fill((isDark ? Color.white : Brand.surface).opacity(reduceTransparency ? 0 : (isDark ? 0.06 : 0.72)))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 150, y: 40)
            Circle()
                .fill(Brand.red.opacity(reduceTransparency ? 0 : (isDark ? 0.10 : 0.045)))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: 330)
            Circle()
                .fill((isDark ? Color.white : Brand.surface).opacity(reduceTransparency ? 0 : (isDark ? 0.07 : 0.60)))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -170, y: 230)
            Circle()
                .fill(Brand.red.opacity(reduceTransparency ? 0 : (isDark ? 0.14 : 0.055)))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 150, y: 250)
            Rectangle()
                .fill(isDark ? .black.opacity(0.12) : .white.opacity(0.08))
        }
        .ignoresSafeArea()
    }
}

struct EmptyPanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Brand.redSoft)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassSurface(cornerRadius: 14)
    }
}

struct AsyncImageCover: View {
    let urlString: String?
    let systemImage: String
    var maxPixelSize: CGFloat = 720

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.surface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Brand.muted)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: cacheKey) {
            await loadImage()
        }
    }

    private var cacheKey: String {
        guard let urlString, !urlString.isEmpty else { return "empty-\(systemImage)" }
        return "\(urlString)#\(Int(maxPixelSize * displayScale))"
    }

    @MainActor
    private func loadImage() async {
        guard let urlString, let url = URL(string: urlString) else {
            image = nil
            isLoading = false
            return
        }

        let pixelSize = max(120, Int(maxPixelSize * displayScale))
        let key = "\(url.absoluteString)#\(pixelSize)" as NSString
        if let cached = CoverImageMemoryCache.shared.object(forKey: key) {
            image = cached
            isLoading = false
            return
        }

        image = nil
        isLoading = true
        let loaded = await CoverImagePipeline.load(url: url, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        if let loaded {
            CoverImageMemoryCache.shared.setObject(loaded, forKey: key, cost: loaded.memoryCost)
            image = loaded
        }
        isLoading = false
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let urlString: String?
    var maxPixelSize: CGFloat = 720
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: cacheKey) {
            await loadImage()
        }
    }

    private var cacheKey: String {
        guard let urlString, !urlString.isEmpty else { return "empty" }
        return "\(urlString)#\(Int(maxPixelSize * displayScale))"
    }

    @MainActor
    private func loadImage() async {
        guard let urlString, let url = URL(string: urlString) else {
            image = nil
            return
        }

        let pixelSize = max(120, Int(maxPixelSize * displayScale))
        let key = "\(url.absoluteString)#\(pixelSize)" as NSString
        if let cached = CoverImageMemoryCache.shared.object(forKey: key) {
            image = cached
            return
        }

        let loaded = await CoverImagePipeline.load(url: url, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        if let loaded {
            CoverImageMemoryCache.shared.setObject(loaded, forKey: key, cost: loaded.memoryCost)
            image = loaded
        }
    }
}

@MainActor
private enum CoverImageMemoryCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 220
        cache.totalCostLimit = 72 * 1024 * 1024
        return cache
    }()
}

private enum CoverImagePipeline {
    static func load(url: URL, pixelSize: Int) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return nil }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            return await Task.detached(priority: .utility) {
                downsample(data: data, pixelSize: pixelSize)
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

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else {
            return Int(size.width * scale * size.height * scale * 4)
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct TopFilterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12, interactive: true)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct LiquidTabBar: View {
    @Binding var selectedTab: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let nativeBarHeight: CGFloat = 56
    private let fallbackBarHeight: CGFloat = 46

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                nativeGlassBar
            } else {
                fallbackBar
            }
        }
        .animation(tabSpring, value: selectedTab)
    }

    @available(iOS 26.0, *)
    private var nativeGlassBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(AppTab.bottomBarTabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .frame(width: proxy.size.width, height: nativeBarHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Brand.separator.opacity(0.74), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(tabDragGesture(width: proxy.size.width))
        }
        .frame(height: nativeBarHeight)
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }

    @available(iOS 26.0, *)
    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            select(tab)
        } label: {
            tabLabel(tab)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private var fallbackBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(AppTab.bottomBarTabs) { tab in
                    Button {
                        select(tab)
                    } label: {
                        tabLabel(tab)
                    }
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(Brand.surface.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Brand.separator.opacity(0.72), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(tabDragGesture(width: proxy.size.width))
        }
        .frame(height: fallbackBarHeight)
        .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        VStack(spacing: 3) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .symbolVariant(selectedTab == tab ? .fill : .none)
                .contentTransition(.symbolEffect(.replace))
            Text(tab.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.opacity)
        }
        .foregroundStyle(selectedTab == tab ? Brand.redSoft : .secondary)
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(Rectangle())
    }

    private func select(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        withAnimation(tabSpring) {
            selectedTab = tab
        }
    }

    private func selectTab(at locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let tabs = AppTab.bottomBarTabs
        let clampedX = min(max(locationX, 0), width - 0.1)
        let index = min(max(Int((clampedX / width) * CGFloat(tabs.count)), 0), tabs.count - 1)
        select(tabs[index])
    }

    private func tabDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                selectTab(at: value.location.x, width: width)
            }
            .onEnded { value in
                selectTab(at: value.location.x, width: width)
            }
    }

    private var tabSpring: Animation {
        reduceMotion ? .linear(duration: 0.01) : .interactiveSpring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.08)
    }
}

struct MetricPill: View {
    let systemImage: String
    let value: String

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Brand.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MiniPlayerBar: View {
    var isTabAccessory = false
    @Environment(AudioPlayerModel.self) private var audio

    var body: some View {
        if let current = audio.current {
            chrome {
                HStack(spacing: 12) {
                    Button {
                        audio.expanded = true
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImageCover(urlString: current.coverUrl, systemImage: "headphones", maxPixelSize: 240)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(current.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(audio.currentChapter?.title ?? current.author ?? current.narrator ?? "Ready")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                MiniProgressLine(progress: audio.progress)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        audio.togglePlay()
                    } label: {
                        PlaybackCircleIcon(isPlaying: audio.isPlaying, size: 36)
                    }
                    .buttonStyle(PressableScaleButtonStyle(scale: 0.92))
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func chrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if isTabAccessory {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        } else {
            content()
                .padding(8)
                .glassSurface(cornerRadius: 14, interactive: true)
                .padding(.horizontal, 12)
        }
    }
}

struct PlaybackCircleIcon: View {
    let isPlaying: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(Brand.onAccent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: max(8, size * 0.22), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Brand.red, Color(red: 0.55, green: 0.045, blue: 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Brand.red.opacity(0.22), radius: 10, y: 5)
    }
}

struct MiniProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Brand.controlFill)
                Capsule()
                    .fill(Brand.red)
                    .frame(width: proxy.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 3)
    }
}

func formatTime(_ seconds: Double) -> String {
    let safe = max(0, Int(seconds))
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60
    if hours > 0 {
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
    }
    return "\(minutes):\(String(format: "%02d", secs))"
}

func formatSpeed(_ speed: Float) -> String {
    if speed == 1 {
        return "1x"
    }
    return String(format: speed.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fx" : "%.2gx", speed)
}
