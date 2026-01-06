import nvg/context
import nvg/core

const
  FONT = staticRead("../assets/vivoSans-Regular.ttf")
  FONT_mono = staticRead("../assets/MapleMono.ttf")
  FONT_emoji = staticRead("../assets/OpenMoji-color-glyf_colr_0.ttf")

var
  fontId = default(FontId)
  fontId_mono = default(FontId)
  fontId_emoji = default(FontId)

proc getDefaultFont*(ctx: Context): FontId =
  # TODO:
  # if fontId.isNil:
  #   fontId = ctx.loadFontFromMemory(cast[seq[byte]](FONT))
  fontId

proc getMonoFont*(ctx: Context): FontId =
  # TODO:
  # if fontId_mono.isNil:
  #   fontId_mono = ctx.loadFontFromMemory(cast[seq[byte]](FONT_mono))
  fontId_mono

proc getEmojiFont*(ctx: Context): FontId =
  # TODO:
  # if fontId_emoji.isNil:
  #   fontId_emoji = ctx.loadFontFromMemory(cast[seq[byte]](FONT_emoji))
  fontId_emoji
