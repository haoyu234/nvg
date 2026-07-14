import std/math

import ./core

proc `-`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] - v2[0], v1[1] - v2[1]]

proc `+`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] + v2[0], v1[1] + v2[1]]

proc `*`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] * v2[0], v1[1] * v2[1]]

proc `*`*(s: float32, v: Vec2): Vec2 {.inline.} =
  [s * v[0], s * v[1]]

proc `*`*(v1: Vec2, v2: float32): Vec2 {.inline.} =
  [v1[0] * v2, v1[1] * v2]

proc `/`*(v1: Vec2, v2: float32): Vec2 {.inline.} =
  [v1[0] / v2, v1[1] / v2]

proc `/`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] / v2[0], v1[1] / v2[1]]

proc dot*(v1, v2: Vec2): float32 {.inline.} =
  v1[0] * v2[0] + v1[1] * v2[1]

proc cross*(v1, v2: Vec2): float32 {.inline.} =
  v1[0] * v2[1] - v2[0] * v1[1]

proc length*(v: Vec2): float32 {.inline.} =
  sqrt(v[0] * v[0] + v[1] * v[1])

proc length2*(v: Vec2): float32 {.inline.} =
  v[0] * v[0] + v[1] * v[1]

proc distance*(v1, v2: Vec2): float32 {.inline.} =
   #GLM glm::distance: euclidean distance between two points
  length(v2 - v1)

proc distance2*(v1, v2: Vec2): float32 {.inline.} =
   #GLM glm::distance2: squared euclidean distance (avoids sqrt)
  length2(v2 - v1)

proc atan*(v: Vec2): float32 {.inline.} =
  arctan2(v[1], v[0])

proc normalize*(v: var Vec2) {.inline.} =
  let len = v.length
  if len > 0:
    v[0] = v[0] / len
    v[1] = v[1] / len

proc normalized*(v: Vec2): Vec2 {.inline.} =
  let len = v.length
  if len > 0:
    [v[0] / len, v[1] / len]
  else:
    [0, 0]

proc nearEqual*(v1, v2: Vec2, distTolSq: float32): bool {.inline.} =
   #euclidean proximity test (disk), distinct from per-component epsilonEqual (box)
  distance2(v1, v2) < distTolSq

proc equal*(v1, v2: Vec2): bool {.inline.} =
  v1[0] == v2[0] and v1[1] == v2[1]

proc epsilonEqual*(v1, v2: Vec2, epsilon: float32): bool {.inline.} =
  abs(v1[0] - v2[0]) <= epsilon and abs(v1[1] - v2[1]) <= epsilon

proc equal*(a, b: float32): bool {.inline.} =
  a == b

proc epsilonEqual*(a, b, epsilon: float32): bool {.inline.} =
  abs(a - b) <= epsilon

proc nearEqual*(a, b, eps: float32): bool {.inline.} =
  abs(a - b) <= eps

proc `*`*(matrix: Mat2d, v: Vec2): Vec2 {.inline.} =
  [
    matrix.xx * v[0] + matrix.xy * v[1] + matrix.x0,
    matrix.yx * v[0] + matrix.yy * v[1] + matrix.y0,
  ]

proc multiply*(matrix: var Mat2d, matrix2: Mat2d) {.inline.} =
  let old = matrix
  matrix.xx = matrix2.xx * old.xx + matrix2.yx * old.xy
  matrix.yx = matrix2.xx * old.yx + matrix2.yx * old.yy
  matrix.xy = matrix2.xy * old.xx + matrix2.yy * old.xy
  matrix.yy = matrix2.xy * old.yx + matrix2.yy * old.yy
  matrix.x0 = matrix2.x0 * old.xx + matrix2.y0 * old.xy + old.x0
  matrix.y0 = matrix2.x0 * old.yx + matrix2.y0 * old.yy + old.y0

proc premultiply*(matrix: var Mat2d, matrix2: Mat2d) {.inline.} =
  let old = matrix
  matrix.xx = old.xx * matrix2.xx + old.yx * matrix2.xy
  matrix.yx = old.xx * matrix2.yx + old.yx * matrix2.yy
  matrix.xy = old.xy * matrix2.xx + old.yy * matrix2.xy
  matrix.yy = old.xy * matrix2.yx + old.yy * matrix2.yy
  matrix.x0 = old.x0 * matrix2.xx + old.y0 * matrix2.xy + matrix2.x0
  matrix.y0 = old.x0 * matrix2.yx + old.y0 * matrix2.yy + matrix2.y0

proc multiplied*(matrix, matrix2: Mat2d): Mat2d {.inline.} =
  result.xx = matrix2.xx * matrix.xx + matrix2.yx * matrix.xy
  result.yx = matrix2.xx * matrix.yx + matrix2.yx * matrix.yy
  result.xy = matrix2.xy * matrix.xx + matrix2.yy * matrix.xy
  result.yy = matrix2.xy * matrix.yx + matrix2.yy * matrix.yy
  result.x0 = matrix2.x0 * matrix.xx + matrix2.y0 * matrix.xy + matrix.x0
  result.y0 = matrix2.x0 * matrix.yx + matrix2.y0 * matrix.yy + matrix.y0

proc premultiplied*(matrix, matrix2: Mat2d): Mat2d {.inline.} =
  result.xx = matrix.xx * matrix2.xx + matrix.yx * matrix2.xy
  result.yx = matrix.xx * matrix2.yx + matrix.yx * matrix2.yy
  result.xy = matrix.xy * matrix2.xx + matrix.yy * matrix2.xy
  result.yy = matrix.xy * matrix2.yx + matrix.yy * matrix2.yy
  result.x0 = matrix.x0 * matrix2.xx + matrix.y0 * matrix2.xy + matrix2.x0
  result.y0 = matrix.x0 * matrix2.yx + matrix.y0 * matrix2.yy + matrix2.y0

proc scaled*(v: Vec2): Mat2d {.inline.} =
  result.xx = v[0]
  result.yx = 0
  result.xy = 0
  result.yy = v[1]
  result.x0 = 0
  result.y0 = 0

proc scaled*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  result = scaled(v)
  result.premultiply(matrix)

proc scale*(matrix: var Mat2d, v: Vec2) {.inline.} =
  matrix.multiply(scaled(v))

proc translated*(v: Vec2): Mat2d {.inline.} =
  result.xx = 1
  result.yx = 0
  result.xy = 0
  result.yy = 1
  result.x0 = v[0]
  result.y0 = v[1]

proc translated*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  result = translated(v)
  result.premultiply(matrix)

proc translate*(matrix: var Mat2d, v: Vec2) {.inline.} =
  matrix.multiply(translated(v))

proc degrees*(angle: float32): float32 {.inline.} =
  angle * 180.0 / PI

proc radians*(angle: float32): float32 {.inline.} =
  angle * PI / 180.0

proc rotated*(radians: float32): Mat2d {.inline.} =
  let
    c = cos(radians)
    s = sin(radians)

  result.xx = c
  result.yx = s
  result.xy = -s
  result.yy = c
  result.x0 = 0
  result.y0 = 0

proc rotated*(matrix: Mat2d, radians: float32): Mat2d {.inline.} =
  result = rotated(radians)
  result.premultiply(matrix)

proc rotate*(matrix: var Mat2d, radians: float32) {.inline.} =
  matrix.multiply(rotated(radians))

proc skewed*(radians: Vec2): Mat2d {.inline.} =
  result.xx = 1
  result.yx = tan(radians[1])
  result.xy = tan(radians[0])
  result.yy = 1
  result.x0 = 0
  result.y0 = 0

proc skewed*(matrix: Mat2d, radians: Vec2): Mat2d {.inline.} =
  result = skewed(radians)
  result.premultiply(matrix)

proc skew*(matrix: var Mat2d, radians: Vec2) {.inline.} =
  matrix.multiply(skewed(radians))

proc inverse*(matrix: var Mat2d) {.inline.} =
  let det = matrix.xx * matrix.yy - matrix.yx * matrix.xy
  if det > -1e-6 and det < 1e-6:
    matrix = mat2d()
    return

  let old = matrix
  let invDet = float32(1) / det
  matrix.xx = old.yy * invDet
  matrix.yx = -old.yx * invDet
  matrix.xy = -old.xy * invDet
  matrix.yy = old.xx * invDet
  matrix.x0 = (old.xy * old.y0 - old.yy * old.x0) * invDet
  matrix.y0 = (old.yx * old.x0 - old.xx * old.y0) * invDet

proc inversed*(matrix: Mat2d): Mat2d {.inline.} =
  let det = matrix.xx * matrix.yy - matrix.yx * matrix.xy
  if det > -1e-6 and det < 1e-6:
    result = mat2d()
    return

  let old = matrix
  let invDet = float32(1) / det
  result.xx = old.yy * invDet
  result.yx = -old.yx * invDet
  result.xy = -old.xy * invDet
  result.yy = old.xx * invDet
  result.x0 = (old.xy * old.y0 - old.yy * old.x0) * invDet
  result.y0 = (old.yx * old.x0 - old.xx * old.y0) * invDet

proc `*`*(matrix: Mat2d, bounds: Bounds): Bounds {.inline.} =
  let
    x0 = matrix.xx * bounds.xMin + matrix.xy * bounds.yMin + matrix.x0
    x1 = matrix.xx * bounds.xMax + matrix.xy * bounds.yMin + matrix.x0
    x2 = matrix.xx * bounds.xMin + matrix.xy * bounds.yMax + matrix.x0
    x3 = matrix.xx * bounds.xMax + matrix.xy * bounds.yMax + matrix.x0
    y0 = matrix.yx * bounds.xMin + matrix.yy * bounds.yMin + matrix.y0
    y1 = matrix.yx * bounds.xMax + matrix.yy * bounds.yMin + matrix.y0
    y2 = matrix.yx * bounds.xMin + matrix.yy * bounds.yMax + matrix.y0
    y3 = matrix.yx * bounds.xMax + matrix.yy * bounds.yMax + matrix.y0

  result.xMin = min(min(x0, x1), min(x2, x3))
  result.xMax = max(max(x0, x1), max(x2, x3))
  result.yMin = min(min(y0, y1), min(y2, y3))
  result.yMax = max(max(y0, y1), max(y2, y3))
