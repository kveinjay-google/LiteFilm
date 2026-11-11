# LiteFilm 0.1.0 (6) verification — 2026-11-10

Implemented bottom tool order Adjust → Film → Frame → Watermark, with Crop & Correction first in the adjustment strip. Export now supports an optional integer KB cap, disabled by default, with custom input and 100/500/1000 KB presets. JPEG and HEIC reduce quality before dimensions; PNG reduces dimensions and preserves alpha. Encoded byte counts are checked before sharing; invalid and impossible limits fail without sharing oversized output.

Vertical preview paging previously used UIKit curl transitions, which introduce a synthesized backface/shadow. Vertical moves now use the existing directional slide/fade. Horizontal flip behavior remains unchanged.

## Verification

- Native ImageIO regression passed for JPEG, PNG and HEIC at 500,000, 100,000 and 10,000 bytes. Also checked decoding, format, aspect ratio, no upscale, generous caps, invalid/impossible limits and PNG alpha after resampling.
- Test-first baseline exceeded its 500,000-byte cap (590,074 bytes); implemented encoder passes. Final runner rerun passed after correcting its source path for case-sensitive checkouts.
- Runner uses one compiler job, compilation timeout 90 seconds and execution timeout 60 seconds, with process-group thread watchdogs. Final measured peak was one thread in each sampled run.
- Swift syntax checks, project plist lint and `git diff --check` passed.
- Debug arm64 simulator and signed Release iPhone builds passed. Generic simulator initially requested both architectures, incompatible with the existing engine configuration; explicit arm64 build passed.
- Simulator UI verified tab order, Crop & Correction entry, optional size controls, invalid zero disabling export, and successful system sharing. A 100 KB export produced a decodable 704×704 JPEG of **98,463 bytes**, including the selected frame/watermark.
- Version 0.1.0 (6) was installed and launched successfully on the paired iPhone without uninstalling the existing app.

## Verification limits and release state

The phone automation service was offline. Simulator automation did not reliably trigger the final attempted upward gesture, so transient animation appearance has not been visually verified on the physical phone. Source inspection and both builds verify removal of vertical curl transitions; physical swipe feedback remains useful.

Build 5 was already awaiting App Store review. This task installed build 6 for testing and did not withdraw or replace that submission.

## Local evidence and storage

Build/test/install logs, screenshots and export byte verification are stored outside Git at:
`/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-10-export-limit/`.

With user authorization, idle project DerivedData, watchOS DeviceSupport and two shutdown project simulators' MobileAsset caches were migrated to external storage with per-file SHA-256 verification and compatibility symlinks. Five durable manifests are under `/Volumes/LEXA 4TB DISK/Developer/migrations/2026-11-10-litefilm/`. Startup free space recovered from approximately 5.6 GiB to 11 GiB before full builds; the existing global DerivedData link and unrelated active simulators were preserved.
