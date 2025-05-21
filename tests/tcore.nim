import pkg/vmath

import nvg/core
import nvg/dummy

import std/monotimes
import std/strformat
import std/times

proc draw(ctx: ptr ContextObj) =
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

  ctx.stroke()
  ctx.fill()
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
