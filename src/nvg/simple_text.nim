import ./atlas
import ./backend
import ./core
import ./sdf
import ./text
import ./truetype

import std/unicode

type
  Glyph = object
    fontId: FontId
    glyphId: GlyphId
    offset: Vec2

  Font = ref object
    fontId: FontId
    fontFamily: FontFamily
    trueType: TrueType
    metrics: FontMetrics
    storage: seq[byte]

  SimpleFontCollection* = ref object of FontCollection
    fonts: seq[Font]

  SimpleTextBlob* = ref object of TextBlob
    fontCollection: SimpleFontCollection
    textLayoutContext: SimpleTextLayoutContext
    size: Vec2
    glyphs: seq[Glyph]
    textAttribs: TextAttribs

  SimpleTextBlobCache* = ref object of TextBlobCache
  SimpleTextLayoutContext* = ref object of TextLayoutContext
  SimpleTextRenderContext* = ref object of TextRenderContext
    atlas: Atlas
    atlasPadding: int32
    atlasFontSize: int32
    backendContext: BackendContext

proc getPixelHeightScale(font: Font, size: float32): float32 =
  size / float32(font.metrics.ascender - font.metrics.descender)

proc createSimpleFontCollection*(): SimpleFontCollection =
  result = SimpleFontCollection()

method loadFromMemory*(fontCollection: SimpleFontCollection, name: string,
    buffer: seq[byte], fontFamily: FontFamily): FontId =
  let
    p = Font()
    nextId = uint32(succ(fontCollection.fonts.len))

  p.storage = buffer
  p.trueType = parseTrueType(p.storage, 0)
  p.metrics = p.trueType.getFontMetrics()
  p.fontId = FontId(id: nextId)

  fontCollection.fonts.add(p)

  p.fontId

proc getFontByRune(fontCollection: SimpleFontCollection, rune: Rune): Font =
  for font in fontCollection.fonts:
    let glyphId = font.trueType.getGlyphId(uint32(rune))
    if not glyphId.isNil:
      result = font
      return

proc getFontById(fontCollection: SimpleFontCollection, fontId: FontId): Font =
  let n = min(int32(len(fontCollection.fonts)), int32(fontId.id))

  for idx in countdown(n - 1, 0):
    let font = fontCollection.fonts[idx]
    if font.fontId == fontId:
      result = font
      return

proc createSimpleTextLayoutContext*(): SimpleTextLayoutContext =
  result = SimpleTextLayoutContext()

proc createSimpleTextBlobImpl(textLayoutContext: SimpleTextLayoutContext,
    textBlobCache: SimpleTextBlobCache, fontCollection: SimpleFontCollection,
    textAttribs: TextAttribs, text: openArray[char]): SimpleTextBlob =
  var
    x = float32(0)
    y = float32(0)
    offset = float32(0)
    prevFont = default(Font)
    prevGlyphId = default(GlyphId)
    glyphs = newSeqOfCap[Glyph](text.len)
    scale = default(float32)

  for r in runes(text):
    let font = fontCollection.getFontByRune(r)
    if font.isNil:
      prevGlyphId = default(GlyphId)
      continue

    let glyphId = font.trueType.getGlyphId(uint32(r))
    if glyphId.isNil:
      prevGlyphId = default(GlyphId)
      continue

    if prevFont != font:
      prevFont = font
      scale = font.getPixelHeightScale(textAttribs.fontSize)

    if not prevGlyphId.isNil:
      let adv = font.trueType.getGlyphKernAdvance(prevGlyphId, glyphId)
      x = x + scale * float32(adv) + textAttribs.letterSpacing

    let
      h = float32(font.metrics.ascender + font.metrics.lineGap -
          font.metrics.descender)
      ascender = float32(font.metrics.ascender + font.metrics.lineGap) / h
      descender = float32(font.metrics.descender) / h

    # y align
    case textAttribs.textBaseline
    of TopBaseline:
      y = ascender * textAttribs.fontSize
    of MiddleBaseline:
      y = (ascender + descender) / float32(2) *
          textAttribs.fontSize
    of BottomBaseline:
      y = descender * textAttribs.fontSize
    of AlphabeticBaseline:
      discard

    var
      glyph = default(Glyph)
    glyph.fontId = font.fontId
    glyph.glyphId = glyphId
    glyph.offset[0] = x
    glyph.offset[1] = y
    glyphs.add(glyph)

    prevGlyphId = glyphId

    let advance = font.trueType.getGlyphAdvance(glyphId)
    x = x + scale * float32(advance)

  # x align
  case textAttribs.textAlign
  of LeftAlign:
    offset = 0
  of RightAlign:
    offset = - x
  of CenterAlign:
    offset = - x * 0.5

  if offset != 0:
    for idx in 0 ..< glyphs.len:
      glyphs[idx].offset[0] += offset

  SimpleTextBlob(
    fontCollection: fontCollection,
    textLayoutContext: textLayoutContext,
    size: vec2(x, 0),
    glyphs: glyphs,
    textAttribs: textAttribs,
  )

method createTextBlob(textLayoutContext: SimpleTextLayoutContext,
    fontCollection: FontCollection, textAttribs: TextAttribs, text: openArray[
    char]): TextBlob =
  let fontCollection = SimpleFontCollection(fontCollection)

  createSimpleTextBlobImpl(textLayoutContext, nil, fontCollection,
      textAttribs, text)

proc createSimpleTextBlobCache*(textRenderContext: SimpleTextLayoutContext): SimpleTextBlobCache =
  result = SimpleTextBlobCache()

proc createSimpleTextRenderContext*(backendContext: BackendContext): SimpleTextRenderContext =
  result = SimpleTextRenderContext()
  result.atlasPadding = 1
  result.atlasFontSize = 48
  result.backendContext = backendContext
  result.atlas = newAtlas(1024, 1024, backendContext)

method fillText(textRenderContext: SimpleTextRenderContext,
    textLayoutContext: TextLayoutContext, textBlobCache: TextBlobCache,
    fontCollection: FontCollection, textAttribs: TextAttribs, text: openArray[
    char], pos: Vec2, transform: Mat2d) =
  let fontCollection = SimpleFontCollection(fontCollection)
  let textBlob = textLayoutContext.createTextBlob(fontCollection, textAttribs, text)
  textRenderContext.fillTextBlob(textBlob, pos, transform)

proc updateCell(textRenderContext: SimpleTextRenderContext,
    fontCollection: SimpleFontCollection, glyph: Glyph): tuple[cell: AtlasCell,
        glyphBox: GlyphBox] =
  let font = fontCollection.getFontById(glyph.fontId)
  if font.isNil:
    return

  let
    pad = textRenderContext.atlasPadding + 1
    fontId32 = cast[uint32](glyph.fontId)
    glyphId32 = cast[uint32](glyph.glyphId)
    id = fontId32 or (glyphId32 shl 16)
    scale = font.getPixelHeightScale(float32(textRenderContext.atlasFontSize))

  if textRenderContext.atlas.hasCell(id):
    result.cell = textRenderContext.atlas.getCell(id)
  else:
    let sdf = font.trueType.generateGlyphSDF(
      glyph.glyphId,
      scale,
      pad,
      127,
      16,
    )

    if sdf.data.len <= 0:
      return

    result.cell = textRenderContext.atlas.allocCell(id, sdf.w, sdf.h, PixelFormatA8)
    if result.cell.isNil:
      return

    textRenderContext.atlas.updateCell(result.cell, sdf.w, sdf.h, sdf.w,
        sdf.data[0].addr)

  result.glyphBox = font.trueType.getGlyphBitmapBox(glyph.glyphId, scale, scale, 0, 0)

proc toGlyphQuad(textRenderContext: SimpleTextRenderContext,
    fontCollection: SimpleFontCollection, glyph: Glyph, pos: Vec2,
    textAttribs: TextAttribs): GlyphQuad =
  let (cell, glyphBox) = textRenderContext.updateCell(fontCollection, glyph)
  if cell.isNil:
    return

  let
    pad = textRenderContext.atlasPadding + 1
    w = glyphBox.xMax - glyphBox.xMin
    h = glyphBox.yMax - glyphBox.yMin

  const signY = float32(1)
  let
    xoff = float32(glyphBox.xMin - pad)
    yoff = float32(glyphBox.yMin - pad)

    x1 = float32(cell.x + 1)
    y1 = float32(cell.y + 1)
    x2 = float32(cell.x + w + pad * 2 - 1)
    y2 = float32(cell.y + h + pad * 2 - 1)

    scale = textAttribs.fontSize / float32(textRenderContext.atlasFontSize)

  result.isSdf = true
  result.imageId = cell.imageId
  result.color = textAttribs.fontColor

  result.x1 = glyph.offset[0] + pos[0] + scale * xoff
  result.y1 = glyph.offset[1] + pos[1] + scale * yoff * signY
  result.x2 = result.x1 + scale * float32(x2 - x1)
  result.y2 = result.y1 + scale * float32(y2 - y1) * signY

  result.s1 = x1 * cell.scaleX
  result.t1 = y1 * cell.scaleY
  result.s2 = x2 * cell.scaleX
  result.t2 = y2 * cell.scaleY

method fillTextBlob(textRenderContext: SimpleTextRenderContext,
    textBlob: TextBlob, pos: Vec2, transform: Mat2d) =
  let textBlob = SimpleTextBlob(textBlob)

  var
    glyphQuads = newSeqOfCap[GlyphQuad](textBlob.glyphs.len)
  for glyph in textBlob.glyphs:
    glyphQuads.add(textRenderContext.toGlyphQuad(textBlob.fontCollection, glyph,
        pos, textBlob.textAttribs))
  textRenderContext.backendContext.drawGlyphQuads(Paint(), transform,
      glyphQuads, SourceOverOperation)

method flush(textRenderContext: SimpleTextRenderContext) =
  textRenderContext.atlas.compact()
