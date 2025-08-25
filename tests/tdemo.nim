import nvg

import ./app
import ./demo

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()

  ctx.renderDemo1()
  ctx.renderTiger()

launch(800, 600, App(
  name: "tdemo.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
