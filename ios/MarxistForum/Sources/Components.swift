import ImageIO
import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(Brand.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.07))
                }
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 9))
            } else {
                self.buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: 9))
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
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.035, blue: 0.035),
                    Color(red: 0.075, green: 0.075, blue: 0.075),
                    Color(red: 0.045, green: 0.040, blue: 0.040)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.black.opacity(0.18))
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
                .fill(Brand.panel)
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
    @State private var dragLocationX: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let liquidBarHeight: CGFloat = 48
    private let liquidTotalHeight: CGFloat = 52
    private let fallbackBarHeight: CGFloat = 46

    var body: some View {
        if #available(iOS 26.0, *) {
            tabItems(isLiquidGlass: true)
        } else {
            tabItems(isLiquidGlass: false)
                .padding(5)
                .background(Brand.panel.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
        }
    }

    private func tabItems(isLiquidGlass: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let tabWidth = width / max(CGFloat(AppTab.allCases.count), 1)
            let sliderWidth = selectedSliderWidth(tabWidth: tabWidth)
            let sliderCenterX = clampedSliderCenter(
                dragLocationX ?? selectedTabCenter(width: width),
                width: width,
                sliderWidth: sliderWidth
            )

            ZStack(alignment: .leading) {
                if #available(iOS 26.0, *), isLiquidGlass {
                    GlassEffectContainer(spacing: 10) {
                        ZStack(alignment: .leading) {
                            liquidGlassBase(width: width)
                            selectedSlider(
                                isLiquidGlass: true,
                                centerX: sliderCenterX,
                                sliderWidth: sliderWidth
                            )
                        }
                    }
                    .zIndex(0)
                } else {
                    fallbackGlassBase(width: width)
                    selectedSlider(
                        isLiquidGlass: false,
                        centerX: sliderCenterX,
                        sliderWidth: sliderWidth
                    )
                    .allowsHitTesting(false)
                    .zIndex(1)
                }

                tabButtonRow
                    .frame(width: width, height: isLiquidGlass ? liquidBarHeight : fallbackBarHeight)
                    .zIndex(2)
            }
            .frame(width: width, height: isLiquidGlass ? liquidTotalHeight : fallbackBarHeight)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        dragLocationX = min(max(value.location.x, 0), width)
                        selectTab(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        selectTab(at: value.location.x, width: width)
                        withAnimation(tabSpring) {
                            dragLocationX = nil
                        }
                    }
            )
        }
        .frame(height: isLiquidGlass ? liquidTotalHeight : fallbackBarHeight)
        .animation(tabSpring, value: selectedTab)
        .animation(tabSpring, value: dragLocationX)
    }

    private func selectTab(at locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let tabs = AppTab.allCases
        let clampedX = min(max(locationX, 0), width - 0.1)
        let index = min(max(Int((clampedX / width) * CGFloat(tabs.count)), 0), tabs.count - 1)
        let nextTab = tabs[index]
        guard nextTab != selectedTab else { return }
        withAnimation(tabSpring) {
            selectedTab = nextTab
        }
    }

    private var tabSpring: Animation {
        reduceMotion ? .linear(duration: 0.01) : .interactiveSpring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.08)
    }

    private var tabButtonRow: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(tabSpring) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
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
                    .foregroundStyle(tabForeground(tab))
                    .shadow(color: .black.opacity(selectedTab == tab ? 0.28 : 0.18), radius: 2, y: 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleButtonStyle(scale: 0.94))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    private func tabForeground(_ tab: AppTab) -> Color {
        selectedTab == tab ? .white : .white.opacity(0.78)
    }

    @available(iOS 26.0, *)
    private func liquidGlassBase(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: liquidBarHeight)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.08))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 14, y: 7)
    }

    @ViewBuilder
    private func selectedSlider(isLiquidGlass: Bool, centerX: CGFloat, sliderWidth: CGFloat) -> some View {
        let sliderHeight: CGFloat = isLiquidGlass ? 36 : 34
        let yOffset: CGFloat = isLiquidGlass ? 6 : 6

        if #available(iOS 26.0, *), isLiquidGlass {
            Color.clear
                .frame(width: sliderWidth, height: sliderHeight)
                .glassEffect(.regular.tint(Brand.red.opacity(0.16)).interactive(), in: .rect(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Brand.red.opacity(0.12))
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.24), .white.opacity(0.07), Brand.red.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Brand.red.opacity(0.12), radius: 8, y: 4)
                .offset(x: centerX - sliderWidth / 2, y: yOffset)
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Brand.red.opacity(0.58), Brand.red.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .frame(width: sliderWidth, height: sliderHeight)
                .shadow(color: Brand.red.opacity(0.16), radius: 8, y: 4)
                .offset(x: centerX - sliderWidth / 2, y: yOffset)
        }
    }

    private func fallbackGlassBase(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.black.opacity(0.14))
            .frame(width: width, height: fallbackBarHeight)
    }

    private func selectedTabCenter(width: CGFloat) -> CGFloat {
        guard width > 0,
              let index = AppTab.allCases.firstIndex(of: selectedTab) else {
            return 0
        }

        let tabWidth = width / CGFloat(AppTab.allCases.count)
        return tabWidth * (CGFloat(index) + 0.5)
    }

    private func selectedSliderWidth(tabWidth: CGFloat) -> CGFloat {
        let baseWidth = max(tabWidth - 8, 46)
        guard dragLocationX != nil else { return baseWidth }
        return min(tabWidth + 10, baseWidth + 14)
    }

    private func clampedSliderCenter(_ centerX: CGFloat, width: CGFloat, sliderWidth: CGFloat) -> CGFloat {
        guard width > 0 else { return centerX }
        let halfWidth = sliderWidth / 2
        return min(max(centerX, halfWidth), width - halfWidth)
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
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MiniPlayerBar: View {
    @Environment(AudioPlayerModel.self) private var audio

    var body: some View {
        if let current = audio.current {
            HStack(spacing: 12) {
                Button {
                    audio.expanded = true
                } label: {
                    HStack(spacing: 12) {
                        AsyncImageCover(urlString: current.coverUrl, systemImage: "headphones")
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
            .padding(8)
            .glassSurface(cornerRadius: 14, interactive: true)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PlaybackCircleIcon: View {
    let isPlaying: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: max(8, size * 0.22), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Brand.red, Color(red: 0.92, green: 0.09, blue: 0.10)],
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
                    .fill(.white.opacity(0.10))
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
