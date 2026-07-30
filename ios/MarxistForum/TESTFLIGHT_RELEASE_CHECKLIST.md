# MarxistInfo external TestFlight release checklist

Target: closed external cohort, iPhone and iPad, version 1.0 build 2.

## Release scope locked in code

- [x] Forum preserved and disabled behind its existing under-construction view.
- [x] Written assignment/exam submissions hidden; candidate papers and public rubrics remain readable.
- [x] Examiner desks, marking, formal grades, certificates, and timed course finals hidden.
- [x] Educational-video navigation hidden until complete sourced content exists.
- [x] StoreKit tips, automatic push prompts, notification preferences, and unfinished email-account creation hidden.
- [x] Unreviewed or flagged questions excluded from scored sessions without deleting canonical records.
- [x] Course and Study progress remains local-first; no Study records are moved to Supabase.

The feature switches are centralized in `AppFeatureFlags`. Re-enabling any item
requires its own product, security, academic, and end-to-end validation.

## Reproducible application validation

- [x] All unit tests pass from a clean generated build directory.
- [x] Release builds pass on the preserved iPhone 17 Pro Max and iPad Pro 13-inch simulators.
- [x] Signed generic-device development archive succeeds.
- [ ] Apple Distribution signing and App Store export succeed.
- [x] Archive contains `PrivacyInfo.xcprivacy` and the expected app/widget entitlements.
- [x] Archive contains no restricted marking guide, examiner PDF, source archive, answer-key export, Jena asset, or packaging ZIP.
- [x] Course import report matches the shipped package hash and canonical counts.
- [ ] Build number `2` is confirmed unused in App Store Connect.
- [ ] Remaining free disk space stays at or above 15 GB after cache regeneration and cleanup (currently 12 GiB; final temporary unit-test cache removal was blocked).

## Academic and content acceptance

- [x] Both complete source courses and their PHI111 → PHI211 relationship are represented.
- [x] Stable source IDs are retained and importer integrity checks are reproducible.
- [x] The 529-question canonical catalogue remains intact and browseable.
- [x] A distinct `reviewed` QA state exists; `corrected` is not treated as academic approval.
- [ ] Academic reviewers approve questions before they can enter scored selection.
- [ ] `B1-C04-MC-013` is adjudicated.
- [ ] PHI111/PHI211 publication, source-text, citation, and rights statuses receive genuine sign-off.
- [ ] Rights register is completed for all library, article, audio, image, animation, and course sources.

Never edit review-status fields simply to pass a release check. The beta may
show draft material transparently to an expert cohort, but no formal academic
result is issued from unapproved content.

## Supabase and account lifecycle

Supabase remains limited to authentication and existing account-backed library
services. Do not add course content, questions, grades, or Study progression.

- [ ] Apply `20260729213124_apple_credential_lifecycle.sql` to production.
- [ ] Deploy `apple-token-exchange`, revised `delete-account`, and `retry-apple-revocations`.
- [ ] Configure `APPLE_TOKEN_ENCRYPTION_KEY` as a random 32-byte base64 secret.
- [ ] Configure `APPLE_REVOCATION_RETRY_SECRET` and invoke the retry function from a protected schedule or manual runbook.
- [ ] Confirm existing Apple client-secret inputs: `APPLE_TEAM_ID`,
  `APPLE_KEY_ID`, `APPLE_CLIENT_ID`, and `APPLE_PRIVATE_KEY`.
- [ ] Verify ordinary anon/authenticated roles cannot read encrypted Apple refresh tokens or retry records.
- [ ] Test Apple code exchange, encrypted refresh-token storage, token revocation, and deletion on a physical device.
- [ ] Confirm deletion completes when Apple is unavailable and records a safe retry/manual-review item.
- [ ] Test complete subject-scoped local Study/reading erasure after cloud deletion.
- [ ] Verify RLS for existing profiles, reading progress, quotations, push tokens, and owned files.

Supabase Auth does not expose an Apple server-to-server credential-revocation
notification endpoint. That lifecycle signal remains an external platform gap;
the app restores/validates its current session on launch, while user-initiated
deletion uses the stored Apple refresh token.

## Public legal site and metadata

- [ ] Marketing, privacy, support, account/data, and terms URLs all return HTTP 200 signed out.
- [x] Hosted and in-app policy text covers local Study records and deletion.
- [x] Product identity is MarxistInfo; Jena preview branding is not used.
- [x] Metadata describes courses, guides, question catalogue, review tools, XP/streaks, and read-only exams accurately.
- [x] Contests remain `None`; academic practice has no prize or public competition.
- [x] Closed-beta description, What to Test, feedback email, and guest path are recorded.
- [ ] Account Holder enters a verified review phone in App Store Connect.
- [ ] If cloud-reading tests are required, a non-expiring existing-account credential is supplied privately.

## Device, UI, and accessibility

- [ ] Guest → Study Center → PHI111 → lesson → exercise → module quiz/progress journey.
- [ ] PHI111 recommended sequel opens PHI211.
- [ ] Question catalogue search/filter and stable ID reporting.
- [x] Offline relaunch and course/reading continuation.
- [x] Forum under-construction screen remains unchanged.
- [x] Legal policy route and public-policy control are reachable.
- [ ] iPhone/iPad portrait and landscape, iPad split view, dark mode, interrupted download, and low-memory relaunch.
- [ ] VoiceOver, Voice Control, 200% Larger Text, contrast, Differentiate Without Color, and Reduce Motion.
- [ ] Physical-device Apple sign-in, Keychain, deletion, provisioning, and background audio.
- [ ] Minimum iOS 18 run on an installed runtime or physical device.
- [ ] Release-mode physical-device profiling: cold launch, course open, long lesson scroll, quiz transition, repeated navigation.

## App Store Connect processing and rollout

- [ ] Reconcile Xcode's archived privacy report with App Privacy declarations and bundled SDK manifests.
- [ ] Confirm archive processing has no entitlement, icon, privacy-manifest, export, or signing warning.
- [ ] Upload screenshots for both supported device classes.
- [ ] Invite a small expert cohort without a public TestFlight link.
- [ ] Ask specifically about academic accuracy, missing text, answer keys, navigation, iPad layout, accessibility, offline reliability, and progress preservation.
- [ ] Log and triage every reproducible crash, data-loss event, course-loading hang, and broken core journey before expanding the cohort.

## Ship gate

Invite external testers only after the release archive, automated/core journeys,
public legal URLs, restricted-material inspection, deletion implementation, and
visible beta-scope checks pass. Academic/right statuses must be truthful: only
content with explicit sign-off may be described or scored as approved.
