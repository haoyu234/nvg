import nvg/path
import nvg/truetype

import std/cmdline
import std/strutils

import ./utils

proc main() =
  if paramCount() < 1:
    return

  let 
    fontData = readFile(paramStr(1))
    font = parseTrueType(cast[seq[byte]](fontData), 0)
  
  if paramCount() < 2:
    echo font.numGlyphs
    return

  let
    glyphId = parseInt(paramStr(2))

  # let
  #   b1 = font.getGlyphBox(GlyphId(glyphId))
  #   b2 = font.getGlyphBox(GlyphId(glyphId), 1, 1, 0, 0)
  
  # echo b1
  # echo b2
  # quit(0)

  if glyphId >= int32(font.numGlyphs):
    return
  elif glyphId > 0:
    var count = 1
    if paramCount() >= 3:
      count = parseInt(paramStr(3))

    for idx in 0 ..< count:
      let nid = glyphId + idx
      if nid < int32(font.numGlyphs):
        echo "glyphId: ", nid
        let path = font.getGlyphPath(GlyphId(nid))
        if not path.empty:
          path.dumpPath()
  else:
    for idx in 1 ..< font.numGlyphs:
      echo "glyphId: ", idx
      let path = font.getGlyphPath(GlyphId(idx))
      if not path.empty:
        path.dumpPath()

main()
