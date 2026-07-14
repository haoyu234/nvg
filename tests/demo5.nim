import nvg

import ./app
import ./images

proc demo_image*(app: App, ctx: Context) =
  let
    imageId = ctx.getImageId(Logo)
    imageInfo = ctx.getImageInfo(imageId)
    size = vec4(0, 0, float32(imageInfo.width), float32(imageInfo.height))

  ctx.beginPath()
  ctx.translate(vec2(
    250 - float32(imageInfo.width) / 2,
    250 - float32(imageInfo.height) / 2))

  ctx.rect(size)

  ctx.fillStyle = color(23, 24, 31, 255)
  ctx.fill()

  ctx.fillStyle = ctx.imagePattern(size, 0, imageId, 1)
  ctx.fill()
