# Gallery mode and text icon — build 9

## Implementation

- Default album retained, separate persisted album/gallery presentation switch.
- Gallery wall uses complete oriented image bounds, thin frames, paper mats, warm wall and captions. Saved variants keep their existing framing.
- Phone portrait: vertical exhibition. Wide, sufficiently tall windows: two columns. Compact landscape: horizontal exhibition with a combined toolbar.
- Existing filtering, import, open, selection and confirmation-based deletion callbacks reused. No image/recipe migration or exported-image change.
- Shared thumbnail decoder is serial, capped at 1,200 pixels, cached with a 32 MiB/60-entry limit; views load lazily.
- Replaced localized `textformat` symbol with `text.badge.plus` in the main text tab and text-layer list.

## Verification

- Final Debug simulator and signed Release device builds: PASS; Xcode jobs=1, 30-minute process-group watchdog. Existing engine-script, Core Image deprecation, unnecessary try and App Intents metadata warnings remain.
- Strict code-signature verification: PASS. Packaged CFBundleVersion: 9.
- Build 9 installed on the authorized iPhone successfully; devicectl launch confirmed.
- Dedicated iOS 26.5 simulator UI: default album, gallery switch, complete portrait image, selection count, selected item retained across mode switch, finish selection, open artwork in editor, return to gallery, persistence through app replacement/relaunch: PASS.
- Compact landscape reviewed, then rotated back to portrait: PASS. Wide iPad layout is implemented but not visually exercised in this pass.
- Text icon visibly renders as lines with a plus, distinct from its caption: PASS.
- Preferences inspected after relaunch: gallery persisted; original gallery manifest entry retained.
- Empty and missing-thumbnail views are retained/provided in code; not separately exercised. Destructive deletion was not performed during UI QA.
- No new automated test was added for this presentation-only change. No rendering/export algorithm changed.

Evidence: `/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-12-gallery-qa/` (build logs, portrait/landscape screenshots, text-icon screenshot and device command JSON).

Physical-device interaction remains unavailable through the offline phone automation runner. Device installation/launch is verified using Apple's devicectl; visual checks above used the dedicated simulator. No App Store or TestFlight submission is included in this update.
