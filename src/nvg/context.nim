import ./altas
import ./cache
import ./core
import ./fontstash
import ./math
import ./opentype
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
    fontBlur: float32
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
    fontBlur*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    fontId*: FontId

    #
    ctx: pointer
    params: BackendContextParams

    fons*: FonsStash
    altas*: Altas
    altasImages: seq[ImageId]

    tessTol: float32
    tessTolSq: float32
    distTol: float32
    distTolSq: float32
    devicePxRatio: float32

    cache: Cache
    states: seq[ContextState]

    path: Path

    # stats
    drawCallCount: int

    # flush texture
    textureDirty: bool

proc `=destroy`(ctx: ContextObj) =
  ctx.params.destroyImpl(ctx.ctx)
  echo "here"

proc resetState(ctx: Context) =
  ctx.fillRule = NonZero
  ctx.fillStyle = color(1, 1, 1, 1)
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
  ctx.fontSize = 16
  ctx.letterSpacing = 0
  ctx.lineHeight = 16
  ctx.fontBlur = 0
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
  result.fontBlur = ctx.fontBlur
  result.textAlign = ctx.textAlign
  result.textBaseline = ctx.textBaseline
  result.fontId = ctx.fontId

proc save*(ctx: Context) =
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
    ctx.fontBlur = state.fontBlur
    ctx.textAlign = state.textAlign
    ctx.textBaseline = state.textBaseline
    ctx.fontId = state.fontId

    ctx.states.setLen(ctx.states.len - 1)

proc createInternal*(params: BackendContextParams): Context =
  assert(params.createImpl != nil)

  result = Context()
  result.params = params
  result.ctx = params.createImpl()
  result.resetState()
  result.setDevicePixelRatio(1)

proc translate*(ctx: Context, v: Vec2) =
  ctx.transform.translate(v)

proc scale*(ctx: Context, v: Vec2) =
  ctx.transform.scale(v)

proc rotate*(ctx: Context, v: float32) =
  ctx.transform.rotate(v)

proc resetTransform*(ctx: Context) =
  ctx.transform = mat2d()

proc getTransform*(ctx: Context): Mat2d =
  ctx.transform

proc loadFontFromMemory*(ctx: Context, data: sink seq[byte]): FontId =
  if ctx.fons.isNil:
    ctx.fons = FonsStash()
    ctx.altas = Altas()

  cast[FontId](ctx.fons.loadFontFromMemory(data))

proc loadFontFromMemory*(ctx: Context, data: openArray[byte]): FontId =
  if ctx.fons.isNil:
    ctx.fons = FonsStash()
    ctx.altas = Altas()

  cast[FontId](ctx.fons.loadFontFromMemory(data))

proc fillPath*(ctx: Context, path: Path) =
  ctx.cache.clear()
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTol, ctx.distTolSq)
  ctx.cache.expandFill(ctx.distTolSq)

  var contourFlags = default(set[ContourFlags])
  if ctx.fillRule == FillRule.EvenOdd:
    contourFlags.incl(ContourFlags.EvenOdd)

  ctx.params.fillImpl(
    ctx.ctx, ctx.fillStyle, ctx.compositeOperation, contourFlags,
    ctx.cache.bounds,
    ctx.cache.contours,
  )

  for idx in 0 ..< ctx.cache.contours.len:
    inc ctx.drawCallCount, 2

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
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTol, ctx.distTolSq)

  if len(ctx.dashArray) > 0 and ctx.dashArray[0] > 0:
    ctx.cache.dashStroke(s, strokeWidth, ctx.dashOffset, ctx.dashArray)

  ctx.cache.expandStroke(
    ctx.lineCap, ctx.lineJoin, strokeWidth, ctx.miterLimit, ctx.tessTol, ctx.distTolSq
  )

  ctx.params.fillImpl(
    ctx.ctx,
    ctx.strokeStyle,
    ctx.compositeOperation,
    default(set[ContourFlags]),
    ctx.cache.bounds,
    ctx.cache.contours,
  )

  for idx in 0 ..< ctx.cache.contours.len:
    inc ctx.drawCallCount, 2

proc begin*(ctx: Context, view: Vec2, devicePixelRatio: float32) =
  ctx.states.setLen(0)
  ctx.resetState()

  ctx.setDevicePixelRatio(devicePixelRatio)

  ctx.params.viewportImpl(ctx.ctx, view, devicePixelRatio)

  ctx.drawCallCount = 0

proc flush*(ctx: Context) =
  ctx.params.flushImpl(ctx.ctx)
  ctx.altas.clear()

proc beginPath*(ctx: Context) {.inline.} =
  ctx.path.clear()

proc rectXYWH*(ctx: Context, rect: Vec4) {.inline.} =
  ctx.path.rectXYWH(rect)

proc rectLTRB*(ctx: Context, rect: Vec4) {.inline.} =
  ctx.path.rectLTRB(rect)

proc arc*(ctx: Context, cp: Vec2, r, a0, a1: float32, ccw: bool) =
  ctx.path.arc(cp, r, a0, a1, ccw)

proc ellipse*(ctx: Context, c: Vec2, rx, ry: float32) {.inline.} =
  ctx.path.ellipse(c, rx, ry)

proc circle*(ctx: Context, c: Vec2, r: float32) {.inline.} =
  ctx.path.circle(c, r)

proc moveTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.moveTo(pos)

proc lineTo*(ctx: Context, pos: Vec2) {.inline.} =
  ctx.path.lineTo(pos)

proc bezierTo*(ctx: Context, cp1, cp2, to: Vec2) {.inline.} =
  ctx.path.bezierTo(cp1, cp2, to)

proc quadCurveTo*(ctx: Context, cp, to: Vec2) {.inline.} =
  ctx.path.quadCurveTo(cp, to)

proc arcTo*(ctx: Context, a, b: Vec2, r: float32) =
  ctx.path.arcTo(a, b, r)

proc closePath*(ctx: Context) {.inline.} =
  ctx.path.closePath()

proc fill*(ctx: Context) {.inline.} =
  ctx.fillPath(ctx.path)

proc stroke*(ctx: Context) {.inline.} =
  ctx.strokePath(ctx.path)

proc fonsAlign(ctx: Context): uint32 {.inline.} =
  case ctx.textAlign
  of LeftAlign:
    result = result or FONS_ALIGN_LEFT
  of CenterAlign:
    result = result or FONS_ALIGN_CENTER
  of RightAlign:
    result = result or FONS_ALIGN_RIGHT

  case ctx.textBaseline
  of TopBaseline:
    result = result or FONS_ALIGN_TOP
  of MiddleBaseline:
    result = result or FONS_ALIGN_MIDDLE
  of AlphabeticBaseline:
    result = result or FONS_ALIGN_BASELINE
  of BottomBaseline:
    result = result or FONS_ALIGN_BOTTOM

proc measureText*(ctx: Context, text: openArray[char]): float32 =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(FonsFontId(ctx.fontId))
  if font.isNil:
    return

  ctx.fons.measureText(font, text, ctx.fontSize, ctx.letterSpacing)

proc textToPath*(ctx: Context, text: openArray[char], pos: Vec2): Path =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(FonsFontId(ctx.fontId))
  if font.isNil:
    return

  let scale = font.getPixelHeightScale(ctx.fontSize)

  for x, y, glyph in ctx.fons.arrange(
    font, text, pos[0], pos[1], ctx.fonsAlign, ctx.fontSize, ctx.letterSpacing
  ):
    let points = ctx.fons.getGlyphShape(glyph)
    if len(points) <= 0:
      continue

    var matrix = [scale, 0, 0, -scale, x, y]
    matrix.multiply(ctx.transform)

    for idx in 0 ..< points.len:
      let vert = points[idx].addr

      if vert.tp == uint8(GlyphShapeCommand.MOVE):
        let p1 = matrix * vec2(float32(vert.x), float32(vert.y))
        result.moveTo(p1)

        if idx <= 0:
          result.appendCommands([float32(PathCommand.RESTART)])

      elif vert.tp == uint8(GlyphShapeCommand.LINE):
        let p1 = matrix * vec2(float32(vert.x), float32(vert.y))
        result.lineTo(p1)

      elif vert.tp == uint8(GlyphShapeCommand.BEZIER):
        let
          p1 = matrix * vec2(float32(vert.x), float32(vert.y))
          p2 = matrix * vec2(float32(vert.cx), float32(vert.cy))

        result.quadCurveTo(p2, p1)

proc text*(ctx: Context, text: openArray[char], pos: Vec2) =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFont(FonsFontId(ctx.fontId))
  if font.isNil:
    return

  let
    altas = ctx.altas
    scale = 96 / ctx.fontSize

  if altas.storage.len <= 0:
    altas.expand(512, 512)

  var
    rev = default(int32)
    image = default(ImageId)
    verts = newSeqOfCap[Vec4](text.len * 6)

    vertBuf: array[6, Vec4]

  if ctx.altasImages.len > 0:
    image = ctx.altasImages[0]
  else:
    image = ctx.params.createTextureImpl(
      ctx.ctx,
      TextureAlpha,
      altas.width,
      altas.height,
      {ImageExternalStorage},
      altas.storage[0].addr
    )

    ctx.altasImages.add(image)

  if ctx.transform[0] * ctx.transform[3] < 0:
    rev = 1

  for x, y, glyph in ctx.fons.arrange(
    font, text, pos[0], pos[1], ctx.fonsAlign, ctx.fontSize, ctx.letterSpacing
  ):
    let
      cell = ctx.fons.addGlyphToAltas(glyph, altas)
      quad = ctx.fons.getGlyphQuad(glyph, x, y, altas, cell, ctx.fontSize, 0)

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

  var paint = ctx.fillStyle
  paint.transform[0] = length(vec2(ctx.transform[0], ctx.transform[2])) / scale
  paint.transform[3] = length(vec2(ctx.transform[1], ctx.transform[3])) / scale
  paint.extent = vec2(96, 96)
  paint.image = image
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a
  paint.radius = ctx.fontBlur

  let
    x = altas.dirtyRect[0]
    y = altas.dirtyRect[1]
    w = altas.dirtyRect[2] - x
    h = altas.dirtyRect[3] - y

  if w > 0 and h > 0:
    ctx.params.markTextureDirtyImpl(
      ctx.ctx,
      image,
      x, y, w, h,
    )

  ctx.params.trianglesImpl(
    ctx.ctx,
    paint,
    ctx.compositeOperation,
    verts,
  )
