import ./core
import ./math
import ./params
import ./path
import ./pieces

import std/math

type Cache* = object
  points: seq[Vec2]
  contours*: seq[Contour]
  bounds*: Vec4
  curPath: ptr Contour
  storage: seq[Vec4]

proc clear*(c: var Cache) {.inline, raises: [].} =
  c.curPath = nil
  c.points.setLen(0)
  c.contours.setLen(0)

proc addContour(c: var Cache) {.inline, raises: [].} =
  let idx = c.contours.len
  c.contours.setLen(idx + 1)

  let p = c.contours[idx].addr
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
    d2 = cross(d, p2 - p1)
    distSq = (d2 * d2) / d.lengthSq

  if distSq < tessTolSq or level >= 9:
    if not equals(p1, p3, distTolSq):
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
  let d = p4 - p1
  let distSq = d.lengthSq

  if distSq < distTolSq:
    if not equals(p1, p4, distTolSq):
      c.addPoint(p4)
    return

  let
    p12 = (p1 + p2) * 0.5
    p23 = (p2 + p3) * 0.5
    p34 = (p3 + p4) * 0.5
    p123 = (p12 + p23) * 0.5
    p234 = (p23 + p34) * 0.5
    p1234 = (p123 + p234) * 0.5

  let midDeviation = cross(d, p1234 - p1)
  let quarterDeviation = cross(d, p123 - p1)
  let threeQuarterDeviation = cross(d, p234 - p1)

  let maxCross = max(max(abs(midDeviation), abs(quarterDeviation)), abs(threeQuarterDeviation))
  let maxCrossSq = maxCross * maxCross
  let toleranceSq = tessTolSq * distSq

  if maxCrossSq < toleranceSq or level >= 9:
    if not equals(p1, p4, distTolSq):
      c.addPoint(p4)
    return

  c.bezier(p1, p12, p123, p1234, level + 1, tessTolSq, distTolSq)
  c.bezier(p1234, p234, p34, p4, level + 1, tessTolSq, distTolSq)

proc updateBounds(c: var Cache, distTolSq: float32) =
  c.bounds = vec4(1e6, 1e6, -1e6, -1e6)

  for idx in 0 ..< c.contours.len:
    let p = c.contours[idx].addr

    p.bounds = vec4(1e6, 1e6, -1e6, -1e6)

    if p.fill.len <= 0:
      continue

    for v in p.fill.toOpenArray:
      p.bounds[0] = min(p.bounds[0], v[2])
      p.bounds[1] = min(p.bounds[1], v[3])
      p.bounds[2] = max(p.bounds[2], v[2])
      p.bounds[3] = max(p.bounds[3], v[3])

    c.bounds[0] = min(p.bounds[0], c.bounds[0])
    c.bounds[1] = min(p.bounds[1], c.bounds[1])
    c.bounds[2] = max(p.bounds[2], c.bounds[2])
    c.bounds[3] = max(p.bounds[3], c.bounds[3])

proc flattenPaths*(
    c: var Cache, path: Path, matrix: Mat2d, tessTolSq, distTolSq: float32
) =
  if c.contours.len > 0:
    c.curPath = nil
    c.contours.setLen(0)

  for command, vals in path.commands:
    case command
    of Command.MOVE:
      c.addContour()

      let p = vec2(vals[0], vals[1]) * matrix
      c.addPoint(p)

    of Command.LINE:
      if not c.curPath.isNil:
        let p = vec2(vals[0], vals[1]) * matrix

        if c.curPath.pointCount > 0:
          let idx = c.curPath.offset + c.curPath.pointCount - 1
          if equals(c.points[idx], p, distTolSq):
            continue

        c.addPoint(p)

    of Command.CURVE:
      if not c.curPath.isNil:
        if c.curPath.pointCount > 0:
          let
            idx = c.curPath.offset + c.curPath.pointCount - 1
            cp = vec2(vals[0], vals[1]) * matrix
            p = vec2(vals[2], vals[3]) * matrix

          c.quadCurve(c.points[idx], cp, p, 0, tessTolSq, distTolSq)

    of Command.BEZIER:
      if not c.curPath.isNil:
        if c.curPath.pointCount > 0:
          let
            idx = c.curPath.offset + c.curPath.pointCount - 1
            cp1 = vec2(vals[0], vals[1]) * matrix
            cp2 = vec2(vals[2], vals[3]) * matrix
            p = vec2(vals[4], vals[5]) * matrix

          c.bezier(c.points[idx], cp1, cp2, p, 0, tessTolSq, distTolSq)

    of Command.CLOSE:
      if not c.curPath.isNil:
        c.curPath.closed = true

  for idx in 0 ..< c.contours.len:
    let p = c.contours[idx].addr

    if p.pointCount <= 1:
      continue

    var
      i = p.offset
      j = p.offset + p.pointCount - 1

    if equals(c.points[j], c.points[i], distTolSq):
      dec j
      dec p.pointCount

      p.closed = true

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

    a0 = angle(p0 - c)
    a1 = angle(p1 - c)

  if a1 > a0:
    a1 = a1 - PI * 2

  let n = clamp(int32(ceil((a0 - a1) / float32(PI) * float32(nCap))), 2, nCap)
  for i in 0 ..< n:
    let
      u = float32(i) / float32(n - 1)
      a = a0 + u * (a1 - a0)
      rx = c[0] + cos(a) * w
      ry = c[1] + sin(a) * w

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

  let contours = move c.contours
  c.curPath = nil

  for idx in 0 ..< contours.len:
    let p = contours[idx].addr

    if p.pointCount <= 1:
      continue

    var
      totalDist = float32(0)
      dashLen = (dashArray[dash0] - dashOffset) * scale
      dashState = true
      dashIdx = dash0

      p0 = c.points[p.offset]

      i = p.offset + 1
      j =
        if p.closed:
          p.offset + p.pointCount
        else:
          p.offset + p.pointCount - 1

    c.addContour()
    c.addPoint(p0)

    while i <= j:
      let
        k = p.offset + (i - p.offset) mod p.pointCount
        dp = c.points[k] - p0
        dist = dp.length

      if totalDist + dist >= dashLen:
        let
          d = (dashLen - totalDist) / dist
          p1 = p0 + dp * d

        if not dashState:
          c.addContour()
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

proc expandStroke*(
    c: var Cache,
    lineCap: LineCap,
    lineJoin: LineJoin,
    strokeWidth, miterLimit: float32,
    tessTol, distTolSq: float32,
) =
  let
    w = float32(0.5 * strokeWidth)
    nCap = curveDivs(w, PI, tessTol)
    mLimSq = w * w * miterLimit * miterLimit

  let vertCount = block:
    var count = default(int32)
    for p in c.contours:
      if lineJoin == RoundJoin or lineCap == RoundCap:
        inc count, (p.pointCount * (nCap + 2) + 1) * 2
      else:
        inc count, (p.pointCount * 2 + 1) * 2
    6 * count

  c.storage.setLenUninit(vertCount)

  var
    l = default(int32)
    r = vertCount
    n = default(int32)
    offset = l

  let memory = piece(c.storage)

  template incp(v1, v2) =
    inc n, 1
    memory[l] = vec4(v1[0], v1[1], v2[0], v2[1])
    inc l

  template decp(v1, v2) =
    inc n, 1
    dec r
    memory[r] = vec4(v1[0], v1[1], v2[0], v2[1])

  for idx in 0 ..< c.contours.len:
    let p = c.contours[idx].addr

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

      tmp[0] = p0[][0] + w / float32(256)
      tmp[1] = p0[][1]

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
        incp(rp, lp)
      elif lineCap == SquareCap:
        let
          cd = vec2(wn01[1], -wn01[0])
          v1 = vec2(rp[0] - cd[0], rp[1] - cd[1])
          v2 = vec2(lp[0] - cd[0], lp[1] - cd[1])

        incp(rp, v1)
        incp(v1, v2)
        incp(v2, lp)
      elif lineCap == RoundCap:
        l = arcJoin(memory, l, rp, lp, p0[], w, nCap, 1)

    while i <= j:
      p2 = c.points[i].addr

      let
        d12 = p2[] - p1[]
        n12 = normalized(vec2(-d12[1], d12[0]))
        wn12 = n12 * w
        miterDenom = max(1e-6f, 1 + dot(n01, n12))
        e = (n01 + n12) / miterDenom
        we = e * w
        mLenSq = e.lengthSq * w * w
        l01Sq = d01.lengthSq
        l12Sq = d12.lengthSq

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
        let p = p1[] + we
        l01 = p
        l12 = p
      else:
        l01 = p1[] + wn01
        l12 = p1[] + wn12

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

      wn01 = n01 * w

    if not closed:
      let
        l01 = p1[] + wn01
        r01 = p1[] - wn01

      incp(lp, l01)
      lp = l01
      decp(r01, rp)
      rp = r01

      if lineCap == ButtCap:
        incp(lp, rp)
      elif lineCap == SquareCap:
        let
          cd = vec2(wn01[1], -wn01[0])
          v1 = vec2(lp[0] + cd[0], lp[1] + cd[1])
          v2 = vec2(rp[0] + cd[0], rp[1] + cd[1])

        incp(lp, v1)
        incp(v1, v2)
        incp(v2, rp)
      elif lineCap == RoundCap:
        l = arcJoin(memory, l, lp, rp, p1[], w, nCap, 1)
    else:
      incp(lp, l00)
      decp(r00, rp)

    let
      n = vertCount - r
      l2 = l + n

    copyMem(memory[l].addr, memory[r].addr, n * sizeof(Vec4))

    p.fill = memory[offset ..< l2]

    l = l2
    offset = l2
    r = vertCount

  c.updateBounds(distTolSq)

proc expandFill*(c: var Cache, distTolSq: float32) =
  let vertCount = block:
    var count = 0

    for p in c.contours:
      inc count, p.pointCount

    count

  c.storage.setLenUninit(vertCount)

  var pos = 0
  let memory = piece(c.storage)

  for idx in 0 ..< c.contours.len:
    let
      p = c.contours[idx].addr
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

  c.updateBounds(distTolSq)
