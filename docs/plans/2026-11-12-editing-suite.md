# Complete editing suite — build 10

Goal: Deliver every capability accepted from the feature proposal, preserving film rendering, page curl, original bytes, gallery modes, font/text overlays and bounded export.

Design: Maintain five main tabs. Basic temperature/tint/black/white controls join Adjust. Curves, HSL and local retouch open focused draft sheets with Cancel/Apply. Detail viewer provides pinch/pan/double-tap reset and analysis tools. Presets/history open from editor actions; gallery multi-selection opens batch processing. No network services or new proprietary assets.

Implementation boundaries:
1. Color module: backward-compatible PhotoAdjustments with temperature, tint, black/white points, monotonic five-point master curve, six HSL bands; same Core Image path for preview/export. AdvancedColorControls.swift accepts settings/onApply, no LabModel writes. Pixel, identity, sanitizer and legacy decode tests.
2. Local module: standalone RetouchEdits and PhotoRetouchProcessor, normalized coordinates after geometry; linear/radial/brush exposure masks and source-to-target feathered repair strokes. Dedicated draft editor operates on unretouched geometrically corrected preview. Bounded layer/point counts, cancellation, no source mutation. Pixel/locality/scale tests. Geometry changes clear masks to avoid moving them onto unintended content, undo restores all.
3. Root integration: model cache and snapshot/persistence shared settings; descriptive session history with restore and redo; named disk-backed recipes and copy/apply (global style by default; spatial edits excluded across photos); batch snapshot executor processes gallery selections serially with a dedicated engine, progress, cancel, per-item errors and shareable files. Include output long-edge, format, size cap, watermark controls. Photo-based tasks must not overwrite current editor state.
4. Preview tools: focused UIScrollView zoom/pan viewer (1–8x), double-tap zoom/reset, original comparison; luminance histogram and clipped-highlight indication computed on a bounded 512px image, view-only overlay never exported. Native page curl untouched.
5. Validation: bounded synthetic runtime self-tests, backward decoding, preview/export parity, history/preset round trips, serial batch snapshot behavior and cancellation. Simulator visual checks, signed device build/install, explicit Git staging and existing GitHub push. Build jobs 1, engine jobs <=4; all evidence on external volume.

Integration contract:
- PhotoAdjustments adds `temperature`, `tint`, `blacks`, `whites`, `curve: ToneCurve`, `hsl: [HSLBand]`, `retouch: RetouchEdits` (default empty, backward decode).
- PhotoProcessor.tone handles global color only; `apply` adds geometry then PhotoRetouchProcessor.apply(..., edits: settings.retouch).
- RetouchEdits Codable/Hashable/Sendable, .sanitized(); PhotoRetouchProcessor.apply(CGImage, edits:) throws -> CGImage.
- AdvancedColorEditor(settings: PhotoAdjustments, onApply: (PhotoAdjustments)->Void).
- RetouchEditor(image: UIImage, edits: RetouchEdits, onApply: (RetouchEdits)->Void).

Delivery checklist:
- [x] Color and advanced controls
- [x] Local adjustment/repair
- [x] Zoom/histogram/highlight warnings
- [x] Presets/copy/history
- [x] Batch processing/export
- [x] Integration regression and visual QA
- [x] Install and launch build 10 on paired iPhone

Publication target: existing `origin/feature/36-frames`; publish the verified implementation and QA record together.
