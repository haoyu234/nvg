import ./core
import ./math
import ./path
import ./pieces

import std/endians
import std/hashes
import std/math

type
  GlyphId* = distinct uint32

  GlyphPoint = object
    flags: uint8
    contourEndIdx: uint16
    x, y, cx, cy: int32

  GlyphBox* = object
    xMin*, yMin*: int32
    xMax*, yMax*: int32

  FontMetrics* = object
    ascender*: int32
    descender*: int32
    lineGap*: int32

  GlyphMetrics* = object
    advance*: int32
    bearing*: int32

  GlyphLayer* = object
    glyphId*: GlyphId
    paletteIdx*: uint32

  GlyphLoader = object
    pp1X: int32
    pp1Y: int32
    pp2X: int32
    pp2Y: int32
    pp3X: int32
    pp3Y: int32
    pp4X: int32
    pp4Y: int32
    linear: int32
    linearDef: bool
    leftBearing: int32
    topBearing: int32
    verticalAdvance: int32
    horizontalAdvance: int32

  TrueType* = object
    data: Piece[byte]
    fontStart: uint32
    numGlyphs*: int32
    colr, cpal, glyf, gpos, head, hhea, hmtx, vhea, vmtx, kern, loca, os2: uint32
    indexMap: uint32
    indexToLocFormat: uint32

proc isNil*(glyphId: GlyphId): bool {.inline.} =
  uint32(glyphId) == 0

proc `$`*(glyphId: GlyphId): string {.borrow.}

proc hash*(glyphId: GlyphId): Hash {.borrow.}

proc `==`*(glyphId1, glyphId2: GlyphId): bool {.borrow.}

proc calcTag(data: static array[4, char]): uint32 {.raises: [].} =
  (uint32(data[0]) shl 24) + (uint32(data[1]) shl 16) + (uint32(data[
      2]) shl 8) +
    (uint32(data[3]) shl 0)

const
  TAG_CMAP = calcTag(['c', 'm', 'a', 'p'])
  TAG_CPAL = calcTag(['C', 'P', 'A', 'L'])
  TAG_COLR = calcTag(['C', 'O', 'L', 'R'])
  TAG_LOCA = calcTag(['l', 'o', 'c', 'a'])
  TAG_HEAD = calcTag(['h', 'e', 'a', 'd'])
  TAG_GLYF = calcTag(['g', 'l', 'y', 'f'])
  TAG_HHEA = calcTag(['h', 'h', 'e', 'a'])
  TAG_VHEA = calcTag(['v', 'h', 'e', 'a'])
  TAG_HMTX = calcTag(['h', 'm', 't', 'x'])
  TAG_VMTX = calcTag(['v', 'm', 't', 'x'])
  TAG_KERN = calcTag(['k', 'e', 'r', 'n'])
  TAG_GPOS = calcTag(['g', 'p', 'o', 's'])
  TAG_MAXP = calcTag(['m', 'a', 'x', 'p'])
  TAG_OS2 = calcTag(['O', 'S', '/', '2'])

proc toInt[T: SomeInteger, O: Natural](
    s: Piece[byte], offset: O, SIZE: static[Natural], _: typedesc[T]
): T {.inline, raises: [].} =
  assert sizeof(T) >= int32(SIZE)
  assert s.len >= int32(offset) + int32(SIZE)

  template RESULT_TYPE(): typedesc =
    const HAS_SIGN = T is SomeSignedInt
    when SIZE == 8:
      when HAS_SIGN: int64 else: uint64
    elif SIZE == 4:
      when HAS_SIGN: int32 else: uint32
    elif SIZE == 2:
      when HAS_SIGN: int16 else: uint16
    else:
      when HAS_SIGN: int8 else: uint8

  when SIZE > 1:
    var data = default(RESULT_TYPE())
    when SIZE == 8:
      bigEndian64(data.addr, s[int32(offset)].addr)
      T(data)
    elif SIZE == 4:
      bigEndian32(data.addr, s[int32(offset)].addr)
      T(data)
    elif SIZE == 2:
      bigEndian16(data.addr, s[int32(offset)].addr)
      T(data)
  else:
    let v = s[int32(offset)]
    T(cast[RESULT_TYPE()](v))

iterator tables(data: Piece[byte], fontStart: uint32): tuple[tag,
    offset: uint32] =
  let
    numTabs = data.toInt(fontStart + 4, 2, uint32)
    dir = fontStart + 12

  for idx in 0 ..< numTabs:
    let
      loc = dir + 16 * idx
      tag = data.toInt(loc, 4, uint32)
      offset = data.toInt(loc + 8, 4, uint32)

    yield (tag, offset)

proc parseTrueType*(data: openArray[byte], fontStart: uint32): TrueType =
  let
    data = piece(cast[ptr UncheckedArray[byte]](data[0].addr), data.len)

  var
    cmap = default(uint32)
    maxp = default(uint32)

  for (tag, offset) in data.tables(fontStart):
    case tag
    of TAG_CMAP: cmap = offset
    of TAG_COLR: result.colr = offset
    of TAG_CPAL: result.cpal = offset
    of TAG_GLYF: result.glyf = offset
    of TAG_GPOS: result.gpos = offset
    of TAG_HEAD: result.head = offset
    of TAG_HHEA: result.hhea = offset
    of TAG_VHEA: result.vhea = offset
    of TAG_HMTX: result.hmtx = offset
    of TAG_VMTX: result.vmtx = offset
    of TAG_KERN: result.kern = offset
    of TAG_LOCA: result.loca = offset
    of TAG_MAXP: maxp = offset
    of TAG_OS2: result.os2 = offset
    else: discard

  if cmap <= 0 or result.glyf <= 0 or result.head <= 0 or result.hhea <= 0 or
      result.hmtx <= 0 or result.loca <= 0:
    return

  let n = data.toInt(cmap + 2, 2, uint32)

  var indexMap = default(uint32)

  for idx in 0 ..< n:
    let
      encodingRecord = cmap + 4 + 8 * idx
      platformID = data.toInt(encodingRecord, 2, uint32)

    if platformID == 3: # microsoft
      let encodingID = data.toInt(encodingRecord + 2, 2, uint32)
      if encodingID == 1 or encodingID == 10:
        indexMap = cmap + data.toInt(encodingRecord + 4, 4, uint32)
    elif platformID == 0: # unicode
      indexMap = cmap + data.toInt(encodingRecord + 4, 4, uint32)

  if indexMap <= 0:
    return

  result.data = data
  result.fontStart = fontStart
  result.numGlyphs =
    if maxp > 0:
        int32(data.toInt(maxp + 4, 2, uint32))
      else:
        0xFFFF

  result.indexMap = indexMap
  result.indexToLocFormat = data.toInt(result.head + 50, 2, uint32)

proc getFontMetrics*(font: TrueType): FontMetrics =
  let
    ascender = font.data.toInt(font.hhea + 4, 2, int32)
    descender = font.data.toInt(font.hhea + 6, 2, int32)
    lineGap = font.data.toInt(font.hhea + 8, 2, int32)

  result.ascender = ascender
  result.descender = descender
  result.lineGap = lineGap

proc getFontTypographicMetrics*(font: TrueType): FontMetrics =
  if font.os2 > 0:
    let
      ascender = font.data.toInt(font.os2 + 68, 2, int32)
      descender = font.data.toInt(font.os2 + 70, 2, int32)
      lineGap = font.data.toInt(font.os2 + 72, 2, int32)

    result.ascender = ascender
    result.descender = descender
    result.lineGap = lineGap

proc getGlyphGlyfOffset(font: TrueType, glyphId: GlyphId): uint32 =
  if uint32(glyphId) >= uint32(font.numGlyphs) or font.indexToLocFormat >= 2:
    return

  var
    offset1 = default(uint32)
    offset2 = default(uint32)

  if font.indexToLocFormat == 0:
    offset1 =
      font.data.toInt(font.loca + uint32(glyphId) * 2, 2, uint32) * 2
    offset2 =
      font.data.toInt(font.loca + uint32(glyphId) * 2 + 2, 2,
          uint32) * 2
  else:
    offset1 = font.data.toInt(font.loca + uint32(glyphId) * 4, 4, uint32)
    offset2 =
      font.data.toInt(font.loca + uint32(glyphId) * 4 + 4, 4, uint32)

  # if a glyph has no outline or instructions, then loca[n] = loca[n+1]
  if offset1 == offset2:
    result = high(uint32)
    return

  font.glyf + offset1

proc getGlyphVerticalAdvance*(font: TrueType, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.vhea + 34, 2, uint32)
  if uint32(glyphId) < n:
    font.data.toInt(font.vmtx + 4 * uint32(glyphId), 2, int32)
  else:
    font.data.toInt(font.vmtx + 4 * (n - 1), 2, int32)

proc getGlyphAdvance*(font: TrueType, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if uint32(glyphId) < n:
    font.data.toInt(font.hmtx + 4 * uint32(glyphId), 2, int32)
  else:
    font.data.toInt(font.hmtx + 4 * (n - 1), 2, int32)

proc getGlyphVerticalMetrics*(font: TrueType,
    glyphId: GlyphId): GlyphMetrics =
  if font.vmtx > 0:
    let n = font.data.toInt(font.vhea + 34, 2, uint32)
    if uint32(glyphId) < n:
      result.advance = font.data.toInt(font.vmtx + 4 * uint32(glyphId), 2, int32)
      result.bearing = font.data.toInt(font.vmtx + 4 * uint32(glyphId) + 2, 2, int32)
    else:
      result.advance = font.data.toInt(font.vmtx + 4 * (n - 1), 2, int32)
      result.bearing = font.data.toInt(font.vmtx + 4 * n + 2 * (uint32(
          glyphId) - n), 2, int32)
    return

  let version =
    if font.os2 > 0:
        font.data.toInt(font.os2, 2, uint32)
      else:
        0xFFFF

  var
    ascender = default(int32)
    descender = default(int32)

  if version != 0xFFFF:
    ascender = font.data.toInt(font.os2 + 68, 2, int32)
    descender = font.data.toInt(font.os2 + 70, 2, int32)
  else:
    ascender = font.data.toInt(font.vhea + 4, 2, int32)
    descender = font.data.toInt(font.os2 + 6, 2, int32)

  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  let yMax = font.data.toInt(offset + 8, 2, int32)
  result.bearing = ascender - yMax
  result.advance = ascender - descender

proc getGlyphMetrics*(font: TrueType,
    glyphId: GlyphId): GlyphMetrics =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if uint32(glyphId) < n:
    result.advance = font.data.toInt(font.hmtx + 4 * uint32(glyphId), 2, int32)
    result.bearing = font.data.toInt(font.hmtx + 4 * uint32(glyphId) + 2, 2, int32)
  else:
    result.advance = font.data.toInt(font.hmtx + 4 * (n - 1), 2, int32)
    result.bearing = font.data.toInt(font.hmtx + 4 * n + 2 * (uint32(glyphId) -
        n), 2, int32)

proc getGlyphId*(font: TrueType, unicodeCodepoint: uint32): GlyphId =
  let format = font.data.toInt(font.indexMap + 0, 2, uint32)
  if format == 0: # Byte encoding table
    let len = font.data.toInt(font.indexMap + 2, 2, uint32)
    if unicodeCodepoint < len - 6:
      result = GlyphId(font.data.toInt(font.indexMap + 6 + unicodeCodepoint, 1, uint32))
    return
  elif format == 4: # Segment mapping to delta values
    if unicodeCodepoint > 0xFFFF:
      return

    let
      segCount = font.data.toInt(font.indexMap + 6, 2, uint32) shr 1
      rangeShift = font.data.toInt(font.indexMap + 12, 2, uint32)
      endCountIdx = font.indexMap + 14

    var
      search = endCountIdx
      searchRange = font.data.toInt(font.indexMap + 8, 2, uint32) shr 1
      idx = font.data.toInt(font.indexMap + 10, 2, uint32)

    if unicodeCodepoint >= font.data.toInt(search + rangeShift, 2, uint32):
      inc search, rangeShift

    dec search, 2

    while idx > 0:
      dec idx, 1

      let stop = font.data.toInt(search + searchRange, 2, uint32)
      if unicodeCodepoint > stop:
        inc search, searchRange

      searchRange = searchRange shr 1

    inc search, 2

    let
      item = search - endCountIdx
      movePos = font.data.toInt(endCountIdx + segCount * 2 + 2 + item, 2, uint32)
      stop = font.data.toInt(endCountIdx + item, 2, uint32)

    if unicodeCodepoint < movePos or unicodeCodepoint > stop:
      return

    let offset = font.data.toInt(endCountIdx + segCount * 6 + 2 + item, 2, uint32)
    if offset > 0:
      let glyphId = font.data.toInt(
        endCountIdx + segCount * 6 + 2 + item + offset + (unicodeCodepoint -
            movePos) * 2,
        2,
        uint32,
      )

      result = GlyphId(glyphId)
    else:
      let glyphId =
        int32(unicodeCodepoint) +
        font.data.toInt(endCountIdx + segCount * 4 + 2 + item, 2, int32)

      result = GlyphId(glyphId)
    return
  elif format == 6: # Trimmed table mapping
    let
      first = font.data.toInt(font.indexMap + 6, 2, uint32)
      count = font.data.toInt(font.indexMap + 8, 2, uint32)

    if unicodeCodepoint >= first and unicodeCodepoint < first + count:
      let glyphId =
        font.data.toInt(font.indexMap + 10 + (unicodeCodepoint - first) * 2, 2, uint32)

      result = GlyphId(glyphId)
    return
  elif format == 12 or format == 13: # Segmented coverage, Many-to-one range mappings
    var
      i = default(uint32)
      j = font.data.toInt(font.indexMap + 12, 4, uint32)

    while i < j:
      let
        mid = i + (j - i) shr 1
        glyphCharStart = font.data.toInt(font.indexMap + 16 + mid * 12, 4, uint32)
        glyphCharEnd = font.data.toInt(font.indexMap + 16 + mid * 12 + 4, 4, uint32)

      if unicodeCodepoint < glyphCharStart:
        j = mid
      elif unicodeCodepoint > glyphCharEnd:
        i = mid + 1
      else:
        let
          glyphStart = font.data.toInt(font.indexMap + 16 + mid * 12 + 8, 4, uint32)
          glyphId =
            if format == 12:
              glyphStart + unicodeCodepoint - glyphCharStart
            else:
              glyphStart

        result = GlyphId(glyphId)
        return

proc getGlyphBox*(font: TrueType, glyphId: GlyphId): GlyphBox =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  result.xMin = font.data.toInt(offset + 2, 2, int32)
  result.yMin = font.data.toInt(offset + 4, 2, int32)
  result.xMax = font.data.toInt(offset + 6, 2, int32)
  result.yMax = font.data.toInt(offset + 8, 2, int32)

proc getGlyphBitmapBox*(font: TrueType, glyphId: GlyphId, scaleX, scaleY,
    shiftX, shiftY: float32): GlyphBox =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  let
    xMin = font.data.toInt(offset + 2, 2, int32)
    yMin = font.data.toInt(offset + 4, 2, int32)
    xMax = font.data.toInt(offset + 6, 2, int32)
    yMax = font.data.toInt(offset + 8, 2, int32)

  result.xMin = int32(floor(float32(xMin) * scaleX + shiftX))
  result.yMin = int32(floor(-float32(yMax) * scaleY + shiftY))
  result.xMax = int32(ceil(float32(xMax) * scaleX + shiftX))
  result.yMax = int32(ceil(-float32(yMin) * scaleY + shiftY))

proc update(loader: var GlyphLoader, font: TrueType, glyphId: GlyphId) =
  let
    bbox = font.getGlyphBox(glyphId)
    hMetrics = font.getGlyphMetrics(glyphId)
    vMetrics = font.getGlyphVerticalMetrics(glyphId)

  loader.pp1X = bbox.xMin - hMetrics.bearing
  loader.pp1Y = 0
  loader.pp2X = loader.pp1X + hMetrics.advance
  loader.pp2Y = 0
  loader.pp3X = 0
  loader.pp3Y = bbox.yMax + vMetrics.bearing
  loader.pp4X = 0
  loader.pp4Y = loader.pp3Y - vMetrics.advance
  loader.leftBearing = hMetrics.bearing
  loader.horizontalAdvance = hMetrics.advance
  loader.topBearing = vMetrics.bearing
  loader.verticalAdvance = vMetrics.advance

  if not loader.linearDef:
    loader.linearDef = true
    loader.linear = hMetrics.advance

proc loadSimpleGlyphAux(loader: var GlyphLoader, font: TrueType,
  offset, contourCount: uint32, points: var seq[GlyphPoint]): bool =
  let
    ins = font.data.toInt(offset + 10 + contourCount * 2, 2, uint32)
    pointCount = 1 + font.data.toInt(offset + 10 + contourCount * 2 - 2, 2, uint32)
    oldLen = uint32(points.len)

  points.setLen(oldLen + pointCount)

  let outputBuf = cast[ptr UncheckedArray[GlyphPoint]](points[oldLen].addr)

  var pointIdx = default(int32)
  for contourIdx in 0 ..< contourCount:
    let pointEndIdx = font.data.toInt(offset + 10 + contourIdx * 2, 2, int32)
    outputBuf[pointIdx].contourEndIdx = uint16(oldLen) + uint16(pointEndIdx)
    pointIdx = pointEndIdx + 1

  var
    x = default(int32)
    y = default(int32)
    flags = default(uint8)
    repeatCount = default(uint8)
    rpos = offset + 10 + contourCount * 2 + 2 + ins

  template next(n, T): auto =
    let data = font.data.toInt(rpos, n, T)
    inc rpos, n
    data

  for idx in 0 ..< pointCount:
    if repeatCount == 0:
      flags = next(1, uint8)
      if (flags and 0x8) != 0:
        repeatCount = next(1, uint8)
    else:
      dec repeatCount, 1

    outputBuf[idx].flags = flags

  if repeatCount > 0:
    return

  for idx in 0 ..< pointCount:
    let p = outputBuf[idx].addr
    if (p.flags and 0x2) != 0:
      if (p.flags and 0x10) != 0:
        inc x, next(1, uint8)
      else:
        dec x, next(1, uint8)
    else:
      if (p.flags and 0x10) == 0:
        inc x, next(2, int32)

    p[].x = x

  for idx in 0 ..< pointCount:
    let p = outputBuf[idx].addr
    if (p.flags and 0x4) != 0:
      if (p.flags and 0x20) != 0:
        inc y, next(1, uint8)
      else:
        dec y, next(1, uint8)
    else:
      if (p.flags and 0x20) == 0:
        inc y, next(2, int32)

    p[].y = y

  result = true

proc loadGlyphAux(loader: var GlyphLoader, font: TrueType, glyphId: GlyphId,
    points: var seq[GlyphPoint]): bool

proc loadCompositeGlyphAux(loader: var GlyphLoader, font: TrueType,
    offset: uint32, points: var seq[GlyphPoint]): bool =
  var
    more = true
    rpos = offset + 10

  template next(n, T): auto =
    let data = font.data.toInt(rpos, n, T)
    inc rpos, n
    data

  let
    oldLen = uint32(points.len)

  while more:
    let
      subGlyphFlags = next(2, uint32)
      subGlyphId = GlyphId(next(2, uint32))
      baseLen = uint32(points.len)

    more = (subGlyphFlags and 0x0020) != 0

    var
      xx = int32(0x10000)
      xy = int32(0)
      yy = int32(0x10000)
      yx = int32(0)
      arg1 = default(int32)
      arg2 = default(int32)

    if (subGlyphFlags and 0x0002) != 0:
      if (subGlyphFlags and 0x0001) != 0:
        arg1 = next(2, int32)
        arg2 = next(2, int32)
      else:
        arg1 = next(1, int32)
        arg2 = next(1, int32)
    else:
      if (subGlyphFlags and 0x0001) != 0:
        arg1 = int32(next(2, uint32))
        arg2 = int32(next(2, uint32))
      else:
        arg1 = int32(next(1, uint32))
        arg2 = int32(next(1, uint32))

    if (subGlyphFlags and 0x0008) != 0:
      xx = next(2, int32) shl 2
      yy = xx
    elif (subGlyphFlags and 0x0040) != 0:
      xx = next(2, int32) shl 2
      yy = next(2, int32) shl 2
    elif (subGlyphFlags and 0x0080) != 0:
      xx = next(2, int32) shl 2
      yx = next(2, int32) shl 2
      xy = next(2, int32) shl 2
      yy = next(2, int32) shl 2

    # echo arg1, " ", arg2
    # echo xx, " ", xy, " ", yx, " ", yy

    let loaderCopy = loader

    result = loader.loadGlyphAux(font, subGlyphId, points)
    if not result:
      return

    if (subGlyphFlags and 0x0200) <= 0:
      loader = loaderCopy

    template mulFix(a, b: int32): int32 =
      let
        ab1 = int64(a) * int64(b)
        ab2 = ab1 + int64(0x8000) + (ab1 shr 63)
      int32(ab2 shr 16)

    template hypot(a, b: int32): int32 =
      let
        a2 = abs(a)
        b2 = abs(b)

      if a2 > b2:
        a2 + (3 * b2) shr 3
      else:
        b2 + (3 * a2) shr 3

    let haveScale = (subGlyphFlags and (0x0008 or 0x0040 or 0x0080)) > 0
    if haveScale:
      for idx in baseLen ..< uint32(points.len):
        let
          p = points[idx].addr
          x = p.x
          y = p.y

        p.x = mulFix(x, xx) + mulFix(y, xy)
        p.y = mulFix(x, yx) + mulFix(y, yy)

    var
      x = default(int32)
      y = default(int32)

    if (subGlyphFlags and 0x0002) != 0:
      x = arg1
      y = arg2

      if x == 0 and y == 0:
        continue

      if haveScale and (subGlyphFlags and 0x0800) != 0:
        let
          xScale = hypot(xx, xy)
          yScale = hypot(yy, yx)

        x = mulFix(x, xScale)
        y = mulFix(y, yScale)
    else:
      let
        p1 = points[arg1 + int32(oldLen)].addr
        p2 = points[arg2 + int32(baseLen)].addr

      x = p1.x - p2.x
      y = p1.y - p2.y

    # echo "x: ", x, " y: ", y

    if x != 0 or y != 0:
      for idx in baseLen ..< uint32(points.len):
        let p = points[idx].addr
        p.x = p.x + x
        p.y = p.y + y

proc loadGlyphAux(loader: var GlyphLoader, font: TrueType, glyphId: GlyphId,
    points: var seq[GlyphPoint]): bool =
  loader.update(font, glyphId)

  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset > 0:
    if offset == high(uint32):
      result = true
    else:
      let contourCount = font.data.toInt(offset, 2, int32)
      if contourCount > 0:
        result = loader.loadSimpleGlyphAux(font, offset, uint32(contourCount), points)
      elif contourCount < 0:
        result = loader.loadCompositeGlyphAux(font, offset, points)

proc getGlyphPath(loader: GlyphLoader, points: seq[GlyphPoint]): Path =
  var
    pointIdx = default(int32)

  while pointIdx < points.len:
    let
      pointEndIdx = int32(points[pointIdx].contourEndIdx)

    var
      closed = false
      limit = pointEndIdx
      sx = float32(points[pointIdx].x)
      sy = float32(points[pointIdx].y)

    if (points[pointIdx].flags and 0x1) == 0:
      if (points[pointEndIdx].flags and 0x1) != 0:
        dec limit, 1
        sx = float32(points[pointEndIdx].x)
        sy = float32(points[pointEndIdx].y)
      else:
        sx = float32((points[pointIdx].x + points[pointEndIdx].x) div 2)
        sy = float32((points[pointIdx].y + points[pointEndIdx].y) div 2)
      dec pointIdx, 1

    result.moveTo(vec2(sx, sy))

    while pointIdx < limit:
      inc pointIdx, 1

      if (points[pointIdx].flags and 0x01) != 0:
        let
          x = float32(points[pointIdx].x)
          y = float32(points[pointIdx].y)

        result.lineTo(vec2(x, y))
      else:
        var
          cx = float32(points[pointIdx].x)
          cy = float32(points[pointIdx].y)

        while true:
          if pointIdx < limit:
            inc pointIdx, 1

            if (points[pointIdx].flags and 0x01) != 0:
              let
                x = float32(points[pointIdx].x)
                y = float32(points[pointIdx].y)

              result.quadCurveTo(vec2(cx, cy), vec2(x, y))
            else:
              let
                x = float32(int32(cx + float32(points[pointIdx].x)) div 2)
                y = float32(int32(cy + float32(points[pointIdx].y)) div 2)

              result.quadCurveTo(vec2(cx, cy), vec2(x, y))

              cx = float32(points[pointIdx].x)
              cy = float32(points[pointIdx].y)
              continue
          else:
            result.quadCurveTo(vec2(cx, cy), vec2(sx, sy))
            closed = true
          break

    if not closed:
      result.lineTo(vec2(sx, sy))

    pointIdx = pointEndIdx + 1

proc getGlyphPath*(font: TrueType, glyphId: GlyphId): Path {.inline.} =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  var
    loader = default(GlyphLoader)
    points = default(seq[GlyphPoint])

  if loader.loadGlyphAux(font, glyphId, points):
    if loader.pp1X != 0:
      for idx in 0 ..< uint32(points.len):
        let p = points[idx].addr
        p.x = p.x - loader.pp1X

    # var idx = 0
    # for p in points:
    #   echo "idx: ", idx, " ", p
    #   inc idx, 1

    result = loader.getGlyphPath(points)

proc getCoverageIndex(
    font: TrueType, coverageTable: uint32, glyphId: GlyphId
): uint32 =
  let coverageFormat = font.data.toInt(coverageTable, 2, uint32)

  if coverageFormat == 1:
    let glyphCount = font.data.toInt(coverageTable + 2, 2, uint32)

    if glyphCount >= 1:
      var
        l = uint32(0)
        r = glyphCount - 1
        mid = default(uint32)

      while l <= r:
        mid = (l + r) shr 1

        let
          glyphArray = coverageTable + 4
          glyphId2 = font.data.toInt(glyphArray + 2 * mid, 2, uint32)

        if uint32(glyphId) < glyphId2:
          r = mid - 1
        elif uint32(glyphId) > glyphId2:
          r = mid + 1
        else:
          result = mid
          return

  elif coverageFormat == 2:
    let
      rangeCount = font.data.toInt(coverageTable + 2, 2, uint32)
      rangeArray = coverageTable + 4

    if rangeCount >= 1:
      var
        l = uint32(0)
        r = rangeCount - 1
        mid = default(uint32)

      while l <= r:
        mid = (l + r) shr 1
        let
          rangeRecord = rangeArray + 6 * mid
          glyphIdStart = font.data.toInt(rangeRecord, 2, uint32)
          glyphIdEnd = font.data.toInt(rangeRecord + 2, 2, uint32)
        if uint32(glyphId) < glyphIdStart:
          r = mid - 1
        elif uint32(glyphId) > glyphIdEnd:
          l = mid + 1
        else:
          let startCoverageIndex = font.data.toInt(rangeRecord + 4, 2, uint32)
          result = startCoverageIndex + uint32(glyphId) - glyphIdStart
          return

  high(uint32)

proc getGlyphClass(font: TrueType, classDefTable: uint32,
    glyphId: GlyphId): uint32 =
  let classDefFormat = font.data.toInt(classDefTable, 2, uint32)
  if classDefFormat == 1:
    let
      startGlyphId = font.data.toInt(classDefTable + 2, 2, uint32)
      glyphCount = font.data.toInt(classDefTable + 4, 2, uint32)
      classDef1ValueArray = classDefTable + 6
    if uint32(glyphId) >= startGlyphId and uint32(glyphId) < (startGlyphId + glyphCount):
      result = font.data.toInt(
        classDef1ValueArray + 2 * (uint32(glyphId) - startGlyphId), 2, uint32
      )
      return
  elif classDefFormat == 2:
    let
      classRangeCount = font.data.toInt(classDefTable + 2, 2, uint32)
      classRangeRecords = classDefTable + 4

    if classRangeCount >= 1:
      var
        l = default(uint32)
        r = classRangeCount - 1
        mid = default(uint32)

      while l <= r:
        mid = (l + r) shr 1
        let
          classRangeRecord = classRangeRecords + 6 * mid
          glyphIdStart = font.data.toInt(classRangeRecord, 2, uint32)
          glyphIdEnd = font.data.toInt(classRangeRecord + 2, 2, uint32)

        if uint32(glyphId) < glyphIdStart:
          r = mid - 1
        elif uint32(glyphId) > glyphIdEnd:
          l = mid + 1
        else:
          result = font.data.toInt(classRangeRecord + 4, 2, uint32)
          return

  high(uint32)

proc getGlyphGposInfoAdvance(font: TrueType, glyphId1,
    glyphId2: GlyphId): uint32 =
  let
    major = font.data.toInt(font.gpos + 0, 2, uint32)
    minor = font.data.toInt(font.gpos + 2, 2, uint32)

  if major != 1 or minor != 0:
    return

  let
    lookupListOffset = font.data.toInt(font.gpos + 8, 2, uint32)
    lookupList = font.gpos + lookupListOffset
    lookupCount = font.data.toInt(lookupList, 2, uint32)

  for idx in 0 ..< lookupCount:
    let
      lookupOffset = font.data.toInt(lookupList + 2 + 2 * idx, 2, uint32)
      lookupTable = lookupList + lookupOffset

      lookupType = font.data.toInt(lookupTable, 2, uint32)
      tableCount = font.data.toInt(lookupTable + 4, 2, uint32)

    if lookupType != 2:
      continue

    for tIdx in 0 ..< tableCount:
      let
        tableOffset = font.data.toInt(lookupTable + 6 + 2 * tIdx, 2, uint32)
        table = lookupTable + tableOffset
        posFormat = font.data.toInt(table, 2, uint32)
        coverageOffset = font.data.toInt(table + 2, 2, uint32)
        coverageIndex = font.getCoverageIndex(table + coverageOffset, glyphId1)

      if coverageIndex == high(uint32):
        continue

      if posFormat == 1:
        let
          valueFormat1 = font.data.toInt(table + 4, 2, uint32)
          valueFormat2 = font.data.toInt(table + 6, 2, uint32)

        if valueFormat1 == 4 and valueFormat2 == 0:
          let
            valueRecordPairSizeInBytes = uint32(2)
            pairSetCount = font.data.toInt(table + 8, 2, uint32)
            pairPosOffset = font.data.toInt(table + 10 + 2 * coverageIndex, 2, uint32)
            pairValueTable = table + pairPosOffset
            pairValueCount = font.data.toInt(pairValueTable, 2, uint32)
            pairValueArray = pairValueTable + 2

          if pairValueCount < 1 or coverageIndex >= pairSetCount:
            return

          var
            l = default(uint32)
            r = pairValueCount - 1
            mid = default(uint32)

          while l <= r:
            mid = (l + r) shr 1

            let
              val = pairValueArray + (2 + valueRecordPairSizeInBytes) * mid
              glyphId3 = font.data.toInt(val, 2, uint32)

            if uint32(glyphId2) < glyphId3:
              r = mid - 1
            elif uint32(glyphId2) > glyphId3:
              l = mid + 1
            else:
              result = font.data.toInt(val + 2, 2, uint32)
              return

      elif posFormat == 2:
        let
          valueFormat1 = font.data.toInt(table + 4, 2, uint32)
          valueFormat2 = font.data.toInt(table + 6, 2, uint32)

        if valueFormat1 == 4 and valueFormat2 == 0:
          let
            classDef1Offset = font.data.toInt(table + 8, 2, uint32)
            classDef2Offset = font.data.toInt(table + 10, 2, uint32)

            glyph1Class = font.getGlyphClass(table + classDef1Offset, glyphId1)
            glyph2Class = font.getGlyphClass(table + classDef2Offset, glyphId2)

            class1Count = font.data.toInt(table + 12, 2, uint32)
            class2Count = font.data.toInt(table + 14, 2, uint32)

          if glyph1Class == high(uint32) or glyph1Class >= class1Count or
              glyph2Class == high(uint32) or glyph2Class >= class2Count:
            return

          let
            class1Records = table + 16
            class2Records = class1Records + 2 * (glyph1Class * class1Count)

          result = font.data.toInt(class2Records + 2 * glyph2Class, 2, uint32)
          return

proc getGlyphKernInfoAdvance(font: TrueType, glyphId1,
    glyphId2: GlyphId): uint32 =
  let
    n = font.data.toInt(2, 2, uint32)
    format = font.data.toInt(8, 2, uint32)

  if n < 1 or format != 1:
    return

  var
    l = default(uint32)
    r = font.data.toInt(10, 2, uint32) - 1
    mid = default(uint32)
    v1 = (uint32(glyphId1) shl 16) or uint32(glyphId2)

  while l <= r:
    mid = (l + r) shr 1
    let v2 = font.data.toInt(18 + (mid * 6), 4, uint32)
    if v1 < v2:
      r = mid - 1
    elif v1 > v2:
      l = mid + 1
    else:
      result = font.data.toInt(22 + (mid * 6), 2, uint32)
      return

proc getGlyphKernAdvance*(font: TrueType, glyphId1,
    glyphId2: GlyphId): uint32 =
  if font.gpos > 0:
    result = font.getGlyphGposInfoAdvance(glyphId1, glyphId2)
    if result != 0:
      return

  if font.kern > 0:
    result = font.getGlyphKernInfoAdvance(glyphId1, glyphId2)

proc getGlyphColrOffset(font: TrueType, glyphId: GlyphId): uint32 =
  let
    numBaseGlyphRecords = font.data.toInt(font.colr + 2, 2, uint32)
    baseGlyphRecordsOffset = font.colr + font.data.toInt(font.colr + 4, 4, uint32)

  if numBaseGlyphRecords <= 0:
    return

  var
    l = default(uint32)
    r = numBaseGlyphRecords - 1
    mid = default(uint32)

  while l <= r:
    mid = (l + r) shr 1

    let
      baseGlyphRecord = baseGlyphRecordsOffset + 6 * mid
      glyphId2 = font.data.toInt(baseGlyphRecord, 2, uint32)

    if uint32(glyphId) < glyphId2:
      r = mid - 1
    elif uint32(glyphId) > glyphId2:
      l = mid + 1
    else:
      result = baseGlyphRecord
      return

proc getPaletteColor*(font: TrueType, paletteIdx: uint32,
    palette: uint32): Color =
  let
    numPaletteEntries = font.data.toInt(font.cpal + 2, 2, uint32)
    numPalettes = font.data.toInt(font.cpal + 4, 2, uint32)
    numColorRecords = font.data.toInt(font.cpal + 6, 2, uint32)
    colorRecordsArrayOffset = font.cpal + font.data.toInt(font.cpal + 8, 4, uint32)

  if paletteIdx >= numPaletteEntries or palette >= numPalettes:
    return

  let
    colorRecordIndicesOffset = font.cpal + 12
    colorRecordIndex = paletteIdx + font.data.toInt(colorRecordIndicesOffset +
        2 * palette, 2, uint32)
  if colorRecordIndex >= numColorRecords:
    return

  let hexColor = font.data.toInt(colorRecordsArrayOffset + 4 * colorRecordIndex,
      4, uint32)
  result.a = float32((hexColor shr 0) and 0xFF) / 255
  result.r = float32((hexColor shr 8) and 0xFF) / 255
  result.g = float32((hexColor shr 16) and 0xFF) / 255
  result.b = float32((hexColor shr 24) and 0xFF) / 255

proc getGlyphLayers*(font: TrueType, glyphId: GlyphId): seq[GlyphLayer] =
  let glyphBasGlyphRecord = font.getGlyphColrOffset(glyphId)
  if glyphBasGlyphRecord > 0:
    let
      firstLayerIndex = font.data.toInt(glyphBasGlyphRecord + 2, 2, uint32)
      numLayers = font.data.toInt(glyphBasGlyphRecord + 4, 2, uint32)
      layerRecordsOffset = font.data.toInt(font.colr + 8, 4, uint32)

    if numLayers >= 1:
      let
        glyphLayerRecordStart = font.colr + layerRecordsOffset + 4 * firstLayerIndex

      result.setLen(numLayers)

      for idx in 0 ..< numLayers:
        let
          glyphId2 = font.data.toInt(glyphLayerRecordStart + idx * 4, 2, uint32)
          paletteIdx = font.data.toInt(glyphLayerRecordStart + idx * 4 + 2, 2, uint32)

        let layer = result[idx].addr
        layer.glyphId = GlyphId(glyphId2)
        layer.paletteIdx = paletteIdx

proc hasColor*(font: TrueType, glyphId: GlyphId): bool =
  if font.colr > 0 and font.cpal > 0:
    result = font.getGlyphColrOffset(glyphId) > 0
