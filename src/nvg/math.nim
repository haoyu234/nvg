import ./core

import std/math

proc `-`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] - v2[0], v1[1] - v2[1]]

proc `+`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] + v2[0], v1[1] + v2[1]]

proc `*`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] * v2[0], v1[1] * v2[1]]

proc `*`*(v1: Vec2, v2: float32): Vec2 {.inline.} =
  [v1[0] * v2, v1[1] * v2]

proc `*`*(v: Vec2, matrix: Mat2d): Vec2 {.inline.} =
  [
    v[0] * matrix.xx + v[1] * matrix.xy + matrix.dx,
    v[0] * matrix.yx + v[1] * matrix.yy + matrix.dy,
  ]

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

proc lengthSq*(v: Vec2): float32 {.inline.} =
  v[0] * v[0] + v[1] * v[1]

proc angle*(v: Vec2): float32 {.inline.} =
  arctan2(v[1], v[0])

proc normalize*(v: var Vec2) {.inline.} =
  let len = v.length
  v[0] = v[0] / len
  v[1] = v[1] / len

proc normalized*(v: Vec2): Vec2 {.inline.} =
  let len = v.length
  [v[0] / len, v[1] / len]

proc equals*(v1, v2: Vec2, distTolSq: float32): bool {.inline.} =
  lengthSq(v2 - v1) < distTolSq

proc multiply*(matrix: var Mat2d, matrix2: Mat2d) {.inline.} =
  let
    xx = matrix.xx
    yx = matrix.yx
    xy = matrix.xy
    yy = matrix.yy

  matrix.xx = xx * matrix2.xx + yx * matrix2.xy
  matrix.yx = xx * matrix2.yx + yx * matrix2.yy
  matrix.xy = xy * matrix2.xx + yy * matrix2.xy
  matrix.yy = xy * matrix2.yx + yy * matrix2.yy
  matrix.dx = matrix.dx * matrix2.xx + matrix.dy * matrix2.xy + matrix2.dx
  matrix.dy = matrix.dx * matrix2.yx + matrix.dy * matrix2.yy + matrix2.dy

proc premultiply*(matrix: var Mat2d, matrix2: Mat2d) {.inline.} =
  let
    xx = matrix.xx
    yx = matrix.yx
    xy = matrix.xy
    yy = matrix.yy

  matrix.xx = matrix2.xx * xx + matrix2.yx * xy
  matrix.yx = matrix2.xx * yx + matrix2.yx * yy
  matrix.xy = matrix2.xy * xx + matrix2.yy * xy
  matrix.yy = matrix2.xy * yx + matrix2.yy * yy
  matrix.dx = matrix2.dx * xx + matrix2.dy * xy + matrix.dx
  matrix.dy = matrix2.dx * yx + matrix2.dy * yy + matrix.dy

proc multiplied*(matrix, matrix2: Mat2d): Mat2d {.inline.} =
  result.xx = matrix.xx * matrix2.xx + matrix.yx * matrix2.xy
  result.yx = matrix.xx * matrix2.yx + matrix.yx * matrix2.yy
  result.xy = matrix.xy * matrix2.xx + matrix.yy * matrix2.xy
  result.yy = matrix.xy * matrix2.yx + matrix.yy * matrix2.yy
  result.dx = matrix.dx * matrix2.xx + matrix.dy * matrix2.xy + matrix2.dx
  result.dy = matrix.dx * matrix2.yx + matrix.dy * matrix2.yy + matrix2.dy

proc scaled*(v: Vec2): Mat2d {.inline.} =
  result.xx = v[0]
  result.yx = 0
  result.xy = 0
  result.yy = v[1]
  result.dx = 0
  result.dy = 0

proc scaled*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  result = scaled(v)
  result.multiply(matrix)

proc scale*(matrix: var Mat2d, v: Vec2) {.inline.} =
  let s = scaled(v)
  matrix.premultiply(s)

proc translated*(v: Vec2): Mat2d {.inline.} =
  result.xx = 1
  result.yx = 0
  result.xy = 0
  result.yy = 1
  result.dx = v[0]
  result.dy = v[1]

proc translated*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  result = translated(v)
  result.multiply(matrix)

proc translate*(matrix: var Mat2d, v: Vec2) {.inline.} =
  let t = translated(v)
  matrix.premultiply(t)

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
  result.dx = 0
  result.dy = 0

proc rotated*(matrix: Mat2d, radians: float32): Mat2d {.inline.} =
  result = rotated(radians)
  result.multiply(matrix)

proc rotate*(matrix: var Mat2d, radians: float32) {.inline.} =
  let r = rotated(radians)
  matrix.premultiply(r)

proc inverse*(matrix: var Mat2d) {.inline.} =
  let det = matrix.xx * matrix.yy - matrix.xy * matrix.yx
  if det > -1e-6 and det < 1e-6:
    matrix = mat2d()
    return

  let
    xx = matrix.xx
    yx = matrix.yx
    xy = matrix.xy
    yy = matrix.yy
    dx = matrix.dx
    dy = matrix.dy
    invDet = float32(1) / det

  matrix.xx = yy * invDet
  matrix.yx = -yx * invDet
  matrix.xy = -xy * invDet
  matrix.yy = xx * invDet
  matrix.dx = float32(float64(xy) * float64(dy) - float64(yy) * float64(dx)) * invDet
  matrix.dy = float32(float64(yx) * float64(dx) - float64(xx) * float64(dy)) * invDet

proc inversed*(matrix: Mat2d): Mat2d {.inline.} =
  let det = matrix.xx * matrix.yy - matrix.xy * matrix.yx
  if det > -1e-6 and det < 1e-6:
    result = mat2d()
    return

  let
    xx = matrix.xx
    yx = matrix.yx
    xy = matrix.xy
    yy = matrix.yy
    dx = matrix.dx
    dy = matrix.dy
    invDet = float32(1) / det

  result.xx = yy * invDet
  result.yx = -yx * invDet
  result.xy = -xy * invDet
  result.yy = xx * invDet
  result.dx = float32(float64(xy) * float64(dy) - float64(yy) * float64(dx)) * invDet
  result.dy = float32(float64(yx) * float64(dx) - float64(xx) * float64(dy)) * invDet
