import ./vec2

import std/math

proc `-`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] - v2[0], v1[1] - v2[1]]

proc `+`*(v1, v2: Vec2): Vec2 {.inline.} =
  [v1[0] + v2[0], v1[1] + v2[1]]

proc `*`*(v1: Vec2, v2: float32): Vec2 {.inline.} =
  [v1[0] * v2, v1[1] * v2]

proc `/`*(v1: Vec2, v2: float32): Vec2 {.inline.} =
  [v1[0] / v2, v1[1] / v2]

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

proc normalize*(v: Vec2): Vec2 {.inline.} =
  let len = v.length
  [v[0] / len, v[1] / len]

proc `[]`*(matrix: Mat3, i, j: static Natural): float32 {.inline, raises: [].} =
  matrix[int32(i) * 3 + int32(j)]

proc `*`*(matrix: Mat3, v: Vec2): Vec2 {.inline.} =
  [
    matrix[0] * v[0] + matrix[3] * v[1] + matrix[6],
    matrix[1] * v[0] + matrix[4] * v[1] + matrix[7],
  ]

proc scale*(matrix: Mat3, v: Vec2): Mat3 {.inline.} =
  [
    matrix[0] * v[0],
    matrix[1] * v[0],
    matrix[2] * v[0],
    matrix[3] * v[1],
    matrix[4] * v[1],
    matrix[5] * v[1],
    matrix[6],
    matrix[7],
    matrix[8],
  ]

proc translate*(matrix: Mat3, v: Vec2): Mat3 {.inline.} =
  [
    matrix[0],
    matrix[1],
    matrix[2],
    matrix[3],
    matrix[4],
    matrix[5],
    matrix[0] * v[0] + matrix[3] * v[1] + matrix[6],
    matrix[1] * v[0] + matrix[4] * v[1] + matrix[7],
    matrix[8],
  ]

proc rotate*(matrix: Mat3, angle: float32): Mat3 {.inline.} =
  let
    c = cos(angle)
    s = sin(angle)

  [
    matrix[0] * c - matrix[3] * s,
    matrix[1] * c - matrix[4] * s,
    matrix[2] * c - matrix[5] * s,
    matrix[0] * s + matrix[3] * c,
    matrix[1] * s + matrix[4] * c,
    matrix[2] * s + matrix[5] * c,
    matrix[6],
    matrix[7],
    matrix[8],
  ]

proc transpose*(matrix: Mat3): Mat3 {.inline.} =
  [
    matrix[0],
    matrix[3],
    matrix[6],
    matrix[1],
    matrix[4],
    matrix[7],
    matrix[2],
    matrix[5],
    matrix[8],
  ]

proc det*(matrix: Mat3): float32 {.inline.} =
  matrix[0] * (matrix[4] * matrix[8] - matrix[7] * matrix[5]) -
    matrix[1] * (matrix[3] * matrix[8] - matrix[5] * matrix[6]) +
    matrix[2] * (matrix[3] * matrix[7] - matrix[4] * matrix[6])

proc inverse*(matrix: Mat3): Mat3 {.inline.} =
  let invDet = 1 / matrix.det
  [
    +(matrix[4] * matrix[8] - matrix[7] * matrix[5]) * invDet,
    -(matrix[1] * matrix[8] - matrix[2] * matrix[7]) * invDet,
    +(matrix[1] * matrix[5] - matrix[2] * matrix[4]) * invDet,
    -(matrix[3] * matrix[8] - matrix[5] * matrix[6]) * invDet,
    +(matrix[0] * matrix[8] - matrix[2] * matrix[6]) * invDet,
    -(matrix[0] * matrix[5] - matrix[3] * matrix[2]) * invDet,
    +(matrix[3] * matrix[7] - matrix[6] * matrix[4]) * invDet,
    -(matrix[0] * matrix[7] - matrix[6] * matrix[1]) * invDet,
    +(matrix[0] * matrix[4] - matrix[3] * matrix[1]) * invDet,
  ]
