import std/hashes
import std/math

import ./backend
import ./core
import ./math
import ./path
import ./pieces
import ./tracy

type Cache* = object
  lastId: uint
  lastVersion: uint32
  lastHash: Hash
  points: seq[Vec2]
  flattenedPathCount: int32
  flattenedPathPointCount: int32
  strokeOffset: int32
  strokeEndOffset: int32
  paths: seq[DrawPath]
  curPath: ptr DrawPath
  storage: seq[Vec4]

proc clear*(c: var Cache) {.inline, raises: [].} =
  c.lastId = 0
  c.lastVersion = 0
  c.lastHash = Hash(0)
  c.curPath = nil
  c.points.setLen(0)
  c.flattenedPathCount = 0
  c.flattenedPathPointCount = 0
  c.strokeOffset = 0
  c.strokeEndOffset = 0
  c.paths.setLen(0)

proc addPath(c: var Cache) {.inline, raises: [].} =
  let idx = c.paths.len
  c.paths.setLen(idx + 1)

  let p = c.paths[idx].addr
  p.offset = int32(c.points.len)

  c.curPath = p

proc addPoint(c: var Cache, p: Vec2) {.inline, raises: [].} =
  inc c.curPath.pointCount, 1
  c.points.add(p)

proc quadCurve(
    c: var Cache, p1, p2, p3: Vec2, level: int32, tessTolSq, distTolSq: float32
) =
  let
    d = p3 - p1
    distSq = d.length2

  if distSq < distTolSq:
    if not nearEqual(p1, p3, distTolSq):
      c.addPoint(p3)
    return

  let
    det = cross(d, p2 - p1)
    perpDistSq = (det * det) / distSq

  if perpDistSq < tessTolSq or level >= 9:
    if not nearEqual(p1, p3, distTolSq):
      c.addPoint(p3)
  else:
    let
      p12 = (p1 + p2) * 0.5
      p23 = (p2 + p3) * 0.5
      p123 = (p12 + p23) * 0.5

    c.quadCurve(p1, p12, p123, level + 1, tessTolSq, distTolSq)
    c.quadCurve(p123, p23, p3, level + 1, tessTolSq, distTolSq)

proc bezier(
    c: var Cache, p1, p2, p3, p4: Vec2, level: int32,
    tessTolSq, distTolSq: float32
) =
  let
    d = p4 - p1
    distSq = d.length2

  if distSq < distTolSq:
    if not nearEqual(p1, p4, distTolSq):
      c.addPoint(p4)
    return

  let
    p12 = (p1 + p2) * 0.5
    p23 = (p2 + p3) * 0.5
    p34 = (p3 + p4) * 0.5
    p123 = (p12 + p23) * 0.5
    p234 = (p23 + p34) * 0.5
    p1234 = (p123 + p234) * 0.5

  let
    midDeviation = cross(d, p1234 - p1)
    quarterDeviation = cross(d, p123 - p1)
    threeQuarterDeviation = cross(d, p234 - p1)

  let
    maxCross = max(max(abs(midDeviation), abs(quarterDeviation)), abs(threeQuarterDeviation))
    maxCrossSq = maxCross * maxCross
    toleranceSq = tessTolSq * distSq

  if maxCrossSq < toleranceSq or level >= 9:
    if not nearEqual(p1, p4, distTolSq):
      c.addPoint(p4)
    return

  c.bezier(p1, p12, p123, p1234, level + 1, tessTolSq, distTolSq)
  c.bezier(p1234, p234, p34, p4, level + 1, tessTolSq, distTolSq)

proc updateBounds(paths: openArray[DrawPath]) =
  if paths.len <= 0:
    return

  for idx in 0 ..< paths.len:
    let p = paths[idx].addr
    if p.fill.len <= 0:
      continue

    var bounds = default(Bounds)
    bounds.xMin = 1e6
    bounds.yMin = 1e6
    bounds.xMax = -1e6
    bounds.yMax = -1e6

    for v in p.fill.toOpenArray:
      bounds.xMin = min(bounds.xMin, v[2])
      bounds.yMin = min(bounds.yMin, v[3])
      bounds.xMax = max(bounds.xMax, v[2])
      bounds.yMax = max(bounds.yMax, v[3])

    p.bounds = bounds

proc flattenPaths*(
    c: var Cache, path: Path, matrix: Mat2d, tessTolSq, distTolSq: float32
) =
  let
    zone = zoneBegin("cache.flattenPaths")
  defer: zone.zoneEnd()

  var
    id = uint(0)
    hash = hash(matrix)

  if c.lastVersion == path.version and c.lastHash == hash:
    if not path.isEmpty:
      id = cast[uint](path.commands[0].addr)
      if c.lastId == id:
        return

  c.clear()
  c.lastHash = hash
  c.lastId = id
  c.lastVersion = path.version

  for cmd in path.commands:
    case cmd.command
    of Command.MOVE:
      c.addPath()

      let p = matrix * cmd.p1
      c.addPoint(p)

    of Command.LINE:
      if c.curPath.isNil:
        c.addPath()
        c.addPoint(vec2(0, 0))

      if not c.curPath.isNil:
        let p = matrix * cmd.p1

        if c.curPath.pointCount > 0:
          let idx = c.curPath.offset + c.curPath.pointCount - 1
          if nearEqual(c.points[idx], p, distTolSq):
            continue

        c.addPoint(p)

    of Command.CURVE:
      if c.curPath.isNil:
        c.addPath()
        c.addPoint(vec2(0, 0))

      if c.curPath.pointCount > 0:
        let
          idx = c.curPath.offset + c.curPath.pointCount - 1
          cp = matrix * cmd.p1
          p = matrix * cmd.p2

        c.quadCurve(c.points[idx], cp, p, 0, tessTolSq, distTolSq)

    of Command.BEZIER:
      if c.curPath.isNil:
        c.addPath()
        c.addPoint(vec2(0, 0))

      if c.curPath.pointCount > 0:
        let
          idx = c.curPath.offset + c.curPath.pointCount - 1
          cp1 = matrix * cmd.p1
          cp2 = matrix * cmd.p2
          p = matrix * cmd.p3

        c.bezier(c.points[idx], cp1, cp2, p, 0, tessTolSq, distTolSq)

    of Command.CLOSE:
      if not c.curPath.isNil:
        c.curPath.closed = true

  let pathCount = int32(c.paths.len)

  for idx in 0 ..< pathCount:
    let p = c.paths[idx].addr

    if p.pointCount <= 1:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    if nearEqual(c.points[j], c.points[i], distTolSq):
      dec j
      dec p.pointCount

      p.closed = true

  c.strokeOffset = 0
  c.strokeEndOffset = pathCount
  c.flattenedPathCount = pathCount
  c.flattenedPathPointCount = int32(c.points.len)

proc curveDivs(r, arc, tol: float32): int32 {.inline.} =
  let da = arccos(r / (r + tol)) * 2
  max(2, int32(ceil(arc / da)))

proc arcJoin(
    memory: Piece[Vec4], idx: int32, p0, p1, c: Vec2, w: float32, nCap, dir: int32
): int32 =
  var
    pos = idx
    ax = float32(0)
    ay = float32(0)

    a0 = atan(p0 - c)
    a1 = atan(p1 - c)

  if a1 > a0:
    a1 = a1 - PI * 2

  let n = clamp(int32(ceil((a0 - a1) / float32(PI) * float32(nCap))), 2, nCap)
  for i in 0 ..< n:
    let
      u = float32(i) / float32(n - 1)
      a = a0 + u * (a1 - a0)
      px = c[0] + cos(a) * w
      py = c[1] + sin(a) * w

    if i > 0:
      if dir < 0:
        dec pos, 1
        memory[pos] = vec4(ax, ay, px, py)
      else:
        memory[pos] = vec4(ax, ay, px, py)
        inc pos, 1

    ax = px
    ay = py

  pos

proc dashStroke*(
    c: var Cache,
    scale, strokeWidth: float32,
    dashOffset: float32,
    dashArray: openArray[float32],
) =
  var dashSum = sum(dashArray)
  if (dashArray.len and 0x1) > 0:
    dashSum = dashSum + dashSum

  var dashOffset = dashOffset mod dashSum
  if dashOffset < 0:
    dashOffset = dashOffset + dashSum

  var dash0 = 0
  while dashOffset > dashArray[dash0]:
    dashOffset = dashOffset - dashArray[dash0]
    dash0 = succ(dash0) mod dashArray.len

  c.curPath = nil
  if c.paths.len > c.flattenedPathCount:
    c.paths.setLenUninit(c.flattenedPathCount)
    c.points.setLenUninit(c.flattenedPathPointCount)

  for idx in 0 ..< c.flattenedPathCount:
    let
      p = c.paths[idx].addr
      pointCount = p.pointCount
      pointOffset = p.offset

    if pointCount <= 1:
      continue

    var
      totalDist = float32(0)
      dashLen = (dashArray[dash0] - dashOffset) * scale
      dashState = true
      dashIdx = dash0

      p0 = c.points[pointOffset]

      i = pointOffset + 1
      j =
        if p.closed:
          pointOffset + pointCount
        else:
          pointOffset + pointCount - 1

    c.addPath()
    c.addPoint(p0)

    while i <= j:
      let
        k = pointOffset + (i - pointOffset) mod pointCount
        dp = c.points[k] - p0
        dist = dp.length

      if totalDist + dist >= dashLen:
        let
          t = (dashLen - totalDist) / dist
          p1 = p0 + dp * t

        if not dashState:
          c.addPath()
        c.addPoint(p1)

        dashState = not dashState
        dashIdx = succ(dashIdx) mod dashArray.len
        dashLen = dashArray[dashIdx] * scale
        totalDist = 0
        p0 = p1
      else:
        totalDist = totalDist + dist
        p0 = c.points[k]
        if dashState:
          c.addPoint(p0)
        inc i, 1

  c.strokeOffset = c.flattenedPathCount
  c.strokeEndOffset = int32(c.paths.len)

proc expandStroke*(
    c: var Cache,
    lineCap: LineCap,
    lineJoin: LineJoin,
    strokeWidth, miterLimit: float32,
    tessTol, distTolSq: float32,
): Piece[DrawPath] =
  let
    zone = zoneBegin("cache.expandStroke")
  defer: zone.zoneEnd()

  let
    w = float32(0.5 * strokeWidth)
    nCap = curveDivs(w, PI, tessTol)
    mLimSq = w * w * miterLimit * miterLimit

  let vertCount = block:
    var count = int32(0)
    for p in c.paths:
      if lineJoin == RoundJoin or lineCap == RoundCap:
        inc count, (p.pointCount * (nCap + 2) + 1) * 2
      else:
        inc count, (p.pointCount * 2 + 1) * 2
    6 * count

  c.storage.setLenUninit(vertCount)

  var
    l = int32(0)
    r = vertCount
    n = int32(0)
    offset = l

  let memory = piece(c.storage)

  template emitLeft(v1, v2) =
    inc n, 1
    memory[l] = vec4(v1[0], v1[1], v2[0], v2[1])
    inc l

  template emitRight(v1, v2) =
    inc n, 1
    dec r
    memory[r] = vec4(v1[0], v1[1], v2[0], v2[1])

  let
    strokeOffset = c.strokeOffset
    strokeEndOffset = c.strokeEndOffset

  for idx in strokeOffset ..< strokeEndOffset:
    let p = c.paths[idx].addr

    if p.pointCount <= 0:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

      p0 = default(ptr Vec2)
      p1 = default(ptr Vec2)
      p2 = default(ptr Vec2)

      tempPoint = default(Vec2)

    let closed = p.closed and p.pointCount > 2

    if closed:
      p0 = c.points[i + p.pointCount - 2].addr
      p1 = c.points[i + p.pointCount - 1].addr
    elif p.pointCount == 1:
      if lineCap == ButtCap:
        continue

      p0 = c.points[i].addr
      p1 = tempPoint.addr

      tempPoint[0] = p0[][0] + w / float32(256)
      tempPoint[1] = p0[][1]

      inc i, 2
    else:
      p0 = c.points[i].addr

      inc i, 1
      p1 = c.points[i].addr

      inc i, 1

    var
      d01 = p1[] - p0[]
      n01 = normalized(vec2(-d01[1], d01[0]))

      lp = default(Vec2)
      rp = default(Vec2)

      l00 = default(Vec2)
      r00 = default(Vec2)

      wn01 = n01 * w

    if not closed:
      lp = p0[] + wn01
      rp = p0[] - wn01

      if lineCap == ButtCap:
        emitLeft(rp, lp)
      elif lineCap == SquareCap:
        let
          capExt = vec2(wn01[1], -wn01[0])
          v1 = vec2(rp[0] - capExt[0], rp[1] - capExt[1])
          v2 = vec2(lp[0] - capExt[0], lp[1] - capExt[1])

        emitLeft(rp, v1)
        emitLeft(v1, v2)
        emitLeft(v2, lp)
      elif lineCap == RoundCap:
        l = arcJoin(memory, l, rp, lp, p0[], w, nCap, 1)

    while i <= j:
      p2 = c.points[i].addr

      let
        d12 = p2[] - p1[]
        n12 = normalized(vec2(-d12[1], d12[0]))
        wn12 = n12 * w
        miterDenom = max(1e-6f, 1 + dot(n01, n12))
        miterDir = (n01 + n12) / miterDenom
        wMiter = miterDir * w
        mLenSq = miterDir.length2 * w * w
        l01Sq = d01.length2
        l12Sq = d12.length2

        join = if lineJoin == MiterJoin and mLenSq <= mLimSq and
          miterDenom > 1e-6f: MiterJoin else: BevelJoin
        outerJoin = if lineJoin == RoundJoin: RoundJoin else: join
        innerJoin = if l01Sq < mLenSq or l12Sq < mLenSq: BevelJoin else: join

        left = cross(d01, d12) > 0
        lJoin = if left: innerJoin else: outerJoin
        rJoin = if left: outerJoin else: innerJoin

      var
        l01 = default(Vec2)
        l12 = default(Vec2)
        r01 = default(Vec2)
        r12 = default(Vec2)

      if lJoin == MiterJoin:
        let p = p1[] + wMiter
        l01 = p
        l12 = p
      else:
        l01 = p1[] + wn01
        l12 = p1[] + wn12

      if i > p.offset:
        emitLeft(lp, l01)
      else:
        l00 = l01

      if lJoin == RoundJoin:
        l = arcJoin(memory, l, l01, l12, p1[], w, nCap, 1)
      elif lJoin == BevelJoin:
        emitLeft(l01, l12)

      lp = l12

      if rJoin == MiterJoin:
        let p = p1[] - wMiter
        r01 = p
        r12 = p
      else:
        r01 = p1[] - wn01
        r12 = p1[] - wn12

      if i > p.offset:
        emitRight(r01, rp)
      else:
        r00 = r01

      if rJoin == RoundJoin:
        r = arcJoin(memory, r, r12, r01, p1[], w, nCap, -1)
      elif rJoin == BevelJoin:
        emitRight(r12, r01)

      rp = r12

      p0 = p1
      p1 = p2

      inc i, 1

      d01 = d12
      n01 = n12

      wn01 = n01 * w

    if not closed:
      let
        l01 = p1[] + wn01
        r01 = p1[] - wn01

      emitLeft(lp, l01)
      lp = l01
      emitRight(r01, rp)
      rp = r01

      if lineCap == ButtCap:
        emitLeft(lp, rp)
      elif lineCap == SquareCap:
        let
          capExt = vec2(wn01[1], -wn01[0])
          v1 = vec2(lp[0] + capExt[0], lp[1] + capExt[1])
          v2 = vec2(rp[0] + capExt[0], rp[1] + capExt[1])

        emitLeft(lp, v1)
        emitLeft(v1, v2)
        emitLeft(v2, rp)
      elif lineCap == RoundCap:
        l = arcJoin(memory, l, lp, rp, p1[], w, nCap, 1)
    else:
      emitLeft(lp, l00)
      emitRight(r00, rp)

    let
      n = vertCount - r
      l2 = l + n

    copyMem(memory[l].addr, memory[r].addr, n * sizeof(Vec4))

    p.fill = memory[offset ..< l2]

    l = l2
    offset = l2
    r = vertCount

  result = piece(c.paths.toOpenArray(strokeOffset, strokeEndOffset - 1))
  updateBounds(result.toOpenArray)

proc expandFill*(c: var Cache, distTolSq: float32): Piece[DrawPath] =
  let
    zone = zoneBegin("cache.expandFill")
  defer: zone.zoneEnd()

  let vertCount = block:
    var count = 0

    for p in c.paths:
      inc count, p.pointCount

    count

  c.storage.setLenUninit(vertCount)

  var pos = 0
  let memory = piece(c.storage)

  let
    fillOffset = 0
    fillEndOffset = c.flattenedPathCount

  for idx in fillOffset ..< fillEndOffset:
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

      memory[pos] = vec4(p0[][0], p0[][1], p1[][0], p1[][1])

      inc i, 1
      inc pos, 1

      p0 = p1

    p.fill = memory[oldPos ..< pos]

  result = piece(c.paths.toOpenArray(fillOffset, fillEndOffset - 1))
  updateBounds(result.toOpenArray)
