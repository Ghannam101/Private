# Identity archive

Every identity this app has worn, kept whole so any of them can be restored or sold
without going through git archaeology.

**These files are deliberately OUTSIDE the Xcode target.** An identity that is not the
one being shipped must not sit inside the binary — that is the same reason the
`strongGold` palette was deleted from `DesignSystem.swift`: it reproduced another app's
exact base and accent, was never referenced, and still shipped. Archive here, ship one.

---

## buyer1 — Blank Prime · بلانك ستور  ← **SHIPPING NOW**

Wordmark-in-a-frame mark, dark on a lime field. Arabic lockup «بلانك ستور».

| slot | value |
|---|---|
| `name` | `"Blank Prime"` |
| `shortName` | `"Blank"` |
| palette | `BrandTheme.blankGreen` (below) |
| assets | `buyer1-blank-prime/assets/` |
| last shipped at | commit `518fe8b`, superseded by `70d1b06`, **restored 2026-08-21** |

**Contrast, measured — not inherited from the note below.** WCAG 2.1 relative
luminance, computed against this exact palette:

| pair | ratio | verdict |
|---|---|---|
| `accentInk` on `#CBFF06` | **15.48 : 1** | AA + AAA |
| `#CBFF06` as text on `base` | 15.48 : 1 | AA |
| on `surface` / `card` / `elevated` | 14.38 / 13.08 / 11.45 | AA |
| `accentMid #00BC72` on base | 7.32 : 1 | AA |
| `accentLow #009159` on base | 4.51 : 1 | AA (just) |
| `accentDeep #00734A` on base | 3.08 : 1 | large text / fill only |

`accentInk` resolves to `s8kBlack` here, and by a wide margin — the lime is the
brightest accent any identity in this archive carries, so the button label is the
darkest and most legible of the three. This palette does NOT carry the Arena defect.

```swift
BrandTheme(
    base:     Color(red: 0.000, green: 0.102, blue: 0.043),   // #001A0B
    surface:  Color(red: 0.016, green: 0.133, blue: 0.059),   // #04220F
    card:     Color(red: 0.027, green: 0.169, blue: 0.078),   // #072B14
    elevated: Color(red: 0.043, green: 0.212, blue: 0.110),   // #0B361C
    accentHigh: Color(red: 0.796, green: 1.000, blue: 0.024), // #CBFF06 lime
    accentMid:  Color(red: 0.000, green: 0.737, blue: 0.447), // #00BC72 teal
    accentLow:  Color(red: 0.000, green: 0.569, blue: 0.349), // #009159
    accentDeep: Color(red: 0.000, green: 0.451, blue: 0.290)  // #00734A
)
```

---

## buyer2 — Arena Live · أرينا

Arena/crown mark, black on an orange field. Sampled from the buyer's own artwork —
`#FF6029` is an exact pixel value from their supplied lockup, not an approximation.

| slot | value |
|---|---|
| `name` | `"Arena Live"` |
| `shortName` | `"Arena"` |
| palette | the `arenaOrange` theme (below) |
| assets | `buyer2-arena-live/assets/` |
| shipped at | commit `70d1b06`, builds 108–110 (TestFlight) |

```swift
BrandTheme(
    base:       Color(red: 0.047, green: 0.031, blue: 0.024),  // #0C0806
    accentHigh: Color(red: 1.000, green: 0.376, blue: 0.161),  // #FF6029  sampled
    accentLow:  Color(red: 0.702, green: 0.220, blue: 0.063)   // #B33810
)
```

> **Known defect, carried by this identity — disclose it if this identity is sold.**
>
> **ROOT CAUSE FIXED 2026-08-21.** `S8KBrand.accentInk` no longer branches on a raw
> luma threshold; it measures real WCAG contrast for both candidate inks and takes the
> winner. Arena's `#FF6029` now resolves to a dark ink instead of white. The palette
> was never the bug — the threshold was — so restoring Arena today is safe. The
> paragraph below is kept as the record of what went wrong.
>
> `#FF6029` has a raw Rec.709 luma of `0.493`, which falls inside the dead band of
> `S8KBrand.accentInk` (`DesignSystem.swift:1855`, branches at `> 0.55`). The rule
> therefore picks **white** ink, and white on `#FF6029` measures **3.02 : 1** — below
> the 4.5:1 WCAG AA floor, on every primary button in the app. The fix belongs in
> `accentInk` (compare both candidate inks' real contrast and take the winner), not in
> the palette, so it travels with whichever identity ships.

---

## Restoring an identity

1. Copy `<identity>/assets/Logo.imageset` and `AppIcon.appiconset` over
   `BlankTV/Assets.xcassets/`. Filenames and `Contents.json` already match, so the
   `project.pbxproj` needs no edit.
2. Set `AccentColor.colorset` to the identity's `accentHigh`.
3. Set `S8KBrand.name` / `shortName` (`DesignSystem.swift:1826`).
4. Restore the `BrandTheme` above and repoint `BrandTheme.active`.
5. Set `INFOPLIST_KEY_CFBundleDisplayName` (two configurations).
6. Run `python brandlint.py` — it catches identity strings that escaped steps 3–5.

~~`S8KWordmark` contains a hard-coded `Text("Prime")`~~ — **FIXED.** The second half of
the lockup is `S8KBrand.markSuffix` now, so step 3 covers it and brandlint can see it.

`brandlint.py` no longer hard-codes a name either. It reads `S8KBrand.name` out of
`DesignSystem.swift` at run time and also checks each word of it separately, because
the wordmark ships in two halves. It used to hunt the literal "Blank Prime" — so
throughout the Trex TV period it reported CLEAN over a codebase it was not inspecting,
which is the exact decay it exists to catch, occurring inside the tool.

---

## trex-tv — Trex TV

Archived 2026-08-21 when buyer1 was restored. Skull mark; violet-dark ramp with an
ember accent, every value measured out of the owner's own logo file.

| slot | value |
|---|---|
| `name` | `"Trex TV"` |
| `shortName` / `markSuffix` | `"Trex"` / `"TV"` |
| palette | `BrandTheme.trexEmber` (still in `DesignSystem.swift`) |
| assets | `trex-tv/assets/` |
| shipped at | up to build 134 (TestFlight) |

> **Defect in the archived assets — fix before reshipping.** `Logo.imageset/logo.png`
> (the 1× slot) is **193 bytes** at 120×120: effectively blank. The 2× and 3× slots are
> real. Nothing on a modern device requests 1×, which is why it was never noticed.
>
> Its accent also measures lower than the one replacing it: `#F4702A` reads 6.70 : 1 on
> its base where Blank Prime's lime reads 15.48 : 1.

---

## Open question for the buyer — the mark and the name disagree

The artwork reads **«بلانك ستور»** (Blank *Store*). The shipped name is **Blank Prime**,
and the wordmark in the top bar renders «Blank Prime». So the icon says one thing in
Arabic and the app says another in English.

This is not a bug to fix silently — it is the buyer's call, and there are three answers:

1. **Keep both.** Arabic mark «بلانك ستور», English name "Blank Prime". Defensible if
   the Arabic is read as the store/brand and the English as the product tier.
2. **Align to the artwork.** `name = "Blank Store"`, `shortName`/`markSuffix` =
   `"Blank"` / `"Store"`. One edit, no new artwork.
3. **Align the artwork.** Redraw the mark to «بلانك برايم». New artwork, and the mark
   is the strongest thing in this identity — changing it costs the most.

Nothing is assumed here: option 1 is what is shipping, because it is what the archive
recorded.
