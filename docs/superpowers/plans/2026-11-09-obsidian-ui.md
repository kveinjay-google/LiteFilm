# LiteFilm Obsidian implementation plan

Approved design uses near-black surfaces, white text, pale yellow selected controls, centered upright LiteFilm lettering, large photo previews and four editing tools. Reference boards are in the external media library under LiteFilm/2026-11-09-黑曜完整页面.

Implement in the existing feature checkout, retaining the current build-3 corrections. Keep the app identifier, saved edit representation, engine and third-party attribution compatible. Use subagent-driven-development for the isolated gallery view and review, and serialize builds.

- [x] Establish shared Obsidian colors and centered navigation in ObsidianStyle.swift. Use a ZStack title and equal reserved side widths, 44-point controls and scalable labels.
- [x] Rebuild HomeGalleryViews.swift as a large featured photo with recent thumbnails and import action, plus a two-column works grid. Retain open, import, delete confirmation, variants and built-in sample access.
- [x] Replace editor wheels with an EditorControls.swift tab dock. Film/paper lists use real catalog values, frame thumbnails reuse model.thumbs, exposure uses a -2...2 accessible ruler, watermarks reuse catalog selection and identity editing. Keep all presets accessible. Show original on press-and-hold and preserve photo aspect ratio.
- [x] Move export and settings into dedicated sheets in ObsidianSheets.swift. Reuse JPEG/PNG/HEIC and current frame/watermark toggles. Preview output composition consistently. Group signature, transitions, privacy, support and licenses.
- [x] Simplify PrintViewport chrome while retaining zoom, pan, frame gestures and watermark dragging. Update default app watermark identity from Spektra to LiteFilm without rewriting custom saved text.
- [x] Add targeted model regression checks for original comparison and export preview composition. Validate existing render/frame/gallery tests and run a simulator build with ARCHS=arm64 and at most four build jobs after resource preflight.
- [x] Inspect real simulator UI on large and compact sizes, exercise import, all tools, export and settings, and correct clipping or alignment. Increment build to 4 and install the verified Release app on the paired iPhone without uninstalling its data.
- [x] Review final diff, retain verification logs/screenshots in external release folder, commit only scoped source and plan files after passing checks.
