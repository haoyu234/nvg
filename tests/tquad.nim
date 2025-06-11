import unittest

import nvg/context
import nvg/core
import nvg/path

when defined(NVG_DUMP):
  import ./dump
else:
  import nvg/dummy

test "quadCurveTo":
  let ctx = newContext()
  ctx.begin(vec2(200, 200), 1)

  var p = default(Path)
  p.moveTo(vec2(10, 100))
  p.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.fillPath(p)
  ctx.strokePath(p)

test "arc":
  let ctx = newContext()
  ctx.begin(vec2(200, 200), 1)

  var p = default(Path)
  p.moveTo(vec2(100, 100))

  p.arc(vec2(250, 170), 20, 40, 50, true)
  p.arc(vec2(250, 170), 20, 40, 50, false)
  p.arc(vec2(-340, -219), 170, -9, 181, true)
  p.arc(vec2(-340, -219), 170, -9, 181, false)
  p.arc(vec2(162, -219), 76, 610, -991, true)
  p.arc(vec2(162, -219), 76, 610, -991, false)

  p.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.fillPath(p)
  ctx.strokePath(p)
