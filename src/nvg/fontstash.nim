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

  FonsGlyphObj* = object
    fontId*: FonsFontId
    unicodeCodepoint*: uint32
    glyphId*: GlyphId
    advance: int32
    shape: seq[GlyphVertex]

  FonsFontObj = object
    fontId: FonsFontId
    openType*: OpenTypeObj
    metrics*: FontMetrics
    glyphs: Table[uint32, FonsGlyphObj]
    data: seq[byte]

  FonsStashObj* = object
    flags: uint32 = FONS_ZERO_TOP_LEFT
    fonts: seq[ptr FonsFontObj]

proc loadFontFromMemory*(fons: var FonsStashObj, data: sink seq[byte]): FonsFontId =
  let
    p = create(FonsFontObj)
    fontId = FonsFontId(succ(fons.fonts.len))

  p.data = move data
  p.openType = parseOpenType(p.data, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId

  fons.fonts.add(p)

  fontId

proc loadFontFromMemory*(fons: var FonsStashObj, data: openArray[byte]): FonsFontId =
  let
    p = create(FonsFontObj)
    fontId = FonsFontId(succ(fons.fonts.len))

  p.openType = parseOpenType(p.data, 0)
  p.metrics = p.openType.getFontMetrics()
  p.fontId = fontId

  fons.fonts.add(p)

  fontId

proc getFontById*(fons: var FonsStashObj, fontId: FonsFontId): ptr FonsFontObj =
  let n = min(len(fons.fonts), int(fontId))

  for idx in 0 ..< n:
    let p = fons.fonts[idx]
    if uint32(p.fontId) == uint32(fontId):
      return p

proc getGlyph*(
    fons: var FonsStashObj, font: ptr FonsFontObj, unicodeCodepoint: uint32
): ptr FonsGlyphObj =
  if not font.glyphs.contains(unicodeCodepoint):
    let glyphId = font.openType.getGlyphId(unicodeCodepoint)
    if glyphId.isNil:
      return

    var glyph = default(FonsGlyphObj)
    glyph.fontId = font.fontId
    glyph.unicodeCodepoint = unicodeCodepoint
    glyph.glyphId = glyphId
    glyph.advance = font.openType.getGlyphAdvance(glyphId)
    font.glyphs[unicodeCodepoint] = glyph

  font.glyphs[unicodeCodepoint].addr

proc measureText*(
    fons: var FonsStashObj,
    font: ptr FonsFontObj,
    text: openArray[char],
    size, spacing: float32,
): float32 =
  var prevGlyphId = default(GlyphId)
  let scale = size / float32(font.metrics.ascender - font.metrics.descender)

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
    fons: var FonsStashObj,
    font: ptr FonsFontObj,
    text: openArray[char],
    x, y: float32,
    align: uint32,
    size, spacing: float32,
): (float32, float32, ptr FonsGlyphObj) =
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
    h = float32(font.metrics.ascender + font.metrics.lineGap - font.metrics.descender)
    ascender = float32(font.metrics.ascender + font.metrics.lineGap) / h
    descender = float32(font.metrics.descender) / h
    scale = size / float32(font.metrics.ascender - font.metrics.descender)
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

proc getGlyphShape*(
    fons: var FonsStashObj, glyph: ptr FonsGlyphObj
): lent seq[GlyphVertex] =
  if glyph.shape.len <= 0:
    let font = fons.getFontById(glyph.fontId)
    if font.isNil:
      return

    glyph.shape = font.openType.getGlyphShape(glyph.glyphId)
  glyph.shape
