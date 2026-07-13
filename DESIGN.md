# BLANK TV — Design Concept & Blueprint
*The single source of truth for BLANK TV's identity, layout, and differentiation.*
*Owner: Ghannam. Engineer/Design lead: Claude. Started 2026-07-13.*

---

## 0. Why this document exists
BLANK TV reuses the **engine** of the shipped app *Strong 8K* (same player, activation,
Xtream/M3U, backend) but must be a **genuinely different product** with its own identity —
so Apple accepts it as a NEW app, not a clone (Guideline 4.3). This doc records the research,
the creative concept, and the concrete per-screen blueprint so we build with confidence and
stop guessing.

---

## 1. The truth about Apple 4.3 (so we aim correctly)
4.3 ("Spam / clone") targets apps that are **repackaged / near-identical** to another app,
**especially from the same developer**, with only trivial differences. It does **NOT** ban
standard streaming UI patterns (hero + rails, poster grids, EPG) — Netflix, Shahid, TOD, IBO
all share patterns and coexist. What clears 4.3 is a genuine, distinct **identity + concept +
experience + store presence** — NOT a bizarre/unusable layout.

**So our target = a distinctive, *tasteful* product** (own brand, concept, look, metadata),
not a weird layout for its own sake. Usability must never be sacrificed to "look different".

**Differentiation levers we will maximize (vs Strong 8K):**
1. Brand identity — DONE: lime/teal on deep-green (vs gold/black), new icon, "BLANK TV".
2. Core concept & metaphor — THIS DOC (a unified, content-first cinematic canvas).
3. Layout/structure — distinct per-screen blueprints below (not restyles).
4. Signature interactions — multi-subscription gate, glass tab bar, immersive spotlight.
5. **App Store presence** — distinct screenshots, description, keywords (CRITICAL, still TODO).

---

## 2. Research — what users love / hate (IPTV & streaming, 2026)
**Loved (build these in / lean on them):**
- **EPG** (program guide) — the #1 "feels like real TV" feature. Present for Live.
- **Fast zapping / near-instant playback** — perceived quality.
- **Clean, TV-like, well-organized categories** — IBO Player Pro praised as "cleanest,
  Netflix-like"; TiviMate criticized as "dense developer-tool aesthetic".
- **Favorites + Continue Watching + resume position.**
- **Search across all content.**
- **Personalized discovery** (~80% of Netflix watch time is from recommendations).
- Cloud sync of favorites/history (we already scope per-playlist).

**Hated (avoid):**
- Navigation complexity / hidden controls / confusing chrome.
- Dense, technical, cluttered screens.
- Slow / buffering; re-doing setup per device.
- Flat undifferentiated grids with no organization.

---

## 3. BLANK TV — the creative concept
**Concept: "The Cinematic Canvas."** BLANK = an uncluttered canvas where the *content* is the
hero and the interface recedes. Content-first, immersive, editorial. Generous negative space,
bold typography, lime accent on deep cinematic green.

**Signature identity rules:**
- **Content-first / low chrome:** big art, minimal UI; controls appear on demand.
- **One cinematic language everywhere:** the same immersive "stage" + curated "shelves"
  system across Home / Live / Movies / Series — a *unified* feel (vs siloed screens).
- **Editorial motion:** smooth cross-fades, a sliding lime indicator, gentle parallax.
- **Green cinematic palette:** deep-green `#001A0B` base, lime `#CBFF06` + teal `#00BC72`.
- **Working, honest navigation:** top bars are `.safeAreaInset` (NEVER inside the ScrollView —
  scroll-child buttons go dead in this codebase; hard-won lesson).

---

## 4. Per-screen blueprint (distinct from Strong 8K, usable, achievable)
Strong 8K content screens = `ContentTitleBar (huge title) + 4 fixed chips (All/Fav/New/Hist) +
grid/rails`. BLANK TV replaces that recognizable chrome with the **Stage + Shelves** system:

### 4.1 Global content-screen shell (Live / Movies / Series share it)
- **Fixed top bar** (`.safeAreaInset`, WORKS): compact section label • search field • one filter
  glyph. No oversized title, no 4-chip strip.
- **STAGE** (scroll top): a large immersive featured backdrop (the section's spotlight) with
  bold title + Play/Details. Full-bleed, cinematic.
- **SHELVES** (below): curated horizontal rails — *Continue*, *Favorites*, then **genre
  shelves** (Movies/Series) or *On Now / category* shelves (Live). Bold shelf headers + lime
  underline. Filters (Favorites/Newest/History) live as **shelves or a filter sheet**, not a
  top tab strip.

### 4.2 Home — "Tonight" feed
Unified personalized feed (not a hub of duplicated rails): immersive rotating spotlight →
Continue Watching → a *blended* "For You" shelf (mix of live/movies/series) → section shelves.

### 4.3 Live — EPG-forward
Left: channel list (compact rows w/ logo + now-playing). Right (iPad) / below (iPhone): a
**mini player + NOW/NEXT EPG** stage. This EPG-forward live view is a strong, loved, distinct
pattern (vs a plain channel grid).

### 4.4 Movies / Series — cinematic library
Stage (featured) + genre shelves. Bigger posters. Detail = cinematic backdrop (DONE) + cast +
(series) season/episode shelf.

### 4.5 Player — immersive, gesture-first
Chrome-less by default; tap reveals controls. Lime play-disc (DONE), square action chips
(DONE). Keep all existing engine behavior (speed, subtitle, audio, PiP, AirPlay, next-episode).

### 4.6 Settings — editorial list
Profile card (DONE) + lime section headers (DONE) + grouped glass cards.

---

## 5. Technical guardrails (do not repeat past bugs)
- **Top/nav bars must be `.safeAreaInset(edge:.top)`, never a ScrollView child** (scroll
  content captures taps → dead buttons; happened on the rejected category-library template).
- **No glass-on-glass**, no solid fill behind `glassEffect`, no `.clipShape` on a glass view.
- **No heavy shadows on cells inside large grids** (scroll perf on 100k items).
- Every change: `chk.py` brace-balance + an agent compile-review BEFORE commit (can't compile
  on Windows). Owner builds via Codemagic → TestFlight Internal → **tap Update** to get it.
- Keep the engine/data untouched (tab/folders/search/VM/services): change layout only.

---

## 6. Build roadmap (each = build + owner review before next)
1. **Global content shell** (Stage + Shelves + working safeAreaInset top bar) on **Movies** as
   the template → owner approves the direction.
2. Apply to **Series**, then **Live** (EPG-forward).
3. **Home** "Tonight" feed refinement.
4. **Player** chrome-less polish.
5. **App Store**: distinct screenshots + description + keywords (4.3-critical).

---

## 7. Differentiation table (BLANK TV vs Strong 8K)
| Aspect | Strong 8K (reference) | BLANK TV |
|---|---|---|
| Palette | Gold on black | Lime/teal on deep green |
| Icon/brand | Gold 8K | Green "BLANK TV" badge |
| Entry | Single login form | Multi-subscription card gate |
| Tab bar | Floating gold capsule | Floating iOS-26 glass, lime indicator |
| Home hero | Small rounded card | Full-bleed immersive spotlight |
| Content nav | Big title + 4 fixed chips + grid | Stage + Shelves, filter sheet, no chip strip |
| Player | Gold circle-symbol | Lime play-disc + square chips, chrome-less |
| Concept | Generic player | "Cinematic Canvas" content-first |

---

## 8. Deep-research addendum (2026-07-13) — concrete techniques
Sources: Fora Soft streaming-UX best practices; cinema-app UI collections; IPTV app reviews.

**Proven techniques (achievable with our existing engine/data — UI-only):**
- **Personalized carousels, not lists** (Netflix): content in horizontal shelves, limited
  visible chrome → less decision fatigue. → our Shelves.
- **Distinct "collection" sections** (Disney+ brand universes): present categories as *named,
  visually-branded collections* users jump into — not a flat chip strip. → BLANK TV "Collections".
- **Content-first onboarding** (HBO Max simplified an overwhelming first UI): discovery before
  settings; minimal launch chrome. → our multi-subscription gate + immersive home.
- **Progressive/instant thumbnails** (already: tuned Coil/S8KImage cache + prefetch).
- **Predictive/global search** across live+movies+series (already: SearchView scopes).
- **Bottom-tab, thumb-friendly nav** (Plex moved off hamburger): keep our floating glass bar.
- **Motion as polish:** smooth list→detail cross-fades, sliding lime indicator, gentle parallax
  on the stage backdrop.

**How top apps DIFFERENTIATE without cloning (the 4.3 lesson, concrete):**
- Vodeo stood out via **theater-inspired design + a proprietary angle (pay-per-view)**, NOT by
  copying subscription rivals. → BLANK TV differentiates via a **coherent cinematic-canvas
  theme + a signature look**, not by copying Strong 8K.

**OUT of scope (backend/ML — do NOT promise):** AI recommendation engine, multi-user profiles,
dynamic thumbnail A/B testing, adaptive-bitrate changes. We reorganize/curate the *existing*
Xtream/M3U data into shelves/collections; we do not invent new backend intelligence.

## 9. BLANK TV signature elements (the "unique identity", refined)
1. **"Collections" metaphor** — categories rendered as bold named collection cards/shelves
   (not a 4-chip tab strip). This is our distinct organizing idea.
2. **The Stage** — one immersive full-bleed featured backdrop per section (parallax), the
   recurring cinematic signature.
3. **Low-chrome player + on-demand controls**, lime play-disc, square chips (done).
4. **Lime "spotlight" accent language** — the lime underline/indicator as a recurring beam
   motif tying every screen together.
5. **Multi-subscription card gate** — a genuinely different entry (done).
6. **EPG-forward Live** — the loved "real-TV" feature, front-and-center.

## 10. Readiness checklist (engineer + design lead + reviewer)
- [x] Full codebase map (screens/VMs/services/engine/nav) documented.
- [x] Design system + green identity in hand.
- [x] 2026 research (loved/hated features, top-app patterns, concrete techniques) recorded here.
- [x] Creative concept + per-screen blueprint + signature elements defined.
- [x] Technical guardrails recorded (safeAreaInset top bars; no glass-on-glass; grid perf).
- [x] Verification method (chk.py + agent compile-review before every commit).
- [ ] Owner approval of concept + Movies template → then execute per §6 roadmap.
- Known limitation: I design blind (no local preview) → mitigated by compile-review + owner
  device builds + screenshots. Plan approved BEFORE building to minimize reject cycles.

## 11. ⭐ REFERENCE the owner chose: "Funflix" cinematic OTT (2026-07-13)
Owner shared 3 screenshots of the **Funflix OTT** kit (Netro Creative) as the target LOOK.
BLANK TV adopts this cinematic pattern **with the lime/green accent** (Funflix shows red/pink)
— which itself keeps us distinct from Funflix too. Concrete spec extracted from the shots:

**HOME (match this):**
1. **Minimal top bar over the hero:** a menu/filter glyph (leading) + a profile/logo glyph
   (trailing). Small, translucent, floats on the hero.
2. **Immersive HERO (~40% height):** featured backdrop, bold title (or title art), a metadata
   line `★ 8.3 · genre`, and **TWO CIRCULAR buttons: a `＋` (outline circle) + a `▶` play
   (accent-FILLED circle, larger)** — this circular-play button is Funflix's signature.
3. **Continue/recent RAIL:** small rounded thumbnail chips.
4. **"Top Trending" section:** bold header + a **2-column poster GRID** (large rounded posters).

**DETAIL (we're already close):** full-bleed backdrop → rounded **bottom info card**: title +
`HD` badge, genre, `★ rating · year · age`, plot + "more", **"Watch now" (accent pill) +
"Trailer" (outline pill)**.

**STYLE:** cinematic dark, ONE accent color (ours = lime `#CBFF06`), rounded cards, minimal
chrome, large imagery, circular hero buttons, bottom-sheet detail.

**Build order to match Funflix:** (1) Home hero → circular ＋/▶ buttons + metadata line;
(2) Home → Continue rail + "Top Trending" 2-col grid; (3) Detail → confirm Watch now/Trailer
pills; (4) apply the cinematic card/hero spirit to Movies/Series/Live.

## 12. Research addendum #2 (2026-07-14) — remaining screens + polish
### Live TV / EPG (the loved "real-TV" feature — users with EPG watch ~40% more live)
Mobile-friendly (not a dense TV grid): a channel LIST (logo + name + **NOW/NEXT** with a
progress bar) → tap → a top **mini player** stage + **now/next** panel. Browse by category,
search. Xtream `get_short_epg` feeds NOW/NEXT (m3u has none → hide gracefully). We already
have InlineLivePlayer + EPGNowNext + a 3-pane iPad split — elevate that: NOW badge, red ● live,
current-program progress bar, next-at time. Keep it clean (IBO-clean, not TiviMate-dense).

### Micro-interactions & motion (what makes it feel PREMIUM in 2026)
- **Animate the favorite heart** (Spotify-style pop) on toggle.
- **Haptics:** light `UIImpactFeedbackGenerator` on play, favorite, tab switch, hero swipe.
  (VLCPlayer already uses haptics — extend the pattern.)
- **Easing 200–500ms**, natural spring/cubic-bezier; no robotic linear.
- **Parallax on the hero backdrop** (foreground text/buttons move slightly vs the image).
- **Purposeful only** — every animation must communicate (feedback/continuity), not decorate.

### Detail screen (refine what we have)
Cinematic backdrop (done) + bottom info card + Watch now/Trailer pills + cast row +
(series) season selector + episode list with **watch-progress** bars + resume. Keep engine.

### Applying Funflix spirit to Movies/Series/Live (after Home is approved)
Each section = a **Stage** (immersive featured, circular ＋/▶ buttons, ★ rating) + curated
shelves/collections; poster cards rounded with a rating badge; working `.safeAreaInset` top bar
(search + filter). Consistent lime accent. This unifies the app under one cinematic language.

### Performance lessons (recorded)
- Carousel/scroll jank = **uncached image decode** (fix: `S8KImageCache.prefetch`) + **needless
  re-computation on render** (fix: sort/derive ONCE in the VM, store; never sort a big catalog
  inside a SwiftUI body). Applied to the hero + Top-rated rails.
- Top/nav bars = `.safeAreaInset(edge:.top)`, never a ScrollView child.

### ⭐ DEVICE SYNC — every design must work on iPhone + iPad + Mac (owner rule)
The app is universal (iPhone + iPad + Mac via Designed-for-iPad). Rules:
- **Device-SHARED views** (Home, Tab bar, Details, Settings, Player, the gate) automatically
  adapt — use `@Environment(\.horizontalSizeClass)` (`.regular` = iPad/Mac) to cap width /
  add columns, NOT device checks. Cap content on iPad (Home ≤900, tab pill ≤480) so it isn't a
  blown-up phone. These are already synced.
- **Content screens have TWO layouts:** iPhone `browser` + iPad `padBrowser` (3-pane split w/
  `CategorySidebar`). **When redesigning Movies/Series/Live, update BOTH** so iPhone and iPad
  stay in sync — never fix the phone and leave the iPad on the old look (owner rule 2026-07-14).
- Test the immersive hero / grids at `.regular` size class (bigger poster columns already:
  iPad 168 vs iPhone 116). Verify the raised center tab + glass bar look right on iPad too.
