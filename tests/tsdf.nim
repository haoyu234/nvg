import nvg

import ./app
import ./fonts

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()
  ctx.fontId = ctx.getDefaultFont()
  ctx.fontSize = 32
  ctx.fillStyle = color(51f / 255f, 51f / 255f, 51f / 255f, 1)
  ctx.textAlign = LeftAlign
  ctx.textBaseline = MiddleBaseline
  ctx.text("你1", vec2(100, 100))

  let p = ctx.textToPath("你2", vec2(100, 150))
  ctx.fillPath(p)

launch(300, 200, App(
  name: "tsdf.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
