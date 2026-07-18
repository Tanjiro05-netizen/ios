# App Store Connect metadata — iOS 1.0

Status: submission draft for the current TestFlight-first build.

Anything marked `REPLACE BEFORE SUBMISSION` requires account-holder
information. The public pages use GitHub Pages and do not require a purchased
domain. Do not submit placeholder contact details.

## App record

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | MarxistInfo |
| Subtitle | Marxist Library & Audio |
| Primary language | English (U.S.) |
| Bundle ID | `com.marxist.forum` |
| SKU | `marxist-forum-ios-001` |
| Version | `1.0` |
| Build | `1` |
| Primary category | Books |
| Secondary category | Education |
| Price | Free |
| Made for Kids | No |
| Copyright | `© 2026 Andreas Kurz` |
| License agreement | Apple's standard EULA |

### Content rights

Proposed answer: **Yes, this app contains or accesses third-party content.**

Before submission, confirm that every distributed book, audiobook, cover,
translation, and Substack article is public domain, licensed, or used with the
rightsholder's permission. Keep a private rights/source register that can be
provided to App Review if requested.

## Public URLs

The required pages must be publicly reachable over HTTPS without an account,
redirect loop, or region restriction. These paths will become live after the
repository's GitHub Pages source is set to the `docs/` folder on `main`.

| App Store Connect field | Value |
| --- | --- |
| Privacy Policy URL | `https://tanjiro05-netizen.github.io/ios/privacy.html` |
| Support URL | `https://tanjiro05-netizen.github.io/ios/support.html` |
| User Privacy Choices URL | Optional: `https://tanjiro05-netizen.github.io/ios/account-and-data.html` |
| Marketing URL | Optional: `https://tanjiro05-netizen.github.io/ios/` |

The additional Terms page is
`https://tanjiro05-netizen.github.io/ios/terms.html`. A custom
Terms/EULA URL is not required by App Store Connect: Apple's standard EULA is
already selected above. The page can still explain the account-backed service
in plain language.

Before submission, replace the visible operator/contact placeholders in
`docs/privacy.html`, `docs/support.html`, and `docs/terms.html` with the final
legal operator identity and a working private support email. The
account-and-data page explains account deletion, data access/correction, and
what to do if in-app deletion fails.

The hosted privacy policy must accurately cover:

- Supabase authentication and database/storage processing;
- Sign in with Apple, including private relay email addresses;
- name, email address, username/account ID, and optional profile data;
- reading progress and saved quotes synchronized to the signed-in account;
- push-notification device tokens when notifications are enabled;
- local preferences, cached EPUBs, and offline reading metadata;
- the Substack archive/feed and links that open outside the app;
- retention, account deletion, processors, user rights, and contact details;
- no sale of personal data, no third-party advertising, and no cross-app
  tracking, provided those practices remain true at submission time.

The short legal copy currently displayed inside the iOS app is not sufficient
as the hosted policy by itself and must be reconciled with the final webpages.

## App Privacy answers

### Initial question

**Do you or your third-party partners collect data from this app?** Yes.

"Collect" here means transmitted off the device and retained. Local-only guest
data, cached books, and preferences are not included in the label.

### Data types to select

| Data type | Collected for | Linked to identity | Used for tracking | Why |
| --- | --- | --- | --- | --- |
| Contact Info → Name | App Functionality | Yes | No | Apple-provided name or chosen username/profile name |
| Contact Info → Email Address | App Functionality | Yes | No | Authentication, account recovery, and private relay support |
| Identifiers → User ID | App Functionality | Yes | No | Supabase account ID and username |
| Identifiers → Device ID | App Functionality | Yes | No | APNs push token tied to the signed-in account |
| Usage Data → Product Interaction | App Functionality | Yes | No | Synced book/chapter position and reading progress |
| User Content → Other User Content | App Functionality | Yes | No | User-saved quote/highlight text and its source metadata |

For every selected data type:

- Third-Party Advertising: No
- Developer's Advertising or Marketing: No
- Analytics: No
- Product Personalization: No
- App Functionality: Yes
- Other Purposes: No
- Linked to the user's identity: Yes
- Used for tracking: No

Do **not** select the following for this build unless the implementation or
production services change before submission:

- Payment Info or Purchase History — StoreKit handles payment outside the app,
  and the app does not retain transaction history in Supabase.
- Search History — searches are not retained off device.
- Browsing History — the app does not retain external browsing history.
- Location, Contacts, Health, Fitness, Financial Info, Photos/Videos, Audio
  Data, Diagnostics, or Advertising Data.
- Sensitive Info — the current iOS release does not ask the user to provide a
  political-opinion/ideology field. Reassess this if profile editing adds it.

Privacy answers must be rechecked if analytics, crash reporting, advertising,
forum posting, profile uploads, or a new third-party SDK is enabled.

## Age rating answers

Recommended calculated/override target: **16+ on iOS 26 and later**. Older OS
versions may display Apple's corresponding legacy rating. This conservative
recommendation reflects the library's recurring discussion of political
strife, revolution, war, repression, and other mature historical themes.

### In-app controls

| Question | Answer |
| --- | --- |
| Parental controls | No |
| Age assurance | No |

### Capabilities

| Question | Answer |
| --- | --- |
| Unrestricted web access | No — article links open through the system; the app is not a general browser |
| User-generated content | No — the forum is disabled in this release |
| Messaging and chat | No |
| Advertising | No |
| Social media capabilities | No — no active social feed, amplification, or interaction with user posts |

### Content frequency

| Content descriptor | Answer |
| --- | --- |
| Profanity or crude humor | Infrequent |
| Horror or fear themes | None |
| Alcohol, tobacco, or drug use or references | Infrequent |
| Medical or treatment information | None |
| Health or wellness topics | None |
| Mature or suggestive themes | Frequent — political strife and mature historical subjects |
| Sexual content or nudity | None |
| Graphic sexual content and nudity | None |
| Cartoon or fantasy violence | None |
| Realistic violence | Infrequent — textual historical discussion |
| Prolonged graphic or sadistic realistic violence | None |
| Guns or other weapons | Infrequent — textual historical references |
| Gambling | No |
| Simulated gambling | None |
| Contests | None — there are no quizzes or competitive activities in this release |
| Loot boxes | No |

Age category and override:

- Made for Kids: No
- Override: Not Applicable if App Store Connect calculates 16+
- If the questionnaire calculates a lower rating, consider overriding to 16+
  so the product page matches the intended audience and subject matter.

Re-answer the capabilities section before enabling the future forum. An active
forum would change User-Generated Content, Messaging/Chat, Social Media, and
possibly content-frequency answers.

## Export compliance

The app uses standard HTTPS/TLS and Apple/Supabase authentication through
system and published cryptographic APIs. It does not implement proprietary or
non-standard encryption.

Proposed submission position:

| Question | Answer |
| --- | --- |
| Does the app use encryption? | Yes, only standard/exempt encryption for HTTPS and authentication |
| Does it implement proprietary or non-standard cryptographic algorithms? | No |
| Does it implement non-exempt encryption independently of Apple's operating system? | No |
| Is export-compliance documentation expected? | No, based on the current implementation; confirm during App Store Connect's questionnaire |

`ITSAppUsesNonExemptEncryption` is already set to `NO` in `Info.plist`. Reassess
this answer if VPN, secure messaging, custom cryptography, or encrypted file
sharing is later added. Export classification is ultimately the account
holder's legal responsibility.

## Product-page copy

### Promotional text

Read classic texts, listen to audiobooks, save quotes, and continue where you
left off across devices — all in one focused Marxist study app.

### Description

MarxistInfo brings a focused library of Marxist theory, history, and analysis
to iPhone and iPad.

Read books in a native EPUB reader, open available PDFs, and save titles for
offline study. Your reading progress can follow your signed-in account across
devices, while guest mode keeps local reading available without requiring an
account.

Listen to audiobooks with chapter navigation, playback-speed controls,
background audio, and system Now Playing support. Browse and search the bundled
Substack archive, save passages to your quote notebook, and search across books,
audio, and articles from one place.

Features:

- Curated books covering theory, history, political economy, and more
- Native EPUB reading with themes, text sizing, chapter navigation, and offline access
- PDF access when a title includes a PDF edition
- Audiobooks with background playback and chapter controls
- Searchable articles and archive content
- Quote notebook and cross-device reading progress
- Sign in with Apple, email sign-in, or guest browsing
- No third-party advertising or cross-app tracking

The community forum is under construction and is not an active social feature
in this version.

### Keywords

`marxism,books,library,audiobooks,theory,history,politics,reading,archive,study`

### What's New — version 1.0

Welcome to the first iOS release of MarxistInfo: read and download books,
listen to audiobooks, browse the article archive, save quotes, and synchronize
reading progress with your account.

## Screenshots

Upload six portrait screenshots for each supported device class. Do not include
the disabled forum, empty error states, placeholder legal text, unavailable
StoreKit products, personal email addresses, or real user data.

### iPhone

Use a 6.9-inch simulator such as iPhone 17 Pro Max and export one accepted
portrait size, preferably the simulator's native `1260 × 2736`, `1290 × 2796`,
or `1320 × 2868` pixels. App Store Connect accepts one to ten screenshots.

| Order | Screen | Suggested caption |
| --- | --- | --- |
| 1 | Library home with real covers and Continue Reading | A library built for serious study |
| 2 | EPUB reader showing a clean chapter | Read without distractions |
| 3 | Book detail/offline download state | Keep essential texts available offline |
| 4 | Audiobook player with chapters | Listen wherever you are |
| 5 | Substack archive/article reader | Essays and analysis in one place |
| 6 | Quote notebook or global search | Save ideas. Find them again. |

### iPad

The Xcode target currently supports iPad, so a 13-inch iPad screenshot set is
required. Capture the same six screens at `2064 × 2752` or `2048 × 2732`
portrait. If iPad is not intended for version 1.0, remove iPad from the target
before uploading the first build instead of submitting an unreviewed layout.

## App Review information

| Field | Value |
| --- | --- |
| Contact first name | `Andreas` |
| Contact last name | `Kurz` |
| Contact phone | `REPLACE BEFORE SUBMISSION` |
| Contact email | `Modernmarxist05@gmail.com` |
| Sign-in required | No — reviewers can choose guest browsing |
| Review account | Optional but recommended: `REPLACE BEFORE SUBMISSION` |

### Review notes draft

The app can be reviewed without an account by selecting guest browsing. Sign in
with Apple and email authentication enable cloud reading progress, saved quotes,
push notifications, and account deletion. Account deletion is available from
More → Profile → Delete Account.

The Forum tab intentionally displays an under-construction page. Forum posting,
messaging, quizzes, contests, and social-media functionality are not enabled in
version 1.0. No moderation workflow needs to be exercised for this build.

If StoreKit support products are not configured for version 1.0, the Support
entry and unavailable purchase screen must be hidden before submission. Do not
reference purchases in the review notes or privacy answers for that build.

## Final metadata checks

- Replace every `REPLACE BEFORE SUBMISSION` value.
- Publish and test all legal/support URLs on a signed-out device.
- Reconcile the in-app legal screens with the hosted policies.
- Verify content rights for every included or remotely delivered work.
- Confirm the privacy label against production Supabase tables, Storage, Edge
  Functions, and every included SDK.
- Confirm the age-rating answers against the exact content shipped in the
  submitted build.
- Hide the StoreKit support route unless the products are configured and being
  submitted with the app.
- Capture clean iPhone and iPad screenshots from release-quality data.
- Do not advertise the forum, quizzes, messaging, or other future features.

## Apple references

- App privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Privacy data definitions: https://developer.apple.com/app-store/app-privacy-details/
- Age-rating questionnaire: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- Age-rating values: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
- Export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
