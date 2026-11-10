# Photo adjustments implementation plan

Goal: visible exposure changes, non-destructive photo tone/crop/geometry editing, cleaner film panel.
Architecture: retain film/paper engine at neutral film exposure; apply user exposure in linear light after film rendering. Core Image adjustment pipeline shared by preview and export. Codable optional photo adjustments in existing archives and gallery variants, included in undo. Separate full-screen crop editor with local draft and cancel/apply.
Tech stack: SwiftUI, Core Image, existing native engine.

- [x] Reproduce exposure cancellation with real engine output: compare mean luma at -1, 0, +1 EV; require monotonic visible change. Run existing self-test before fix.
- [x] EngineClient: keep film exposure 0, apply CIExposureAdjust to finished image using requested EV. Check preview/export parity.
- [x] PhotoAdjustments.swift: tone (highlights/shadows/contrast/saturation), normalized crop, quarter turns, straightening, horizontal/vertical perspective and radial distortion. Sanitize finite bounded values. Geometry precedes normalized crop. Preserve original bytes. Neutral pipeline returns original.
- [x] LabModel: capture adjustments for render/export; preview includes crop; expose uncropped toned image for crop editor; snapshot, restore, persistence and gallery recipe; reset geometry for new unrelated photos. Framing source ratio follows edited image dimensions. No stale render overwrites newer state.
- [x] AdjustmentControls.swift and CropEditor.swift: dark Obsidian tabs, selected value slider, resets; full photo crop overlay with rule-of-thirds, draggable corners/interior, free/source/1:1/4:3/3:4/3:2/2:3/16:9/9:16; angle, 90° turns, vertical/horizontal perspective, radial lens correction. Cancel leaves model untouched; apply one undo.
- [x] EditorControls.swift: remove film/paper simulation helper text; integrate new panel. Preserve four main tabs and compact landscape access.
- [x] Regression tests: actual pixel luminance, selective highlights/shadows, neutral identity, crop aspect/dimensions, geometry no alpha holes, extreme/nonfinite sanitization, archive backward compatibility, undo, gallery round-trip and exported PNG content/dimensions.
- [x] Serial build jobs1 with timeout1800. Simulator tests timeout180; visually exercise adjustment/crop/cancel/apply/export at large and compact sizes. Release build5; install to paired iPhone without uninstall. Scope git changes, document evidence and commit/push.


Follow-up delivered: short F/P catalog codes, full selected names below, exclusive long-press favorites, persistent independent film/paper favorites and stable favorites-first ordering. Crop presentation moved to the root so device rotation preserves its draft.

QA scope and remaining manual verification are recorded in `docs/qa/2026-11-10-adjustments.md`. App Store resubmission is outside this feature delivery.
