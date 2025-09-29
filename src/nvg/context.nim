import ./atlas
import ./cache
import ./core
import ./fontstash
import ./math
import ./params
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
    ctx*: pointer
    params*: BackendContextParams

    fons*: FonsStash
    atlas*: Atlas

    tessTol: float32
    tessTolSq: float32
    distTol: float32
    distTolSq: float32
    devicePxRatio: float32

    cache: Cache
    states: seq[ContextState]

    path: Path

proc `=destroy`(ctx: var ContextObj) =
  `=destroy`(ctx.dashArray)
  `=destroy`(ctx.cache)
  `=destroy`(ctx.states)
  `=destroy`(ctx.path)

  reset(ctx.fons)
  reset(ctx.atlas)

  if not ctx.params.destroyImpl.isNil:
    ctx.params.destroyImpl(ctx.ctx)

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

proc setDevicePixelRatio(ctx: Context, ratio: float32) {.inline.} =
  ctx.tessTol = 0.25 / ratio
  ctx.distTol = 0.01 / ratio
  ctx.tessTolSq = ctx.tessTol * ctx.tessTol
  ctx.distTolSq = ctx.distTol * ctx.distTol
  ctx.devicePxRatio = ratio

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

proc createInternal*(ctx: pointer, params: BackendContextParams): Context =
  if not params.initImpl.isNil:
    params.initImpl(ctx)

  result = Context()
  result.params = params
  result.ctx = ctx
  result.resetState()
  result.setDevicePixelRatio(1)

  result.atlas = createAtlas(2048, 2048)
  result.fons = createFonsStash(TopLeftOrigin, result.atlas)

proc translate*(ctx: Context, v: Vec2) {.inline.} =
  ctx.transform.translate(v)

proc scale*(ctx: Context, v: Vec2) {.inline.} =
  ctx.transform.scale(v)

proc rotate*(ctx: Context, v: float32) {.inline.} =
  ctx.transform.rotate(v)

proc resetTransform*(ctx: Context) {.inline.} =
  ctx.transform = mat2d()

proc getTransform*(ctx: Context): lent Mat2d {.inline.} =
  ctx.transform

proc loadFontFromMemory*(ctx: Context, data: sink seq[
    byte]): FontId {.inline.} =
  cast[FontId](ctx.fons.loadFontFromMemory(data))

proc loadFontFromMemory*(ctx: Context, data: openArray[
    byte]): FontId {.inline.} =
  cast[FontId](ctx.fons.loadFontFromMemory(data))

proc fillPath*(ctx: Context, path: Path) =
  ctx.cache.clear()
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)
  ctx.cache.expandFill(ctx.distTolSq)

  var renderFlags = default(set[RenderFlags])
  if ctx.fillRule == FillRule.EvenOdd:
    renderFlags.incl(RenderFlags.EvenOdd)

  var paint = ctx.fillStyle
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  if not ctx.params.fillImpl.isNil:
    ctx.params.fillImpl(
      ctx.ctx, paint, ctx.compositeOperation, renderFlags,
      ctx.cache.bounds,
      ctx.cache.contours,
    )

proc getAverageScale(t: Mat2d): float32 {.inline.} =
  let
    sx = sqrt(t[0] * t[0] + t[2] * t[2])
    sy = sqrt(t[1] * t[1] + t[3] * t[3])

  (sx + sy) * 0.5

proc strokePath*(ctx: Context, path: Path) =
  let
    s = getAverageScale(ctx.transform)
    strokeWidth = clamp(ctx.strokeWidth * s, 1, 200)

  var paint = ctx.strokeStyle
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  ctx.cache.clear()
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTolSq, ctx.distTolSq)

  if len(ctx.dashArray) > 0 and ctx.dashArray[0] > 0:
    ctx.cache.dashStroke(s, strokeWidth, ctx.dashOffset, ctx.dashArray)

  ctx.cache.expandStroke(
    ctx.lineCap, ctx.lineJoin, strokeWidth, ctx.miterLimit, ctx.tessTolSq, ctx.distTolSq
  )

  if not ctx.params.fillImpl.isNil:
    ctx.params.fillImpl(
      ctx.ctx,
      ctx.strokeStyle,
      ctx.compositeOperation,
      default(set[RenderFlags]),
      ctx.cache.bounds,
      ctx.cache.contours,
    )

proc begin*(ctx: Context, view: Vec2, devicePixelRatio: float32) =
  ctx.states.setLen(0)
  ctx.resetState()

  ctx.setDevicePixelRatio(devicePixelRatio)

  if not ctx.params.viewportImpl.isNil:
    ctx.params.viewportImpl(ctx.ctx, view, devicePixelRatio)

  ctx.atlas.compact()

proc flush*(ctx: Context) =
  if not ctx.params.flushImpl.isNil:
    ctx.params.flushImpl(ctx.ctx)

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

    let matrix = [scale, 0, 0, -scale, x, y]
    ctx.path.addPath(path, multiplied(matrix, ctx.transform))

proc fillText*(ctx: Context, text: openArray[char], pos: Vec2) =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(ctx.fontId)
  if font.isNil:
    return

  var
    rev = default(int32)
    verts = newSeqOfCap[Vec4](text.len * 6)

    vertBuf: array[6, Vec4]

  if ctx.transform[0] * ctx.transform[3] < 0:
    rev = 1

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
    if quad.image.isNil:
      continue

    if not paint.image.isNil:
      if paint.image != quad.image:
        if not ctx.params.trianglesImpl.isNil:
          ctx.params.trianglesImpl(
            ctx.ctx,
            paint,
            ctx.compositeOperation,
            default(set[RenderFlags]),
            verts,
          )

          verts.setLen(0)

    paint.image = quad.image

    let
      p1 = ctx.transform * vec2(quad.x1, quad.y1)
      p2 = ctx.transform * vec2(quad.x2, quad.y1)
      p3 = ctx.transform * vec2(quad.x2, quad.y2)
      p4 = ctx.transform * vec2(quad.x1, quad.y2)

    vertBuf[0] = vec4(p1, vec2(quad.s1, quad.t1))
    vertBuf[1 + rev] = vec4(p3, vec2(quad.s2, quad.t2))
    vertBuf[2 - rev] = vec4(p2, vec2(quad.s2, quad.t1))
    vertBuf[3] = vec4(p1, vec2(quad.s1, quad.t1))
    vertBuf[4 + rev] = vec4(p4, vec2(quad.s1, quad.t2))
    vertBuf[5 - rev] = vec4(p3, vec2(quad.s2, quad.t2))

    verts.add(vertBuf)

  if verts.len > 0:
    if not ctx.params.trianglesImpl.isNil:
      ctx.params.trianglesImpl(
        ctx.ctx,
        paint,
        ctx.compositeOperation,
        default(set[RenderFlags]),
        verts,
      )
