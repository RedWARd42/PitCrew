# Overlay design notes

Principles (apple-design / emil-design-eng): restraint, one accent per drone, springs not tweens, interruptible
motion (drones retarget live while scrolling), nothing animates without a purpose, reduced motion snaps.

- Motion: drones use a slightly underdamped spring (zeta about 0.8) simulated per frame, so a scroll simply moves
  the target and the drone re-anchors smoothly. Launch is staggered 70ms, in parallel. Sheet slides up 300ms
  ease-out; press feedback is a 0.97 scale. `MediaQuery.disableAnimations` snaps positions and stops rotors/bob.
- Material: solid surfaces (white / graphite by platform brightness) with hairline border and soft shadow so the
  panel, chip and Hive read over both light and dark Google Messages. Hive is a dark graphite disc with a colored
  status ring (green / amber / red / neutral) so it never disappears into either theme.
- Type: system font, tight tracking on large sizes (-0.3 to -1), 16sp body, 13sp uppercase labels.

## Mobbin references (cues taken)
1. Phantom, "Keep Your Recovery Phrase Secret" (https://mobbin.com/screens/1a8dc318-cdb3-4d4b-9106-03fbd78f3320):
   red shield icon + short bold headline for a warning; informed the Warden "Hold up" card hierarchy.
2. X, "Your assets are safe" sheet (https://mobbin.com/screens/14a00e21-adb3-4a7a-aa74-01c2ee7908cd):
   large-radius white bottom sheet, single full-width Done button; informed sheet radius (28) and action buttons.
3. Cash App, "Scam warnings" (https://mobbin.com/screens/1b58d10a-e494-4fb7-a03f-1dcf1c8acdf5):
   calm plain-language alert copy, green/neutral tone for "we detected something"; informed chip wording.
4. Lemonade analysis result (https://mobbin.com/screens/cc8c461b-0bee-4d00-8a40-4fe4f9b4cd07): labelled rows with a
   compact rating visual; informed the Summary "What the drones found" rows and risk meter.
5. Insight Timer "Repeat" sheet + Discord status sheet (https://mobbin.com/screens/afb57a33-34ce-45a1-a924-07f1d75207e3,
   https://mobbin.com/screens/89a029ad-34c3-4d35-aa95-e476c1c0c0c4): segmented/pill tabs with a filled selected
   state and a colored status dot; informed the per-drone tab chips.

Art: drones, Hive, beam, outlines, meter and sparkline are all CustomPainters (no raster assets, no new deps).
