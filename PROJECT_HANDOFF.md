# Blank Prime — Session Handoff Report
_For the next chief engineer. Written 2026-07-25. Exhaustive by request._

---

## 1. Project identity
- **App:** "Blank Prime" (was "BLANK TV"), a **luxury iOS IPTV player** (SwiftUI, iPhone/iPad/Mac), sold commercially.
- **Owner:** Ghannam (Arabic-speaking, gr7.alajmi@gmail.com). Communicates in Arabic; reply in Arabic.
- **Repo:** `C:\Users\user\Strong8K-App\blankstor` (git, branch `main`, remote `github.com/Ghannam101/Private`).
- **Bundle id:** `com.blanktv.player` (do NOT change).
- **Target:** iOS 17 min, iOS 26 SDK, Xcode 26.3 (pinned in codemagic.yaml).
- **Reference app:** `C:\Users\user\Strong8K-App\Strong8K\iOS` — the owner's OTHER published app "Strong8K". **READ-ONLY.** Port its ENGINEERING, never its LOOK. Blank Prime must be **180° visually different** from Strong8K so Apple accepts it as a distinct, non-cloned app.

## 2. Build & verify pipeline (CRITICAL — read before touching code)
- **Cannot compile locally** (Windows, no Xcode). Verify EVERY change with this 3-step loop:
  1. `python chk.py` (repo root) — brace-balance sanity.
  2. **Agent compile-review** — spawn a `general-purpose` agent to read the diff for Swift compile errors + runtime traps. (Note: agents read code; they CANNOT see rendered SwiftUI — layout/visual bugs still slip through. See §5.)
  3. **Codemagic build** → TestFlight. Owner taps Update on-device, tests, sends feedback.
- **Codemagic REST API** (owner provides the token each session — ask for it):
  - Header `x-auth-token: <TOKEN>`. appId `6a51950410f7ed8a9c8867d6`, workflowId `ios-release`, branch `main`.
  - Trigger: `POST https://api.codemagic.io/builds {"appId","workflowId","branch"}` → returns `{buildId}`.
  - Status: `GET https://api.codemagic.io/builds/{id}` → `.build.status` (preparing→building→publishing→finished/failed) + `.build.index`.
  - **TestFlight version = Codemagic build `index` + 2** (an `agvtool` step in codemagic.yaml).
- **App Store Connect DAILY UPLOAD LIMIT:** Apple caps TestFlight uploads/app/day (~hit it after ~9 builds). A "publishing"-step failure with `409 Upload limit reached` ≠ code failure (the IPA built fine). BATCH several reviewed changes per build when iterating fast. `chk`+agent = fast inner loop; Codemagic = rate-limited outer loop.
- **Safe-rollout pattern the owner likes:** build a redesign as an ISOLATED view reached via a temporary preview button (never on the launch-critical path), verify on-device, THEN swap it in + remove the preview button. Used for Settings V2 and the login Gateway.

## 3. Governing constraints (non-negotiable)
- **No hardcoded API keys** (e.g. TMDB key must come from the server/config, never in code).
- **Strong8K reference = READ-ONLY**, engineering only (see §1).
- **project.pbxproj has NO synchronized groups** → EVERY new `.swift` file needs **4 manual entries**: PBXBuildFile, PBXFileReference, PBXGroup children, PBXSourcesBuildPhase. Hand-added IDs use the `1A1A1A1A000000000000FXXX` scheme (F001–F014 used so far — next free is F015+). Asset catalogs (`.xcassets`) are compiled wholesale → new imagesets need NO pbxproj edit.
- **NEVER `ForEach(0..<someVariable)`** (variable-count Range ForEach) — traps at runtime on the value change. Use `ForEach(Array(0..<n), id: \.self)` or `ForEach(items)` (Identifiable). This crashed a launch build before.
- **Never sort by raw `Double(rating)`** — `Double("nan")==.nan` breaks strict-weak-ordering → `sorted` traps. Use `s8kRating(...)`/`.isFinite`.
- **TabView evaluates ALL tab bodies at launch** — a runtime trap in ANY tab body = launch crash. Heavy view rewrites on the tab path MUST be build-tested.
- **Top/nav bars via `.safeAreaInset(edge:.top)`**, never a ScrollView child (scroll content captures taps → dead buttons).
- Review after each task (owner insists). Keep the "blast radius" small.

## 4. What shipped this session (all on TestFlight unless noted)
Chronological, newest last. TestFlight version in brackets.

1. **Rebrand** BLANK TV → "Blank Prime" (display name + `S8KWordmark` + defaults). [v44/45]
2. **Settings V2 redesign** — navigation hub (`SettingsProV2` in SettingsView.swift): cinematic header (tappable → `AccountSwitcherView`), dark section rows each opening its own sub-page (`SetConnectionPage`/`SetPlayerPage`/`SetAppPage`/`SetAboutPage`), shared `SetUI` builders + `SetScaffold`, redesigned parental flow. Adopted as the live settings tab; old accordion deleted. [v44/45]
3. **Player engine "brain"** (final decision after verified research — see [[player-engine-ksplayer]] memory): kept AVPlayer+VLC (KSPlayer rejected: GPL-default/paid-LGPL/single-maintainer). Added `StreamRouter.swift` (routing), `EngineDecisionCache.swift` (persistent per-content last-good engine), `EngineStats.swift` + a Settings→Connection "Playback Engine Diagnostics" numbers panel. [v47]
4. **GRDB/SQLite catalog store** (`CatalogDB.swift`, ported from Strong8K): pod `GRDB.swift ~> 6.24`; schema + FTS5 (unicode61 remove_diacritics 2) + keyset paging + migrations. Off-main shadow-write population in `PlaylistService` (Core.swift, both M3U + Xtream-direct fetch sites) — NOTE: pure-Xtream-credentials path NOT yet populated (fallback covers it). First read consumer = FTS-accelerated `SearchVM.search()` (gated by `isSearchable`, full in-memory fallback). See [[catalog-store-grdb]]. [v48–51]
5. **ThumbHash** (`ThumbHash.swift`, verbatim MIT port): `image_hash` table (CatalogDB migration v2) + encode-on-decode in `S8KImageCache.fetch` (off-main, idempotent) + instant blurred placeholder + crossfade in `S8KImage`. [v52–54]
6. **Warm player** (`MediaPrefetcher.swift`): pooled muted AVPlayer pre-buffers a VOD on `MovieDetailView.task`; `AVPlayerVM.setup` adopts it via `take(for:)`. [v56]
7. **Loading feel** (owner: big-app minimal): `ContentBootView` stripped to logo+spinner; `LoadingView` text removed; NEW `S8KPosterGridSkeleton`/`S8KListSkeleton` on Movies/Series/Live loaders (page-drawn shimmer, no "loading…" text). [v57–58]
8. **Tab-bar search-cancel bug** fixed (stale debounce could re-filter after close). **Instant-start** tuning (`AVPlayerVM`: preferredForwardBufferDuration 1 + `playImmediately`). [v57]

## 5. THE LOGIN GATEWAY — IN PROGRESS, HAS AN UNRESOLVED VISUAL BUG
Owner wants a muvy-style login screen (design ref = the WhatsApp image `WhatsApp Image 2026-07-25 at 5.39.20 PM.jpeg`): a full-bleed animated **poster wall** (3 rows, alternating directions, seamless) behind the app logo/wordmark (no tagline) + a compact **Xtream/M3U** login card + language toggle + a **multi-account "switch account"** button. Built as `BlankTV/GatewayView.swift`, reached via a TEMP "معاينة بوّابة الدخول الجديدة" button in `SubscriptionsGateView` (AuthViews.swift) — **live login is untouched.**

### Decisions locked
- Brand = the app's own `BrandLogo` + `S8KWordmark`, centered. No Arabic tagline.
- Posters = the owner's 6 studio posters, BUNDLED as `Assets.xcassets/gwposter1…6.imageset` (load instantly). **Copyright caveat flagged** (studio art, no license) — owner accepts for now; the professional/safe path is **TMDB posters via the owner's central server** (see §6).
- Marquee is SEAMLESS: `GatewayMarqueeRow` repeats the 6-poster set `reps` times and animates the offset by EXACTLY one base-set width (`gwBaseWidth = 6*(cardW+spacing)`) — item[6]==item[0], uniform stride → no jump. Fixed `reps = 6` (no width dependency). This part WORKS.

### ✅ THE BUG IS FIXED (2026-07-25, commit `d9652e2`, build index 62 → TestFlight v64)
The root cause below was confirmed and the measurement was **removed entirely** — there is no
`GeometryReader` anywhere in `GatewayView` now:
- Root = plain `ZStack(alignment:.bottom)`; login block = `.frame(maxWidth: 400)` +
  `.padding(.horizontal, 24)` → can never overflow, can never go negative.
- Language pill + close button moved into `.safeAreaInset(edge:.top) { topBar }` → always clear of the
  notch / Dynamic Island on every device.
- Foreground wrapped in `ScrollView` + `.defaultScrollAnchor(.bottom)` +
  `.scrollBounceBehavior(.basedOnSize)` → bottom-pinned when it fits, scrollable with the keyboard up,
  in landscape, or at large text sizes.
- Poster card size switches on `horizontalSizeClass` (112pt compact / 152pt regular) instead of measuring.
**Awaiting the owner's device verification (iPhone + iPad). Then: swap it in + delete the temp preview button.**

### THE BUG — original diagnosis (kept for the record)
The **foreground (login card + brand + language button) DISAPPEARS on device — only the poster wall shows** — whenever `GatewayView`'s root is a **`GeometryReader`**. Confirmed twice:
- v60 (GeometryReader + ScrollView + Spacer + `.frame(minHeight: geo.height)`) → foreground gone.
- v63 (GeometryReader + ZStack + `.frame(width: min(geo.size.width-44, 430))`) → foreground gone.
- v61/v62 (simple `ZStack(alignment:.bottom)`, NO GeometryReader) → foreground SHOWED (but 2 lesser bugs: buttons wider than screen, and language pill hidden under the notch).

**Diagnosis:** a `GeometryReader` as the root of the `.fullScreenCover` content appears to report a bad/zero size in this context, so `contentW = min(geo.size.width - 44, 430)` goes NEGATIVE (`min(-44,430) = -44`) → `.frame(width: -44)` collapses the login VStack to nothing. The `.ignoresSafeArea()` poster/scrim layers don't depend on `geo`, so they still render → "only posters." (Two agent reviews wrongly blessed the GeometryReader — agents can't see rendered layout. Lesson: for layout, trust device tests over agent reasoning.)

### RECOMMENDED FIX (for the new engineer)
Go back to the **simple `ZStack(alignment:.bottom)` (v61/v62 base that SHOWED the foreground)** and fix its two lesser bugs WITHOUT a root GeometryReader:
1. **Overflow** ("buttons wider than screen"): cap the login block with `.frame(maxWidth: 400)` (a value clearly < the narrowest screen minus margins), NOT `.frame(width: …)`, and keep `.padding(.horizontal, 24)`. Avoid the self-contradictory `maxWidth(440).frame(maxWidth:.infinity)` chain. If a specific control still overflows, it's the mode toggle text — labels are now short ("Xtream"/"M3U").
2. **Language pill hidden under notch**: the v62 `.overlay(alignment:.top){…}.padding(.top,6)` put it under the Dynamic Island. Fix WITHOUT GeometryReader — use `.safeAreaInset(edge: .top)` for a top bar (the guardrail-blessed API, reserves space in the safe area) OR a fixed `.padding(.top, 54)` that clears the notch on all phones. Keep it a high-contrast gold pill (already styled).
3. Keep everything else from v63 (elegant capsule toggle, stronger scrim, the multi-account switch button + `accountSheet` + `enter(acc)` reusing `auth.switchPlaylist`).
Then: owner verifies on iPhone + iPad. Once approved → **swap `GatewayView()` in place of `SubscriptionsGateView()`** (or wire it as the not-logged-in screen) + **remove the temp preview button** (AuthViews.swift: `showGatewayPreview`, the `.fullScreenCover`, and the footer preview Button).

An approved HTML mockup of the intended design exists at the Artifact URL the owner has (poster wall + gold lang pill + capsule toggle + bottom login card).

## 5b. Device-compatibility pass (2026-07-25, same commit `d9652e2`)
Owner requirement: "the app must fit EVERY device and version, professionally." Screen metrics were
researched from Apple's HIG/docs and written up permanently in **`DEVICE_MATRIX.md`** (repo root) —
every iOS 17+ iPhone size, every iPad, multitasking widths, safe-area insets, the four hard extremes to
test, the approved adaptive APIs, and the **banned patterns** list. Read it before any layout work.

Fixed in this pass (full audit of all view files):
- **CRITICAL** `MaintenanceView` / `UpdateRequiredView` (ActivationView.swift): non-scrollable full-screen
  gates with a *server-supplied* message → Retry/Update could be pushed off-screen, **trapping the user**.
- **CRITICAL** reseller-code sheet + `AddPlaylistView`: the keyboard covered the only action button on a
  `.medium` detent → now scrollable + `[.medium, .large]`.
- `ChannelInfoSheet` (long IPTV names), `PINEntryView`, sleep-timer sheet → scrollable.
- Settings hub + **every** settings sub-page: bottom spacer 30 → 110 (logout + last row were under the
  floating tab bar).
- New `s8kWindowSize()` (DesignSystem.swift) replaces `UIScreen.main.bounds` for hero heights and the VLC
  crop fallback — the screen is not the window under Split View / Stage Manager / Mac.
- `S8KPosterGridSkeleton` → adaptive columns (was a fixed 3 → 440pt "posters" on iPad).
- `S8KTextField` → `minHeight` instead of a fixed 52 (clipped at accessibility text sizes).
- Tab bar spacing 4 → 2 (the 6-circle bar clipped in a 320pt iPad Slide Over pane); `FlowLayout`
  zero-width probe guard; `CategoryReorderView` 0-height first-pass clamp.

**Deliberately NOT changed — needs owner approval (changes approved visuals):** the 13 hard-coded
`.padding(.top, 50…70)` sites, converting `AppTabBar` to a `.safeAreaInset(edge:.bottom)`, and full
Dynamic Type adoption in `S8KFont`. All three are listed in `DEVICE_MATRIX.md` §6.

## 5c. Owner device feedback + design pass (2026-07-25 evening)
Owner tested v64 and reported: the language pill never appeared, the switch-account button
"is a plain rectangle, not elegant", the text fields felt sticky to tap, and the Xtream/M3U
switch felt slow. Root causes and fixes (build 63 → **v65**, build 64 → **v66**):
- **Language pill invisible:** an `.ignoresSafeArea()` CHILD inflates its ZStack parent to
  full screen, so "the top of the container" was under the Dynamic Island — which defeated
  `.overlay(alignment:.top)` AND `.safeAreaInset`. The gateway root is now a plain `VStack`
  whose first child is the top bar, with the poster wall in `.background { … }` (a
  background cannot inflate its host). **Nothing on this screen is measured.**
- **Sticky fields:** a SwiftUI `TextField`'s hit area is only its intrinsic text box — the
  icon, padding and the extra `minHeight` were dead space. `S8KTextField` now has
  `.contentShape(Rectangle())` + `.onTapGesture { focused = true }` (app-wide). Plus
  `GWNoTouchDelay`, which turns off `UIScrollView.delaysContentTouches` (~150ms) inside the
  gateway — that delay also suppressed all button press feedback.
- **Slow toggle:** the pill was each tab's own `.background` (a crossfade, not a slide);
  feedback came from `configuration.isPressed`, which is unreliable inside a ScrollView;
  and a global `withAnimation` dragged the scroll height and poster wall into the
  transaction. Rebuilt as `GatewayModeSwitcher` — one `matchedGeometryEffect` indicator,
  state-driven, scoped `.animation(value:)`, prepared haptic fired before the state change.
- **Design pass** (owner-approved directions, vetted by a review-board agent): flat lime CTA
  with a neutral shadow (no gradient, no glow), flat input surfaces, solid-lime wordmark,
  side-aligned brand lockup (aligned to the CARD's edge, mirrored by language), crisp
  rounded-rect mode switcher, and "switch account" rebuilt as an identity row with
  direct-entry account tiles. Three live defects were found in passing: the disabled CTA
  was 1.6:1 contrast (its default state on the gateway), button labels had no
  `lineLimit`/`minimumScaleFactor` and truncate at 13 sites, and the password-reveal control
  was a ~14pt tap target. Also: the password field had no `contentType: .password`, which
  breaks iOS Password AutoFill outright.

**Process note that keeps paying off:** every round, an adversarial review agent found real
defects in the previous round's work (including a `ViewThatFits` that would have destroyed
text-field focus the moment the keyboard appeared). Do not skip it.

## 5d. GATEWAY ADOPTED + INSTANT SIGN-IN (build 65 → **v67**)
- **`GatewayView()` is now the real not-logged-in root** (BlankTVApp). `SubscriptionsGateView`
  is retired (still compiles, unreferenced); the temp preview button is gone; the reseller
  support link was moved onto the gateway footer.
- **`ContentBootView` deleted.** Sign-in lands on the app instantly; the tabs' own skeletons
  cover the first load. **The mechanism:** `AppRouter.contentReady` is now a COMPUTED
  property whose setter bumps `@Published contentGen`, and the tab stack carries
  `.id(router.contentGen)`. The eight `contentReady = false` writers in Services.swift are
  unchanged. **Do NOT turn `contentReady` back into a stored `@Published Bool` with an
  `.onChange` observer** — those sites write `false` over `false`, the observer never fires,
  and every switch/refresh leaves the tabs on a skeleton forever (this exact bug was caught
  in review before it shipped).
- `loginXtream`/`loginM3U` now call `ContentCache.reset()` (they also run from "add account"
  while signed in). Cancelled loads no longer record errors (`guard !Task.isCancelled` in
  every VM catch). `ErrorView` retry and Home pull-to-refresh pass `force: true`.
- **Keyboard:** `defaultScrollAnchor(.bottom)` was the cause of "the keyboard is very far
  away and the screen jumps". Keyboard avoidance shrinks the scroll view's FRAME; a bottom
  anchor re-pins content to it, so the block translated by the full keyboard height on top
  of UIKit's own scroll-into-view. **Never re-add a bottom scroll anchor to a form.** The
  card is kept low by a top inset derived from the WINDOW height (probe inside the
  `.background`, which ignores the safe area and so never shrinks for the keyboard).
- Field fixes: password field was missing `ltr: true` (+`contentType: .password` in
  AuthViews — without a paired password field iOS AutoFill never engages); username/password
  use `.asciiCapable`; the reveal toggle re-asserts focus on the next runloop.

## 5e. THE LAYOUT SYSTEM — `S8KMetrics` (2026-07-26)
Owner asked for "one studied engineering design across every screen, with fixed standards".
An architecture review found the real problem: layout numbers were re-derived per page and
patched device-by-device. `S8KMetrics` (in `DesignSystem.swift`) is now the single source of
truth. **Read `DEVICE_MATRIX.md` §6b/§6c/§7 before touching any layout.**

- `S8KDeviceClass` — six classes (compactNarrow/Regular/Wide, regularMedium/Large/XL) with
  boundaries at 390 / 414 / 720 / 1100. Branch on THIS, never on a raw width.
- `S8KMetrics` — derived from the WINDOW + size classes + safe area. Exposes `gutter`,
  `gridSpacing`, `contentMaxWidth`, `readableMaxWidth`, `formMaxWidth`, `topBarReserve`,
  `bottomClearance`, `heroHeight`…
- `S8KMetricsRoot` — installed ONCE around the TabView; injects `\.s8kMetrics`.
- **`heroHeight` is the one hero formula**, full-bleed, with the invariant
  `hero + 88 + bottomClearance ≤ window height`. It replaced three disagreeing per-page
  formulas, two of which produced a hero taller than the viewport.

**Adopted so far:** the three hero sites, and `bottomClearance` at 13 spacer sites.
**Not yet adopted (deliberate — they change approved visuals, owner sign-off needed):** the
width caps, the grid/rail metrics, and the 13 hard-coded top paddings. Until they are, the
old literals still live alongside the system — do not assume a number in a view is canonical.

## 5f. DETAIL PAGES REBUILT — the distinctiveness fix (2026-07-26, v73)
**Read this before touching `MovieDetailView` / `SeriesDetailView`.**

A line-by-line audit against `Strong8K/iOS` found the detail pages were **a fork, not a
resemblance**: 9 of 11 elements were byte-for-byte identical SOURCE, four of them carrying
Strong8K's own code comments verbatim into this binary (the actions row, the section header,
the synopsis block, the episode row, the info chip recipe, the dismiss gesture *including its
80/120 constants*, the cast chips). The four main pages had genuinely diverged — the detail
pages had not moved at all, which is precisely what made them the evidence.

**They are now rebuilt as "pinned canvas + editorial plinth":**
- The artwork is a FIXED canvas; content rises over it on an **opaque** plinth (Apple: glass
  belongs to the navigation layer, never a content background).
- **The title is LIVE TYPE on the plinth, never an image composited onto artwork.** This is
  the biggest break from the whole category *and* it fixes contrast, Dynamic Type, RTL and
  missing artwork at once — a type-led page still works when the catalogue has no backdrop,
  which [[metadata-agnostic-design]] requires.
- Primary action = a **content-sized capsule** with an inset progress rule + 48pt circular
  glass satellites — the same vocabulary as the main pages' tool rows. **Never a full-width
  bar plus rounded squares**: that strip is the most-copied element in streaming and was
  identical to Strong8K line for line.
- Synopsis clamps to **4 lines**, expands in place. `MetaSection` was **deleted** (not left
  unused) so the borrowed motif cannot be reintroduced.
- **Episode rows are inverted**: oversized numeral in its own gutter, thumbnail on the
  OPPOSITE side, resume as a rule along the thumbnail's bottom edge. The three things that
  ARE Strong8K's row — a 120×68 leading thumbnail, a 32pt circular play badge on a black
  scrim, a trailing chevron — are gone. Numerals go through `NumberFormatter`, so Arabic
  renders ١ ٢ ٣.
- Everything mirrors by LANGUAGE (`s8kIsRTL` / `s8kTextAlign` / `s8kFrameAlign`), because the
  app forces `layoutDirection = .leftToRight` globally — child ORDER is flipped by hand. The
  ▶ glyph deliberately does NOT mirror (media transport controls keep their direction).
- `BrandTheme.strongGold` (an unused palette reproducing Strong8K's exact #0A0A0A/#FFD700)
  was deleted — it shipped inside the binary of the app we argue is a distinct product.

**Do not "simplify" any of this back toward the common pattern.** Every choice above is the
distinctiveness argument.

## 6. Remaining tasks (priority order)
1. ~~Fix the gateway bug → adopt it → remove the preview button~~ **DONE** (§5, §5d, v67).
2. ~~**Post-login instant flow**~~ **DONE** (§5d, v67).
3. **TMDB posters via the owner's central server** (safe/legal, App-Store-accepted, with mandatory TMDB attribution): BLANK currently points to `strong8k.app/api/v1` (APIConfig, Core.swift:571) but was DELIBERATELY SEVERED from the central `/v2/*` endpoints (ActivationService.swift:5). Strong8K's server has TMDB enrichment (`CentralVOD /v2/vod/info`) + central EPG (`CentralEPG /v2/epg/*`) + `CatalogCentral`, gated by `X-App-Key`. **Owner decision needed:** does his server serve BLANK on `/v2` + issue an app key + expose a "gateway posters" endpoint? Then build the client (fetch TMDB poster URLs → marquee via S8KImage + attribution + bundled fallback). No TMDB key in the app.
4. **Central EPG brain** (after #3): port `CentralEPG` (sync→match to a rich global EPG, now/next + full guide) + on-device `epg_cache` (add a table to CatalogDB, we already own it) for instant guide paint.
5. **Complete catalog-store population for the pure-Xtream-credentials path** (currently only M3U/Xtream-direct shadow-write; add the Xtream path so FTS/store benefit all users).
6. **Paged-list VM rewrite** (task deferred): convert MoviesVM (then Series/Live) to windowed keyset reads from CatalogDB behind `isPopulated` + full in-memory fallback. Hot path, big — owner sign-off first.
7. **KSPlayer** — optional/deferred (NOT the core, see [[player-engine-ksplayer]]): only if owner buys the LGPL license, as an additive `.ks` engine for AV1/DoVi/HDR10+.

## 7. Architecture map (key files under BlankTV/)
- `BlankTVApp.swift` — app entry, `AppRouter`, the launch flow: `SplashView` → `ActivationGate` → (loggedIn ? `contentReady ? tabView : ContentBootView` : `SubscriptionsGateView`). tabView = TabView with the 5 tabs; custom `AppTabBar` overlay.
- `Core.swift` — `L()` localization dictionary (ar/en/fr/tr/es), `Store` (UserDefaults), `APIConfig`/`APIClient`, `M3UContent`/`M3UParser`, `CatalogDiskCache` (legacy JSON cache), `CatalogDB` (new SQLite store), `PlaylistService`/`XtreamService` actors, `DemoContent` (Blender CC posters).
- `Services.swift` — `AuthService` (login/logout/switchPlaylist/enterDemo, `loggedIn`/`error`/`isLoading`), `ConfigService`, `ActivationService`.
- `PlayerEngine.swift` — `BasePlayerVM`, `AVPlayerVM`, `PlayerEngineSelector` (`initialKind` → user pref → EngineDecisionCache → StreamRouter), `MediaPrefetcher`, `KeepAwake`. `VLCPlayer.swift` = `VLCPlayerVM`. `PlayerView.swift` = the player UI + engine failover.
- `ContentViews.swift` — `LiveTVVM`/`MoviesVM`/`SeriesVM` + their views, `SearchVM` (FTS), detail views, `UnifiedReorderView`.
- `HomeView.swift` — `HomeVM` (`bootLoad`), Home editorial feed, `ContentBootView`, `AlertsView`.
- `SettingsView.swift` — `SettingsProV2` hub + sub-pages + `SetUI`/`SetScaffold` + `EngineStatsView` + `AccountSwitcherView` + `PlaylistsView` + `ParentalControlView`.
- `AuthViews.swift` — `SplashView`, `LoginView` (Xtream/M3U form + reseller-code logic), `SubscriptionsGateView` (pre-login account list; hosts the TEMP gateway preview button).
- `DesignSystem.swift` — tokens (`s8k*` colors = a GREEN/lime palette; `S8KGradient.goldFlat` = lime; `S8KFont`, `S8KRadius`, `S8KSpace`, `S8KButtonStyle`), `S8KImageCache`/`S8KImage` (+ ThumbHash), `SkeletonBlock`/`S8KPosterGridSkeleton`/`S8KListSkeleton`, `LoadingView`, `AppTab`/`AppTabBar`, `S8KTextField`, `GoldButton`, `BrandLogo`, `S8KWordmark`, `S8KConfirm`, glass helpers.
- `GatewayView.swift` — the new login gateway (§5). `Models.swift` — `Channel`/`Movie`/`Series`/`Category`/`Episode`/`ContentItem`/`SavedPlaylist`/`LoginMode`/`StreamQuality`/`AppError`. `Downloads.swift`, `ActivationService.swift`, `ActivationView.swift`, `Diagnostics.swift`, `RailEngine.swift`.

## 8. Gotchas & lessons
- **I cannot see rendered SwiftUI.** Visual/layout bugs (the whole gateway saga) only surface on device. For layout: prefer the SIMPLEST reliable pattern, avoid clever GeometryReader/ScrollView combos in fullScreenCovers, and get an HTML mockup approved BEFORE building. Trust device tests over agent "it will render" reasoning.
- `ContentItem.id` = `"live_…"/"movie_…"/"ep_…"` (namespaced string) — safe cache/ForEach key.
- Scope key for CatalogDB/CatalogDiskCache = `Store.shared.m3uURL` (the saved playlist URL).
- The app forces `.environment(\.layoutDirection, .leftToRight)` globally (BlankTVApp) — Arabic text still shows RTL via per-view modifiers, but layout is LTR (so "leading"=left, "trailing"=right).
- Memory files at `…/memory/` auto-load each session (MEMORY.md index): blank-tv-project, owner-ghannam, build-verify-constraints, player-engine-ksplayer, catalog-store-grdb, design-distinct-from-strong8k, filmm-reference, etc. Read them first.

## 9. Performance pass (builds 74–77 → TestFlight 76–79)

Ordered by benefit-to-risk and executed one item per build, each behind a
compile review + an adversarial review. Every round found a real defect, which
is the only reason to keep running it.

| # | Item | What was actually wrong |
|---|------|-------------------------|
| P2 | Windowed lists/grids | `LazyVStack`/`LazyVGrid` defer building VIEWS, but `ForEach` still walks the WHOLE collection to build its identity map on every invalidation, and `Array(channels.enumerated())` materialised one tuple per channel each time. 56k tuples per keystroke on a big line. Now 120 rows + 180 per step, grown from a 1pt sentinel a lazy container only builds when scrolled to. |
| P3 | Stale posters | On a cache miss a recycled `S8KImage` kept the PREVIOUS url's bitmap while it awaited — the "wrong artwork while scrolling fast" report. Also started the download before the ThumbHash decode instead of after. |
| P4 | ThumbHash memo | `thumbHashImage` hit SQLite and re-decoded on every cell appearance; `hasImageHash` sat on `fetch`'s return path. |
| P5 | Folded search | `searchResults` was a COMPUTED property read from the body → a full ICU sweep of the catalogue per render AND per keystroke. Names folded once at load, needle once per query, plain substring match, one-entry memo. |
| P6 | Live zap | `automaticallyWaitsToMinimizeStalling = !isLive` — the stall-proof buffer wait is right for VOD, wrong for channel flicking. |
| P7 | Partial-failure tolerance | One slow list (usually VOD, the largest payload) used to fail the whole login over a perfectly good channel list. |
| P8 | Favourites hoist | Every `ChannelRow` held its own `@StateObject` on the singleton — one state box + one Combine subscription per visible row, churned on every scroll. |

### The defect the review caught in P7 — worth remembering
Making the catalogue partial-tolerant is only half the fix. `_load` persisted the
result unconditionally, so a VOD timeout would have written `movies = []` over
the last good 12-hour disk cache AND wiped the FTS rows (`CatalogDB.save` deletes
the scope before re-inserting). The user would then see an empty Movies tab with
**no error to retry from**, surviving a relaunch, recoverable only through the
playlist manager. A degraded catalogue is now flagged `M3UContent.isPartial` and
never persisted: serving a partial for one session is fine, recording it as the
truth is not.

**Rule this generalises to:** any change that makes a load *tolerate* failure must
also decide whether the tolerated result is allowed to become the cached truth.

### Also worth keeping
- The scope-audit regex must be `var` + `\s+` + the symbol + a word boundary, not
  `var $sym\s*(:|=|\{)` — the
  latter misses `@Environment(\.s8kMetrics) private var metrics`, and that gap is
  what let build 72 fail. Strip comments AND string literals before auditing, or
  `L("search.title")` reads as a use of `search`.
- Window resets must key on the HEAD ITEM, not the count, and live on a `Group`
  wrapping both branches: keyed on count, toggling one favourite in a >120-item
  favourites list collapses the content height and throws the scroll position;
  placed inside the `else`, the modifier is destroyed on a 5000 → 0 transition
  and never fires.
- An `async let` child task is *nonisolated* — it must not read a main-actor
  stored property of a View. Copy to a local first.

## 10. Still open
- **Blocked on the server:** the "دليل البرامج" button and the guide grid need a
  batched `GET /v2/epg/guide?host=&ids=&from=&to=` (~30 lines on
  `strong8k-panel/routes/epg.js`; `/guide` is currently single-channel). Never
  build a guide from per-channel provider requests — fail2ban on IPTV panels bans
  an IP for 24h after >10 requests/10 min. The two-axis grid must be a custom
  `UICollectionViewLayout` + `UIHostingConfiguration`, never nested SwiftUI lazy
  stacks.
- **"التفاصيل" button:** needs `Movie` widened to keep the `get_vod_info` fields
  currently discarded (country, releaseDate, originalName, ageRating, trailer,
  codec, resolution, audio channels, bitrate, tmdbID) — zero new network calls.
- **P9:** `CatalogDB` migration `v3_epg` (rich columns, off-main reads/writes, prune).

## 11. App Store readiness pass (builds 78–91 → TestFlight 80–93)

An App Review simulation, a differentiation audit, a touch audit and a technique
adjudication were run against the app; all four reports live at the repo root and
should be read before re-deriving any of this:

| file | what it holds |
|------|---------------|
| `APP_REVIEW_AUDIT.md` | every guideline finding, with the review-notes draft |
| `DIFFERENTIATION_REPORT.md` | measured similarity to the reference, by dimension |
| `TOUCH_AUDIT.md` | 9 BROKEN controls, 62 sub-44pt targets, 26 missing a11y labels |
| `TECH_ADJUDICATION.md` | reference techniques judged against 2026 practice |
| `SHARED_STRINGS.md` | the string-by-string inventory the copy rewrite was driven from |
| `TYPE_SCALE_PROPOSAL.md` | the proposed type/spacing scale, unimplemented |

### The rejection that was sitting in the binary
Six **commercial film posters** were bundled and rendered full-screen on the login
screen — `gwposter1` was the Marvel Studios *Thor: Ragnarok* one-sheet, and one of the
six carried the illustrator's own watermark. An IPTV player whose first screen is a
wall of unlicensed studio art is the textbook 5.2.3 rejection. All six are now Blender
open-movie posters (CC-BY), replaced in place under the same asset names so the project
file was untouched. **Never put artwork in this app that the owner cannot license.**

### Other guideline work closed
- **2.1** — three surfaces offered a reseller code, and `ActivationService.resolveCode`
  returns `false` unconditionally. A promised feature that cannot succeed. Removed.
- **5.1.1(v)** — "delete my account" was a no-op in demo mode (`enterDemo` never sets
  `mode`, so the `.xtream` default made it attempt a backend call that threw before the
  network and took every cleanup line with it). It also left the SQLite catalogue, the
  disk cache, the downloads and the Keychain device ID behind. All fixed. **`logout()`
  must never reach those purges** — regenerating the device identity on every logout
  breaks activation binding.
- **5.2.3** — the player-only disclaimer moved to the gateway footer, the one screen a
  reviewer is guaranteed to open.
- `PrivacyInfo.xcprivacy` is present and correct. An audit claimed `3B52.1` should be
  `C617.1`; it should not — `3B52.1` is for files in the app's own container, which is
  what this app touches. Do not "fix" it.

### Copy — measured, not estimated
Shared Arabic values fell **84.4% → 55.8%**, shared English **82.1% → 56.9%**, measured
against the reference's own table. 72 dead keys were deleted rather than rewritten.
**~50 strings were deliberately left identical**: أفلام، مسلسلات، إلغاء، حفظ، الكل،
دقيقة، ترجمة، Sign in, Cancel, Save. They are simply the words, and a thesaurus pass
over them produces copy that reads generated. Distinctiveness comes from the sentences.

### Live defects found and fixed (none were visible in review; all were real)
1. A spinner over playing video — KVO without `.initial` never fires for an item that
   is ALREADY `.readyToPlay`, which is exactly what `MediaPrefetcher` hands over.
2. Lost resume points — `cleanup()` saved progress, `load()` did not, and `load()` is
   the zap / next-episode path. Fixed in BOTH engines.
3. A download library one bad byte from gone — the manifest decoded all-or-nothing.
4. The series resume button always said episode 1 — "first episode under 90%" is
   satisfied by episode 1 forever. Also: history was capped at 50 rows GLOBALLY, so a
   minute of channel zapping evicted episode progress.
5. A near miss on a playlist row's "…" menu switched the playlist.
6. The tab bar was drawn over every confirmation dialog.
7. Ending the hold-to-2× gesture toggled the player controls every time.

### The rule that produced most of this
Every change went through an adversarial review before its build. **The review caught a
real defect in every single round, including three of my own**: a live-zap change that
disabled AVPlayer's stall recovery (Apple documents that with waiting off the player
does not resume by itself), a modal-blocking counter that could have hidden the tab bar
permanently, and a compile error left by a deletion. Do not skip it.

Corollary, learned the same way: **be as sceptical of the reviewers as of the code.**
One claimed the app phoned home on first launch — `APIClient` throws before opening a
connection. Another claimed every background task reads a nil Keychain — no background
path reads the Keychain at all. Verify, then act.

## 12. Server
`strong8k.app/v2` is served by **`/opt/s8k-dev`** (PM2 `s8k-dev-panel2`, port 3200) —
despite the name. `/var/www/strong8k` is the old `:3000` API and has no `/v2`.
`/opt/s8k-staging` (3201) is stale and is not a valid test bed.

A batched `GET /v2/epg/guide?ids=` was deployed there and verified live. It also fixed a
**remote 500 that was live in `/nn`**: `ids=constructor` resolved to the inherited
`Object`, which is truthy and not iterable. Every accumulator keyed by client input is
now `Object.create(null)`.

The server's copy of `routes/epg.js` was AHEAD of the local repo (it has a `/enrich`
TMDB route) — the change was applied on top of the live file, not copied over it.
**Always diff before deploying.** Rollback: `routes/epg.js.bak-20260728-001011`.
Still open there: no rate limiter on `/v2/epg/*`, and `APP_KEY` ships in every client.

## 13. What is next, in order
1. **Type scale stage 2** — stage 1 (moving 19 hard-coded text sizes onto the tokens,
   visually neutral) is shipped. Stage 2 re-cuts the scale: base 17 / ratio 1.25, a
   floor of 11pt (`caption2`=10 and `caption3`=9 are under Apple's documented minimum),
   Dynamic Type support (every token is a fixed `Font.system(size:)` today, so nothing
   responds to the user's text-size setting), and a step between `title3`=18 and
   `title2`=22 — the gap that forced 20 headlines to invent their own size.
   Device-verify three things: the hero height floor (`DesignSystem.swift:179`), the
   poster column count on 414pt phones (`ContentViews.swift:1894` — 3 columns need
   376pt of 382pt available), and the player action row.
2. The remaining touch-audit items: 62 sub-44pt targets, 26 missing a11y labels, and
   B3/B6 leftovers. `HomeView`'s `navBar`/refresh confirm is **dead code** — wire it or
   delete it.
3. The brand kit — one file for palette, logo, app name and support links, with the
   button ink computed from the accent's luminance (a dark accent currently makes
   button text vanish), plus a lint that fails the build on a hard-coded colour or name.
   The app name is still baked into 5-language sentences.
4. Credentials: `Store.m3uURL` holds the user's IPTV username and password in a query
   string in **UserDefaults**, unencrypted and in unencrypted backups. Moving it to the
   Keychain needs `AfterFirstUnlockThisDeviceOnly` (the class currently pins
   `WhenUnlockedThisDeviceOnly`) or the background download relaunch reads nil.
5. Blocked on the owner: publish under a neutral identity vs. sell; a Blank domain to
   replace `strong8k.app`; and whether to deploy the panel's 5 unpushed commits.

_End of handoff. Live TestFlight = build index 91 → version 93._
