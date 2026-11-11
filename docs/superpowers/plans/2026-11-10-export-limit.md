# Editor ordering, bounded export, and vertical preview transition

User authorized direct implementation. Preserve unrelated untracked project files.

Design: bottom tools are Adjust, Film, Frame, Watermark, with Adjust initially selected. Crop & Correction is the first action in the adjustment strip, before Exposure. Export offers an optional integer KB cap (decimal KB = 1,000 bytes), disabled by default. Keep the selected JPEG/PNG/HEIC format; reduce lossy quality first, then proportional dimensions if needed. PNG preserves transparency and only reduces dimensions. Validate actual encoded bytes before exposing the share URL; report impossible limits instead of sharing an oversized file. Snapshot the cap with the other export choices.

Root-cause evidence: vertical preview moves select UIKit transitionCurlUp/Down in FrameChrome; horizontal moves select flip transitions. User reports only upward preview paging produces a colored block. Remove the vertical curl/backface path in favor of the existing directional slide/fade, retaining horizontal behavior and Reduce Motion. No unrelated scroll masks are changed.

Implementation:
- Reorder EditorControls and move the crop action in AdjustmentControls.
- Add an isolated ImageIO export encoder with a bounded quality/dimension search and input validation; cover real JPEG, PNG, HEIC bytes, decodeability, alpha, proportions, invalid limits and impossible targets with a small macOS CLI test.
- Add size controls and validation to ObsidianExportSheet; pass the captured byte cap through LabModel and ImageCodec, report actual final dimensions/size.
- Replace vertical curl and update its settings description.
- Run encoder tests, Swift syntax checks and app build/UI checks when resource gate allows. Preserve signed build 5 already awaiting review; this task does not withdraw its review.

Resource gate at start: startup free 5.6 GiB (< 10 GiB), another Xcode build active; no new heavy build or simulator launch until recovered. Encoder CLI is a small single-process test with an external timeout and bounded images; all outputs/caches go to external storage. iPhone runner is offline.
