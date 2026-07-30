# App Store Connect metadata — external TestFlight build 1.0 (2)

This is the submission record for a closed external beta. Values that depend on
the Account Holder are explicitly called out; no invented contact information
or credentials are stored in the repository.

## App record

| Field | Value |
| --- | --- |
| Platform | iOS and iPadOS |
| Name | MarxistInfo |
| Subtitle | Library, Courses & Study |
| Primary language | English (U.S.) |
| Bundle ID | `com.marxist.forum` |
| SKU | `marxist-forum-ios-001` |
| Version | `1.0` |
| Build | `2` — confirm that this is unused before upload |
| Primary category | Education |
| Secondary category | Books |
| Price | Free |
| Made for Kids | No |
| Copyright | `© 2026 Andreas Kurz` |
| License agreement | Apple's standard EULA |

## Public URLs

These pages must return HTTP 200 over HTTPS before inviting external testers.

| App Store Connect field | Value |
| --- | --- |
| Privacy Policy | `https://tanjiro05-netizen.github.io/ios/privacy.html` |
| Support | `https://tanjiro05-netizen.github.io/ios/support.html` |
| Account and data deletion | `https://tanjiro05-netizen.github.io/ios/account-and-data.html` |
| Marketing | `https://tanjiro05-netizen.github.io/ios/` |
| Terms | `https://tanjiro05-netizen.github.io/ios/terms.html` |

The same policy links are available inside the app. The policies explain that
Study Center packages, attempts, review data, written drafts, achievements, and
course progress are local-first and are not uploaded to Supabase in this beta.

## Content rights

Answer **Yes** to third-party content. Rights sign-off is required for every
distributed lesson, quotation, translation, bibliography item, book,
audiobook, cover, article, logo, animation, and course source. The repository's
`CONTENT_RIGHTS_REGISTER.md` records the current status. Draft course content
may be shown to an expert beta cohort for review, but its status must not be
represented as independently certified.

## App Privacy draft

Answer **Yes** to data collection: signed-in library/account data is transmitted
to Supabase and retained. Guest Study Center data, cached books, downloaded
content, local preferences, course progress, quiz attempts, review cards,
assignment drafts, and exam drafts are local-only and are not part of the
privacy label.

| Data type | Purpose | Linked | Tracking | Detail |
| --- | --- | --- | --- | --- |
| Name | App Functionality | Yes | No | Apple-provided or chosen profile name |
| Email Address | App Functionality | Yes | No | Authentication and private relay support |
| User ID | App Functionality | Yes | No | Supabase account identifier and username |
| Device ID | App Functionality | Yes | No | APNs token retained for an account that previously enabled notifications |
| Product Interaction | App Functionality | Yes | No | Synchronized book/chapter reading position |
| Other User Content | App Functionality | Yes | No | Synchronized saved quotations and source metadata |

Push permission is not requested and its controls are hidden, but Device ID is
declared conservatively because an existing account may already have an APNs
token in the account service. Reassess all answers before enabling push,
analytics, crash reporting, forum posting, uploads, or any additional SDK. The
app has no third-party advertising and performs no cross-app tracking.

## Age rating draft

Use a conservative target appropriate to recurring discussion of political
strife, revolution, war, and repression. Proposed target: **16+** where the
current questionnaire supports it.

| Capability | Answer |
| --- | --- |
| User-generated content | No — the forum is under construction and disabled |
| Messaging or chat | No |
| Advertising | No |
| Social-media features | No |
| Unrestricted web access | No |
| Contests | None — academic quizzes have no prizes, wagering, or public competition |
| Loot boxes or simulated gambling | No |
| Mature themes | Frequent, in an academic/historical context |
| Realistic violence | Infrequent textual historical discussion |
| Weapons | Infrequent textual historical references |

## Export compliance

The app uses published system and SDK cryptography for HTTPS, authentication,
and local/service data protection. It does not implement proprietary or
non-standard cryptography. `ITSAppUsesNonExemptEncryption` is `NO`; confirm the
standard/exempt-encryption answers during upload.

## Product-page copy

### Promotional text

Read primary texts, follow substantial courses, use study and reading guides,
and continue learning offline in one focused Apple-native study app.

### Description

MarxistInfo combines a native reading library with a structured Study Center
for serious, self-paced learning on iPhone and iPad.

The Study Center includes the complete PHI111 course, *Hegelian Dialectics I:
Being, Essence, Concept*, and its sequel PHI211, *Marx's Dialectical Method*.
Each course preserves its ordered modules and lessons, long-form teaching text,
embedded exercises, study and reading guides, reading lists, assignments,
public rubrics, glossary, bibliography, and final candidate examination paper.
PHI211 is linked as the recommended sequel to PHI111.

The separate question catalogue, practice, daily-learning, review, progress,
XP, and streak systems are included as local-first learning tools. Scored
questions remain unavailable until their answers and citations have received
the explicit academic-review status required by the app. Written submissions,
examiner grading, formal course grades, and certificates are not enabled in
this beta; complete candidate papers and public rubrics remain available for
study.

The library provides native EPUB reading, offline downloads, available PDFs,
audiobooks with chapter controls, a searchable article archive, saved
quotations, and optional signed-in reading synchronization. Guest mode keeps
library and course study available without an account.

Features:

- Two complete, reading-centred dialectics courses with 26 ordered modules
- 221 course sections and 52 exercises in their intended lesson positions
- Study Guides, Reading Guides, primary-source reading plans, glossaries, and bibliographies
- 529-question canonical catalogue, with review status shown transparently
- Local course progress, review tools, achievements, XP, and optional streaks
- Complete read-only candidate assignments, rubrics, and final examination papers
- Native EPUB and audio reading tools with offline use
- Sign in with Apple, existing-account email sign-in, or guest browsing
- No third-party advertising or cross-app tracking

The community forum remains under construction and unchanged. Educational
videos, written submissions, examiner grading, tips, and unreviewed scored
assessments are hidden for this beta.

### Keywords

`marxism,courses,study,philosophy,dialectics,books,education,reading,hegel,marx`

### What's New — 1.0

Welcome to MarxistInfo: use the native reading library and begin two complete,
reading-centred courses in Hegelian and Marxian dialectics. Follow lessons,
guides, exercises, local progress, and complete candidate assessment papers on
iPhone or iPad.

## External TestFlight information

### Beta description

This closed expert beta tests the MarxistInfo library and new Study Center,
including two full courses, lesson navigation, embedded exercises, guides,
question catalogue, local progress, review tools, offline continuation, and
read-only formal assessment materials. It does not enable the forum, tips,
videos, written submissions, examiner grading, certificates, or unreviewed
scored questions.

### What to Test

1. Choose **Continue as Guest**, open Study Center, and begin PHI111.
2. Check module and section order, long-form lesson rendering, exercises, Study
   Guide, Reading Guide, glossary, bibliography, and progress persistence.
3. Follow the recommended sequel from PHI111 to PHI211.
4. Search and filter the 529-question catalogue and confirm review status is
   clear; report any disputed answer, citation, duplicated heading, or missing
   passage using its stable question/content ID.
5. Open assignments and final examinations and confirm they are complete,
   readable candidate papers without submission, timer, examiner, or grade UI.
6. Relaunch offline and confirm the current course and reading position remain.
7. Test iPhone and iPad layouts, Larger Text, VoiceOver, Reduce Motion, and dark
   mode. Confirm the Forum tab still shows its under-construction screen.

Feedback email: `Modernmarxist05@gmail.com`

### App Review information

| Field | Value |
| --- | --- |
| Contact | Andreas Kurz |
| Contact email | `Modernmarxist05@gmail.com` |
| Contact phone | Enter the verified Account Holder phone directly in App Store Connect; it is intentionally not stored here |
| Sign-in required | No |
| Review path | Choose **Continue as Guest** |
| Review account | Not required for core review; provide a non-expiring existing-account credential privately only for cloud-reading tests |

Review notes: the app is fully reviewable in guest mode. Sign in with Apple and
existing-account email login are only needed for account-backed reading sync.
Account deletion is in Profile → Delete Account. The Forum tab intentionally
shows an under-construction page. Academic scoring is review-gated; formal
assessment materials are read-only. No purchase surface is exposed.

## Screenshot plan

Capture clean iPhone 17 Pro Max and iPad Pro 13-inch portrait sets from the
release build. Prioritize Library, PHI111 landing/syllabus, a long lesson with
an exercise, Study/Reading Guide, question catalogue with transparent QA state,
and PHI211 sequel navigation. Do not show personal data, disabled forum, tips,
examiner screens, unavailable videos, or developer scaffolding.

## Account Holder checks before upload

- Confirm build `2` is unused, then upload it.
- Enter and verify the review phone number directly in App Store Connect.
- Confirm the feedback email and legal operator identity.
- Complete the final rights and academic sign-offs for anything presented as approved.
- Confirm App Privacy and age-rating answers against the archived binary.
- Complete EU DSA trader status before later public EU distribution; it is not
  itself required solely for TestFlight distribution.
