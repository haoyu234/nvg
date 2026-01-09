import ./backend
import ./context
import ./core

import std/os

const
  USE_LODEPNG = false
  EXTERN_ROOT = currentSourcePath().splitPath.head & "/extern"

when USE_LODEPNG:
  {.compile: EXTERN_ROOT & "/lodepng.c".}

  const LODEPNG = EXTERN_ROOT & "/lodepng.h"

  proc lodepng_decode32(p: var ptr uint8, w, h: var cuint, buffer: pointer,
      len: csize_t): cint {.importc, header: LODEPNG.}

  proc lodepng_free(p: pointer) {.importc: "free".}

else:
  {.passC: "-DSTBI_NO_STDIO".}
  {.passC: "-DSTB_IMAGE_IMPLEMENTATION".}

  const STB_IMAGE = EXTERN_ROOT & "/stb_image.h"

  proc stbi_set_unpremultiply_on_load(shouldUnpremultiply: cint) {.importc,
      header: STB_IMAGE.}

  proc stbi_convert_iphone_png_to_rgb(shouldConvert: cint) {.importc,
      header: STB_IMAGE.}

  proc stbi_load_from_memory(buffer: pointer, len: cint, x, y,
      channels: var cint, desiredChannels: cint): pointer {.importc,
          header: STB_IMAGE.}

  proc stbi_image_free(p: pointer) {.importc, header: STB_IMAGE.}

proc loadImageFromMemory*(ctx: Context, data: openArray[byte], imageFlags: set[
    ImageFlags]): ImageId =
  when USE_LODEPNG:
    var
      width = cuint(0)
      height = cuint(0)
      p = default(ptr uint8)

    discard lodepng_decode32(p, width, height, data[0].addr, csize_t(data.len))
    if p.isNil:
      return

    defer:
      lodepng_free(p)

  else:
    var
      width = cint(0)
      height = cint(0)
      channels = cint(0)

    stbi_set_unpremultiply_on_load(1)
    stbi_convert_iphone_png_to_rgb(1)

    let p = stbi_load_from_memory(data[0].addr, cint(data.len), width, height,
        channels, 4)

    defer:
      stbi_image_free(p)

  result = ctx.backendContext.allocImage(
    ImageInfo(
      width: int32(width),
      height: int32(height),
      pixelFormat: PixelFormatRGBA8,
    ),
    imageFlags
  )

  ctx.backendContext.updateImage(
    result,
    0, 0, int32(width), int32(height),
    int32(width) * 4,
    p
  )

proc loadImage*(ctx: Context, path: string, imageFlags: set[
    ImageFlags]): ImageId =
  let data = readFile(path)
  ctx.loadImageFromMemory(cast[seq[byte]](data), imageFlags)
