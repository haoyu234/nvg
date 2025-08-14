import ./core
import ./math
import ./params
import ./path
import ./pieces

import std/math

when defined(NVG_DEBUG_CORE):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

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

proc bezier(
    c: var Cache, p1, p2, p3, p4: Vec2, level: int, tessTol, distTolSq: float32
) =
  let
    d = p4 - p1
    d2 = cross(d, p2 - p4)
    d3 = cross(d, p3 - p4)
    d4 = d2 + d3

  if d4 * d4 < tessTol * d.lengthSq or level >= 9:
    if not equals(p1, p4, distTolSq):
      c.addPoint(p4)
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

proc updateBounds(c: var Cache, distTolSq: float32) =
  c.bounds = vec4(1e6, 1e6, -1e6, -1e6)

  for idx in 0 ..< c.contours.len:
    let p = c.contours[idx].addr

    p.bounds = vec4(1e6, 1e6, -1e6, -1e6)

    if p.fill.len <= 0:
      continue

    when defined(NVG_DEBUG_CORE):
      printf("updateBounds %u\n", idx)

    for v in p.fill.toOpenArray:
      p.bounds[0] = min(p.bounds[0], v[2])
      p.bounds[1] = min(p.bounds[1], v[3])
      p.bounds[2] = max(p.bounds[2], v[2])
      p.bounds[3] = max(p.bounds[3], v[3])

      when defined(NVG_DEBUG_CORE):
        printf(
          "x[%.6f] y[%.6f] %.6f %.6f %.6f %.6f\n",
          v[2],
          v[3],
          p.bounds[0],
          p.bounds[1],
          p.bounds[2],
          p.bounds[3],
        )

    c.bounds[0] = min(p.bounds[0], c.bounds[0])
    c.bounds[1] = min(p.bounds[1], c.bounds[1])
    c.bounds[2] = max(p.bounds[2], c.bounds[2])
    c.bounds[3] = max(p.bounds[3], c.bounds[3])

    when defined(NVG_DEBUG_CORE):
      printf(
        "- %.6f %.6f %.6f %.6f\n", c.bounds[0], c.bounds[1], c.bounds[2], c.bounds[3]
      )

proc flattenPaths*(
    c: var Cache, path: Path, matrix: Mat3, tessTol, distTolSq: float32
) =
  if c.contours.len > 0:
    c.curPath = nil
    c.contours.setLen(0)

  for command, vals in path.commands:
    case command
    of PathCommand.MOVE:
      when defined(NVG_DEBUG_CORE):
        printf("MOVE BEGIN %u\n", c.points.len)
        defer:
          printf("MOVE END %u\n", c.points.len)

      c.addContour()

      let p = matrix * vec2(vals[0], vals[1])
      c.addPoint(p)

    of PathCommand.LINE:
      when defined(NVG_DEBUG_CORE):
        printf("LINE BEGIN %u\n", c.points.len)
        defer:
          printf("LINE END %u\n", c.points.len)

      if not c.curPath.isNil:
        let p = matrix * vec2(vals[0], vals[1])

        if c.curPath.pointCount > 0:
          let idx = c.curPath.offset + c.curPath.pointCount - 1
          if equals(c.points[idx], p, distTolSq):
            continue

        c.addPoint(p)

    of PathCommand.BEZIER:
      when defined(NVG_DEBUG_CORE):
        printf("BEZIER BEGIN %u\n", c.points.len)
        defer:
          printf("BEZIER END %u\n", c.points.len)

      if not c.curPath.isNil:
        if c.curPath.pointCount > 0:
          let
            idx = c.curPath.offset + c.curPath.pointCount - 1
            cp1 = matrix * vec2(vals[0], vals[1])
            cp2 = matrix * vec2(vals[2], vals[3])
            p = matrix * vec2(vals[4], vals[5])

          c.bezier(c.points[idx], cp1, cp2, p, 0, tessTol, distTolSq)

    of PathCommand.CLOSE:
      if not c.curPath.isNil:
        c.curPath.closed = true

    of PathCommand.RESTART:
      if not c.curPath.isNil:
        c.curPath.restart = true

  when defined(NVG_DEBUG_CORE):
    printf("BEGIN flattenPaths\n")
    for v in c.points:
      printf("__ %.6f %.6f\n", v[0], v[1])
    printf("END flattenPaths\n")

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
    c.curPath.restart = p.restart
    # p = contours[idx].addr

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
          # p = contours[idx].addr

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
    var count = 0
    for p in c.contours:
      if lineJoin == RoundJoin or lineCap == RoundCap:
        inc count, (p.pointCount * (nCap + 2) + 1) * 2
      else:
        inc count, (p.pointCount * 2 + 1) * 2
    6 * count

  when defined(NVG_DEBUG_CORE):
    printf("expandStroke vertCount = %u ncap = %u\n", vertCount, nCap)

  c.storage.setLenUninit(vertCount)

  var
    l = 0
    r = vertCount
    n = default(int)
    offset = l

  let memory = piece(c.storage)

  template incp(v1, v2) =
    inc n, 1
    when defined(NVG_DEBUG_CORE):
      printf("line[%u] %u %.6f %.6f %.6f %.6f\n", 0, n, v1[0], v1[1], v2[0], v2[1])
    memory[l] = vec4(v1[0], v1[1], v2[0], v2[1])
    inc l

  template decp(v1, v2) =
    inc n, 1
    when defined(NVG_DEBUG_CORE):
      printf("line[%u] %u %.6f %.6f %.6f %.6f\n", 0, n, v1[0], v1[1], v2[0], v2[1])
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

        join =
          if lineJoin == MiterJoin and mLenSq <= mLimSq and miterDenom > 1e-6f:
            MiterJoin
          else:
            BevelJoin

        outerJoin = if lineJoin == RoundJoin: RoundJoin else: join
        innerJoin = if l01Sq < mLenSq or l12Sq < mLenSq: BevelJoin else: join

        left = cross(d01, d12) > 0
        lJoin = if left: innerJoin else: outerJoin
        rJoin = if left: outerJoin else: innerJoin

      when defined(NVG_DEBUG_CORE):
        template joinToStr(t: LineJoin): cstring =
          if t == MiterJoin:
            "MiterJoin".cstring
          elif t == BevelJoin:
            "BevelJoin".cstring
          elif t == RoundJoin:
            "RoundJoin".cstring
          else:
            "?".cstring

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
          wn01[0],
          wn01[1],
          wn12[0],
          wn12[1],
          p1[][0],
          p1[][1],
        )

        printf("l01[%.6f, %.6f] l12[%.6f, %.6f]\n", l01[0], l01[1], l12[0], l12[1])
        printf("%.6f, %.6f\n", p1[][0] + w * n01[0], p1[][1] + w * n01[1])

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

      when defined(NVG_DEBUG_CORE):
        printf(
          "x[%.6f] y[%.6f] n01x[%.6f] n01y[%.6f] l01x[%.6f] l01y[%.6f] r01x[%.6f] r01y[%.6f] w[%.6f]\n",
          p1[][0],
          p1[][1],
          n01[0],
          n01[1],
          l01[0],
          l01[1],
          r01[0],
          r01[1],
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
          cd = vec2(wn01[1], -wn01[0])
          v1 = vec2(lp[0] + cd[0], lp[1] + cd[1])
          v2 = vec2(rp[0] + cd[0], rp[1] + cd[1])

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
      # printf("l[%u] r[%u] n[%u]\n", l, r, n)

      printf("nfill[%u]\n", p.fill.len)
      printf("---->\n")
      for v in p.fill.toOpenArray:
        printf("%.6f %.6f %.6f %.6f\n", v[0], v[1], v[2], v[3])
      printf("---->\n")

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

  when defined(NVG_DEBUG_CORE):
    printf("expandFill vertCount = %u\n", vertCount)

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

      when defined(NVG_DEBUG_CORE):
        printf(
          "line[%u] %u %.6f %.6f %.6f %.6f\n",
          0,
          succ(pos),
          p0[][0],
          p0[][1],
          p1[][0],
          p1[][1],
        )

      memory[pos] = vec4(p0[][0], p0[][1], p1[][0], p1[][1])

      inc i, 1
      inc pos, 1

      p0 = p1

    p.fill = memory[oldPos ..< pos]

  c.updateBounds(distTolSq)
