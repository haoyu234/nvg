import ./core
import ./params
import ./rectpack

import std/hashes
import std/tables

type
  LruItem = object
    prev: uint32
    next: uint32

  LruHead = object
    head: uint32
    tail: uint32

  Cell = object
    id: uint32
    rectId: RectId
    imageIdx: uint32
    x: int32
    y: int32
    w: int32
    h: int32
    lastAccessStamp: uint32
    lru: LruItem

  Image = object
    idx: uint32
    typ: TextureType
    width: int32
    height: int32
    rp: RectPack
    imageId: ImageId
    scaleX, scaleY: float32
    storage: seq[byte]

  AtlasCell* = object
    x*, y*: int32
    # w*, h*: int32
    scaleX*, scaleY*: float32
    imageIdx: uint32
    imageId*: ImageId

  Atlas* = ref AtlasObj
  AtlasObj = object
    ctx: pointer
    params: BackendContextParams
    atlasWidth: int32
    atlasHeight: int32
    images: seq[Image]
    nowStamp: uint32
    lastEvictedStamp: uint32
    lru: LruHead
    cells: seq[Cell]
    cellFreeList: uint32
    lookup: Table[uint32, uint32]

proc `=destroy`(a: AtlasObj) =
  for idx in 0 ..< a.images.len:
    try:
      a.params.deleteTextureImpl(a.ctx, a.images[idx].imageId)
    except:
      discard

proc isNil*(cell: AtlasCell): bool {.inline.} =
  cell.scaleX <= 0 or cell.scaleY <= 0

proc initLru(lru: var LruItem) {.inline.} =
  lru.prev = high(uint32)
  lru.next = high(uint32)

proc initLru(lru: var LruHead) {.inline.} =
  lru.head = high(uint32)
  lru.tail = high(uint32)

proc getLru(a: Atlas, idx: uint32): ptr LruItem {.inline.} =
  a.cells[idx].lru.addr

proc removeLru(a: Atlas, idx: uint32) {.inline.} =
  let
    lru = a.getLru(idx)

  if lru.prev != high(uint32):
    let prev = a.getLru(lru.prev)
    prev.next = lru.next
  elif a.lru.head == idx:
    a.lru.head = lru.next

  if lru.next != high(uint32):
    let next = a.getLru(lru.next)
    next.prev = lru.prev
  elif a.lru.tail == idx:
    a.lru.tail = lru.prev

  initLru(lru[])

proc moveToFrontLru(a: Atlas, idx: uint32) {.inline.} =
  if a.lru.head == idx:
    return

  a.removeLru(idx)
  let
    lru = a.getLru(idx)

  lru.next = a.lru.head
  a.lru.head = idx

  if lru.next != high(uint32):
    let next = a.getLru(lru.next)
    next.prev = idx
  else:
    a.lru.tail = idx

proc initImage(a: Atlas, image: ptr Image, idx, w, h: int32, typ: TextureType) =
  image.idx = uint32(idx)
  image.typ = typ
  image.width = w
  image.height = h
  image.rp.expand(w, h)
  image.storage.setLen(w * h)
  image.scaleX = 1 / float32(w)
  image.scaleY = 1 / float32(h)
  image.imageId = a.params.createTextureImpl(
    a.ctx,
    typ,
    w,
    h,
    {ImageExternalStorage},
    image.storage[0].addr
  )

proc allocImage(a: Atlas, w, h: int32, typ: TextureType): ptr Image =
  let idx = a.images.len
  a.images.setLen(idx + 1)

  let image = a.images[idx].addr
  a.initImage(image, int32(idx), w, h, typ)
  image

proc allocRectOrGrow(a: Atlas, w, h: int32, typ: TextureType): tuple[id: RectId,
    cell: AtlasCell] =
  for idx in 0 ..< a.images.len:
    let image = a.images[idx].addr
    if image.typ != typ:
      continue

    let r = image.rp.allocRect(w, h)
    if not r.id.isNil:
      result.id = r.id
      result.cell.imageIdx = uint32(idx)
      result.cell.imageId = image.imageId
      result.cell.x = r.offsetX
      result.cell.y = r.offsetY
      # result.cell.w = w
      # result.cell.h = h
      result.cell.scaleX = image.scaleX
      result.cell.scaleY = image.scaleY
      return

  let image = a.allocImage(a.atlasWidth, a.atlasHeight, typ)
  if image.isNil:
    return

  let r = image.rp.allocRect(w, h)
  if not r.id.isNil:
    result.id = r.id
    result.cell.imageIdx = image.idx
    result.cell.imageId = image.imageId
    result.cell.x = r.offsetX
    result.cell.y = r.offsetY
    # result.cell.w = w
    # result.cell.h = h
    result.cell.scaleX = image.scaleX
    result.cell.scaleY = image.scaleY
    return

proc hasCell*(a: Atlas, id: uint32): bool {.inline.} =
  a.lookup.contains(id)

proc getCell*(a: Atlas, id: uint32): AtlasCell {.inline.} =
  let
    idx = a.lookup[id]
    cell = a.cells[idx].addr
    image = a.images[cell.imageIdx].addr

  cell.lastAccessStamp = a.nowStamp

  result.imageIdx = cell.imageIdx
  result.imageId = image.imageId
  result.x = cell.x
  result.y = cell.y
  # result.w = cell.w
  # result.h = cell.h
  result.scaleX = image.scaleX
  result.scaleY = image.scaleY

  a.moveToFrontLru(idx)

proc allocCell*(a: Atlas, id: uint32, w, h: int32,
    typ: TextureType): AtlasCell =
  if id in a.lookup:
    let
      idx = a.lookup[id]
      cell = a.cells[idx].addr
      image = a.images[cell.imageIdx].addr

    result.imageIdx = cell.imageIdx
    result.imageId = image.imageId
    result.x = cell.x
    result.y = cell.y
    # result.w = cell.w
    # result.h = cell.h
    result.scaleX = image.scaleX
    result.scaleY = image.scaleY

    a.moveToFrontLru(idx)
    return

  let r = a.allocRectOrGrow(w, h, typ)
  if r.id.isNil:
    return

  var idx = default(uint32)
  if a.cellFreeList != high(uint32):
    idx = a.cellFreeList
    a.cellFreeList = a.cells[a.cellFreeList].lru.next
  else:
    idx = uint32(a.cells.len())
    a.cells.setLen(idx + 1)

  let cell = a.cells[idx].addr
  cell.id = id
  cell.rectId = r.id
  cell.imageIdx = r.cell.imageIdx
  cell.x = int32(r.cell.x)
  cell.y = int32(r.cell.y)
  cell.w = w
  cell.h = h
  cell.lastAccessStamp = a.nowStamp
  initLru(cell.lru)

  a.lookup[id] = uint32(idx)
  a.moveToFrontLru(idx)

  r.cell

proc updateCell(a: Atlas, image: ptr Image, x, y, w, h, stride: int32,
    data: ptr UncheckedArray[byte]) =
  let
    bytePerPixel = image.typ.bytePerPixel
    offset = x + y * image.width
    lineBytes = w * bytePerPixel
    sourceStrideBytes = stride * bytePerPixel
    destinationStrideBytes = image.width * bytePerPixel
    destinationPixels = cast[ptr UncheckedArray[byte]](image.storage[offset *
        bytePerPixel].addr)

  for idx in 0 ..< h:
    copyMem(destinationPixels[idx * destinationStrideBytes].addr, data[idx *
        sourceStrideBytes].addr, lineBytes)

  a.params.markTextureDirtyImpl(
    a.ctx,
    image.imageId,
    x, y, w, h,
  )

proc updateCell*(a: Atlas, cell: AtlasCell, w, h, stride: int32,
    data: pointer) =
  if cell.imageIdx >= uint32(a.images.len):
    return

  let image = a.images[cell.imageIdx].addr
  if cell.imageId != image.imageId:
    return

  a.updateCell(image, cell.x, cell.y, w, h, stride, cast[ptr UncheckedArray[
      byte]](data))

proc evictCells(a: Atlas, duration: int32) =
  var
    idx = a.lru.tail

  while idx != high(uint32):
    let
      cell = a.cells[idx].addr
      inactiveDuration = int32(a.nowStamp - cell.lastAccessStamp)

    if inactiveDuration <= duration:
      break

    let
      prevIdx = cell.lru.prev
      image = a.images[cell.imageIdx].addr

    a.lookup.del(cell.id)
    image.rp.freeRect(cell.rectId)

    a.removeLru(idx)

    cell.lru.next = a.cellFreeList
    a.cellFreeList = idx

    idx = prevIdx

proc compact*(a: Atlas) =
  inc a.nowStamp, 1

  var
    duration = int32(10)
    maxOccupancy = float32(0)

  for idx in 0 ..< a.images.len:
    let
      image = a.images[idx].addr

    maxOccupancy = max(maxOccupancy, image.rp.occupancy)

  if maxOccupancy > 0.65f:
    duration = 1
  elif maxOccupancy > 0.35f:
    duration = (duration + 1) div 2

  a.evictCells(duration)

proc createAtlas*(width, height: int32, ctx: pointer,
    params: BackendContextParams): Atlas =
  result = Atlas()
  result.ctx = ctx
  result.params = params
  result.atlasWidth = width
  result.atlasHeight = height
  result.nowStamp = 1
  result.cellFreeList = high(uint32)

  initLru(result.lru)
