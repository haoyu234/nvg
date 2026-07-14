import std/math
import std/unicode

import ./backend
import ./cache
import ./core
import ./font
import ./font_collection
import ./glyph_cache
import ./math
import ./path
import ./pieces
import ./text_blob
import ./tracy

type
  ContextState = object
    fillRule: FillRule
    compositeOperation: CompositeOperation
    fillStyle: Paint
    strokeStyle: Paint
    strokeWidth: float32
    miterLimit: float32
    lineJoin: LineJoin
    lineCap: LineCap
    dashArray: seq[float32]
    dashOffset: float32
    globalAlpha: float32
    transform: Mat2d

    # font state
    fontCollection: FontCollection
    fontSize: float32
    letterSpacing: float32
    wordSpacing: float32
    lineHeight: float32
    textAlign: HorizontalAlignment
    textBaseline: BaselineAlignment
    textWrap: TextWrap
    textOverflow: TextOverflow
    fontWeight: FontWeight
    fontStyle: FontStyle
    fontStretch: FontStretch
    fontFamily: FontFamily
    maxWidth: float32

  Context* = ref ContextObj
  ContextObj = object # state
    fillRule*: FillRule
    fillStyle*: Paint
    strokeStyle*: Paint
    strokeWidth*: float32
    miterLimit*: float32
    lineJoin*: LineJoin
    lineCap*: LineCap
    dashArray*: seq[float32]
    dashOffset*: float32
    globalAlpha*: float32
    compositeOperation*: CompositeOperation
    transform: Mat2d

    # font state
    fontId*: FontId
    fontSize*: float32
    letterSpacing*: float32
    wordSpacing*: float32
    lineHeight*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    textWrap*: TextWrap
    textOverflow*: TextOverflow
    fontWeight*: FontWeight
    fontStyle*: FontStyle
    fontStretch*: FontStretch
    fontFamily*: FontFamily
    maxWidth*: float32

    #
    backendContext*: BackendContext
    fontCollection*: FontCollection
    textLayoutContext*: TextLayoutContext
    glyphCache*: GlyphCache

    tessTol: float32
    tessTolSq: float32
    distTol: float32
    distTolSq: float32
    devicePixelRatio: float32

    cache: Cache
    states: seq[ContextState]
    lastIdx: uint32

    path: Path

    glyphs: seq[DrawGlyph]

proc resetState(ctx: Context) =
  ctx.fillRule = NonZero
  ctx.fillStyle = color(0, 0, 0, 255)
  ctx.strokeStyle = color(0, 0, 0, 255)

  ctx.compositeOperation = SOURCE_OVER_OPERATION
  ctx.strokeWidth = 1
  ctx.miterLimit = 10
  ctx.lineCap = ButtCap
  ctx.lineJoin = MiterJoin
  ctx.dashArray.setLen(0)
  ctx.dashOffset = 0
  ctx.globalAlpha = 1
  ctx.transform = mat2d()

  # font settings
  ctx.fontId = default(FontId)
  ctx.fontSize = 32
  ctx.letterSpacing = 0
  ctx.wordSpacing = 0
  ctx.lineHeight = 0
  ctx.textAlign = LeftAlign
  ctx.textBaseline = AlphabeticBaseline
  ctx.textWrap = NoWrap
  ctx.textOverflow = Hidden
  ctx.fontWeight = Normal
  ctx.fontStyle = Normal
  ctx.fontStretch = Normal
  ctx.fontFamily = Default
  ctx.maxWidth = 0

proc setDevicePixelRatio*(
  ctx: Context, devicePixelRatio: float32) {.inline.} =
  ctx.tessTol = 0.25 / devicePixelRatio
  ctx.distTol = 0.01 / devicePixelRatio
  ctx.tessTolSq = ctx.tessTol * ctx.tessTol
  ctx.distTolSq = ctx.distTol * ctx.distTol
  ctx.devicePixelRatio = devicePixelRatio

proc devicePixelRatio*(ctx: Context): float32 {.inline.} =
  ctx.devicePixelRatio

proc state(ctx: Context): ContextState =
  result.fillRule = ctx.fillRule
  result.compositeOperation = ctx.compositeOperation
  result.fillStyle = ctx.fillStyle
  result.strokeStyle = ctx.strokeStyle
  result.strokeWidth = ctx.strokeWidth
  result.miterLimit = ctx.miterLimit
  result.lineJoin = ctx.lineJoin
  result.lineCap = ctx.lineCap
  result.dashArray = ctx.dashArray
  result.dashOffset = ctx.dashOffset
  result.globalAlpha = ctx.globalAlpha
  result.transform = ctx.transform

  result.fontCollection = ctx.fontCollection
  result.fontSize = ctx.fontSize
  result.letterSpacing = ctx.letterSpacing
  result.wordSpacing = ctx.wordSpacing
  result.lineHeight = ctx.lineHeight
  result.textAlign = ctx.textAlign
  result.textBaseline = ctx.textBaseline
  result.textWrap = ctx.textWrap
  result.textOverflow = ctx.textOverflow
  result.fontWeight = ctx.fontWeight
  result.fontStyle = ctx.fontStyle
  result.fontStretch = ctx.fontStretch
  result.fontFamily = ctx.fontFamily
  result.maxWidth = ctx.maxWidth

proc save*(ctx: Context) {.inline.} =
  ctx.states.add(ctx.state)

  assert ctx.states.len < 255

proc restore*(ctx: Context) =
  assert ctx.states.len > 0

  if ctx.states.len > 0:
    let state = ctx.states[ctx.states.len - 1].addr
    ctx.fillRule = state.fillRule
    ctx.compositeOperation = state.compositeOperation
    ctx.fillStyle = state.fillStyle
    ctx.strokeStyle = state.strokeStyle
    ctx.strokeWidth = state.strokeWidth
    ctx.miterLimit = state.miterLimit
    ctx.lineJoin = state.lineJoin
    ctx.lineCap = state.lineCap
    ctx.dashArray = state.dashArray
    ctx.dashOffset = state.dashOffset
    ctx.globalAlpha = state.globalAlpha
    ctx.transform = state.transform

    ctx.fontCollection = state.fontCollection
    ctx.fontSize = state.fontSize
    ctx.letterSpacing = state.letterSpacing
    ctx.wordSpacing = state.wordSpacing
    ctx.lineHeight = state.lineHeight
    ctx.textAlign = state.textAlign
    ctx.textBaseline = state.textBaseline
    ctx.textWrap = state.textWrap
    ctx.textOverflow = state.textOverflow
    ctx.fontWeight = state.fontWeight
    ctx.fontStyle = state.fontStyle
    ctx.fontStretch = state.fontStretch
    ctx.fontFamily = state.fontFamily
    ctx.maxWidth = state.maxWidth

    ctx.states.setLen(ctx.states.len - 1)

proc createContext*(backendContext: BackendContext,
    fontCollection: FontCollection,
    textLayoutContext: TextLayoutContext): Context =
  result = Context()
  result.backendContext = backendContext
  result.fontCollection = fontCollection
  result.textLayoutContext = textLayoutContext
  result.glyphCache = createGlyphCache(result.backendContext)
  result.setDevicePixelRatio(1)
  result.resetState()

proc translate*(ctx: Context, v: Vec2) {.inline.} =
  ctx.transform.translate(v)

proc scale*(ctx: Context, v: Vec2) {.inline.} =
  ctx.transform.scale(v)

proc rotate*(ctx: Context, radians: float32) {.inline.} =
  ctx.transform.rotate(radians)

proc skew*(ctx: Context, radians: Vec2) {.inline.} =
  ctx.transform.skew(radians)

proc resetTransform*(ctx: Context) {.inline.} =
  ctx.transform = mat2d()

proc getTransform*(ctx: Context): lent Mat2d {.inline.} =
  ctx.transform

proc setTransform*(ctx: Context, v: Mat2d) {.inline.} =
  ctx.transform = v

proc transform*(ctx: Context, v: Mat2d) {.inline.} =
  ctx.transform.multiply(v)

proc fillPath*(ctx: Context, path: Path) =
  let
    zone = zoneBegin("context.fillPath")
  defer: zone.zoneEnd()

  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  let paths = ctx.cache.expandFill(ctx.distTolSq)

  var paint = ctx.fillStyle
  paint.transform.premultiply(ctx.transform)
  paint.innerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.innerColor.a))
  paint.outerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.outerColor.a))

  ctx.backendContext.drawPaths(
    paint,
    paths.toOpenArray,
    ctx.fillRule,
    ctx.compositeOperation,
  )

proc getAverageScale(t: Mat2d): float32 {.inline.} =
  let
    sx = sqrt(t.xx * t.xx + t.xy * t.xy)
    sy = sqrt(t.yx * t.yx + t.yy * t.yy)

  sqrt(sx * sy)

proc strokePath*(ctx: Context, path: Path) =
  let
    zone = zoneBegin("context.strokePath")
  defer: zone.zoneEnd()

  let
    s = getAverageScale(ctx.transform)
    strokeWidth = max(ctx.strokeWidth * s, 0.01)

  var paint = ctx.strokeStyle
  paint.transform.premultiply(ctx.transform)
  paint.innerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.innerColor.a))
  paint.outerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.outerColor.a))

  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  if len(ctx.dashArray) > 0 and ctx.dashArray[0] > 0:
    ctx.cache.dashStroke(s, strokeWidth, ctx.dashOffset, ctx.dashArray)

  let paths = ctx.cache.expandStroke(
    ctx.lineCap, ctx.lineJoin, strokeWidth, ctx.miterLimit,
    ctx.tessTolSq, ctx.distTolSq
  )

  ctx.backendContext.drawPaths(
    paint,
    paths.toOpenArray,
    NonZero,
    ctx.compositeOperation,
  )

proc flush*(ctx: Context) {.inline.} =
  let
    zone = zoneBegin("context.flush")
  defer: zone.zoneEnd()

  ctx.glyphCache.uploadDirty()
  ctx.backendContext.flush()

proc beginPath*(ctx: Context) {.inline.} =
  ctx.path.clear()

proc rect*(ctx: Context, xywh: Vec4) {.inline.} =
  ctx.path.rect(xywh)

proc arc*(ctx: Context, c: Vec2, r, a0, a1: float32, ccw: bool) =
  ctx.path.arc(c, r, a0, a1, ccw)

proc ellipse*(ctx: Context, c: Vec2, rx, ry: float32) {.inline.} =
  ctx.path.ellipse(c, rx, ry)

proc circle*(ctx: Context, c: Vec2, r: float32) {.inline.} =
  ctx.path.circle(c, r)

proc moveTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.moveTo(pos)

proc relMoveTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.relMoveTo(pos)

proc lineTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.lineTo(pos)

proc relLineTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.relLineTo(pos)

proc bezierTo*(ctx: Context, cp1, cp2, to: Vec2) {.inline.} =
  ctx.path.bezierTo(cp1, cp2, to)

proc relBezierTo*(ctx: Context, cp1, cp2, to: Vec2) {.inline.} =
  ctx.path.relBezierTo(cp1, cp2, to)

proc quadCurveTo*(ctx: Context, cp, to: Vec2) {.inline.} =
  ctx.path.quadCurveTo(cp, to)

proc relQuadCurveTo*(ctx: Context, cp, to: Vec2) {.inline.} =
  ctx.path.relQuadCurveTo(cp, to)

proc arcTo*(ctx: Context, a, b: Vec2, r: float32) =
  ctx.path.arcTo(a, b, r)

proc closePath*(ctx: Context) {.inline.} =
  ctx.path.closePath()

proc fill*(ctx: Context) {.inline.} =
  ctx.fillPath(ctx.path)

proc stroke*(ctx: Context) {.inline.} =
  ctx.strokePath(ctx.path)

proc imagePattern*(ctx: Context, xywh: Vec4, radians: float32,
    imageId: ImageId, alpha: float32): Paint {.inline.} =
  result.transform = rotated(radians)
  result.transform.x0 = xywh[0]
  result.transform.y0 = xywh[1]
  result.extent[0] = xywh[2]
  result.extent[1] = xywh[3]
  result.imageId = imageId

  let a8 = uint8(clamp(alpha, 0, 1) * 255)
  result.innerColor = color(255, 255, 255, a8)
  result.outerColor = color(255, 255, 255, a8)

proc getImageInfo*(ctx: Context, imageId: ImageId): ImageInfo {.inline.} =
  ctx.backendContext.getImageInfo(imageId)

proc loadFontFromMemory*(ctx: Context, name: string, buffer: seq[byte],
    fontFamily: FontFamily) =
  if ctx.fontCollection.isNil or ctx.textLayoutContext.isNil:
    return

  inc ctx.lastIdx, 1

  let
    fontId = FontId(id: ctx.lastIdx)
    font = createFontFromMemory(fontId, fontFamily, buffer)
  ctx.fontCollection.add(font)

proc textAttribs*(ctx: Context): TextAttribs =
  TextAttribs(attribs: [
    TextAttrib(kind: akColor, color: ctx.fillStyle.innerColor),
    TextAttrib(kind: akFontSize, fontSize: ctx.fontSize),
    TextAttrib(kind: akLetterSpacing, letterSpacing: ctx.letterSpacing),
    TextAttrib(kind: akWordSpacing, wordSpacing: ctx.wordSpacing),
    TextAttrib(kind: akLineHeight, lineHeight: ctx.lineHeight),
    TextAttrib(kind: akTextAlign, textAlign: ctx.textAlign),
    TextAttrib(kind: akTextBaseline, textBaseline: ctx.textBaseline),
    TextAttrib(kind: akTextWrap, textWrap: ctx.textWrap),
    TextAttrib(kind: akTextOverflow, textOverflow: ctx.textOverflow),
    TextAttrib(kind: akFontWeight, fontWeight: ctx.fontWeight),
    TextAttrib(kind: akFontStyle, fontStyle: ctx.fontStyle),
    TextAttrib(kind: akFontStretch, fontStretch: ctx.fontStretch),
    TextAttrib(kind: akFontFamily, fontFamily: ctx.fontFamily),
  ])

proc createTextBlob*(ctx: Context, text: openArray[char]): TextBlob =
  if ctx.fontCollection.isNil or ctx.textLayoutContext.isNil:
    return

  result = ctx.textLayoutContext.createTextBlob(
    ctx.fontCollection, toRunes(text), [
      TextAttribSpan(
        runeRange: int32(0) .. high(int32),
        attribs: ctx.textAttribs.attribs,
    )
  ],
    float32(0), float32(0))

type
  BatchDrawGlyph = object
    curveTexId: ImageId
    bandTexId: ImageId
    useSolid: bool
    basePaint: Paint
    solidPaint: Paint

proc flushGlyphs(batch: var BatchDrawGlyph, ctx: Context) =
  let
    zone = zoneBegin("context.flushGlyphs")
  defer: zone.zoneEnd()

  if ctx.glyphs.len > 0:
    ctx.backendContext.drawGlyphs(
        (if batch.useSolid: batch.solidPaint else: batch.basePaint),
        ctx.transform, batch.curveTexId, batch.bandTexId, ctx.glyphs,
        ctx.compositeOperation)
    ctx.glyphs.setLen(0)

proc addGlyph(batch: var BatchDrawGlyph, ctx: Context,
    info: SlugGlyphInfo, posX, posY: float32, textColor: Color,
    useSolid: bool, layerTransform: Mat2d, scale: float32) =
  let
    zone = zoneBegin("context.addGlyph")
  defer: zone.zoneEnd()

  if info.rawBBox.xMin == 0 and info.rawBBox.xMax == 0 and
      info.rawBBox.yMin == 0 and info.rawBBox.yMax == 0:
    return

  let
    scale = scale
    baselineX = posX
    baselineY = posY

  var
    glyphTransform = mat2d()
  if layerTransform != glyphTransform:
    # Layer transform expressed around the baseline:
    #   T(baseline) · S(scale,-scale) · layerTransform · S(1/scale,-1/scale) · T(-baseline)
    glyphTransform = translated(vec2(baselineX, baselineY))
      .multiplied(scaled(vec2(scale, -scale)))
      .multiplied(layerTransform)
      .multiplied(scaled(vec2(float32(1) / scale, -float32(1) / scale)))
      .multiplied(translated(vec2(-baselineX, -baselineY)))

  if info.curveTexId != batch.curveTexId or
      info.bandTexId != batch.bandTexId or
      useSolid != batch.useSolid:
    batch.flushGlyphs(ctx)
    batch.curveTexId = info.curveTexId
    batch.bandTexId = info.bandTexId
    batch.useSolid = useSolid

  let
    x = baselineX + info.rawBBox.xMin * scale
    y = baselineY - info.rawBBox.yMin * scale
    w = (info.rawBBox.xMax - info.rawBBox.xMin) * scale
    h = (info.rawBBox.yMin - info.rawBBox.yMax) * scale

  var
    drawGlyph = default(DrawGlyph)
  drawGlyph.drawRect[0] = x
  drawGlyph.drawRect[1] = y
  drawGlyph.drawRect[2] = w
  drawGlyph.drawRect[3] = h
  drawGlyph.glyphLocX = info.glyphLoc[0]
  drawGlyph.glyphLocY = info.glyphLoc[1]
  drawGlyph.maxBandX = info.maxBandX
  drawGlyph.maxBandY = info.maxBandY
  drawGlyph.color = textColor
  drawGlyph.transform = glyphTransform

  ctx.glyphs.add(drawGlyph)

proc addColrGlyph(batch: var BatchDrawGlyph, ctx: Context, font: Font,
    run: GlyphRun, pos: Vec2, color: Color, paintIsPlain: bool,
    scale: float32, shear: bool) =
  let
    zone = zoneBegin("context.addColrGlyph")
  defer: zone.zoneEnd()

  for g in font.getColrGlyphs(run.glyphId):
    if g.glyphId.isNil:
      continue

    var
      layerColor = color

    if g.paletteEntryIndex != 0xFFFF:
      layerColor = font.getPaletteColor(0, g.paletteEntryIndex)
      layerColor.a = uint8((uint32(layerColor.a) * uint32(color.a) +
          uint32(127)) div uint32(255))

    let layerAlpha = clamp(g.alpha, float32(0), float32(1))
    if layerAlpha < 1:
      layerColor.a = uint8(float32(layerColor.a) * layerAlpha +
          float32(0.5))

    let
      glyphInfo = ctx.glyphCache.getGlyphInfo(font, g.glyphId, shear)

    batch.addGlyph(ctx, glyphInfo, pos[0] + run.x, pos[1] + run.y,
        layerColor, not paintIsPlain, g.paintTransform, scale)

proc fillTextBlob*(ctx: Context, textBlob: TextBlob, pos: Vec2) =
  let
    zone = zoneBegin("context.fillTextBlob")
  defer: zone.zoneEnd()

  if textBlob.lines.len <= 0:
    return

  let
    basePaint = ctx.fillStyle
    paintIsPlain = basePaint.imageId.isNil and
        basePaint.innerColor == basePaint.outerColor

  var
    batch = BatchDrawGlyph(
      basePaint: basePaint,
      solidPaint: basePaint,
    )
  batch.solidPaint.imageId = default(ImageId)
  batch.solidPaint.outerColor = batch.solidPaint.innerColor

  for line in textBlob.lines:
    for i in line.runStart ..< line.runStart + line.runLen:
      let
        run = textBlob.runs[i]
        font = textBlob.fontCollection.getFont(run.fontId)
      if font.isNil:
        continue

      let
        zone = zoneBegin("context.fillTextBlob.run")
      defer: zone.zoneEnd()

      if run.glyphId.isNil:
        continue

      let
        fontSize = getAttrib(textBlob.spans, run.runePos, akFontSize)
        scale = font.getPixelHeightScale(fontSize)

      var
        shear = false
        color = getAttrib(textBlob.spans, run.runePos, akColor)
      color.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(color.a))

      if font.getStyle() == Normal:
        let
          runStyle = getAttrib(textBlob.spans, run.runePos, akFontStyle)
        if runStyle == Italic or runStyle == Oblique:
          shear = true

      if not font.hasColor(run.glyphId):
        let
          glyphInfo = ctx.glyphCache.getGlyphInfo(font, run.glyphId, shear)

        batch.addGlyph(ctx, glyphInfo, pos[0] + run.x, pos[1] + run.y,
            color, false, mat2d(), scale)
      else:
        batch.addColrGlyph(ctx, font, run, pos, color, paintIsPlain,
            scale, shear)

  batch.flushGlyphs(ctx)

proc fillText*(ctx: Context, text: openArray[char], pos: Vec2) =
  let
    zone = zoneBegin("context.fillText")
  defer: zone.zoneEnd()

  if ctx.fontCollection.isNil or ctx.textLayoutContext.isNil:
    return

  let
    textBlob = ctx.createTextBlob(text)
  if textBlob.lines.len <= 0:
    return

  ctx.fillTextBlob(textBlob, pos)
