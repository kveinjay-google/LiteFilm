# Photo text and crop label

Rename both crop entry and editor title to 裁剪; retain geometry tools.
Add 文字 between 相框 and 水印. Up to eight independent multiline text layers,
each with bundled Chinese font, size, color, alignment, shadow and normalized position.
An isolated draft editor provides live raster preview and drag placement; cancel
changes nothing, done records one undo step. Text is anchored to the final photo
opening, clipped within it, and composed before the existing watermark. The same
renderer serves preview and export, including export without a frame.

Persist layers in edit schema 7 and gallery recipes with optional fields for old
archives. Reset text on new originals, restore on gallery variants and undo.
Bundle unmodified Noto Sans/Serif CJK SC Regular and LXGW WenKai Regular, with
upstream source hashes and complete SIL OFL notices, visible in About.

Validation: sanitizer/archive tests, font registration and Chinese glyph coverage,
render position/clipping/scale checks, model undo/persistence/gallery/export checks,
simulator UI, signed iPhone build/install. Preserve page curl and size-limited export.
