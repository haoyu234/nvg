import ./core
import ./math
import ./path
import ./pieces

import std/math

type
  Edge = object
    command: Command
    p1: Vec2
    p2: Vec2
    p3: Vec2

  Distance = object
    distance: float32 = -999999
    dot: float32

  EdgeCache = object
    p: Vec2
    absDistance: float32

  DistanceSelector = object
    p: Vec2
    minDistance: Distance

  Contour = Piece[Edge]

  ShapeDistanceFinder* = object
    edgeStorage: seq[Edge]
    edgeCache: seq[EdgeCache]

    contours: seq[Contour]
    windings: seq[int8]
    selectors: seq[DistanceSelector]

proc initDistance(d: var float32) {.inline.} =
  d = -999999

proc `<`(v1, v2: Distance): bool {.inline.} =
  let
    abs1 = abs(v1.distance)
    abs2 = abs(v2.distance)
  abs1 < abs2 or (abs1 == abs2 and v1.dot < v2.dot)

proc lerp[T](p1, p2: T, weight: float32): T {.inline.} =
  p1 * (1.0f - weight) + p2 * weight

proc lerp[T](p1, p2, p3: T, weight: float32): T {.inline.} =
  lerp(lerp(p1, p2, weight), lerp(p2, p3, weight), weight)

proc point(e: Edge, weight: float32): Vec2 {.inline.} =
  case e.command
  of LINE:
    lerp(e.p1, e.p2, weight)
  of CURVE:
    lerp(e.p1, e.p2, e.p3, weight)
  else:
    vec2(0, 0)

proc merge(s: var DistanceSelector, s2: DistanceSelector) {.inline.} =
  if s2.minDistance < s.minDistance:
    s.minDistance = s2.minDistance

proc distance(s: DistanceSelector): float32 {.inline.} =
  s.minDistance.distance

proc sign[T](t: T): T {.inline.} =
  if t > T(0):
    1
  else:
    -1

proc signZ[T](t: T): T {.inline.} =
  if t > T(0):
    1
  elif t < T(0):
    -1
  else:
    0

proc winding(contour: Piece[Edge]): int8 =
  if contour.len <= 0:
    result = 0
    return

  template shoelace(a, b: Vec2): float32 =
    (b[0] - a[0]) * (a[1] + b[1])

  var
    total = default(float32)

  if contour.len == 1:
    let
      a = contour[0].p1
      b = contour[0].point(1.0f / 3)
      c = contour[0].point(2.0f / 3)

    total = total + shoelace(a, b)
    total = total + shoelace(b, c)
    total = total + shoelace(c, a)

  elif contour.len == 2:
    let
      a = contour[0].p1
      b = contour[0].point(0.5f)
      c = contour[1].p1
      d = contour[1].point(0.5f)

    total = total + shoelace(a, b)
    total = total + shoelace(b, c)
    total = total + shoelace(c, d)
    total = total + shoelace(d, a)

  else:
    var
      prev = contour[^1].p1

    for v in contour.toOpenArray:
      total = total + shoelace(prev, v.p1)
      prev = v.p1

  int8(signZ(total))

proc orthonormal(p: Vec2): Vec2 {.inline.} =
  let len = p.length
  if len != 0:
    vec2(p[1] / len, -p[0] / len)
  else:
    vec2(0, 0)

proc solveQuadratic(res: var array[3, float32], a, b, c: float32): int32 =
  if a == 0 or abs(b) > 1e12 * abs(a):
    if b == 0:
      if c == 0:
        result = -1
      else:
        result = 0
      return

    res[0] = -c / b
    result = 1
    return

  let ta = 2 * a
  var dscr = b * b - 4 * a * c
  if dscr > 0:
    dscr = sqrt(dscr)
    res[0] = (-b + dscr) / ta
    res[1] = (-b - dscr) / ta
    result = 2
  elif dscr == 0:
    res[0] = -b / ta
    result = 1
  else:
    result = 0

proc solveCubicNormed(res: var array[3, float32], a, b, c: float32): int32 =
  let
    a2 = a * a
    q = 1 / 9.0f * (a2 - 3 * b)
    r = 1 / 54.0f * (a * (2 * a2 - 9 * b) + 27 * c)
    r2 = r * r
    q3 = q * q * q

    f = 1.0f / 3.0f

  let na = a * f
  if r2 < q3:
    var t = r / sqrt(q3)
    if t > 1: t = 1
    if t < -1: t = -1
    t = arccos(t)
    let nq = -2 * sqrt(q)
    res[0] = nq * cos(f * t) - na
    res[1] = nq * cos(f * (t + 2 * PI)) - na
    res[2] = nq * cos(f * (t - 2 * PI)) - na
    result = 3
    return

  let
    u0 = pow(abs(r) + sqrt(r2 - q3), f)
    u = if r < 0:
        u0
      else:
        -u0
    v = if u == 0:
        float32(0)
      else:
        q / u

  res[0] = (u + v) - na
  if u == v or abs(u - v) < 1e-12 * abs(u + v):
    res[1] = -0.5f * (u + v) - na
    result = 2
  else:
    result = 1

proc solveCubic(res: var array[3, float32], a, b, c, d: float32): int32 =
  if a != 0:
    let bn = b / a
    if abs(bn) < 1e6:
      result = solveCubicNormed(res, bn, c / a, d / a)
      return

  result = solveQuadratic(res, b, c, d)
  return

proc direction(p1, p2, p3: Vec2, tp: static int): Vec2 =
  when tp == 0:
    let tangent = p2 - p1
  else:
    let tangent = p3 - p2

  if tangent[0] == 0 and tangent[1] == 0:
    p3 - p1
  else:
    tangent

proc signedDistance(origin, p1, p2: Vec2): Distance =
  let
    aq = origin - p1
    ab = p2 - p1
    param = dot(aq, ab) / dot(ab, ab)

  let
    eq =
      if param > 0.5f:
        (p2 - origin)
      else:
        (p1 - origin)
    endpointDistance = eq.length

  if param > 0 and param < 1:
    let orthoDistance = dot(orthonormal(ab), aq)
    if abs(orthoDistance) < endpointDistance:
      result.distance = orthoDistance
      result.dot = 0
      return

  result.distance = sign(cross(aq, ab)) * endpointDistance
  result.dot = dot(ab.normalized, eq.normalized)

proc signedDistance(origin, p1, p2, p3: Vec2): Distance =
  let
    qa = p1 - origin
    ab = p2 - p1
    br = p3 - p2 - ab

  let
    a = dot(br, br)
    b = 3 * dot(ab, br)
    c = 2 * dot(ab, ab) + dot(qa, br)
    d = dot(qa, ab)

  var
    res = default(array[3, float32])

  let n = solveCubic(res, a, b, c, d)

  var
    param = default(float32)
    epDir = direction(p1, p2, p3, 0)
    minDistance = sign(cross(epDir, qa)) * qa.length

  block:
    let distance = (p3 - origin).length
    if distance < abs(minDistance):
      epDir = direction(p1, p2, p3, 1)
      minDistance = sign(cross(epDir, p3 - origin)) * distance
      param = dot(origin - p2, epDir) / dot(epDir, epDir)
    else:
      param = -dot(qa, epDir) / dot(epDir, epDir)

  for idx in 0 ..< n:
    if res[idx] > 0 and res[idx] < 1:
      let
        qe = qa + ab * (2 * res[idx]) + br * (res[idx] * res[idx])
        distance = qe.length

      if distance <= abs(minDistance):
        minDistance = sign(cross(ab + br * res[idx], qe)) * distance
        param = res[idx]

  if param >= 0 and param <= 1:
    result.dot = 0
  elif param < 0.5f:
    result.dot = abs(dot(direction(p1, p2, p3, 0).normalized, qa.normalized))
  else:
    result.dot = abs(dot(direction(p1, p2, p3, 1).normalized, (p3 -
        origin).normalized))
  result.distance = minDistance

proc addEdge(d: var DistanceSelector, ec: var EdgeCache, prev, cur, next: Edge) =
  let delta = 1.001f * length(d.p - ec.p)

  if ec.absDistance - delta <= abs(d.minDistance.distance):
    let distance =
      case cur.command
      of LINE:
        signedDistance(
          d.p,
          cur.p1,
          cur.p2,
        )

      of CURVE:
        signedDistance(
          d.p,
          cur.p1,
          cur.p2,
          cur.p3,
        )

      else:
        default(Distance)

    if distance < d.minDistance:
      d.minDistance = distance

    ec.p = d.p
    ec.absDistance = abs(distance.distance)

proc reset(s: var DistanceSelector, p: Vec2) =
  let
    delta = 1.001f * length(p - s.p)
    distance = s.minDistance.distance + sign(s.minDistance.distance) * delta

  s.p = p
  s.minDistance.distance = distance

proc resolveDistance(d: float32): float32 {.inline.} =
  d

proc composeDistance(df: var ShapeDistanceFinder, p: Vec2): float32 =
  let contourCount = int32(df.contours.len)
  var
    shapeSelector = default(DistanceSelector)
    innerEdgeSelector = default(DistanceSelector)
    outerEdgeSelector = default(DistanceSelector)

  shapeSelector.reset(p)
  innerEdgeSelector.reset(p)
  outerEdgeSelector.reset(p)

  for idx in 0 ..< contourCount:
    let distance = df.selectors[idx].distance
    shapeSelector.merge(df.selectors[idx])

    if df.windings[idx] > 0 and resolveDistance(distance) >= 0:
      innerEdgeSelector.merge(df.selectors[idx])

    if df.windings[idx] < 0 and resolveDistance(distance) <= 0:
      outerEdgeSelector.merge(df.selectors[idx])

  let
    shapeDistance = shapeSelector.distance
    innerDistance = innerEdgeSelector.distance
    outerDistance = outerEdgeSelector.distance

    innerScalarDistance = resolveDistance(innerDistance)
    outerScalarDistance = resolveDistance(outerDistance)

  var
    winding = default(int8)
    distance = default(float32)

  distance.initDistance()

  if innerScalarDistance >= 0 and abs(innerScalarDistance) <= abs(outerScalarDistance):
    distance = innerDistance
    winding = 1

    for idx in 0 ..< contourCount:
      if df.windings[idx] > 0:
        let contourDistance = df.selectors[idx].distance
        if abs(resolveDistance(contourDistance)) < abs(outerScalarDistance) and
            resolveDistance(contourDistance) > resolveDistance(distance):
          distance = contourDistance

  elif outerScalarDistance <= 0 and abs(outerScalarDistance) < abs(innerScalarDistance):
    distance = outerDistance
    winding = -1

    for idx in 0 ..< contourCount:
      if df.windings[idx] < 0:
        let contourDistance = df.selectors[idx].distance
        if abs(resolveDistance(contourDistance)) < abs(innerScalarDistance) and
            resolveDistance(contourDistance) < resolveDistance(distance):
          distance = contourDistance
  else:
    result = shapeDistance
    return

  for idx in 0 ..< contourCount:
    if df.windings[idx] != winding:
      let contourDistance = df.selectors[idx].distance
      if resolveDistance(contourDistance) * resolveDistance(distance) >= 0 and
          abs(resolveDistance(contourDistance)) < abs(resolveDistance(distance)):
        distance = contourDistance

  distance

proc distance(df: var ShapeDistanceFinder, p: Vec2): float32 =
  for idx in 0 ..< df.selectors.len:
    df.selectors[idx].reset(p)

  var
    n = default(int32)

  for idx in 0 ..< len(df.contours):
    let
      contour = df.contours[idx]
      selector = df.selectors[idx].addr

    var
      cur = int32(contour.len - 1)
      prev = if contour.len >= 2:
          int32(contour.len - 2)
        else:
          int32(0)

    for idx in 0 ..< int32(contour.len):
      selector[].addEdge(
        df.edgeCache[n],
        contour[prev],
        contour[cur],
        contour[idx],
      )

      prev = cur
      cur = idx

      inc n, 1

  let distance = df.composeDistance(p)
  distance

proc setupEdges(df: var ShapeDistanceFinder, path: Path) =
  var
    e = default(Edge)
    p = default(Vec2)
    start = default(Vec2)
    startIdx = default(int32)

  template addContour =
    let idx = int32(df.edgeStorage.len)
    if startIdx != idx:
      let contour = piece(df.edgeStorage.toOpenArray(startIdx, idx - 1))
      df.contours.add(contour)
      startIdx = idx

  const scale = float32(1) / float32(64)

  for command, data in path.commands:
    case command
    of MOVE:
      start[0] = data[0] * scale
      start[1] = data[1] * scale
      p = start

      addContour()

    of LINE:
      let
        x1 = data[0] * scale
        y1 = data[1] * scale

      if p[0] != x1 or p[1] != y1:
        e.command = LINE
        e.p1 = p
        e.p2 = vec2(x1, y1)
        e.p3 = default(Vec2)
        p = e.p2
        df.edgeStorage.add(e)

    of CURVE:
      let
        x1 = data[0] * scale
        y1 = data[1] * scale
        x2 = data[2] * scale
        y2 = data[3] * scale

      if p[0] != x2 or p[1] != y2:
        e.command = CURVE
        e.p1 = p
        e.p2 = vec2(x1, y1)
        e.p3 = vec2(x2, y2)
        p = e.p3
        df.edgeStorage.add(e)

    of BEZIER:
      discard

    of CLOSE:
      if p[0] != start[0] or p[1] != start[1]:
        e.command = LINE
        e.p1 = p
        e.p2 = start
        e.p3 = default(Vec2)
        p = e.p2
        df.edgeStorage.add(e)

    of RESTART:
      p[0] = 0
      p[1] = 0
      start[0] = 0
      start[1] = 0

  addContour()

proc setup(df: var ShapeDistanceFinder, path: Path) =
  df.contours.setLen(0)
  df.edgeCache.setLen(0)
  df.edgeStorage.setLen(len(path.data))
  df.edgeStorage.setLen(0)
  df.selectors.setLen(0)
  df.windings.setLen(0)

  df.setupEdges(path)

  df.edgeCache.setLen(df.edgeStorage.len)
  df.selectors.setLen(df.contours.len)

  for contour in df.contours:
    let wind = contour.winding
    df.windings.add(wind)

proc generateDistanceField*(df: var ShapeDistanceFinder,
    path: Path,
    w, h: int32,
    pixelRange: Slice[int32],
    inverseYAxis = false): seq[float32] =

  df.setup(path)

  let
    pixelScale = float32(1) / float32(pixelRange.b - pixelRange.a)
    pixelTranslate = float32(-pixelRange.a)

  var sdf = newSeqUninit[float32](w * h)

  for row in 0 ..< h:
    let y =
      if inverseYAxis:
        h - row - 1
      else:
        row

    for x in 0 ..< w:
      let
        p = vec2(float32(x) + 0.5f, float32(y) + 0.5f)
        distance = df.distance(p)
        value = pixelScale * (distance + pixelTranslate)

      sdf[x + w * row] = value

  sdf
