# Preserve vertical page curl

User explicitly wants the page-turn effect retained, with no stray colored blocks or animation artifacts. Direct execution is authorized.

Hypothesis: UIKit's curl is applied to a full-size aspect-fit image view, including transparent letterboxing, with no clipping ancestor. Curl's generated backface and shadow can therefore cover the surrounding preview area. Test this against a curl surface fitted to the actual image and clipped by a stable container. Do not replace the requested curl with slide/fade.

- Add a Debug-only deterministic preview transition probe that exercises the production coordinator, plus the legacy full-bounds curl for comparison. Inspect actual simulator compositor frames during upward and downward turns using wide, tall and transparent content.
- Restore vertical curl inside an image-fitted clipped host, keeping horizontal flips and Reduce Motion behavior. Clean up the temporary host on completion, interrupted gestures, image replacement, layout change and view dismantling.
- Verify animation checkpoints and rapid interruption, compile simulator and signed device builds under bounded jobs/timeouts, install on the paired iPhone, record evidence and sync only relevant source files to the existing public repository.

The phone UI automation runner is currently offline. Use simulator visual evidence and device build/install evidence; do not claim physical swipe verification without it. Keep the existing App Store submission intact.

Completed: legacy artifact reproduced, native curl restored inside the fitted clipped host, intermediate compositor frames checked, lifecycle regression passed, simulator/Release builds passed, and build 7 installed/launched on the paired iPhone. Evidence and limitations are recorded in `docs/qa/2026-11-10-page-curl.md`.
