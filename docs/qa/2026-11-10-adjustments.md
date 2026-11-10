# LiteFilm 0.1.0 (5): adjustments and favorites

## Changes

- Fixed visible exposure: the film engine automatically compensated the old film exposure parameter. Keep that parameter neutral and apply the requested EV to the completed image in linear light.
- Added highlights, shadows, contrast and saturation; normalized non-destructive crop; free/original/common fixed ratios; 90-degree rotation, straightening, horizontal/vertical perspective, and manual radial lens distortion correction.
- Preview and export share tone/geometry processing, followed by frame and watermark. Edits persist in archives and gallery variants and participate in undo.
- Removed film/paper simulation helper copy. Cards use F01… / P01…; full selected names remain below. Long press toggles a star and persistent favorites-first ordering without selecting the item. Codes retain catalog identity when reordered.
- Isolated undo between source photos and restored full edit state after failed gallery opening.
- Present crop editor from the stable root so orientation changes preserve drafts.

## Verification

- Debug arm64 simulator and signed Release arm64 device builds passed, serial jobs=1 with 1800-second process timeouts.
- Engine regression: old mean luminance at -1/0/+1 EV was 96.46/97.86/99.56; fixed values 69.93/97.86/134.61. New assertion failed before the fix and passed afterwards.
- Pixel checks passed: neutral image, crop/rotation dimensions, brighter shadows/darker highlights, opaque corrected geometry, invalid/nonfinite input sanitation, and legacy archive decode.
- Model checks passed: favorite persistence/order/code/selection, crop undo, archive/gallery roundtrip, export tone/aspect, retained original bytes, failed-gallery rollback and cross-photo undo isolation. Failed-gallery regression was red before the fix.
- Existing frame/export self-tests passed.
- Simulator UI checked at large and compact sizes. Latest compact verification: long-press F15 and P06 adds stars and scrolls to favorites first; selected F14/P05 remains unchanged; second long press cancels favorite. Full names remain legible in portrait. Crop 1:1 and quarter turn survive landscape-to-portrait rotation; Cancel leaves original preview and no undo action.
- Version 0.1.0 (5) installed over the existing app on the paired iPhone and launched successfully via devicectl; no uninstall.

## Limits

- Physical phone automation endpoint is offline/external; installation/launch are verified, but interactive physical-device acceptance is not claimed.
- Simulator automation drag did not produce observable movement, including horizontal lists; free-crop corner/interior dragging needs manual touch verification. Fixed-ratio cropping and geometry processing have automated coverage.
- Compact landscape control panels scroll vertically for additional controls.
- No new App Store/TestFlight upload or resubmission was performed in this feature task.

## Local evidence

Build/test logs and actual simulator screenshots are stored at:
`/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-10-Adjustments`

Final build logs: `orientation-simulator-build.log`, `verified-device-build.log`.
Final regression logs: `verified-engine-test.log`, `verified-frame-test.log`.
Installation evidence: `device-install.log`, `device-launch.log`.
Screenshots: `favorites-compact.png`, `paper-favorites-compact.png`, `crop-compact-portrait.png`.
