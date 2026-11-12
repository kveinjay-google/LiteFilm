# Editing suite — build 10

## Delivered

- Temperature/tint, black/white points, five-point master curve and six-band HSL, with cancellable live-preview sheets.
- Linear, radial and brush local exposure/saturation; feathered source-sampling repair. Geometry changes invalidate spatial edits; undo restores them.
- 1–8× preview zoom/pan, original comparison, bounded luminance histogram and display-only highlight warning.
- Named persistent recipes, copy/apply, shared toolbar/native undo/redo and a 60-step session timeline.
- Gallery selection batch export, serial rendering, progress, cancellation and per-item errors; JPEG/PNG/HEIC, long-edge/size limits and decoration switches.
- Fixed first-presentation empty batch selection by passing an identifiable selection snapshot with the sheet.

## Verification

- Final simulator integration run: PASS (`LITEFILM_EDITING_SUITE_OK`), peak sampled app threads 25, ceiling 96, external timeout 240 seconds. Covers actual color/local pixels, old decoding, analysis orientation, recipe persistence, native and toolbar history, branching, photo changes, batch recipe isolation and actual JPEG/PNG output limits.
- Earlier text regression in this implementation: PASS, peak 23 threads, 90-second watchdog. Final change after that run only affects gallery batch-sheet presentation.
- Final signed Release build: PASS, one Xcode build job, 30-minute process-group timeout. Strict signature verification: PASS. Packaged CFBundleVersion: 10.
- Simulator evidence retained for curves, highlight detail, local retouch and batch success. Final live inspection confirms a generated 747 KB JPEG in the system share sheet. Completing Save to Files was not verified: CUA returned `windowNotFoundAtPosition` for the simulator window; no claim is made that a Files destination was saved.
- Final build installed on the paired iPhone 17 Pro Max and launched successfully through devicectl. The phone UI automation runner is externally managed and offline, so physical-device visual/gesture QA was not performed.
- `git diff --check`: PASS. Explicit source/project/document list checked for common credential patterns and the 50 MB file limit: PASS.
- Existing engine build-script, unnecessary `try`, Core Image kernel-language deprecation and absent App Intents metadata warnings remain. No build errors.

Evidence directory: `/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-12-editing-suite-qa/` (final test/build logs, screenshots, installation and launch JSON).

## Scope and limits

Repair uses sampled pixels, not content-aware AI. Zoom enlarges the bounded preview, not a full-resolution RAW development view. History is per-photo/per-session; recipes persist. Batches process at most 50 items; output resolution remains constrained by the existing device-memory ceiling. This update includes local installation and source publication, not a new App Store/TestFlight submission.
