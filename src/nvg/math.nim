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

proc `*`*(matrix: Mat2d, v: Vec2): Vec2 {.inline.} =
  [
    v[0] * matrix[0] + v[1] * matrix[2] + matrix[4],
    v[0] * matrix[1] + v[1] * matrix[3] + matrix[5],
  ]

proc scale*(matrix: var Mat2d, v: Vec2) {.inline.} =
  matrix[0] = matrix[0] * v[0]
  matrix[1] = matrix[1] * v[0]
  matrix[2] = matrix[2] * v[1]
  matrix[3] = matrix[3] * v[1]
  matrix[4] = matrix[4] * v[0]
  matrix[5] = matrix[5] * v[1]

proc scaled*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  [
    matrix[0] * v[0],
    matrix[1] * v[0],
    matrix[2] * v[1],
    matrix[3] * v[1],
    matrix[4] * v[0],
    matrix[5] * v[1],
  ]

proc translate*(matrix: var Mat2d, v: Vec2) {.inline.} =
  matrix[4] = matrix[4] + matrix[0] * v[0] + matrix[2] * v[1]
  matrix[5] = matrix[5] + matrix[1] * v[0] + matrix[3] * v[1]

proc translated*(matrix: Mat2d, v: Vec2): Mat2d {.inline.} =
  [
    matrix[0],
    matrix[1],
    matrix[2],
    matrix[3],
    matrix[4] + matrix[0] * v[0] + matrix[2] * v[1],
    matrix[5] + matrix[1] * v[0] + matrix[3] * v[1],
  ]

proc rotate*(matrix: var Mat2d, angle: float32) {.inline.} =
  let
    c = cos(angle)
    s = sin(angle)

  let
    m0 = matrix[0]
    m1 = matrix[1]
    m2 = matrix[2]
    m3 = matrix[3]

  matrix[0] = m0 * c + m2 * s
  matrix[1] = m1 * c + m3 * s
  matrix[2] = m0 * (-s) + m2 * c
  matrix[3] = m1 * (-s) + m3 * c

proc rotated*(matrix: Mat2d, angle: float32): Mat2d {.inline.} =
  let
    c = cos(angle)
    s = sin(angle)

  [
    matrix[0] * c + matrix[2] * s,
    matrix[1] * c + matrix[3] * s,
    matrix[0] * (-s) + matrix[2] * c,
    matrix[1] * (-s) + matrix[3] * c,
    matrix[4],
    matrix[5],
  ]

proc det*(matrix: Mat2d): float32 {.inline.} =
  matrix[0] * matrix[3] - matrix[1] * matrix[2]

proc inverse*(matrix: var Mat2d) {.inline.} =
  let
    invDet = 1 / matrix.det

  let
    m0 = matrix[0]
    m1 = matrix[1]
    m2 = matrix[2]
    m3 = matrix[3]

  matrix[0] = m3 * invDet
  matrix[1] = -m1 * invDet
  matrix[2] = -m2 * invDet
  matrix[3] = m0 * invDet
  matrix[4] = (m2 * matrix[5] - m3 * matrix[4]) * invDet
  matrix[5] = (m1 * matrix[4] - m0 * matrix[5]) * invDet

proc inversed*(matrix: Mat2d): Mat2d {.inline.} =
  let
    invDet = 1 / matrix.det

  [
   +matrix[3] * invDet,
   -matrix[1] * invDet,
   -matrix[2] * invDet,
   +matrix[0] * invDet,
   +(matrix[2] * matrix[5] - matrix[3] * matrix[4]) * invDet,
   +(matrix[1] * matrix[4] - matrix[0] * matrix[5]) * invDet,
  ]

proc multiply*(matrix: var Mat2d, matrix2: Mat2d) {.inline.} =
  let
    m0 = matrix[0]
    m1 = matrix[1]
    m2 = matrix[2]
    m3 = matrix[3]

  matrix[0] = m0 * matrix2[0] + m2 * matrix2[1]
  matrix[1] = m1 * matrix2[0] + m3 * matrix2[1]
  matrix[2] = m0 * matrix2[2] + m2 * matrix2[3]
  matrix[3] = m1 * matrix2[2] + m3 * matrix2[3]
  matrix[4] = m0 * matrix2[4] + m2 * matrix2[5] + matrix[4]
  matrix[5] = m1 * matrix2[4] + m3 * matrix2[5] + matrix[5]

proc multiplied*(matrix, matrix2: Mat2d): Mat2d {.inline.} =
  [
    matrix[0] * matrix2[0] + matrix[2] * matrix2[1],
    matrix[1] * matrix2[0] + matrix[3] * matrix2[1],
    matrix[0] * matrix2[2] + matrix[2] * matrix2[3],
    matrix[1] * matrix2[2] + matrix[3] * matrix2[3],
    matrix[0] * matrix2[4] + matrix[2] * matrix2[5] + matrix[4],
    matrix[1] * matrix2[4] + matrix[3] * matrix2[5] + matrix[5],
  ]
