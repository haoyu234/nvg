import ./atlas
import ./core
import ./opentype
import ./params

import std/tables
import std/unicode

type
  Origin* = enum
    TopLeftOrigin
    BottomLeftOrigin

  Quad* = object
    x1*, y1*, x2*, y2*: float32
    s1*, t1*, s2*, t2*: float32

  Glyph* = object
    fontId*: FontId
    unicodeCodepoint*: uint32
    glyphId*: GlyphId
    advance: int32
    atlasGlyphBox*: GlyphBox
    shape: seq[GlyphVertex]

  Font* = ref FontObj
  FontObj = object
    fontId: FontId
    openType*: OpenTypeObj
    metrics*: FontMetrics
    glyphs: Table[uint32, Glyph]
    atlasPixelScale: float32
    storage: seq[byte]

  FonsStash* = ref FonsStashObj
  FonsStashObj = object
    origin*: Origin
    signY: float32
    atlasFontSize*: int32
    atlasPadding*: int32
    fonts: seq[Font]
    atlas: Atlas

proc getPixelHeightScale*(font: Font, size: float32): float32 =
  size / float32(font.metrics.ascender - font.metrics.descender)

proc loadFontFromMemory*(fons: FonsStash, data: sink seq[byte]): FontId =
  let
    p = Font()
    fontId = cast[FontId](succ(fons.fonts.len))

  p.storage = move data
  p.openType = parseOpenType(p.storage, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId
  p.atlasPixelScale = p.getPixelHeightScale(float32(fons.atlasFontSize))

  fons.fonts.add(p)

  fontId

proc loadFontFromMemory*(fons: FonsStash, data: openArray[byte]): FontId =
  let
    p = Font()
    fontId = cast[FontId](succ(fons.fonts.len))

  p.openType = parseOpenType(data, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId
  p.atlasPixelScale = p.getPixelHeightScale(float32(fons.atlasFontSize))

  fons.fonts.add(p)

  fontId

proc getFont*(fons: FonsStash, fontId: FontId): Font =
  let n = min(len(fons.fonts), int(fontId))

  for idx in 0 ..< n:
    let p = fons.fonts[idx]
    if uint32(p.fontId) == uint32(fontId):
      return p

proc getGlyph*(
    fons: FonsStash, font: Font, unicodeCodepoint: uint32
): ptr Glyph =
  if not font.glyphs.contains(unicodeCodepoint):
    let glyphId = font.openType.getGlyphId(unicodeCodepoint)
    if glyphId.isNil:
      return

    var glyph = default(Glyph)
    glyph.fontId = font.fontId
    glyph.unicodeCodepoint = unicodeCodepoint
    glyph.glyphId = glyphId
    glyph.advance = font.openType.getGlyphAdvance(glyphId)
    font.glyphs[unicodeCodepoint] = glyph

  font.glyphs[unicodeCodepoint].addr

proc measureText*(
    fons: FonsStash, font: Font, text: openArray[char], size, spacing: float32
): float32 =
  var prevGlyphId = default(GlyphId)
  let scale = font.getPixelHeightScale(size)

  for r in runes(text):
    let glyph = fons.getGlyph(font, uint32(r))
    if glyph.isNil:
      prevGlyphId = default(GlyphId)
      continue

    if not prevGlyphId.isNil:
      let adv = font.openType.getGlyphKernAdvance(prevGlyphId, glyph.glyphId)
      result = result + scale * float32(adv) + spacing
    prevGlyphId = glyph.glyphId

    result = result + scale * float32(glyph.advance)

iterator arrange*(
    fons: FonsStash,
    font: Font,
    text: openArray[char],
    x, y: float32,
    textAlign: HorizontalAlignment,
    textBaseline: BaselineAlignment,
    size, spacing: float32,
): (float32, float32, ptr Glyph) =
  var
    x = x
    y = y
    prevGlyphId = default(GlyphId)

  # x align
  if textAlign == LeftAlign:
    discard
  elif textAlign == RightAlign:
    x = x - measureText(fons, font, text, size, spacing)
  elif textAlign == CenterAlign:
    x = x - measureText(fons, font, text, size, spacing) / 2

  let
    h = float32(font.metrics.ascender + font.metrics.lineGap -
        font.metrics.descender)
    ascender = float32(font.metrics.ascender + font.metrics.lineGap) / h
    descender = float32(font.metrics.descender) / h
    scale = font.getPixelHeightScale(size)

  # y align
  if textBaseline == TopBaseline:
    y = y + fons.signY * ascender * size
  elif textBaseline == MiddleBaseline:
    y = y + fons.signY * (ascender + descender) / float32(2) * size
  elif textBaseline == BottomBaseline:
    y = y + fons.signY * descender * size

  for r in runes(text):
    let glyph = fons.getGlyph(font, uint32(r))
    if glyph.isNil:
      prevGlyphId = default(GlyphId)
      continue

    if not prevGlyphId.isNil:
      let adv = font.openType.getGlyphKernAdvance(prevGlyphId, glyph.glyphId)
      x = x + scale * float32(adv) + spacing
    prevGlyphId = glyph.glyphId

    yield (x, y, glyph)

    x = x + scale * float32(glyph.advance)

proc getGlyphShape*(fons: FonsStash, glyph: ptr Glyph): lent seq[GlyphVertex] =
  if glyph.shape.len <= 0:
    let font = fons.getFont(glyph.fontId)
    if font.isNil:
      return

    glyph.shape = font.openType.getGlyphShape(glyph.glyphId)
  glyph.shape

proc updateCell(fons: FonsStash, glyph: ptr Glyph): AtlasCell =
  let font = fons.getFont(glyph.fontId)
  if font.isNil:
    return

  if glyph.atlasGlyphBox.x2 <= 0 and glyph.atlasGlyphBox.y2 <= 0:
    glyph.atlasGlyphBox = font.openType.getGlyphBox(glyph.glyphId,
        font.atlasPixelScale, font.atlasPixelScale, 0, 0)

  let
    pad = fons.atlasPadding + 1
    w = glyph.atlasGlyphBox.x2 - glyph.atlasGlyphBox.x1
    h = glyph.atlasGlyphBox.y2 - glyph.atlasGlyphBox.y1

  let
    fontId32 = cast[uint32](glyph.fontId)
    glyphId32 = cast[uint32](glyph.glyphId)
    id = fontId32 or (glyphId32 shl 16)

  if fons.atlas.hasCell(id):
    result = fons.atlas.getCell(id)
  else:
    let
      padw = w + 2 * pad
      padh = h + 2 * pad

    result = fons.atlas.allocCell(id, padw, padh, TextureAlpha)
    if result.isNil:
      return

    let atlas = font.openType.getGlyphSDF(glyph.glyphId, font.atlasPixelScale, 0,
        127, 32)
    fons.atlas.updateCell(result, atlas.w, atlas.h, atlas.w, atlas.data[0].addr)

proc getGlyphQuad*(fons: FonsStash, glyph: ptr Glyph, x, y, size: float32): (
    ImageId, Quad) =
  let cell = fons.updateCell(glyph)
  if cell.isNil:
    return

  let
    pad = fons.atlasPadding + 1
    w = glyph.atlasGlyphBox.x2 - glyph.atlasGlyphBox.x1
    h = glyph.atlasGlyphBox.y2 - glyph.atlasGlyphBox.y1

  let
    blur = default(float32)
    expand = min(blur, float32(fons.atlasPadding)) + 1
    xoff = float32(glyph.atlasGlyphBox.x1) - expand
    yoff = float32(glyph.atlasGlyphBox.y1) - expand

    x1 = float32(cell.x + pad) - expand
    y1 = float32(cell.y + pad) - expand
    x2 = float32(cell.x + pad + w) + expand
    y2 = float32(cell.y + pad + h) + expand

    scale = size / float32(fons.atlasFontSize)

  result[0] = cell.imageId

  result[1].x1 = x + scale * xoff
  result[1].y1 = y + scale * yoff * fons.signY
  result[1].x2 = result[1].x1 + scale * float32(x2 - x1)
  result[1].y2 = result[1].y1 + scale * float32(y2 - y1) * fons.signY

  result[1].s1 = x1 * cell.scaleX
  result[1].t1 = y1 * cell.scaleY
  result[1].s2 = x2 * cell.scaleX
  result[1].t2 = y2 * cell.scaleY

proc createFonsStash*(origin: Origin, atlas: Atlas): FonsStash =
  result = FonsStash()
  result.atlas = atlas
  result.origin = origin

  case origin
  of TopLeftOrigin:
    result.signY = float32(1)

  of BottomLeftOrigin:
    result.signY = float32(-1)

  # SDF
  result.atlasPadding = 1
  result.atlasFontSize = 48 * 2
