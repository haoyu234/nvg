import nvg

import ./image

const
  IMAGE_LOGO = staticRead("../assets/logo.png")

var
  imageId = default(ImageId)
  imageInfo = default(ImageInfo)

proc demo_image*(ctx: Context) =
  if imageId.isNil:
    imageId = ctx.loadImageFromMemory(cast[seq[byte]](IMAGE_LOGO), {})
    imageInfo = ctx.getImageInfo(imageId)

  let size = vec4(0, 0, float32(imageInfo.width), float32(imageInfo.height))

  ctx.beginPath()
  ctx.translate(vec2(
    250 - float32(imageInfo.width) / 2,
    250 - float32(imageInfo.height) / 2))
  ctx.rect(size)

  ctx.fillStyle = color(23 / 255, 24 / 255, 31 / 255, 1)
  ctx.fill()

  ctx.fillStyle = ctx.imagePattern(size, 0, imageId, 1)
  ctx.fill()
