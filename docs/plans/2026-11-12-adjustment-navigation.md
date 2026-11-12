# Adjustment navigation — build 11

Goal: remove advanced-tool links from the persistent bottom of every tone panel and give editing tools a clear hierarchy within the existing Adjust tab.

Design: keep the five main tabs and existing dark/green palette. Use one evenly spaced icon-and-label rail: Crop, Light, Color, Curves, HSL, Local, Repair. Crop remains first. Light/Color reveal compact parameter selectors and one slider; the other tools open their dedicated editors. Curves and HSL each show only their own controls. Local/Repair enter the corresponding brush mode directly. Pending renders must settle before a full-screen editor opens. Cancel/apply, recipes and rendering remain unchanged.

Implementation checklist:
- [x] Replace AdjustmentControls footer with the tool rail; group parameters by light/color; align values and reset action.
- [x] Give AdvancedColorEditor an explicit curve/HSL section; give RetouchEditor a starting mode and accurate title.
- [x] Increment build to 11 in generator/project; document the new entry points.
- [x] Build simulator; inspect portrait, a narrow/landscape viewport, and independent editor entry/return. Run existing editing regression. No implementation-mirroring test for this presentation change.
- [x] Build/sign/install/launch on the paired iPhone; stage only scoped source/docs for the existing GitHub branch.

Validation evidence goes to the external media library. Use one build job and a 30-minute timeout. Physical-device touch QA depends on the phone runner; installation/launch can use devicectl.
