# Immersive gallery — build 11

User requirements: settle every browse gesture with an artwork centered; fast gestures may skip multiple works; offer explicit horizontal as well as vertical browsing; remove distracting black bars and persistent text.

Design: full-screen warm exhibition wall, one complete photograph per viewport. Native scroll projection determines travel distance, then a custom ScrollTargetBehavior rounds the resting origin to a viewport boundary. There is no one-page momentum limit. Keep the current artwork ID outside the scroll view so axis changes and viewport changes preserve it. Both directions are persisted separately from album layout.

Controls: overlay compact back, direction and menu icons, a small counter and edit action. No permanent page title, filter bar, captions or bottom toolbar in browse mode. Dragging or tapping hides controls; tapping reveals them. Optional artwork info lives in the menu. Selection mode retains batch/delete controls. Original files, saved recipes and album layouts stay intact.

Validation: numeric snapping tests for both axis lengths, multi-page projection, start/end boundaries, single/empty data and invalid sizes. Simulator interaction must exercise normal/long drags, axis change, first/last photos, tap-to-reveal, editing and selection. Inspect full-screen centering and clean edges in portrait/landscape. Use synthetic numbered QA cards in the dedicated simulator, never modify a physical-device user's gallery for testing.
