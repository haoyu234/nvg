import std/algorithm
import std/tables

import ./backend
import ./core
import ./font
import ./lru
import ./math
import ./slab
import ./slug
import ./tracy

type
  SlugGlyphTextureCell = object
    tex: ptr SlugTextureObj
    base: int32
    len: int32

  SlugGlyphKey = object
    font: uint
    glyphId: GlyphId
    mask: uint32

  SlugGlyph = object
    key: SlugGlyphKey
    id: LruItem
    lruEntry: LruItemEntry
    rawBBox: Bounds
    advance: float32
    lsb: float32
    maxBandX: int32
    maxBandY: int32
    glyphLoc: array[2, int32]
    bandCell: SlugGlyphTextureCell
    curveCell: SlugGlyphTextureCell
    lastAccess: int64

  SlugGlyphInfo* = object
    rawBBox*: Bounds
    advance*: float32
    lsb*: float32
    maxBandX*: int32
    maxBandY*: int32
    glyphLoc*: array[2, int32]
    curveTexId*: ImageId
    bandTexId*: ImageId

  SlugTexture = ref SlugTextureObj
  SlugTextureObj = object
    idx: int32
    slab: Slab
    data: seq[byte]
    texId: ImageId
    pixelFormat: PixelFormat
    dirtyY0: int32
    dirtyY1: int32
    fillH: int32

  GlyphCache* = ref object
    backendContext: BackendContext
    atlasMaxGlyphs: int32
    images: seq[SlugTexture]

    lruHead: LruHead
    now: int64
    glyphEntryList: seq[SlugGlyph]
    glyphEntryFreeList: LruItem
    lookup: Table[SlugGlyphKey, LruItem]

proc allocSlabTexture(idx: int32, backendContext: BackendContext,
    pixelFormat: PixelFormat): SlugTexture =
  let
    zone = zoneBegin("glyphCache.allocSlabTexture")
  defer: zone.zoneEnd()

  let
    perSlabTexels = NVG_SLUG_TEXTURE_WIDTH * NVG_SLUG_TEXTURE_HEIGHT
    image = backendContext.allocImage(
      ImageInfo(
        width: NVG_SLUG_TEXTURE_WIDTH,
        height: NVG_SLUG_TEXTURE_HEIGHT,
        pixelFormat: pixelFormat),
        {ImageNearest})

  result = SlugTexture()
  result.idx = idx
  result.slab = createSlab(perSlabTexels)
  result.data = newSeq[byte](perSlabTexels * pixelFormat.bytesPerPixel)
  result.texId = image
  result.pixelFormat = pixelFormat
  result.dirtyY0 = -1
  result.dirtyY1 = -1
  result.fillH = 0

proc createGlyphCache*(backendContext: BackendContext,
    atlasMaxGlyphs: int32 = 4096): GlyphCache =
  result = GlyphCache()
  result.backendContext = backendContext
  result.atlasMaxGlyphs = atlasMaxGlyphs
  result.lruHead = default(LruHead)
  result.glyphEntryList = @[]
  result.glyphEntryFreeList = default(LruItem)
  result.lookup = initTable[SlugGlyphKey, LruItem]()

proc getLruHead(ctx: GlyphCache): ptr LruHead {.inline.} =
  ctx.lruHead.addr

proc getLru(ctx: GlyphCache, id: LruItem): ptr LruItemEntry {.inline.} =
  ctx.glyphEntryList[id.id].lruEntry.addr

proc allocGlyph(ctx: GlyphCache): ptr SlugGlyph {.inline.} =
  if ctx.glyphEntryFreeList.id != high(int32):
    let idx = ctx.glyphEntryFreeList.id
    ctx.glyphEntryFreeList = ctx.glyphEntryList[idx].lruEntry.next
    result = ctx.glyphEntryList[idx].addr
  else:
    let idx = int32(ctx.glyphEntryList.len)
    ctx.glyphEntryList.setLen(idx + 1)
    result = ctx.glyphEntryList[idx].addr
    result.id.id = idx

  result.lruEntry = default(LruItemEntry)
  result.curveCell = default(SlugGlyphTextureCell)
  result.bandCell = default(SlugGlyphTextureCell)

proc allocCell(tex: SlugTexture | ptr SlugTextureObj,
    need: int32): SlugGlyphTextureCell =
  let
    zone = zoneBegin("glyphCache.allocCell")
  defer: zone.zoneEnd()

  if need <= 0:
    return

  let base = tex.slab.allocate(need)
  if base < 0:
    return

  result.tex = tex[].addr
  result.base = base
  result.len = need

proc allocCell(ctx: GlyphCache, need: int32,
    pixelFormat: PixelFormat): SlugGlyphTextureCell =
  let
    zone = zoneBegin("glyphCache.allocCell")
  defer: zone.zoneEnd()

  for tex in ctx.images:
    if tex.pixelFormat != pixelFormat:
      continue

    result = tex.allocCell(need)
    if result.tex != nil:
      return

proc allocOrGrowCell(ctx: GlyphCache, need: int32,
    pixelFormat: PixelFormat): SlugGlyphTextureCell =
  let
    zone = zoneBegin("glyphCache.allocOrGrowCell")
  defer: zone.zoneEnd()

  if need <= 0:
    return

  result = ctx.allocCell(need, pixelFormat)
  if result.tex != nil:
    return

  let
    tex = allocSlabTexture(int32(ctx.images.len), ctx.backendContext, pixelFormat)
  if not tex.isNil:
    ctx.images.add(tex)

    result = tex.allocCell(need)

proc freeCell(tex: SlugTexture | ptr SlugTextureObj,
    cell: SlugGlyphTextureCell) =
  let
    zone = zoneBegin("glyphCache.freeCell")
  defer: zone.zoneEnd()

  tex.slab.release(cell.base, cell.len)

proc freeGlyph(ctx: GlyphCache,
    e: ptr SlugGlyph) {.inline.} =
  let
    zone = zoneBegin("glyphCache.freeGlyph")
  defer: zone.zoneEnd()

  ctx.remove(e.id)
  ctx.lookup.del(e.key)

  if not e.isNil:
    if e.curveCell.len > 0:
      e.curveCell.tex.freeCell(e.curveCell)
    if e.bandCell.len > 0:
      e.bandCell.tex.freeCell(e.bandCell)
    e.curveCell = default(SlugGlyphTextureCell)
    e.bandCell = default(SlugGlyphTextureCell)

  e.lruEntry.next = ctx.glyphEntryFreeList
  ctx.glyphEntryFreeList = e.id

proc markDirtyY(image: ptr SlugTextureObj, tw, base, len: int32) =
  let
    y0 = base div tw
    y1 = (base + len + tw - 1) div tw
  if image.dirtyY0 < 0:
    image.dirtyY0 = y0
    image.dirtyY1 = y1
  else:
    image.dirtyY0 = min(image.dirtyY0, y0)
    image.dirtyY1 = max(image.dirtyY1, y1)
  image.fillH = max(image.fillH, y1)

proc evictGlyph(ctx: GlyphCache, duration: int64) =
  let
    zone = zoneBegin("glyphCache.evictGlyph")
  defer: zone.zoneEnd()

  for id in ctx.reversed:
    let
      e = ctx.glyphEntryList[id.id].addr

    if e.lastAccess + duration > ctx.now:
      return

    ctx.freeGlyph(e)

proc allocCurveAndBandCell(ctx: GlyphCache, curveSize,
    bandSize: int32): (SlugGlyphTextureCell, SlugGlyphTextureCell) =
  let
    zone = zoneBegin("glyphCache.allocCurveAndBandCell")
  defer: zone.zoneEnd()

  let
    cCell = ctx.allocOrGrowCell(curveSize, PixelFormatRGBA32f)
  if cCell.tex.isNil:
    return

  let
    bCell = ctx.allocOrGrowCell(bandSize, PixelFormatRGBA32u)
  if bCell.tex.isNil:
    cCell.tex.freeCell(cCell)
    return

  (cCell, bCell)

proc writeBytes[T](tex: SlugTexture | ptr SlugTextureObj,
    cell: SlugGlyphTextureCell, data: openArray[T]) =
  if data.len <= 0:
    return

  let
    buffer = cast[ptr UncheckedArray[T]](tex.data[0].addr)
  copyMem(buffer[cell.base * sizeof(T)].addr, data[0].addr, data.len * sizeof(T))

proc writeBands(tex: SlugTexture | ptr SlugTextureObj,
    cell: SlugGlyphTextureCell, bake: SlugGlyphBaked, base: int32) =
  let
    zone = zoneBegin("glyphCache.writeBands")
  defer: zone.zoneEnd()

  if tex.data.len <= 0:
    return

  let
    buffer = cast[ptr UncheckedArray[uint32]](tex.data[0].addr)
    dstBase = cell.base * sizeof(uint32)

  var
    src = int32(0)
  while src < bake.bandBlock.len:
    let
      sx = int32(bake.bandBlock[src + 0])
      sy = int32(bake.bandBlock[src + 1])

    if (src div int32(4)) < bake.bandHeaderSize:
      buffer[dstBase + src + 0] = bake.bandBlock[src + 0]
      buffer[dstBase + src + 1] = bake.bandBlock[src + 1]
      buffer[dstBase + src + 2] = bake.bandBlock[src + 2]
      buffer[dstBase + src + 3] = bake.bandBlock[src + 3]
    else:
      let
        idx = sy * NVG_SLUG_TEXTURE_WIDTH + sx
        nidx = idx + base
      buffer[dstBase + src + 0] = uint32(nidx mod NVG_SLUG_TEXTURE_WIDTH)
      buffer[dstBase + src + 1] = uint32(nidx div NVG_SLUG_TEXTURE_WIDTH)
      buffer[dstBase + src + 2] = bake.bandBlock[src + 2]
      buffer[dstBase + src + 3] = bake.bandBlock[src + 3]
    src += int32(4)

proc placeGlyph(ctx: GlyphCache, c: ptr SlugGlyph, bake: SlugGlyphBaked,
    curveCell, bandCell: SlugGlyphTextureCell) =
  let
    zone = zoneBegin("glyphCache.placeGlyph")
  defer: zone.zoneEnd()

  curveCell.tex.writeBytes(curveCell, bake.curveBlock)
  bandCell.tex.writeBands(bandCell, bake, curveCell.base)

  curveCell.tex.markDirtyY(NVG_SLUG_TEXTURE_WIDTH, curveCell.base, curveCell.len)
  bandCell.tex.markDirtyY(NVG_SLUG_TEXTURE_WIDTH, bandCell.base, bandCell.len)

  let
    offset1 = int32(bandCell.base mod NVG_SLUG_TEXTURE_WIDTH)
    offset2 = int32(bandCell.base div NVG_SLUG_TEXTURE_WIDTH)

  c.glyphLoc = [offset1, offset2]
  c.curveCell = curveCell
  c.bandCell = bandCell

proc getGlyphInfo(ctx: GlyphCache, c: ptr SlugGlyph): SlugGlyphInfo =
  if not c.curveCell.tex.isNil and not c.bandCell.tex.isNil:
    result.bandTexId = c.bandCell.tex.texId
    result.curveTexId = c.curveCell.tex.texId

  result.rawBBox = c.rawBBox
  result.advance = c.advance
  result.lsb = c.lsb
  result.maxBandX = c.maxBandX
  result.maxBandY = c.maxBandY
  result.glyphLoc = c.glyphLoc

  c.lastAccess = ctx.now

  ctx.moveToFront(c.id)

proc createGlyph(ctx: GlyphCache, key: SlugGlyphKey,
    path: openArray[PathEntry], bounds: Bounds,
    advance, lsb: float32): ptr SlugGlyph =
  let
    zone = zoneBegin("glyphCache.createGlyph")
  defer: zone.zoneEnd()

  let
    g = buildGlyph(path, bounds, advance, lsb)
    bake = bakeGlyph(g)

  result = ctx.allocGlyph()
  result.key = key
  result.rawBBox = bounds
  result.advance = advance
  result.lsb = lsb
  result.maxBandX = int32(g.verticalBands.len) - 1
  result.maxBandY = int32(g.horizontalBands.len) - 1

  let
    cells = ctx.allocCurveAndBandCell(bake.curveSize, bake.bandSize)
  if not cells[0].tex.isNil and not cells[1].tex.isNil:
    ctx.placeGlyph(result, bake, cells[0], cells[1])

proc getGlyphInfo*(ctx: GlyphCache, font: Font,
    glyphId: GlyphId, shear: bool): SlugGlyphInfo =
  let
    zone = zoneBegin("glyphCache.getGlyphInfo")
  defer: zone.zoneEnd()

  let
    key = SlugGlyphKey(
      font: cast[uint](font),
      glyphId: glyphId,
      mask: uint32(shear),
    )

  var
    glyph = default(ptr SlugGlyph)

  ctx.lookup.withValue(key, val):
    let
      idx = val[].id
    glyph = ctx.glyphEntryList[idx].addr
  do:
    var
      matrix = mat2d()

    if shear:
      matrix.xy = float32(1.0 / 6.0)

    let
      path = font.getGlyphPath(glyphId, matrix)
      advance = font.getGlyphAdvance(glyphId)
      bounds = matrix * font.getGlyphBox(glyphId)
    glyph = ctx.createGlyph(key, path.commands, bounds, advance, float32(0.0))

    ctx.lookup[key] = glyph.id

  result = ctx.getGlyphInfo(glyph)

proc updateImage(ctx: GlyphCache, tex: SlugTexture) =
  let
    zone = zoneBegin("glyphCache.updateImage")
  defer: zone.zoneEnd()

  if tex.dirtyY0 >= 0 and tex.fillH > 0:
    let
      y0 = tex.dirtyY0
      y1 = min(tex.dirtyY1, tex.fillH)
      rows = y1 - y0
      rowBytes = NVG_SLUG_TEXTURE_WIDTH * tex.pixelFormat.bytesPerPixel

    if rows > 0:
      ctx.backendContext.writeImagePixels(tex.texId, 0, y0,
        NVG_SLUG_TEXTURE_WIDTH,
        rows, rowBytes,
        tex.data[y0 * rowBytes].addr)

    tex.dirtyY0 = -1
    tex.dirtyY1 = -1

proc uploadDirty*(ctx: GlyphCache) =
  let
    zone = zoneBegin("glyphCache.uploadDirty")
  defer: zone.zoneEnd()

  for tex in ctx.images:
    ctx.updateImage(tex)

  inc ctx.now, 1

  ctx.evictGlyph(10)
