import pkg/chroma
import pkg/vmath

import ./core

import std/times
import std/strformat

const GRAPH_HISTORY_COUNT = 100

type
  PerfGraphRenderStyle* = enum
    PERF_GRAPH_RENDER_MS
    PERF_GRAPH_RENDER_FPS
    PERF_GRAPH_RENDER_PERCENT

  PerfGraph* = object
    head: int32
    values: array[GRAPH_HISTORY_COUNT, float32]

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

proc renderGraph*(
    ctx: ptr ContextObj,
    pos: Vec2,
    p: PerfGraph,
    style: PerfGraphRenderStyle,
    fontId: FontId,
) =
  let
    w = float32(380)
    h = float32(80)

  ctx.save()
  ctx.beginPath()
  ctx.rect(vec4(pos.x, pos.y, w, h))
  ctx.setFillColor(color(0, 0, 0, 0.75))
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(vec2(pos.x, pos.y + h))

  template lineTo(MAX: static[float32]) =
    if v > MAX:
      v = MAX

    vx = pos.x + float32(idx) / float32(GRAPH_HISTORY_COUNT - 1) * w
    vy = pos.y + h - (v / MAX * h)

    ctx.lineTo(vec2(vx, vy))

  case style
  of PERF_GRAPH_RENDER_MS:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v = p.values[(p.head + idx) mod GRAPH_HISTORY_COUNT] * float32(1000)
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(20))
  of PERF_GRAPH_RENDER_FPS:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v = float32(1) / (0.00001 + p.values[(p.head + idx) mod GRAPH_HISTORY_COUNT])
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(80))
  of PERF_GRAPH_RENDER_PERCENT:
    for idx in 0 ..< GRAPH_HISTORY_COUNT:
      var
        v = p.values[(p.head + idx) mod GRAPH_HISTORY_COUNT]
        vx = default(float32)
        vy = default(float32)

      lineTo(float32(100))

  ctx.lineTo(vec2(pos.x + w, pos.y + h))
  ctx.setFillColor(color(1, 0.75, 0, 0.5))
  ctx.fill()

  ctx.beginPath()

  ctx.setFontId(fontId)
  ctx.setFontSize(36)
  ctx.setFillColor(color(0.58, 0.25, 1, 1))
  ctx.setTextAlign(RightAlign)
  ctx.setTextBaseline(TopBaseline)

  let v = p.average

  case style
  of PERF_GRAPH_RENDER_FPS:
    ctx.text(fmt"{1 / v:.2f} FPS", vec2(pos.x + w - 3, pos.y + 1))
    ctx.fill()
    ctx.setFontSize(30)
    ctx.setFillColor(color(0.58, 0.25, 1, 0.9))
    ctx.setTextBaseline(BottomBaseline)
    ctx.text(fmt"{v * 1000:.2f} ms", vec2(pos.x + w - 3, pos.y + h - 1))
    ctx.fill()
  of PERF_GRAPH_RENDER_PERCENT:
    ctx.text(fmt"{v:.1f} %", vec2(pos.x + w - 3, pos.y + 1))
    ctx.fill()
  of PERF_GRAPH_RENDER_MS:
    ctx.text(fmt"{v * 1000:.2f} ms", vec2(pos.x + w - 3, pos.y + 1))
    ctx.fill()

  ctx.restore()
