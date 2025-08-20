import ./cache
import ./core
import ./fontstash
import ./math
import ./opentype
import ./params
import ./path

import std/math

when defined(NVG_DEBUG_CORE):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

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
    transform: Mat3

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
    transform: Mat3

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

    tessTol: float32
    distTol: float32
    distTolSq: float32
    devicePxRatio: float32

    cache: Cache
    states: seq[ContextState]

    # stats
    drawCallCount: int

    # flush texture
    textureDirty: bool

proc resetState(ctx: Context) =
  ctx.fillRule = NonZero
  ctx.fillStyle = color(1, 1, 1, 1)
  ctx.strokeStyle = color(0, 0, 0, 1)

  ctx.compositeOperation = CompositeOperation.SOURCE_OVER_OPERATION
  ctx.strokeWidth = 1
  ctx.miterLimit = 10
  ctx.lineCap = ButtCap
  ctx.lineJoin = MiterJoin
  ctx.dashArray.setLen(0)
  ctx.dashOffset = 0
  ctx.globalAlpha = 1
  ctx.transform = mat3()

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
  ctx.transform = mat3()

proc getTransform*(ctx: Context): Mat3 =
  ctx.transform

proc loadFontFromMemory*(ctx: Context, data: sink seq[byte]): FontId =
  if ctx.fons.isNil:
    ctx.fons = FonsStash()

  FontId(ctx.fons.loadFontFromMemory(data))

proc loadFontFromMemory*(ctx: Context, data: openArray[byte]): FontId =
  if ctx.fons.isNil:
    ctx.fons = FonsStash()

  FontId(ctx.fons.loadFontFromMemory(data))

proc fillPath*(ctx: Context, path: Path) =
  when defined(NVG_DEBUG_CORE):
    printf("fill begin\n")

  ctx.cache.clear()
  ctx.cache.flattenPaths(path, ctx.transform, ctx.tessTol, ctx.distTolSq)
  ctx.cache.expandFill(ctx.distTolSq)

  var contourFlags = default(set[ContourFlags])
  if ctx.fillRule == FillRule.EvenOdd:
    contourFlags.incl(ContourFlags.EvenOdd)

  ctx.params.fillImpl(
    ctx.ctx, ctx.fillStyle, ctx.compositeOperation, contourFlags, ctx.cache.bounds,
    ctx.cache.contours,
  )

  when defined(NVG_DEBUG_CORE):
    printf("fill end\n")

  for idx in 0 ..< ctx.cache.contours.len:
    inc ctx.drawCallCount, 2

proc getAverageScale(t: Mat3): float32 {.inline.} =
  let
    sx = sqrt(t[0] * t[0] + t[3] * t[3])
    sy = sqrt(t[1] * t[1] + t[4] * t[4])

  (sx + sy) * 0.5

proc strokePath*(ctx: Context, path: Path) =
  let
    s = getAverageScale(ctx.transform)
    strokeWidth = clamp(ctx.strokeWidth * s, 1, 200)

  var paint = ctx.strokeStyle
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  when defined(NVG_DEBUG_CORE):
    printf("stroke begin\n")

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

  when defined(NVG_DEBUG_CORE):
    printf("stroke end\n")

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

  let font = ctx.fons.getFontById(FonsFontId(ctx.fontId))
  if font.isNil:
    return

  ctx.fons.measureText(font, text, ctx.fontSize, ctx.letterSpacing)

proc textToPath*(ctx: Context, text: openArray[char], pos: Vec2): Path =
  if ctx.fons.isNil:
    return

  let font = ctx.fons.getFontById(FonsFontId(ctx.fontId))
  if font.isNil:
    return

  let scale = ctx.fontSize / float32(font.metrics.ascender - font.metrics.descender)

  when defined(NVG_DEBUG_CORE):
    printf(
      "fontSize: %.6f scale: %.6f fonsAlign: %u\n", ctx.fontSize, scale, ctx.fonsAlign
    )

  for x, y, glyph in ctx.fons.arrange(
    font, text, pos[0], pos[1], ctx.fonsAlign, ctx.fontSize, ctx.letterSpacing
  ):
    let points = ctx.fons.getGlyphShape(glyph)

    when defined(NVG_DEBUG_CORE):
      printf("glyph: %u x: %.6f y: %.6f\n", glyph.unicodeCodepoint, x, y)
      printf("len(points): %u\n", len(points))

      for idx in 0 ..< len(points):
        let p = points[idx].addr

        if p.tp == uint8(GlyphShapeCommand.MOVE):
          printf("%d %d %d %d\n", int32(idx), int32(p.tp), int32(p.x), int32(p.y))
        elif p.tp == uint8(GlyphShapeCommand.LINE):
          printf("%d %d %d %d\n", int32(idx), int32(p.tp), int32(p.x), int32(p.y))
        elif p.tp == uint8(GlyphShapeCommand.BEZIER):
          printf(
            "%d %d %d %d %d %d\n",
            int32(idx),
            int32(p.tp),
            int32(p.x),
            int32(p.y),
            int32(p.cx),
            int32(p.cy),
          )

    if len(points) <= 0:
      continue

    var matrix = mat3()
    matrix.translate(vec2(x, y))
    matrix.scale(vec2(scale, -scale))

    for idx in 0 ..< points.len:
      let vert = points[idx].addr

      if vert.tp == uint8(GlyphShapeCommand.MOVE):
        let p1 = matrix * vec2(float32(vert.x), float32(vert.y))
        result.moveTo(p1)

        if idx <= 0:
          result.restart()

      elif vert.tp == uint8(GlyphShapeCommand.LINE):
        let p1 = matrix * vec2(float32(vert.x), float32(vert.y))
        result.lineTo(p1)

      elif vert.tp == uint8(GlyphShapeCommand.BEZIER):
        let
          p1 = matrix * vec2(float32(vert.x), float32(vert.y))
          p2 = matrix * vec2(float32(vert.cx), float32(vert.cy))

        result.quadCurveTo(p2, p1)
