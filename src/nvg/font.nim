import ./core
import ./truetype
import ./unicode_script

type
  Font* = ref object
    fontId: FontId
    fontFamily: FontFamily
    trueType: TrueType
    weight: FontWeight
    style: FontStyle
    stretch: FontStretch
    metrics: FontMetrics
    scripts: seq[uint8]
    storage: seq[byte]

proc computeScripts(trueType: TrueType): seq[uint8] =
  var
    seen: array[256, bool]
    scanned: int32 = 0

  for (a, b) in trueType.getCoveredRanges():
    var c = a
    while c <= b:
      if trueType.getGlyphId(c).id != 0:
        let s = uint8(ord(lookupScript(c)))
        if s != 0 and not seen[s]:
          seen[s] = true
          result.add(s)
      inc c
      inc scanned
      if scanned > int32(1_000_000):
        return

proc createFontFromMemory*(fontId: FontId, fontFamily: FontFamily,
    buffer: seq[byte]): Font =
  let
    p = Font()
    storage = buffer
    trueType = parseTrueType(storage, 0)
    metrics = trueType.getFontMetrics()

  p.storage = storage
  p.trueType = trueType
  p.metrics = metrics
  p.fontId = fontId
  p.fontFamily = fontFamily
  p.style = trueType.getStyle()
  p.weight = trueType.getWeight()
  p.stretch = trueType.getStretch()
  p.scripts = trueType.computeScripts()

  p

proc getFontId*(font: Font): FontId =
  font.fontId

proc getFontFamily*(font: Font): FontFamily =
  font.fontFamily

proc getGlyphCount*(font: Font): int32 =
  font.trueType.numGlyphs

proc getFontMetrics*(font: Font): FontMetrics =
  font.metrics

proc getStyle*(font: Font): FontStyle =
  font.style

proc getWeight*(font: Font): FontWeight =
  font.weight

proc getStretch*(font: Font): FontStretch =
  font.stretch

proc getScripts*(font: Font): seq[uint8] =
  font.scripts

proc getPixelHeightScale*(font: Font, size: float32): float32 =
  let
    metrics = font.getFontMetrics()
    em = float32(metrics.ascender - metrics.descender)

  if em > 0.0f:
    size / em
  else:
    size

proc getGlyphId*(font: Font, unicodeCodepoint: uint32): GlyphId =
  font.trueType.getGlyphId(unicodeCodepoint)

proc getGlyphBox*(font: Font, glyphId: GlyphId): Bounds =
  let
    box = font.trueType.getGlyphBox(glyphId)
  Bounds(
    xMin: float32(box.xMin),
    yMin: float32(box.yMin),
    xMax: float32(box.xMax),
    yMax: float32(box.yMax),
  )

proc getGlyphPath*(font: Font, glyphId: GlyphId,
    matrix: Mat2d = mat2d()): Path =
  font.trueType.getGlyphPath(glyphId, matrix)

proc getGlyphMetrics*(font: Font, glyphId: GlyphId): GlyphMetrics =
  font.trueType.getGlyphMetrics(glyphId)

proc getGlyphAdvance*(font: Font, glyphId: GlyphId): float32 =
  float32(font.trueType.getGlyphAdvance(glyphId))

proc getGlyphKernAdvance*(font: Font, glyphId1, glyphId2: GlyphId): uint32 =
  font.trueType.getGlyphKernAdvance(glyphId1, glyphId2)

proc hasColor*(font: Font, glyphId: GlyphId): bool =
  font.trueType.hasColor(glyphId)

iterator getColrGlyphs*(font: Font, glyphId: GlyphId): ColrGlyph =
  for glyph in font.trueType.getColrGlyphs(glyphId):
    yield glyph

proc getPaletteColor*(font: Font, paletteIndex: int32,
    paletteEntryIndex: uint16): Color =
  font.trueType.getPaletteColor(paletteIndex, paletteEntryIndex)

