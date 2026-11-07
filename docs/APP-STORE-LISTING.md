# DockGrove App Store listing and submission form

Everything App Store Connect asks for to publish the Mac app, filled in as far as the repository allows.

Prepared 2026-11-06 against commit `9786d30`. Apple sources were checked the same day and are listed in [section 12](#12-sources). Nothing here was entered into App Store Connect. The App Store Connect state below comes from `docs/IN-APP-PURCHASES.md`, which calls itself dated evidence, so check it in the account.

Status words used in this document:

- `ready`: the value can be entered as written.
- `owner`: only the owner can supply or decide it.
- `blocked`: the value depends on work that isn't finished, such as a build, a live page or an audit.

## 1. Read this first

Four problems decide whether this listing can ship. The first needs an owner decision. The other three are review risks that good metadata can't fix.

### 1.1 Price and model conflict: owner decision

The repository describes two incompatible offers. This document doesn't choose between them.

| | App Store record | `docs/COMMERCE.md` and `/terms` |
| --- | --- | --- |
| Sale | Free app with two in-app purchases | Direct sale through Stripe |
| Price | Plus $4.99, Full Access $9.99 | $9.99 once |
| Devices | Every Mac on the buyer's Apple Account | Three personal Macs |
| Coverage | Permanent non-consumable | Major version 1 and its maintenance updates |
| Unlock | StoreKit, `DOCKGROVE_STOREKIT` | License key, `DOCKGROVE_COMMERCIAL` |
| App Store | Draft records exist | "App Store publication is not part of this release" |

`docs/COMMERCE.md` also says the StoreKit route is "not the selected release route", and `docs/IN-APP-PURCHASES.md` says "No App Store submission is requested". Publishing on the App Store reverses a documented decision, so that needs an explicit owner call.

Options:

| Option | App Store price | What changes |
| --- | --- | --- |
| A. Free with in-app purchases | Free, Plus $4.99, Full Access $9.99 | Matches the existing records. Differs from the $9.99 direct offer, and a buyer could pay $4.99 for less. |
| B. Paid up front | $9.99, no in-app purchases | Closest to the direct offer. Needs a build with no tiers, and the two drafts go unused. |
| C. Direct only | No listing | This document is parked. |

Whichever A or B is chosen:

- The three-device limit can't be carried over. Guideline 2.4.5(vi) bars license keys and custom copy protection in Mac App Store apps, and 3.1.1 bars unlocking features with license keys.
- If direct sales continue alongside the App Store, `/terms`, the website pricing and any FAQ need to describe both.

Copy in section 2 is written for option A, with a swap paragraph for option B.

### 1.2 Review risk: Dock replacement

Replacement mode writes `autohide` and `autohide-delay` to `com.apple.dock` and restarts the system Dock (`app/Sources/DockBehavior.swift`). These rules apply:

- 2.5.8: "Apps that create alternate desktop/home screen environments will be rejected."
- 2.5.9: apps that "alter or disable the functions of standard switches ... or other native user interface elements or behaviors will be rejected."
- 5.2.5: don't create an app that "appears confusingly similar to an existing Apple product, interface (such as Finder)".
- 2.4.5(i): use "the appropriate macOS APIs for modifying user data stored by other apps".

Apple applies these rules case by case, and I can't predict the outcome. Companion mode, which leaves the Apple Dock alone, is the lower-risk feature. The copy below never promises replacement. If the feature ships, it has to be declared in the review notes, because 2.3.1 and 2.5.19 rule out undocumented behavior.

### 1.3 Review risk: sandbox

`app/project.yml` sets `ENABLE_APP_SANDBOX: NO`, and 2.4.5(i) requires the sandbox. Another agent owns this work. Several listed features run subprocesses or reach outside the container, so the copy depends on what survives:

| Feature | Current mechanism |
| --- | --- |
| Dock replacement | `/usr/bin/defaults`, `/usr/bin/killall` |
| Window management and snapping | Accessibility API |
| Music | `/usr/bin/osascript` |
| Other apps' login items | `osascript` to System Events |
| Screenshot widget | `/usr/sbin/screencapture` |
| Codex, Claude Code, Gemini CLI, GitHub CLI | Runs CLIs outside the bundle. Also see 2.5.2. |
| Claude status line | Edits `~/.claude/settings.json`. Also see 2.5.2. |

Section 2.6 maps each sentence of the description to the feature it depends on.

### 1.4 Review risk: license code in the binary

`app/Sources/Licensing.swift` compiles into every build and contains the key entry field and a Buy button. A StoreKit build doesn't activate it, but 2.5.19 forbids "hidden, dormant, or undocumented features". The App Store build should compile that code out.

## 2. Draft copy

Limits were checked by script. Apple counts keywords and review notes in bytes.

### 2.1 Name, subtitle, promotional text

| Field | Limit | Used | Text |
| --- | --- | --- | --- |
| Name | 2 to 30 characters | 9 | `DockGrove` |
| Subtitle | 30 characters | 29 | `Apps and widgets within reach` |
| Promotional text | 170 characters | 142 | `Keep your apps, notes, tasks and a focus timer in one glass bar. Add the widgets you use, and arrange everything the way you work on your Mac.` |

Alternative subtitle: `Your apps and tools, one bar` (28).

### 2.2 Description, option A

Limit 4000 characters, plain text, no HTML. Used: 1964.

```text
DockGrove is a customizable bar for your Mac. It keeps the apps you open every day beside small widgets for the things you check all the time, so they stay within reach.

YOUR APPS
Pin apps, search everything installed, and drag tiles into the order you want. Save named layouts, and export or import them. Run up to four bars, each with its own apps, widgets and display.

FREE TO USE
App launching, app search, the Focus timer, Tasks, the clock, and full layout settings are included at no cost.

DOCKGROVE PLUS (IN-APP PURCHASE)
Adds the everyday widgets: Quick Note, File Shelf, Clipboard, Calendar, Reminders, Weather, Music, System information, Calculator, Currency, Converter, Voice Memo, Bookmarks, Stopwatch, World Clocks, Habits, Drink Water and more.

DOCKGROVE FULL ACCESS (IN-APP PURCHASE)
Includes everything in Plus, and adds nine pixel-art companions, the GitHub widget, and AI usage widgets. Full Access is a separate purchase, and it doesn't need Plus first. Buying it after Plus costs the full price.

MAKE IT YOURS
Choose Automatic, Glass, Graphite or Pearl themes, 16 color packs, card shapes, icon size, width and position. On Macs with a notch, an optional strip holds music, Focus, widgets and a file tray.

AI USAGE, NOT AI CHAT
AI widgets show usage figures that your own accounts report, including Codex, Claude Code, Gemini CLI, OpenAI, Anthropic and Cursor. DockGrove has no chatbot, generates no content and never sends prompts to refresh usage. These connections need your own accounts or admin keys.

YOUR DATA
Notes, tasks, layouts and voice memos stay on your Mac. DockGrove has no analytics and no DockGrove account. Connected widgets contact only the service you choose, and permissions are requested only when you turn on a feature. Weather data comes from Apple Weather.

Requires macOS 14 or later. DockGrove is independent and isn't affiliated with or endorsed by Apple, OpenAI, Anthropic, Google, GitHub, Spotify or Cursor.
```

### 2.3 Description, option B swap

Replace the three sections FREE TO USE, DOCKGROVE PLUS and DOCKGROVE FULL ACCESS with this, and keep the rest. Used in the full description: 1668.

```text
WIDGETS AND COMPANIONS
One purchase includes the Focus timer, Tasks, Quick Note, File Shelf, Clipboard, Calendar, Reminders, Weather, Music, System information, Calculator, Currency, Converter, Voice Memo, Bookmarks, Stopwatch, World Clocks, Habits, Drink Water and more, along with nine pixel-art companions, the GitHub widget and AI usage widgets.
```

### 2.4 Keywords, category, what's new

| Field | Limit | Used | Value |
| --- | --- | --- | --- |
| Keywords | 100 bytes, each keyword over 2 characters | 93 | `launcher,widgets,menu bar,notch,focus timer,notes,tasks,clipboard,weather,shortcuts,pixel pet` |
| Primary category | | | Utilities |
| Secondary category | | | Productivity |
| What's New | 4000 characters | | Not available for the first version. Apple requires it from 1.0.1 on. |

Utilities fits "solve a problem or complete a specific task". Developer Tools is the wrong primary, because the developer widgets are a small part of the app.

Template for the first update: `Fixes and stability improvements.` That's only acceptable when the update contains nothing more. 2.3.12 requires significant changes to be listed.

### 2.5 Wording rules

Applied in the drafts above, and to be kept in later edits:

- **Dock trademark.** "Dock" isn't on Apple's published trademark list. "Mission Control", "AirDrop", "Spotlight", "Finder", "Mac" and "macOS" are. The list is non-exhaustive, so absence isn't a waiver. DockGrove is the owner-selected name and it's kept. The copy uses "bar" for the product, and it doesn't use "Dock" as a feature claim, "Apple Dock", or "replaces the Dock".
- **Referential use only.** Apple's rules allow a word mark in a phrase like "for" or "compatible with" only when it isn't part of the product name, is less prominent than the name, and creates no sense of endorsement. So there's no "for Mac" in the name.
- **No Apple endorsement.** 5.2.4(a). The closing disclaimer states independence.
- **No prices in the name, subtitle or screenshots.** 2.3.7. I also left prices out of the description, because the price is undecided and it can vary by storefront.
- **In-app purchases are disclosed.** 2.3.2. The description says which features need a purchase.
- **No trademarked keywords.** 2.3.7 and Apple's keyword field: "Names of other apps or companies aren't allowed". No Spotify, ChatGPT, Claude, GitHub or CoolDock. Don't repeat "DockGrove" or "dock" either, since the name is already searchable.
- **No unverifiable claims.** 2.3.7. No "best", "fastest" or "most private".
- **Accurate privacy claims.** "No analytics" and "stay on your Mac" match the source for notes, tasks, layouts and voice memos. Don't widen this to "nothing leaves your Mac", because weather, currency, GitHub and AI connections do contact services.
- **"Companion" wording.** The new Dating and Relationships descriptor mentions a "virtual companion". DockGrove's are pixel pets, so "pixel-art companions" stays explicit.

### 2.6 Sentence dependency

Remove the matching text if the feature doesn't survive the sandbox work or the tier decision.

| Text | Depends on |
| --- | --- |
| "Run up to four bars" | Extra-dock code, unchanged by sandbox as far as I can tell. Confirm in the final build. |
| "Music" | Automation access to Spotify and Music from a sandboxed app |
| "Calendar", "Reminders" | Calendars and Reminders access, with the sandbox entitlements |
| "Voice Memo" | Microphone entitlement |
| "File Shelf" | Security-scoped bookmarks |
| "GitHub widget" | Public REST path stays. The `gh` path is at risk. |
| "Codex, Claude Code, Gemini CLI" | CLI execution. OpenAI, Anthropic and Cursor admin-key widgets use HTTPS only. |
| "an optional strip holds ... a file tray" | Same as File Shelf |

Window management, snapping and Dock replacement are left out of the description on purpose. If they ship, add a sentence for each, and update section 9.

## 3. Required URLs

Live status was checked on 2026-11-06. `NEXT.md` says automatic deploys are off because the `production` environment has no Cloudflare token, so a merged page may not go live until someone deploys it.

| Field | URL | Required | Live | Blocker |
| --- | --- | --- | --- | --- |
| Support URL | https://dockgrove.com/support | Yes | 404 | Page missing. Apple says it "must lead to actual contact information". No contact exists yet. |
| Privacy Policy URL | https://dockgrove.com/privacy | Yes | 200 | Text is a candidate and doesn't meet 5.1.1(i). See section 5.5. |
| Marketing URL | https://dockgrove.com | No | 200 | Preview state and the purchase link. See below. |
| Accessibility URL | https://dockgrove.com/accessibility | No | 404 | Page missing. Must match section 7. |
| Terms | https://dockgrove.com/terms | No field | 200 | Draft for the Stripe offer. Only useful in the listing with a custom EULA. |
| Privacy Choices URL | Leave blank | No | | Optional |

Two checks before submission:

- 2.1(a) rejects "placeholder text, empty websites, and other temporary content". The site still shows preview and test-mode language.
- 3.1.1(a) says that outside the United States storefront, apps "and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase". The marketing URL leads to a Stripe `/purchase` page. If direct sales continue, take advice on this, or point the marketing URL at a page with no purchase link.

## 4. Screenshots

Specification from Apple's screenshot page:

| Item | Value |
| --- | --- |
| Accepted sizes | 1280 x 800, 1440 x 900, 2560 x 1600, 2880 x 1800, all 16:10 |
| Count | At least 1, up to 10 |
| Formats | `.jpeg`, `.jpg`, `.png`, no alpha or transparency |
| Recommendation | Capture at 2880 x 1800. App Store Connect scales down if the UI is consistent. |
| App previews | Optional, up to 3 per localization |
| Creative assets | Optional, new on 2026-10-05, must follow 2.3.14 |

Rules for capture:

- 2.3.3: show the app in use, not title art, a login page or a splash screen.
- 2.3.8: everything must suit a 4+ audience, even if the rating ends up higher.
- 2.3.7: no prices or unrelated terms in screenshots or overlays.
- 2.3.2: mark paid features. Use a caption such as "Plus widgets" under option A.
- Capture a build matching the submission, with no "Development" labels, license UI or test-mode text.
- Don't show Apple's wallpapers, a visible Apple Dock next to a confusingly similar bar, real calendar entries, tokens, or third-party album art. Use a neutral background of your own and sample data.
- The built-in notched display on the development Mac is 1512 x 982 points, which isn't 16:10. Notch shots need a display mode or canvas that yields 16:10 without distorting the UI.

Shot list, in order. No images were generated.

| # | Shot | Caption | Tier | Dependency |
| --- | --- | --- | --- | --- |
| 1 | Bar on a clean desktop with apps, clock, Tasks and Focus | Apps and widgets within reach | Free | None |
| 2 | Settings, Library, dragging a widget card into the layout | Build it your way | Free | None |
| 3 | App search panel with results | Find any app | Free | None |
| 4 | Rich widget cards: Weather, Calendar, Notes, System | Everyday widgets on your bar | Plus | Weather needs WeatherKit-signed build |
| 5 | Appearance with themes and a color pack | Automatic, Glass, Graphite or Pearl | Free | Confirm tier of themes in final build |
| 6 | Notch strip open with Music and Focus | Quick access at the notch | Plus | Notch display mode |
| 7 | Companion tile and care panel | Nine pixel-art companions | Full Access | None |
| 8 | AI usage cards with sample figures | Usage from your own accounts | Full Access | Use fixture data, and avoid implying provider endorsement |

Keep the first three free-tier shots first, so the product page matches what a download gives without paying. Under option B, drop the tier captions.

## 5. App Privacy questionnaire

### 5.1 Answer

Apple defines "collect" as transmitting data off the device so that you or your partners can access it for longer than needed to service the request in real time. Its partner definition covers vendors whose code you added to your app.

The App Store build, with StoreKit and no license code, has:

- No DockGrove server contact.
- No third-party SDKs. `app/project.yml` declares no packages.
- No analytics. A source search found none, and the README states the same.
- No App Tracking Transparency use.

**Draft answer: "No, we do not collect data from this app."** The product page then shows Data Not Collected, and there are no linked or tracking answers to give.

That answer holds only if the build removes the license client. If it stays, use the right-hand column below.

### 5.2 Every data type

Tracking is No in every row. The App Store build column assumes no license code.

| Category | Data type | App Store build | If license client stays | Linked |
| --- | --- | --- | --- | --- |
| Contact Info | Name, Phone, Physical Address, Other | Not collected | Not collected | |
| Contact Info | Email Address | Not collected | Not collected by the app. Checkout and recovery email are on the website. | |
| Health & Fitness | Health, Fitness | Not collected. Water and habit counts stay local. | Same | |
| Financial Info | Payment, Credit, Other | Not collected. Apple processes purchases. | Not collected by the app. Stripe hosts checkout. | |
| Location | Precise, Coarse | Not collected. No device location requested. City text is typed. | Same | |
| Sensitive Info | Sensitive Info | Not collected | Same | |
| Contacts | Contacts | Not collected | Same | |
| User Content | Emails or Text Messages | Not collected | Same | |
| User Content | Photos or Videos | Not collected. Screenshots go to the clipboard. | Same | |
| User Content | Audio Data | Not collected. Voice memos stay local. | Same | |
| User Content | Gameplay Content | Not collected. Companion state is local. | Same | |
| User Content | Customer Support | Not collected in the app | Same | |
| User Content | Other User Content | Not collected. Notes, tasks, clipboard are local. | Same | |
| Browsing History | Browsing History | Not collected | Same | |
| Search History | Search History | Not collected. Web search opens the browser. | Same | |
| Identifiers | User ID | Not collected | Collected, license key identifies the license | Yes |
| Identifiers | Device ID | Not collected | Collected, generated installation ID, hashed by the server | Yes |
| Purchases | Purchase History | Not collected | Collected, license and activation records | Yes |
| Usage Data | Product Interaction, Advertising, Other | Not collected | Same | |
| Diagnostics | Crash, Performance, Other | Not collected | Same | |
| Surroundings | Environment Scanning | Not collected | Same | |
| Body | Hands, Head | Not collected | Same | |
| Other Data | Other Data Types | Not collected | Same | |

In the right-hand column, the purpose for the three collected types is App Functionality.

If crash reporting or analytics is added later, or App Store Connect analytics sharing is treated differently by counsel, redo this section.

### 5.3 Optional third-party connections

All are off until the user acts. None involve a DockGrove server. The providers aren't partners under Apple's definition, because their code isn't in the app and the developer can't access the data. So they don't appear on the label, but the privacy policy must name them.

| Connection | What leaves the Mac | Goes to | Credential | Retained locally |
| --- | --- | --- | --- | --- |
| OpenAI API usage | Admin key, usage query | `api.openai.com` | Keychain | Report in memory |
| ChatGPT / Codex | Nothing from DockGrove directly. Calls the local Codex CLI, which contacts OpenAI. | OpenAI, via CLI | Owned by CLI | Usage figures |
| Claude API usage | Admin key, usage query | `api.anthropic.com` | Keychain | Report in memory |
| Claude Code | Nothing from DockGrove directly. Reads numbers from a local status-line helper. | Anthropic, via CLI | Owned by CLI | Allowlisted numbers in Application Support, mode 0600 |
| Gemini CLI | Nothing. Local import of CLI JSON. | None | Owned by CLI | Latest session numbers |
| Cursor team usage | Admin key, usage query | `api.cursor.com` | Keychain | Report in memory |
| GitHub | Repository name | `api.github.com`, or `gh` | None, or owned by `gh` | Repository stats |
| Spotify | Local Automation only. Artwork fetch sends the image request. | Spotify image CDN, allowlisted hosts | None | Artwork in memory |
| Apple Music | Local Automation only | None | None | Artwork in memory |
| Google Calendar, Calendar | Nothing from DockGrove. EventKit reads the macOS account. | None | macOS Internet Accounts | Events in memory |
| Reminders | Nothing from DockGrove. Writes only the completion you choose. | None | None | In memory |
| Weather | Typed city, then coordinates | Apple geocoding and WeatherKit | None | Current result |
| Currency | Currency pair | `api.frankfurter.dev` | None | Latest rate |
| Web search | Query, through the browser | Chosen search engine | None | None |
| Window management | Nothing. Titles read through Accessibility. | None | None | In memory |
| Clipboard | Nothing | None | None | In memory, cleared on quit |
| AirDrop | User-selected files, through the macOS share service | Chosen device | None | Tray shortcuts |

Under 5.1.2(i), personal data shared with third-party AI needs clear disclosure and explicit permission. DockGrove sends no prompts or responses. It does send an organization admin key to the provider the user chose, which the Connections card makes explicit. State this in the privacy policy.

No OAuth client exists for Google, Spotify or GitHub. Google sign-in belongs to macOS, Spotify is local Automation, and GitHub uses public REST or the user's `gh`.

### 5.4 Weather detail

The city goes to Apple's geocoder and the coordinates go to WeatherKit. The app doesn't retain them on any server, and the developer can't read them, so they aren't "collected" as Apple defines it. The app doesn't request location permission.

### 5.5 Privacy policy changes needed before the URL is usable

`website/web/src/app/privacy/page.tsx`, updated October 29, can't be submitted as written:

- It describes a release candidate, and says the services "are not deployed".
- 5.1.1(i) requires retention, deletion and revocation terms. The page says a "final retention and deletion policy requires owner review".
- 5.1.1(i) requires confirming that third parties with access to user data give equal protection. The page has no such statement.
- It covers Stripe and license activation, but not App Store purchases. It needs a section for that build.
- It sends data requests to GitHub Issues, and needs a private contact method.
- It doesn't name Spotify's image hosts, OpenAI, Anthropic or Cursor admin keys, Reminders, Accessibility window titles, or the Claude Code status-line change.

5.1.1(i) also requires a privacy link inside the app. No URL for `dockgrove.com` appears in `app/Sources`.

## 6. Age rating questionnaire

Answer in App Information. This covers the January 2026 system (4+, 9+, 13+, 16+, 18+), the social media questions required since September 2026, and the two declarations arriving 2026-11-16, which are due by 2027-01-12 for all apps.

**Expected result: 4+.** App Store Connect computes the rating, so confirm it on screen.

| Group | Item | Answer | Basis |
| --- | --- | --- | --- |
| In-App Controls | Parental Controls | No | None |
| In-App Controls | Age Assurance | No | None |
| Capabilities | Unrestricted Web Access | No | No WebKit or web view. Search and bookmarks open the default browser. |
| Capabilities | User-Generated Content | No | Notes and memos are private and local, not distributed |
| Capabilities | Social Media | No | No feed |
| Capabilities | Social Media Disabled for Users Under 13 | No | No social media |
| Capabilities | Messaging and Chat | No | No user-to-user communication |
| Capabilities | Advertising | No | None |
| Capabilities | Shared Location | No | New 2026-11-16. No location sharing. |
| Capabilities | Dating and Relationships | No | New 2026-11-16. Companions are pixel pets with no romantic or sexual content. |
| Mature Themes | Profanity or Crude Humor | None | |
| Mature Themes | Horror/Fear Themes | None | |
| Mature Themes | Alcohol, Tobacco, or Drug Use or References | None | |
| Medical or Wellness | Medical or Treatment Information | None | |
| Medical or Wellness | Health or Wellness Topics | No, see note | Drink Water and Habits |
| Sexuality or Nudity | Mature or Suggestive Themes | None | |
| Sexuality or Nudity | Sexual Content or Nudity | None | |
| Sexuality or Nudity | Graphic Sexual Content and Nudity | None | |
| Violence | Cartoon or Fantasy Violence | None | Pets walk, sleep and play. The dragon only flies. |
| Violence | Realistic Violence | None | |
| Violence | Prolonged Graphic or Sadistic Realistic Violence | None | |
| Violence | Guns or Other Weapons | None | |
| Chance-Based Activities | Gambling | None | |
| Chance-Based Activities | Simulated Gambling | None | |
| Chance-Based Activities | Contests | None | Companion levels are personal progress, not a competition |
| Chance-Based Activities | Loot Boxes | None | |

Notes:

- **The one judgment call:** Apple defines Health or Wellness Topics as "self-care or lifestyle recommendations, such as calorie tracking, dieting, or exercise advice". Drink Water has a default goal of 8 glasses and an optional hourly sound, and the UI says "Choose your own goal". I read that as a counter rather than advice. If the owner prefers the cautious reading, the rating becomes 9+. Nothing else changes.
- **AI:** DockGrove has no chat, assistant or generated content. It displays usage numbers only, so guidelines 4.7 and 1.2 don't apply, and no AI question changes the rating.
- **Third-party content:** Spotify and Apple Music tiles show track titles and artwork from the user's own player. DockGrove doesn't host or curate this.
- **Regional:** Korea's GRAC regional rating applies to Games and Entertainment categories, so not to Utilities. Brazil adds ratings only for the two new declarations, which are both No.

## 7. Accessibility Nutrition Labels

Labels are voluntary today, and Apple says they'll become required with notice. I found no date. Apple allows a claim only when users can complete all common tasks with the feature. Common tasks include first launch, primary functions, purchase and settings.

**Draft answer: leave all features unanswered for 1.0.** The code shows real support, but no one has run the audits, and App Review can ask you to correct misleading labels under 2.3.

| Feature | Mac | Code evidence | Gaps | Draft |
| --- | --- | --- | --- | --- |
| VoiceOver | Yes | 67 `accessibilityLabel` uses, 15 trait uses, custom actions in notch views, decorative images hidden. App tiles and page arrows are labeled. | No VoiceOver test recorded. Most interaction is hover, click and drag on a nonactivating panel. No announcements for status changes found. | Unverified, don't claim |
| Voice Control | Yes | Benefits from the same labels. Right-click move commands exist as a drag alternative. | No test recorded. Hover-revealed notch and auto-hide need spoken alternatives. | Unverified, don't claim |
| Larger Text | Not on Mac | Not applicable | | Not offered |
| Dark Interface | Yes | Glass and Graphite themes use a dark scheme. Automatic follows macOS. The notch is dark. Settings follow the theme. | Contrast in dark mode with Increase Contrast not measured. | Candidate, unverified |
| Differentiate Without Color Alone | Yes | Text labels on most states | No reference to the system setting. The status of running indicators, drop targets and charts hasn't been tested in Grayscale. | Unverified, don't claim |
| Sufficient Contrast | Yes | Dock plate border strengthens with Increase Contrast. Reduce Transparency adds an opaque plate and stronger widget backgrounds. | The contrast check touches only the plate border. No 4.5:1 or 3:1 measurements for native UI. Translucent glass and 92 accents make this harder. | Unverified, don't claim |
| Reduced Motion | Yes | Respected on the tile hover, notch pages, Studio panels, and companions (rest pose, 1 fps). `docs/COMPANION-REVIEW.md` records a test. | Ungated: Applications stack reveal and hover springs (`ApplicationsStack.swift` lines 28, 299, 457, 479) and tile reorder (`Views.swift` line 88). Decorative springs must stop. | Candidate after those fixes |
| Captions | Yes | No video and no spoken content from the developer. Voice memos are the user's own. | | Not applicable |
| Audio Descriptions | Yes | No video | | Not applicable |

Keyboard use isn't a label of its own, but it matters for VoiceOver and for the Accessibility page. Evidence in code:

- Global ⌥⌘D hide or show. Carbon hotkey, no Accessibility permission needed.
- ⌘W closes Settings and ⌘Q quits.
- Esc triggers the Done buttons and closes the notch strip.
- Arrow keys move the selection in the Applications stack search. Unverified by hand.
- Full keyboard navigation of the bar is unverified. No `focusable` use was found.

The website's reviewed keyboard behavior in `docs/DESIGN-REVIEW-WEB.md` covers the site, not the app.

The `/accessibility` page should say the same thing: what's supported, what's being evaluated, and how to report a barrier.

## 8. Export compliance

| Question | Answer |
| --- | --- |
| Does the app use encryption? | Yes, only encryption provided by macOS |
| Proprietary or non-standard algorithms? | No |
| Standard algorithms implemented outside the OS? | No |
| France declaration needed? | Not expected. Apple names secure storage, secure communications and antivirus apps as the controlled categories. |
| Documentation upload | Not expected |
| `ITSAppUsesNonExemptEncryption` | `NO` |

Crypto actually used:

| Use | API | Location |
| --- | --- | --- |
| HTTPS | `URLSession` | All network clients |
| Secret storage | Keychain, `SecItem` | `AIUsage.swift`, `Licensing.swift` |
| Device hash | CryptoKit SHA-256 | `Licensing.swift` |
| Signature verification | CryptoKit P-256 ECDSA | `Licensing.swift` |

The project has no third-party crypto library or package. Apple says OS-provided encryption such as `URLSession` HTTPS "is typically exempt", and that exempt apps "may need to submit a year-end self-classification report to the U.S. government". The developer carries liability for the claim, so the owner should certify this and check the self-classification point with an adviser.

`app/Info.plist` lacks the key, so App Store Connect will ask on every upload until it's added. The dialog's exact wording wasn't available to me. Match it to "uses only encryption within the operating system".

## 9. App Review notes

Limit 4000 bytes. Used: 3081. Strike any line whose feature didn't ship. Under option B, delete the In-App Purchases section.

```text
WHAT IT IS
DockGrove is a customizable bar for apps and widgets on the Mac. It's a menu-bar utility (LSUIElement), so it has no Dock icon and no main window. After launch, look for the bar at the bottom of the main display and the DockGrove icon in the menu bar.

SIGN-IN
No account or sign-in is needed. There's no DockGrove account or server. Optional connections use the reviewer's own third-party accounts, and every widget works or shows a clear setup state without them.

HOW TO TEST
1. Launch DockGrove. Open Settings from the menu-bar icon or the sliders button on the bar.
2. Library: drag a widget or app into Your Dock, or onto the bar. Right-click a tile for move and remove commands. Undo layout reverts changes.
3. Click the Focus tile and start a 5-minute session. Add a task in Tasks.
4. Appearance: change the theme, color pack, icon size, and widget shape.
5. Behavior: save a named layout, then add an extra bar.
6. Quit from the menu-bar icon. The menu-bar icon always offers Settings, show or hide, and Quit.

IN-APP PURCHASES
Settings > Purchases lists DockGrove Plus and DockGrove Full Access, both non-consumable, plus Restore Purchases. Locked Library cards open these offers. Free: app launching, app search, Focus, Tasks, clock, spacers and layout settings. Plus: everyday widgets. Full Access: everything in Plus, companions, GitHub and AI usage. Full Access doesn't require Plus.

SIMPLE WIDGETS TO TRY
- Weather: enter Cupertino and refresh. Uses WeatherKit, with Apple Weather attribution.
- Currency: choose a pair and refresh.
- GitHub: enter a public repository, such as apple/swift, and refresh. No sign-in needed.
- Companion: choose a pet and open its care panel.

PERMISSIONS
Each is requested only when the feature is turned on.
- Microphone: Voice Memo, when Record is pressed. Audio stays on the Mac.
- Calendars: Calendar widgets, when Connect is pressed. Read only.
- Reminders: Reminders widget. Reads incomplete reminders and marks the one chosen as complete.
- Automation: Music widgets, to read the current track and control Spotify or Music.
- Accessibility: Windows widget and window snapping, to list, move and resize windows the user selects.
The app doesn't request location access. It doesn't use the camera.

AI USAGE WIDGETS
These display usage figures only. DockGrove has no chatbot, generates no content, and sends no prompts. Testing needs a provider account or admin key. Without one, a card shows its setup state. Admin keys go to the Keychain and only to that provider's API.

SYSTEM DOCK OPTION
Settings > Behavior > Use DockGrove as my Dock sets the system Dock's auto-hide preferences so the two bars don't overlap, after recording the original values. Turning it off, quitting, or choosing Restore Apple Dock from the menu-bar icon restores those values. The system Dock restarts briefly when this changes. The option is off by default.

NOTCH
Settings > Appearance > Notch quick access applies only on Macs with a camera housing.

THIRD PARTIES
DockGrove is independent and isn't affiliated with any named provider.
```

Check these against the final build before pasting:

- Sandbox outcome for the Accessibility, Automation and system Dock items.
- Whether the system Dock section can stay at all. See section 1.2.
- That the "off by default" statement matches a fresh install.
- That the free tier list matches `WidgetCatalog.swift`, which it does today.

In-app purchase review notes, 4000 character limit, same text for both products:

```text
Open Settings > Purchases. Buy this product, then confirm the matching locked Library cards unlock. Restore Purchases rebuilds access. No sign-in is required beyond the App Store sandbox account.
```

## 10. Form field table

Each row is one field or attestation. Counts are in section 13.

### App Information

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Name | 2 to 30 characters | `ready` | DockGrove |
| Subtitle | 30 characters | `ready` | Apps and widgets within reach |
| Apple ID | Read only | `ready` | 6829005855 |
| Bundle ID | Fixed after first build | `owner` | `com.dylan.wavedock.development`. Confirm before upload, since it can't change afterward and the suffix says development. `com.dylan.wavedock` would need a new app record. |
| SKU | Set at creation | `owner` | Not in the repository. Read from App Store Connect. |
| Primary language | | `ready` | English (U.S.) |
| Primary category | | `ready` | Utilities |
| Secondary category | | `ready` | Productivity |
| Content Rights | Attestation | `owner` | Draft: yes, the app shows third-party content, and has the rights. Owner confirms for Font Awesome (CC BY 4.0), provider marks, Spotify artwork, WeatherKit and Frankfurter. See 5.2.2. |
| Age Rating | Questionnaire | `ready` | Section 6. Expected 4+. |
| License Agreement | | `owner` | Draft: Apple standard EULA. `/terms` is a draft for the Stripe offer, so it isn't a substitute. |
| DSA trader status | Declaration | `owner` | Section 11. Required even if the app skips the EU. |
| Regulated Medical Device | Conditional | `ready` | Not applicable. Not in Health & Fitness or Medical, and no medical references. |
| China mainland availability | Conditional | `owner` | Needs a valid ICP filing number, otherwise exclude the storefront. |
| Republic of Korea availability | Conditional | `owner` | Required for organization enrollments distributing there. Enrollment type isn't in the repository. |
| Vietnam availability | Conditional | `owner` | Apple lists the field. I found no requirement that applies, so check it in App Store Connect. |
| App Store Server Notifications URL | Optional | `ready` | Leave blank. The app checks transactions on device. |

### Pricing and Availability

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Price | | `owner` | Option A Free, option B $9.99. Section 1.1. |
| App availability | | `owner` | Drafts select all 175 regions. Review after China decision. |
| Pre-order | | `ready` | No |
| Business and Education distribution | | `ready` | Default |
| Tax category | | `ready` | Default |

### App Privacy

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Privacy Policy URL | Required | `blocked` | https://dockgrove.com/privacy, once section 5.5 is done |
| Privacy Choices URL | Optional | `ready` | Leave blank |
| Data collection | Questionnaire | `blocked` | Draft: Data Not Collected. Depends on removing the license client. |

### Accessibility

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Accessibility URL | Optional | `blocked` | https://dockgrove.com/accessibility, currently 404 |
| Accessibility support | Voluntary | `blocked` | Leave unanswered until audited. Section 7. |

### Version 1.0.0

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Version number | | `ready` | 1.0.0 |
| Build | Required | `blocked` | No sandboxed, App Store-signed build exists |
| Copyright | Required | `owner` | Section 11 |
| Promotional text | 170 characters | `ready` | Section 2.1 |
| Description | 4000 characters | `owner` | Section 2.2 or 2.3, after the section 1.1 decision |
| Keywords | 100 bytes | `ready` | Section 2.4 |
| Support URL | Required | `blocked` | https://dockgrove.com/support, currently 404, and needs a contact |
| Marketing URL | Optional | `blocked` | https://dockgrove.com, after preview text and the purchase link are resolved |
| Screenshots | 1 to 10 | `blocked` | Section 4. Needs the final build. |
| App preview | Optional | `ready` | Skip |
| Creative assets | Optional | `ready` | Skip for 1.0 |
| What's New | 4000 characters | `ready` | Not available for version 1.0 |
| Release method | | `ready` | Manual, so the owner controls launch day |
| Export compliance | Questionnaire | `ready` | Section 8. Owner certifies at submission. |

### App Review Information

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Sign-in required | | `ready` | No |
| Contact first and last name | Required | `owner` | Not in the repository |
| Contact email | Required | `owner` | None exists in the repository. Not invented. |
| Contact phone | Required, with `+` country code | `owner` | Not in the repository |
| Notes | 4000 bytes | `blocked` | Section 9. Must match the final build. |

### In-App Purchases, option A only

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Reference names | 64 characters | `ready` | DockGrove Plus, DockGrove Full Access |
| Product IDs | 100 characters, permanent | `ready` | `com.dylan.wavedock.plus`, `com.dylan.wavedock.full` |
| Display names | 2 to 30 characters | `ready` | DockGrove Plus, DockGrove Full Access |
| Plus description | 45 characters | `ready` | Unlock everyday widgets with one purchase. (42) |
| Full Access description | 45 characters | `ready` | All widgets, companions and AI usage (36). The current `DockGrove.storekit` text is 58 characters. Check what the saved record contains. |
| Prices | | `owner` | $4.99 and $9.99 as saved. Section 1.1. |
| Review screenshots | Required | `blocked` | Outstanding. Any accepted Mac screenshot size, showing the offer. |
| Review notes | 4000 characters | `ready` | Section 9 |
| Family Sharing | | `owner` | Off in `DockGrove.storekit`. Confirm. Can't be turned off once on. |

Apple's reference gives 30 and 45 characters. Its product page guide says 35 and 55. These drafts fit both.

The first in-app purchases must be submitted with an app version. Apple IDs are Plus 6829005609 and Full Access 6829006160.

### Account

| Field | Limit | Status | Value |
| --- | --- | --- | --- |
| Paid Apps Agreement | Account Holder | `owner` | Section 11 |
| Tax forms | Account Holder or Admin | `owner` | Section 11 |
| Banking | Account Holder or Admin | `owner` | Section 11 |

## 11. Owner-only items

| Item | What's needed | Repository state |
| --- | --- | --- |
| App Store decision | Confirm the App Store is wanted, and choose option A, B or C | `docs/COMMERCE.md` rules it out today |
| Paid Apps Agreement | Must be active. Only the Account Holder can sign. Accept any newer version too, or new records are blocked. Apple updated the developer agreement on 2026-10-13. | Recorded as accepted, in a dated note. Check it. |
| Tax | Complete the tax forms | Not recorded |
| Banking | Add a bank account | Not recorded |
| DSA status | Self-assess. Apple can't decide this. Apple lists revenue from apps, commercial promotion, VAT registration and professional development as factors, so a paid app points to trader. | Undeclared |
| DSA trader details | Address or P.O. box, phone, email and supporting documents. Published on the EU product page. Email and phone are verified by code. | None exists |
| Developer name | Check what name the account shows. It appears on the product page. | Team `G563Q4D3XW`, name not in the repository |
| Copyright line | Year and rights holder. Candidate: `2026 Dylan Lasensky`, from `LICENSE`. App Store Connect adds the symbol. The site footer says `© 2026 DockGrove`, so pick one. | Conflict |
| IP ownership | 5.2.1 requires submission by the owner or licensee. The license names Dylan Lasensky, and `docs/MALCOLM-SIGNING-HANDOFF.md` assigns signing to Malcolm. Confirm the account holder has the rights. | Unconfirmed |
| Commercial license transition | `docs/COMMERCIAL-LICENSE-TRANSITION.md` still needs approval | Open |
| Support contact | A monitored email or form for `/support` and the privacy policy | None exists |
| App Review contact | Name, email, phone with `+` country code | None exists |
| Third-party permission | 5.2.2: confirm terms allow Spotify, Frankfurter, and Codex usage reads. Apple can ask for proof. | Unconfirmed |
| Export certification | Confirm section 8 and the self-classification question | Open |
| China mainland | File an ICP number or exclude the storefront | Open |

### Build items found while filling this in

No code was changed. These are for the sandbox and code work:

- `ENABLE_APP_SANDBOX: NO`. Sections 1.3 and 2.6.
- The base `PRODUCT_DISPLAY_NAME` is `DockGrove Development`, and the `Release` archive inherits it. The name in the build should match the listing. See 2.3.8.
- The bundle ID with the App Store record belongs to the build config that `docs/COMMERCE.md` says must never ship.
- Automatic Apple Development signing and `Release` archive need an App Store distribution path.
- `LSApplicationCategoryType` is missing from `app/Info.plist`. For Mac apps, Apple says the Xcode category should match the App Store Connect primary category. Use `public.app-category.utilities`.
- `ITSAppUsesNonExemptEncryption` is missing. Section 8.
- No `PrivacyInfo.xcprivacy` exists. The app uses `UserDefaults`, which is a required-reason API, and Apple has required approved reasons since 2024-05-01.
- No in-app privacy link. Section 5.5.
- Dormant license UI. Section 1.4.
- The Reduced Motion gaps. Section 7.
- `DockGrove.storekit` Full Access description exceeds Apple's limit. Section 10.
- Apple said macOS 26 is the last release for Intel Macs. The universal build stays valid, and arm64-only is optional.

## 12. Sources

Checked 2026-11-06.

App Store Connect Help:

- Required, localizable and editable properties: https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties
- App information: https://developer.apple.com/help/app-store-connect/reference/app-information/
- Platform version information: https://developer.apple.com/help/app-store-connect/reference/platform-version-information/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Age ratings: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- Evaluation criteria for VoiceOver, Voice Control, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion and Captions: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria and sibling pages
- EU DSA trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- Export compliance overview: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- In-App Purchase information: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information
- Agreements: https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/
- Availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/
- China mainland compliance: https://developer.apple.com/help/app-store-connect/manage-compliance-information/view-china-mainland-compliance-information

Apple policy and developer pages:

- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Categories: https://developer.apple.com/app-store/categories/
- Product page guide: https://developer.apple.com/app-store/product-page/
- Encryption export regulations: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- `ITSAppUsesNonExemptEncryption`: https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption
- Upcoming requirements: https://developer.apple.com/news/upcoming-requirements/
- Apple trademark list: https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
- Third-party trademark guidelines: https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html

Recent changes that affect this form:

- 2026-11-02, new age rating descriptors from 2026-11-16, due 2027-01-12: https://developer.apple.com/news/?id=yxkh08us
- 2026-10-16, updated guidelines, including 2.3.14: https://developer.apple.com/news/?id=92th7e5i
- 2026-10-05, creative assets: https://developer.apple.com/news/?id=ljpl7kyn
- 2026-09-09, submissions open, social media age questions, macOS 27 Apple silicon only: https://developer.apple.com/news/?id=k1mtkt1k
- Age rating update, since 2026-01-31: https://developer.apple.com/news/upcoming-requirements/?id=07242025a

Not confirmed:

- I found no date for mandatory Accessibility Nutrition Labels.
- Apple's published April 2026 and April 2027 SDK lists name iOS, iPadOS, tvOS, visionOS and watchOS, but not macOS. Build with the current Xcode anyway.
- Apple's required-properties page didn't expose its Required and Editable columns to my fetch, so required flags come from the field reference pages.
- The export dialog's current wording. It's behind sign-in.

## 13. Status counts

The field table in section 10 has 58 rows.

| Status | Count |
| --- | --- |
| `ready` | 28 |
| `owner` | 20 |
| `blocked` | 10 |

The nine In-App Purchases rows fall away under option B: six `ready`, two `owner` and one `blocked`. Under option C, the whole form is parked.
