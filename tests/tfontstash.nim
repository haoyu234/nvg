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
    atlas = createAtlas(nil, 
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

  for x, y, glyph in fons.arrange(font, text, 0, 0, default(
      HorizontalAlignment), default(BaselineAlignment), fontSize, 0):
    discard fons.getGlyphQuad(glyph, x, y, fontSize)

  for idx in 0 ..< 100:
    atlas.compact()

main()
