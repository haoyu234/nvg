import ./core

proc createImage*(w, h: int32, pixelFormat: PixelFormat, imageFlags: set[
    ImageFlags]): Image =
  result = Image()
  result.width = w
  result.height = h
  result.imageFlags = imageFlags
  result.pixelFormat = pixelFormat
  result.data.setLen(w * h * pixelFormat.bytesPerPixel)

proc updatePixels*(image: Image, x, y, w, h, stride: int32,
    data: ptr UncheckedArray[byte]) =
  let
    bytesPerPixel = image.pixelFormat.bytesPerPixel
    offset = x + y * image.width
    lineBytes = w * bytesPerPixel
    sourceStrideBytes = stride * bytesPerPixel
    destinationStrideBytes = image.width * bytesPerPixel
    destinationPixels = cast[ptr UncheckedArray[byte]](image.data[offset *
        bytesPerPixel].addr)

  for idx in 0 ..< h:
    copyMem(destinationPixels[idx * destinationStrideBytes].addr, data[idx *
        sourceStrideBytes].addr, lineBytes)

  inc image.version, 1
