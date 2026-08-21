// ============================================================
// BLANK TV — SearchAndHostTests.swift
// Three small pure helpers that carry a lot of weight:
//
//   · `CatalogText.fold` — the ONE comparison rule every catalogue search obeys.
//     If it stops folding, Arabic search silently returns fewer results and nobody
//     gets an error.
//   · `AuthService.normalizeXtreamHost` — the first thing a new user's typing meets.
//     Every wrong answer here reads to the user as "my line does not work".
//   · `ActivationService.versionLessThan` — a numeric compare that a string compare
//     would get wrong in the one case that matters (1.10 vs 1.9).
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("CatalogText.fold")
struct CatalogTextFoldTests {

    @Test("folding is idempotent")
    func idempotent() {
        for s in ["Netflix", "Café", "مسلسل", "ÀÉÎÕÜ", ""] {
            #expect(CatalogText.fold(CatalogText.fold(s)) == CatalogText.fold(s))
        }
    }

    @Test("case is ignored")
    func caseInsensitive() {
        #expect(CatalogText.fold("NETFLIX") == CatalogText.fold("netflix"))
        #expect(CatalogText.fold("NetFlix") == CatalogText.fold("nETFLIX"))
    }

    @Test("Latin accents are ignored")
    func latinDiacritics() {
        #expect(CatalogText.fold("Café") == CatalogText.fold("Cafe"))
        #expect(CatalogText.fold("Amélie") == CatalogText.fold("amelie"))
    }

    @Test("Arabic diacritics and hamza forms are ignored")
    func arabicDiacritics() {
        // This is the behaviour Arabic search DEPENDS on: a provider writes "أفلام"
        // and the user types "افلام", or a title carries harakat the user will never
        // type. It is asserted separately from the Latin case so that if Foundation's
        // folding ever changes, the failure names the language it broke.
        #expect(CatalogText.fold("أفلام") == CatalogText.fold("افلام"))
        #expect(CatalogText.fold("إسلام") == CatalogText.fold("اسلام"))
        #expect(CatalogText.fold("مُسَلْسَل") == CatalogText.fold("مسلسل"))
    }

    @Test("an empty string folds to an empty string")
    func empty() {
        #expect(CatalogText.fold("").isEmpty)
    }
}

@Suite("CatalogText.narrow")
struct CatalogTextNarrowTests {

    private let items = ["Café Society", "Breaking Bad", "أفلام عربية", "NETFLIX Originals"]

    @Test("an empty query does not filter")
    func emptyQueryKeepsEverything() {
        #expect(CatalogText.narrow(items, matching: "", by: { $0 }).count == items.count)
    }

    @Test("a query of only whitespace still filters, because it folds to whitespace")
    func whitespaceQuery() {
        // Documented, not accidental: " " folds to " ", which is a real substring of
        // the titles that contain a space — so it matches those and only those.
        let hit = CatalogText.narrow(items, matching: " ", by: { $0 })
        #expect(hit.count == items.count)
    }

    @Test("matching ignores case and accents")
    func foldedMatching() {
        #expect(CatalogText.narrow(items, matching: "cafe", by: { $0 }) == ["Café Society"])
        #expect(CatalogText.narrow(items, matching: "netflix", by: { $0 }) == ["NETFLIX Originals"])
    }

    @Test("matching works on Arabic with a different hamza form")
    func arabicMatching() {
        #expect(CatalogText.narrow(items, matching: "افلام", by: { $0 }) == ["أفلام عربية"])
    }

    @Test("no match returns nothing rather than everything")
    func noMatch() {
        #expect(CatalogText.narrow(items, matching: "zzzz", by: { $0 }).isEmpty)
    }

    @Test("narrowing an empty list is safe")
    func emptyList() {
        #expect(CatalogText.narrow([String](), matching: "x", by: { $0 }).isEmpty)
    }
}

// ============================================================
// MARK: - Host normalisation  (MainActor: AuthService is main-actor isolated)
// ============================================================

@Suite("AuthService.normalizeXtreamHost")
@MainActor
struct HostNormalisationTests {

    @Test("a bare host gains the default scheme")
    func bareHost() {
        #expect(AuthService.normalizeXtreamHost("example.com") == "http://example.com")
    }

    @Test("surrounding whitespace is removed")
    func trimsWhitespace() {
        #expect(AuthService.normalizeXtreamHost("  example.com  ") == "http://example.com")
    }

    @Test("an explicit scheme is preserved")
    func keepsScheme() {
        #expect(AuthService.normalizeXtreamHost("https://tv.example.com") == "https://tv.example.com")
    }

    @Test("the port is preserved")
    func keepsPort() {
        #expect(AuthService.normalizeXtreamHost("http://example.com:8080") == "http://example.com:8080")
    }

    @Test("a pasted player_api link is reduced to its base")
    func stripsPathAndQuery() {
        // This is the single most common thing a user pastes into the server field.
        let pasted = "http://example.com:8080/player_api.php?username=a&password=b"
        #expect(AuthService.normalizeXtreamHost(pasted) == "http://example.com:8080")
    }

    @Test("a pasted get.php link is reduced to its base")
    func stripsGetPHP() {
        let pasted = "http://example.com/get.php?username=a&password=b&type=m3u_plus"
        #expect(AuthService.normalizeXtreamHost(pasted) == "http://example.com")
    }

    @Test("a trailing slash is removed")
    func stripsTrailingSlash() {
        #expect(AuthService.normalizeXtreamHost("example.com/") == "http://example.com")
    }

    @Test("empty and whitespace-only input yield an empty host, not a broken URL")
    func emptyInput() {
        #expect(AuthService.normalizeXtreamHost("") == "")
        #expect(AuthService.normalizeXtreamHost("     ") == "")
    }
}

@Suite("AuthService.xtreamAPIURL")
@MainActor
struct XtreamAPIURLTests {

    @Test("the plain case builds the player_api URL")
    func plain() {
        #expect(AuthService.xtreamAPIURL(base: "http://tv.example.com:8080",
                                         username: "user", password: "pass")
                == "http://tv.example.com:8080/player_api.php?username=user&password=pass")
    }

    // THE REASON THIS IS A FUNCTION AND NOT A STRING LITERAL.
    //
    // `&`, `=` and `+` are subtracted from `urlQueryAllowed` on purpose. Left
    // unescaped, a password containing one of them splits the query — the line then
    // authenticates as a DIFFERENT user, or fails with a message that explains
    // nothing. Providers hand out passwords with symbols in them all the time.
    @Test("an ampersand in the password cannot split the query")
    func ampersand() {
        let u = AuthService.xtreamAPIURL(base: "http://h", username: "a", password: "p&x=1")
        #expect(u == "http://h/player_api.php?username=a&password=p%26x%3D1")
        // Exactly two parameters, whatever the password contained.
        #expect(u.components(separatedBy: "&").count == 2)
    }

    @Test("plus and equals are escaped too")
    func plusAndEquals() {
        let u = AuthService.xtreamAPIURL(base: "http://h", username: "a+b", password: "c=d")
        #expect(u.contains("username=a%2Bb"))
        #expect(u.contains("password=c%3Dd"))
    }

    @Test("a space survives as an escape rather than breaking the URL")
    func space() {
        let u = AuthService.xtreamAPIURL(base: "http://h", username: "a b", password: "c d")
        #expect(URL(string: u) != nil, "the result must be a parseable URL")
        #expect(!u.contains(" "))
    }

    @Test("the result always parses as a URL, for every symbol a provider might use")
    func alwaysParseable() {
        for pw in ["p@ss", "p/w", "p?w", "p#w", "p%w", "p&w", "p+w", "p=w", "p w", "كلمة"] {
            let u = AuthService.xtreamAPIURL(base: "http://h:8080", username: "u", password: pw)
            #expect(URL(string: u) != nil, "failed for password \(pw)")
        }
    }

    @Test("it composes with normalizeXtreamHost, which is how both callers use it")
    func composesWithNormalise() {
        // switchPlaylist stores a bare host; loginXtream normalises first. The pair has
        // to produce the same string either way, or a restored playlist points nowhere.
        let base = AuthService.normalizeXtreamHost("tv.example.com:8080/get.php?x=1")
        #expect(base == "http://tv.example.com:8080")
        #expect(AuthService.xtreamAPIURL(base: base, username: "u", password: "p")
                == "http://tv.example.com:8080/player_api.php?username=u&password=p")
    }
}

// ============================================================
// MARK: - Version comparison  (MainActor: ActivationService is main-actor isolated)
// ============================================================

@Suite("ActivationService.versionLessThan")
@MainActor
struct VersionCompareTests {

    @Test("a later patch is greater")
    func patch() {
        #expect(ActivationService.versionLessThan("1.0.0", "1.0.1"))
        #expect(ActivationService.versionLessThan("1.0.1", "1.0.0") == false)
    }

    @Test("components compare numerically, not as text")
    func numericNotLexicographic() {
        // "1.10.0" < "1.9.0" is TRUE as strings and FALSE as versions. This one case
        // is the entire reason this function exists instead of `<` on String.
        #expect(ActivationService.versionLessThan("1.10.0", "1.9.0") == false)
        #expect(ActivationService.versionLessThan("1.9.0", "1.10.0"))
        #expect(ActivationService.versionLessThan("2.0", "10.0"))
    }

    @Test("equal versions are not less than each other")
    func equalIsNotLess() {
        #expect(ActivationService.versionLessThan("1.2.3", "1.2.3") == false)
    }

    @Test("a missing component counts as zero")
    func missingComponentIsZero() {
        #expect(ActivationService.versionLessThan("1.0", "1.0.0") == false)
        #expect(ActivationService.versionLessThan("1.0.0", "1.0") == false)
        #expect(ActivationService.versionLessThan("1.0", "1.0.1"))
    }

    @Test("a non-numeric component counts as zero rather than crashing")
    func garbageIsZero() {
        #expect(ActivationService.versionLessThan("1.x.0", "1.0.0") == false)
        #expect(ActivationService.versionLessThan("", "1.0.0"))
        #expect(ActivationService.versionLessThan("", "") == false)
    }
}
