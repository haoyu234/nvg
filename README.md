# nvg

A **Nim** port of [nanovgXC](https://github.com/styluslabs/nanovgXC) with some opinionated modifications—though these changes may not necessarily be improvements, since my knowledge of graphics programming is limited.

# Features inherited from nanovgXC:
* rendering of arbitrary paths with "exact coverage" antialiasing
  * it is not necessary to specify whether each subpath encloses a solid area or a hole
  * including very thin (a few pixels or less) filled paths, with which nanovg's antialiasing technique has some difficulties
* support for both even-odd and non-zero fill rules
* support for rendering text as paths
* signed distance field text rendering
* dashed strokes

# Build and run samples
* `nimble install sokol-nim`
* `nim -d:feature.nvg.sokol c -d:release -d:danger tests/tdemo.nim`
* or `nim -d:feature.nvg.sokol -d:gl c -d:release -d:danger tests/tdemo.nim`

# Some other libraries that were borrowed from:
* [stb_truetype.h](https://github.com/nothings/stb/blob/master/stb_truetype.h): almost all truetype code and SDF generation logic
* [opentype.js](https://github.com/opentypejs/opentype.js): glyph layering and color processing
* [freetype](https://github.com/freetype/freetype): text outline path generation logic
* [Skribidi](https://github.com/memononen/Skribidi/blob/main/src/skb_image_atlas.c): rectangle packing logic
* [fontstash](https://github.com/styluslabs/nanovgXC/blob/master/src/fontstash.h): heavily referenced
* [sdf_text_sample](https://github.com/suikki/sdf_text_sample): heavily referenced
* [nanovg_sokol.h](https://github.com/void256/nanovg_sokol.h): heavily referenced
* [pixie](https://github.com/treeform/pixie): some enums and user-friendly API style
* [msdfgen](https://github.com/Chlumsky/msdfgen): some unused modules are derived from it
* [cairo samples](https://www.cairographics.org/samples): some demos are sourced from here
* [MDN tutorial](https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Drawing_shapes): some demos are sourced from here

# My own modifications:
* Added support for [sokol](https://github.com/floooh/sokol-nim) backend
* Added support for instanced rendering
* `NVGwinding` has been removed, with only `NVGfillRule` supported
* ...

# Status
Currently, image rendering and gradients are not supported, and the project has not undergone sufficient testing.
