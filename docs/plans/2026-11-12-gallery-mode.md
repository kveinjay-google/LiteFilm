# Gallery mode implementation plan

Goal: Keep the existing album and add a persistent, directly accessible gallery presentation to 全部作品.

Design: A warm gray exhibition wall with complete, uncropped photographs, restrained dark frames, paper mats and soft directional shadows. Portrait phones show one large artwork per row; wider windows show two. Saved variants already contain their chosen framing, so use a minimal mount. Artwork captions contain title, sequence and import date. No photo bytes or recipes change.

Alternatives considered: a horizontal carousel hides collection overview; a 3D room adds navigation complexity and rendering cost. Use a vertically browsable exhibition wall with native scrolling instead.

Implementation:
- [x] Add a separate AppStorage presentation preference (album default), visible album/gallery switch and route gallery content before existing album layouts.
- [x] Create GalleryWallView.swift for the wall and aspect-preserving mounts, sharing the existing serial thumbnail loader and 32 MiB cache. Reuse selection, open and delete actions. Keep old layout menu specific to album.
- [x] Validate simulator build and UI (actual coverage and limitations recorded in docs/qa/2026-11-12-gallery-mode.md): default, switch, persistence, artwork aspect ratios, selection, open, missing thumbnails, empty state and narrow/wide layout. Build signed device release with one Xcode job and existing bounded engine jobs.
- [x] Install on the authorized iPhone and record evidence.
- [ ] Commit only task files and sync existing GitHub branch.

Also includes the pending text-tool symbol fix (text.badge.plus) and build 9. No App Store submission is part of this update.
