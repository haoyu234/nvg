import pkg/chroma
import pkg/vmath

import ./core

import std/times

const GRAPH_HISTORY_COUNT = 100

proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

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
    ctx: ptr ContextObj, pos, size: Vec2, p: PerfGraph, style: PerfGraphRenderStyle
) =
  ctx.save()
  ctx.beginPath()
  ctx.rect(vec4(pos.x, pos.y, size.x, size.y))
  ctx.setFillColor(color(0, 0, 0, 0.753))
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(vec2(pos.x, pos.y + size.y))

  template lineTo(MAX: static[float32]) =
    if v > MAX:
      v = MAX

    vx = pos.x + float32(idx) / float32(GRAPH_HISTORY_COUNT - 1) * size.x
    vy = pos.y + size.y - (v / MAX * size.y)

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

  ctx.lineTo(vec2(pos.x + size.x, pos.y + size.y))
  ctx.setFillColor(color(1, 0.753, 0, 0.5))
  ctx.fill()

  ctx.restore()
