import std/endians
import std/math

import ./core
import ./math
import ./path
import ./pieces
import ./tracy

type
  GlyphBox* = object
    xMin*: int32
    yMin*: int32
    xMax*: int32
    yMax*: int32

  GlyphPoint = object
    flags: uint8
    contourEndIdx: uint16
    x, y, cx, cy: int32

  GlyphLayer* = object
    glyphId*: GlyphId
    paletteEntryIndex*: uint16

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

  ColrGlyph* = object
    glyphId*: GlyphId
    paletteEntryIndex*: uint16
    alpha*: float32
    paintTransform*: Mat2d

  TrueType* = object
    data: Piece[byte]
    fontStart: uint32
    numGlyphs*: int32
    colr, cpal, glyf, gpos, head, hhea, hmtx, vhea, vmtx, kern, loca, os2: uint32
    indexMap: uint32
    indexToLocFormat: uint32

proc isNil*(glyphId: GlyphId): bool {.inline.} =
  uint32(glyphId.id) == 0

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
  let
    offset = int32(offset)

  assert sizeof(T) >= SIZE
  assert s.len >= offset + SIZE

  template RESULT_TYPE(): typedesc =
    const HAS_SIGN = T is SomeSignedInt
    when SIZE == 8:
      when HAS_SIGN: int64 else: uint64
    elif SIZE == 4:
      when HAS_SIGN: int32 else: uint32
    elif SIZE == 3:
      # 3 bytes, big-endian; smallest holding type is 32-bit
      when HAS_SIGN: int32 else: uint32
    elif SIZE == 2:
      when HAS_SIGN: int16 else: uint16
    else:
      when HAS_SIGN: int8 else: uint8

  when SIZE > 1:
    var data = default(RESULT_TYPE())
    when SIZE == 8:
      bigEndian64(data.addr, s[offset].addr)
      T(data)
    elif SIZE == 4:
      bigEndian32(data.addr, s[offset].addr)
      T(data)
    elif SIZE == 3:
      # 3 bytes, big-endian: no endian helper, assemble manually
      let
        val = (uint32(s[offset]) shl 16) or (uint32(s[offset +
            1]) shl 8) or uint32(s[offset + 2])
      when T is SomeSignedInt:
        # sign-extend from bit 23
        data = cast[int32](val shl 8) shr 8
      else:
        data = val
      T(data)
    elif SIZE == 2:
      bigEndian16(data.addr, s[offset].addr)
      T(data)
  else:
    let v = s[offset]
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
    cmap = uint32(0)
    maxp = uint32(0)

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

  var indexMap = uint32(0)

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
    unitsPerEm = font.data.toInt(font.head + 18, 2, uint32)

  result.ascender = ascender
  result.descender = descender
  result.lineGap = lineGap
  result.unitsPerEm = unitsPerEm

proc getFontTypographicMetrics*(font: TrueType): FontMetrics =
  if font.os2 > 0:
    let
      ascender = font.data.toInt(font.os2 + 68, 2, int32)
      descender = font.data.toInt(font.os2 + 70, 2, int32)
      lineGap = font.data.toInt(font.os2 + 72, 2, int32)
      unitsPerEm = font.data.toInt(font.head + 18, 2, uint32)

    result.ascender = ascender
    result.descender = descender
    result.lineGap = lineGap
    result.unitsPerEm = unitsPerEm

proc getWeight*(font: TrueType): FontWeight =
  if font.os2 <= 0:
    return Normal
  let w = int32(font.data.toInt(font.os2 + 4, 2, uint32))
  case w
  of 100: Thin
  of 200: ExtraLight
  of 300: Light
  of 400: Normal
  of 500: Medium
  of 600: Semibold
  of 700: Bold
  of 800: ExtraBold
  of 900: Black
  of 950: UltraBlack
  else:
    if w < 400: Light
    elif w < 700: Medium
    else: Bold

proc getStretch*(font: TrueType): FontStretch =
  if font.os2 <= 0:
    return Normal
  let wc = int32(font.data.toInt(font.os2 + 6, 2, uint32))
  case wc
  of 1: UltraCondensed
  of 2: ExtraCondensed
  of 3: Condensed
  of 4: SemiCondensed
  of 5: Normal
  of 6: SemiExpanded
  of 7: Expanded
  of 8: ExtraExpanded
  of 9: UltraExpanded
  else: Normal

proc getStyle*(font: TrueType): FontStyle =
  if font.os2 <= 0:
    return Normal
  let fs = font.data.toInt(font.os2 + 62, 2, uint32)
  if (fs and uint32(0x1)) != 0: Italic
  elif (fs and uint32(0x200)) != 0: Oblique
  else: Normal

proc getCoveredRanges*(font: TrueType): seq[(uint32, uint32)] =
  if font.indexMap <= 0:
    return

  let format = font.data.toInt(font.indexMap + 0, 2, uint32)
  case format
  of uint32(0): # Byte encoding table
    let len = font.data.toInt(font.indexMap + 2, 2, uint32)
    if len > 6:
      var start = uint32(0)
      var inRun = false
      let last = (len - 6) - 1
      for c in uint32(0) .. last:
        let g = font.data.toInt(font.indexMap + 6 + c, 1, uint32)
        if g != 0:
          if not inRun:
            start = c
            inRun = true
        elif inRun:
          result.add((start, c - 1))
          inRun = false
      if inRun:
        result.add((start, last))
  of uint32(4): # Segment mapping to delta values
    let
      segCount = font.data.toInt(font.indexMap + 6, 2, uint32) shr 1
      endCountIdx = font.indexMap + 14
    for i in uint32(0) ..< segCount:
      let
        endCount = font.data.toInt(endCountIdx + i * 2, 2, uint32)
        startCount = font.data.toInt(endCountIdx + segCount * 2 + 2 + i * 2, 2, uint32)
      if startCount <= endCount and startCount != uint32(0xFFFF):
        result.add((startCount, endCount))
  of uint32(6): # Trimmed table mapping
    let
      first = font.data.toInt(font.indexMap + 6, 2, uint32)
      count = font.data.toInt(font.indexMap + 8, 2, uint32)
    if count > 0:
      result.add((first, first + count - 1))
  of uint32(12), uint32(13): # Segmented coverage / many-to-one
    let groups = font.data.toInt(font.indexMap + 12, 4, uint32)
    for i in uint32(0) ..< groups:
      let
        startCode = font.data.toInt(font.indexMap + 16 + i * 12, 4, uint32)
        endCode = font.data.toInt(font.indexMap + 16 + i * 12 + 4, 4, uint32)
      if startCode <= endCode:
        result.add((startCode, endCode))
  else:
    discard

proc getGlyphGlyfOffset(font: TrueType, glyphId: GlyphId): uint32 =
  if glyphId.id >= uint32(font.numGlyphs) or font.indexToLocFormat >= 2:
    return

  var
    offset1 = uint32(0)
    offset2 = uint32(0)

  if font.indexToLocFormat == 0:
    offset1 =
      font.data.toInt(font.loca + glyphId.id * 2, 2, uint32) * 2
    offset2 =
      font.data.toInt(font.loca + glyphId.id * 2 + 2, 2,
          uint32) * 2
  else:
    offset1 = font.data.toInt(font.loca + glyphId.id * 4, 4, uint32)
    offset2 =
      font.data.toInt(font.loca + glyphId.id * 4 + 4, 4, uint32)

  # if a glyph has no outline or instructions, then loca[n] = loca[n+1]
  if offset1 == offset2:
    result = high(uint32)
    return

  font.glyf + offset1

proc getGlyphVerticalAdvance*(font: TrueType, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.vhea + 34, 2, uint32)
  if glyphId.id < n:
    font.data.toInt(font.vmtx + 4 * glyphId.id, 2, int32)
  else:
    font.data.toInt(font.vmtx + 4 * (n - 1), 2, int32)

proc getGlyphAdvance*(font: TrueType, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if glyphId.id < n:
    font.data.toInt(font.hmtx + 4 * glyphId.id, 2, int32)
  else:
    font.data.toInt(font.hmtx + 4 * (n - 1), 2, int32)

proc getGlyphVerticalMetrics*(font: TrueType,
    glyphId: GlyphId): GlyphMetrics =
  if font.vmtx > 0:
    let n = font.data.toInt(font.vhea + 34, 2, uint32)
    if glyphId.id < n:
      result.advance = font.data.toInt(font.vmtx + 4 * glyphId.id, 2, int32)
      result.bearing = font.data.toInt(font.vmtx + 4 * glyphId.id + 2, 2, int32)
    else:
      result.advance = font.data.toInt(font.vmtx + 4 * (n - 1), 2, int32)
      result.bearing = font.data.toInt(font.vmtx + 4 * n + 2 * (glyphId.id - n),
          2, int32)
    return

  let version =
    if font.os2 > 0:
        font.data.toInt(font.os2, 2, uint32)
      else:
        0xFFFF

  var
    ascender = int32(0)
    descender = int32(0)

  if version != 0xFFFF:
    ascender = font.data.toInt(font.os2 + 68, 2, int32)
    descender = font.data.toInt(font.os2 + 70, 2, int32)
  else:
    ascender = font.data.toInt(font.vhea + 4, 2, int32)
    descender = font.data.toInt(font.vhea + 6, 2, int32)

  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  let yMax = font.data.toInt(offset + 8, 2, int32)
  result.bearing = ascender - yMax
  result.advance = ascender - descender

proc getGlyphMetrics*(font: TrueType,
    glyphId: GlyphId): GlyphMetrics =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if glyphId.id < n:
    result.advance = font.data.toInt(font.hmtx + 4 * glyphId.id, 2, int32)
    result.bearing = font.data.toInt(font.hmtx + 4 * glyphId.id + 2, 2, int32)
  else:
    result.advance = font.data.toInt(font.hmtx + 4 * (n - 1), 2, int32)
    result.bearing = font.data.toInt(font.hmtx + 4 * n + 2 * (glyphId.id -
        n), 2, int32)

proc getGlyphId*(font: TrueType, unicodeCodepoint: uint32): GlyphId =
  let
    zone = zoneBegin("truetype.getGlyphId")
  defer: zone.zoneEnd()

  let format = font.data.toInt(font.indexMap + 0, 2, uint32)
  if format == 0: # Byte encoding table
    let len = font.data.toInt(font.indexMap + 2, 2, uint32)
    if unicodeCodepoint < len - 6:
      let glyphId = font.data.toInt(font.indexMap + 6 + unicodeCodepoint, 1, uint32)
      result.id = glyphId
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

      result.id = glyphId
    else:
      let glyphId =
        uint32(int32(unicodeCodepoint) +
        font.data.toInt(endCountIdx + segCount * 4 + 2 + item, 2, int32))

      result.id = glyphId
    return
  elif format == 6: # Trimmed table mapping
    let
      first = font.data.toInt(font.indexMap + 6, 2, uint32)
      count = font.data.toInt(font.indexMap + 8, 2, uint32)

    if unicodeCodepoint >= first and unicodeCodepoint < first + count:
      let glyphId =
        font.data.toInt(font.indexMap + 10 + (unicodeCodepoint - first) * 2, 2, uint32)

      result.id = glyphId
    return
  elif format == 12 or format == 13: # Segmented coverage, Many-to-one range mappings
    var
      i = uint32(0)
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

        result.id = glyphId
        return

proc getGlyphBox*(font: TrueType, glyphId: GlyphId): GlyphBox =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0 or offset == high(uint32):
    return

  result.xMin = font.data.toInt(offset + 2, 2, int32)
  result.yMin = font.data.toInt(offset + 4, 2, int32)
  result.xMax = font.data.toInt(offset + 6, 2, int32)
  result.yMax = font.data.toInt(offset + 8, 2, int32)

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
    zone = zoneBegin("truetype.loadSimpleGlyphAux")
  defer: zone.zoneEnd()

  let
    ins = font.data.toInt(offset + 10 + contourCount * 2, 2, uint32)
    pointCount = 1 + font.data.toInt(offset + 10 + contourCount * 2 - 2, 2, uint32)
    oldLen = uint32(points.len)

  points.setLen(oldLen + pointCount)

  let outputBuf = cast[ptr UncheckedArray[GlyphPoint]](points[oldLen].addr)

  var pointIdx = int32(0)
  for contourIdx in 0 ..< contourCount:
    let pointEndIdx = font.data.toInt(offset + 10 + contourIdx * 2, 2, int32)
    outputBuf[pointIdx].contourEndIdx = uint16(oldLen) + uint16(pointEndIdx)
    pointIdx = pointEndIdx + 1

  var
    x = int32(0)
    y = int32(0)
    flags = uint8(0)
    repeatCount = uint8(0)
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
    points: var seq[GlyphPoint]): bool {.gcsafe.}

proc loadCompositeGlyphAux(loader: var GlyphLoader, font: TrueType,
    offset: uint32, points: var seq[GlyphPoint]): bool =
  let
    zone = zoneBegin("truetype.loadCompositeGlyphAux")
  defer: zone.zoneEnd()

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
      subGlyphId = GlyphId(id: next(2, uint32))
      baseLen = uint32(points.len)

    more = (subGlyphFlags and 0x0020) != 0

    var
      xx = int32(0x10000)
      xy = int32(0)
      yy = int32(0x10000)
      yx = int32(0)
      arg1 = int32(0)
      arg2 = int32(0)

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
      x = int32(0)
      y = int32(0)

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

    if x != 0 or y != 0:
      for idx in baseLen ..< uint32(points.len):
        let p = points[idx].addr
        p.x = p.x + x
        p.y = p.y + y

proc loadGlyphAux(loader: var GlyphLoader, font: TrueType, glyphId: GlyphId,
    points: var seq[GlyphPoint]): bool =
  let
    zone = zoneBegin("truetype.loadGlyphAux")
  defer: zone.zoneEnd()

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

proc mapPoint(matrix: Mat2d, x, y: float32): Vec2 {.inline.} =
  [
    matrix.xx * x + matrix.xy * y,
    matrix.yx * x + matrix.yy * y,
  ]

proc toPath(points: openArray[GlyphPoint], matrix: Mat2d): Path =
  var
    pointIdx = int32(0)

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

    result.moveTo(mapPoint(matrix, sx, sy))

    while pointIdx < limit:
      inc pointIdx, 1

      if (points[pointIdx].flags and 0x01) != 0:
        result.lineTo(mapPoint(matrix, float32(points[pointIdx].x),
            float32(points[pointIdx].y)))
      else:
        var
          cx = float32(points[pointIdx].x)
          cy = float32(points[pointIdx].y)

        while true:
          if pointIdx < limit:
            inc pointIdx, 1

            if (points[pointIdx].flags and 0x01) != 0:
              result.quadCurveTo(mapPoint(matrix, cx, cy),
                  mapPoint(matrix, float32(points[pointIdx].x),
                  float32(points[pointIdx].y)))
            else:
              let
                mx = float32(int32(cx + float32(points[pointIdx].x)) div 2)
                my = float32(int32(cy + float32(points[pointIdx].y)) div 2)
              result.quadCurveTo(mapPoint(matrix, cx, cy),
                  mapPoint(matrix, mx, my))

              cx = float32(points[pointIdx].x)
              cy = float32(points[pointIdx].y)
              continue
          else:
            result.quadCurveTo(mapPoint(matrix, cx, cy),
                mapPoint(matrix, sx, sy))
            closed = true
          break

    if not closed:
      result.lineTo(mapPoint(matrix, sx, sy))

    pointIdx = pointEndIdx + 1

proc getGlyphPath*(font: TrueType, glyphId: GlyphId,
    matrix: Mat2d = mat2d()): Path {.inline.} =
  let
    zone = zoneBegin("truetype.getGlyphPath")
  defer: zone.zoneEnd()

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

    result = points.toPath(matrix)

proc getCoverageIndex(
    font: TrueType, coverageTable: uint32, glyphId: GlyphId
): uint32 =
  let
    zone = zoneBegin("truetype.getCoverageIndex")
  defer: zone.zoneEnd()

  let coverageFormat = font.data.toInt(coverageTable, 2, uint32)

  if coverageFormat == 1:
    let glyphCount = font.data.toInt(coverageTable + 2, 2, uint32)

    if glyphCount >= 1:
      var
        l = uint32(0)
        r = glyphCount - 1
        mid = uint32(0)

      while l <= r:
        mid = (l + r) shr 1

        let
          glyphArray = coverageTable + 4
          glyphId2 = font.data.toInt(glyphArray + 2 * mid, 2, uint32)

        if glyphId.id < glyphId2:
          r = mid - 1
        elif glyphId.id > glyphId2:
          l = mid + 1
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
        mid = uint32(0)

      while l <= r:
        mid = (l + r) shr 1
        let
          rangeRecord = rangeArray + 6 * mid
          glyphIdStart = font.data.toInt(rangeRecord, 2, uint32)
          glyphIdEnd = font.data.toInt(rangeRecord + 2, 2, uint32)
        if glyphId.id < glyphIdStart:
          r = mid - 1
        elif glyphId.id > glyphIdEnd:
          l = mid + 1
        else:
          let startCoverageIndex = font.data.toInt(rangeRecord + 4, 2, uint32)
          result = startCoverageIndex + glyphId.id - glyphIdStart
          return

  high(uint32)

proc getGlyphClass(font: TrueType, classDefTable: uint32,
    glyphId: GlyphId): uint32 =
  let
    zone = zoneBegin("truetype.getGlyphClass")
  defer: zone.zoneEnd()

  let classDefFormat = font.data.toInt(classDefTable, 2, uint32)
  if classDefFormat == 1:
    let
      startGlyphId = font.data.toInt(classDefTable + 2, 2, uint32)
      glyphCount = font.data.toInt(classDefTable + 4, 2, uint32)
      classDef1ValueArray = classDefTable + 6
    if glyphId.id >= startGlyphId and glyphId.id < (startGlyphId + glyphCount):
      result = font.data.toInt(
        classDef1ValueArray + 2 * (glyphId.id - startGlyphId), 2, uint32
      )
      return
  elif classDefFormat == 2:
    let
      classRangeCount = font.data.toInt(classDefTable + 2, 2, uint32)
      classRangeRecords = classDefTable + 4

    if classRangeCount >= 1:
      var
        l = uint32(0)
        r = classRangeCount - 1
        mid = uint32(0)

      while l <= r:
        mid = (l + r) shr 1
        let
          classRangeRecord = classRangeRecords + 6 * mid
          glyphIdStart = font.data.toInt(classRangeRecord, 2, uint32)
          glyphIdEnd = font.data.toInt(classRangeRecord + 2, 2, uint32)

        if glyphId.id < glyphIdStart:
          r = mid - 1
        elif glyphId.id > glyphIdEnd:
          l = mid + 1
        else:
          result = font.data.toInt(classRangeRecord + 4, 2, uint32)
          return

  high(uint32)

proc getGlyphGposInfoAdvance(font: TrueType, glyphId1,
    glyphId2: GlyphId): uint32 =
  let
    zone = zoneBegin("truetype.getGlyphGposInfoAdvance")
  defer: zone.zoneEnd()

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
            l = uint32(0)
            r = pairValueCount - 1
            mid = uint32(0)

          while l <= r:
            mid = (l + r) shr 1

            let
              val = pairValueArray + (2 + valueRecordPairSizeInBytes) * mid
              glyphId3 = font.data.toInt(val, 2, uint32)

            if glyphId2.id < glyphId3:
              r = mid - 1
            elif glyphId2.id > glyphId3:
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
    zone = zoneBegin("truetype.getGlyphKernInfoAdvance")
  defer: zone.zoneEnd()

  let
    n = font.data.toInt(font.kern + 2, 2, uint32)
    coverage = font.data.toInt(font.kern + 8, 2, uint32)

  if n < 1 or coverage != 1:
    return

  var
    l = uint32(0)
    r = font.data.toInt(font.kern + 10, 2, uint32) - 1
    mid = uint32(0)
    v1 = (glyphId1.id shl 16) or (glyphId2.id)

  while l <= r:
    mid = (l + r) shr 1
    let v2 = font.data.toInt(font.kern + 18 + (mid * 6), 4, uint32)
    if v1 < v2:
      r = mid - 1
    elif v1 > v2:
      l = mid + 1
    else:
      result = font.data.toInt(font.kern + 22 + (mid * 6), 2, uint32)
      return

proc getGlyphKernAdvance*(font: TrueType, glyphId1,
    glyphId2: GlyphId): uint32 =
  let
    zone = zoneBegin("truetype.getGlyphKernAdvance")
  defer: zone.zoneEnd()

  if font.gpos > 0:
    result = font.getGlyphGposInfoAdvance(glyphId1, glyphId2)
    if result != 0:
      return

  if font.kern > 0:
    result = font.getGlyphKernInfoAdvance(glyphId1, glyphId2)

proc getGlyphColrOffset(font: TrueType, glyphId: GlyphId): uint32 =
  let
    zone = zoneBegin("truetype.getGlyphColrOffset")
  defer: zone.zoneEnd()

  let
    numBaseGlyphRecords = font.data.toInt(font.colr + 2, 2, uint32)
    baseGlyphRecordsOffset = font.colr + font.data.toInt(font.colr + 4, 4, uint32)

  if numBaseGlyphRecords <= 0:
    return

  var
    l = uint32(0)
    r = numBaseGlyphRecords

  while l < r:
    let
      mid = (l + r) div 2
      baseGlyphRecord = baseGlyphRecordsOffset + 6 * mid
      glyphId2 = font.data.toInt(baseGlyphRecord, 2, uint32)

    if glyphId.id < glyphId2:
      r = mid
    elif glyphId.id > glyphId2:
      l = mid + 1
    else:
      result = baseGlyphRecord
      return

proc getPaletteColor*(font: TrueType, paletteIndex: int32,
    paletteEntryIndex: uint16): Color =
  let
    numPaletteEntries = font.data.toInt(font.cpal + 2, 2, uint32)
    numPalettes = font.data.toInt(font.cpal + 4, 2, uint32)
    numColorRecords = font.data.toInt(font.cpal + 6, 2, uint32)
    colorRecordsArrayOffset = font.cpal + font.data.toInt(font.cpal + 8, 4, uint32)

  if uint32(paletteIndex) >= numPalettes or uint32(paletteEntryIndex) >= numPaletteEntries:
    return

  let
    colorRecordIndicesOffset = font.cpal + 12
    baseIndex = font.data.toInt(colorRecordIndicesOffset + 2 * uint32(
        paletteIndex), 2, uint32)
    colorRecordIndex = baseIndex + uint32(paletteEntryIndex)

  if colorRecordIndex >= numColorRecords:
    return

  let
    hexColor = font.data.toInt(colorRecordsArrayOffset + 4 * colorRecordIndex,
        4, uint32)
  result.a = uint8((hexColor shr 0) and 0xFF)
  result.r = uint8((hexColor shr 8) and 0xFF)
  result.g = uint8((hexColor shr 16) and 0xFF)
  result.b = uint8((hexColor shr 24) and 0xFF)

iterator getGlyphLayers*(font: TrueType, glyphId: GlyphId): GlyphLayer =
  let
    zone = zoneBegin("truetype.getGlyphLayers")
  defer: zone.zoneEnd()

  let glyphBasGlyphRecord = font.getGlyphColrOffset(glyphId)
  if glyphBasGlyphRecord > 0:
    let
      firstLayerIndex = font.data.toInt(glyphBasGlyphRecord + 2, 2, uint32)
      numLayers = font.data.toInt(glyphBasGlyphRecord + 4, 2, uint32)
      layerRecordsOffset = font.data.toInt(font.colr + 8, 4, uint32)

    if numLayers >= 1:
      let
        glyphLayerRecordStart = font.colr + layerRecordsOffset + 4 * firstLayerIndex

      for idx in 0 ..< numLayers:
        let
          base = glyphLayerRecordStart + idx * 4
          subGlyphId = font.data.toInt(base, 2, uint32)
          slotIndex = font.data.toInt(base + 2, 2, uint16)

        var
          layer = default(GlyphLayer)
        layer.glyphId = GlyphId(id: subGlyphId)
        layer.paletteEntryIndex = slotIndex
        yield layer

proc getGlyphColrPaintOffset(font: TrueType, glyphId: GlyphId): uint32 =
  let
    zone = zoneBegin("truetype.getGlyphColrPaintOffset")
  defer: zone.zoneEnd()

  let
    version = font.data.toInt(font.colr, 2, uint32)
  if version < 1:
    return

  let baseGlyphListOffset = font.data.toInt(font.colr + 14, 4, uint32)
  if baseGlyphListOffset == 0:
    return

  let
    listAddr = font.colr + baseGlyphListOffset
    count = font.data.toInt(listAddr, 4, uint32)

  var
    l = uint32(0)
    r = count

  while l < r:
    let
      mid = (l + r) div 2
      p = listAddr + 4 + mid * 6
      gid = font.data.toInt(p, 2, uint32)

    if gid < glyphId.id:
      l = mid + 1
    elif gid > glyphId.id:
      r = mid
    else:
      result = listAddr + font.data.toInt(p + 2, 4, uint32)
      return

proc hasColor*(font: TrueType, glyphId: GlyphId): bool =
  if font.colr > 0 and font.cpal > 0:
    result = font.getGlyphColrOffset(glyphId) > 0 or
        font.getGlyphColrPaintOffset(glyphId) > 0

const MAX_PAINT_DEPTH = int32(24)

proc parsePaintTree(font: TrueType,
                    outGlyphs: var seq[ColrGlyph],
                    paletteEntryIndex: var uint16,
                    paintAlpha: var float32,
                    paintTransform: var Mat2d,
                    paintOffset: uint32,
                    depth: int32) =
  let
    zone = zoneBegin("truetype.parsePaintTree")
  defer: zone.zoneEnd()

  if paintOffset == 0 or depth > MAX_PAINT_DEPTH:
    return

  let format = font.data.toInt(paintOffset, 1, uint8)

  template withTransform(tr: Mat2d, body: untyped) =
    block:
      let saveTransform = paintTransform
      paintTransform.multiply(tr)
      defer:
        paintTransform = saveTransform
      body

  case format
  of 1: # PaintColrLayers
    let
      numLayers = font.data.toInt(paintOffset + 1, 1, uint32)
      firstLayerIndex = font.data.toInt(paintOffset + 2, 4, uint32)
      layerListOffset = font.data.toInt(font.colr + 18, 4, uint32)

    if layerListOffset != 0:
      let
        layerListAddr = font.colr + layerListOffset
        layerCount = font.data.toInt(layerListAddr, 4, uint32)

      for idx in 0 ..< numLayers:
        let layerIndex = firstLayerIndex + idx
        if layerIndex < layerCount:
          let rel = font.data.toInt(layerListAddr + 4 + 4 * layerIndex, 4,
              uint32)
          font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
              paintTransform, layerListAddr + rel, depth + 1)

  of 2, 3: # PaintSolid / PaintVarSolid
    paletteEntryIndex = font.data.toInt(paintOffset + 1, 2, uint16)
    paintAlpha = float32(font.data.toInt(paintOffset + 3, 2, int16)) / 16384

  of 4, 5, 6, 7, 8, 9: # gradients: approximate with the first color stop
    let colorLineRel = font.data.toInt(paintOffset + 1, 3, uint32)
    if colorLineRel != 0:
      let
        colorLineAddr = paintOffset + colorLineRel
        numStops = font.data.toInt(colorLineAddr + 1, 2, uint32)
      if numStops > 0:
        paletteEntryIndex = font.data.toInt(colorLineAddr + 5, 2, uint16)
        paintAlpha = float32(font.data.toInt(colorLineAddr + 7, 2,
            int16)) / 16384

  of 10: # PaintGlyph
    let
      childRel = font.data.toInt(paintOffset + 1, 3, uint32)
      subGlyphId = font.data.toInt(paintOffset + 4, 2, uint32)
      saveSlot = paletteEntryIndex
      saveAlpha = paintAlpha

    if childRel != 0:
      font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
          paintTransform, paintOffset + childRel, depth + 1)

    var glyph = default(ColrGlyph)
    glyph.glyphId = GlyphId(id: subGlyphId)
    glyph.paintTransform = paintTransform
    glyph.paletteEntryIndex = paletteEntryIndex
    glyph.alpha = paintAlpha
    outGlyphs.add(glyph)

    paletteEntryIndex = saveSlot
    paintAlpha = saveAlpha

  of 11: # PaintColrGlyph
    let baseGlyphId = font.data.toInt(paintOffset + 1, 2, uint32)
    font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
        paintTransform, font.getGlyphColrPaintOffset(GlyphId(id: baseGlyphId)),
        depth + 1)

  of 12, 13: # PaintTransform
    let childRel = font.data.toInt(paintOffset + 1, 3, uint32)
    if childRel != 0:
      let transformRel = font.data.toInt(paintOffset + 4, 3, uint32)
      if transformRel != 0:
        # Affine2x3 subtable: Fixed xx, yx, xy, yy, dx, dy
        let t = paintOffset + transformRel
        let tr = mat2d(
          float32(font.data.toInt(t + 0, 4, int32)) / 65536,
          float32(font.data.toInt(t + 4, 4, int32)) / 65536,
          float32(font.data.toInt(t + 8, 4, int32)) / 65536,
          float32(font.data.toInt(t + 12, 4, int32)) / 65536,
          float32(font.data.toInt(t + 16, 4, int32)) / 65536,
          float32(font.data.toInt(t + 20, 4, int32)) / 65536
        )
        withTransform(tr):
          font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
              paintTransform, paintOffset + childRel, depth + 1)
      else:
        font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
            paintTransform, paintOffset + childRel, depth + 1)

  of 14, 15: # PaintTranslate
    let
      childRel = font.data.toInt(paintOffset + 1, 3, uint32)
      tr = mat2d(1, 0, 0, 1,
          float32(font.data.toInt(paintOffset + 4, 2, int16)),
          float32(font.data.toInt(paintOffset + 6, 2, int16)))
    if childRel != 0:
      withTransform(tr):
        font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
            paintTransform, paintOffset + childRel, depth + 1)

  of 16, 17, 18, 19, 20, 21, 22, 23: # PaintScale family (F2Dot14 + FWORD center)
    var
      sx = float32(1)
      sy = float32(1)
      cx = float32(0)
      cy = float32(0)

    case format
    of 16, 17: # PaintScale
      sx = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384
      sy = float32(font.data.toInt(paintOffset + 6, 2, int16)) / 16384
    of 18, 19: # PaintScaleAroundCenter
      sx = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384
      sy = float32(font.data.toInt(paintOffset + 6, 2, int16)) / 16384
      cx = float32(font.data.toInt(paintOffset + 8, 2, int16))
      cy = float32(font.data.toInt(paintOffset + 10, 2, int16))
    of 20, 21: # PaintScaleUniform
      sx = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384
      sy = sx
    else: # 22, 23 PaintScaleUniformAroundCenter
      sx = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384
      sy = sx
      cx = float32(font.data.toInt(paintOffset + 6, 2, int16))
      cy = float32(font.data.toInt(paintOffset + 8, 2, int16))

    let
      childRel = font.data.toInt(paintOffset + 1, 3, uint32)
      tr = mat2d(sx, 0, 0, sy, cx * (1 - sx), cy * (1 - sy))
    if childRel != 0:
      withTransform(tr):
        font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
            paintTransform, paintOffset + childRel, depth + 1)

  of 24, 25, 26, 27: # PaintRotate / PaintRotateAroundCenter
    let rad = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384 *
        float32(Pi)

    var
      cx = float32(0)
      cy = float32(0)
    if format >= 26:
      cx = float32(font.data.toInt(paintOffset + 6, 2, int16))
      cy = float32(font.data.toInt(paintOffset + 8, 2, int16))

    let
      c = cos(rad)
      s = sin(rad)
      childRel = font.data.toInt(paintOffset + 1, 3, uint32)
      tr = mat2d(c, s, -s, c,
          cx - c * cx + s * cy,
          cy - s * cx - c * cy)
    if childRel != 0:
      withTransform(tr):
        font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
            paintTransform, paintOffset + childRel, depth + 1)

  of 28, 29, 30, 31: # PaintSkew / PaintSkewAroundCenter
    let
      xRad = float32(font.data.toInt(paintOffset + 4, 2, int16)) / 16384 *
          float32(Pi)
      yRad = float32(font.data.toInt(paintOffset + 6, 2, int16)) / 16384 *
          float32(Pi)

    var
      cx = float32(0)
      cy = float32(0)
    if format >= 30:
      cx = float32(font.data.toInt(paintOffset + 8, 2, int16))
      cy = float32(font.data.toInt(paintOffset + 10, 2, int16))

    let
      tanX = tan(xRad)
      tanY = tan(yRad)
      childRel = font.data.toInt(paintOffset + 1, 3, uint32)
      # spec matrix: b = tan(ySkewAngle), c = -tan(xSkewAngle)
      tr = mat2d(1, tanY, -tanX, 1, tanX * cy, -tanY * cx)
    if childRel != 0:
      withTransform(tr):
        font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
            paintTransform, paintOffset + childRel, depth + 1)

  of 32: # PaintComposite
    let
      backdropRel = font.data.toInt(paintOffset + 5, 3, uint32)
      sourceRel = font.data.toInt(paintOffset + 1, 3, uint32)
    if backdropRel != 0:
      font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
          paintTransform, paintOffset + backdropRel, depth + 1)
    if sourceRel != 0:
      font.parsePaintTree(outGlyphs, paletteEntryIndex, paintAlpha,
          paintTransform, paintOffset + sourceRel, depth + 1)

  else:
    discard

iterator getColrGlyphs*(font: TrueType, glyphId: GlyphId): ColrGlyph =
  block body:
    let paintOffset = font.getGlyphColrPaintOffset(glyphId)
    if paintOffset != 0:
      var
        paletteEntryIndex = uint16(0xFFFF)
        paintAlpha = float32(1)
        paintTransform = mat2d()
        glyphs: seq[ColrGlyph]

      font.parsePaintTree(glyphs, paletteEntryIndex, paintAlpha,
          paintTransform, paintOffset, int32(0))

      if glyphs.len > 0:
        for glyph in glyphs:
          yield glyph

        break body

    for layer in font.getGlyphLayers(glyphId):
      var glyph = default(ColrGlyph)
      glyph.glyphId = layer.glyphId
      glyph.paintTransform = mat2d()
      glyph.paletteEntryIndex = layer.paletteEntryIndex
      glyph.alpha = float32(1)
      yield glyph
