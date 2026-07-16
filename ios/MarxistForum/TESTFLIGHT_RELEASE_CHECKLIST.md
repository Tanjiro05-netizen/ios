# TestFlight release checklist

The repository contains the app-side implementation. The following external
steps must be completed with the Apple Developer, App Store Connect, and
Supabase accounts before a public or TestFlight build is considered ready.

## Apple Developer and App Store Connect

1. Register `com.marxist.forum` and enable Sign in with Apple, App Groups
   (`group.com.marxist.forum`), and Push Notifications.
2. Confirm the App ID and widget App ID are part of the same team and that
   automatic signing can create distribution profiles.
3. Create the App Store Connect app, upload the archive from the
   `MarxistForum` scheme, and verify the App Icon, privacy URL, support URL,
   age rating, export-compliance answers, and App Privacy declarations.
   Use `APP_STORE_CONNECT_METADATA.md` as the submission draft and replace all
   marked placeholders before entering the metadata.
4. Test on a physical iPhone. Simulator builds cannot validate Apple login,
   APNs delivery, Keychain sharing, or production provisioning.

## Supabase

1. Apply migrations, including `20260714122007_reading_sync.sql`, to
   the production project.
2. Deploy `substack-feed`, `send-push-notification`, and `delete-account`.
3. Enable the Apple Auth provider. Native iOS uses the App ID; configure a
   Services ID/private key as well if the website or Android client will offer
   Apple login.
4. Configure Edge Function secrets. Never put these values in the iOS app:

   - `SUPABASE_SERVICE_ROLE_KEY`
   - `APPLE_TEAM_ID`
   - `APPLE_KEY_ID`
   - `APPLE_CLIENT_ID` (defaults to `com.marxist.forum` for native login)
   - `APPLE_PRIVATE_KEY`
   - `APNS_BUNDLE_ID`
   - `APNS_USE_SANDBOX`
   - `APNS_TEAM_ID`
   - `APNS_KEY_ID`
   - `APNS_PRIVATE_KEY`

5. Verify RLS and Storage policies with a normal authenticated test user. The
   iOS app only contains the public Supabase key.

The Supabase security advisor reports two future quiz/knowledge tables with RLS
disabled: `public.knowledge_quiz_concepts` and
`public.knowledge_scenario_concepts`. They are not used by the current iOS
release and are not a version 1.0 feature blocker. Before any quiz or knowledge
feature is exposed, define its intended read/write policies and then run:

```sql
ALTER TABLE public.knowledge_quiz_concepts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_scenario_concepts ENABLE ROW LEVEL SECURITY;
```

## Account and data acceptance tests

- First Apple authorization persists the supplied display name; later Apple
  authorizations do not erase it.
- Sign out clears the local session but keeps guest/offline reading data.
- Delete Account removes the Supabase auth user, profile, reading progress,
  quotes, push tokens, owned files, and local Keychain/UserDefaults/app-group
  state.
- Reading progress converges between iOS, Android, and web using the Supabase
  user ID and timestamp-based conflict resolution; iOS quote records sync to
  the same account-scoped backend.
- Android and web readers now synchronize chapter progress; quote capture is
  currently available in the native iOS notebook/API, while quote-selection UI
  still needs to be added to the other readers before claiming quote parity.
- A failed deletion leaves the account recoverable and presents a retryable
  error rather than silently signing out.

## Current release scope

- Quizzes, contests, and the related knowledge-learning tables are deferred to
  a later release and must not be advertised in version 1.0 metadata.
- Forum remains disabled until reporting, blocking, filtering, and moderation
  workflows are complete.
- StoreKit support products remain hidden/deferred until App Store Connect
  products are configured and reviewed.
- CloudKit is intentionally not used; Supabase is the canonical backend.
