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
    imageId*: ImageId
    x1*, y1*, x2*, y2*: float32
    s1*, t1*, s2*, t2*: float32

  Glyph* = ref object
    fontId*: FontId
    glyphId*: GlyphId
    atlasGlyphBox: GlyphBox
    shape: seq[GlyphVertex]

  Font* = ref FontObj
  FontObj = object
    fontId*: FontId
    openType*: OpenTypeObj
    metrics*: FontMetrics
    glyphs: Table[GlyphId, Glyph]
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
  let n = min(int32(len(fons.fonts)), int32(fontId))

  for idx in countdown(n - 1, 0):
    let font = fons.fonts[idx]
    if font.fontId == fontId:
      result = font
      break

proc getGlyphId*(font: Font, unicodeCodepoint: uint32): GlyphId {.inline.} =
  font.openType.getGlyphId(unicodeCodepoint)

proc getGlyph*(font: Font, glyphId: GlyphId): Glyph =
  var glyph = default(Glyph)
  font.glyphs.withValue(glyphId, val):
    glyph = val[]

  if glyph.isNil:
    glyph = Glyph()
    glyph.fontId = font.fontId
    glyph.glyphId = glyphId

    font.glyphs[glyphId] = glyph
  glyph

proc getGlyphShape*(font: Font, glyph: Glyph): lent seq[GlyphVertex] {.inline.} =
  if glyph.shape.len <= 0:
    glyph.shape = font.openType.getGlyphShape(glyph.glyphId)
  glyph.shape

proc measureText*(
    fons: FonsStash, font: Font, text: openArray[char], size, spacing: float32
): float32 =
  var
    x = default(float32)
    prevGlyphId = default(GlyphId)
  let scale = font.getPixelHeightScale(size)

  for r in runes(text):
    let glyphId = font.getGlyphId(uint32(r))
    if glyphId.isNil:
      prevGlyphId = default(GlyphId)
      continue

    if not prevGlyphId.isNil:
      let adv = font.openType.getGlyphKernAdvance(prevGlyphId, glyphId)
      x = x + scale * float32(adv) + spacing

    prevGlyphId = glyphId

    let advance = font.openType.getGlyphAdvance(glyphId)
    x = x + scale * float32(advance)

  x

iterator arrange*(
    fons: FonsStash,
    font: Font,
    text: openArray[char],
    x, y: float32,
    textAlign: HorizontalAlignment,
    textBaseline: BaselineAlignment,
    size, spacing: float32,
): (float32, float32, GlyphId) =
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
    let glyphId = font.getGlyphId(uint32(r))
    if glyphId.isNil:
      prevGlyphId = default(GlyphId)
      continue

    if not prevGlyphId.isNil:
      let adv = font.openType.getGlyphKernAdvance(prevGlyphId, glyphId)
      x = x + scale * float32(adv) + spacing

    prevGlyphId = glyphId

    yield (x, y, glyphId)

    let advance = font.openType.getGlyphAdvance(glyphId)
    x = x + scale * float32(advance)

proc updateCell(fons: FonsStash, glyph: Glyph): AtlasCell =
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

    let sdf = font.openType.getGlyphSDF(glyph.glyphId, font.atlasPixelScale,
        pad, 127, 32)
    if sdf.data.len > 0:
      fons.atlas.updateCell(result, sdf.w, sdf.h, sdf.w, sdf.data[0].addr)

proc getGlyphQuad*(fons: FonsStash, glyph: Glyph, x, y,
    size: float32): Quad =
  let cell = fons.updateCell(glyph)
  if cell.isNil:
    return

  let
    pad = fons.atlasPadding + 1
    w = glyph.atlasGlyphBox.x2 - glyph.atlasGlyphBox.x1
    h = glyph.atlasGlyphBox.y2 - glyph.atlasGlyphBox.y1

  let
    xoff = float32(glyph.atlasGlyphBox.x1 - pad)
    yoff = float32(glyph.atlasGlyphBox.y1 - pad)

    x1 = float32(cell.x)
    y1 = float32(cell.y)
    x2 = float32(cell.x + w + pad * 2)
    y2 = float32(cell.y + h + pad * 2)

    scale = size / float32(fons.atlasFontSize)

  result.imageId = cell.imageId

  result.x1 = x + scale * xoff
  result.y1 = y + scale * yoff * fons.signY
  result.x2 = result.x1 + scale * float32(x2 - x1)
  result.y2 = result.y1 + scale * float32(y2 - y1) * fons.signY

  result.s1 = x1 * cell.scaleX
  result.t1 = y1 * cell.scaleY
  result.s2 = x2 * cell.scaleX
  result.t2 = y2 * cell.scaleY

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
  result.atlasPadding = 8
  result.atlasFontSize = 48 * 2
