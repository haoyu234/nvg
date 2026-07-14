import nvg

const
  FONT_sans = staticRead("../assets/vivoSans-Regular.ttf")
  FONT_emoji = staticRead("../assets/NotoColorEmoji-Regular.ttf")
  FONT_devanagari = staticRead("../assets/NotoSansDevanagari-Regular.ttf")

  FONT_plex_regular = staticRead("../assets/IBMPlexSans-Regular.ttf")
  FONT_plex_bold = staticRead("../assets/IBMPlexSans-Bold.ttf")
  FONT_plex_italic = staticRead("../assets/IBMPlexSans-Italic.ttf")
  FONT_plex_arabic = staticRead("../assets/IBMPlexSansArabic-Regular.ttf")
  FONT_plex_devanagari = staticRead("../assets/IBMPlexSansDevanagari-Regular.ttf")
  FONT_plex_jp = staticRead("../assets/IBMPlexSansJP-Regular.ttf")

let
  default_fonts = createFontCollection()
  plex_fonts = createFontCollection()

proc add(fonts: FontCollection, bytes: static[string], family: FontFamily) =
  let
    data = cast[seq[byte]](bytes)
    font = createFontFromMemory(FontId(id: uint32(fonts.len + 1)), family, data)
  fonts.add(font)

proc getDefaultFontCollection*(): FontCollection =
  if default_fonts.len <= 0:
    default_fonts.add(FONT_sans, Default)
    default_fonts.add(FONT_emoji, Default)
    default_fonts.add(FONT_devanagari, Default)
  default_fonts

proc getPlexFontCollection*(): FontCollection =
  if plex_fonts.len <= 0:
    plex_fonts.add(FONT_plex_regular, Default)
    plex_fonts.add(FONT_plex_bold, Default)

    plex_fonts.add(FONT_plex_italic, Default)
    plex_fonts.add(FONT_plex_arabic, Default)
    plex_fonts.add(FONT_plex_devanagari, Default)
    plex_fonts.add(FONT_plex_jp, Default)
    plex_fonts.add(FONT_emoji, Emoji)
  plex_fonts
