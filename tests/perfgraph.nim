import nvg/context
import nvg/core
import nvg/math
import nvg/path

import ./fonts

import std/times
import std/strformat

const GRAPH_HISTORY_COUNT = 100

type
  PerfGraphStyle* = enum
    PERF_GRAPH_RENDER_MS
    PERF_GRAPH_RENDER_FPS
    PERF_GRAPH_RENDER_PERCENT

  PerfGraph* = object
    name: string
    renderStyle: PerfGraphStyle
    head: int32
    values: array[GRAPH_HISTORY_COUNT, float32]

proc initGraph*(name: string, renderStyle: PerfGraphStyle): PerfGraph =
  result.name = name
  result.renderStyle = renderStyle

proc updateGraph*(p: var PerfGraph, frameTime: Duration) =
  p.head = succ(p.head) mod int32(GRAPH_HISTORY_COUNT)
  p.values[p.head] = float32(frameTime.inNanoseconds) / float32(1000000000)

proc average*(p: PerfGraph): float32 =
  var
    n = default(int32)
    sum = default(float32)

  for v in p.values:
    if v > 0:
      inc n, 1
      sum = sum + v

  if n > 0:
    sum / float32(n)
  else:
    high(float32)

proc renderGraph*(ctx: Context, pos: Vec2, perfGraph: PerfGraph) =
  let
    w = float32(290)
    h = float32(80)

  ctx.save()

  ctx.beginPath()
  ctx.rect(vec4(pos[0], pos[1], w, h))
  ctx.fillStyle = color(0, 0, 0, 191)
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(vec2(pos[0], pos[1] + h))

  template lineTo(MAX: static[float32]) =
    if v > MAX:
      v = MAX

    vx = pos[0] + float32(idx) / float32(GRAPH_HISTORY_COUNT - 1) * w
    vy = pos[1] + h - (v / MAX * h)

    ctx.lineTo(vec2(vx, vy))

  case perfGraph.renderStyle
  of PERF_GRAPH_RENDER_MS:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v =
          perfGraph.values[(perfGraph.head + idx) mod GRAPH_HISTORY_COUNT] *
          float32(1000)
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(20))

  of PERF_GRAPH_RENDER_FPS:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v =
          float32(1) /
          (0.00001 + perfGraph.values[(perfGraph.head + idx) mod GRAPH_HISTORY_COUNT])
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(80))

  of PERF_GRAPH_RENDER_PERCENT:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v = perfGraph.values[(perfGraph.head + idx) mod GRAPH_HISTORY_COUNT]
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(100))

  ctx.lineTo(vec2(pos[0] + w, pos[1] + h))

  ctx.fillStyle = color(255, 191, 0, 127)
  ctx.fill()

  ctx.fontId = ctx.getMonoFont()
  ctx.fontSize = 36
  ctx.fillStyle = color(239, 239, 239, 255)
  ctx.textAlign = RightAlign
  ctx.textBaseline = TopBaseline

  let v = perfGraph.average

  case perfGraph.renderStyle
  of PERF_GRAPH_RENDER_FPS:
    # TODO:
    # ctx.fillText(fmt"{1 / v:.2f} FPS", vec2(pos[0] + w - 3, pos[1] + 1))
    ctx.fontSize = 30
    ctx.fillStyle = color(239, 239, 239, 158)
    ctx.textBaseline = BottomBaseline
    # TODO:
    # ctx.fillText(fmt"{v * 1000:.2f} ms", vec2(pos[0] + w - 3, pos[1] + h - 1))
    discard

  of PERF_GRAPH_RENDER_PERCENT:
    # TODO:
    # ctx.fillText(fmt"{v:.1f} %", vec2(pos[0] + w - 3, pos[1] + 1))
    discard

  of PERF_GRAPH_RENDER_MS:
    # TODO:
    # ctx.fillText(fmt"{v * 1000:.2f} ms", vec2(pos[0] + w - 3, pos[1] + 1))
    discard

  ctx.restore()
