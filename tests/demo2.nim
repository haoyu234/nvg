import nvg

import std/math

proc demo_arc*(ctx: Context) =
  # https://www.cairographics.org/samples/arc/

  const
    xc = 128
    yc = 128
    radius = 100
    angle1 = 45 * PI / 180
    angle2 = 180 * PI / 180

  ctx.beginPath()
  ctx.strokeWidth = 10
  ctx.arc(vec2(xc, yc), radius, angle1, angle2, false)
  ctx.stroke()

  let color1 = color(255, 51, 51, 153)
  ctx.fillStyle = color1
  ctx.strokeStyle = color1
  ctx.strokeWidth = 6

  ctx.beginPath()
  ctx.arc(vec2(xc, yc), 10, 0, 2 * PI, false)
  ctx.fill()

  ctx.beginPath()
  ctx.arc(vec2(xc, yc), radius, angle1, angle1, false)
  ctx.lineTo(vec2(xc, yc))
  ctx.arc(vec2(xc, yc), radius, angle2, angle2, false)
  ctx.lineTo(vec2(xc, yc))
  ctx.stroke()

proc demo_curveTo*(ctx: Context) =
  # https://www.cairographics.org/samples/curve_to/

  let
    p1 = vec2(0.1, 0.5)
    p2 = vec2(0.4, 0.9)
    p3 = vec2(0.6, 0.1)
    p4 = vec2(0.9, 0.5)

  ctx.beginPath()
  ctx.scale(vec2(200, 200))
  ctx.strokeWidth = 0.04
  ctx.moveTo(p1)
  ctx.bezierTo(p2, p3, p4)
  ctx.stroke()

  ctx.beginPath()
  ctx.strokeStyle = color(255, 51, 51, 153)
  ctx.strokeWidth = 0.02
  ctx.moveTo(p1)
  ctx.lineTo(p2)
  ctx.moveTo(p3)
  ctx.lineTo(p4)
  ctx.stroke()

proc demo_lineDash*(ctx: Context) =
  # https://www.cairographics.org/samples/dash/

  ctx.dashArray = @[50, 10, 10, 10]
  ctx.dashOffset = -50
  ctx.strokeWidth = 10

  ctx.beginPath()
  ctx.moveTo(vec2(128, 25.6))
  ctx.lineTo(vec2(230.4, 230.4))
  ctx.relLineTo(vec2(-102.4, 0))
  ctx.bezierTo(vec2(51.2, 230.4), vec2(51.2, 128), vec2(128, 128))
  ctx.stroke()

proc demo_lineCap*(ctx: Context) =
  # https://www.cairographics.org/samples/set_line_cap/

  ctx.beginPath()
  ctx.strokeWidth = 30
  ctx.lineCap = ButtCap
  ctx.moveTo(vec2(64, 50))
  ctx.lineTo(vec2(64, 200))
  ctx.stroke()

  ctx.beginPath()
  ctx.lineCap = RoundCap
  ctx.moveTo(vec2(128, 50))
  ctx.lineTo(vec2(128, 200))
  ctx.stroke()

  ctx.beginPath()
  ctx.lineCap = SquareCap
  ctx.moveTo(vec2(192, 50))
  ctx.lineTo(vec2(192, 200))
  ctx.stroke()

  ctx.beginPath()
  ctx.strokeStyle = color(255, 51, 51, 255)
  ctx.strokeWidth = 2.56
  ctx.moveTo(vec2(64, 50))
  ctx.lineTo(vec2(64, 200))
  ctx.moveTo(vec2(128, 50))
  ctx.lineTo(vec2(128, 200))
  ctx.moveTo(vec2(192, 50))
  ctx.lineTo(vec2(192, 200))
  ctx.stroke()

proc demo_lineJoin*(ctx: Context) =
  # https://www.cairographics.org/samples/set_line_join/

  ctx.beginPath()
  ctx.strokeWidth = 40.96
  ctx.moveTo(vec2(76.8, 84.48))
  ctx.relLineTo(vec2(51.2, -51.2))
  ctx.relLineTo(vec2(51.2, 51.2))
  ctx.lineJoin = MiterJoin
  ctx.stroke()

  ctx.beginPath()
  ctx.moveTo(vec2(76.8, 161.28))
  ctx.relLineTo(vec2(51.2, -51.2))
  ctx.relLineTo(vec2(51.2, 51.2))
  ctx.lineJoin = BevelJoin
  ctx.stroke()

  ctx.beginPath()
  ctx.moveTo(vec2(76.8, 238.28))
  ctx.relLineTo(vec2(51.2, -51.2))
  ctx.relLineTo(vec2(51.2, 51.2))
  ctx.lineJoin = RoundJoin
  ctx.stroke()
