import std/strformat
import std/times

import nvg/context
import nvg/core

const
  GRAPH_HISTORY = 100
  GRAPH_W = float32(176.0)
  GRAPH_H = float32(56.0)
  GRAPH_R = float32(8.0)
  FRAME_BUDGET_MS = float32(16.6667)

type
  PerfGraphStyle* = enum
    PERF_GRAPH_RENDER_MS
    PERF_GRAPH_RENDER_FPS
    PERF_GRAPH_RENDER_PERCENT

  PerfGraph* = object
    renderStyle: PerfGraphStyle
    head: int32
    values: array[GRAPH_HISTORY, float32]
    current: float32

proc initGraph*(renderStyle: PerfGraphStyle): PerfGraph =
  result.renderStyle = renderStyle

proc metricOf(style: PerfGraphStyle, seconds: float32): float32 =
  case style
  of PERF_GRAPH_RENDER_FPS: float32(1.0) / seconds
  of PERF_GRAPH_RENDER_MS: seconds * float32(1000.0)
  of PERF_GRAPH_RENDER_PERCENT: seconds * float32(1000.0) / FRAME_BUDGET_MS *
      float32(100.0)

proc updateGraph*(p: var PerfGraph, frameTime: Duration) =
  let seconds = float32(frameTime.inNanoseconds) / float32(1.0e9)
  if seconds <= 0:
    return

  p.head = succ(p.head) mod int32(GRAPH_HISTORY)
  p.values[p.head] = seconds
  p.current = metricOf(p.renderStyle, seconds)

proc metricColor(style: PerfGraphStyle, v: float32): Color =
  case style
  of PERF_GRAPH_RENDER_FPS:
    if v >= 55: color(82, 196, 26, 255)
    elif v >= 30: color(250, 173, 20, 255)
    else: color(255, 77, 79, 255)
  of PERF_GRAPH_RENDER_MS: color(64, 169, 255, 255)
  of PERF_GRAPH_RENDER_PERCENT:
    if v < 100: color(82, 196, 26, 255)
    elif v < 130: color(250, 173, 20, 255)
    else: color(255, 77, 79, 255)

proc roundRect(ctx: Context, x, y, w, h, r: float32) =
  let radius = min(r, min(w, h) * float32(0.5))
  if radius < float32(0.5):
    ctx.beginPath()
    ctx.rect(vec4(x, y, w, h))
    ctx.closePath()
    return

  ctx.beginPath()
  ctx.moveTo(vec2(x + radius, y))
  ctx.lineTo(vec2(x + w - radius, y))
  ctx.arc(vec2(x + w - radius, y + radius), radius, -float32(1.5707963),
      float32(0.0), false)
  ctx.lineTo(vec2(x + w, y + h - radius))
  ctx.arc(vec2(x + w - radius, y + h - radius), radius, float32(0.0), float32(
      1.5707963), false)
  ctx.lineTo(vec2(x + radius, y + h))
  ctx.arc(vec2(x + radius, y + h - radius), radius, float32(1.5707963), float32(
      3.1415926), false)
  ctx.lineTo(vec2(x, y + radius))
  ctx.arc(vec2(x + radius, y + radius), radius, float32(3.1415926), float32(
      4.7123889), false)
  ctx.closePath()

proc drawPanel(ctx: Context, x, y: float32) =
  roundRect(ctx, x, y, GRAPH_W, GRAPH_H, GRAPH_R)
  ctx.fillStyle = color(28, 30, 38, 240)
  ctx.fill()
  ctx.strokeStyle = color(255, 255, 255, 30)
  ctx.strokeWidth = 1
  ctx.stroke()

proc drawLabel(ctx: Context, text: string, x, y: float32) =
  ctx.fontSize = 12
  ctx.fillStyle = color(236, 238, 244, 255)
  ctx.textAlign = LeftAlign
  ctx.textBaseline = TopBaseline
  ctx.fillText(text, vec2(x + 14, y + 8))

proc drawBigNumber(ctx: Context, text: string, x, y: float32, accent: Color) =
  ctx.fontSize = 30
  ctx.letterSpacing = -float32(0.5)
  ctx.fillStyle = accent
  ctx.textAlign = RightAlign
  ctx.textBaseline = MiddleBaseline
  ctx.fillText(text, vec2(x + GRAPH_W - 14, y + 24))
  ctx.letterSpacing = float32(0.0)

proc drawSparkline(ctx: Context, x, y, w, h: float32, g: PerfGraph,
    accent: Color) =
  var
    mn = high(float32)
    mx = -high(float32)
    count = 0

  for i in 0 ..< GRAPH_HISTORY:
    let v = g.values[(g.head + 1 + i) mod int32(GRAPH_HISTORY)]
    if v > 0:
      let m = metricOf(g.renderStyle, v)
      if m < mn: mn = m
      if m > mx: mx = m
      inc count

  if count < 2: return

  let floorMax = case g.renderStyle
    of PERF_GRAPH_RENDER_FPS: float32(120.0)
    of PERF_GRAPH_RENDER_PERCENT: float32(200.0)
    of PERF_GRAPH_RENDER_MS: float32(4.0)
  mn = float32(0.0)
  if mx < floorMax: mx = floorMax

  let
    pad = h * float32(0.15)
    usableH = h - 2 * pad

  ctx.beginPath()
  if mx - mn <= float32(1.0e-4):
    let centerY = y + h / 2
    ctx.moveTo(vec2(x, centerY)); ctx.lineTo(vec2(x + w, centerY))
  else:
    let n = mx - mn
    var idx = 0
    for i in 0 ..< GRAPH_HISTORY:
      let v = g.values[(g.head + 1 + i) mod int32(GRAPH_HISTORY)]
      if v > 0:
        let
          m = metricOf(g.renderStyle, v)
          fx = x + (float32(idx) / float32(count - 1)) * w
          t = (m - mn) / n
          centerY = y + h - pad - t * usableH

        if idx == 0:
          ctx.moveTo(vec2(fx, centerY))
        else:
          ctx.lineTo(vec2(fx, centerY))
        inc idx

  ctx.strokeStyle = accent
  ctx.strokeWidth = 1.5
  ctx.stroke()

proc renderGraph*(ctx: Context, pos: Vec2, g: PerfGraph) =
  let
    px = pos[0]
    py = pos[1]
    v = g.current

  ctx.save()

  drawPanel(ctx, px, py)

  var label, big: string
  case g.renderStyle
  of PERF_GRAPH_RENDER_FPS:
    label = "FPS"; big = fmt"{v:.0f}"
  of PERF_GRAPH_RENDER_MS:
    label = "ms"; big = fmt"{v:.1f}"
  of PERF_GRAPH_RENDER_PERCENT:
    label = "%"; big = fmt"{v:.0f}"

  let
    accent = metricColor(g.renderStyle, v)

  drawLabel(ctx, label, px, py)
  drawBigNumber(ctx, big, px, py, accent)
  drawSparkline(ctx, px + 12, py + 42, GRAPH_W - 24, 10, g, accent)

  ctx.restore()
