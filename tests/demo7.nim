import nvg

import ./app
import ./images

const
  TEXTs = [
    "你好, 世界",
    "hello world ~",
    "😬👀🚨",
  ]

proc demo_text*(app: App, ctx: Context) =
  ctx.fillStyle = color(255, 0, 0, 255)
  ctx.translate(vec2(100, 100))

  for text in TEXTs:
    ctx.fillText(text, vec2(0, 0))
    ctx.translate(vec2(0, 40))

  let
    imageId = ctx.getImageId(Logo)
    imageInfo = ctx.getImageInfo(imageId)
    size = vec4(0, 0, float32(imageInfo.width), float32(imageInfo.height))

  ctx.fontSize = 16.0
  ctx.textAlign = LeftAlign
  ctx.textBaseline = TopBaseline

  var text = ""
  let cols = 36
  let rows = 11
  for r in 0 ..< rows:
    for c in 0 ..< cols:
      text.add(chr(48 + ((r * cols + c) mod 10)))
    text.add("\n")

  var
    pattern = ctx.imagePattern(size, 0, imageId, 1)
  pattern.backdropColor = color(90, 95, 110, 255)
  ctx.fillStyle = pattern
  ctx.fillText(text, vec2(8, 8))
