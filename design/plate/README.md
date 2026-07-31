# THE PLATE — generated artwork, reference implementation

This app is fed by the user's own IPTV provider, so posters, titles, ratings and EPG
are frequently missing. Every competitor answers that with a grey box. This answers it
with artwork the app makes itself: a deterministic woven plate, dyed from the title's
own letters, with the name set in live type over it.

The consequence is the point — **there is no broken-image state anywhere in the app.**

`plate_reference.py` is the reference implementation, kept OUTSIDE the Xcode target.
It exists to be run and looked at, because every claim below was settled by rendering
rather than by argument.

```
python plate_reference.py     # writes the three sheets next to it
```

## Construction

`SHA-256` of the normalised title seeds every knob: thread counts, hue, hue drift,
three low-frequency sinusoids, slub. Same title, same cloth, forever, with no state
and no network.

Colour is evaluated in **OKLab** with **chroma hard-clamped to 0.055** and lightness
banded **0.20–0.40**. That clamp is the whole difference between dyed cloth and a
pixel sprite, and it is why a rail of plates sits *under* real poster artwork instead
of fighting it. It is the most fragile number here — do not raise it without looking.

## Three things that were verified by rendering, not asserted

**1. Near-collisions separate.** The objection was that a dozen chroma-clamped plates
would look like one object repeated. `MBC 1` / `MBC 2` / `MBC 3` / `MBC 4` — four
strings differing by one character — produce four plainly different plates
(`weave2_near.png`). SHA-256's avalanche does the work.

**2. The first version was not cloth.** It had weft only: horizontal bands fading
into each other, which reads as a coloured blur placeholder, and those already exist
elsewhere. What makes a textile read as *made* is two thread directions crossing and,
above all, the **over/under interlace parity** — one thread passing over another. That
parity is a single term in the loop and it is the difference between this and a
gradient. Slub (seeded per-thread thickness variation) keeps it from reading as
machine print. See `weave2_detail.png` at 1:1.

**3. Thread count must follow the pixels.** With a fixed 26–52 warp, a 192 px cell
gives a ~4 px thread, the interlace parity lands on alternating pixels, and the weave
aliases into moiré and hard stripes. Rendering the same title at 354 / 312 / 192 px
showed only the smallest breaking. `MIN_THREAD = 7.0` clamps the seeded counts to what
the render size can actually resolve. **This would have shipped broken**, because it
looks correct at every size a designer inspects and fails at the size a phone draws a
small cell.

## Porting to Swift — the constraints that matter

- Draw **once per title** into `S8KImageCache` (`DesignSystem.swift:1375`) as an
  `Image`. Never a live `Canvas` inside a scrolling cell: this repo has a recorded
  scroll-stutter history, and ~100 bands across ~30 visible cells is how it returns.
- Key the cache on **(normalised title, pixel size)** — per `MIN_THREAD`, the same
  title at two sizes is two different plates, and re-scaling one into the other
  reintroduces exactly the aliasing the clamp removes.
- The **type carries the meaning**, not the colour. The plate is therefore fully
  legible in greyscale, to a colour-blind user, and to VoiceOver — set
  `.accessibilityLabel` to the normalised name. Colour here is texture, never
  information.

## Where the same object reappears

The empty poster · the empty hero · the empty detail canvas · the buffering screen ·
every failure state · the gateway ground. One rule, six surfaces.
