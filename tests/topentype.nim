import nvg/opentype

import std/unicode

const FONT = staticRead("../msyh.ttf")

proc main() =
  let
    runes = "你好世界".toRunes
    scale = 0.011839f

  let font = parseOpenType(cast[seq[byte]](FONT), 0)

  for r in runes:
    let glyphId = font.getGlyphId(uint32(r))
    let sdf = font.getGlyphSDF(glyphId, scale, 4, 127, 32)

    discard sdf

main()
