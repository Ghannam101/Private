// ============================================================
// BLANK TV — TextFoldTests.swift
// The normalisation rule every search in the app now shares.
//
// Each Arabic case below is one of Lucene's ArabicNormalizer rules, asserted
// separately so a failure names the rule that broke rather than "Arabic".
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("S8KFold.key — Latin")
struct FoldLatinTests {

    @Test("case is ignored")
    func caseFolded() {
        #expect(S8KFold.key("NETFLIX") == S8KFold.key("netflix"))
    }

    @Test("Latin accents are ignored")
    func accentsFolded() {
        #expect(S8KFold.key("Café") == S8KFold.key("cafe"))
        #expect(S8KFold.key("Amélie") == S8KFold.key("amelie"))
        #expect(S8KFold.key("Ñoño") == S8KFold.key("nono"))
    }

    @Test("full-width forms are ignored")
    func widthFolded() {
        #expect(S8KFold.key("ＮＥＴＦＬＩＸ") == S8KFold.key("netflix"))
    }

    @Test("text with nothing to change is returned unaltered")
    func passthrough() {
        #expect(S8KFold.key("breaking bad") == "breaking bad")
        #expect(S8KFold.key("") == "")
    }
}

@Suite("S8KFold.key — Arabic (Lucene ArabicNormalizer rules)")
struct FoldArabicTests {

    @Test("the three alef forms collapse to bare alef")
    func alefForms() {
        #expect(S8KFold.key("أفلام") == "افلام")   // U+0623 hamza above
        #expect(S8KFold.key("إسلام") == "اسلام")   // U+0625 hamza below
        #expect(S8KFold.key("آسيا")  == "اسيا")    // U+0622 madda
    }

    @Test("alef wasla collapses to bare alef")
    func alefWasla() {
        // Beyond Lucene, and deliberately: this form is all over Quranic and
        // religious channel names, which this catalogue is full of.
        #expect(S8KFold.key("\u{0671}سلام") == "اسلام")
    }

    @Test("dotless yeh becomes yeh")
    func dotlessYeh() {
        #expect(S8KFold.key("مصطفى") == "مصطفي")
    }

    @Test("teh marbuta becomes heh")
    func tehMarbuta() {
        #expect(S8KFold.key("عربية") == S8KFold.key("عربيه"))
    }

    @Test("harakat are removed")
    func harakat() {
        #expect(S8KFold.key("مُسَلْسَل") == "مسلسل")
        #expect(S8KFold.key("قُرْآن") == S8KFold.key("قران"))
    }

    @Test("tatweel is removed")
    func tatweel() {
        #expect(S8KFold.key("أفـــلام") == "افلام")
    }

    @Test("hamza on waw and yeh keep their seats, matching Lucene")
    func seatedHamzaPreserved() {
        // Asserted so that if someone widens the rule later, they do it knowingly.
        #expect(S8KFold.key("مؤمن") == "مؤمن")
        #expect(S8KFold.key("رئيس") == "رئيس")
    }

    @Test("folding is idempotent")
    func idempotent() {
        for s in ["أفلام", "مُسَلْسَل", "عربية", "Café", "NETFLIX", "", "مصطفى"] {
            #expect(S8KFold.key(S8KFold.key(s)) == S8KFold.key(s))
        }
    }

    @Test("a mixed Latin and Arabic title folds on both sides at once")
    func mixedScript() {
        #expect(S8KFold.key("MBC أفلام HD") == "mbc افلام hd")
    }
}

@Suite("S8KFold.containsWord")
struct ContainsWordTests {

    @Test("a key at the start of the text matches")
    func atStart() {
        #expect(S8KFold.containsWord("oman tv", "oman"))
    }

    @Test("a key after a space matches")
    func afterSpace() {
        #expect(S8KFold.containsWord("nature uk", "uk"))
    }

    @Test("a key after punctuation matches")
    func afterPunctuation() {
        #expect(S8KFold.containsWord("tv-uk hd", "uk"))
        #expect(S8KFold.containsWord("(bbc) one", "bbc"))
    }

    @Test("a key buried inside a word does NOT match")
    func insideWordRejected() {
        // The three real misfilings this function exists to stop.
        #expect(S8KFold.containsWord("romania tv", "oman") == false)
        #expect(S8KFold.containsWord("sukkar tv", "uk") == false)
        #expect(S8KFold.containsWord("duke tv", "uk") == false)
    }

    @Test("a stem still matches the start of a longer word")
    func stemsStillWork() {
        // Half the key lists are deliberate stems; word-INITIAL matching must not
        // turn into whole-word matching or they all stop working.
        #expect(S8KFold.containsWord("algeria sport", "algeri"))
        #expect(S8KFold.containsWord("emirates tv", "emirat"))
        #expect(S8KFold.containsWord("rai italia", "ital"))
        #expect(S8KFold.containsWord("portugal 1", "portug"))
    }

    @Test("a multi-word key matches across the space")
    func multiWordKey() {
        #expect(S8KFold.containsWord("united states network", "united states"))
        #expect(S8KFold.containsWord("abu dhabi tv", "abu dhabi"))
    }

    @Test("a later occurrence is found when the first is buried")
    func scansPastABuriedHit() {
        // "uk" appears inside "sukkar" first and at a word start second. Stopping at
        // the first occurrence would wrongly report no match.
        #expect(S8KFold.containsWord("sukkar uk", "uk"))
    }

    @Test("an empty key never matches")
    func emptyKey() {
        #expect(S8KFold.containsWord("anything", "") == false)
    }

    @Test("a key longer than the text never matches")
    func keyLongerThanText() {
        #expect(S8KFold.containsWord("uk", "united states") == false)
    }
}
