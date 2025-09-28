import std/streams

const BMP_LINEAR_COLOR_SPACE_SPECIFICATION = [
    uint8(0xf8), 0xc2, 0x64, 0x1a, 0x08, 0x3d, 0x9b, 0x0d, 0x11, 0x36, 0x3c, 0x01,
    0x1c, 0xeb, 0xe2, 0x16, 0x39, 0xd6, 0xc5, 0x2d, 0x09, 0xf9, 0xa0, 0x07,
    0xdf, 0x4f, 0x8d, 0x0b, 0xc0, 0xec, 0x9e, 0x04, 0xf4, 0xfd, 0xd4, 0x3c,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
]

proc writeBmp*(path: string, pixels: openArray[uint8], w, h,
    bytesPerPixel: int32) =
  if bytesPerPixel != 1 and
    bytesPerPixel != 3 and bytesPerPixel != 4:
    return

  let
    padw = (bytesPerPixel * w + int32(3)) and not int32(3)
    padding = [uint8(0), 0, 0, 0]

  let
    colorTableEntries =
      if bytesPerPixel == 1:
        256
      else:
        0
    bitmapStart = 14 + 108 + 4 * colorTableEntries
    bitmapSize = h * padw
    fileSize = bitmapStart + bitmapSize

  let fstream = newFileStream(path, FileMode.fmWrite, 1024)
  # BMP
  fstream.write(uint16(0x4d42))
  fstream.write(uint32(fileSize))
  fstream.write(uint16(0))
  fstream.write(uint16(0))
  fstream.write(uint32(bitmapStart))

  # DIB header (BITMAPV4HEADER)
  fstream.write(uint32(108))
  fstream.write(int32(w))
  fstream.write(int32(h))
  fstream.write(uint16(1))
  fstream.write(uint16(8 * bytesPerPixel))
  if bytesPerPixel == 4:
    # BI_BITFIELDS
    fstream.write(uint32(3))
  else:
    # BI_RGB
    fstream.write(uint32(0))
  fstream.write(uint32(bitmapSize))
  fstream.write(uint32(2835))
  fstream.write(uint32(2835))
  fstream.write(uint32(colorTableEntries))
  fstream.write(uint32(colorTableEntries))
  fstream.write(uint32(0x00ff0000))
  fstream.write(uint32(0x0000ff00))
  fstream.write(uint32(0x000000ff))
  if bytesPerPixel == 4:
    fstream.write(uint32(0xff000000))
  else:
    fstream.write(uint32(0))
  fstream.write(uint32(0))
  fstream.writeData(BMP_LINEAR_COLOR_SPACE_SPECIFICATION[0].addr, len(BMP_LINEAR_COLOR_SPACE_SPECIFICATION))

  if bytesPerPixel == 1:
    var color = uint32(0)
    while color < uint32(0x01000000):
      fstream.write(color or uint32(0xff000000))
      color = color + uint32(0x00010101)

    let
      pad = padw - w

    for y in 0 ..< h:
      let
        s = y * w
      fstream.writeData(pixels[s].addr, w)
      if pad > 0:
        fstream.writeData(padding[0].addr, pad)

  elif bytesPerPixel == 3:
    let
      pad = padw - 3 * w

    for y in 0 ..< h:
      for x in 0 ..< w:
        let bgr = [
          pixels[y * w + x + 2],
          pixels[y * w + x + 1],
          pixels[y * w + x + 0],
        ]

        fstream.writeData(bgr[0].addr, len(bgr))
      if pad > 0:
        fstream.writeData(padding[0].addr, pad)

  elif bytesPerPixel == 4:
    for y in 0 ..< h:
      for x in 0 ..< w:
        let bgra = [
          pixels[y * w + x + 2],
          pixels[y * w + x + 1],
          pixels[y * w + x + 0],
          pixels[y * w + x + 3],
        ]

        fstream.writeData(bgra[0].addr, len(bgra))
