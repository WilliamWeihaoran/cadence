# Icon Concepts: Round 4 — drawn in the app's own visual language

Rounds 1–3 were rejected: round 1 as abstract geometry ("shapes mixed with each other"),
rounds 2–3 as invented brand names with illustrated, softly-shaded marks.

This round is built from `Cadence/Shared/Theme.swift` rather than from taste. Every value below
is a literal token from the shipping app, not an approximation:

| Role            | Token                                    | Hex       |
|-----------------|------------------------------------------|-----------|
| Tile            | `Theme.surface`                          | `#131316` |
| Primary ink     | `Theme.text`                             | `#ededef` |
| Recessive ink   | `Theme.borderStrong`                     | `#3f3f46` |
| Blue            | `CadenceAccentPalette.cadence.blueHex`   | `#4a9eff` |
| Red             | `...redHex`                              | `#ff6b6b` |
| Green           | `...greenHex`                            | `#4ecb71` |
| Amber           | `...amberHex`                            | `#ffa94d` |
| Purple          | `...purpleHex`                           | `#a78bfa` |
| Teal            | `...tealHex`                             | `#45CBC4` |

Shared construction rules, matching the UI: one stroke weight per mark, round line caps,
flat fills, no gradient, no bevel, no letterform, at most two hues plus a recessive neutral.

## The eight

| Name   | Mark                                    | What the name claims          |
|--------|-----------------------------------------|-------------------------------|
| Morrow | half sun over a rule                    | the day ahead                 |
| Tally  | five-bar gate                           | a running count of what's done|
| Rung   | ladder, one lit rung                    | one step, then the next       |
| Loop   | open ring, marker at the top            | the part of the day that repeats |
| Lane   | three staggered bars beside a rail      | the day laid out end to end   |
| Noon   | progress track crossed by a now-line    | where you are in it           |
| Steady | spirit level, centred bubble            | level, not fast               |
| Vesper | evening star over a horizon             | the hour you look back        |

## Status

- **Not approved.** Concept presentations, not production exports.
- **No availability check has been run** on any of these names — no App Store search,
  no trademark search. Assume nothing is clear.
- A rename is cheap only before the first upload: the bundle id `com.haoranwei.Cadence`
  and the CloudKit container name are permanent afterwards.

## Files

`*.svg` are the source (vector, 200-unit grid). `*.png` are 1024x1024 rasterisations made with
`qlmanage -t -s 1024`, for eyeballing at real icon size.
