import nvg

const
  IMAGE_LOGO = staticRead("../assets/logo.png")

var
  imageId_logo = default(ImageId)

type
  Images* = enum
    Logo

proc addDefaultImages*(ctx: Context) =
  imageId_logo = ctx.loadImageFromMemory(cast[seq[byte]](IMAGE_LOGO), {})

proc getImageId*(id: Images): ImageId =
  {.cast(noSideEffect).}:
    case id
    of Logo: imageId_logo
