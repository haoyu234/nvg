import unittest

import pkg/vmath

import nvg/core

when defined(NVG_DUMP):
  import ./dump
else:
  import nvg/dummy

# test "quadCurveTo":
#   let ctx = newContext()
#   ctx.begin(vec2(200, 200), 1)

#   ctx.save()
#   ctx.beginPath()
#   ctx.moveTo(vec2(10, 100))
#   ctx.quadCurveTo(vec2(250, 170), vec2(230, 20))
#   ctx.fill()
#   ctx.stroke()
#   ctx.restore()

test "arc":
  let ctx = newContext()
  ctx.begin(vec2(200, 200), 1)

  ctx.save()
  ctx.beginPath()
  ctx.moveTo(vec2(100, 100))

  ctx.arc(vec2(250, 170), 20, 40, 50, true)
  ctx.arc(vec2(250, 170), 20, 40, 50, false)
  ctx.arc(vec2(-340, -219), 170, -9, 181, true)
  ctx.arc(vec2(-340, -219), 170, -9, 181, false)
  ctx.arc(vec2(162, -219), 76, 610, -991, true)
  ctx.arc(vec2(162, -219), 76, 610, -991, false)
  
  ctx.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.fill()
  ctx.stroke()

  ctx.restore()
