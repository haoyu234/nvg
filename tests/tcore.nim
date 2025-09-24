import nvg

import ./app

proc frameImpl(ctx: Context) =
  ctx.save()

  let
    p1 = vec2(0.1f, 0.5f)
    p2 = vec2(0.4f, 0.9f)
    p3 = vec2(0.6f, 0.1f)
    p4 = vec2(0.9f, 0.5f)

  ctx.beginPath()
  ctx.scale(vec2(200, 200))
  ctx.strokeWidth = 0.04f
  ctx.moveTo(p1)
  ctx.bezierTo(p2, p3, p4)
  ctx.stroke()

  ctx.beginPath()
  ctx.strokeStyle = color(1, 0.2, 0.2, 0.6)
  ctx.strokeWidth = 0.02f
  ctx.moveTo(p1)
  ctx.lineTo(p2)
  ctx.moveTo(p3)
  ctx.lineTo(p4)
  ctx.stroke()

  ctx.restore()

launch(400, 300, App(
  name: "tcore.nim",
  frameImpl: frameImpl,
))
