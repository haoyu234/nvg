import std/math

import nvg

import ./app

proc roundedRect(ctx: Context, x, y, w, h, radius: float32) =
  ctx.beginPath()
  ctx.moveTo(vec2(x, y + radius))
  ctx.lineTo(vec2(x, y + h - radius))
  ctx.quadCurveTo(vec2(x, y + h), vec2(x + radius, y + h))
  ctx.lineTo(vec2(x + w - radius, y + h))
  ctx.quadCurveTo(vec2(x + w, y + h), vec2(x + w, y + h - radius))
  ctx.lineTo(vec2(x + w, y + radius))
  ctx.quadCurveTo(vec2(x + w, y), vec2(x + w - radius, y))
  ctx.lineTo(vec2(x + radius, y))
  ctx.quadCurveTo(vec2(x, y), vec2(x, y + radius))
  ctx.stroke()

proc demo_pacman*(app: App, ctx: Context) =
  # https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Drawing_shapes#making_combinations

  ctx.roundedRect(12, 12, 184, 168, 15)
  ctx.roundedRect(19, 19, 170, 154, 9)
  ctx.roundedRect(53, 53, 49, 33, 10)
  ctx.roundedRect(53, 119, 49, 16, 6)
  ctx.roundedRect(135, 53, 49, 33, 10)
  ctx.roundedRect(135, 119, 25, 49, 10)

  ctx.beginPath()
  ctx.arc(vec2(37, 37), 13, PI / 7, -PI / 7, false)
  ctx.lineTo(vec2(31, 37))
  ctx.fill()

  ctx.beginPath()
  for idx in 0 ..< 8:
    ctx.rect(vec4(float32(idx) * 16 + 51, 35, 4, 4))

  for idx in 0 ..< 6:
    ctx.rect(vec4(115, float32(idx) * 16 + 51, 4, 4))

  for idx in 0 ..< 8:
    ctx.rect(vec4(float32(idx) * 16 + 51, 99, 4, 4))
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(vec2(83, 116))
  ctx.lineTo(vec2(83, 102))
  ctx.bezierTo(vec2(83, 94), vec2(89, 88), vec2(97, 88))
  ctx.bezierTo(vec2(105, 88), vec2(111, 94), vec2(111, 102))
  ctx.lineTo(vec2(111, 116))
  ctx.lineTo(vec2(106.333, 111.333))
  ctx.lineTo(vec2(101.666, 116))
  ctx.lineTo(vec2(97, 111.333))
  ctx.lineTo(vec2(92.333, 116))
  ctx.lineTo(vec2(87.666, 111.333))
  ctx.lineTo(vec2(83, 116))
  ctx.fill()

  ctx.beginPath()
  ctx.fillStyle = color(255, 255, 255, 255)
  ctx.moveTo(vec2(91, 96))
  ctx.bezierTo(vec2(88, 96), vec2(87, 99), vec2(87, 101))
  ctx.bezierTo(vec2(87, 103), vec2(88, 106), vec2(91, 106))
  ctx.bezierTo(vec2(94, 106), vec2(95, 103), vec2(95, 101))
  ctx.bezierTo(vec2(95, 99), vec2(94, 96), vec2(91, 96))
  ctx.moveTo(vec2(103, 96))
  ctx.bezierTo(vec2(100, 96), vec2(99, 99), vec2(99, 101))
  ctx.bezierTo(vec2(99, 103), vec2(100, 106), vec2(103, 106))
  ctx.bezierTo(vec2(106, 106), vec2(107, 103), vec2(107, 101))
  ctx.bezierTo(vec2(107, 99), vec2(106, 96), vec2(103, 96))
  ctx.fill()

  ctx.fillStyle = color(0, 0, 0, 255)
  ctx.beginPath()
  ctx.arc(vec2(101, 102), 2, 0, PI * 2, true)
  ctx.fill()

  ctx.beginPath()
  ctx.arc(vec2(89, 102), 2, 0, PI * 2, true)
  ctx.fill()
