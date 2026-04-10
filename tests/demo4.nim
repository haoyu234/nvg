import nvg

import std/math

proc demo_fillRule*(ctx: Context) =
  # https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Applying_styles_and_colors#canvas_fill_rules

  ctx.beginPath()
  ctx.fillRule = EvenOdd
  ctx.arc(vec2(50, 50), 30, 0, 2 * PI, true)
  ctx.arc(vec2(50, 50), 15, 0, 2 * PI, true)
  ctx.fill()

proc demo_fillStyle*(ctx: Context) =
  # https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Applying_styles_and_colors#a_fillstyle_example

  for i in 0 ..< 6:
    for j in 0 ..< 6:
      let
        r = uint8(floor(255 - 42.5 * float32(i)))
        g = uint8(floor(255 - 42.5 * float32(j)))

      ctx.beginPath()
      ctx.fillStyle = color(r, g, 0, 255)
      ctx.rect(vec4(float32(j * 25), float32(i * 25), 25, 25))
      ctx.fill()

proc hexRGBColor4(h: uint32): Color =
  result.r = uint8((0xF00 and h) shr 8) * 15
  result.g = uint8((0x0F0 and h) shr 4) * 15
  result.b = uint8((0x00F and h) shr 0) * 15
  result.a = 255

proc hexRGBColor8(h: uint32): Color =
  result.r = uint8((0xFF0000 and h) shr 16)
  result.g = uint8((0x00FF00 and h) shr 8)
  result.b = uint8((0x0000FF and h) shr 0)
  result.a = 255

proc fillRect(ctx: Context, color: Color, pos: Vec4) =
  ctx.beginPath()
  ctx.fillStyle = color
  ctx.rect(pos)
  ctx.fill()

proc demo_globalAlpha*(ctx: Context) =
  # https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Applying_styles_and_colors#a_globalalpha_example

  ctx.fillRect(hexRGBColor4(0xFD0), vec4(0, 0, 75, 75))
  ctx.fillRect(hexRGBColor4(0x6C0), vec4(75, 0, 75, 75))
  ctx.fillRect(hexRGBColor4(0x09F), vec4(0, 75, 75, 75))
  ctx.fillRect(hexRGBColor4(0xF30), vec4(75, 75, 75, 75))

  ctx.globalAlpha = 0.2
  ctx.fillStyle = hexRGBColor4(0xFFF)

  for idx in 0 ..< 7:
    ctx.beginPath()
    ctx.arc(vec2(75, 75), float32(10 + 10 * idx), 0, 2 * PI, true)
    ctx.fill()

proc demo_rotate*(ctx: Context) =
  # https://developer.mozilla.org/en-US/docs/Web/API/Canvas_API/Tutorial/Transformations#a_rotate_example

  ctx.save()
  ctx.fillRect(hexRGBColor8(0x95DD), vec4(30, 30, 100, 100))
  ctx.rotate(radians(25))

  ctx.fillRect(hexRGBColor8(0x4D4E53), vec4(30, 30, 100, 100))
  ctx.restore()

  ctx.fillRect(hexRGBColor8(0x0095DD), vec4(150, 30, 100, 100))

  ctx.translate(vec2(200, 80))
  ctx.rotate(radians(25))
  ctx.translate(vec2(-200, -80))

  ctx.fillRect(hexRGBColor8(0x4D4E53), vec4(150, 30, 100, 100))
