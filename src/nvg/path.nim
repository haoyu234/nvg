import std/math

import ./core
import ./math

const
  NVG_KAPPA90 = float32(4.0 * (sqrt(2.0) - 1.0) / 3.0)
  NVG_EPSILON = 0.0001 * PI

proc isEmpty*(p: Path): bool =
  p.commands.len <= 0

proc markDirty(p: var Path) {.inline.} =
  inc p.version, 1
  while p.version == 0:
    inc p.version, 1

proc clear*(p: var Path) {.inline.} =
  p.markDirty()
  p.start = vec2(0, 0)
  p.last = vec2(0, 0)
  p.commands.setLen(0)

proc appendCommands*(p: var Path, commands: openArray[PathEntry]) {.inline.} =
  for cmd in commands:
    case cmd.command
    of Command.MOVE:
      p.start = cmd.p1
      p.last = cmd.p1

    of Command.LINE:
      p.last = cmd.p1

    of Command.CURVE:
      p.last = cmd.p2

    of Command.BEZIER:
      p.last = cmd.p3

    of Command.CLOSE:
      p.last = p.start

  p.markDirty()
  p.commands.add(commands)

proc rect*(p: var Path, xywh: Vec4) {.inline.} =
  p.appendCommands(
    [
      PathEntry(command: Command.MOVE,
        p1: vec2(xywh[0], xywh[1])),
      PathEntry(command: Command.LINE,
        p1: vec2(xywh[0], xywh[1] + xywh[3])),
      PathEntry(command: Command.LINE,
        p1: vec2(xywh[0] + xywh[2], xywh[1] +
          xywh[3])),
      PathEntry(command: Command.LINE,
        p1: vec2(xywh[0] + xywh[2], xywh[1])),
      PathEntry(command: Command.CLOSE),
    ]
  )

proc arc*(p: var Path, c: Vec2, r, a0, a1: float32, ccw: bool) =
  if r <= 0:
    return

  const
    pi2 = float32(PI) * 2
    pidiv2 = float32(PI) * 0.5
    kappaBase = float32(4) / 3

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

  let
    ndivs = max(1, min(int32(abs(da) / pidiv2 + float32(0.5)), 5))
    hda = da / float32(ndivs) * 0.5

  var kappa = abs(kappaBase * (1 - cos(hda)) / sin(hda))

  if ccw:
    kappa = -kappa

  var
    px = float32(0)
    py = float32(0)
    ptanx = float32(0)
    ptany = float32(0)

  var
    idx = 0
    commands = default(array[5, PathEntry])

  for i in 0 .. ndivs:
    let
      angle = a0 + da * float32(i) / float32(ndivs)
      dx = cos(angle)
      dy = sin(angle)
      x = c[0] + dx * r
      y = c[1] + dy * r
      tanx = -dy * r * kappa
      tany = dx * r * kappa

    var cmd = default(PathEntry)

    if i > 0:
      cmd.command = Command.BEZIER
      cmd.p1 = vec2(px + ptanx, py + ptany)
      cmd.p2 = vec2(x - tanx, y - tany)
      cmd.p3 = vec2(x, y)
    elif not p.isEmpty:
      cmd.command = Command.LINE
      cmd.p1 = vec2(x, y)
    else:
      cmd.command = Command.MOVE
      cmd.p1 = vec2(x, y)

    commands[idx] = cmd
    inc idx, 1

    px = x
    py = y
    ptanx = tanx
    ptany = tany

  p.appendCommands(commands.toOpenArray(0, idx - 1))

proc ellipse*(p: var Path, c: Vec2, rx, ry: float32) {.inline.} =
  if rx <= 0 or ry <= 0:
    return

  p.appendCommands([
    PathEntry(command: Command.MOVE,
      p1: vec2(c[0] - rx, c[1])),
    PathEntry(command: Command.BEZIER,
      p1: vec2(c[0] - rx, c[1] + ry * NVG_KAPPA90),
      p2: vec2(c[0] - rx * NVG_KAPPA90, c[1] + ry),
      p3: vec2(c[0], c[1] + ry)),
    PathEntry(command: Command.BEZIER,
      p1: vec2(c[0] + rx * NVG_KAPPA90, c[1] + ry),
      p2: vec2(c[0] + rx, c[1] + ry * NVG_KAPPA90),
      p3: vec2(c[0] + rx, c[1])),
    PathEntry(command: Command.BEZIER,
      p1: vec2(c[0] + rx, c[1] - ry * NVG_KAPPA90),
      p2: vec2(c[0] + rx * NVG_KAPPA90, c[1] - ry),
      p3: vec2(c[0], c[1] - ry)),
    PathEntry(command: Command.BEZIER,
      p1: vec2(c[0] - rx * NVG_KAPPA90, c[1] - ry),
      p2: vec2(c[0] - rx, c[1] - ry * NVG_KAPPA90),
      p3: vec2(c[0] - rx, c[1])),
    PathEntry(command: Command.CLOSE),
  ])

proc circle*(p: var Path, c: Vec2, r: float32) {.inline.} =
  if r <= 0:
    return

  p.ellipse(c, r, r)

proc moveTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.MOVE,
      p1: pos),
  ])

proc relMoveTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.MOVE,
      p1: p.last + pos),
  ])

proc lineTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.LINE,
      p1: pos),
  ])

proc relLineTo*(p: var Path, pos: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.LINE,
      p1: p.last + pos),
  ])

proc bezierTo*(p: var Path, cp1, cp2, to: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.BEZIER,
      p1: cp1,
      p2: cp2,
      p3: to),
  ])

proc relBezierTo*(p: var Path, cp1, cp2, to: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.BEZIER,
      p1: p.last + cp1,
      p2: p.last + cp2,
      p3: p.last + to),
  ])

proc quadCurveTo*(p: var Path, cp, to: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.CURVE,
      p1: cp,
      p2: to),
  ])

proc relQuadCurveTo*(p: var Path, cp, to: Vec2) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.CURVE,
      p1: p.last + cp,
      p2: p.last + to),
  ])

proc arcTo*(p: var Path, a, b: Vec2, r: float32) =
  let
    p1 = p.last
    ab = b - a
    ap = p1 - a

    l12sq = length2(ap)

  if p.isEmpty:
    p.moveTo(a)
    return
  elif l12sq <= NVG_EPSILON:
    return

  let det = cross(ab, ap)

  if abs(det) <= NVG_EPSILON or r == 0:
    p.lineTo(a)
  else:
    let
      dir0 = normalized(ap)
      dir1 = normalized(ab)
      tanLen = r / tan(arccos(dot(dir0, dir1)) * 0.5)

    if tanLen > 10000:
      p.lineTo(a)
      return

    var
      cx = float32(0)
      cy = float32(0)
      a0 = float32(0)
      a1 = float32(0)
      ccw = false

    if det > 0:
      cx = a[0] + dir0[0] * tanLen + dir0[1] * r
      cy = a[1] + dir0[1] * tanLen - dir0[0] * r
      a0 = arctan2(dir0[0], -dir0[1])
      a1 = arctan2(-dir1[0], dir1[1])
      ccw = false
    else:
      cx = a[0] + dir0[0] * tanLen - dir0[1] * r
      cy = a[1] + dir0[1] * tanLen + dir0[0] * r
      a0 = arctan2(-dir0[0], dir0[1])
      a1 = arctan2(dir1[0], -dir1[1])
      ccw = true

    p.arc([cx, cy], r, a0, a1, ccw)

proc closePath*(p: var Path) {.inline.} =
  p.appendCommands([
    PathEntry(command: Command.CLOSE),
  ])

proc addPath*(p: var Path, p2: Path) {.inline.} =
  p.appendCommands(p2.commands)

proc addPath*(p: var Path, p2: Path, matrix: Mat2d) {.inline.} =
  for cmd in p2.commands:
    case cmd.command
    of Command.MOVE:
      let
        p1 = matrix * cmd.p1
      p.moveTo(p1)

    of Command.LINE:
      let
        p1 = matrix * cmd.p1
      p.lineTo(p1)

    of Command.CURVE:
      let
        p1 = matrix * cmd.p1
        p2 = matrix * cmd.p2
      p.quadCurveTo(p1, p2)

    of Command.BEZIER:
      let
        p1 = matrix * cmd.p1
        p2 = matrix * cmd.p2
        p3 = matrix * cmd.p3
      p.bezierTo(p1, p2, p3)

    of Command.CLOSE:
      p.closePath()
