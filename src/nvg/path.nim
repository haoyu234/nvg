import ./core
import ./math
import ./pieces

import std/math

const
  NVG_KAPPA90 = float32(4.0 * (sqrt(2.0) - 1.0) / 3.0)
  NVG_EPSILON = 0.0001 * PI

proc empty*(p: Path): bool =
  p.data.len <= 0

proc clear*(p: var Path) {.inline.} =
  p.data.setLen(0)

proc appendCommands*(p: var Path, values: openArray[float32]) {.inline.} =
  if len(values) > 0:
    p.currentPos[0] = values[^2]
    p.currentPos[1] = values[^1]

  p.data.add(values)

proc rect*(p: var Path, xywh: Vec4) {.inline.} =
  p.appendCommands(
    [
      float32(Command.MOVE),
      xywh[0],
      xywh[1],
      float32(Command.LINE),
      xywh[0],
      xywh[1] + xywh[3],
      float32(Command.LINE),
      xywh[0] + xywh[2],
      xywh[1] + xywh[3],
      float32(Command.LINE),
      xywh[0] + xywh[2],
      xywh[1],
      float32(Command.CLOSE),
    ]
  )

proc arc*(p: var Path, cp: Vec2, r, a0, a1: float32, ccw: bool) =
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
    ndivs = max(1, min(int32(abs(da) / pidiv2 + float32(0.5)), 5))
    hda = da / float32(ndivs) / 2

  var kappa = abs(s * (1 - cos(hda)) / sin(hda))

  if ccw:
    kappa = -kappa

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
      x = cp[0] + dx * r
      y = cp[1] + dy * r
      tanx = -dy * r * kappa
      tany = dx * r * kappa

    if i > 0:
      append(float32(Command.BEZIER))
      append(px + ptanx)
      append(py + ptany)
      append(x - tanx)
      append(y - tany)
    elif not p.empty:
      append(float32(Command.LINE))
    else:
      append(float32(Command.MOVE))

    append(x)
    append(y)

    px = x
    py = y
    ptanx = tanx
    ptany = tany

  p.appendCommands(commands.toOpenArray(0, idx - 1))

proc ellipse*(p: var Path, c: Vec2, rx, ry: float32) {.inline.} =
  p.appendCommands(
    [
      float32(Command.MOVE),
      c[0] - rx,
      c[1],
      float32(Command.BEZIER),
      c[0] - rx,
      c[1] + ry * NVG_KAPPA90,
      c[0] - rx * NVG_KAPPA90,
      c[1] + ry,
      c[0],
      c[1] + ry,
      float32(Command.BEZIER),
      c[0] + rx * NVG_KAPPA90,
      c[1] + ry,
      c[0] + rx,
      c[1] + ry * NVG_KAPPA90,
      c[0] + rx,
      c[1],
      float32(Command.BEZIER),
      c[0] + rx,
      c[1] - ry * NVG_KAPPA90,
      c[0] + rx * NVG_KAPPA90,
      c[1] - ry,
      c[0],
      c[1] - ry,
      float32(Command.BEZIER),
      c[0] - rx * NVG_KAPPA90,
      c[1] - ry,
      c[0] - rx,
      c[1] - ry * NVG_KAPPA90,
      c[0] - rx,
      c[1],
      float32(Command.CLOSE),
    ]
  )

proc circle*(p: var Path, c: Vec2, r: float32) {.inline.} =
  p.ellipse(c, r, r)

proc moveTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([float32(Command.MOVE), pos[0], pos[1]])

proc lineTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([float32(Command.LINE), pos[0], pos[1]])

proc bezierTo*(p: var Path, cp1, cp2, to: Vec2) {.inline.} =
  p.appendCommands(
    [float32(Command.BEZIER), cp1[0], cp1[1], cp2[0], cp2[1], to[0], to[1]]
  )

proc quadCurveTo*(p: var Path, cp, to: Vec2) {.inline.} =
  p.appendCommands(
    [float32(Command.CURVE), cp[0], cp[1], to[0], to[1]]
  )

proc arcTo*(p: var Path, a, b: Vec2, r: float32) =
  let
    p1 = p.currentPos
    p32 = b - a
    p12 = p1 - a

    l12sq = lengthSq(p12)

  if p.empty:
    p.moveTo(a)
    return
  elif l12sq <= NVG_EPSILON:
    return

  let c = cross(p32, p12)

  if abs(c) <= NVG_EPSILON or r == 0:
    p.lineTo(a)
  else:
    let
      d0 = normalized(p12)
      d1 = normalized(p32)
      d = r / tan(arccos(dot(d0, d1)) / 2f32)

    if d > 10000:
      p.lineTo(a)
      return

    var
      cpx = default(float32)
      cpy = default(float32)
      a0 = default(float32)
      a1 = default(float32)
      ccw = false

    if c > 0:
      cpx = a[0] + d0[0] * d + d0[1] * r
      cpy = a[1] + d0[1] * d - d0[0] * r
      a0 = arctan2(d0[0], -d0[1])
      a1 = arctan2(-d1[0], d1[1])
      ccw = false
    else:
      cpx = a[0] + d0[0] * d - d0[1] * r
      cpy = a[0] + d0[1] * d + d0[0] * r
      a0 = arctan2(-d0[0], d0[1])
      a1 = arctan2(d1[0], -d1[1])
      ccw = true

    p.arc([cpx, cpy], r, a0, a1, ccw)

proc closePath*(p: var Path) {.inline.} =
  const commands = [float32(Command.CLOSE)]
  p.appendCommands(commands)

iterator commands*(p: Path): (Command, Piece[float32]) =
  var j = 0

  while j < p.data.len:
    let command = Command(p.data[j])
    inc j, 1

    case command
    of Command.MOVE, Command.LINE:
      let i = j
      inc j, 2

      yield (command, piece(p.data.toOpenArray(i, j - 1)))

    of Command.CURVE:
      let i = j
      inc j, 4

      yield (command, piece(p.data.toOpenArray(i, j - 1)))

    of Command.BEZIER:
      let i = j
      inc j, 6

      yield (command, piece(p.data.toOpenArray(i, j - 1)))

    of Command.CLOSE, Command.RESTART:
      let i = j
      inc j, 0

      yield (command, piece(p.data.toOpenArray(i, j - 1)))

proc addPath*(p: var Path, other: Path) {.inline.} =
  const commands = [float32(Command.RESTART)]
  p.appendCommands(commands)
  p.appendCommands(other.data)

proc addPath*(p: var Path, other: Path, matrix: Mat2d) {.inline.} =
  const commands = [float32(Command.RESTART)]
  p.appendCommands(commands)

  for command, data in other.commands:
    case command
    of Command.MOVE:
      let
        p1 = matrix * vec2(data[0], data[1])
      p.moveTo(p1)

    of Command.LINE:
      let
        p1 = matrix * vec2(data[0], data[1])
      p.lineTo(p1)

    of Command.CURVE:
      let
        p1 = matrix * vec2(data[0], data[1])
        p2 = matrix * vec2(data[2], data[3])
      p.quadCurveTo(p1, p2)

    of Command.BEZIER:
      let
        p1 = matrix * vec2(data[0], data[1])
        p2 = matrix * vec2(data[2], data[3])
        p3 = matrix * vec2(data[4], data[5])
      p.bezierTo(p1, p2, p3)

    of Command.CLOSE, Command.RESTART:
      p.appendCommands([float32(command)])

proc transform*(p: var Path, matrix: Mat2d) =
  for command, data in p.commands:
    case command
    of Command.MOVE, Command.LINE:
      let
        p1 = matrix * vec2(data[0], data[1])
      data[0] = p1[0]
      data[1] = p1[1]

    of Command.CURVE:
      let
        p1 = matrix * vec2(data[0], data[1])
        p2 = matrix * vec2(data[2], data[3])
      data[0] = p1[0]
      data[1] = p1[1]
      data[2] = p2[0]
      data[3] = p2[1]

    of Command.BEZIER:
      let
        p1 = matrix * vec2(data[0], data[1])
        p2 = matrix * vec2(data[2], data[3])
        p3 = matrix * vec2(data[4], data[5])
      data[0] = p1[0]
      data[1] = p1[1]
      data[2] = p2[0]
      data[3] = p2[1]
      data[4] = p3[0]
      data[5] = p3[1]

    else:
      discard
