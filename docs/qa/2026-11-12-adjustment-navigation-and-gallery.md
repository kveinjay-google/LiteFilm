# Build 11 — adjustment navigation and immersive gallery QA

Evidence directory: `/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-12-adjustment-navigation-qa/`.

## Verified

- Dedicated iOS 26.5 simulator: `BEDC19A5-9C45-41F5-81A3-9A379828D949`.
- Final Debug simulator build passed. Existing engine build-phase and Core Image deprecation warnings remain; no compilation errors.
- Editing regression passed with 21 sampled app threads (96-thread ceiling, 240-second watchdog). Includes curves/HSL, local adjustment, repair, histogram, JPEG/PNG batch output, recipes, native undo/redo, and model transitions.
- New page-target numerical tests passed for 393/852/1194-point viewports, multi-page projection, beginning/end clamping, one/zero items and invalid dimensions. These test target math, not touch input.
- Visually inspected the real running simulator UI: seven distinct adjustment tools, parameter chips/value/reset/slider in portrait and landscape; HSL opens its own controls; curve opens its own editor; repair immediately requests a source point. Cancel returns to the main editor.
- Gallery inspected in portrait and landscape: artwork centered on a full-screen warm wall; no black header/footer or persistent title/date. Axis button switches its persisted value. Tapping hides/reveals chrome. Menu selection mode selects a work and enables batch actions. Edit-current opens that work.

## Limits and follow-up

- Automated simulator drag/scroll input did not produce movement in either the new gallery or the pre-existing album grid. Drag calls acted like taps; instrumented gallery targets only reported zero velocity/origin on layout. Removing the simultaneous gesture did not change that observation. The final implementation observes native scroll phase on iOS 18+, with a focused-ID fallback on iOS 17, rather than adding another pan recognizer.
- Consequently normal/fast real touch flicks, physical end-page resting position and non-first-item axis retention are **not yet interactively verified**. They must not be reported as passed based on numerical tests.
- The externally managed iPhone automation runner reports offline; do not take over its setup. Device installation/launch is separate from physical touch QA.
- Numbered aspect-ratio fixtures were added only to the dedicated simulator; its original manifest was backed up externally. The original simulator manifest was restored after testing (fixture files retained externally and in the dedicated simulator for repeatability). No physical-device photos were touched.

## Device delivery

Release build passed; strict/deep code-signature verification passed; bundle version verified as 11. Build 11 installed and launched successfully on the paired iPhone. Launch result is recorded in `device-launch-final.json`. No App Store/TestFlight submission was made in this UI-only change.
