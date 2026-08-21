// ============================================================
// BLANK TV — TypeScaleTests.swift
// The type scale was fixed point sizes, so Larger Text did nothing at all. Making it
// scale is the kind of change that either does nothing visible or breaks every
// screen, and the difference is a curve nobody can eyeball.
//
// These pin both ends of it WITHOUT a device: `scaledValue(for:compatibleWith:)`
// takes a trait collection, so the whole Dynamic Type range can be asked directly.
// ============================================================

import Foundation
import UIKit
import Testing
@testable import BlankTV

@Suite("S8KFont type scale")
@MainActor
struct TypeScaleTests {

    @Test("at the DEFAULT text size nothing changes — every token keeps its design size")
    func defaultIsANoOp() {
        // The single most important assertion here. Most users never touch the
        // setting, and for them this change must be invisible. A scale that shifted
        // the default layout by even a point would be a redesign nobody asked for.
        for t in S8KFont.designSizes {
            let got = S8KFont.scaledSize(t.size, t.style, category: .large)
            #expect(got == t.size, "\(t.name): expected \(t.size), got \(got)")
        }
    }

    @Test("every token grows at the largest accessibility size")
    func growsAtAX5() {
        for t in S8KFont.designSizes {
            let got = S8KFont.scaledSize(t.size, t.style, category: .accessibilityExtraExtraExtraLarge)
            #expect(got > t.size, "\(t.name) did not grow: \(t.size) -> \(got)")
        }
    }

    @Test("every token shrinks at the smallest size")
    func shrinksAtXS() {
        for t in S8KFont.designSizes {
            let got = S8KFont.scaledSize(t.size, t.style, category: .extraSmall)
            #expect(got <= t.size, "\(t.name) grew when it should shrink: \(t.size) -> \(got)")
        }
    }

    @Test("the curve is monotonic — bigger setting is never smaller text")
    func monotonic() {
        // A non-monotonic curve would mean a user increasing their text size sees
        // something get SMALLER. Worth pinning because the mapping from token to text
        // style is a judgement call, and a wrong pairing can produce exactly that.
        let ladder: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge,
        ]
        for t in S8KFont.designSizes {
            var previous: CGFloat = 0
            for c in ladder {
                let got = S8KFont.scaledSize(t.size, t.style, category: c)
                #expect(got >= previous, "\(t.name) shrank going from the previous step to \(c.rawValue)")
                previous = got
            }
        }
    }

    @Test("the smallest token stays legible at the largest setting")
    func smallestTokenBecomesReadable() {
        // caption3 is 9pt — the smallest type in the app, and the reason Larger Text
        // support is not cosmetic here. At AX5 it has to reach something a person who
        // needs that setting can actually read.
        let got = S8KFont.scaledSize(9, .caption2, category: .accessibilityExtraExtraExtraLarge)
        #expect(got >= 18, "9pt only reached \(got) at AX5")
    }

    @Test("headings still outrank captions at every setting")
    func hierarchyHolds() {
        // Different text styles scale at different rates, so a badly chosen pairing
        // can invert the hierarchy at the top of the range — a caption rendering
        // larger than the title above it. This walks the range and refuses that.
        let ladder: [UIContentSizeCategory] = [
            .large, .extraExtraExtraLarge, .accessibilityLarge,
            .accessibilityExtraExtraExtraLarge,
        ]
        for c in ladder {
            let display  = S8KFont.scaledSize(34, .largeTitle, category: c)
            let headline = S8KFont.scaledSize(15, .headline, category: c)
            let caption  = S8KFont.scaledSize(11, .caption1, category: c)
            #expect(display > headline, "display <= headline at \(c.rawValue)")
            #expect(headline > caption, "headline <= caption at \(c.rawValue)")
        }
    }
}
