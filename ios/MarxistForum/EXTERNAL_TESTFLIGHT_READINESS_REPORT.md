# MarxistInfo external TestFlight readiness report

Assessment date: 30 July 2026

Release candidate: 1.0 (2)

Branch: `codex/phi-dialectics-course-import`

## Executive result

The application now builds in Release for iPhone and iPad, creates a signed
generic-device archive, preserves the Forum, and passes the automated content
and bundle gate. The archive is suitable for local device validation, but the
release is **not yet ready to invite external testers**. The remaining gates
require production credentials, App Store Connect work, academic/rightsholder
decisions, public hosting, and physical-device/accessibility validation.

The archive produced during this assessment is:

- `/tmp/MarxistInfo-1.0-2.xcarchive`
- Version `1.0`, build `2`
- Bundle identifier `com.marxist.forum`
- Team identifier `LA7GTT4246`
- Development signed, with `get-task-allow = true`

An Apple Distribution certificate/profile and an App Store export/upload are
still required. This development-signed archive must not be presented as the
uploaded TestFlight build.

## Verified implementation

- Beta feature gates keep the Forum under construction and hide unfinished
  submissions, examiner grading, formal course results, videos, tips, automatic
  push prompts, and email account creation.
- Sign in with Apple exchanges authorization codes server-side. Refresh tokens
  are encrypted for revocation, and deletion can queue a safe retry if Apple is
  temporarily unavailable.
- Account deletion removes cloud account data and erases account-scoped local
  Study Center attempts, progress, reviews, saved items, achievements, and
  drafts.
- Only questions in the distinct `reviewed` state can enter scored selection.
  Corrected, flagged, imported, and draft records remain canonical and
  browseable without being silently treated as approved.
- The privacy manifest is present in the built app and was scanned during both
  Release build and archive creation.
- The release validator found no restricted marking guide, examiner PDF,
  answer-key export, source archive, course packaging ZIP, or Jena asset in the
  built simulator app or device archive.
- In-app and hosted legal copy describes local Study data, Sign in with Apple,
  account deletion, beta limitations, and the separation between learning
  progress and accredited academic results.

## Shipped academic content inventory

- 2 complete courses: PHI111 and PHI211
- 1 learning path: PHI111 → PHI211
- 26 modules
- 221 authored sections
- 52 placed exercises
- 26 module quizzes
- 246 course-package quiz questions
- 11 assignments
- 38 final-examination prompts
- 2 restricted marking-guide metadata records; restricted guide files are not
  shipped to learners
- 529 canonical catalogue questions, referenced by stable ID

## Build, test, and simulator evidence

- Final Release simulator build: passed on iPad Pro 13-inch (M5), iOS 26.5.
- Earlier Release simulator build: passed on iPhone 17 Pro Max, iOS 26.5.
- Generic iOS device archive: passed and validated.
- Static release/package validator: passed against source, the final simulator
  app, and the device archive.
- Final clean unit suite: 60 tests passed with zero failures against the final
  source.
- End-to-end course journey: passed from guest mode through Study Center,
  PHI111 orientation, first authored section, termination, offline relaunch,
  and return to Study Center.
- Forum/legal journey: passed; the Forum remains under construction, Settings
  opens the privacy policy, and the corrected public-policy control is exposed.
- Catalogue journey reached the 529-item catalogue, searched canonical ID
  `B1-C04-MC-013`, and reduced to one result. The run caught and led to fixes for
  the singular result label and stable row accessibility identifier.
- iPad learning-path run rendered both the featured PHI111 course and its
  learning-path card. The automated tap was ambiguous because the title appears
  legitimately twice; the selector is now deterministic.
- Xcode's iOS 26.5 Simulator test service repeatedly failed with Mach error
  `-308` while launching or finalizing subsequent UI-test runners. This is
  recorded as test-infrastructure instability, not as a passing product result.
  The two corrected journeys must be rerun before inviting testers.

Both preserved simulators boot concurrently:

- iPhone 17 Pro Max, iOS 26.5
- iPad Pro 13-inch (M5), iOS 26.5

The three redundant simulator devices were removed. The main verification
DerivedData was removed after the archive was preserved. The final clean unit
run regenerated an 877 MB temporary cache at
`/tmp/codex-marxist-unit-final`; removal was blocked by the execution
environment's approval/usage limit. APFS currently reports 12 GiB available,
so the agreed 15 GiB free-space gate must be restored before upload.

## External blockers

### Academic and rights

- No catalogue question is yet recorded as academically reviewed (`0/529`).
- `B1-C04-MC-013` still requires adjudication.
- PHI111 and PHI211 publication, source-text, citation, and rights statuses need
  genuine reviewer/rightsholder sign-off.
- Library, article, image, audio, animation, and course-source rights registers
  are not complete.

### Production services

- Apply `20260729213124_apple_credential_lifecycle.sql` to production.
- Configure the Apple token-encryption and revocation-retry secrets.
- Deploy `apple-token-exchange`, revised `delete-account`, and
  `retry-apple-revocations`.
- Add a protected retry schedule/runbook and verify RLS in production.
- The Supabase CLI could not establish a usable project-list session during
  this assessment, so none of these production changes are claimed as deployed.
- Supabase Auth does not expose Apple's native server-to-server credential
  notification endpoint; launch-time session validation and user-initiated
  revocation are implemented, but this remains a platform limitation.

### Distribution and App Store Connect

- Install/use valid Apple Distribution signing credentials, export the archive
  for App Store Connect, and upload build 2.
- Confirm build number 2 is unused and complete App Privacy declarations.
- Enter the review phone privately and add required iPhone/iPad screenshots.
- Wait for processing and resolve any signing, entitlement, icon, privacy, or
  export warning.
- Publish the legal site and confirm every public URL returns HTTP 200 while
  signed out.

### Manual quality gates

- Remove the final temporary unit-test build cache and confirm at least 15 GB
  remains free after APFS updates its available-space accounting.
- Rerun the corrected catalogue and PHI111→PHI211 UI journeys after the
  simulator service is stable.
- Test the minimum supported iOS 18 runtime or a physical iOS 18 device.
- Complete physical-device Sign in with Apple, Keychain, deletion, APNs,
  offline download, background audio, and low-memory/interruption tests.
- Complete portrait/landscape, iPad split view, dark mode, VoiceOver, Voice
  Control, 200% Larger Text, contrast, Differentiate Without Color, and Reduce
  Motion validation.
- Profile cold launch, course open, long lesson scrolling, quiz transitions,
  and repeated navigation in Release on a physical device.

## Ship decision

Do not invite external testers yet. The code and content package have crossed
the local build/archive gate, but distribution signing/export, production
account lifecycle deployment, public legal URLs, academic/rightsholder
acceptance, two corrected UI reruns, and physical accessibility/device checks
remain mandatory.
