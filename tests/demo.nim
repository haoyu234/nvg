import nvg/context
import nvg/core
import nvg/path

import ./perfgraph
import ./fonts

import std/monotimes
import std/strformat
import std/times

var
  frameCount = 0
  frameStartTime = default(MonoTime)

  totalTime = default(Duration)
  graph = default(PerfGraph)

proc initDemo*(ctx: Context) =
  graph = initGraph("Frame ", PERF_GRAPH_RENDER_FPS)

proc renderDemo1*(ctx: Context) =
  ctx.save()

  ctx.fillStyle = color(1, 0, 0, 0.50)
  ctx.strokeStyle = color(0, 1, 0, 0.50)

  var p = default(Path)
  p.moveTo([float32(100), 100])

  p.arc(vec2(250, 170), 20, 40, 50, true)
  p.arc(vec2(250, 170), 20, 40, 50, false)
  p.arc(vec2(-340, -219), 170, -9, 181, true)
  p.arc(vec2(-340, -219), 170, -9, 181, false)
  p.arc(vec2(162, -219), 76, 610, -991, true)
  p.arc(vec2(162, -219), 76, 610, -991, false)

  p.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.fillPath(p)
  ctx.strokePath(p)

  ctx.restore()

proc renderDemo2*(ctx: Context) =
  ctx.save()

  ctx.fontId = ctx.getDefaultFont()
  ctx.fillStyle = color(1, 0, 0, 0.50)
  ctx.fontSize = 32

  var y = 0

  for align in HorizontalAlignment:
    for baseline in BaselineAlignment:
      ctx.textAlign = align
      ctx.textBaseline = baseline

      let path = ctx.textToPath("123456790", vec2(100, float32(y * 20 + 100)))
      ctx.fillPath(path)

      inc y, 1

  ctx.restore()

proc renderPerfGraph*(ctx: Context) =
  ctx.renderGraph(vec2(10, 40), graph)

proc frameStart*() =
  frameStartTime = getMonoTime()

proc frameEnd*() =
  inc frameCount, 1
  let diff = getMonoTime() - frameStartTime
  totalTime = totalTime + diff

  graph.updateGraph(diff)

proc dump*() =
  let us = totalTime.inMicroseconds

  echo ""
  echo fmt"nim version: {NimVersion}"
  echo fmt"times: {frameCount}"
  echo fmt"total time: {us} usecs"
  echo fmt"average time: {float(us) / float(frameCount)} usecs"
  echo ""
