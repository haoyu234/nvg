import ./backend
import ./core
import ./lru
import ./rectpack

import std/hashes
import std/tables

type
  Cell = object
    id: uint32
    idx: int32
    rectId: RectId
    imageIdx: int32
    x: int32
    y: int32
    w: int32
    h: int32
    lastAccessStamp: uint32
    lru: LruItem

  AtlasImage = object
    idx: int32
    rp: RectPack
    imageId: ImageId
    pixelFormat: PixelFormat
    scaleX, scaleY: float32

  AtlasCell* = object
    x*, y*: int32
    # w*, h*: int32
    scaleX*, scaleY*: float32
    imageId*: ImageId
    imageIdx: int32

  Atlas* = ref object
    atlasWidth: int32
    atlasHeight: int32
    images: seq[AtlasImage]
    nowStamp: uint32
    lastEvictedStamp: int32
    lruHead: LruHead
    cells: seq[Cell]
    cellFreeList: int32
    lookup: Table[uint32, int32]
    backendContext: BackendContext

proc getLruHead(a: Atlas): ptr LruHead {.inline.} =
  a.lruHead.addr

proc getLru(a: Atlas, idx: int32): ptr LruItem {.inline.} =
  a.cells[idx].lru.addr

proc isNil*(cell: AtlasCell): bool {.inline.} =
  cell.scaleX <= 0 or cell.scaleY <= 0

proc allocImage(a: Atlas, w, h: int32, pixelFormat: PixelFormat): ptr AtlasImage =
  let idx = a.images.len
  a.images.setLen(idx + 1)

  let atlasImage = a.images[idx].addr
  atlasImage.idx = int32(idx)
  atlasImage.rp.expand(w, h)
  atlasImage.scaleX = 1 / float32(w)
  atlasImage.scaleY = 1 / float32(h)
  atlasImage.pixelFormat = pixelFormat
  atlasImage.imageId = a.backendContext.allocImage(
    ImageInfo(
      width: w,
      height: h,
      pixelFormat: pixelFormat,
    ),
    {}
  )

  atlasImage

proc allocRectOrGrow(a: Atlas, w, h: int32, pixelFormat: PixelFormat): tuple[
    id: RectId, cell: AtlasCell] =
  for idx in 0 ..< a.images.len:
    let atlasImage = a.images[idx].addr
    if atlasImage.pixelFormat != pixelFormat:
      continue

    let r = atlasImage.rp.allocRect(w, h)
    if not r.id.isNil:
      result.id = r.id
      result.cell.imageIdx = int32(idx)
      result.cell.imageId = atlasImage.imageId
      result.cell.x = r.offsetX
      result.cell.y = r.offsetY
      # result.cell.w = w
      # result.cell.h = h
      result.cell.scaleX = atlasImage.scaleX
      result.cell.scaleY = atlasImage.scaleY
      return

  let atlasImage = a.allocImage(a.atlasWidth, a.atlasHeight, pixelFormat)
  if atlasImage.isNil:
    return

  let r = atlasImage.rp.allocRect(w, h)
  if not r.id.isNil:
    result.id = r.id
    result.cell.imageIdx = atlasImage.idx
    result.cell.imageId = atlasImage.imageId
    result.cell.x = r.offsetX
    result.cell.y = r.offsetY
    # result.cell.w = w
    # result.cell.h = h
    result.cell.scaleX = atlasImage.scaleX
    result.cell.scaleY = atlasImage.scaleY
    return

proc hasCell*(a: Atlas, id: uint32): bool {.inline.} =
  a.lookup.contains(id)

proc getCell*(a: Atlas, id: uint32): AtlasCell {.inline.} =
  let
    idx = a.lookup[id]
    cell = a.cells[idx].addr
    atlasImage = a.images[cell.imageIdx].addr

  cell.lastAccessStamp = a.nowStamp

  result.imageIdx = cell.imageIdx
  result.imageId = atlasImage.imageId
  result.x = cell.x
  result.y = cell.y
  # result.w = cell.w
  # result.h = cell.h
  result.scaleX = atlasImage.scaleX
  result.scaleY = atlasImage.scaleY

  a.moveToFrontLru(idx)

proc allocCell(a: Atlas): ptr Cell {.inline.} =
  if a.cellFreeList != high(int32):
    let idx = a.cellFreeList
    a.cellFreeList = a.cells[a.cellFreeList].lru.next

    result = a.cells[idx].addr
  else:
    let idx = int32(a.cells.len())
    a.cells.setLen(idx + 1)

    result = a.cells[idx].addr
    result.idx = idx

  result.lru.initLru()

proc freeCell(a: Atlas, cell: ptr Cell) {.inline.} =
  a.removeLru(cell.idx)

  cell.rectId = default(RectId)
  cell.lru.next = a.cellFreeList

  a.lookup.del(cell.id)
  a.cellFreeList = cell.idx

  if not cell.rectId.isNil:
    let
      imageId = a.images[cell.imageIdx].addr
    imageId.rp.freeRect(cell.rectId)

proc allocCell*(a: Atlas, id: uint32, w, h: int32,
    typ: PixelFormat): AtlasCell =
  if id in a.lookup:
    let
      idx = a.lookup[id]
      cell = a.cells[idx].addr
      atlasImage = a.images[cell.imageIdx].addr

    result.imageIdx = cell.imageIdx
    result.imageId = atlasImage.imageId
    result.x = cell.x
    result.y = cell.y
    # result.w = cell.w
    # result.h = cell.h
    result.scaleX = atlasImage.scaleX
    result.scaleY = atlasImage.scaleY

    a.moveToFrontLru(idx)
    return

  let r = a.allocRectOrGrow(w, h, typ)
  if r.id.isNil:
    return

  let
    cell = a.allocCell()

  cell.id = id
  cell.rectId = r.id
  cell.imageIdx = r.cell.imageIdx
  cell.x = int32(r.cell.x)
  cell.y = int32(r.cell.y)
  cell.w = w
  cell.h = h
  cell.lastAccessStamp = a.nowStamp

  a.lookup[id] = cell.idx
  a.moveToFrontLru(cell.idx)

  r.cell

proc updateCell*(a: Atlas, cell: AtlasCell, w, h, strideBytes: int32,
    data: pointer) =
  if cell.imageIdx >= int32(a.images.len):
    return

  let
    atlasImage = a.images[cell.imageIdx].addr
    imageId = atlasImage.imageId

  if cell.imageIdx != atlasImage.idx:
    return

  a.backendContext.updateImage(imageId, cell.x, cell.y, w, h, strideBytes, data)

proc updateCell*(a: Atlas, cell: AtlasCell, x, y, w, h, strideBytes: int32,
    data: pointer) =
  if cell.imageIdx >= int32(a.images.len):
    return

  let
    atlasImage = a.images[cell.imageIdx].addr
    imageId = atlasImage.imageId

  if cell.imageIdx != atlasImage.idx:
    return

  a.backendContext.updateImage(imageId, cell.x + x, cell.y + y, w, h, strideBytes, data)

proc evictCells(a: Atlas, imageIdx: int32, duration: int32) =
  for idx in a.reversedLru:
    let
      cell = a.cells[idx].addr
    if cell.imageIdx != imageIdx:
      continue

    if int32(a.nowStamp - cell.lastAccessStamp) <= duration:
      break

    a.freeCell(cell)

proc compact*(a: Atlas) =
  inc a.nowStamp, 1

  for idx in 0 ..< int32(a.images.len):
    let
      imageId = a.images[idx].addr
      occupancy = imageId.rp.occupancy

    var
      duration = int32(10)

    if occupancy > 0.65f:
      duration = 1
    elif occupancy > 0.35f:
      duration = (duration + 1) div 2
    elif occupancy > 0.15f:
      discard
    else:
      continue

    a.evictCells(idx, duration)

proc newAtlas*(width, height: int32, backendContext: BackendContext): Atlas =
  Atlas(
    atlasWidth: width,
    atlasHeight: height,
    nowStamp: 1,
    cellFreeList: high(int32),
    backendContext: backendContext,
  )
