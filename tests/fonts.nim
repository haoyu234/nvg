import nvg/context
import nvg/core

const
  FONT = staticRead("../vivoSans-Regular.ttf")
  FONT_emoji = staticRead("../OpenMoji-color-glyf_colr_0.ttf")

var
  fontId = default(FontId)
  fontId_emoji = default(FontId)

proc getDefaultFont*(ctx: Context): FontId =
  if fontId.isNil:
    fontId = ctx.loadFontFromMemory(cast[seq[byte]](FONT))
  fontId

proc getEmojiFont*(ctx: Context): FontId =
  if fontId_emoji.isNil:
    fontId_emoji = ctx.loadFontFromMemory(cast[seq[byte]](FONT_emoji))
  fontId_emoji
