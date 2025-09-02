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

  sum / float32(n)

proc renderGraph*(ctx: Context, pos: Vec2, perfGraph: PerfGraph) =
  return

  var p = default(Path)

  let
    w = float32(290)
    h = float32(80)

  ctx.save()

  p.clear()
  p.rectXYWH(vec4(pos[0], pos[1], w, h))

  ctx.fillStyle = color(0, 0, 0, 0.75)
  ctx.fillPath(p)

  p.clear()
  p.moveTo(vec2(pos[0], pos[1] + h))

  template lineTo(MAX: static[float32]) =
    if v > MAX:
      v = MAX

    vx = pos[0] + float32(idx) / float32(GRAPH_HISTORY_COUNT - 1) * w
    vy = pos[1] + h - (v / MAX * h)

    p.lineTo(vec2(vx, vy))

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

  p.lineTo(vec2(pos[0] + w, pos[1] + h))

  ctx.fillStyle = color(1, 0.75, 0, 0.5)
  ctx.fillPath(p)

  ctx.fontId = ctx.getDefaultFont()
  ctx.fontSize = 36
  ctx.fillStyle = color(0.58, 0.25, 1, 1)
  ctx.textAlign = RightAlign
  ctx.textBaseline = TopBaseline

  let v = perfGraph.average

  case perfGraph.renderStyle
  of PERF_GRAPH_RENDER_FPS:
    let path1 = ctx.textToPath(fmt"{1 / v:.2f} FPS", vec2(pos[0] + w - 3, pos[1] + 1))
    ctx.fillPath(path1)
    ctx.fontSize = 30
    ctx.fillStyle = color(0.58, 0.25, 1, 0.9)
    ctx.textBaseline = BottomBaseline
    let path2 =
      ctx.textToPath(fmt"{v * 1000:.2f} ms", vec2(pos[0] + w - 3, pos[1] + h - 1))
    ctx.fillPath(path2)
  of PERF_GRAPH_RENDER_PERCENT:
    let path1 = ctx.textToPath(fmt"{v:.1f} %", vec2(pos[0] + w - 3, pos[1] + 1))
    ctx.fillPath(path1)
  of PERF_GRAPH_RENDER_MS:
    let path1 = ctx.textToPath(fmt"{v * 1000:.2f} ms", vec2(pos[0] + w - 3, pos[1] + 1))
    ctx.fillPath(path1)

  ctx.restore()
