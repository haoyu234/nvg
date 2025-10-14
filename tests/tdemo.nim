import nvg

import ./app
import ./demo1
import ./demo2
import ./demo3
import ./demo4
import ./demo5
import ./fonts

const
  SCREEN_W = 500
  SCREEN_H = 500

const demos = [
  (demo1.demo_tiger, "tiger"),
  (demo3.demo_pacman, "pacman"),
  (demo2.demo_arc, "arc"),
  (demo2.demo_curveTo, "curveTo"),
  (demo2.demo_lineDash, "lineDash"),
  (demo2.demo_lineCap, "lineCap"),
  (demo2.demo_lineJoin, "lineJoin"),
  (demo4.demo_fillRule, "fillRule"),
  (demo4.demo_fillStyle, "fillStyle"),
  (demo4.demo_globalAlpha, "globalAlpha"),
  (demo4.demo_rotate, "rotate"),
  (demo5.demo_image, "image"),
]

var
  idx = int32(low(demos))
  dx = int32(0)
  dy = int32(0)
  mouseDown = false
  mouseX = int32(0)
  mouseY = int32(0)

proc initImpl(ctx: Context) =
  discard

proc eventImpl(ctx: Context, event: AppEvent) =
  case event.typ
  of EVENT_TYPE_KEY_DOWN:
    if event.keyCode == KEY_CODE_LEFT:
      dec idx, 1
    elif event.keyCode == KEY_CODE_RIGHT:
      inc idx, 1
    else:
      return

    dx = 0
    dy = 0

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

  else:
    discard

  if idx < 0:
    idx = high(demos)
  elif idx >= len(demos):
    idx = 0

proc frameImpl(ctx: Context) =
  let name = demos[idx][1]

  # render
  block:
    ctx.save()

    ctx.translate(vec2(float32(dx), float32(dy)))

    let frameImpl = demos[idx][0]
    frameImpl(ctx)

    ctx.restore()

  ctx.save()

  # name
  ctx.fontId = ctx.getDefaultFont()
  ctx.fontSize = 32
  ctx.textBaseline = MiddleBaseline
  ctx.fillStyle = color(0, 0, 0, 1)
  ctx.fillText(name, vec2(10, float32(SCREEN_H - 20)))

  # page indicator
  let
    n = len(demos)
    mid = float32(SCREEN_W) / 2
    offset = mid - (n - 1) * 10 / 2

  for i in 0 ..< n:
    let r = if idx == i: 5 else: 3

    ctx.beginPath()
    ctx.circle(vec2(offset + float32(i * 10), float32(SCREEN_H - 10)), float32(r))

    if idx == i: ctx.fill() else: ctx.stroke()

  ctx.restore()

launch(SCREEN_W, SCREEN_H, App(
  name: "tdemo.nim",
  initImpl: initImpl,
  eventImpl: eventImpl,
  frameImpl: frameImpl,
))
