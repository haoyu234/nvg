import ./math
import ./pieces
import ./vec2

import std/math

when defined(NVG_DEBUG_CORE):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

type
  PathCommand* = enum
    MOVE
    LINE
    BEZIER
    CLOSE
    RESTART

  Path* = object
    commandXY: Vec2
    commands: seq[float32]

const
  NVG_KAPPA90 = float32(4.0 * (sqrt(2.0) - 1.0) / 3.0)
  NVG_EPSILON = 0.0001 * PI

proc empty*(path: Path): bool =
  path.commands.len <= 0

proc clear*(path: var Path) {.inline.} =
  path.commands.setLen(0)
  path.commandXY = vec2(0, 0)

proc appendCommands(path: var Path, values: openArray[float32]) {.inline.} =
  if values.len >= 3:
    path.commandXY[0] = values[values.len - 2]
    path.commandXY[1] = values[values.len - 1]

  when defined(NVG_DEBUG_CORE):
    printf("line[%u] appendCommands %u cmd[%u]\n", 0, values.len, uint32(values[0]))
    printf("commandXY %.6f %.6f\n", path.commandXY[0], path.commandXY[1])

    for v in values:
      printf("_ %.6f\n", v)

  path.commands.add(values)

proc rectXYWH*(path: var Path, rect: Vec4) {.inline.} =
  path.appendCommands(
    [
      float32(PathCommand.MOVE),
      rect[0],
      rect[1],
      float32(PathCommand.LINE),
      rect[0],
      rect[1] + rect[3],
      float32(PathCommand.LINE),
      rect[0] + rect[2],
      rect[1] + rect[3],
      float32(PathCommand.LINE),
      rect[0] + rect[2],
      rect[1],
      float32(PathCommand.CLOSE),
    ]
  )

proc rectLTRB*(path: var Path, rect: Vec4) {.inline.} =
  path.appendCommands(
    [
      float32(PathCommand.MOVE),
      rect[0],
      rect[1],
      float32(PathCommand.LINE),
      rect[0],
      rect[3],
      float32(PathCommand.LINE),
      rect[2],
      rect[3],
      float32(PathCommand.LINE),
      rect[2],
      rect[1],
      float32(PathCommand.CLOSE),
    ]
  )

proc arc*(path: var Path, cp: Vec2, r, a0, a1: float32, ccw: bool) =
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
    ndivs = max(1, min(int(abs(da) / pidiv2 + float32(0.5)), 5))
    hda = da / float32(ndivs) / 2

  var kappa = abs(s * (1 - cos(hda)) / sin(hda))

  if ccw:
    kappa = -kappa

  when defined(NVG_DEBUG_CORE):
    printf("ndivs[%u] hda[%.6f] kappa[%.6f]\n", ndivs, hda, kappa)

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

    when defined(NVG_DEBUG_CORE):
      printf(
        "a[%f] dx[%.6f] dy[%.6f] x[%.6f] y[%.6f] tanx[%.6f] tany[%.6f]\n", a, dx, dy, x,
        y, tanx, tany,
      )

    if i > 0:
      append(float32(PathCommand.BEZIER))
      append(px + ptanx)
      append(py + ptany)
      append(x - tanx)
      append(y - tany)
    elif path.commands.len > 0:
      append(float32(PathCommand.LINE))
    else:
      append(float32(PathCommand.MOVE))

    append(x)
    append(y)

    px = x
    py = y
    ptanx = tanx
    ptany = tany

  when defined(NVG_DEBUG_CORE):
    printf("commands: \n")
    for i in 0 ..< idx:
      printf("%.6f ", commands[i])
    printf("\n")

  path.appendCommands(commands.toOpenArray(0, idx - 1))

proc ellipse*(path: var Path, c: Vec2, rx, ry: float32) {.inline.} =
  path.appendCommands(
    [
      float32(PathCommand.MOVE),
      c[0] - rx,
      c[1],
      float32(PathCommand.BEZIER),
      c[0] - rx,
      c[1] + ry * NVG_KAPPA90,
      c[0] - rx * NVG_KAPPA90,
      c[1] + ry,
      c[0],
      c[1] + ry,
      float32(PathCommand.BEZIER),
      c[0] + rx * NVG_KAPPA90,
      c[1] + ry,
      c[0] + rx,
      c[1] + ry * NVG_KAPPA90,
      c[0] + rx,
      c[1],
      float32(PathCommand.BEZIER),
      c[0] + rx,
      c[1] - ry * NVG_KAPPA90,
      c[0] + rx * NVG_KAPPA90,
      c[1] - ry,
      c[0],
      c[1] - ry,
      float32(PathCommand.BEZIER),
      c[0] - rx * NVG_KAPPA90,
      c[1] - ry,
      c[0] - rx,
      c[1] - ry * NVG_KAPPA90,
      c[0] - rx,
      c[1],
      float32(PathCommand.CLOSE),
    ]
  )

proc circle*(path: var Path, c: Vec2, r: float32) {.inline.} =
  path.ellipse(c, r, r)

proc moveTo*(path: var Path, pos: Vec2) {.inline.} =
  path.appendCommands([float32(PathCommand.MOVE), pos[0], pos[1]])

proc lineTo*(path: var Path, pos: Vec2) {.inline.} =
  path.appendCommands([float32(PathCommand.LINE), pos[0], pos[1]])

proc bezierTo*(path: var Path, cp1, cp2, to: Vec2) {.inline.} =
  path.appendCommands(
    [float32(PathCommand.BEZIER), cp1[0], cp1[1], cp2[0], cp2[1], to[0], to[1]]
  )

proc quadCurveTo*(path: var Path, cp, to: Vec2) {.inline.} =
  const s = float32(2) / 3
  let pos = path.commandXY

  path.appendCommands(
    [
      float32(PathCommand.BEZIER),
      pos[0] + s * (cp[0] - pos[0]),
      pos[1] + s * (cp[1] - pos[1]),
      to[0] + s * (cp[0] - to[0]),
      to[1] + s * (cp[1] - to[1]),
      to[0],
      to[1],
    ]
  )

proc arcTo*(path: var Path, a, b: Vec2, r: float32) =
  let
    p1 = path.commandXY
    p32 = b - a
    p12 = p1 - a

    l12sq = lengthSq(p12)

  if path.commands.len == 0:
    path.moveTo(a)
    return
  elif l12sq <= NVG_EPSILON:
    return

  let c = cross(p32, p12)

  if abs(c) <= NVG_EPSILON or r == 0:
    path.lineTo(a)
  else:
    let
      d0 = normalized(p12)
      d1 = normalized(p32)
      d = r / tan(arccos(dot(d0, d1)) / 2f32)

    if d > 10000:
      path.lineTo(a)
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

    path.arc([cpx, cpy], r, a0, a1, ccw)

proc addPath*(path: var Path, other: Path) {.inline.} =
  const commands = [float32(PathCommand.RESTART)]
  path.appendCommands(commands)
  path.appendCommands(other.commands)

proc closePath*(path: var Path) {.inline.} =
  const commands = [float32(PathCommand.CLOSE)]
  path.appendCommands(commands)

proc restart*(path: var Path) {.inline.} =
  const commands = [float32(PathCommand.RESTART)]
  path.appendCommands(commands)

iterator commands*(path: Path): (PathCommand, Piece[float32]) =
  var j = 0
  let data = piece(path.commands)

  while j < path.commands.len:
    let cmd = PathCommand(path.commands[j])
    inc j, 1

    case cmd
    of PathCommand.MOVE, PathCommand.LINE:
      let i = j
      inc j, 2

      yield (cmd, data[i ..< j])
    of PathCommand.BEZIER:
      let i = j
      inc j, 6

      yield (cmd, data[i ..< j])
    of PathCommand.CLOSE, PathCommand.RESTART:
      let i = j
      inc j, 0

      yield (cmd, data[i ..< j])
