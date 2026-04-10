import ./backend
import ./cache
import ./core
import ./math
import ./path
import ./pieces
import ./text

import std/math

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
    fontId: FontId
    fontSize: float32
    fontColor: Color
    letterSpacing: float32
    wordSpacing: float32
    lineHeight: float32
    textAlign: HorizontalAlignment
    textBaseline: BaselineAlignment
    textWrap: TextWrap
    textOverflow: TextOverflow

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
    fontColor*: Color
    letterSpacing*: float32
    wordSpacing*: float32
    lineHeight*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    textWrap*: TextWrap
    textOverflow*: TextOverflow

    #
    backendContext*: BackendContext
    fontCollection*: FontCollection
    textBlobCache*: TextBlobCache
    textLayoutContext*: TextLayoutContext
    textRenderContext*: TextRenderContext

    tessTol: float32
    tessTolSq: float32
    distTol: float32
    distTolSq: float32
    devicePixelRatio: float32

    cache: Cache
    states: seq[ContextState]

    path: Path

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
  ctx.fontColor = color(0, 0, 0, 255)
  ctx.letterSpacing = 0
  ctx.wordSpacing = 0
  ctx.lineHeight = 16
  ctx.textAlign = LeftAlign
  ctx.textBaseline = AlphabeticBaseline
  ctx.textWrap = NoWrap
  ctx.textOverflow = Hidden

proc setDevicePixelRatio*(
  ctx: Context, devicePixelRatio: float32) {.inline.} =
  ctx.tessTol = 0.25 / devicePixelRatio
  ctx.distTol = 0.01 / devicePixelRatio
  ctx.tessTolSq = ctx.tessTol * ctx.tessTol
  ctx.distTolSq = ctx.distTol * ctx.distTol
  ctx.devicePixelRatio = devicePixelRatio

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

  result.fontId = ctx.fontId
  result.fontSize = ctx.fontSize
  result.fontColor = ctx.fontColor
  result.letterSpacing = ctx.letterSpacing
  result.wordSpacing = ctx.wordSpacing
  result.lineHeight = ctx.lineHeight
  result.textAlign = ctx.textAlign
  result.textBaseline = ctx.textBaseline
  result.textWrap = ctx.textWrap
  result.textOverflow = ctx.textOverflow

proc textAttribs(ctx: Context): TextAttribs =
  result.fontSize = ctx.fontSize
  result.fontColor = ctx.fontColor
  result.letterSpacing = ctx.letterSpacing
  result.wordSpacing = ctx.wordSpacing
  result.lineHeight = ctx.lineHeight
  result.textAlign = ctx.textAlign
  result.textBaseline = ctx.textBaseline
  result.textWrap = ctx.textWrap
  result.textOverflow = ctx.textOverflow

proc save*(ctx: Context) {.inline.} =
  ctx.states.add(ctx.state)

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

    ctx.fontId = state.fontId
    ctx.fontSize = state.fontSize
    ctx.fontColor = state.fontColor
    ctx.letterSpacing = state.letterSpacing
    ctx.wordSpacing = state.wordSpacing
    ctx.lineHeight = state.lineHeight
    ctx.textAlign = state.textAlign
    ctx.textBaseline = state.textBaseline
    ctx.textWrap = state.textWrap
    ctx.textOverflow = state.textOverflow

    ctx.states.setLen(ctx.states.len - 1)

proc createContext*(backendContext: BackendContext,
    fontCollection: FontCollection, textBlobCache: TextBlobCache,
    textLayoutContext: TextLayoutContext,
    textRenderContext: TextRenderContext): Context =
  result = Context()
  result.backendContext = backendContext
  result.fontCollection = fontCollection
  result.textBlobCache = textBlobCache
  result.textLayoutContext = textLayoutContext
  result.textRenderContext = textRenderContext
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
  ctx.transform.premultiply(v)

proc fillPath*(ctx: Context, path: Path) =
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  let contours = ctx.cache.expandFill(ctx.distTolSq)

  var paint = ctx.fillStyle
  paint.transform.multiply(ctx.transform)
  paint.innerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.innerColor.a))
  paint.outerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.outerColor.a))

  ctx.backendContext.drawContours(
    paint,
    contours.toOpenArray,
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
    s = getAverageScale(ctx.transform)
    strokeWidth = max(ctx.strokeWidth * s, 0.01)

  var paint = ctx.strokeStyle
  paint.transform.multiply(ctx.transform)
  paint.innerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.innerColor.a))
  paint.outerColor.a = uint8(clamp(ctx.globalAlpha, 0, 1) * float32(
      paint.outerColor.a))

  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  if len(ctx.dashArray) > 0 and ctx.dashArray[0] > 0:
    ctx.cache.dashStroke(s, strokeWidth, ctx.dashOffset, ctx.dashArray)

  let contours = ctx.cache.expandStroke(
    ctx.lineCap, ctx.lineJoin, strokeWidth, ctx.miterLimit,
    ctx.tessTolSq, ctx.distTolSq
  )

  ctx.backendContext.drawContours(
    paint,
    contours.toOpenArray,
    NonZero,
    ctx.compositeOperation,
  )

proc flush*(ctx: Context) {.inline.} =
  ctx.textLayoutContext.flush()
  ctx.textRenderContext.flush()
  ctx.backendContext.flush()

  ctx.states.setLen(0)
  ctx.resetState()

  ctx.textBlobCache.compact()

proc beginPath*(ctx: Context) {.inline.} =
  ctx.path.clear()

proc rect*(ctx: Context, xywh: Vec4) {.inline.} =
  ctx.path.rect(xywh)

proc arc*(ctx: Context, cp: Vec2, r, a0, a1: float32, ccw: bool) =
  ctx.path.arc(cp, r, a0, a1, ccw)

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
  result.transform.dx = xywh[0]
  result.transform.dy = xywh[1]
  result.extent[0] = xywh[2]
  result.extent[1] = xywh[3]
  result.imageId = imageId

  let a8 = uint8(clamp(alpha, 0, 1) * 255)
  result.innerColor = color(255, 255, 255, a8)
  result.outerColor = color(255, 255, 255, a8)

proc getImageInfo*(ctx: Context, imageId: ImageId): ImageInfo {.inline.} =
  ctx.backendContext.getImageInfo(imageId)

proc loadFontFromMemory*(ctx: Context, name: string, buffer: seq[byte],
    fontFamily: FontFamily): FontId =
  if ctx.fontCollection.isNil or ctx.textBlobCache.isNil or
      ctx.textLayoutContext.isNil or ctx.textRenderContext.isNil:
    return

  ctx.fontCollection.loadFromMemory(name, buffer, fontFamily)

proc createTextBlob*(ctx: Context, text: openArray[char]): TextBlob =
  if ctx.fontCollection.isNil or ctx.textBlobCache.isNil or
      ctx.textLayoutContext.isNil or ctx.textRenderContext.isNil:
    return

  result = ctx.textLayoutContext.createTextBlob(ctx.fontCollection,
      ctx.textAttribs, text)

proc fillText*(ctx: Context, text: openArray[char], pos: Vec2) =
  if ctx.fontCollection.isNil or ctx.textBlobCache.isNil or
      ctx.textLayoutContext.isNil or ctx.textRenderContext.isNil:
    return

  ctx.textRenderContext.fillText(ctx.textLayoutContext, ctx.textBlobCache,
      ctx.fontCollection, ctx.textAttribs, text, pos, ctx.transform)

proc fillTextBlob*(ctx: Context, textBlob: TextBlob, pos: Vec2) =
  if ctx.fontCollection.isNil or ctx.textBlobCache.isNil or
      ctx.textLayoutContext.isNil or ctx.textRenderContext.isNil:
    return

  ctx.textRenderContext.fillTextBlob(textBlob, pos, ctx.transform)
