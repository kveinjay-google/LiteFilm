# LiteFilm build 12 — visual polish verification

Date: 2026-11-12. Baseline: `51ea25e`, branch `feature/36-frames`.

## Delivered

Deep green studio chrome (#101816), warm text (#F5F2E9), secondary text (#A4AFA6), champagne accent (#DEC79A). Shared theme covers the existing editor sheets without changing image processing. Primary/header/thumbnail selection treatments, home composition, export groups and settings/About branding were refined. All five bottom tools, seven independent adjustment routes, film/paper favorites and gallery behavior remain.

The icon was generated using OpenAI's built-in image generation, with mechanical sips resizing for all existing platform sizes and a reusable BrandIcon asset. Original direction: opaque deep forest green square, centered champagne film gate with three sprocket holes per side and broad ivory diagonal light beam; no text. Generated master and provenance manifest remain in the external media library. No secrets or user photos are included in this commit.

Launch storyboard and SwiftUI use the same 88pt image / 18pt gap / 24pt semibold title on the same canvas. Removed the previous 1.15-second artificial hold. A launch storyboard runtime-radius attribute was rejected by ibtool in the first build; replaced with supported static geometry before final builds.

## Verification

- Debug arm64 simulator build and signed Release arm64 device build: PASS, one xcodebuild job, 30-minute watchdog each. Existing engine deprecation/script-output warnings remain.
- Existing editing suite: PASS (gallery snap arithmetic, color, local repair, histogram/analysis, batch JPEG/PNG, recipes, undo/redo and model integration). External 240-second watchdog and 96-thread ceiling.
- Asset sanity: all app icon PNG dimensions match their named sizes; square and opaque. Brand images provide 1x/2x/3x variants.
- Measured contrast on base: primary text 16.11:1, secondary 7.95:1, accent 10.94:1. This is a token check, not a complete accessibility audit.
- Actual iOS 26.5 simulator visual inspection: populated home, portrait editor, film selection/favorites, final export page, settings and About. Centered header, intact photograph aspect, clear controls and license content observed.
- Local retouch inspected portrait/landscape. Landscape now reserves a large photo area and separate controls. Rotation initially dismissed the editor because ContentView conditionally recreated EditorControls. Replaced HStack/VStack branches with AnyLayout. Re-tested with one radial draft layer through landscape → portrait: editor remained open and layer count stayed 1. Cancelled the temporary draft after inspection.
- Signed build 12 installed and launched successfully on the paired iPhone through devicectl.

## Evidence and limits

Logs, icon master, installation/launch JSON and screenshots are stored under the external media library's `发布/LiteFilm/2026-11-12-commercial-polish` directory. Export was visually inspected through the tool's returned screenshot; a subsequent file capture switched to another active Simulator window and is explicitly excluded as export evidence.

The phone automation endpoint remains offline and externally managed. Installation/launch succeeded, but direct phone interaction QA was not performed. Simulator scroll/drag injection was unreliable, so no new claim is made about physical flick velocity or gallery centering beyond the existing numerical tests. No frame-accurate cold-launch recording, exhaustive iPad/Dynamic Type matrix, or separate empty-home screenshot was produced. No App Store or TestFlight submission was performed in this task.
