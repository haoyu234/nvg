# nvg

A **Nim** port of [nanovgXC](https://github.com/styluslabs/nanovgXC), including several opinionated modifications. 
Note that some changes may not constitute improvements, given my limited background in graphics programming.

# Features inherited from nanovgXC
* rendering of arbitrary paths with "exact coverage" antialiasing
  * it is not necessary to specify whether each subpath encloses a solid area or a hole
  * including very thin (a few pixels or less) filled paths, with which nanovg's antialiasing technique has some difficulties
* support for both even-odd and non-zero fill rules
* support for rendering text as paths
* Slug text rendering
* dashed strokes support

# Build and run samples
* `nimble install sokol`
* `nim -d:feature.nvg.sokol c -d:release -d:danger tests/tdemo.nim`
* or `nim -d:feature.nvg.sokol -d:gl c -d:release -d:danger tests/tdemo.nim`

# Borrowed & Referenced Libraries
* [stb_truetype.h](https://github.com/nothings/stb/blob/master/stb_truetype.h): Majority of the TrueType implementation
* [opentype.js](https://github.com/opentypejs/opentype.js): Glyph layering and color processing
* [freetype](https://github.com/freetype/freetype): Text outline path generation logic
* [Skribidi](https://github.com/memononen/Skribidi): Heavily referenced
* [libunibreak](https://github.com/adah1972/libunibreak): Line‑breaking algorithm
* [SheenBidi](https://github.com/Tehreer/SheenBidi): Bidirectional text analysis and script run localization
* [sokol-slug-odin](https://tangled.org/dosha.dev/sokol-slug-odin): Slug algorithm implementation for sokol‑gfx
* [nanovg_sokol.h](https://github.com/void256/nanovg_sokol.h): Heavily referenced
* [pixie](https://github.com/treeform/pixie): Some enums and user‑friendly API styling
* [cairo samples](https://www.cairographics.org/samples): Some demos are adapted from these samples
* [MDN tutorial](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Drawing_shapes): Some demos are adapted from these samples

# My own modifications:
* Added [sokol](https://github.com/floooh/sokol-nim) backend support
* Added instanced rendering support
* Removed `NVGwinding`, only `NVGfillRule` is retained
* Added Slug algorithm support
* Added basic rich‑text support
* ...

# Status
Image rendering and gradients are not yet implemented. This project is insufficiently tested and **not intended for production use**.
