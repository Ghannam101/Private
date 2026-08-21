// ============================================================
// BLANK TV — TextFold.swift
// ONE normalisation rule for every text comparison in the app.
//
// WHY THIS FILE EXISTS. `CatalogText.fold` claimed to be diacritic-insensitive and
// was not, for the app's primary language. Foundation's `.diacriticInsensitive`
// covers Latin script and leaves Arabic untouched — a test asserted the opposite
// and failed with the strings printed side by side:
//
//     fold("أفلام")     → "أفلام"        (unchanged)
//     fold("مُسَلْسَل")  → "مُسَلْسَل"     (harakat intact)
//
// SQLite was checked too, because the FTS index carries
// `tokenize = 'unicode61 remove_diacritics 2'` and the obvious hope was that it
// covered what Foundation missed. Run against SQLite 3.50.4 it does not:
// searching `افلام` over an indexed `أفلام عربية` returns nothing. So BOTH search
// paths were blind to hamza and harakat variation, consistently — which is the
// one piece of luck here, because it means a single rule fixes both without the
// two disagreeing during the transition.
//
// THE RULES ARE NOT INVENTED. They are Lucene's `ArabicNormalizer`, the reference
// implementation the search industry has used for two decades, taken from its
// source rather than from a description of it:
//
//     آ أ إ (U+0622, U+0623, U+0625)  →  ا (U+0627)
//     ى     (U+0649)                  →  ي (U+064A)
//     ة     (U+0629)                  →  ه (U+0647)
//     removed: ـ (U+0640 tatweel) and the harakat U+064B…U+0652
//
// TWO ADDITIONS BEYOND LUCENE, both deliberate:
//   · ٱ (U+0671, alef wasla) → ا. Same class as the three alef forms above; Lucene
//     omits it, and it appears in exactly the Quranic and religious channel names
//     this catalogue is full of.
//   · U+0670 (superscript alef) removed. It is a combining mark that sits with the
//     harakat and is dropped for the same reason they are.
//
// WHAT IS DELIBERATELY NOT DONE. ؤ and ئ keep their seats, matching Lucene. They
// carry meaning more often than they are typed inconsistently, and collapsing them
// costs precision for very little recall.
// ============================================================

import Foundation

enum S8KFold {

    private static let alef: Unicode.Scalar = "\u{0627}"
    private static let yeh:  Unicode.Scalar = "\u{064A}"
    private static let heh:  Unicode.Scalar = "\u{0647}"

    /// The comparison key for a title. Case-, width-, and diacritic-insensitive
    /// across Latin AND Arabic.
    ///
    /// Call it ONCE per string and compare the results — never inside a comparator.
    /// Step one reaches into ICU, which is the most expensive thing a browse page
    /// can do per row, and the catalogue can hold fifty thousand rows.
    static func key(_ s: String) -> String {
        // Step 1 — Latin, unchanged from what the app has always done. This is a
        // no-op for Arabic text, which is precisely the defect being fixed below.
        let latin = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                              locale: nil)

        // Step 2 — Arabic. Scanned before it is rewritten so a title with no Arabic
        // in it (the common case in a mixed catalogue) pays one pass and allocates
        // nothing.
        var needsWork = false
        for u in latin.unicodeScalars where isArabicRewrite(u.value) { needsWork = true; break }
        guard needsWork else { return latin }

        var out = String.UnicodeScalarView()
        out.reserveCapacity(latin.unicodeScalars.count)
        for u in latin.unicodeScalars {
            switch u.value {
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append(alef)
            case 0x0649:                         out.append(yeh)
            case 0x0629:                         out.append(heh)
            case 0x0640, 0x064B...0x0652, 0x0670: continue   // tatweel + harakat
            default:                             out.append(u)
            }
        }
        return String(out)
    }

    private static func isArabicRewrite(_ v: UInt32) -> Bool {
        switch v {
        case 0x0622, 0x0623, 0x0625, 0x0671, 0x0649, 0x0629,
             0x0640, 0x064B...0x0652, 0x0670: return true
        default: return false
        }
    }

    /// True when `key` appears in `text` at the START of a word.
    ///
    /// A plain `contains` is what let three channels be filed under the wrong
    /// continent: "Romania" contains "oman", "Sukkar" contains "uk". Requiring a
    /// word boundary in FRONT of the match — and only in front — keeps the
    /// deliberate stems working ("algeri" must still match "Algeria", "emirat"
    /// must still match "Emirates") while refusing a match buried inside a word.
    ///
    /// Both operands are expected to be `key(_:)`-folded already; this does not
    /// fold, so it can be called in a loop without paying ICU per candidate.
    static func containsWord(_ text: String, _ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        var from = text.startIndex
        while let r = text.range(of: key, range: from..<text.endIndex) {
            if r.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: r.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            guard r.lowerBound < text.endIndex else { break }
            from = text.index(after: r.lowerBound)
        }
        return false
    }
}
