import std/enumerate
import std/unicode

import ./core
import ./font
import ./font_collection
import ./line_break
import ./text_blob
import ./tracy
import ./unicode_script

type
  Glyph = object
    font: Font
    glyphId: GlyphId
    scale: float32
    fontSize: float32
    rune: Rune
    isSpace: bool
    advance: float32
    width: float32
    metrics: GlyphMetrics
    leadingKern: float32
    x: float32

  FontAndGlyph = object
    glyphId: GlyphId
    font: Font

  LineRange = object
    start: int32
    stop: int32

  LineMetrics = object
    font: Font
    lineHeight, asc, desc, maxFontSize: float32

  SimpleTextLayoutContext* = ref object of TextLayoutContext
    glyphs: seq[Glyph]
    lines: seq[LineRange]
    runs: seq[GlyphRun]

proc createSimpleTextLayoutContext*(): SimpleTextLayoutContext =
  SimpleTextLayoutContext()

proc isSpaceAscii(r: Rune): bool =
  r == Rune(ord(' ')) or r == Rune(ord('\t'))

proc matchFontAndGlyph(fontCollection: FontCollection,
    fontFamily: FontFamily, fontWeight: FontWeight, fontStyle: FontStyle,
    fontStretch: FontStretch, r: Rune, script: uint8): FontAndGlyph =
  let
    zone = zoneBegin("simpleTextLayout.matchFontAndGlyph")
  defer: zone.zoneEnd()

  let
    primary = fontCollection.matchFonts(
      uint8(0),
      script,
      fontFamily,
      fontWeight,
      fontStyle,
      fontStretch)

  for f in primary:
    let glyph = f.getGlyphId(uint32(r))
    if not glyph.isNil:
      result.glyphId = glyph
      result.font = f
      return

  let fallbackFont = fontCollection.getFontByRune(r)
  if not fallbackFont.isNil:
    result.glyphId = fallbackFont.getGlyphId(uint32(r))
    result.font = fallbackFont

proc buildGlyphs(layoutContext: SimpleTextLayoutContext,
    text: openArray[Rune], fontCollection: FontCollection,
    spans: openArray[TextAttribSpan]) =
  let
    zone = zoneBegin("simpleTextLayout.buildGlyphs")
  defer: zone.zoneEnd()

  var
    prevFont = default(Font)
    prevFontSize = float32(-1)
    prevScale = float32(0)
    prevGlyphId = default(GlyphId)

  for scriptRun in scriptRuns(text):
    var
      key = uint8(0)
    if isConcreteScript(scriptRun.script):
      key = uint8(ord(scriptRun.script))

    for idx in scriptRun.offset ..< scriptRun.offset + scriptRun.length:
      var
        glyph = default(Glyph)
      glyph.rune = text[idx]

      if glyph.rune == Rune(ord('\n')):
        layoutContext.glyphs.add(glyph)
        continue

      let
        fontFamily = getAttrib(spans, idx, akFontFamily)
        fontWeight = getAttrib(spans, idx, akFontWeight)
        fontStyle = getAttrib(spans, idx, akFontStyle)
        fontStretch = getAttrib(spans, idx, akFontStretch)
        fontSize = getAttrib(spans, idx, akFontSize)
        letterSpacing = getAttrib(spans, idx, akLetterSpacing)
        wordSpacing = getAttrib(spans, idx, akWordSpacing)

      let
        item = matchFontAndGlyph(fontCollection, fontFamily, fontWeight,
            fontStyle, fontStretch, glyph.rune, key)
      if item.font.isNil:
        layoutContext.glyphs.add(glyph)
        continue

      if prevFont != item.font or prevFontSize != fontSize:
        prevFont = item.font
        prevFontSize = fontSize
        prevScale = item.font.getPixelHeightScale(fontSize)

      let
        metrics = item.font.getGlyphMetrics(item.glyphId)
        advance = prevScale * float32(metrics.advance)
        isSpace = isSpaceAscii(glyph.rune)

      glyph.font = item.font
      glyph.glyphId = item.glyphId
      glyph.scale = prevScale
      glyph.fontSize = fontSize
      glyph.isSpace = isSpace
      glyph.advance = advance
      glyph.metrics = metrics

      if isSpace:
        glyph.width = advance + wordSpacing
      else:
        glyph.width = advance

      if not prevGlyphId.isNil:
        if prevFont == item.font:
          glyph.leadingKern = prevScale * float32(item.font.getGlyphKernAdvance(
              prevGlyphId, item.glyphId)) + letterSpacing
        else:
          glyph.leadingKern = letterSpacing

      prevGlyphId = item.glyphId

      layoutContext.glyphs.add(glyph)

proc layoutLines(layoutContext: SimpleTextLayoutContext,
    text: openArray[Rune], maxLineWidth: float32, textWrap: TextWrap) =
  let
    zone = zoneBegin("simpleTextLayout.layoutLines")
  defer: zone.zoneEnd()

  let
    wrapActive = (textWrap != NoWrap) and maxLineWidth > 0

  var
    lineStart = int32(0)
    lineStop = int32(0)
    lineCount = int32(0)
    width = float32(0)

  template appendRange(start, stop: int32, allowWrap = false): int32 =
    if lineCount == 0:
      lineStart = start

    var
      idx = start
    while idx < stop:
      let
        glyph = layoutContext.glyphs[idx].addr
      # if wrapping is allowed, check whether the next glyph fits on
      # the current line; spaces never trigger a wrap (consistent with
      # the old tkSpace: trailing spaces stay at line end)
      if allowWrap and lineCount > 0 and not glyph.isSpace and
          width + glyph.width + glyph.leadingKern > maxLineWidth:
        break

      if lineCount > 0:
        width += glyph.leadingKern
      glyph.x = width
      width += glyph.width

      inc lineCount, 1
      inc idx, 1

    lineStop = idx
    idx

  template appendLine() =
    layoutContext.lines.add(LineRange(start: lineStart,
        stop: lineStop))
    lineCount = 0
    width = 0

  for run in lineBreakRuns(text):
    if not wrapActive:
      discard appendRange(run.offset, run.stop)
      if run.mustBreak:
        appendLine()
      continue

    let
      widthBefore = width
      lineStopBefore = lineStop
      lineCountBefore = lineCount

    let placed = appendRange(run.offset, run.stop, true)
    if placed == run.stop:
      if run.mustBreak:
        appendLine()
      continue

    var
      idx = placed
    if lineCountBefore > 0:
      width = widthBefore
      lineStop = lineStopBefore
      lineCount = lineCountBefore
      appendLine()
      idx = appendRange(run.offset, run.stop, true)
      if idx == run.stop:
        if run.mustBreak:
          appendLine()
        continue

    if textWrap == WordCharWrap:
      while idx < run.stop:
        appendLine()
        idx = appendRange(idx, run.stop, true)
    else:
      discard appendRange(idx, run.stop)

    if run.mustBreak:
      appendLine()

  if lineCount > 0:
    layoutContext.lines.add(LineRange(start: lineStart,
        stop: lineStop))

proc lineBaselineOffset(textBaseline: BaselineAlignment, asc, desc,
    fontSize: float32): float32 =
  case textBaseline
  of TopBaseline:
    result = asc * fontSize
  of MiddleBaseline:
    result = (asc + desc) / 2 * fontSize
  of BottomBaseline:
    result = desc * fontSize
  of AlphabeticBaseline:
    result = float32(0)

proc measureLineMetrics(layoutContext: SimpleTextLayoutContext,
    spans: openArray[TextAttribSpan], lineGlyphRange: LineRange): LineMetrics =
  let
    zone = zoneBegin("simpleTextLayout.measureLineMetrics")
  defer: zone.zoneEnd()

  var
    font: Font
    maxFontSize = float32(0)

  if lineGlyphRange.stop > lineGlyphRange.start:
    font = layoutContext.glyphs[lineGlyphRange.start].font
    for idx in lineGlyphRange.start ..< lineGlyphRange.stop:
      let
        fontSize = layoutContext.glyphs[idx].fontSize
      if fontSize > maxFontSize:
        maxFontSize = fontSize

  var
    lineHeight = maxFontSize * float32(1.2)
    asc = float32(0.8)
    desc = float32(0.2)

  let
    lineHeightAttrib = getAttrib(spans, lineGlyphRange.start, akLineHeight)
  if lineHeightAttrib > 0:
    lineHeight = lineHeightAttrib
  if not font.isNil:
    let
      metrics = font.getFontMetrics()
      metricsHeight = float32(metrics.ascender + metrics.lineGap -
        metrics.descender)
    if metricsHeight > 0:
      asc = float32(metrics.ascender + metrics.lineGap) / metricsHeight
      desc = float32(-metrics.descender) / metricsHeight

  result = LineMetrics(font: font, lineHeight: lineHeight, asc: asc,
      desc: desc, maxFontSize: maxFontSize)

proc buildTextLine(layoutContext: SimpleTextLayoutContext,
    fontCollection: FontCollection, lineGlyphRange: LineRange,
    width: float32,
    lineYBase, lineHeight, asc, desc, lineFontSize: float32,
    spans: openArray[TextAttribSpan], forceEllipsis: bool): TextLine =
  let
    zone = zoneBegin("simpleTextLayout.buildTextLine")
  defer: zone.zoneEnd()

  let
    textAlign = getAttrib(spans, lineGlyphRange.start, akTextAlign)
    textBaseline = getAttrib(spans, lineGlyphRange.start, akTextBaseline)
    textOverflow = getAttrib(spans, lineGlyphRange.start, akTextOverflow)
    fontFamily = getAttrib(spans, lineGlyphRange.start, akFontFamily)
    fontWeight = getAttrib(spans, lineGlyphRange.start, akFontWeight)
    fontStyle = getAttrib(spans, lineGlyphRange.start, akFontStyle)
    fontStretch = getAttrib(spans, lineGlyphRange.start, akFontStretch)

  var
    ellipsisFont = default(Font)
    ellipsisGlyph = default(GlyphId)
    ellipsisScale = float32(0)
    ellipsisLead = float32(0)
    lineGlyphLastIdx = lineGlyphRange.stop - 1

  if textOverflow == Ellipsis and width > 0 and
      lineGlyphLastIdx >= lineGlyphRange.start:

    let
      estimate = layoutContext.glyphs[lineGlyphLastIdx].x +
          layoutContext.glyphs[lineGlyphLastIdx].width

    if estimate > width or forceEllipsis:
      let
        item = matchFontAndGlyph(fontCollection, fontFamily, fontWeight,
            fontStyle, fontStretch, Rune(0x2026), uint8(0))
      if not item.font.isNil:
        ellipsisFont = item.font
        ellipsisGlyph = item.glyphId
        ellipsisScale = item.font.getPixelHeightScale(lineFontSize)

        let
          s = ellipsisScale *
            float32(item.font.getGlyphAdvance(item.glyphId))

        while lineGlyphLastIdx >= lineGlyphRange.start:
          let
            idx = lineGlyphLastIdx
            w = layoutContext.glyphs[idx].x +
                layoutContext.glyphs[idx].width
          ellipsisLead = ellipsisScale * float32(
              ellipsisFont.getGlyphKernAdvance(layoutContext.glyphs[
              idx].glyphId, ellipsisGlyph))
          if w + ellipsisLead + s <= width:
            break

          dec lineGlyphLastIdx, 1

  var
    lineWidth = float32(0)
    runStart = int32(layoutContext.runs.len)

  for offset, glyph in enumerate(layoutContext.glyphs.toOpenArray(
      lineGlyphRange.start, lineGlyphLastIdx)):
    var
      run = default(GlyphRun)
    run.fontId = glyph.font.getFontId
    run.glyphId = glyph.glyphId
    run.x = glyph.x
    run.y = lineYBase + lineBaselineOffset(textBaseline, asc, desc,
        glyph.fontSize)
    run.unicodeCodepoint = uint32(glyph.rune)
    run.metrics = glyph.metrics
    run.advance = glyph.advance
    run.runePos = lineGlyphRange.start + int32(offset)
    layoutContext.runs.add(run)
    lineWidth = glyph.x + glyph.width

  if not ellipsisFont.isNil:
    var
      x = float32(0)
    if lineGlyphLastIdx >= lineGlyphRange.start:
      x = lineWidth + ellipsisLead

    var
      run = default(GlyphRun)
    run.fontId = ellipsisFont.getFontId
    run.glyphId = ellipsisGlyph
    run.x = x
    run.y = lineYBase + lineBaselineOffset(textBaseline, asc, desc,
        lineFontSize)
    run.unicodeCodepoint = uint32(0x2026)
    run.metrics = ellipsisFont.getGlyphMetrics(ellipsisGlyph)
    run.advance = ellipsisScale * float32(ellipsisFont.getGlyphAdvance(ellipsisGlyph))
    run.runePos = lineGlyphRange.stop
    layoutContext.runs.add(run)
    lineWidth = x + run.advance

  let baseX = case textAlign
    of LeftAlign: float32(0)
    of RightAlign: width - lineWidth
    of CenterAlign: (width - lineWidth) * float32(0.5)

  if baseX != 0:
    for idx in runStart ..< layoutContext.runs.len:
      layoutContext.runs[idx].x += baseX

  result.runStart = runStart
  result.runLen = int32(layoutContext.runs.len) - runStart
  result.width = lineWidth
  result.ascender = asc * lineFontSize
  result.descender = desc * lineFontSize

method createTextBlob*(layoutContext: SimpleTextLayoutContext,
    fontCollection: FontCollection, text: openArray[Rune],
    spans: openArray[TextAttribSpan], width, height: float32): TextBlob =
  let
    zone = zoneBegin("simpleTextLayout.createTextBlob")
  defer: zone.zoneEnd()

  layoutContext.lines.setLen(0)
  layoutContext.glyphs.setLen(0)
  layoutContext.runs.setLen(0)

  let
    textWrap = getAttrib(spans, akTextWrap)

  layoutContext.buildGlyphs(text, fontCollection, spans)
  layoutContext.layoutLines(text, width, textWrap)

  if layoutContext.lines.len == 0:
    return

  result = TextBlob()
  result.spans = @spans
  result.fontCollection = fontCollection

  var
    lineYBase = float32(0)
    maxLineWidth = float32(0)
    lineIndex = int32(0)
    lineCount = int32(layoutContext.lines.len)
    current = layoutContext.measureLineMetrics(spans, layoutContext.lines[0])

  while lineIndex < lineCount:
    if height > 0 and lineYBase + current.lineHeight > height:
      break

    var
      next = default(LineMetrics)

    let
      hasNext = lineIndex + 1 < lineCount
      lineGlyphRange = layoutContext.lines[lineIndex]

    if hasNext:
      next = layoutContext.measureLineMetrics(spans, layoutContext.lines[
          lineIndex + 1])

    let
      forceEllipsis = hasNext and height > 0 and
          lineYBase + current.lineHeight + next.lineHeight > height
      line = layoutContext.buildTextLine(
        fontCollection,
        lineGlyphRange,
        width,
        lineYBase,
        current.lineHeight,
        current.asc,
        current.desc,
        current.maxFontSize,
        spans,
        forceEllipsis)

    if line.width > maxLineWidth:
      maxLineWidth = line.width

    lineYBase += current.lineHeight
    lineIndex += 1

    result.lines.add(line)

    if forceEllipsis:
      break

    current = next

  result.runs = move(layoutContext.runs)
  result.width = maxLineWidth
  result.height = lineYBase
