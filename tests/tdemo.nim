import nvg

import ./app
import ./demo
import ./fonts

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()

  ctx.fillStyle = color(1, 0, 0, 1)
  ctx.beginPath()
  ctx.rect(vec4(10, 10, 138, 138))
  ctx.fill()

  ctx.renderTiger()

  ctx.fillStyle = color(0, 0, 0, 1)
  ctx.fontSize = 128
  ctx.fontId = ctx.getDefaultFont()

  ctx.textBaseline = TopBaseline
  ctx.fillText("A", vec2(15, 15))

launch(500, 500, App(
  name: "tdemo.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
