import nvg/context
import nvg/core

const
  FONT_sans = staticRead("../assets/vivoSans-Regular.ttf")
  FONT_emoji = staticRead("../assets/NotoColorEmoji-Regular.ttf")

var
  fontId_sans = default(FontId)
  fontId_emoji = default(FontId)

type
  Fonts* = enum
    Sans
    Emoji

proc addDefaultFonts*(ctx: Context) =
  fontId_sans = ctx.loadFontFromMemory("vivoSans", cast[seq[byte]](FONT_sans), FontFamilyDefault)
  fontId_emoji = ctx.loadFontFromMemory("NotoColorEmoji", cast[seq[byte]](
      FONT_emoji), FontFamilyEmoji)

proc getFontId*(id: Fonts): FontId =
  {.cast(noSideEffect).}:
    case id
    of Sans: fontId_sans
    of Emoji: fontId_emoji
