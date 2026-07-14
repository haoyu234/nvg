import nvg

const
  IMAGE_LOGO = staticRead("../assets/logo.png")

type
  Images* = enum
    Logo

var
  imageId_logo = default(ImageId)

proc getImageId*(ctx: Context, id: Images): ImageId =
  {.cast(noSideEffect).}:
    case id
    of Logo:
      if imageId_logo.isNil:
        imageId_logo = ctx.loadImageFromMemory(cast[seq[byte]](IMAGE_LOGO), {})
      result = imageId_logo
