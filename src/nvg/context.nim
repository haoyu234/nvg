import ./backend
import ./cache
import ./core
import ./fontstash
import ./math
import ./path

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
    fontSize: float32
    letterSpacing: float32
    lineHeight: float32
    textAlign: HorizontalAlignment
    textBaseline: BaselineAlignment
    fontId: FontId

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
    fontSize*: float32
    letterSpacing*: float32
    lineHeight*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    fontId*: FontId

    #
    fons*: FonsStash
    backendContext*: BackendContext

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
  ctx.fillStyle = color(0, 0, 0, 1)
  ctx.strokeStyle = color(0, 0, 0, 1)

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
  ctx.fontSize = 32
  ctx.letterSpacing = 0
  ctx.lineHeight = 16
  ctx.textAlign = LeftAlign
  ctx.textBaseline = AlphabeticBaseline
  ctx.fontId = default(FontId)

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

  result.fontSize = ctx.fontSize
  result.letterSpacing = ctx.letterSpacing
  result.lineHeight = ctx.lineHeight
  result.textAlign = ctx.textAlign
  result.textBaseline = ctx.textBaseline
  result.fontId = ctx.fontId

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

    ctx.fontSize = state.fontSize
    ctx.letterSpacing = state.letterSpacing
    ctx.lineHeight = state.lineHeight
    ctx.textAlign = state.textAlign
    ctx.textBaseline = state.textBaseline
    ctx.fontId = state.fontId

    ctx.states.setLen(ctx.states.len - 1)

proc createInternal*(fons: FonsStash, backendContext: BackendContext): Context =
  result = Context()
  result.fons = fons
  result.backendContext = backendContext
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

proc loadFontFromMemory*(ctx: Context, data: sink seq[
    byte]): FontId {.inline.} =
  if ctx.fons.isNil:
    return

  ctx.fons.loadFontFromMemory(data)

proc loadFontFromMemory*(ctx: Context, data: openArray[
    byte]): FontId {.inline.} =
  if ctx.fons.isNil:
    return

  ctx.fons.loadFontFromMemory(data)

proc fillPath*(ctx: Context, path: Path) =
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)
  ctx.cache.expandFill(ctx.distTolSq)

  var paint = ctx.fillStyle
  paint.transform.multiply(ctx.transform)
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  ctx.backendContext.renderContour(
    paint,
    ctx.cache.contours,
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
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  if len(ctx.dashArray) > 0 and ctx.dashArray[0] > 0:
    ctx.cache.dashStroke(s, strokeWidth, ctx.dashOffset, ctx.dashArray)

  ctx.cache.expandStroke(
    ctx.lineCap, ctx.lineJoin, strokeWidth, ctx.miterLimit,
    ctx.tessTolSq, ctx.distTolSq
  )

  ctx.backendContext.renderContour(
    paint,
    ctx.cache.contours,
    NonZero,
    ctx.compositeOperation,
  )

proc flush*(ctx: Context) {.inline.} =
  ctx.backendContext.flush()

  ctx.states.setLen(0)
  ctx.resetState()

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
  result.innerColor = color(1, 1, 1, alpha)
  result.outerColor = color(1, 1, 1, alpha)

proc getImageInfo*(ctx: Context, imageId: ImageId): ImageInfo {.inline.} =
  ctx.backendContext.getImageInfo(imageId)

proc measureText*(ctx: Context, text: openArray[char]): float32 =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(ctx.fontId)
  if font.isNil:
    return

  ctx.fons.measureText(font, text, ctx.fontSize, ctx.letterSpacing)

proc text*(ctx: Context, text: openArray[char], pos: Vec2) =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(ctx.fontId)
  if font.isNil:
    return

  let scale = font.getPixelHeightScale(ctx.fontSize)

  for x, y, glyphId in ctx.fons.arrange(
    font, text, pos[0], pos[1], ctx.textAlign, ctx.textBaseline, ctx.fontSize,
        ctx.letterSpacing
  ):
    let glyph = font.getGlyph(glyphId)
    if glyph.isNil:
      continue

    let path = font.getGlyphPath(glyph)
    if path.empty:
      continue

    let matrix = mat2d(scale, 0, 0, -scale, x, y)
    ctx.path.addPath(path, multiplied(matrix, ctx.transform))

proc fillText*(ctx: Context, text: openArray[char], pos: Vec2) =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(ctx.fontId)
  if font.isNil:
    return

  var
    rev = default(int32)
    verts = newSeqOfCap[Vec4](text.len * 4)
    vertBuf: array[4, Vec4]

  if ctx.transform.xx * ctx.transform.yy < 0:
    rev = 2

  var paint = default(Paint)
  paint.innerColor = ctx.fillStyle.innerColor
  paint.outerColor = ctx.fillStyle.outerColor
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  for x, y, glyphId in ctx.fons.arrange(
    font, text, pos[0], pos[1], ctx.textAlign, ctx.textBaseline, ctx.fontSize,
        ctx.letterSpacing
  ):
    let glyph = font.getGlyph(glyphId)
    if glyph.isNil:
      continue

    let quad = ctx.fons.getGlyphQuad(glyph, x, y, ctx.fontSize)
    if quad.imageId.isNil:
      continue

    if not paint.imageId.isNil:
      if paint.imageId != quad.imageId:
        ctx.backendContext.renderSdf(
          paint,
          verts,
          ctx.compositeOperation,
        )

        verts.setLen(0)

    paint.imageId = quad.imageId

    let
      p1 = vec2(quad.x1, quad.y1) * ctx.transform
      p2 = vec2(quad.x2, quad.y1) * ctx.transform
      p3 = vec2(quad.x2, quad.y2) * ctx.transform
      p4 = vec2(quad.x1, quad.y2) * ctx.transform

    vertBuf[0] = vec4(p3, vec2(quad.s2, quad.t2))
    vertBuf[1 + rev] = vec4(p2, vec2(quad.s2, quad.t1))
    vertBuf[2] = vec4(p1, vec2(quad.s1, quad.t1))
    vertBuf[3 - rev] = vec4(p4, vec2(quad.s1, quad.t2))

    verts.add(vertBuf)

  if verts.len > 0:
    ctx.backendContext.renderSdf(
      paint,
      verts,
      ctx.compositeOperation,
    )
