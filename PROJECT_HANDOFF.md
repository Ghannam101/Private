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

_End of handoff. Current live TestFlight = build index 61 → version 63 (gateway preview has the foreground bug; everything else is good)._
