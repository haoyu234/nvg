import pkg/chroma
import pkg/vmath

import std/algorithm
import std/math

import ./params
import ./pieces

when defined(NVG_DEBUG_CORE):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

const
  NVG_MAX_STATES = 32
  NVG_INIT_COMMANDS_SIZE = 256
  NVG_INIT_POINTS_SIZE = 256
  NVG_INIT_PATH_SIZE = 16
  NVG_INIT_VERTS_SIZE = 26
  NVG_KAPPA90 = float32(4.0 * (sqrt(2.0) - 1.0) / 3.0)

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

  FillRule* = enum
    NonZero
    EvenOdd

  StateObj = object
    fillRule: FillRule
    compositeOperation: CompositeOperation
    fill: PaintObj
    stroke: PaintObj
    strokeWidth: float32
    miterLimit: float32
    lineJoin: LineJoin
    lineCap: LineCap
    dashArray: seq[float32]
    dashOffset: float32
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

  PathCacheObj = object
    points: seq[Vec2]
    paths: seq[PathObj]
    verts: seq[Vec4]
    currentPath: ptr PathObj
    bounds: Vec4

  ContextObj* = object
    ctx: pointer
    params: BackendContextParams

    commands: seq[float32]
    commandXY: Vec2
    state: array[NVG_MAX_STATES, StateObj]
    stateCount: int
    lastState: ptr StateObj
    cache: PathCacheObj
    tessTol: float32
    distTol: float32
    distTolSq: float32
    devicePxRatio: float32

    # stats
    drawCallCount: int

    # flush texture
    textureDirty: bool

proc setDevicePixelRatio(ctx: ptr ContextObj, ratio: float32) =
  ctx.tessTol = 0.25 / ratio
  ctx.distTol = 0.01 / ratio
  ctx.distTolSq = ctx.distTol * ctx.distTol
  ctx.devicePxRatio = ratio

proc save*(ctx: ptr ContextObj) =
  if ctx.stateCount >= NVG_MAX_STATES:
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

proc setColor(p: var PaintObj, color: Color) =
  p.transform = mat3()
  p.extent = vec2(0, 0)
  p.radius = 0
  p.feather = 1
  p.innerColor = color
  p.outerColor = color

proc reset(ctx: ptr ContextObj) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fillRule = NonZero
  state.fill.setColor(color(1, 1, 1, 1))
  state.stroke.setColor(color(0, 0, 0, 1))

  state.compositeOperation = CompositeOperation.SOURCE_OVER_OPERATION
  state.strokeWidth = 1
  state.miterLimit = 10
  state.lineCap = ButtCap
  state.lineJoin = MiterJoin
  state.dashArray.setLenUninit(0)
  state.dashOffset = 0
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

  ctx.commands = newSeqOfCap[float32](NVG_INIT_COMMANDS_SIZE)

  ctx.cache.points = newSeqOfCap[Vec2](NVG_INIT_POINTS_SIZE)
  ctx.cache.paths = newSeqOfCap[PathObj](NVG_INIT_PATH_SIZE)
  ctx.cache.verts = newSeqOfCap[Vec4](NVG_INIT_VERTS_SIZE)

  save(ctx)
  reset(ctx)

  setDevicePixelRatio(ctx, 1)

  ctx

proc setGlobalCompositeOperation*(ctx: ptr ContextObj, operation: CompositeOperation) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.compositeOperation = operation

proc setFillPaint*(ctx: ptr ContextObj, paint: PaintObj) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fill = paint

proc setFillColor*(ctx: ptr ContextObj, color: Color) =
  let state = ctx.lastState
  assert (not state.isNil)

  state.fill.setColor(color)

proc setStrokePaint*(ctx: ptr ContextObj, paint: PaintObj) =
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

proc clear(c: ptr PathCacheObj) {.inline, raises: [].} =
  c.currentPath = nil
  c.points.setLenUninit(0)
  c.paths.setLenUninit(0)

proc appendCommands(ctx: ptr ContextObj, values: openArray[float32]) =
  let
    c = ctx.cache.addr
    state = ctx.lastState

  if values.len >= 3:
    ctx.commandXY.x = values[values.len - 2]
    ctx.commandXY.y = values[values.len - 1]

  when defined(NVG_DEBUG_CORE):
    printf("line[%u] appendCommands %u\n", 0, values.len)
    printf("commandXY %.6f %.6f\n", ctx.commandXY.x, ctx.commandXY.y)

    for v in values:
      printf("_ %.6f\n", v)

  var
    i = 0
    offset = ctx.commands.len

  ctx.commands.add(values)

  template modify(pos: Vec2) =
    ctx.commands[offset + i] = pos.x
    ctx.commands[offset + i + 1] = pos.y
    inc i, 2

  while i < values.len:
    case Command(values[i])
    of Command.MOVE_TO, Command.LINE_TO:
      let pos = state.transform * vec2(values[i + 1], values[i + 2])

      inc i, 1
      modify(pos)
    of Command.BEZIER_TO:
      let pos1 = state.transform * vec2(values[i + 1], values[i + 2])
      let pos2 = state.transform * vec2(values[i + 3], values[i + 4])
      let pos3 = state.transform * vec2(values[i + 5], values[i + 6])

      inc i, 1
      modify(pos1)
      modify(pos2)
      modify(pos3)
    of Command.CLOSE:
      inc i, 1

proc beginPath*(ctx: ptr ContextObj) =
  let c = ctx.cache.addr
  ctx.commands.setLenUninit(0)
  c.clear()

proc rect*(ctx: ptr ContextObj, rect: Vec4) =
  ctx.appendCommands(
    [
      float32(Command.MOVE_TO),
      rect.x,
      rect.y,
      float32(Command.LINE_TO),
      rect.x,
      rect.y + rect.w,
      float32(Command.LINE_TO),
      rect.x + rect.z,
      rect.y + rect.w,
      float32(Command.LINE_TO),
      rect.x + rect.z,
      rect.y,
      float32(Command.CLOSE),
    ]
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

  var
    idx = 0
    commands {.noinit.}: array[3 + 5 * 7 + 100, float32]

  template append(v) =
    commands[idx] = v
    inc idx, 1

  let
    ndivs = max(1, min(int(abs(da) / pidiv2 + float32(0.5)), 5))
    hda = da / float32(ndivs) / 2

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

  for i in 0 .. ndivs:
    let
      a = a0 + da * float32(i) / float32(ndivs)
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
      append(float32(Command.BEZIER_TO))
      append(px + ptanx)
      append(py + ptany)
      append(x - tanx)
      append(y - tany)
    elif ctx.commands.len > 0:
      append(float32(Command.LINE_TO))
    else:
      append(float32(Command.MOVE_TO))

    append(x)
    append(y)

    px = x
    py = y
    ptanx = tanx
    ptany = tany

  when defined(NVG_DEBUG_CORE):
    printf("commands: \n")
    for i in 0 ..< idx:
      printf("%.6f ", commands[i])
    printf("\n")

  ctx.appendCommands(commands.toOpenArray(0, idx - 1))

proc ellipse*(ctx: ptr ContextObj, c: Vec2, rx, ry: float32) =
  ctx.appendCommands(
    [
      float32(Command.MOVE_TO),
      c.x - rx,
      c.y,
      float32(Command.BEZIER_TO),
      c.x - rx,
      c.y + ry * NVG_KAPPA90,
      c.x - rx * NVG_KAPPA90,
      c.y + ry,
      c.x,
      c.y + ry,
      float32(Command.BEZIER_TO),
      c.x + rx * NVG_KAPPA90,
      c.y + ry,
      c.x + rx,
      c.y + ry * NVG_KAPPA90,
      c.x + rx,
      c.y,
      float32(Command.BEZIER_TO),
      c.x + rx,
      c.y - ry * NVG_KAPPA90,
      c.x + rx * NVG_KAPPA90,
      c.y - ry,
      c.x,
      c.y - ry,
      float32(Command.BEZIER_TO),
      c.x - rx * NVG_KAPPA90,
      c.y - ry,
      c.x - rx,
      c.y - ry * NVG_KAPPA90,
      c.x - rx,
      c.y,
      float32(Command.CLOSE),
    ]
  )

proc circle*(ctx: ptr ContextObj, c: Vec2, r: float32) =
  ctx.ellipse(c, r, r)

proc moveTo*(ctx: ptr ContextObj, pos: Vec2) =
  ctx.appendCommands([float32(Command.MOVE_TO), pos.x, pos.y])

proc lineTo*(ctx: ptr ContextObj, pos: Vec2) =
  ctx.appendCommands([float32(Command.LINE_TO), pos.x, pos.y])

proc bezierTo*(ctx: ptr ContextObj, cp1, cp2, to: Vec2) =
  ctx.appendCommands(
    [float32(Command.BEZIER_TO), cp1.x, cp1.y, cp2.x, cp2.y, to.x, to.y]
  )

proc quadCurveTo*(ctx: ptr ContextObj, cp, to: Vec2) =
  const s = float32(2) / 3
  let pos = ctx.commandXY

  ctx.appendCommands(
    [
      float32(Command.BEZIER_TO),
      pos.x + s * (cp.x - pos.x),
      pos.y + s * (cp.y - pos.y),
      to.x + s * (cp.x - to.x),
      to.y + s * (cp.y - to.y),
      to.x,
      to.y,
    ]
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
  const cmds = [float32(Command.CLOSE)]
  ctx.appendCommands(cmds)

proc createPath(c: ptr PathCacheObj) {.inline, raises: [].} =
  let idx = c.paths.len
  c.paths.setLen(idx + 1)

  let p = c.paths[idx].addr
  p.offset = int32(c.points.len)
  p.ccw = true

  c.currentPath = p

proc createPoint(c: ptr PathCacheObj, p: Vec2) {.inline, raises: [].} =
  inc c.currentPath.pointCount, 1
  c.points.add(p)

proc bezier(
    c: ptr PathCacheObj, p1, p2, p3, p4: Vec2, level: int, tessTol, distTolSq: float32
) =
  let
    d = p4 - p1
    d2 = cross(p2 - p4, d)
    d3 = cross(p3 - p4, d)
    d4 = d2 + d3

  if d4 * d4 < tessTol * d.lengthSq or level >= 9:
    if not equals(p1, p4, distTolSq):
      c.createPoint(p4)
  else:
    let
      p12 = (p1 + p2) / 2
      p23 = (p2 + p3) / 2
      p34 = (p3 + p4) / 2
      p123 = (p12 + p23) / 2
      p234 = (p23 + p34) / 2
      p1234 = (p123 + p234) / 2

    c.bezier(p1, p12, p123, p1234, level + 1, tessTol, distTolSq)
    c.bezier(p1234, p234, p34, p4, level + 1, tessTol, distTolSq)

proc area(pts: openArray[Vec2]): float32 {.inline.} =
  var r = float32(0)
  for i in 2 ..< pts.len:
    let
      a = pts[0]
      b = pts[i - 1]
      c = pts[i]

    r = r + cross(b - a, c - a)
  r

proc flattenPaths(ctx: ptr ContextObj) =
  let c = ctx.cache.addr
  if c.paths.len > 0:
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

      c.createPath()
      c.createPoint(vec2(ctx.commands[i + 1], ctx.commands[i + 2]))

      inc i, 3
    of Command.LINE_TO:
      when defined(NVG_DEBUG_CORE):
        printf("LINE_TO BEGIN %u\n", c.points.len)
        defer:
          printf("LINE_TO END %u\n", c.points.len)

      if not c.currentPath.isNil:
        let p = vec2(ctx.commands[i + 1], ctx.commands[i + 2])

        if c.currentPath.pointCount > 0:
          let idx = c.currentPath.offset + c.currentPath.pointCount - 1
          if equals(c.points[idx], p, ctx.distTolSq):
            inc i, 3
            continue

        c.createPoint(p)

      inc i, 3
    of Command.BEZIER_TO:
      when defined(NVG_DEBUG_CORE):
        printf("BEZIER_TO BEGIN %u\n", c.points.len)
        defer:
          printf("BEZIER_TO END %u\n", c.points.len)

      if not c.currentPath.isNil:
        if c.currentPath.pointCount > 0:
          let
            idx = c.currentPath.offset + c.currentPath.pointCount - 1
            cp1 = vec2(ctx.commands[i + 1], ctx.commands[i + 2])
            cp2 = vec2(ctx.commands[i + 3], ctx.commands[i + 4])
            p = vec2(ctx.commands[i + 5], ctx.commands[i + 6])

          c.bezier(c.points[idx], cp1, cp2, p, 0, ctx.tessTol, ctx.distTolSq)

      inc i, 7
    of Command.CLOSE:
      if not c.currentPath.isNil:
        c.currentPath.closed = true

      inc i, 1

  when defined(NVG_DEBUG_CORE):
    printf("BEGIN flattenPaths\n")
    for v in c.points:
      printf("__ %.6f %.6f\n", v.x, v.y)
    printf("END flattenPaths\n")

  for idx in 0 ..< c.paths.len:
    let p = c.paths[idx].addr

    if p.pointCount <= 1:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    if equals(c.points[j], c.points[i], ctx.distTolSq):
      dec j
      dec p.pointCount

      p.closed = true

    if p.pointCount > 2:
      let a = area(c.points.toOpenArray(i, j))
      if p.ccw:
        if a < 0:
          reverse(c.points.toOpenArray(i, j))
      elif a > 0:
        reverse(c.points.toOpenArray(i, j))

proc updateBounds(c: ptr PathCacheObj, paths: openArray[PathObj], distTolSq: float32) =
  c.bounds = vec4(1e6, 1e6, -1e6, -1e6)

  for idx in 0 ..< c.paths.len:
    let p = c.paths[idx].addr

    p.bounds = vec4(1e6, 1e6, -1e6, -1e6)

    if p.fill.len <= 0:
      continue

    for v in p.fill.toOpenArray:
      p.bounds.x = min(p.bounds.x, v.x)
      p.bounds.y = min(p.bounds.y, v.y)
      p.bounds.z = max(p.bounds.z, v.x)
      p.bounds.w = max(p.bounds.w, v.y)

    c.bounds.x = min(p.bounds.x, c.bounds.x)
    c.bounds.y = min(p.bounds.y, c.bounds.y)
    c.bounds.z = max(p.bounds.z, c.bounds.x)
    c.bounds.w = max(p.bounds.w, c.bounds.y)

proc curveDivs(r, arc, tol: float32): int {.inline.} =
  let da = arccos(r / (r + tol)) * 2
  max(2, int(ceil(arc / da)))

proc arcJoin(
    memory: Piece[Vec4], idx: int, p0, p1, c: Vec2, w: float32, nCap, dir: int
): int =
  var
    pos = idx
    ax = float32(0)
    ay = float32(0)

    a0 = angle(p0 - c)
    a1 = angle(p1 - c)

  if a1 > a0:
    a1 = a1 - PI * 2

  let n = clamp(int(ceil((a0 - a1) / float32(PI) * float32(nCap))), 2, nCap)
  for i in 0 ..< n:
    let
      u = float32(i) / float32(n - 1)
      a = a0 + u * (a1 - a0)
      rx = c.x + cos(a) * w
      ry = c.y + sin(a) * w

    if i > 0:
      if dir < 0:
        dec pos, 1
        memory[pos] = vec4(ax, ay, rx, ry)
      else:
        memory[pos] = vec4(ax, ay, rx, ry)
        inc pos, 1

    ax = rx
    ay = ry

  pos

proc expandStroke(
    ctx: ptr ContextObj,
    lineCap: LineCap,
    lineJoin: LineJoin,
    strokeWidth, miterLimit: float32,
) =
  let
    c = ctx.cache.addr
    w = float32(0.5 * strokeWidth)
    nCap = curveDivs(w, PI, ctx.tessTol)
    mLimSq = w * w * miterLimit * miterLimit

  let vertCount = block:
    var count = 0

    for p in c.paths.items:
      inc count, p.pointCount

    if lineJoin == RoundJoin or lineCap == RoundCap:
      6 * (count * (nCap + 2) + 1) * 2
    else:
      6 * (count * 2 + 1) * 2

  var n = default(int)

  when defined(NVG_DEBUG_CORE):
    printf("vertCount = %u\n", vertCount)

  c.verts.setLenUninit(vertCount)

  var
    l = 0
    r = vertCount
    offset = l

  let memory = piece(c.verts)

  template incp(v1, v2) =
    inc n, 1
    when defined(NVG_DEBUG_CORE):
      printf("line[%u] %u %.6f %.6f %.6f %.6f\n", 0, n, v1.x, v1.y, v2.x, v2.y)
    memory[l] = vec4(v1.x, v1.y, v2.x, v2.y)
    inc l

  template decp(v1, v2) =
    inc n, 1
    when defined(NVG_DEBUG_CORE):
      printf("line[%u] %u %.6f %.6f %.6f %.6f\n", 0, n, v1.x, v1.y, v2.x, v2.y)
    dec r
    memory[r] = vec4(v1.x, v1.y, v2.x, v2.y)

  for idx in 0 ..< c.paths.len:
    let p = c.paths[idx].addr

    if p.pointCount <= 0:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

      p0 = default(ptr Vec2)
      p1 = default(ptr Vec2)
      p2 = default(ptr Vec2)

      tmp = default(Vec2)

    let closed = p.closed and p.pointCount > 2

    if closed:
      p0 = c.points[i + p.pointCount - 2].addr
      p1 = c.points[i + p.pointCount - 1].addr
    elif p.pointCount == 1:
      if lineCap == ButtCap:
        continue

      p0 = c.points[i].addr
      p1 = tmp.addr

      tmp.x = p0[].x + w / float32(256)
      tmp.y = p0[].y

      inc i, 2
    else:
      p0 = c.points[i].addr

      inc i, 1
      p1 = c.points[i].addr

      inc i, 1

    var
      d01 = p1[] - p0[]
      n01 = normalize(vec2(-d01.y, d01.x))

      lp = default(Vec2)
      rp = default(Vec2)

      l00 = default(Vec2)
      r00 = default(Vec2)

      wn01 = w * n01

    if not closed:
      lp = p0[] + wn01
      rp = p0[] - wn01

      if lineCap == ButtCap:
        incp(rp, lp)
      elif lineCap == SquareCap:
        let
          cd = vec2(wn01.y, -wn01.x)
          v1 = vec2(rp.x - cd.x, rp.y - cd.y)
          v2 = vec2(lp.x - cd.x, lp.y - cd.y)

        incp(rp, v1)
        incp(v1, v2)
        incp(v2, lp)
      elif lineCap == RoundCap:
        l = arcJoin(memory, l, rp, lp, p0[], w, nCap, 1)

    while i <= j:
      p2 = c.points[i].addr

      let
        d12 = p2[] - p1[]
        n12 = normalize(vec2(-d12.y, d12.x))
        wn12 = w * n12
        miterDenom = max(1e-6f, 1 + dot(n01, n12))
        e = (n01 + n12) / miterDenom
        we = w * e
        mLenSq = w * w * e.lengthSq
        l01Sq = d01.lengthSq
        l12Sq = d12.lengthSq

        join =
          if lineJoin == MiterJoin and mLenSq <= mLimSq and miterDenom > 1e-6f:
            MiterJoin
          else:
            BevelJoin

        outerJoin = if lineJoin == RoundJoin: RoundJoin else: join
        innerJoin = if l01Sq < mLenSq or l12Sq < mLenSq: BevelJoin else: join

        left = cross(d12, d01) > 0
        lJoin = if left: innerJoin else: outerJoin
        rJoin = if left: outerJoin else: innerJoin

      when defined(NVG_DEBUG_CORE):
        template joinToStr(t: LineJoin): cstring =
          if t == MiterJoin:
            "MiterJoin"
          elif t == BevelJoin:
            "BevelJoin"
          elif t == RoundJoin:
            "RoundJoin"
          else:
            "?"

        printf(
          "join[%s] outerJoin[%s] innerJoin[%s] lJoin[%s] rJoin[%s] left[%u]\n",
          joinToStr(join),
          joinToStr(outerJoin),
          joinToStr(innerJoin),
          joinToStr(lJoin),
          joinToStr(rJoin),
          left,
        )

      var
        l01 = default(Vec2)
        l12 = default(Vec2)
        r01 = default(Vec2)
        r12 = default(Vec2)

      if lJoin == MiterJoin:
        let p = p1[] + we
        l01 = p
        l12 = p
      else:
        l01 = p1[] + wn01
        l12 = p1[] + wn12

      when defined(NVG_DEBUG_CORE):
        printf(
          "ljoin[%u] wn01[%.6f, %.6f] wn12[%.6f, %.6f] p1[%.6f, %.6f]\n",
          lJoin == MiterJoin,
          wn01.x,
          wn01.y,
          wn12.x,
          wn12.y,
          p1[].x,
          p1[].y,
        )

        printf("l01[%.6f, %.6f] l12[%.6f, %.6f]\n", l01.x, l01.y, l12.x, l12.y)
        printf("%.6f, %.6f\n", p1[].x + w * n01.x, p1[].y + w * n01.y)

      if i > p.offset:
        incp(lp, l01)
      else:
        l00 = l01

      if lJoin == RoundJoin:
        l = arcJoin(memory, l, l01, l12, p1[], w, nCap, 1)
      elif lJoin == BevelJoin:
        incp(l01, l12)

      lp = l12

      if rJoin == MiterJoin:
        let p = p1[] - we
        r01 = p
        r12 = p
      else:
        r01 = p1[] - wn01
        r12 = p1[] - wn12

      if i > p.offset:
        decp(r01, rp)
      else:
        r00 = r01

      if rJoin == RoundJoin:
        r = arcJoin(memory, r, r12, r01, p1[], w, nCap, -1)
      elif rJoin == BevelJoin:
        decp(r12, r01)

      rp = r12

      p0 = p1
      p1 = p2

      inc i, 1

      d01 = d12
      n01 = n12

      wn01 = w * n01

    if not closed:
      let
        l01 = p1[] + wn01
        r01 = p1[] - wn01

      when defined(NVG_DEBUG_CORE):
        printf(
          "x[%.6f] y[%.6f] n01x[%.6f] n01y[%.6f] l01x[%.6f] l01y[%.6f] r01x[%.6f] r01y[%.6f] w[%.6f]\n",
          p1[].x,
          p1[].y,
          n01.x,
          n01.y,
          l01.x,
          l01.y,
          r01.x,
          r01.y,
          w,
        )

      incp(lp, l01)
      lp = l01
      decp(r01, rp)
      rp = r01

      if lineCap == ButtCap:
        incp(lp, rp)
      elif lineCap == SquareCap:
        let
          cd = vec2(wn01.y, -wn01.x)
          v1 = vec2(lp.x + cd.x, lp.y + cd.y)
          v2 = vec2(rp.x + cd.x, rp.y + cd.y)

        incp(lp, v1)
        incp(v1, v2)
        incp(v2, rp)
      elif lineCap == RoundCap:
        r = arcJoin(memory, r, lp, rp, p1[], w, nCap, 1)
    else:
      incp(lp, l00)
      decp(r00, rp)

    let
      n = vertCount - r
      l2 = l + n

    copyMem(memory[l].addr, memory[r].addr, n * sizeof(Vec4))

    p.fill = memory[offset ..< l2]

    when defined(NVG_DEBUG_CORE):
      printf("l[%u] r[%u] n[%u]\n", l, r, n)
      printf("---->\n")
      for v in p.fill.toOpenArray:
        printf("%.6f %.6f %.6f %.6f\n", v.x, v.y, v.z, v.w)
      printf("---->\n")

    l = l2
    offset = l2
    r = vertCount

proc dashStroke(ctx: ptr ContextObj, scale, strokeWidth: float32) =
  let
    c = ctx.cache.addr
    state = ctx.lastState

    n = c.paths.len

  var dashSum = sum(state.dashArray)
  if (n and 0x1) > 0:
    dashSum = dashSum + dashSum

  var dashOffset = state.dashOffset mod dashSum
  if dashOffset < 0:
    dashOffset = dashOffset + dashSum

  var dash0 = 0
  while dashOffset > state.dashArray[dash0]:
    dashOffset = dashOffset - state.dashArray[dash0]
    dash0 = succ(dash0) mod state.dashArray.len

  var idx = 0
  while idx < c.paths.len:
    var
      totalDist = float32(0)
      dashLen = (state.dashArray[dash0] - dashOffset) * scale
      dashState = true
      dash = dash0

      p = c.paths[idx].addr
      p0 = c.points[p.offset]

      i = p.offset + 1
      j =
        if p.closed:
          p.offset + p.pointCount + 1
        else:
          p.offset + p.pointCount

    c.createPath()
    p = c.paths[idx].addr

    c.createPoint(p0)

    while i <= j:
      let
        k = j mod p.pointCount
        dp = c.points[i + k] - p0
        dist = dp.length

      if totalDist + dist > dashLen:
        let
          d = (dashLen - totalDist) / dist
          p1 = p0 + dp * d

        if not dashState:
          c.createPath()
          p = c.paths[idx].addr

        c.createPoint(p1)

        dashState = not dashState
        dash = (dash + 1) mod state.dashArray.len
        dashLen = state.dashArray[dash] * scale
        totalDist = 0
        p0 = p1
      else:
        totalDist = totalDist + dist
        p0 = c.points[i + k]
        if dashState:
          c.createPoint(p0)
        inc i, 1

proc expandFill(ctx: ptr ContextObj) =
  let
    c = ctx.cache.addr
    vertCount = block:
      var count = 0

      for p in c.paths.items:
        inc count, p.pointCount

      count

  c.verts.setLenUninit(vertCount)

  var pos = 0
  let memory = piece(c.verts)

  for idx in 0 ..< c.paths.len:
    let
      p = c.paths[idx].addr
      oldPos = pos

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

      p1 = default(ptr Vec2)
      p0 = c.points[j].addr

    while i <= j:
      p1 = c.points[i].addr

      when defined(NVG_DEBUG_CORE):
        printf(
          "line[%u] %u %.6f %.6f %.6f %.6f\n",
          0,
          succ(pos),
          p0[].x,
          p0[].y,
          p1[].x,
          p1[].y,
        )

      memory[pos] = vec4(p0[].x, p0[].y, p1[].x, p1[].y)

      inc i, 1
      inc pos, 1

      p0 = p1

    p.fill = memory[oldPos ..< pos]

proc fill*(ctx: ptr ContextObj) =
  let
    state = ctx.lastState
    c = ctx.cache.addr

  when defined(NVG_DEBUG_CORE):
    printf("fill begin\n")

  ctx.flattenPaths()
  ctx.expandFill()

  updateBounds(c, c.paths, ctx.distTolSq)

  var pathFlags = default(PathFlags)
  if state.fillRule == EvenOdd:
    pathFlags.evenOdd = true

  ctx.params.fillImpl(
    ctx.ctx, state.fill.addr, state.compositeOperation, pathFlags, c.bounds, c.paths
  )

  when defined(NVG_DEBUG_CORE):
    printf("fill end\n")

  for idx in 0 ..< c.paths.len:
    # let p = c.paths[idx].addr

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
    strokeWidth = clamp(state.strokeWidth * s, 1, 200)
    c = ctx.cache.addr

  var paint = state.stroke
  paint.innerColor.a = state.globalAlpha * paint.innerColor.a
  paint.outerColor.a = state.globalAlpha * paint.outerColor.a

  when defined(NVG_DEBUG_CORE):
    printf("stroke begin\n")

  ctx.flattenPaths()

  # if state.dashArray.len > 0:
  #   ctx.dashStroke(s, strokeWidth)

  ctx.expandStroke(state.lineCap, state.lineJoin, strokeWidth, state.miterLimit)

  updateBounds(c, c.paths, ctx.distTolSq)

  ctx.params.fillImpl(
    ctx.ctx, state.stroke.addr, state.compositeOperation, PathFlags(), c.bounds, c.paths
  )

  when defined(NVG_DEBUG_CORE):
    printf("stroke end\n")

  for idx in 0 ..< c.paths.len:
    # let p = c.paths[idx].addr

    inc ctx.drawCallCount, 2

proc begin*(ctx: ptr ContextObj, view: Vec2, devicePixelRatio: float32) =
  ctx.stateCount = 0

  ctx.save()
  ctx.reset()

  ctx.setDevicePixelRatio(devicePixelRatio)

  ctx.params.viewportImpl(ctx.ctx, view, devicePixelRatio)

  ctx.drawCallCount = 0

proc flush*(ctx: ptr ContextObj) =
  ctx.params.flushImpl(ctx.ctx)
