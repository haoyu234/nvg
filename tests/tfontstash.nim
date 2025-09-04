import nvg/atlas
import nvg/core
import nvg/fontstash
import nvg/params

const FONT = staticRead("../msyh.ttf")

proc createTextureImpl(ctx: pointer, typ: TextureType, w, h: int32,
        imageFlags: set[ImageFlags], data: pointer): ImageId =
  discard

proc markTextureDirtyImpl(ctx: pointer, imageId: ImageId, x, y, w, h: int32) =
  discard

proc deleteTextureImpl(ctx: pointer, imageId: ImageId) =
  discard

proc main() =
  let
    atlas = createAtlas(
      2048,
      2048,
      nil,
      BackendContextParams(
        createTextureImpl: createTextureImpl,
        markTextureDirtyImpl: markTextureDirtyImpl,
        deleteTextureImpl: deleteTextureImpl,
      )
    )

    fons = createFonsStash(TopLeftOrigin, atlas)
    fontId = fons.loadFontFromMemory(cast[seq[byte]](FONT))
    text = "你好世界"

  let
    font = fons.getFont(fontId)
    fontSize = 18.4775391f

  for x, y, glyphId in fons.arrange(font, text, 0, 0, LeftAlign,
      AlphabeticBaseline, fontSize, 0):
    let glyph = font.getGlyph(glyphId)
    if glyph.isNil:
      continue

    discard fons.getGlyphQuad(glyph, x, y, fontSize)

  for idx in 0 ..< 100:
    atlas.compact()

main()
