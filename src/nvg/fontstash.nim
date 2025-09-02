import ./altas
import ./opentype

import std/tables
import std/unicode

const
  FONS_ZERO_TOP_LEFT* = uint32(1 shl 0)
  FONS_ZERO_BOTTOM_LEFT* = uint32(1 shl 1)

  FONS_ALIGN_LEFT* = uint32(1 shl 0)
  FONS_ALIGN_CENTER* = uint32(1 shl 1)
  FONS_ALIGN_RIGHT* = uint32(1 shl 2)
  FONS_ALIGN_TOP* = uint32(1 shl 3)
  FONS_ALIGN_MIDDLE* = uint32(1 shl 4)
  FONS_ALIGN_BOTTOM* = uint32(1 shl 5)
  FONS_ALIGN_BASELINE* = uint32(1 shl 6)

type
  FonsFontId* = distinct uint32

  FonsQuad* = object
    x1*, y1*, x2*, y2*: float32
    s1*, t1*, s2*, t2*: float32

  FonsGlyph* = object
    fontId*: FonsFontId
    unicodeCodepoint*: uint32
    glyphId*: GlyphId
    advance: int32
    glyphBox48: GlyphBox
    shape: seq[GlyphVertex]

  FonsFont* = ref FonsFontObj
  FonsFontObj = object
    fontId: FonsFontId
    openType*: OpenTypeObj
    metrics*: FontMetrics
    glyphs: Table[uint32, FonsGlyph]
    sdfPixelScale: float32
    storage: seq[byte]

  FonsStash* = ref FonsStashObj
  FonsStashObj = object
    flags: uint32 = FONS_ZERO_TOP_LEFT
    sdfPadding: uint32
    fonts: seq[FonsFont]

proc isNil*(fontId: FonsFontId): bool {.inline.} =
  uint32(fontId) == 0

proc getPixelHeightScale*(font: FonsFont, size: float32): float32 =
  size / float32(font.metrics.ascender - font.metrics.descender)

proc loadFontFromMemory*(fons: FonsStash, data: sink seq[byte]): FonsFontId =
  let
    p = FonsFont()
    fontId = FonsFontId(succ(fons.fonts.len))

  p.storage = move data
  p.openType = parseOpenType(p.storage, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId
  p.sdfPixelScale = p.getPixelHeightScale(96)

  fons.fonts.add(p)

  fontId

proc loadFontFromMemory*(fons: FonsStash, data: openArray[byte]): FonsFontId =
  let
    p = FonsFont()
    fontId = FonsFontId(succ(fons.fonts.len))

  p.openType = parseOpenType(data, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId
  p.sdfPixelScale = p.getPixelHeightScale(96)

  fons.fonts.add(p)

  fontId

proc getFont*(fons: FonsStash, fontId: FonsFontId): FonsFont =
  let n = min(len(fons.fonts), int(fontId))

  for idx in 0 ..< n:
    let p = fons.fonts[idx]
    if uint32(p.fontId) == uint32(fontId):
      return p

proc getGlyph*(
    fons: FonsStash, font: FonsFont, unicodeCodepoint: uint32
): ptr FonsGlyph =
  if not font.glyphs.contains(unicodeCodepoint):
    let glyphId = font.openType.getGlyphId(unicodeCodepoint)
    if glyphId.isNil:
      return

    var glyph = default(FonsGlyph)
    glyph.fontId = font.fontId
    glyph.unicodeCodepoint = unicodeCodepoint
    glyph.glyphId = glyphId
    glyph.advance = font.openType.getGlyphAdvance(glyphId)
    font.glyphs[unicodeCodepoint] = glyph

  font.glyphs[unicodeCodepoint].addr

proc measureText*(
    fons: FonsStash, font: FonsFont, text: openArray[char], size,
        spacing: float32
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
    font: FonsFont,
    text: openArray[char],
    x, y: float32,
    align: uint32,
    size, spacing: float32,
): (float32, float32, ptr FonsGlyph) =
  var
    x = x
    y = y
    prevGlyphId = default(GlyphId)

  # x align
  if (align and FONS_ALIGN_LEFT) > 0:
    discard
  elif (align and FONS_ALIGN_RIGHT) > 0:
    x = x - measureText(fons, font, text, size, spacing)
  elif (align and FONS_ALIGN_CENTER) > 0:
    x = x - measureText(fons, font, text, size, spacing) / 2

  let
    h = float32(font.metrics.ascender + font.metrics.lineGap -
        font.metrics.descender)
    ascender = float32(font.metrics.ascender + font.metrics.lineGap) / h
    descender = float32(font.metrics.descender) / h
    scale = font.getPixelHeightScale(size)
    sign =
      if (fons.flags and FONS_ZERO_TOP_LEFT) > 0:
        float32(1)
      else:
        float32(-1)

  # y align
  if (align and FONS_ALIGN_TOP) > 0:
    y = y + sign * ascender * size
  elif (align and FONS_ALIGN_MIDDLE) > 0:
    y = y + sign * (ascender + descender) / float32(2) * size
  elif (align and FONS_ALIGN_BOTTOM) > 0:
    y = y + sign * descender * size

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

proc getGlyphShape*(fons: FonsStash, glyph: ptr FonsGlyph): lent seq[GlyphVertex] =
  if glyph.shape.len <= 0:
    let font = fons.getFont(glyph.fontId)
    if font.isNil:
      return

    glyph.shape = font.openType.getGlyphShape(glyph.glyphId)
  glyph.shape

proc addGlyphToAltas*(fons: FonsStash, glyph: ptr FonsGlyph,
    atlas: Altas): AltasCell =
  let font = fons.getFont(glyph.fontId)
  if font.isNil:
    return

  if glyph.glyphBox48.x2 <= 0 and glyph.glyphBox48.y2 <= 0:
    glyph.glyphBox48 = font.openType.getGlyphBox(glyph.glyphId,
        font.sdfPixelScale, font.sdfPixelScale, 0, 0)

  let
    pad = fons.sdfPadding + 1
    w = glyph.glyphBox48.x2 - glyph.glyphBox48.x1 + int32(2 * pad)
    h = glyph.glyphBox48.y2 - glyph.glyphBox48.y1 + int32(2 * pad)

  let
    cell = atlas.allocCell(w, h)
    sdf = font.openType.getGlyphSDF(glyph.glyphId, font.sdfPixelScale, 0, 127, 32)

  atlas.updateCell(cell, sdf.w, sdf.h, sdf.w, sdf.data)

  cell

proc getGlyphQuad*(fons: FonsStash, glyph: ptr FonsGlyph, x, y: float32,
    atlas: Altas, cell: AltasCell, size, blur: float32): FonsQuad =
  let
    pad = int32(fons.sdfPadding + 1)
    expand = min(blur, float32(fons.sdfPadding)) + 1
    xoff = float32(glyph.glyphBox48.x1) - expand
    yoff = float32(glyph.glyphBox48.y1) - expand

    w = glyph.glyphBox48.x2 - glyph.glyphBox48.x1
    h = glyph.glyphBox48.y2 - glyph.glyphBox48.y1

    x1 = float32(cell.x + pad) - expand
    y1 = float32(cell.y + pad) - expand
    x2 = float32(cell.x + pad + w) + expand
    y2 = float32(cell.x + pad + h) + expand

    sign =
      if (fons.flags and FONS_ZERO_TOP_LEFT) > 0:
        float32(1)
      else:
        float32(-1)

    scale = size / float32(96)

  result.x1 = x + scale * xoff
  result.y1 = y + scale * yoff * sign
  result.x2 = result.x1 + scale * float32(x2 - x1)
  result.y2 = result.y1 + scale * float32(y2 - y1) * sign

  result.s1 = x1 / float32(atlas.width)
  result.t1 = y1 / float32(atlas.height)
  result.s2 = x2 / float32(atlas.width)
  result.t2 = y2 / float32(atlas.height)
