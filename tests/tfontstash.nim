import nvg/fontstash

const FONT = staticRead("../msyh.ttf")

proc main() =
  var
    fons = FonsStash()
    fontId = fons.loadFontFromMemory(cast[seq[byte]](FONT))
    text = "你好世界"

  let font = fons.getFontById(fontId)

  for x, y, glyph in fons.arrange(font, text, 0, 0, 0, 18.4775391f, 0):
    echo x, y

main()
