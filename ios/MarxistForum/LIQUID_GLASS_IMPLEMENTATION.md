# Liquid Glass implementation record

**Date:** 2026-07-09
**Scope:** Native SwiftUI iOS client in `ios/MarxistForum`. The Expo/React Native Android client was not changed because Liquid Glass is an Apple-platform material and the reported implementation lives in the iOS target.

## Result

The app now uses the native iOS 26 Liquid Glass API for its shared card/panel treatment, bottom tab bar, key library cards, login panel, and custom icon toolbar buttons. On iOS 18–25, it preserves functionality and presents a deliberately translucent material fallback rather than the previous opaque dark panels.

The deployment target remains iOS 18.0. This is intentional: `glassEffect` is available only on iOS 26+, so lowering the deployment target would not make native Liquid Glass appear on an older device. Availability checks select the appropriate implementation at runtime.

## Loading performance update (2026-07-13)

The archive now keeps short-lived in-memory results for books, book details, audio, Substack, and forum content. Library categories and books load concurrently, and the initial empty-search task no longer fires a duplicate books request. Spotlight indexing and widget publication run after the first frame rather than holding the loading state open. Restored authentication renders immediately while the non-critical profile refresh continues in the background. Substack displays its bundled archive immediately and refreshes the live feed asynchronously. Cover requests are downsampled to the size of the UI they serve.

## Apple research used

The implementation follows Apple's current guidance:

- [Liquid Glass technology overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass): system components pick up the material when built with the current SDK; custom controls can adopt it directly.
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): use `glassEffect(_:in:)` on custom surfaces, apply it after visual/layout modifiers, use `.interactive(_:)` for touch-responsive controls, and use `GlassEffectContainer` only to coordinate multiple native glass effects.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): avoid an excessive number of simultaneous custom effects because that harms rendering performance.
- [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials): use clear glass when underlying content is visually rich, and regular glass when legibility requires stronger background treatment.

## Exact source changes

### `Sources/Components.swift`

#### 1. Shared `glassSurface` modifier

**Before:** iOS 26 received `.glassEffect`, but iOS 18–25 received `Brand.panel.opacity(0.72)`, which reads as an opaque dark box.

**After:** iOS 26 uses the native effect with a consistent one-point edge. Earlier systems use `.ultraThinMaterial` under a much lighter panel tint and edge. The `interactive` argument is passed directly to `Glass.interactive(_:)`, so only callers that opt in receive touch-responsive material.

```swift
extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(Brand.panel.opacity(0.42), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}
```

The overlay is explicitly non-hittable so it cannot block buttons or gestures inside a glass surface.

#### 2. `ScreenBackground`

**Before:** three nearly black gradient stops plus a `0.18` black overlay provided too little color, contrast, or depth for a refractive material to reveal.

**After:** the background includes a red-tinted gradient, five diffuse red/white light sources, and a reduced `0.12` black finish. The two lower light sources are positioned behind the bottom navigation bar so its glass has real color and luminance to refract while the library content loads. These light sources are behind every surface and do not affect interaction.

```swift
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.034, blue: 0.038),
                    Color(red: 0.085, green: 0.047, blue: 0.050),
                    Color(red: 0.025, green: 0.026, blue: 0.032)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Brand.red.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -140, y: -260)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 150, y: 40)
            Circle()
                .fill(Brand.red.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: 330)
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -170, y: 230)
            Circle()
                .fill(Brand.red.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 150, y: 250)
            Rectangle()
                .fill(.black.opacity(0.12))
        }
        .ignoresSafeArea()
    }
}
```

#### 3. Navigation bar

The iOS 26 compact layout now uses the system `TabView`, allowing the platform to own the Liquid Glass navigation geometry and interaction. Library, Audio, Substack, and Forum remain visible; Alerts and Profile are intentionally available through the system **More** destination. This removes the fragile custom slider/union treatment entirely. The iOS 18–25 fallback retains a compact custom bar with the same six destinations.

For the fallback, the tab bar uses this layered material instead of an opaque panel:

```swift
.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
.background(Brand.panel.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
.overlay {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.09), lineWidth: 1)
}
```

The custom fallback base uses `.clear` instead of `.regular` deliberately. Apple describes regular glass as darkening dark backgrounds for legibility, which is why the earlier live screenshot still looked like a black capsule. Text-heavy card and panel surfaces continue to use regular glass.

### `Sources/Screens.swift`

#### 4. Login panel

`loginPanelChrome()` no longer implements a separate opaque panel. Its complete implementation is now:

```swift
func loginPanelChrome() -> some View {
    self
        .glassSurface(cornerRadius: 14)
}
```

The text-field chrome remains unchanged to retain reliable input contrast.

#### 5. Library and continue cards

The following three button-backed components removed their `Brand.panel.opacity(0.74)` backgrounds and custom `0.06` strokes, then adopted the shared interactive surface:

- `ContinueReadingCard`
- `ContinueListeningCard`
- `BookCard`

Each now ends with this exact code after its existing padding:

```swift
.glassSurface(cornerRadius: 12, interactive: true)
```

They are interactive because their parent views are buttons. This gives native iOS 26 feedback without adding another effect to non-interactive content.

#### 6. Icon toolbar controls

The custom icon toolbar buttons below no longer override system glass behavior with `.buttonStyle(.plain)`. Each now uses:

```swift
.glassButtonStyle()
```

Updated controls:

- Library settings (`gearshape`)
- Substack external link (`safari`)
- Forum create thread (`square.and.pencil`)

Text-only `Done` actions and non-toolbar controls retain their existing button styles; they are not icon glass controls and were intentionally not changed.

### `Sources/MarxistForumApp.swift`

#### 7. Global-search icon toolbar control

The global search (`magnifyingglass`) button changed from:

```swift
.buttonStyle(.plain)
```

to:

```swift
.glassButtonStyle()
```

`glassButtonStyle()` already selects `.glass` with a 9-point rounded rectangle on iOS 26 and `.bordered` on iOS 18–25. The accessibility label remains `Global search`.

## What was deliberately not changed

- `IPHONEOS_DEPLOYMENT_TARGET` remains `18.0` in the Xcode project. Raising it would remove older-device support but would not improve the iOS 26 native effect.
- Existing small list rows and dense audio/reader content that still use panel colors were not converted indiscriminately. Apple cautions against too many simultaneous custom glass effects; the implementation favors high-level cards, panels, navigation, and controls where glass communicates hierarchy.
- No Android source files, app data, navigation paths, business logic, accessibility labels, or animation timing were changed.

## Verification

The app was built successfully with the installed iOS 26.4 SDK for the generic iOS Simulator destination:

```sh
xcodebuild \
  -project ios/MarxistForum/MarxistForum.xcodeproj \
  -scheme MarxistForum \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

For final visual QA, run the app on an iOS 26 simulator or device to inspect native refraction, then once on iOS 18–25 to confirm the material fallback. Verify the login panel, Library cards, global-search icon, settings icon, bottom tab bar, and tab selection animation in both appearances.
