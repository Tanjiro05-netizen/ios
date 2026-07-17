# MarxistInfo for iOS

This repository contains the native SwiftUI iOS app, its widget extension, shared Supabase backend definitions, and the static legal/support site used for App Store distribution.

## iOS project

Open `ios/MarxistForum/MarxistForum.xcodeproj` in Xcode and use the `MarxistForum` scheme.

- Deployment target: iOS 18 or later
- Primary validation target: iOS 26.4
- App bundle identifier: `com.marxist.forum`
- Widget bundle identifier: `com.marxist.forum.widgets`

Release and account setup instructions are in `ios/MarxistForum/TESTFLIGHT_RELEASE_CHECKLIST.md`.

## Repository layout

- `ios/MarxistForum/` — native iOS app, widget, resources, and tests
- `supabase/` — shared backend functions and database migrations
- `docs/` — privacy, support, terms, and account-deletion pages

The discontinued Android/React Native client is intentionally not part of this repository.
