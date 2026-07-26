# Blank Prime — Device Compatibility Matrix
_The permanent reference for "does it fit on every device?" Researched 2026-07-25 against Apple HIG,
Apple developer docs/forums, and device-metrics references. Deployment target: **iOS 17**._

**How to use this file:** it is for **designing the test matrix and budgeting worst cases**.
Runtime code must NEVER hard-code these numbers — read the safe area via `.safeAreaInset` /
`\.safeAreaInsets`, and adapt via size classes. See §5.

---

## 1. iPhone — every model that can run iOS 17+

iOS 17 requires iPhone XS / XR / SE-2 or later. iOS 26 drops XR/XS/XS Max (floor = iPhone 11 / SE-2).
**Consequence: 320pt-wide iPhones (SE 1st gen) no longer exist in our matrix.**

| Points (portrait W×H) | Scale | Models | Top cutout |
|---|---|---|---|
| **375 × 667** | @2x | iPhone SE 2, SE 3 | Home button |
| 375 × 812 | @3x | 12 mini, 13 mini (+ XS, 11 Pro) | Notch |
| 390 × 844 | @3x | 12, 12 Pro, 13, 13 Pro, 14, 16e | Notch |
| 393 × 852 | @3x | 14 Pro, 15, 15 Pro, 16 | Dynamic Island |
| 402 × 874 | @3x | 16 Pro, 17, 17 Pro | Dynamic Island |
| 414 × 896 | @2x/@3x | 11, 11 Pro Max (+ XR, XS Max) | Notch |
| 420 × 912 | @3x | iPhone Air | Dynamic Island |
| 428 × 926 | @3x | 12 Pro Max, 13 Pro Max, 14 Plus | Notch |
| 430 × 932 | @3x | 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus | Dynamic Island |
| **440 × 956** | @3x | 16 Pro Max, 17 Pro Max | Dynamic Island |

**Widths to survive: 375, 390, 393, 402, 414, 420, 428, 430, 440.**

## 2. iPad + multitasking

| Points (portrait W×H) | Models |
|---|---|
| 744 × 1133 | iPad mini 6/7 |
| 810 × 1080 | iPad 7–10 |
| 820 × 1180 | iPad Air 11", iPad 11" |
| 834 × 1194 / 834 × 1210 | iPad Pro 11" |
| 1024 × 1366 / **1032 × 1376** | iPad Pro 12.9" / 13" |

| Multitasking | Portrait | Landscape |
|---|---|---|
| Slide Over / narrow Split View | **320pt (compact)** | 375pt (compact) |
| 50/50 Split View (mini) | 566.5pt (compact) | 566.5pt |

- **320pt is the narrowest width the app can be given.** Widths are **not** guaranteed integral (566.5).
- iPadOS 26 deprecates `UIRequiresFullScreen`; windows are freely resizable and
  `sizeRestrictions.minimumSize` is only a *preference*. **Design for continuous width ≥ ~320, not a
  lookup table.**
- Our `Info.plist` has no `UIRequiresFullScreen` → Split View / Slide Over / Stage Manager are live.

## 3. Safe-area insets (points)

| Device class | Portrait T / B | Landscape T / B / L / R |
|---|---|---|
| Home-button iPhone (SE 2/3) | 20 / 0 | 0 / 0 / 0 / 0 |
| Notch iPhone | 47 / 34 | 0 / 21 / 47 / 47 |
| Dynamic Island (393×852, 430×932) | 59 / 34 | 0 / 21 / 59 / 59 |
| Dynamic Island (402×874, 440×956) | 62 / 34 | 20 / 20 / 62 / 62 *(iOS 26)* |
| iPhone Air (420×912) | 68 / 34 | 20 / 29 / 68 / 68 *(iOS 26)* |
| iPad, home button | 20 / 0 | 20 / 0 / 0 / 0 |
| iPad, home indicator | 24 / 20 | 24 / 20 / 0 / 0 |

⚠️ **iOS 26 change:** landscape `safeAreaInsets.top` went 0 → 20 on iPhone even with no status bar.
Any hard-coded landscape offset tuned before iOS 26 is now 20pt off.

## 4. The hard extremes — if these pass, everything passes

| Extreme | Value | Where |
|---|---|---|
| **Narrowest width** | **320pt** | iPad Slide Over portrait |
| Narrowest iPhone | 375pt | SE 2/3, 12/13 mini |
| **Shortest usable height** | **~334pt** | 13 mini landscape (375 − 20 − 21, iOS 26) |
| Tallest usable height | 860pt | 17 Pro Max (956 − 62 − 34) |
| Largest | 1032 × 1376 | iPad Pro 13" |

**Test these four first: (a) iPhone SE portrait with the keyboard up, (b) a phone in landscape,
(c) iPad Slide Over 320pt, (d) iPad Pro 13" landscape.**

## 5. The rules this codebase follows (iOS 17+, no GeometryReader)

| Need | Use | Min iOS | Note |
|---|---|---|---|
| Adapt to device/window class | `\.horizontalSizeClass` / `\.verticalSizeClass` | 13 | Optional; only compact/regular |
| Cap a block's width | `.frame(maxWidth: N)` + outer `.padding(.horizontal:)` | — | **NEVER** `.frame(width: measured - N)` — it can go negative |
| Top / bottom bars | `.safeAreaInset(edge:)` | 15 | Reserves real safe-area space. Never a ScrollView child (taps die) |
| Content that may not fit | `ScrollView` + `.defaultScrollAnchor(.bottom)` + `.scrollBounceBehavior(.basedOnSize)` | 17 / 16.4 | Bottom-pinned when short, scrollable when tall, no rubber-band |
| Pick a layout by fit | `ViewThatFits` | 16 | Measures *ideal* size — a greedy `maxWidth:.infinity` child always "fits" |
| Proportional sizing | `.containerRelativeFrame` | 17 | Nearest container wins; avoid perpendicular to a ScrollView axis |
| Grids | `GridItem(.adaptive(minimum:))` | 14 | Never a fixed column count |
| Dynamic Type | `@ScaledMetric`, `.dynamicTypeSize(...)` | 14/15 | `@ScaledMetric` scales **unbounded** — always clamp |
| The app's own size | **`s8kWindowSize()`** (DesignSystem.swift) | — | **NEVER `UIScreen.main.bounds`** — that is the whole display, wrong in Split View / Stage Manager / Mac |

### Banned patterns (each one has already caused a real bug here)
1. **`GeometryReader` as a view root** — it has no ideal size, places children top-leading, and inside a
   `fullScreenCover` / navigation container it can report 0. It produced the gateway
   "only the posters show" bug via `min(geo.width - 44, 430)` = **−44**. Also: a GeometryReader that
   ignores the safe area reads its insets as **0**.
2. **`ForEach(0..<someVariable)`** — traps at runtime when the count changes. Use
   `ForEach(Array(0..<n), id: \.self)`.
3. **`UIScreen.main.bounds`** for layout — see above.
4. **A fixed `.frame(height:)` on a row containing text** — clips at large Dynamic Type. Use `minHeight`.
5. **A full-screen gate or a keyboard-bearing sheet without a `ScrollView`** — the action button ends up
   unreachable and the user is trapped (this bricked the maintenance/update gates and the code sheet).
6. **`.presentationDetents([.medium])` alone** on a sheet with a text field — always offer `.large` too.

## 6b. iPad multitasking — measured pane widths (researched 2026-07-26)

The Split View divider is **10pt**, confirmed by two independent verbatim data points
(8.3" mini landscape: narrow 375 + wide 748 = 1123 = 1133 − 10; portrait: 320 + 414 = 734 =
744 − 10). So `⅔ pane = screenW − 10 − narrow` and `½ pane = (screenW − 10) / 2`.

| Device (landscape W) | Slide Over / ⅓ | ½ | ⅔ | size class at ½ |
|---|---|---|---|---|
| 12.9"/13" Pro (1366) | **375** | 678 | 981 | **regular** |
| 11" Pro (1194) | **375** | 592 | 809 | **regular** |
| 10.5" Pro (1112) | **320** | 551 | 782 | compact |
| 10.2" (1080) | **320** | 535 | 750 | compact |
| 9.7" (1024) | **320** | 507 | 694 | compact |
| 8.3" mini (1133) | **375** | **561.5** ⚠ | 748 | compact |

**Portrait: the narrow pane is 320pt on EVERY iPad.**

Three facts that matter more than the table:
1. **Widths are not guaranteed integral** — the 8.3" mini's 50/50 landscape pane is 561.5pt.
   Never compare a width with `==`, never assume a whole number.
2. **320pt was never a documented floor** — it is empirically universal in the classic model,
   but Apple publishes no minimum. Under **iPadOS 26 free-form windowing** Split View/Slide
   Over are gone as modes, windows resize continuously, and `sizeRestrictions.minimumSize` is
   explicitly *"a preference… not guaranteed"* (Apple DTS). Design for a **continuous** width.
3. **The compact→regular flip has no published threshold.** Measured: 561.5pt is compact,
   592pt is regular — so it lies in (561.5, 592]. The commonly-quoted "640" is wrong. Never
   hard-code it; read `horizontalSizeClass`.

## 6c. What the audits actually found (2026-07-26)

A quantitative pass over all four content pages, plus a layout-system design review:

- **Three near-identical hero formulas** that disagreed (Home / Movies / Series), and
  "hero height" meant two different things because Movies/Series added `+ topInset`.
  **Two of the three produced a hero TALLER THAN THE VIEWPORT** — iPhone SE portrait (520pt
  in a 667pt screen) and every phone in landscape (300pt in a 274pt usable area).
- **Eleven different content-width caps**, **five grid rules**, **three bottom spacers**
  (110/100/130 against a real footprint of 68+safeBottom), and **thirteen hard-coded top
  paddings** stacked on top of the real safe area.
- **Four controls below Apple's 44pt tap minimum** (38–42pt).
- The poster grid was **2-up from 375pt to 414pt and 3-up from 420pt** — the same page was a
  different product on an iPhone 15 and a 15 Plus.

## 7. THE LAYOUT SYSTEM (mandatory)

`S8KMetrics` in `DesignSystem.swift` is the single source of truth. The rules:

1. **Every layout number** comes from `S8KMetrics`, `S8KSpace` or `S8KRadius`. A bare numeric
   literal in `.frame(` / `.padding(` / `.adaptive(minimum:` is a bug, not a style choice.
2. **Adapt via `metrics.cls`** (`S8KDeviceClass`) — never a raw width, never
   `UIDevice.current.userInterfaceIdiom`.
3. `S8KMetricsRoot` is installed **once**, around the TabView in `BlankTVApp`. Never add a second.
4. It derives everything from the **WINDOW** (`s8kWindowSize()`, keyboard-immune) and the size
   classes. It NEVER measures a width from a nested proxy — that is what makes the
   "`min(geo.width − 44, 430)` went negative and the screen collapsed" bug unrepresentable.
5. Safe-area insets come from the window scene (`s8kWindowInsets()`) or a **page-root**
   GeometryReader, and are used for insets **only** — never to derive a width.
6. Any interactive element is **≥ 44pt**, expressed as `minHeight:`, never `height:`.
7. The hero has **one** implementation: `metrics.heroHeight`. It is **full-bleed** — never add
   `+ topInset`. It carries a hard invariant:
   **`hero + heroPeek(88) + bottomClearance ≤ window height`**, so the next row always peeks.
   Its floor is the hero card's own incompressible copy stack (248pt).
8. A page whose content runs to the physical bottom reserves `metrics.bottomClearance`
   (= 68pt bar footprint + 12 + the real home-indicator inset). Nothing else.

## 6. Known-open items (need owner approval — they change approved visuals)
- 13 sites use a hard-coded `.padding(.top, 50…70)` on top of the real safe area (`AuthViews:306/511/661`,
  `ActivationView:257`, `ContentViews:200/231/314/1331/1476/1552/1925`, `HomeView:1466`,
  `SettingsView:612/1099`). On a Dynamic Island phone that is ~120pt of chrome before the first word;
  worst on iPad landscape and Mac. Fix = delete the number, hang the bar off `.safeAreaInset(edge:.top)`.
- `AppTabBar` is a ZStack overlay, not a `.safeAreaInset(edge:.bottom)`, so every page hand-pads 110pt.
  Converting it removes ~15 magic spacers — but it touches the launch-critical path.
- `S8KFont` is entirely fixed `.system(size:)` with no `relativeTo:` → the app effectively ignores
  Dynamic Type. Full adoption is a typography pass across every screen.
