import vmath
import chroma

import std/math
import std/algorithm

import ./seqs
import ./slice2
import ./params

when defined(NVG_DEBUG_CORE):
  proc printf*(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

const
  MAX_STATES = 32
  INIT_COMMANDS_SIZE = 256
  INIT_POINTS_SIZE = 256
  INIT_PATH_SIZE = 16
  INIT_VERTS_SIZE = 26
  KAPPA90 = float32(4.0 * (sqrt(2.0) - 1.0) / 3.0)

type
  LineCap* = enum
    ButtCap
    RoundCap
    SquareCap

  LineJoin* = enum
    MiterJoin
    RoundJoin
    BevelJoin

  HorizontalAlignment* = enum
    LeftAlign
    CenterAlign
    RightAlign

  BaselineAlignment* = enum
    TopBaseline
    MiddleBaseline
    AlphabeticBaseline
    BottomBaseline

  Command = enum
    MOVE_TO
    LINE_TO
    BEZIER_TO
    CLOSE

  PointFlags* = object
    corner: bool
    left: bool
    bevel: bool
    innerBevel: bool

  PointObj = object
    pos: Vec2
    dpos: Vec2
    dmpos: Vec2
    len: float32
    flags: PointFlags

  StateObj = object
    compositeOperation: CompositeOperation
    fill: Paint
    stroke: Paint
    strokeWidth: float32
    miterLimit: float32
    lineJoin: LineJoin
    lineCap: LineCap
    globalAlpha: float32
    transform: Mat3

    # font StateObj
    fontSize: float32
    letterSpacing: float32
    lineHeight: float32
    fontBlur: float32
    textAlign: HorizontalAlignment
    textBaseline: BaselineAlignment
    fontId: int

  ContourCacheObj = object
    points: seq[PointObj]
    contours: seq[ContourObj]
    verts: seq[Vec4]
    lastPoint: ptr PointObj
    lastContour: ptr ContourObj
    bounds: Vec4

  ContextObj* = object
    ctx: pointer
    params: BackendContextParams

    commands: seq[float32]
    commandXY: Vec2
    state: array[MAX_STATES, StateObj]
    stateCount: int
    lastState: ptr StateObj
    cache: ContourCacheObj
    tessTol: float32
    distTol: float32
    distTolSq: float32
    devicePxRatio: float32

    # stats
    drawCallCount: int
    fillTriCount: int
    strokeTriCount: int
    textTriCount: int

    # flush texture
    textureDirty: bool

proc setDevicePixelRatio(ctx: ptr ContextObj, ratio: float32) =
  ctx.tessTol = 0.25 / ratio
  ctx.distTol = 0.01 / ratio
  ctx.distTolSq = ctx.distTol * ctx.distTol
  ctx.devicePxRatio = ratio

proc save*(ctx: ptr ContextObj) =
  if ctx.stateCount >= MAX_STATES:
    assert false

  if ctx.stateCount > 0:
    ctx.state[ctx.stateCount] = ctx.state[ctx.stateCount - 1]

  ctx.lastState = ctx.state[ctx.stateCount].addr
  inc ctx.stateCount

proc restore*(ctx: ptr ContextObj) =
  if ctx.stateCount <= 0:
    assert false

  dec ctx.stateCount
  if ctx.stateCount > 0:
    ctx.lastState = ctx.state[ctx.stateCount - 1].addr
  else:
    ctx.lastState = nil

proc setColor(p: var Paint, color: Color) =
  p.transform = mat3()
  p.extent = vec2(0, 0)
  p.radius = 0
  p.feather = 1
  p.innerColor = color
  p.outerColor = color
  p.image = default(ImageId)

proc reset(ctx: ptr ContextObj) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fill.setColor(color(1, 1, 1, 1))
  state.stroke.setColor(color(0, 0, 0, 1))

  state.compositeOperation = CompositeOperation.SOURCE_OVER_OPERATION
  state.strokeWidth = 1
  state.miterLimit = 10
  state.lineCap = ButtCap
  state.lineJoin = MiterJoin
  state.globalAlpha = 1
  state.transform = mat3()

  # font settings
  state.fontSize = 16
  state.letterSpacing = 0
  state.lineHeight = 1
  state.fontBlur = 0
  state.textAlign = LeftAlign
  state.textBaseline = AlphabeticBaseline
  state.fontId = 0

proc createInternal*(params: BackendContextParams): ptr ContextObj =
  assert(params.createImpl != nil)

  let ctx = create(ContextObj)
  ctx.params = params
  ctx.ctx = params.createImpl()

  ctx.commands = newSeqOfCap[float32](INIT_COMMANDS_SIZE)

  ctx.cache.points = newSeqOfCap[PointObj](INIT_POINTS_SIZE)
  ctx.cache.contours = newSeqOfCap[ContourObj](INIT_PATH_SIZE)
  ctx.cache.verts = newSeqOfCap[Vec4](INIT_VERTS_SIZE)

  save(ctx)
  reset(ctx)

  setDevicePixelRatio(ctx, 1)

  ctx

proc setGlobalCompositeOperation*(ctx: ptr ContextObj, operation: CompositeOperation) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.compositeOperation = operation

proc setFillPaint*(ctx: ptr ContextObj, paint: Paint) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fill = paint

proc setFillColor*(ctx: ptr ContextObj, color: Color) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fill.setColor(color)

proc setStrokePaint*(ctx: ptr ContextObj, paint: Paint) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.stroke = paint

proc setStrokeColor*(ctx: ptr ContextObj, color: Color) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.stroke.setColor(color)

proc setStrokeWidth*(ctx: ptr ContextObj, width: float32) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.strokeWidth = width

proc setMiterLimit*(ctx: ptr ContextObj, limit: float32) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.miterLimit = limit

proc setLineCap*(ctx: ptr ContextObj, lineCap: LineCap) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.lineCap = lineCap

proc setLineJoin*(ctx: ptr ContextObj, lineJoin: LineJoin) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.lineJoin = lineJoin

proc setGlobalAlpha*(ctx: ptr ContextObj, globalAlpha: float32) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.globalAlpha = globalAlpha

proc resetTransform*(ctx: ptr ContextObj) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform = mat3()

proc setTransform*(ctx: ptr ContextObj, mat: Mat3) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform = mat

proc getTransform*(ctx: ptr ContextObj): Mat3 =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform

proc translate*(ctx: ptr ContextObj, vec: Vec2) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform = state.transform * translate(vec)

proc rotate*(ctx: ptr ContextObj, angle: float32) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform = state.transform * rotate(angle)

# proc skewX*(ctx: ptr ContextObj, angle: float32) =
#   discard

# proc skewY*(ctx: ptr ContextObj, angle: float32) =
#   discard

proc scale*(ctx: ptr ContextObj, scale: Vec2) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.transform = state.transform * scale(scale)

template appendPos(ctx: ptr ContextObj, pos: Vec2) =
  ctx.commands.add(pos.x)
  ctx.commands.add(pos.y)

proc clear(c: ptr ContourCacheObj) {.inline, raises: [].} =
  if not c.lastPoint.isNil:
    c.points.clear()
    c.contours.clear()

    c.lastPoint = nil
    c.lastContour = nil

proc appendCommands(ctx: ptr ContextObj, values: varargs[float32]) =
  let
    c = ctx.cache.addr
    state = ctx.lastState

  if values.len >= 3:
    ctx.commandXY.x = values[values.len - 2]
    ctx.commandXY.y = values[values.len - 1]

  var i = 0
  while i < values.len:
    let cmd = Command(values[i])
    ctx.commands.add(values[i])

    case cmd
    of Command.MOVE_TO, Command.LINE_TO:
      let pos = state.transform * vec2(values[i + 1], values[i + 2])
      ctx.appendPos(pos)
      inc i, 3
    of Command.BEZIER_TO:
      let pos1 = state.transform * vec2(values[i + 1], values[i + 2])
      let pos2 = state.transform * vec2(values[i + 3], values[i + 4])
      let pos3 = state.transform * vec2(values[i + 5], values[i + 6])
      ctx.appendPos(pos1)
      ctx.appendPos(pos2)
      ctx.appendPos(pos3)
      inc i, 7
    of Command.CLOSE:
      inc i, 1

  c.clear()

proc beginPath*(ctx: ptr ContextObj) =
  ctx.commands.clear()

proc rect*(ctx: ptr ContextObj, rect: Vec4) =
  ctx.appendCommands(
    float32(Command.MOVE_TO),
    rect.x,
    rect.y,
    float32(Command.LINE_TO),
    rect.x,
    rect.y + rect.z,
    float32(Command.LINE_TO),
    rect.x + rect.w,
    rect.y + rect.z,
    float32(Command.LINE_TO),
    rect.x + rect.w,
    rect.y,
    float32(Command.CLOSE),
  )

proc arc*(ctx: ptr ContextObj, cp: Vec2, r, a0, a1: float32, ccw: bool) =
  const
    pi2 = float32(2 * PI)
    pidiv2 = float32(PI / 2)
    s = float32(4) / 3

  var da = a1 - a0
  if not ccw:
    if abs(da) >= pi2:
      da = pi2
    else:
      while da < 0:
        da = da + pi2
  else:
    if abs(da) >= pi2:
      da = -pi2
    else:
      while da > 0:
        da = da - pi2

  let
    ndivs = clamp(int(abs(da) / pidiv2 + 0.5), 1, 5)
    hda = da / float32(ndivs) / 2
    e = da / float32(ndivs)

  var kappa = abs(s * (1 - cos(hda)) / sin(hda))

  if ccw:
    kappa = -kappa

  when defined(NVG_DEBUG_CORE):
    printf("ndivs[%u] hda[%.6f] kappa[%.6f]\n", ndivs, hda, kappa)

  var
    px = float32(0)
    py = float32(0)
    ptanx = float32(0)
    ptany = float32(0)
    a = a0

  for i in 0 .. ndivs:
    let
      dx = cos(a)
      dy = sin(a)
      x = cp.x + dx * r
      y = cp.y + dy * r
      tanx = -dy * r * kappa
      tany = dx * r * kappa

    when defined(NVG_DEBUG_CORE):
      printf(
        "a[%f] dx[%.6f] dy[%.6f] x[%.6f] y[%.6f] tanx[%.6f] tany[%.6f]\n", a, dx, dy, x,
        y, tanx, tany,
      )

    if i > 0:
      ctx.appendCommands(
        float32(Command.BEZIER_TO), px + ptanx, py + ptany, x - tanx, y - tany, x, y
      )
    elif ctx.commands.len > 0:
      ctx.appendCommands(float32(Command.LINE_TO), x, y)
    else:
      ctx.appendCommands(float32(Command.MOVE_TO), x, y)

    px = x
    py = y
    ptanx = tanx
    ptany = tany
    a = a + e

proc ellipse*(ctx: ptr ContextObj, c: Vec2, rx, ry: float32) =
  ctx.appendCommands(
    float32(Command.MOVE_TO),
    c.x - rx,
    c.y,
    float32(Command.BEZIER_TO),
    c.x - rx,
    c.y + ry * KAPPA90,
    c.x - rx * KAPPA90,
    c.y + ry,
    c.x,
    c.y + ry,
    float32(Command.BEZIER_TO),
    c.x + rx * KAPPA90,
    c.y + ry,
    c.x + rx,
    c.y + ry * KAPPA90,
    c.x + rx,
    c.y,
    float32(Command.BEZIER_TO),
    c.x + rx,
    c.y - ry * KAPPA90,
    c.x + rx * KAPPA90,
    c.y - ry,
    c.x,
    c.y - ry,
    float32(Command.BEZIER_TO),
    c.x - rx * KAPPA90,
    c.y - ry,
    c.x - rx,
    c.y - ry * KAPPA90,
    c.x - rx,
    c.y,
    float32(Command.CLOSE),
  )

proc circle*(ctx: ptr ContextObj, c: Vec2, r: float32) =
  ctx.ellipse(c, r, r)

proc moveTo*(ctx: ptr ContextObj, pos: Vec2) =
  ctx.appendCommands(float32(Command.MOVE_TO), pos.x, pos.y)

proc lineTo*(ctx: ptr ContextObj, pos: Vec2) =
  ctx.appendCommands(float32(Command.LINE_TO), pos.x, pos.y)

proc bezierTo*(ctx: ptr ContextObj, cp1, cp2, to: Vec2) =
  ctx.appendCommands(float32(Command.BEZIER_TO), cp1.x, cp1.y, cp2.x, cp2.y, to.x, to.y)

proc quadCurveTo*(ctx: ptr ContextObj, cp, to: Vec2) =
  let pos = ctx.commandXY
  const s = float32(2) / 3

  ctx.appendCommands(
    float32(Command.BEZIER_TO),
    pos.x + s * (cp.x - pos.x),
    pos.y + s * (cp.y - pos.y),
    to.x + s * (cp.x - to.x),
    to.y + s * (cp.y - to.y),
    to.x,
    to.y,
  )

proc cross(p1, p2: Vec2): float32 {.inline, raises: [].} =
  p2.x * p1.y - p1.x * p2.y

proc distSegment(p1, p2, p3: Vec2): float32 {.inline, raises: [].} =
  let
    v32 = p3 - p2
    v12 = p1 - p2

  var
    d = v32.lengthSq
    t = v32.x * v12.x + v32.y * v12.y

  if d > 0:
    t = t / d

  t = clamp(t, 0, 1)

  lengthSq(p2 + t * v32 - p1)

proc equals(a, b: Vec2, distTolSq: float32): bool {.inline.} =
  lengthSq(b - a) < distTolSq

proc arcTo*(ctx: ptr ContextObj, a, b: Vec2, r: float32) =
  if ctx.commands.len == 0:
    assert false

  let pos = ctx.commandXY
  if equals(pos, a, ctx.distTolSq) or equals(a, b, ctx.distTolSq) or
      distSegment(a, pos, b) < ctx.distTolSq or r < ctx.distTol:
    ctx.lineTo(a)
    return

  let
    d0 = normalize(pos - a)
    d1 = normalize(b - a)
    d = r / tan(arccos(dot(d0, d1)) / 2f32)

  if d > 10000:
    ctx.lineTo(a)
    return

  var
    cpx = default(float32)
    cpy = default(float32)
    a0 = default(float32)
    a1 = default(float32)
    ccw = false

  if cross(d0, d1) > 0:
    cpx = a.x + d0.x * d + d0.y * r
    cpy = a.y + d0.y * d - d0.x * r
    a0 = arctan2(d0.x, -d0.y)
    a1 = arctan2(-d1.x, d1.y)
    ccw = false
  else:
    cpx = a.x + d0.x * d - d0.y * r
    cpy = a.x + d0.y * d + d0.x * r
    a0 = arctan2(-d0.x, d0.y)
    a1 = arctan2(d1.x, -d1.y)
    ccw = true

  ctx.arc(vec2(cpx, cpy), r, a0, a1, ccw)

proc closePath*(ctx: ptr ContextObj) =
  ctx.appendCommands(float32(Command.CLOSE))

proc createContour(c: ptr ContourCacheObj): ptr ContourObj {.inline, raises: [].} =
  let idx = c.contours.len
  c.contours.setLen(idx + 1)

  let p = c.contours[idx].addr
  c.lastContour = p

  p.offset = int32(c.points.len)
  p.ccw = true
  p

proc createPoint(c: ptr ContourCacheObj): ptr PointObj {.inline, raises: [].} =
  inc c.lastContour.pointCount, 1

  let idx = c.points.len
  c.points.setLen(idx + 1)

  let p = c.points[idx].addr
  c.lastPoint = p
  p

proc bezier(
    c: ptr ContourCacheObj,
    p0: ptr PointObj,
    cp1, cp2, p3: Vec2,
    level: int,
    pointFlags: PointFlags,
    tessTol, distTolSq: float32,
) =
  let
    p12 = (p0.pos + cp1) / 2
    p23 = (cp1 + cp2) / 2
    p34 = (cp2 + p3) / 2
    p123 = (p12 + p23) / 2

    d = p3 - p0.pos
    d2 = cross(cp1 - p3, d)
    d3 = cross(cp2 - p3, d)
    d4 = d2 + d3

  if d4 * d4 < tessTol * lengthSq(d):
    if not equals(p3, p0.pos, distTolSq):
      let pt = c.createPoint()
      pt.pos = p3
      pt.flags = pointFlags
      return

    if pointFlags.corner:
      p0.flags.corner = true
    if pointFlags.left:
      p0.flags.left = true
    if pointFlags.bevel:
      p0.flags.bevel = true
    if pointFlags.innerBevel:
      p0.flags.innerBevel = true
    return

  let
    p234 = (p23 + p34) / 2
    p1234 = (p123 + p234) / 2

  if level <= 9:
    c.bezier(c.lastPoint, p12, p123, p1234, level + 1, PointFlags(), tessTol, distTolSq)
    c.bezier(c.lastPoint, p234, p34, p3, level + 1, pointFlags, tessTol, distTolSq)

proc triarea2(a, b, c: Vec2): float32 {.inline.} =
  cross(b - a, c - a)

proc area(pts: openArray[PointObj]): float32 {.inline.} =
  result = 0

  for i in 2 ..< pts.len:
    result = result + triarea2(pts[0].pos, pts[i - 1].pos, pts[i].pos)

proc updateBounds(
    c: ptr ContourCacheObj, contours: openArray[ContourObj], distTolSq: float32
) =
  c.bounds = vec4(1e6, 1e6, -1e6, -1e6)

  for p in c.contours.mitems:
    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    if equals(c.points[j].pos, c.points[i].pos, distTolSq):
      dec p.pointCount
      if p.pointCount <= 0:
        continue
      p.closed = true
      dec j

    if p.pointCount > 2:
      let a = area(c.points.toOpenArray(i, j))
      if p.ccw:
        if a < 0:
          reverse(c.points.toOpenArray(i, j))
      elif a > 0:
        reverse(c.points.toOpenArray(i, j))

    var p0 = c.points[j].addr
    while i <= j:
      let
        p1 = c.points[i].addr
        dxy = p1.pos - p0.pos
        d = dxy.length
      p0.dpos = dxy / d
      p0.len = d

      c.bounds.x = min(c.bounds.x, p0.pos.x)
      c.bounds.y = min(c.bounds.y, p0.pos.y)
      c.bounds.z = max(c.bounds.z, p0.pos.x)
      c.bounds.w = max(c.bounds.w, p0.pos.y)

      inc i, 1
      p0 = p1

when defined(NVG_DEBUG_CORE):
  proc dumpContours(values: openArray[float32]) =
    printf("DUMP BEGIN\n")

    var i = 0
    while i < values.len:
      let cmd = Command(values[i])
      case cmd
      of Command.MOVE_TO:
        printf("- MOVE_TO %.6f %.6f\n", values[i + 1], values[i + 2])
        inc i, 3
      of Command.LINE_TO:
        printf("- LINE_TO %.6f %.6f\n", values[i + 1], values[i + 2])
        inc i, 3
      of Command.BEZIER_TO:
        printf(
          "- BEZIER_TO %.6f %.6f %.6f %.6f %.6f %.6f\n",
          values[i + 1],
          values[i + 2],
          values[i + 3],
          values[i + 4],
          values[i + 5],
          values[i + 6],
        )
        inc i, 7
      of Command.CLOSE:
        printf("- CLOSE\n")
        inc i, 1

    printf("DUMP END\n")

proc flattenContours(ctx: ptr ContextObj) =
  when defined(NVG_DEBUG_CORE):
    dumpContours(ctx.commands)

  let c = ctx.cache.addr
  if c.contours.len > 0:
    return

  var i = 0
  while i < ctx.commands.len:
    let cmd = Command(ctx.commands[i])
    case cmd
    of Command.MOVE_TO:
      when defined(NVG_DEBUG_CORE):
        printf("MOVE_TO BEGIN %u\n", c.points.len)
        defer:
          printf("MOVE_TO END %u\n", c.points.len)

      discard c.createContour()
      let pt = c.createPoint()
      pt.flags.corner = true
      pt.pos = vec2(ctx.commands[i + 1], ctx.commands[i + 2])
      inc i, 3
    of Command.LINE_TO:
      when defined(NVG_DEBUG_CORE):
        printf("LINE_TO BEGIN %u\n", c.points.len)
        defer:
          printf("LINE_TO END %u\n", c.points.len)

      if not c.lastContour.isNil:
        let p = vec2(ctx.commands[i + 1], ctx.commands[i + 2])

        if c.lastContour.pointCount > 0 and not c.lastPoint.isNil:
          if equals(c.lastPoint.pos, p, ctx.distTolSq):
            c.lastPoint.flags.corner = true
            inc i, 3
            continue

        let pt = c.createPoint()
        pt.flags.corner = true
        pt.pos = p

      inc i, 3
    of Command.BEZIER_TO:
      when defined(NVG_DEBUG_CORE):
        printf("BEZIER_TO BEGIN %u\n", c.points.len)
        defer:
          printf("BEZIER_TO END %u\n", c.points.len)

      if not c.lastPoint.isNil:
        let
          cp1 = vec2(ctx.commands[i + 1], ctx.commands[i + 2])
          cp2 = vec2(ctx.commands[i + 3], ctx.commands[i + 4])
          p = vec2(ctx.commands[i + 5], ctx.commands[i + 6])
        c.bezier(
          c.lastPoint,
          cp1,
          cp2,
          p,
          0,
          PointFlags(corner: true),
          ctx.tessTol,
          ctx.distTolSq,
        )
      inc i, 7
    of Command.CLOSE:
      if not c.lastContour.isNil:
        c.lastContour.closed = true
      inc i, 1

  c.updateBounds(c.contours, ctx.distTolSq)

proc calculateJoins(c: ptr ContourCacheObj, lineJoin: LineJoin, miterLimit: float32) =
  const
    limit = 1.01
    limitPow2 = limit * limit

  let miterLimitPow2 = miterLimit * miterLimit

  for p in c.contours.mitems:
    if p.pointCount == 0:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1
      leftCount = 0

    p.bevelCount = 0

    var p0 = c.points[j].addr
    while i <= j:
      let
        p1 = c.points[i].addr
        dlx0 = p0.dpos.y
        dly0 = -p0.dpos.x
        dlx1 = p1.dpos.y
        dly1 = -p1.dpos.x

      p1.dmpos.x = (dlx0 + dlx1) / 2
      p1.dmpos.y = (dly0 + dly1) / 2

      let dmr2 = lengthSq(p1.dmpos)
      if dmr2 > 0.000001:
        var s = float32(1) / dmr2
        if s > 600:
          s = 600
        p1.dmpos = p1.dmpos * s

      p1.flags = PointFlags(corner: p1.flags.corner)

      if cross(p0.dpos, p1.dpos) > 0:
        inc leftCount, 1
        p1.flags.left = true

      if dmr2 * limitPow2 < 1:
        p1.flags.innerBevel = true

      if p1.flags.corner:
        if dmr2 * miterLimitPow2 < 1 or lineJoin == LineJoin.BevelJoin or
            lineJoin == LineJoin.RoundJoin:
          p1.flags.bevel = true

      if p1.flags.bevel or p1.flags.innerBevel:
        inc p.bevelCount, 1

      inc i, 1
      p0 = p1

    p.convex = leftCount == p.pointCount

proc expandFill(ctx: ptr ContextObj, lineJoin: LineJoin, miterLimit: float32) =
  let c = ctx.cache.addr

  c.calculateJoins(lineJoin, miterLimit)

  var
    idx1 = 0
    idx2 = 0
    vertCount = 0

  for p in c.contours:
    inc vertCount, 1
    inc vertCount, p.pointCount
    inc vertCount, p.bevelCount

  c.verts.resize(vertCount)

  for p in c.contours.mitems:
    if p.pointCount == 0:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    while i <= j:
      let p = c.points[i].addr

      c.verts[idx2] = vec4(p.pos.x, p.pos.y, 0.5, 1)

      inc idx2, 1
      inc i, 1

    p.fill = slice(c.verts.toOpenArray(idx1, idx2 - 1))
    p.stroke = default(Slice2[Vec4])

    idx1 = idx2

proc curveDivs(r, arc, tol: float32): int {.inline.} =
  let da = arccos(r / (r + tol)) * 2
  max(2, int(ceil(arc / da)))

proc chooseBevel(bevel: bool, p0, p1: PointObj, w: float32): (Vec2, Vec2) =
  if bevel:
    let
      p2x = p1.pos.x + p0.dpos.y * w
      p2y = p1.pos.y - p0.dpos.x * w
      p3x = p1.pos.x + p1.dpos.y * w
      p3y = p1.pos.y - p1.dpos.x * w

    result[0] = vec2(p2x, p2y)
    result[1] = vec2(p3x, p3y)
    return

  let
    p2x = p1.pos.x + p1.dmpos.x * w
    p2y = p1.pos.y + p1.dmpos.y * w
    p3x = p1.pos.x + p1.dmpos.x * w
    p3y = p1.pos.y + p1.dmpos.y * w

  result[0] = vec2(p2x, p2y)
  result[1] = vec2(p3x, p3y)

proc roundJoin(
    verts: var seq[Vec4], p0, p1: PointObj, lw, rw, lu, ru: float32, ncap: int
) =
  let
    dlx0 = p0.dpos.y
    dly0 = -p0.dpos.x
    dlx1 = p1.dpos.y
    dly1 = -p1.dpos.x

  if p1.flags.left:
    let
      (lxy0, lxy1) = chooseBevel(p1.flags.innerBevel, p0, p1, lw)
      a0 = arctan2(-dly0, -dlx0)
    var a1 = arctan2(-dly1, -dlx1)
    if a1 > a0:
      a1 = a1 - 2 * PI

    verts.add(vec4(lxy0.x, lxy0.y, lu, 1))
    verts.add(vec4(p1.pos.x - dlx0 * rw, p1.pos.y - dly0 * rw, ru, 1))

    var i = float32(0)
    let n =
      clamp(float32(ceil((a0 - a1) / PI * float32(ncap))), float32(2), float32(ncap))
    while i < n:
      let
        u = i / (n - 1)
        a = a0 + u * (a1 - a0)
        rx = p1.pos.x + cos(a) * rw
        ry = p1.pos.y + sin(a) * rw
      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))
      verts.add(vec4(rx, ry, ru, 1))
      i = i + 1
    verts.add(vec4(lxy1.x, lxy1.y, lu, 1))
    verts.add(vec4(p1.pos.x - dlx1 * rw, p1.pos.y - dly1 * rw, ru, 1))
  else:
    let
      (rxy0, rxy1) = chooseBevel(p1.flags.innerBevel, p0, p1, -rw)
      a0 = arctan2(dly0, dlx0)
    var a1 = arctan2(dly1, dlx1)
    if a1 < a0:
      a1 = a1 + 2 * PI

    verts.add(vec4(p1.pos.x + dlx0 * rw, p1.pos.y + dly0 * rw, lu, 1))
    verts.add(vec4(rxy0.x, rxy0.y, ru, 1))

    var i = float32(0)
    let n =
      clamp(float32(ceil((a0 - a1) / PI * float32(ncap))), float32(2), float32(ncap))
    while i < n:
      let
        u = i / (n - 1)
        a = a0 + u * (a1 - a0)
        lx = p1.pos.x + cos(a) * lw
        ly = p1.pos.y + sin(a) * lw
      verts.add(vec4(lx, ly, lu, 1))
      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))
      i = i + 1
    verts.add(vec4(p1.pos.x + dlx1 * rw, p1.pos.y + dly1 * rw, lu, 1))
    verts.add(vec4(rxy1.x, rxy1.y, ru, 1))

proc bevelJoin(verts: var seq[Vec4], p0, p1: PointObj, lw, rw, lu, ru: float32) =
  let
    dlx0 = p0.dpos.y
    dly0 = -p0.dpos.x
    dlx1 = p1.dpos.y
    dly1 = -p1.dpos.x

  if p1.flags.left:
    let (lxy0, lxy1) = chooseBevel(p1.flags.innerBevel, p0, p1, lw)

    verts.add(vec4(lxy0.x, lxy0.y, lu, 1))
    verts.add(vec4(p1.pos.x - dlx0 * rw, p1.pos.y - dly0 * rw, ru, 1))

    if p1.flags.bevel:
      verts.add(vec4(lxy0.x, lxy0.y, lu, 1))
      verts.add(vec4(p1.pos.x - dlx0 * rw, p1.pos.y - dly0 * rw, ru, 1))
      verts.add(vec4(lxy1.x, lxy1.y, lu, 1))
      verts.add(vec4(p1.pos.x - dlx1 * rw, p1.pos.y - dly1 * rw, ru, 1))
    else:
      let
        rx0 = p1.pos.x - p1.dmpos.x * rw
        ry0 = p1.pos.y - p1.dmpos.y * rw

      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))
      verts.add(vec4(p1.pos.x - dlx0 * rw, p1.pos.y - dly0 * rw, ru, 1))
      verts.add(vec4(rx0, ry0, ru, 1))
      verts.add(vec4(rx0, ry0, ru, 1))
      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))
      verts.add(vec4(p1.pos.x - dlx1 * rw, p1.pos.y - dly1 * rw, ru, 1))

    verts.add(vec4(lxy1.x, lxy1.y, lu, 1))
    verts.add(vec4(p1.pos.x - dlx1 * rw, p1.pos.y - dly1 * rw, ru, 1))
  else:
    let (rxy0, rxy1) = chooseBevel(p1.flags.innerBevel, p0, p1, -rw)

    verts.add(vec4(p1.pos.x + dlx0 * lw, p1.pos.y + dly0 * lw, lu, 1))
    verts.add(vec4(rxy0.x, rxy0.y, ru, 1))

    if p1.flags.bevel:
      verts.add(vec4(p1.pos.x + dlx0 * lw, p1.pos.y + dly0 * lw, lu, 1))
      verts.add(vec4(rxy0.x, rxy0.y, ru, 1))

      verts.add(vec4(p1.pos.x + dlx1 * lw, p1.pos.y + dly1 * lw, lu, 1))
      verts.add(vec4(rxy1.x, rxy1.y, ru, 1))
    else:
      let
        lx0 = p1.pos.x - p1.dmpos.x * lw
        ly0 = p1.pos.y - p1.dmpos.y * lw

      verts.add(vec4(p1.pos.x + dlx0 * lw, p1.pos.y + dly0 * lw, lu, 1))
      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))
      verts.add(vec4(lx0, ly0, lu, 1))
      verts.add(vec4(lx0, ly0, lu, 1))
      verts.add(vec4(p1.pos.x + dlx1 * lw, p1.pos.y + dly1 * lw, lu, 1))
      verts.add(vec4(p1.pos.x, p1.pos.y, 0.5, 1))

    verts.add(vec4(p1.pos.x + dlx1 * lw, p1.pos.y + dly1 * lw, lu, 1))
    verts.add(vec4(rxy1.x, rxy1.y, ru, 1))

proc buttCapStart(verts: var seq[Vec4], p, dxy: Vec2, w, d, u0, u1: float32) =
  let
    pxy = p - dxy * d
    dlx = dxy.y
    dly = -dxy.x
  verts.add(vec4(pxy.x + dlx * w, pxy.y + dly * w, u0, 0))
  verts.add(vec4(pxy.x - dlx * w, pxy.y - dly * w, u1, 0))
  verts.add(vec4(pxy.x + dlx * w, pxy.y + dly * w, u0, 1))
  verts.add(vec4(pxy.x - dlx * w, pxy.y - dly * w, u1, 1))

proc buttCapEnd(verts: var seq[Vec4], p, dxy: Vec2, w, d, u0, u1: float32) =
  let
    pxy = p + dxy * d
    dlx = dxy.y
    dly = -dxy.x
  verts.add(vec4(pxy.x + dlx * w, pxy.y + dly * w, u0, 1))
  verts.add(vec4(pxy.x - dlx * w, pxy.y - dly * w, u1, 1))
  verts.add(vec4(pxy.x + dlx * w, pxy.y + dly * w, u0, 0))
  verts.add(vec4(pxy.x - dlx * w, pxy.y - dly * w, u1, 0))

proc roundCapStart(verts: var seq[Vec4], p, dxy: Vec2, w, u0, u1: float32, ncap: int) =
  let
    dlx = dxy.y
    dly = -dxy.x
    e = PI / float32(ncap - 1)

  var
    i = 0
    a = float32(0)

  while i < ncap:
    a = a + e

    let
      ax = cos(a) * w
      ay = sin(a) * w

    verts.add(vec4(p.x - dlx * ax - dxy.x * ay, p.y - dly * ax - dxy.y * ay, u0, 1))
    verts.add(vec4(p.x, p.y, 0.5, 1))

    inc i, 1

  verts.add(vec4(p.x + dlx * w, p.y + dly * w, u0, 1))
  verts.add(vec4(p.x - dlx * w, p.y - dly * w, u1, 1))

proc roundCapEnd(verts: var seq[Vec4], p, dxy: Vec2, w, u0, u1: float32, ncap: int) =
  let
    dlx = dxy.y
    dly = -dxy.x
    e = PI / float32(ncap - 1)

  verts.add(vec4(p.x + dlx * w, p.y + dly * w, u0, 1))
  verts.add(vec4(p.x - dlx * w, p.y - dly * w, u1, 1))

  var
    i = 0
    a = float32(0)

  while i < ncap:
    a = a + e

    let
      ax = cos(a) * w
      ay = sin(a) * w

    verts.add(vec4(p.x, p.y, 0.5, 1))
    verts.add(vec4(p.x - dlx * ax + dxy.x * ay, p.y - dly * ax + dxy.y * ay, u0, 1))

    inc i, 1

proc expandStroke(
    ctx: ptr ContextObj,
    width: float32,
    lineCap: LineCap,
    lineJoin: LineJoin,
    miterLimit: float32,
) =
  let
    c = ctx.cache.addr
    u0 = float32(0.5)
    u1 = float32(0.5)
    ncap = curveDivs(width, PI, ctx.tessTol)

  c.calculateJoins(lineJoin, miterLimit)

  var vertCount = 0

  for p in c.contours:
    if lineJoin == RoundJoin:
      inc vertCount, (p.pointCount + p.bevelCount * (ncap + 2) + 1) * 2
    else:
      inc vertCount, (p.pointCount + p.bevelCount * 5 + 1) * 2

    if not p.closed:
      if lineCap == RoundCap:
        inc vertCount, (ncap * 2 + 2) * 2
      else:
        inc vertCount, (3 + 3) * 2

  c.verts.clear()
  c.verts.reserve(vertCount)

  for p in c.contours.mitems:
    if p.pointCount == 0:
      continue

    let offset = c.verts.len

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    var
      p0 = c.points[j].addr
      p1 = c.points[i].addr

    if not p.closed:
      p0 = c.points[i].addr
      inc i, 1
      dec j, 1
      p1 = c.points[i].addr

      let dxy = normalize(p1.pos - p0.pos)
      case lineCap
      of ButtCap:
        c.verts.buttCapStart(p0.pos, dxy, width, 0, u0, u1)
      of SquareCap:
        c.verts.buttCapStart(p0.pos, dxy, width, width, u0, u1)
      of RoundCap:
        c.verts.roundCapStart(p0.pos, dxy, width, u0, u1, ncap)

    while i <= j:
      p1 = c.points[i].addr
      if p1.flags.bevel or p1.flags.innerBevel:
        if lineJoin == RoundJoin:
          c.verts.roundJoin(p0[], p1[], width, width, u0, u1, ncap)
        else:
          c.verts.bevelJoin(p0[], p1[], width, width, u0, u1)
      else:
        c.verts.add(
          vec4(p1.pos.x + p1.dmpos.x * width, p1.pos.y + p1.dmpos.y * width, u0, 1)
        )
        c.verts.add(
          vec4(p1.pos.x - p1.dmpos.x * width, p1.pos.y - p1.dmpos.y * width, u0, 1)
        )

      inc i, 1
      p0 = p1

    if p.closed:
      let n = succ(offset)
      c.verts.add(vec4(c.verts[offset].x, c.verts[offset].y, u0, 1))
      c.verts.add(vec4(c.verts[n].x, c.verts[n].y, u1, 1))
    else:
      p1 = c.points[i].addr

      let dxy = normalize(p1.pos - p0.pos)
      case lineCap
      of ButtCap:
        c.verts.buttCapEnd(p1.pos, dxy, width, 0, u0, u1)
      of SquareCap:
        c.verts.buttCapEnd(p1.pos, dxy, width, width, u0, u1)
      of RoundCap:
        c.verts.roundCapEnd(p1.pos, dxy, width, u0, u1, ncap)

    p.fill = default(Slice2[Vec4])
    p.stroke = slice(c.verts.toOpenArray(offset, c.verts.len - 1))

proc fill*(ctx: ptr ContextObj) =
  let
    state = ctx.lastState
    c = ctx.cache.addr

  ctx.flattenContours()
  if c.contours.len <= 0:
    return

  ctx.expandFill(MiterJoin, state.miterLimit)

  ctx.params.fillImpl(
    ctx.ctx,
    state.fill.addr,
    state.compositeOperation,
    c.bounds,
    c.contours.toOpenArray(0, -1),
    c.contours,
  )

  for p in c.contours.mitems:
    if p.fill.len >= 2:
      inc ctx.fillTriCount, p.fill.len - 2
    if p.stroke.len >= 2:
      inc ctx.fillTriCount, p.stroke.len - 2
    inc ctx.drawCallCount, 2

proc getAverageScale(t: Mat3): float32 =
  let
    t0 = t[0, 0]
    t1 = t[0, 1]
    t2 = t[1, 0]
    t3 = t[1, 1]

  let
    sx = sqrt(t0 * t0 + t2 * t2)
    sy = sqrt(t1 * t1 + t3 * t3)

  (sx + sy) * 0.5

proc stroke*(ctx: ptr ContextObj) =
  let
    state = ctx.lastState
    s = getAverageScale(state.transform)
    strokeWidth = clamp(state.strokeWidth * s, 0, 200)
    c = ctx.cache.addr

  var paint = state.stroke
  paint.innerColor.a = state.globalAlpha * paint.innerColor.a
  paint.outerColor.a = state.globalAlpha * paint.outerColor.a

  ctx.flattenContours()
  if c.contours.len <= 0:
    return

  ctx.expandStroke(strokeWidth * 0.5, state.lineCap, state.lineJoin, state.miterLimit)

  ctx.params.strokeImpl(
    ctx.ctx,
    state.stroke.addr,
    state.compositeOperation,
    c.bounds,
    c.contours.toOpenArray(0, -1),
    c.contours,
  )

  for p in c.contours.mitems:
    if p.stroke.len >= 2:
      inc ctx.fillTriCount, p.stroke.len - 2
    inc ctx.drawCallCount, 2

proc begin*(ctx: ptr ContextObj, view: Vec2, devicePixelRatio: float32) =
  ctx.stateCount = 0

  ctx.save()
  ctx.reset()

  ctx.setDevicePixelRatio(devicePixelRatio)

  ctx.params.viewportImpl(ctx.ctx, view, devicePixelRatio)

  ctx.drawCallCount = 0
  ctx.fillTriCount = 0
  ctx.strokeTriCount = 0

proc flush*(ctx: ptr ContextObj) =
  ctx.params.flushImpl(ctx.ctx)
