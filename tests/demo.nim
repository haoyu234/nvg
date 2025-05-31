import pkg/chroma
import pkg/vmath

import nvg/core
import nvg/perfgraph

import std/monotimes
import std/strformat
import std/times

const FONT = staticRead("../msyh.ttf")

var
  frameCount = 0
  frameStartTime = default(MonoTime)

  totalTime = default(Duration)
  fontId = default(FontId)
  graph = default(PerfGraph)

  title = "demo"

proc initDemo*(ctx: ptr ContextObj, name: string) =
  title = name
  fontId = ctx.loadFontFromMemory(cast[seq[byte]](FONT))

proc renderDemo1*(ctx: ptr ContextObj) =
  ctx.save()

  ctx.setFillColor(color(1, 0, 0, 0.50))
  ctx.setStrokeColor(color(0, 1, 0, 0.50))

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

proc renderDemo2*(ctx: ptr ContextObj) =
  ctx.save()

  ctx.setFontId(fontId)
  ctx.setFillColor(color(1, 0, 0, 0.50))
  ctx.setFontSize(32)

  var y = 0

  for align in HorizontalAlignment:
    for baseline in BaselineAlignment:
      ctx.setTextAlign(align)
      ctx.setTextBaseline(baseline)
      ctx.text("123456790", vec2(float32(100), float32(y * 20 + 100)))
      ctx.fill()

      inc y, 1

  ctx.restore()

proc renderPerfGraph*(ctx: ptr ContextObj) =
  ctx.renderGraph(vec2(10, 40), graph, PERF_GRAPH_RENDER_FPS, fontId)

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
  echo fmt"demo: {title}"
  echo fmt"nim version: {NimVersion}"
  echo fmt"times: {frameCount}"
  echo fmt"total time: {us} usecs"
  echo fmt"average time: {float(us) / float(frameCount)} usecs"
  echo ""
