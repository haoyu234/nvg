import nvg/context
import nvg/core

const FONT = staticRead("../msyh.ttf")

var fontId = default(FontId)

proc getDefaultFont*(ctx: Context): FontId =
  if fontId.isNil:
    fontId = ctx.loadFontFromMemory(cast[seq[byte]](FONT))
  fontId
