import nvg/fontstash
import nvg/atlas

const FONT = staticRead("../msyh.ttf")

proc main() =
  var
    atlas = Atlas()
    fons = FonsStash()
    fontId = fons.loadFontFromMemory(cast[seq[byte]](FONT))
    text = "你好世界"

  let font = fons.getFont(fontId)

  for x, y, glyph in fons.arrange(font, text, 0, 0, 0, 18.4775391f, 0):
    echo x, y

    let
      cell = fons.addGlyphToAtlas(glyph, atlas)
      quad = fons.getQuad(glyph, x, y, atlas, cell)

    echo quad

main()
