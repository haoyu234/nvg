import nvg

import ./app
import ./demo

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()

  ctx.fillStyle = color(1, 0, 0, 1)
  ctx.beginPath()
  ctx.rect(vec4(10, 10, 90, 90))
  ctx.fill()

  ctx.renderTiger()

launch(400, 300, App(
  name: "tdemo.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
