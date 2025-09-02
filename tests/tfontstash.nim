import nvg/fontstash
import nvg/altas

const FONT = staticRead("../msyh.ttf")

proc main() =
  var
    altas = Altas()
    fons = FonsStash()
    fontId = fons.loadFontFromMemory(cast[seq[byte]](FONT))
    text = "你好世界"

  let font = fons.getFont(fontId)

  for x, y, glyph in fons.arrange(font, text, 0, 0, 0, 18.4775391f, 0):
    echo x, y

    let
      cell = fons.addGlyphToAltas(glyph, altas)
      quad = fons.getQuad(glyph, x, y, altas, cell)

    echo quad

main()
