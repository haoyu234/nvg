import ./core

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

proc normalize*(v: var Vec2) {.inline.} =
  let len = v.length
  v[0] = v[0] / len
  v[1] = v[1] / len

proc normalized*(v: Vec2): Vec2 {.inline.} =
  let len = v.length
  [v[0] / len, v[1] / len]

proc equals*(v1, v2: Vec2, distTolSq: float32): bool {.inline.} =
  lengthSq(v2 - v1) < distTolSq

proc `[]`*(matrix: Mat3, i, j: static Natural): float32 {.inline, raises: [].} =
  matrix[int32(i) * 3 + int32(j)]

proc `[]=`*(matrix: var Mat3, i, j: static Natural, v: float32) {.inline, raises: [].} =
  matrix[int32(i) * 3 + int32(j)] = v

proc `*`*(matrix: Mat3, v: Vec2): Vec2 {.inline.} =
  [
    matrix[0, 0] * v[0] + matrix[1, 0] * v[1] + matrix[2, 0],
    matrix[0, 1] * v[0] + matrix[1, 1] * v[1] + matrix[2, 1],
  ]

proc scale*(matrix: var Mat3, v: Vec2) {.inline.} =
  matrix[0, 0] = matrix[0, 0] * v[0]
  matrix[0, 1] = matrix[0, 1] * v[0]
  matrix[0, 2] = matrix[0, 2] * v[0]
  matrix[1, 0] = matrix[1, 0] * v[1]
  matrix[1, 1] = matrix[1, 1] * v[1]
  matrix[1, 2] = matrix[1, 2] * v[1]

proc scaled*(matrix: Mat3, v: Vec2): Mat3 {.inline.} =
  [
    matrix[0, 0] * v[0],
    matrix[0, 1] * v[0],
    matrix[0, 2] * v[0],
    matrix[1, 0] * v[1],
    matrix[1, 1] * v[1],
    matrix[1, 2] * v[1],
    matrix[2, 0],
    matrix[2, 1],
    matrix[2, 2],
  ]

proc translate*(matrix: var Mat3, v: Vec2) {.inline.} =
  matrix[2, 0] = matrix[0, 0] * v[0] + matrix[1, 0] * v[1] + matrix[2, 0]
  matrix[2, 1] = matrix[0, 1] * v[0] + matrix[1, 1] * v[1] + matrix[2, 1]

proc translated*(matrix: Mat3, v: Vec2): Mat3 {.inline.} =
  [
    matrix[0, 0],
    matrix[0, 1],
    matrix[0, 2],
    matrix[1, 0],
    matrix[1, 1],
    matrix[1, 2],
    matrix[0, 0] * v[0] + matrix[1, 0] * v[1] + matrix[2, 0],
    matrix[0, 1] * v[0] + matrix[1, 1] * v[1] + matrix[2, 1],
    matrix[2, 2],
  ]

proc rotate*(matrix: var Mat3, angle: float32) {.inline.} =
  let
    c = cos(angle)
    s = sin(angle)

    m00 = matrix[0, 0]
    m01 = matrix[0, 1]
    m02 = matrix[0, 2]
    m10 = matrix[1, 0]
    m11 = matrix[1, 1]
    m12 = matrix[1, 2]

  matrix[0, 0] = m00 * c - m10 * s
  matrix[0, 1] = m01 * c - m11 * s
  matrix[0, 2] = m02 * c - m12 * s
  matrix[1, 0] = m00 * s + m10 * c
  matrix[1, 1] = m01 * s + m11 * c
  matrix[1, 2] = m02 * s + m12 * c

proc rotated*(matrix: Mat3, angle: float32): Mat3 {.inline.} =
  let
    c = cos(angle)
    s = sin(angle)

  [
    matrix[0, 0] * c - matrix[1, 0] * s,
    matrix[0, 1] * c - matrix[1, 1] * s,
    matrix[0, 2] * c - matrix[1, 2] * s,
    matrix[0, 0] * s + matrix[1, 0] * c,
    matrix[0, 1] * s + matrix[1, 1] * c,
    matrix[0, 2] * s + matrix[1, 2] * c,
    matrix[2, 0],
    matrix[2, 1],
    matrix[2, 2],
  ]

proc transpose*(matrix: var Mat3) {.inline.} =
  let
    m00 = matrix[0, 0]
    m01 = matrix[0, 1]
    m02 = matrix[0, 2]
    m10 = matrix[1, 0]
    m11 = matrix[1, 1]
    m12 = matrix[1, 2]
    m20 = matrix[2, 0]
    m21 = matrix[2, 1]
    m22 = matrix[2, 2]

  matrix[0, 0] = m00
  matrix[0, 1] = m10
  matrix[0, 2] = m20
  matrix[1, 0] = m01
  matrix[1, 1] = m11
  matrix[1, 2] = m21
  matrix[2, 0] = m02
  matrix[2, 1] = m12
  matrix[2, 2] = m22

proc transposed*(matrix: Mat3): Mat3 {.inline.} =
  [
    matrix[0, 0],
    matrix[1, 0],
    matrix[2, 0],
    matrix[0, 1],
    matrix[1, 1],
    matrix[2, 1],
    matrix[0, 2],
    matrix[1, 2],
    matrix[2, 2],
  ]

proc det*(matrix: Mat3): float32 {.inline.} =
  matrix[0, 0] * (matrix[1, 1] * matrix[2, 2] - matrix[2, 1] * matrix[1, 2]) -
    matrix[0, 1] * (matrix[1, 0] * matrix[2, 2] - matrix[1, 2] * matrix[2, 0]) +
    matrix[0, 2] * (matrix[1, 0] * matrix[2, 1] - matrix[1, 1] * matrix[2, 0])

proc inverse*(matrix: var Mat3) {.inline.} =
  let
    invDet = 1 / matrix.det

    m00 = matrix[0, 0]
    m01 = matrix[0, 1]
    m02 = matrix[0, 2]
    m10 = matrix[1, 0]
    m11 = matrix[1, 1]
    m12 = matrix[1, 2]
    m20 = matrix[2, 0]
    m21 = matrix[2, 1]
    m22 = matrix[2, 2]

  matrix[0, 0] = +(m11 * m22 - m21 * m12) * invDet
  matrix[0, 1] = -(m01 * m22 - m02 * m21) * invDet
  matrix[0, 2] = +(m01 * m12 - m02 * m11) * invDet
  matrix[1, 0] = -(m10 * m22 - m12 * m20) * invDet
  matrix[1, 1] = +(m00 * m22 - m02 * m20) * invDet
  matrix[1, 2] = -(m00 * m12 - m10 * m02) * invDet
  matrix[2, 0] = +(m10 * m21 - m20 * m11) * invDet
  matrix[2, 1] = -(m00 * m21 - m20 * m01) * invDet
  matrix[2, 2] = +(m00 * m11 - m10 * m01) * invDet

proc inversed*(matrix: Mat3): Mat3 {.inline.} =
  let invDet = 1 / matrix.det
  [
    +(matrix[1, 1] * matrix[2, 2] - matrix[2, 1] * matrix[1, 2]) * invDet,
    -(matrix[0, 1] * matrix[2, 2] - matrix[0, 2] * matrix[2, 1]) * invDet,
    +(matrix[0, 1] * matrix[1, 2] - matrix[0, 2] * matrix[1, 1]) * invDet,
    -(matrix[1, 0] * matrix[2, 2] - matrix[1, 2] * matrix[2, 0]) * invDet,
    +(matrix[0, 0] * matrix[2, 2] - matrix[0, 2] * matrix[2, 0]) * invDet,
    -(matrix[0, 0] * matrix[1, 2] - matrix[1, 0] * matrix[0, 2]) * invDet,
    +(matrix[1, 0] * matrix[2, 1] - matrix[2, 0] * matrix[1, 1]) * invDet,
    -(matrix[0, 0] * matrix[2, 1] - matrix[2, 0] * matrix[0, 1]) * invDet,
    +(matrix[0, 0] * matrix[1, 1] - matrix[1, 0] * matrix[0, 1]) * invDet,
  ]
