# Identity archive

Every identity this app has worn, kept whole so any of them can be restored or sold
without going through git archaeology.

**These files are deliberately OUTSIDE the Xcode target.** An identity that is not the
one being shipped must not sit inside the binary — that is the same reason the
`strongGold` palette was deleted from `DesignSystem.swift`: it reproduced another app's
exact base and accent, was never referenced, and still shipped. Archive here, ship one.

---

## buyer1 — Blank Prime · بلانك ستور

Wordmark-in-a-frame mark, dark on a lime field. Arabic lockup «بلانك ستور».

| slot | value |
|---|---|
| `name` | `"Blank Prime"` |
| `shortName` | `"Blank"` |
| palette | `BrandTheme.blankGreen` (below) |
| assets | `buyer1-blank-prime/assets/` |
| last shipped at | commit `518fe8b` (superseded by `70d1b06`) |

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

`S8KWordmark` (`DesignSystem.swift:1897-1932`) contains a hard-coded `Text("Prime")`
at `:1913` that `brandlint.py` does not see. Any rename that only edits `shortName`
ships «<NewName> Prime». Check it by hand until the wordmark becomes vector artwork.
