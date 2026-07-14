import nvg

import ./app
import ./demo1
import ./demo2
import ./demo3
import ./demo4
import ./demo5
import ./demo6
import ./demo7
import ./fonts
import ./perf_graph

# import ./demo8
import std/times

import ./demo10
import ./demo11
import ./demo12
import ./demo9

const
  SCREEN_W = 800
  SCREEN_H = 600

type
  DemoEntry = object
    name: string
    frame: proc (app: App, ctx: Context)

const demos = [
  DemoEntry(frame: demo1.demo_tiger, name: "tiger"),
  DemoEntry(frame: demo3.demo_pacman, name: "pacman"),
  DemoEntry(frame: demo2.demo_arc, name: "arc"),
  DemoEntry(frame: demo2.demo_curveTo, name: "curveTo"),
  DemoEntry(frame: demo2.demo_lineDash, name: "lineDash"),
  DemoEntry(frame: demo2.demo_lineCap, name: "lineCap"),
  DemoEntry(frame: demo2.demo_lineJoin, name: "lineJoin"),
  DemoEntry(frame: demo4.demo_fillRule, name: "fillRule"),
  DemoEntry(frame: demo4.demo_fillStyle, name: "fillStyle"),
  DemoEntry(frame: demo4.demo_globalAlpha, name: "globalAlpha"),
  DemoEntry(frame: demo4.demo_rotate, name: "rotate"),
  DemoEntry(frame: demo5.demo_image, name: "image"),
  DemoEntry(frame: demo6.demo_skew, name: "skew"),
  DemoEntry(frame: demo7.demo_text, name: "text"),
  # DemoEntry(frame: demo8.demo_vehicle, name: "vehicle"),
  DemoEntry(frame: demo9.demo_cursor, name: "cursor"),
  DemoEntry(frame: demo10.demo_aligns, name: "aligns"),
  DemoEntry(frame: demo11.demo_rich_text, name: "richText"),
  DemoEntry(frame: demo12.demo_text_attribs, name: "textAttribs"),
]

var
  idx = int32(high(demos))
  dx = int32(0)
  dy = int32(0)
  mouseDown = false
  mouseX = int32(SCREEN_W div 2)
  mouseY = int32(SCREEN_H div 2)
  scale = int32(1)

  fpsGraph: PerfGraph
  percentGraph: PerfGraph

  showFps: bool
  showPercent: bool

proc applyZoom(delta: int32) =
  let
    newScale = clamp(scale + delta, int32(1), int32(20))
  if newScale == scale:
    return
  if scale > 0:
    let
      s = float32(scale)
      sNew = float32(newScale)
      mx = float32(mouseX)
      my = float32(mouseY)
    dx = int32(mx - sNew * (mx - float32(dx)) / s)
    dy = int32(my - sNew * (my - float32(dy)) / s)
  scale = newScale

proc renderPerfPanel(ctx: Context) =
  let
    gx = float32(SCREEN_W - 188)
    gy0 = float32(10.0)
    gStep = float32(66.0)

  var
    idx = int32(0)

  if showFps:
    ctx.renderGraph(vec2(gx, gy0 + float32(idx) * gStep), fpsGraph)
    inc idx

  if showPercent:
    ctx.renderGraph(vec2(gx, gy0 + float32(idx) * gStep), percentGraph)
    inc idx

proc tickGraphs(dt: Duration) =
  fpsGraph.updateGraph(dt)
  percentGraph.updateGraph(dt)

proc initImpl(app: App) =
  let ctx = app.ctx
  ctx.fontCollection = getDefaultFontCollection()
  fpsGraph = initGraph(PERF_GRAPH_RENDER_FPS)
  percentGraph = initGraph(PERF_GRAPH_RENDER_PERCENT)
  showFps = true
  showPercent = false

proc eventImpl(app: App, event: AppEvent) =
  case event.typ
  of EVENT_TYPE_KEY_DOWN:
    case event.keyCode
    of KEY_CODE_LEFT:
      dec idx, 1
      dx = 0
      dy = 0

    of KEY_CODE_RIGHT:
      inc idx, 1
      dx = 0
      dy = 0

    of KEY_CODE_SPACE:
      dx = 0
      dy = 0
      scale = 1

    of KEY_CODE_EQUAL, KEY_CODE_KP_ADD:
      applyZoom(1)

    of KEY_CODE_MINUS, KEY_CODE_KP_SUBTRACT:
      applyZoom(-1)

    of KEY_CODE_1:
      showFps = not showFps

    of KEY_CODE_2:
      showPercent = not showPercent
    else:
      return

  of EVENT_TYPE_MOUSE_DOWN:
    mouseDown = true

  of EVENT_TYPE_MOUSE_UP:
    mouseDown = false

  of EVENT_TYPE_MOUSE_MOVE:
    if mouseDown:
      dx += event.mouseDx
      dy += event.mouseDy

    mouseX = event.mouseX
    mouseY = event.mouseY

  of EVENT_TYPE_MOUSE_SCROLL:
    if event.scrollY > 0:
      applyZoom(1)
    else:
      applyZoom(-1)

  else:
    discard

  if idx < 0:
    idx = len(demos) - 1
  elif idx >= len(demos):
    idx = 0

proc frameImpl(app: App, dt: Duration) =
  let ctx = app.ctx
  let name = demos[idx].name

  ctx.save()

  # render
  block:
    ctx.save()

    ctx.translate(vec2(float32(dx), float32(dy)))
    ctx.scale(vec2(float32(scale), float32(scale)))

    let frameImpl = demos[idx].frame
    frameImpl(app, ctx)

    ctx.restore()

  let pos = vec2(5, float32(SCREEN_H - 32 - 5))
  ctx.beginPath()
  ctx.rect(vec4(pos[0], pos[1], 40 * float32(len(name)), 48))
  ctx.fillStyle = color(255, 255, 255, 128)
  ctx.fill()

  # name
  ctx.fontSize = 32
  ctx.fillStyle = color(0, 0, 0, 255)
  ctx.textBaseline = MiddleBaseline
  ctx.fillText(name, pos)

  # page indicator
  let
    n = len(demos)
    mid = float32(SCREEN_W) / 2
    offset = mid - (n - 1) * 10 / 2

  ctx.fillStyle = color(0, 0, 0, 128)
  ctx.strokeStyle = color(0, 0, 0, 128)

  for i in 0 ..< n:
    let r = if idx == i: 5 else: 3

    ctx.beginPath()
    ctx.circle(vec2(offset + float32(i * 10), float32(SCREEN_H - 10)), float32(r))

    if idx == i: ctx.fill() else: ctx.stroke()

  ctx.renderPerfPanel()

  tickGraphs(dt)

  ctx.restore()

launch(App(
  w: SCREEN_W,
  h: SCREEN_H,
  name: "tdemo.nim",
  initImpl: initImpl,
  eventImpl: eventImpl,
  frameImpl: frameImpl,
))
