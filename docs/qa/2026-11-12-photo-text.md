# Photo text — 0.1.0 (8)

## Changes

- Crop entry and editor title now read 裁剪; rotation, perspective and lens controls remain.
- Added 文字 between 相框 and 水印, with up to eight text blocks, 200 characters each.
- Draft editor: font, multiline content, relative size, six colors, alignment, shadow,
  drag placement, center reset and accessible horizontal/vertical sliders.
- Done records one undo action; cancel leaves the model untouched. Text is included
  in edit persistence (schema 7), gallery recipes, restored variants and exports.
- Positions and type scale follow the photo opening, with clipping to keep text off
  the mat; editor dragging uses a cached, bounded 720px surface. Existing page curl
  and export size cap are preserved.
- Unmodified Noto Sans CJK SC Regular 2.004, Noto Serif CJK SC Regular 2.003,
  LXGW WenKai Regular 1.530. SIL OFL 1.1 notices and copyright bundled and visible
  in About. SOURCES.json pins origins/hashes; bundling verifies every digest.

## Validation

- Debug arm64 simulator and signed Release arm64 iPhone builds: PASS, one Xcode job,
  1800-second build watchdog. Existing script-phase/deprecation warnings remain.
- `Scripts/test_photo_text.py`: PASS; sampled peak 23 app threads, limit 96, 90s timeout.
  Covers font registration and Chinese glyph coverage; archive compatibility;
  finite/clamped geometry, text/layer limits, duplicate identities; visible rendering;
  size invariance; top-left placement and clipping; model persistence, undo,
  gallery restoration, actual PNG export and resetting text on a new photo.
- `Scripts/test_preview_curl.py`: PASS; peak 19 threads, limit 96, 30s timeout.
  Vertical page curl, bounds, interruptions, resize, rapid swaps, cleanup and Reduce Motion.
- Signed bundle verification: PASS. All bundled font/license hashes match sources.
- Simulator UI: verified 裁剪 and fifth 文字 tool, editing sheet, Chinese font samples,
  switching to WenKai, actual keyboard text changes, amber color and size changes,
  and precise-position disclosure. Screenshot retained externally.
- The legacy FramePainter.pixels8 helper flips rows despite its top-left comment.
  Confirmed the saved PNG visually before using an independent unflipped bitmap
  reader for the new location test. Production painting was already oriented correctly.
- Device installation: devicectl succeeded on the user's paired iPhone, then launch
  succeeded. The separate iPhone UI runner is offline; no claim of full physical-device
  gesture QA. Simulator coordinate dragging was unavailable in the automation host;
  geometry/rendering was covered programmatically, but full drag/cancel interaction
  was not completed through that host.
- Application/source whitespace checks, generated project plist lint and Python syntax checks: PASS.
  The verbatim upstream LXGWWenKai-OFL.txt contains one trailing space on line 22;
  retained intact for the recorded upstream SHA-256 (excluded from whitespace lint).

Evidence (local only, not committed):
`/Volumes/LEXA 4TB DISK/媒体资源库/发布/LiteFilm/2026-11-12-text-qa/`
contains build logs, bounded regression logs, text-position PNG, editor screenshot,
and device installation/launch JSON. No App Store/TestFlight submission in this change.
