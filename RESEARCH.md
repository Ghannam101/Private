# BLANK TV — Engineering & Design Reference (كبير المهندسين)
*Living reference. Owner: Ghannam. Engineer/Design lead: Claude. Started 2026-07-21.*
*Purpose: the single technical source of truth for reaching Filmm/Netflix-grade — fast, smooth, professional. Revisit every cycle to check we're still on the road to the top.*

> Status: assembled from (a) a real code review of the current app, (b) my own read of the
> speed-critical path, and (c) deep web research. Sections 3–6 (design, Xtream API, M3U,
> SwiftUI perf) are appended as research completes. `DESIGN.md` = look/identity; this = how.

---

## 0. The mission, in one line
Filmm-grade **look** + Netflix-grade **speed** on a pure Xtream/M3U player, universal
(iPhone+iPad+Mac), reusing the Strong 8K engine, App-Store-4.3-distinct. Never sacrifice
usability or speed for "different".

---

## 1. Current architecture — honest review (what we actually have)

**Strong foundations (keep, don't rewrite):**
- Actor-isolated networking (`PlaylistService`, `APIClient`) — I/O off the main thread.
- **Single-flight fetch** (`inFlight: Task`, Core.swift:1631) — the boot screen fires
  `load()` 3× at once; they coalesce into ONE catalog fetch. Prevents rate-limit empty-home.
- Category fetch (3 calls) and stream fetch (3 calls) each run **concurrently** via `async let`
  (Core.swift:1901–1926) → login waits ≈ slowest call, not the sum.
- **Professional image cache** `S8KImageCache` (DesignSystem.swift:488): NSCache + URLCache,
  ImageIO **downsampling**, off-main decode via `byPreparingForDisplay()`, single-flight per key,
  bounded prefetch. Hand-built, genuinely good.
- **Instant cold start** via `CatalogDiskCache` (Core.swift:1494) — 12h TTL disk copy paints
  home immediately on relaunch. Biggest first-paint win we already have.
- Clean hybrid player with bounded retry/failover; resume position; next-episode countdown.

**The gap to Netflix/Filmm is concentrated in 4 areas + dead code:**

| # | Weakness | Where | Fix |
|---|----------|-------|-----|
| 1 | **Inline browser search: NO debounce, filters full catalog in `body` on main thread** every keystroke | ContentViews.swift:84–86, 1192, 1605 (used 186/276/1276/1292/1688/1707) | Move to debounced (~300ms) VM method publishing `searchResults`, mirror the good `SearchVM` (2367–2407). **Biggest felt-latency win.** |
| 2 | **3 browser VMs not `@MainActor`** → mutate `@Published` + run `Dictionary(grouping:)` off-main after `await` | ContentViews.swift:13/596/1555, mut 618–640 | Annotate `@MainActor`; push grouping into `Task.detached`, assign back on main. |
| 3 | **Catalog fetch single-shot, `JSONSerialization`-parsed, non-incremental**; huge blob fully materialized | Core.swift:1820–1822, 1929–1973 | Codable DTOs off-main; **paint live/movies/series as each finishes** (boot flags already exist, HomeView.swift:109–121); per-category lazy for "All". |
| 4 | **No PiP & no real AirPlay for VOD** — all mp4/mkv forced to VLC | PlayerEngine.swift:691–701, 291 | Route progressive mp4/mov/HLS → AVPlayer (native PiP/AirPlay/HDR); keep VLC only for ts/mkv/exotic. See §2. |
| 5 | Disk cache **serve-only, never background-revalidates** (comment claims SWR, code doesn't) | Core.swift:1652–1658 | After serving cache, kick a background `force` refetch + diff-update VMs. |
| 6 | Main-thread whole-catalog **sort/group at load** (`rebuildHero`/`rebuildRails`) | HomeView.swift:58–59, RailEngine.swift:96–125 | Run in detached task, hand back finished arrays. |
| 7 | Image cache `countLimit=240` low; `maxPixel=800` for 116pt cells (~2× oversized); prefetch tasks never cancelled | DesignSystem.swift:494/559, ContentViews.swift:1482/1842 | countLimit ~500–800; maxPixel ≈350 for posters (1400 hero); cancel prefetch on scroll-away. |
| 8 | Whole-catalog `LazyVGrid` for "All" retains 100k identifiers | ContentViews.swift:1268, *PosterScreen | Cap/paginate "All" (render 300, grow on scroll). |
| 9 | VLC `network-caching=1500` conservative → slower VOD first frame | VLCPlayer.swift:261 | ~800–1000ms for VOD; tune per live-vs-VOD. |
| 10 | **Dead legacy proxy path** (`APIClient`/`XtreamService` + unused `cache`/`cacheTTL`) — all logins go direct now | Core.swift:543–667, 1181–1236 | Delete/gate to shrink surface & clarify data flow. |

**My own read confirms:** disk cache re-encodes/decodes a full Codable Envelope (slow cold
decode on huge lines); no gzip/ETag/If-Modified-Since for delta refresh; all VOD structs held
in memory at once (no pagination/lazy hydration).

---

## 2. Playback engineering — Netflix-speed (research-backed)

**Core principle: hybrid engine, route each stream to the right decoder.** Not either/or.

| Stream | Engine | Why |
|---|---|---|
| VOD MP4/MOV (H.264/HEVC + AAC) | **AVPlayer** | HW decode, PiP + AirPlay2 + HDR *free*, low battery/heat |
| HLS `.m3u8` | **AVPlayer** | native ABR + low-latency |
| Live raw MPEG-TS over HTTP (Xtream get.php) | **VLCKit** | AVPlayer can't play raw TS |
| MKV, AC3/E-AC3/DTS, VP9, exotic/malformed | **VLCKit** | software fallback "just plays" |

Build a `PlaybackEngine` protocol + factory inspecting URL/ext/codec. (We already route .m3u8→AV;
**extend: route progressive mp4/mov→AV too** so movies regain PiP/AirPlay — fixes weakness #4.)

**Fast START — AVPlayer recipe (WWDC16 S503):**
1. Create `AVPlayer` + `AVPlayerLayer` **before** assigning the item (avoids pipeline reconfig).
2. Async-load asset keys (`playable`,`duration`,`tracks`) during browse, not at press-play.
3. Cap first variant: `preferredPeakBitRate` low to start → **reset to 0** after playback climbs.
4. `preferredForwardBufferDuration ≈ 1–5s` to start fast → **reset to 0** after start.
5. `automaticallyWaitsToMinimizeStalling=true` for live; consider `false` only for warm-zap.
6. `preroll(atRate:)` before flipping rate to 1.0 for a clean first frame.
7. Watch `timeControlStatus` + `reasonForWaitingToPlay`, not raw `rate`.

**Fast START — VLC recipe:** the dominant knob is caching.
```
:network-caching=1000   // 300–1000 low-latency start · 3000–5000 flaky panels
:live-caching=1000
:clock-jitter=0  :clock-synchro=0
:rtsp-tcp  :drop-late-frames  :skip-frames
```
Lower `network-caching` = faster start, more stalls. Auto-raise after N stalls in M sec.

**Instant zapping (research: pre-joining prev+next kills delay for ~half of zaps):**
1. Warm player pool: current + 1 hidden pre-warmed adjacent player; swap on zap, warm next.
2. Prebuffer N-1/N+1 manifests+first segments in muted/paused background engines.
3. **Thumbnail-first:** show poster/last frame instantly, cross-fade to video on first frame.
4. VLC: keep the player alive, swap `media` only (never teardown+recreate — VideoToolbox setup
   is expensive). Reuse `VLCMediaListPlayer`.
5. Debounce fast list-scrubbing (~300ms settle) so you don't spin up dozens of engines.

**Next-episode / resume / background:** `AVQueuePlayer` preloads ONLY next item (enqueue
current+next, not whole season) + `preroll` → seamless cut. Resume via seek(to:) on async-loaded
asset. Background: `UIBackgroundModes:audio` + `AVAudioSession .playback`; detach playerLayer on
resignActive, reattach on active. PiP: `AVPictureInPictureController(playerLayer:)` (native, needs
bg-audio). AirPlay: `AVRoutePickerView` + `allowsExternalPlayback=true`.

**Buffering / recovery (flaky IPTV):** KVO `isPlaybackLikelyToKeepUp` / `isPlaybackBufferEmpty` /
`status`; notifications `AVPlayerItemPlaybackStalled`, `...FailedToPlayToEndTime`,
`mediaServicesWereReset` (session died → MUST rebuild player+audio session). Unstick a wedged item
with `seek(to:)`/`playImmediately(atRate:)`; dead stream → recreate `AVPlayerItem`. Exponential
backoff 0.5→1→2→5s, fresh item each try, re-seek to live edge.

**HW/thermal/HDR:** prefer HW decode (AVPlayer HW-only; VLC falls to software = heat/battery).
HEVC HW on A9+; AV1 HW only A17 Pro/M3+. HDR/Dolby Vision auto-configured by AVFoundation
(gate on `AVPlayer.eligibleForHDRPlayback`) — send HDR VOD through AVPlayer. Watch
`ProcessInfo.thermalState`; under serious/critical cap bitrate + disable HDR. AC3/E-AC3/DTS carry
Dolby/DTS **licensing** obligations if shipping decoders.

**Poster prefetch = perceived speed:** memory cost = pixel dims, not file size (4000×3000 ≈ 48MB
decoded regardless of JPEG size). **Downsample via ImageIO** (`CGImageSourceCreateThumbnailAtIndex`
+ `kCGImageSourceShouldCacheImmediately`) off-main to exact display size × scale. Two-tier cache
(NSCache+disk) keyed by id+size. Prefetch just-offscreen rows, cancel on reuse/scroll-away. (Our
S8KImageCache already does this — just needs the tuning in weakness #7.)

*Sources: WWDC16 S503; Apple AVFoundation/PiP/HDR docs; VLCKit wiki; predictive-prejoining
(ScienceDirect); Swift Senpai downsampling; Nuke/Kingfisher/SDWebImage.*

---

## 3. Modern OTT UI/UX (2026) — Filmm/Netflix/Shahid-grade

**Home architecture:** vertical stack of horizontal rails ("shelves").
- **8–15 rails.** Order: **Continue Watching first (above fold)** → Trending/New → 6–10
  personalized rows with *reasoned* labels ("لأنك شاهدت…") → genre/network rails. Fold discovery
  into Home, don't spread across tabs (Netflix direction).
- **Hero/billboard:** top ~55–65% of first viewport, full-bleed, bottom gradient scrim for text
  legibility. Personalized to ONE title. Netflix ships **CoreMotion parallax tilt** + **artwork-
  derived gradient wallpaper + a poster-colored border** (extract dominant color from poster =
  cheap cohesion trick — worth adopting with our lime accent).
- **Top-10 rail:** dedicated carousel, **large hollow/outlined numerals** overlapping posters
  (we already mimic this). One only, near top.
- **Continue Watching cards use 16:9 landscape** (frame grab + progress bar + time left), NOT the
  2:3 poster — differentiates from browse rows.

**Two card ratios, deliberately** — this is what reads as "professional":
- **2:3 portrait** → browse/genre/network/Top-10 rails.
- **16:9 landscape** → Continue Watching, episodes, hero backdrops.

**Card sizing (HIG-consistent, implement directly):** content margin 16–20pt; **8/16/24pt** spacing
grid; inter-card gap 8–12pt; **iPhone poster ~115–130pt wide** (so ~2.3–2.7 peek = signals scroll),
height = width×1.5; corner radius **6–10pt** (iOS 26: `cornerRadius: .containerConcentric`); touch
target ≥44×44pt. Bottom black→transparent scrim on any card with overlaid text. Rating badge = small
pill on a scrim, top/bottom-left. **Hover/focus (iPad/Mac/tvOS):** scale-up preview card w/ muted
autoplay clip, push neighbors out; animate `scale()` NOT `width`.

**Motion — SwiftUI spring presets (concrete):**
| Interaction | Spring |
|---|---|
| tap / favorite-heart pop | `.spring(response:0.3, dampingFraction:0.75)` / `.snappy` |
| toggle / small control | `response:0.35, damping:0.75` |
| default UI change | `response:0.55, damping:0.75` |
| sheet / detail present | `response:0.9, damping:0.8` / `.smooth` |
| Liquid Glass morph | `.bouncy` |
Damping 0.5=bouncy, 0.75=balanced, 0.95=subtle. **Prefer springs over easeInOut** (easing feels
mechanical). Use `interactiveSpring` for gesture-driven. Signature premium motions: hero tilt
parallax, **interruptible transitions** (grab a card mid-animation), cross-fades not hard cuts,
favorite pop 1→1.3→1 + `.light` haptic, sliding tab indicator (spring the position/width).

**Haptics:** `UIImpactFeedbackGenerator` light=frequent/minor, medium=standard, heavy=significant;
`UISelectionFeedbackGenerator` for tab/segment/season change; `UINotificationFeedbackGenerator` for
success/error. **Call `.prepare()`** before the moment; don't overuse.

**Detail screen (top→bottom):** full-bleed backdrop (16:9/trailer)+scrim → title + metadata line
(match% · year · rating · duration/seasons) → **glass action pills** (Play `.glassProminent`,
Trailer/+List `.glass`) → synopsis + cast (circular) → **season selector → episode list (16:9 thumb
+ title + duration + progress + time-left)** → "More like this". Player: sprite seek-thumbnails,
controls auto-hide after 3s, caption toggle persists across sessions/devices, PiP + AirPlay.

**Arabic/RTL:** mirror whole layout (nav, rails, chevrons, carousels, swipes) via
`environment(\.layoutDirection,.rightToLeft)`; **do NOT mirror** logos, photos, media controls
(play always points right), numerals/times/Latin text. Arabic type **+10–15% size** vs Latin,
**line-height 1.6–1.8×**. Fonts: **SF Arabic** (system default), Cairo, IBM Plex Arabic, Tajawal,
29LT Bukra (premium headers). Pair AR+Latin with matching weight/x-height for bilingual titles.
**Shahid = the Arabic benchmark** (localized artwork + AI rows). For RTL, mirror the shimmer sweep.

**Dark cinematic theming:** surfaces **#121212/#1E1E1E/#0D1117**, lighter grays for elevated cards
(depth without borders). **True black only for player/hero** (OLED). ONE saturated accent (ours =
lime), everything else grayscale; consider per-title accent from artwork. Text contrast ≥4.5:1.

**iOS 26 Liquid Glass:** glass ONLY on nav layer (tab/tool/nav bars, floating buttons, sheets) —
NEVER on content/lists/backgrounds. Native controls get it automatically; custom = `.glassEffect()`.
**Tab bar minimize on scroll:** `.tabBarMinimizeBehavior(.onScrollDown)`. **Now-Playing mini-player:**
`.tabViewBottomAccessory{}`. Search tab: `Tab(role:.search)`. Group with `GlassEffectContainer`,
morph via `.glassEffectID()`+namespace. Tint sparingly `.glassEffect(.regular.tint(...).interactive())`.
⚠️ **Glass is GPU/battery heavy** (~13% drain reports on 16PM, lag on 11–13) — keep to nav layer, no
continuous glass animation, test on 3-yr-old devices, graceful pre-26 fallback.

**Nav:** 4–5 tabs max on phone (Home/Live/Library/Profile); iPad side-nav above ~600pt; browse-to-
watch ≤3 taps; search needs typo-tolerant multilingual fuzzy match (AR/Latin/transliteration).

**Perceived speed (targets):** skeletons over spinners (~50% faster perceived), progressive image
reveal, optimistic UI, sprite seek. **Time-to-first-frame <2s (P50), cold start <3s, rebuffer <1%**;
abandonment +5.8%/sec above 2s (Akamai).

**Accessibility:** Dynamic Type mandatory (min 11pt, use text styles so rails reflow), contrast
4.5:1, targets 44pt (60 on TV), VoiceOver labels on every poster, Reduce-Motion → swap parallax for
cross-fades. Test Dynamic Type + RTL together.

*Sources: Fora Soft streaming UX; UX-News Netflix iOS redesign; Apple HIG; Liquid Glass Reference
(conorluddy); createwithswift springs; Shahid/CGI; Purrweb/Milaaj RTL; Ahmed Elramlawy Arabic fonts.*
*Note: Netflix/Shahid don't publish exact pt specs; dimensions above are HIG-consistent practice.
No credible case study for an app literally named "Filmm" — Shahid is the Arabic benchmark.*

---

## 4. Xtream Codes API — fast catalog + playback

**The governing truth:** `player_api.php` is an **untyped, UNPAGINATED JSON-over-HTTP** API. List
endpoints **dump the whole catalog** (only filter = single `category_id`); generating that array
can take the panel **10–75s** and stream **tens of MB**. It never returns playable URLs — you
**construct** them. Fields arrive as string-or-number inconsistently; EPG text is **Base64**. No
token/refresh — creds ride every request → hammering = **fail2ban IP ban**. Winning architecture
(universal across every serious client): **fetch once in background → streaming-parse into local
SQLite/FTS5 index → drive virtualized UI from the DB only → HLS for AVPlayer + VLCKit fallback →
warm player for zap.**

**Auth:** `…/player_api.php?username=U&password=P` (no action = `user_info`+`server_info`). Cache
`exp_date`, `status`, `is_trial`, **`max_connections`/`active_cons`**, `allowed_output_formats`.
⚠️ **Interop hazard #1 (top crash source):** numeric-looking fields are JSON **strings** — write
lenient `Codable` (string→Int/Bool coercion) everywhere. (Our code already does this via `str()`/
`intVal()` helpers — keep that.)

**Endpoints:** `get_*_categories` (tiny — fetch FIRST, render tree instantly) → `get_live_streams`
/`get_vod_streams`/`get_series` (the big dumps, optional `&category_id=`). Detail:
`get_vod_info(&vod_id=)`, `get_series_info(&series_id=)`. Key fields: live `stream_id`+
`epg_channel_id`+`tv_archive`; VOD `stream_id`+**`container_extension`** (REQUIRED for URL)+`added`
(delta key); series `series_id`+`last_modified`. ⚠️ **`get_series_info`:** derive seasons from the
**keys of `episodes`** (map keyed by season-string), NOT the `seasons` array (often empty); episode
**`id`** goes in the URL (not series id); flakiest endpoint — **retry up to 3×**. Old 1.x panels
have NO series endpoints — tolerate empty.

**URL construction (API never returns these):**
| | Template |
|---|---|
| Live TS | `host/live/U/P/{stream_id}.ts` |
| Live HLS | `host/live/U/P/{stream_id}.m3u8` |
| VOD | `host/movie/U/P/{stream_id}.{container_extension}` |
| Episode | `host/series/U/P/{episode_id}.{container_extension}` |
| Catch-up | `host/timeshift/U/P/{dur_min}/{YYYY-MM-DD:HH-MM}/{stream_id}.ext` (only if `tv_archive==1`) |
Always include `/live/` (newer panels break without it). VOD/series **require** exact
`container_extension`. Pick live ext from `allowed_output_formats` (try .m3u8 → fall back .ts).

**Performance at scale:**
- **NO reliable pagination** — `params[offset]`/`items_per_page` are documented in libs but **NOT
  honored** by panel PHP. Only real request-shrinker = per-`category_id`.
- **Payload/timing (measured):** `get_live_streams` = **~75s / ~6MB for 16k channels** (hit 60s
  nginx timeout → 504). 50k–100k VOD → ~tens of MB. **Use long READ timeouts, tolerate 504s, fetch
  ONCE in background, never main thread.** (⚠️ our current 45s timeout may be too short for big lines.)
- **Parsing:** Swift `JSONDecoder` ≈ **10 MB/s** (~10× slower than `JSONSerialization`, builds
  intermediate NSDictionary) → a 40MB blob = ~4s main-thread CPU + DOM RAM can OOM a phone. Use
  **ZippyJSON** (simdjson, 3–6×) or a **SAX/streaming parser** (YAJL) that inserts rows straight
  into SQLite then discards. (Our current `JSONSerialization` is actually the fast choice vs Codable
  — the real upgrade is streaming→SQLite, not switching decoder.)
- **Recommended hybrid:** categories first (instant tree) → background full dump → streaming-parse
  into **SQLite + FTS5** (instant global search on 100k) → **UI queries DB only**, virtualized,
  sectioned by category (no view holds 45k rows) → per-category fetch only for repair/fallback.
- **Delta refresh:** no server "changes-since" — re-download + diff client-side on `added`/
  `last_modified` vs local `MAX()`. ⚠️ **NEVER wipe cache on an empty/short response** — the XC API
  intermittently returns 0 results; naive replace = wiped library (real bug). (Our disk cache already
  guards empty on save — extend this guard to refresh.)
- **Transport:** gzip usually `off` in stock nginx (send `Accept-Encoding: gzip` anyway, assume
  uncompressed); **no ETag/304** (dynamic PHP) → freshness via own timestamps; reuse keep-alive
  connection across many detail calls.

**Reliability pitfalls:**
- **fail2ban:** panels run nginx `limit_req`/`limit_conn` + fail2ban, typical **findtime=600s,
  maxretry=10, bantime=24h** → **>10 req/10min = 24h IP ban**. Danger = refresh storms + retry
  loops. **Cache aggressively, stagger with jitter, long TTLs.** (Our single-flight already helps.)
- **`max_connections` = most misdiagnosed failure** (1–3 slots; ~⅓ of "buffering" tickets = a 2nd
  device holding the slot; slot frees ~2min AFTER teardown). ⚠️ **Direct impact on fast-zap:**
  pre-rolling channel N+1 while N plays **burns a 2nd slot → refused on a 1-connection line.** So
  tear down at/just before pre-roll; expect a stale-connection window. **This constrains §2 zapping.**
- Mid-session 401/403 → re-run auth ONCE to distinguish expired/banned from transient before retrying.

**EPG:** `get_short_epg(&stream_id=&limit=4)` (NOW/NEXT, on-demand) · `get_simple_data_table`
(full ~1000 rows) · `xmltv.php` (whole grid, heavy). Base64-decode title/description. Compute NOW/
NEXT from `start_timestamp`/`stop_timestamp` (Unix, UTC; `epg_shift` corrects TZ). `has_archive=1`
→ show a catch-up button. Cache parsed EPG, refresh ~4–6h. (Our `shortEPG` already does base64 +
5min cache — good; could add xmltv full-grid for a timeline UI later.)

**iOS playback (corroborates §2):** AVPlayer plays HLS natively but **canNOT play raw MPEG-TS or
MKV over HTTP** (`-11850 "Operation Stopped"`; same stream plays in VLC). → request `.m3u8` gated
on `allowed_output_formats`; route `mkv`/raw-`ts`/exotic audio → **VLCKit or KSPlayer**. Fast start:
`automaticallyWaitsToMinimizeStalling=false` + `playImmediately(atRate:)` + low
`preferredForwardBufferDuration` (reset to 0 after) + `preroll` + early-sized `AVPlayerLayer` +
small warm `AVQueuePlayer` pool — **respecting max_connections**.

**⭐ Best reference client for our exact stack — [bilipp/Lume](https://github.com/bilipp/Lume)**
(native SwiftUI Xtream/M3U for iPhone/iPad/Mac/tvOS/visionOS): **SwiftData** (~8 models:
Playlist/Category/LiveStream/Movie/Series/Episode/CastMember/EPGListing), `ContentSyncManager`
(6h/daily/weekly refresh + stale-title pruning), `ImagePipeline` cache + TMDB enrichment, **3
interchangeable engines w/ auto-fallback: VLCKit + KSPlayer + AVPlayer**. This is the blueprint.
Other clients confirm the pattern: IPTV Smarters (SQLite, instant reopen), OTT Navigator (12/24h
quick-start cache), TiviMate (XMLTV + 4–6h EPG save, tvg-id matching pain).

**Xtream vs M3U:** prefer **Xtream API as primary** (first-class categories, series season/episode
tree, catch-up, EPG in one API, per-category fetch). M3U re-downloads the whole flat file each
refresh — keep a streaming importer as fallback, classify by group-title + URL path.

**Confidence:** HIGH (cross-corroborated): URL templates, no-pagination/full-dump, Base64 EPG,
string-typing hazard, SQLite/FTS5 standard, 1–3 conn limits, AVPlayer-can't-play-raw-TS (direct
Apple evidence), never-wipe-on-empty. ESTIMATED: exact 50–100k payload size (extrapolated from 6MB/
16k). THIN: ETag unsupported (inferred), catch-up path varies by panel (implement w/ fallbacks).

*Sources: worldofiptvcom XC API doc v2.9.2; sherif-fanous Go structs; Dispatcharr #1220/#968;
metaobject JSON bench; ZippyJSON; SQLite FTS5; fail2ban nginx filter; panelsellers/lumiptv operator
guides; Apple forums 710481/767810; WWDC16 S503; bilipp/Lume; Nuke.*

---

## 5. Large M3U parsing at scale (50k–150k entries)

**Format (M3U Plus):** first line exactly `#EXTM3U` (no BOM/whitespace); header may carry
`url-tvg`/`x-tvg-url` (EPG). Entry = `#EXTINF:<dur> <attrs>,<display-name>` then optional
`#EXTGRP`/`#KODIPROP`/`#EXTVLCOPT` lines, then the URL line (which **closes** the entry). Everything
after the comma = human name. ⚠️ This dialect **breaks RFC 8216**: attribute values can contain
**unescaped commas/quotes** → naive `split(",")` is wrong. Attributes: `tvg-id` (EPG key, stable),
`tvg-name`, `tvg-logo`, `tvg-chno`, `group-title` (may be `;`-list), `catchup`+`catchup-source`,
`radio`. HTTP headers arrive 3 ways → consolidate: `#EXTVLCOPT:http-user-agent/referrer/cookie`,
`#KODIPROP`, and **pipe params** `url|User-Agent=X&Referer=Y` (split off the `|` before use).

**Parse = line-state-machine + ONE pre-compiled regex for attrs** (`([\w-]+)="([^"]*)"`). Never one
big multiline regex (backtracking + unescaped commas destroy it). Pre-compiling the regex = **78%
faster** (real benchmark). Find end of attr-run first, then name after next comma.

**Streaming/incremental (don't block, don't hold 50MB in RAM):**
- `URLSession.bytes(from:).lines` off the main actor — simplest, "surprisingly competitive."
- **Fastest + lowest RAM = `URLSessionDataDelegate`** chunked `Data`, scan for `\n` with
  `withUnsafeBytes`, keep tail partial line. Benchmark (100k-scale byte stream): delegate+chunks
  **36ms / 26MB peak** vs `bytes()` 79ms/91MB vs `data()`+per-byte loop **605ms** (full file in RAM).
  → Avoid per-byte `AsyncSequence` iteration and `data(from:)` for large files (10–20× slower).
- Emit entries in **~1000-item batches** hopped to `@MainActor` (never per-entry). Support
  `Task.checkCancellation()`. Kodi's cold parse of 20k+ channels = **5–15 min** without caching —
  hence persistence is mandatory.

**Data structures:** master = `ContiguousArray<struct>` with `reserveCapacity`. **Intern repeated
strings** (`group-title` etc. repeat 100k× but there are ~300 groups) → store small integer group
IDs; biggest memory win. Indexes: `[GroupID:[Int]]` and `[StreamType:[Int]]` (O(1) category select,
never linear scan). Search: normalized-fold background scan (simple) OR **SQLite FTS5** (recommended
at this scale, sub-100ms ranked).

**Persist = GRDB/SQLite (recommended over Core Data — CoreData `CONTAINS` slow; FTS5 fast+ranked).**
FTS5 external-content table synced via `synchronize(withTable:)`; plain indexes on group_id/
stream_type. **Bulk insert in ONE transaction** (per-row = 100× slower), reused prepared statement,
`PRAGMA journal_mode=WAL` + `synchronous=NORMAL` for a rebuildable cache. Re-open target: <1s from DB.
**Refresh:** serve DB immediately, background-refresh if older than interval (~24h); honor
**ETag/Last-Modified/Content-Length** to skip re-parse; delta = parse to temp table, diff by
`tvg-id` (stable) else hash(url+name), upsert/delete, swap atomically.

**Classify Live/VOD/Series from flat M3U (priority cascade):** (1) `#EXTINF` duration `-1`→live,
positive→VOD; `radio`/`media`→VOD. (2) **Xtream URL path** `/live/`·`/movie/`·`/series/` (very
reliable). (3) extension `.ts/.m3u8`→live, `.mp4/.mkv/.avi`→VOD. (4) `group-title` keyword analysis
(need AR keywords!). (5) name pattern `S01E02`/`1x02` → series, aggregate by (sanitized name,
season). (6) fallback. **If source is Xtream, prefer the JSON API over the M3U** (authoritative
categories + series hierarchy, no heuristics).

**Malformed handling:** never abort whole playlist on one bad entry — skip + collect `warnings`.
Sanitize first (strip BOM, normalize CRLF/LF — mismatched endings glue lines). Dedupe by stable key.
Tolerant UTF-8 (replace invalid bytes). Never `String(contentsOf:)` a 50MB file into one string.

*Sources: M3UKit; notsurewhoisthis/iptv-m3u-playlist-parser (benchmarks); Beer4Ever83/ipytv;
Kodi pvr.iptvsimple; Wade Tregaskis URLSession byte-stream benchmarks; GRDB FTS5 docs; Apple
URLSession.AsyncBytes / WWDC21.*

---

## 6. SwiftUI performance for huge catalogs (60/120fps)

**Frame budget:** 120Hz=8.3ms, 60Hz=16.7ms per frame; realistically **~5ms** main-thread for
layout+bodies before a hitch. `body` runs on main — any sync sort/format/decode there eats it.

**Container choice:**
- **`VStack`** = never (instantiates everything).
- **`ScrollView{LazyVStack/LazyVGrid}`** = good for rails/grids BUT created views are **retained**
  (memory grows monotonically as you scroll) and it estimates total height (evaluates ahead on fast
  scroll). 
- **`List`** = UIKit-backed **recycling** (discards offscreen, ~100 rows max alive) → **most stable
  for very long lists**. Netflix shape = `List`/LazyVStack vertical, each row =
  `ScrollView(.horizontal){LazyHStack}` (lazy rails).
- **`UICollectionView` via `UIViewRepresentable`** = escape hatch for 100k+ / real prefetch API
  (`prefetchDataSource`) / decode-ahead.
- ⚠️ Gotchas: **`.id()` on List rows breaks laziness** (instantiates all) — make models
  `Identifiable`+`Hashable` instead; **top-level `if/switch` in a List row breaks reuse** (wrap in
  `VStack`); offscreen cell `@State` resets (lift to VM).

**Stable identity = #1 lever:** `ForEach` needs stable unique IDs (server ID, NOT array index, NOT
`UUID()` in body — that re-instantiates everything every render). Positional identity re-renders ALL
rows on any insert/reorder.

**Do expensive work ONCE, never in body** (WWDC25 306): sort/filter/group/format in the VM on data
change; expose **precomputed display structs** (already-formatted strings, resolved URL, chosen
aspect ratio) so the cell body is pure layout. Cache derived values by ID in an `@Observable` model.
**Avoid `AnyView`** (erases identity, defeats diffing) → use `@ViewBuilder`/generics. **Avoid
per-cell `GeometryReader`** → use iOS17 `scrollTransition`/`visualEffect` or iOS18
`onScrollGeometryChange`. Keep `.onAppear` cheap (fires during scroll). Beware `.task`/`.onAppear`
inheriting `@MainActor` — push CPU to `Task.detached`, hop back for UI.

**Images = the real stutter cause** (synchronous decode as cell appears; won't even show in the
SwiftUI trace). **Plain `AsyncImage` is wrong for rails** (black-box decode, no memory cache, no
downsample, no prefetch/cancel). Four techniques:
- **(a) Downsample to display size** via `CGImageSourceCreateThumbnailAtIndex` +
  `kCGImageSourceShouldCacheImmediately` — 3648×5472 poster **87MB→11MB (~85% cut)**.
- **(b) Decode off main** on a **dedicated** bg queue (not global concurrent → thread explosion) via
  `preparingForDisplay()`, hand ready bitmap to main.
- **(c) Prefetch ahead + cancel offscreen** (cancel on `.onDisappear`/id-change).
- **(d) Use Nuke/Kingfisher** or our own cache (S8KImageCache already does a,b,d — needs the tuning
  from §1 #7). Best of all: **request pre-sized thumbnail URLs from server**.
- Reserve the exact aspect-ratio frame BEFORE load so rails don't reflow.

**Diffing:** **`@Observable` (Observation) beats `ObservableObject`** — property-level pull-based
invalidation vs coarse `objectWillChange` broadcast. Changing `item[42]` invalidates only the view
reading item[42]. **Don't read a whole array to answer a per-item question** (per-item sub-VMs cached
by ID so a favorite-toggle updates ONE row, not all). `@ObservationIgnored` for non-UI storage. Keep
fast-changing values out of `@Environment` (every reader pays a check). `Equatable` cell inputs +
`.equatable()` skip unchanged subtrees. `drawingGroup()` only for heavy overlapped art (hurts simple
views). Debug with `let _ = Self._printChanges()`.

**Memory:** tiny structs (IDs + URL + precomputed fields, no `Data`/`UIImage` embedded). Paginate/
window (load 20–100, page on scroll). Cap decoded-image cache (NSCache cost limit), drop far-offscreen
bitmaps. Store blobs as `Data` not `Image` (releases predictably). Decoded size ≫ file size (2MB JPEG
≈ 80MB decoded) — downsampling is the primary control.

**Profiling:** Instruments 26 **SwiftUI template** on release build/real device → *Long View Body
Updates* (red=hitch) → Time Profiler → **Cause & Effect graph** ("why did this update?"). Cross-check
Hangs + Animation Hitches. Image-decode hitches DON'T appear in the SwiftUI lane.

**iOS 17/18/26 scroll APIs:** `scrollTargetBehavior(.viewAligned/.paging)` + `scrollTargetLayout()`
for rail snapping (also triggers earlier data load). `scrollTransition`/`visualEffect` for focused-
poster scale/opacity without GeometryReader. `scrollPosition(id:)` for continue-watching restore.
`onScrollGeometryChange` (iOS18) for prefetch triggers.

**Skeletons:** `.redacted(reason:.placeholder)` turns real cells into gray shapes (matches final
layout) + shimmer = moving `LinearGradient` (~1.5–2s, RTL-mirrored). Reserve exact aspect-ratio
frames so no reflow; fade real image in on decode.

*Sources: WWDC25 306 / WWDC23 10248; Jacob's Tech Tavern 120FPS; fatbobman (List vs LazyVStack);
smork.info; The Case Against AsyncImage; Swift Senpai downsampling; SwiftLee @Observable; Apple
scroll APIs.*

---

## 7. Chief engineer's prioritized action plan (full synthesis)
Two tracks: **QUICK WINS** (small diffs, high felt-speed, low risk — do first) and the **BIG
ARCHITECTURAL MOVE** (SQLite/FTS5 — the real path to 100k-item Netflix-grade). Each item = build +
`chk.py` + agent compile-review + owner device review.

**TRACK A — Quick wins (order by impact-per-effort):**
1. **Debounce inline search off-main** (§1 #1) — cheap, biggest felt-speed win on big lines.
2. **`@MainActor` + off-main grouping for the 3 browser VMs** (§1 #2, #6) — fixes a real
   concurrency hazard AND the boot→home hitch. Do together.
3. **AVPlayer for progressive VOD (mp4/mov/HLS)** (§1 #4, §2, §4) — restores PiP/AirPlay/HDR on
   movies + hardware decode (faster start, cooler). Keep VLC for ts/mkv/exotic. Highest "feels
   premium" playback win. Verify each container routes correctly.
4. **Progressive catalog paint + background revalidate** (§1 #3, #5) — home appears as each of
   live/movies/series lands (boot flags exist); after serving disk cache, background `force`
   refetch + diff-update. ⚠️ **NEVER wipe cache on an empty/short API response** (§4 — real
   library-wipe bug); extend our existing empty-guard to refresh.
5. **Image cache tuning + prefetch cancellation** (§1 #7, §6) — countLimit ~500–800, maxPixel ≈350
   for posters (1400 hero), cancel prefetch tasks on scroll-away. Smoother scroll, less re-shimmer.
6. **Paginate "All" grids** (§1 #8) + **VLC VOD buffer tune** to ~800–1000ms (§1 #9) + **raise the
   catalog fetch READ timeout** for big lines (§4: panels take 10–75s) — memory + start latency.
7. **Delete dead proxy path** (§1 #10) — clarity, smaller binary. Low risk, do when touching Core.

**TRACK B — The big architectural move (schedule deliberately, biggest long-term payoff):**
8. **Migrate the catalog store from one JSON Envelope → SQLite (GRDB) + FTS5** (§4, §5, §6). This is
   what every serious client (Lume/IPTV Smarters/OTT Navigator) does and the real unlock for 100k
   items: **streaming-parse straight into the DB** (bounded RAM, no 40MB blob/OOM, no ~4s decode
   hitch) → **FTS5 global search <100ms** → **UI queries DB only, virtualized & sectioned by
   category** (no view holds 45k rows) → instant re-open. Reference blueprint: **bilipp/Lume**
   (SwiftData, ContentSyncManager 6h refresh + stale pruning, 3-engine fallback). Big change —
   plan it as its own milestone with owner sign-off; can ship incrementally (DB behind the existing
   `ContentService` facade first, then swap UIs to query it).

**Design track (parallel, per §3 + DESIGN.md):** two card ratios (2:3 browse / 16:9 continue+
episodes); artwork-derived hero accent; iOS 26 Liquid Glass on nav layer only + tab-minimize-on-
scroll + Now-Playing accessory; spring/haptic specs; RTL audit (+10–15% Arabic type, mirror
shimmer); skeletons via `.redacted`. Prefer **`@Observable`** over ObservableObject for new VMs.

**Hard constraints to weave into every task:**
- **max_connections (1–3 slots):** warm-player/adjacent-prebuffer zapping (§2) **burns a 2nd slot**
  → tear down before pre-rolling on a 1-connection line. Don't over-parallelize stream requests.
- **fail2ban (>10 req/10min = 24h ban):** cache aggressively, jittered/staggered refresh, no tight
  retry loops. Our single-flight already helps — preserve it.

**Guardrails (never violate — DESIGN.md §5):** top bars `.safeAreaInset` not ScrollView child; no
glass-on-glass; no heavy shadows in big grids; sort/derive/format ONCE in VM never in `body`; stable
`Identifiable` IDs (never `UUID()` in body, never `.id()` on List rows); `chk.py` + agent compile-
review before every commit (no local compile on Windows); update BOTH iPhone `browser` and iPad
`padBrowser` layouts.
