import nvg

import ./app
import ./demo1
import ./demo2
import ./demo3
import ./demo4
import ./demo5
import ./demo6
import ./demo7
# import ./demo8
import ./fonts
import ./images

const
  SCREEN_W = 1568
  SCREEN_H = 940

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
  (demo6.demo_skew, "skew"),
  (demo7.demo_text, "text"),
  # (demo8.demo_vehicle, "vehicle"),
]

var
  idx = int32(high(demos))
  dx = int32(0)
  dy = int32(0)
  mouseDown = false
  mouseX = int32(0)
  mouseY = int32(0)
  scale = int32(1)

proc initImpl(ctx: Context) =
  ctx.addDefaultFonts()
  ctx.addDefaultImages()

proc eventImpl(ctx: Context, event: AppEvent) =
  case event.typ
  of EVENT_TYPE_KEY_DOWN:
    if event.keyCode == KEY_CODE_LEFT:
      dec idx, 1
    elif event.keyCode == KEY_CODE_RIGHT:
      inc idx, 1
    elif event.keyCode == KEY_CODE_SPACE:
      dx = 0
      dy = 0
      scale = 1
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

  of EVENT_TYPE_MOUSE_SCROLL:
    if event.scrollY > 0:
      inc scale, 1
    else:
      dec scale, 1

    scale = clamp(scale, 1, 20)

  else:
    discard

  if idx < 0:
    idx = high(demos)
  elif idx >= len(demos):
    idx = 0

proc frameImpl(ctx: Context) =
  let name = demos[idx][1]

  ctx.save()

  # render
  block:
    ctx.save()

    ctx.translate(vec2(float32(dx), float32(dy)))
    ctx.scale(vec2(float32(scale), float32(scale)))

    let frameImpl = demos[idx][0]
    frameImpl(ctx)

    ctx.restore()

  let pos = vec2(5, float32(SCREEN_H - 32 - 5))
  ctx.beginPath()
  ctx.rect(vec4(pos[0], pos[1], 40 * float32(len(name)), 48))
  ctx.fillStyle = color(255, 255, 255, 128)
  ctx.fill()

  # name
  ctx.fontSize = 32
  ctx.fontColor = color(0, 0, 0, 255)
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

  ctx.restore()

launch(SCREEN_W, SCREEN_H, App(
  name: "tdemo.nim",
  initImpl: initImpl,
  eventImpl: eventImpl,
  frameImpl: frameImpl,
))
