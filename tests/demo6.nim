import nvg

proc demo_skew*(ctx: Context) =
  let c = ctx.getTransform()

  ctx.beginPath()
  ctx.rect(vec4(10, 10, 90, 90))

  const
    colors = [
      color(255, 0, 0, 255),
      color(0, 255, 0, 255),
      color(0, 0, 255, 255),
    ]

    vecs = [
      vec2(radians(15), 0),
      vec2(0, radians(15)),
      vec2(radians(15), radians(15)),
    ]

  for idx in 0 ..< 3:
    ctx.setTransform(c)
    ctx.translate(vec2(0, 100 * float32(idx)))
    ctx.skew(vecs[idx])

    ctx.fillStyle = colors[idx]
    ctx.fill()
