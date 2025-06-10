import nvg/context
import nvg/dummy
import nvg/path
import nvg/vec2

import std/monotimes
import std/strformat
import std/times

proc draw(ctx: Context) =
  ctx.begin(vec2(200, 200), 1)

  ctx.save()

  var p = default(Path)
  p.moveTo(vec2(100, 100))
  p.arc(vec2(250, 170), 20, 40, 50, true)
  p.arc(vec2(250, 170), 20, 40, 50, false)
  p.arc(vec2(-340, -219), 170, -9, 181, true)
  p.arc(vec2(-340, -219), 170, -9, 181, false)
  p.arc(vec2(162, -219), 76, 610, -991, true)
  p.arc(vec2(162, -219), 76, 610, -991, false)

  p.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.strokePath(p)
  ctx.fillPath(p)

  ctx.restore()

proc main() =
  let numRun = 10000

  let ctx = newContext()
  let a = getMonoTime()

  for i in 0 ..< numRun:
    draw(ctx)

  let b = getMonoTime()

  let us = (b - a).inMicroseconds
  echo fmt"nim version: {NimVersion}"
  echo fmt"times: {numRun}"
  echo fmt"total time: {us} usecs"
  echo fmt"average time: {float(us) / float(numRun)} usecs"

main()
