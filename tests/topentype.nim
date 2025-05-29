import nvg/opentype

import std/unicode
import std/monotimes
import std/times

const FONT = staticRead("../msyh.ttf")

proc main() =
  let
    runes = "你好世界".toRunes
    scale = 0.011839f

  let font = parseOpenType(cast[seq[byte]](FONT), 0)

  let t1 = getMonoTime()

  for _ in 0 ..< 1000:
    for r in runes:
      let glyphId = font.getGlyphId(uint32(r))
      let sdf = font.getGlyphSDF(glyphId, scale, 4, 127, 32)

  let t2 = getMonoTime()

  echo (t2 - t1).inSeconds

main()
