type
  AltasCell* = object
    x*, y*: int32

  Altas* = ref object
    width*: int32
    height*: int32
    nextX: int32
    nextY: int32
    rowH: int32
    atlasBlockHeight*: int32
    storage*: seq[byte]
    dirtyRect*: array[4, int32]

proc clear*(a: Altas) =
  a.rowH = 0
  a.nextX = 0
  a.nextY = 0

  a.dirtyRect[0] = a.width
  a.dirtyRect[1] = a.height
  a.dirtyRect[2] = 0
  a.dirtyRect[3] = 0

proc expand*(a: Altas, w, h: int32) =
  var
    w2 = max(w, a.width)
    h2 = max(h, a.height)

  if w2 == a.width and h2 == a.height:
    return

  if a.width > 0 and w2 != a.width:
    return

  a.storage.setLen(w2 * h2)

  a.dirtyRect[0] = w2
  a.dirtyRect[1] = h2
  a.dirtyRect[2] = 0
  a.dirtyRect[3] = 0

  a.width = w2
  a.height = h2

proc allocCell*(a: Altas, w, h: int32): AltasCell =
  if a.storage.len <= 0:
    a.expand(512, 512)

  if a.nextX + w > a.width:
    a.nextX = 0
    a.nextY = a.nextY + a.rowH
    a.rowH = 0

  if a.atlasBlockHeight > 0:
    let
      v1 = (a.nextY + h) div a.atlasBlockHeight
      v2 = a.nextY div a.atlasBlockHeight

    if v1 != v2:
      a.nextX = 0
      a.nextY = (v2 + 1) * a.atlasBlockHeight
      a.rowH = 0

  if a.nextY + h > a.height:
    return

  result.x = a.nextX
  result.y = a.nextY

  a.nextX = a.nextX + w
  a.rowH = max(a.rowH, h)

proc updateCell*(a: Altas, cell: AltasCell, w, h, stride: int32,
    storage: openArray[byte]) =
  let
    offset = cell.x + cell.y * a.width
    pixels = cast[ptr UncheckedArray[byte]](a.storage[offset].addr)

  for idx in 0 ..< h:
    copyMem(pixels[idx * a.width].addr, storage[idx * stride].addr, w)

  a.dirtyRect[0] = min(a.dirtyRect[0], cell.x)
  a.dirtyRect[1] = min(a.dirtyRect[1], cell.y)
  a.dirtyRect[2] = max(a.dirtyRect[2], cell.x + w)
  a.dirtyRect[3] = max(a.dirtyRect[3], cell.y + h)
