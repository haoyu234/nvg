import ./core
import ./math
import ./pieces

import std/math
import std/endians
import std/hashes

type
  GlyphId* = distinct uint32

  GlyphShapeCommand* = enum
    MOVE = 1
    LINE
    BEZIER
    CLOSE

  GlyphBox* = object
    x1*, y1*: int32
    x2*, y2*: int32

  GlyphVertex* = object
    x*, y*, cx*, cy*: int16
    command*: GlyphShapeCommand

  FontMetrics* = object
    ascender*: int32
    descender*: int32
    lineGap*: int32

  GlyphSDF* = object
    w*, h*: int32
    data*: seq[byte]

  GlyphLayer* = object
    glyphId*: GlyphId
    paletteIdx*: uint32

  OpenTypeObj* = object
    data: Piece[byte]
    fontStart: uint32
    numGlyphs: uint32
    colr, cpal, glyf, gpos, head, hhea, hmtx, kern, loca: uint32
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
  TAG_HMTX = calcTag(['h', 'm', 't', 'x'])
  TAG_KERN = calcTag(['k', 'e', 'r', 'n'])
  TAG_GPOS = calcTag(['g', 'p', 'o', 's'])
  TAG_MAXP = calcTag(['m', 'a', 'x', 'p'])

proc toInt[T: SomeInteger, O: Natural](
    s: Piece[byte], offset: O, SIZE: static[Natural], _: typedesc[T]
): T {.inline, raises: [].} =
  assert sizeof(T) >= int(SIZE)
  assert s.len >= int(offset) + int(SIZE)

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
      bigEndian64(data.addr, s[int(offset)].addr)
      T(data)
    elif SIZE == 4:
      bigEndian32(data.addr, s[int(offset)].addr)
      T(data)
    elif SIZE == 2:
      bigEndian16(data.addr, s[int(offset)].addr)
      T(data)
  else:
    T(RESULT_TYPE()(s[int(offset)]))

proc getTable(data: Piece[byte], fontStart: uint32, targetTag: uint32): uint32 =
  let
    numTabs = data.toInt(fontStart + 4, 2, uint32)
    dir = fontStart + 12

  for idx in 0 ..< numTabs:
    let loc = dir + 16 * idx

    if targetTag != data.toInt(loc, 4, uint32):
      continue

    result = data.toInt(loc + 8, 4, uint32)
    return

proc parseOpenType*(data: openArray[byte], fontStart: uint32): OpenTypeObj =
  let
    data = piece(cast[ptr UncheckedArray[byte]](data[0].addr), data.len)
    cmap = getTable(data, fontStart, TAG_CMAP)
    colr = getTable(data, fontStart, TAG_COLR)
    cpal = getTable(data, fontStart, TAG_CPAL)
    glyf = getTable(data, fontStart, TAG_GLYF)
    head = getTable(data, fontStart, TAG_HEAD)
    hhea = getTable(data, fontStart, TAG_HHEA)
    hmtx = getTable(data, fontStart, TAG_HMTX)
    loca = getTable(data, fontStart, TAG_LOCA)

  if cmap <= 0 or glyf <= 0 or head <= 0 or hhea <= 0 or hmtx <= 0 or loca <= 0:
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

  let
    kern = getTable(data, fontStart, TAG_KERN)
    gpos = getTable(data, fontStart, TAG_GPOS)
    maxp = getTable(data, fontStart, TAG_MAXP)
    indexToLocFormat = data.toInt(head + 50, 2, uint32)
    numGlyphs = block:
      if maxp > 0:
        data.toInt(maxp + 4, 2, uint32)
      else:
        0xFFFF

  result.data = data
  result.fontStart = fontStart
  result.numGlyphs = numGlyphs
  result.colr = colr
  result.cpal = cpal
  result.glyf = glyf
  result.gpos = gpos
  result.head = head
  result.hhea = hhea
  result.hmtx = hmtx
  result.kern = kern
  result.loca = loca
  result.indexMap = indexMap
  result.indexToLocFormat = indexToLocFormat

proc getFontMetrics*(font: OpenTypeObj): FontMetrics =
  let
    ascender = font.data.toInt(font.hhea + 4, 2, int32)
    descender = font.data.toInt(font.hhea + 6, 2, int32)
    lineGap = font.data.toInt(font.hhea + 8, 2, int32)

  result.ascender = ascender
  result.descender = descender
  result.lineGap = lineGap

proc getGlyphAdvance*(font: OpenTypeObj, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if uint32(glyphId) < n:
    font.data.toInt(font.hmtx + 4 * uint32(glyphId), 2, int32)
  else:
    font.data.toInt(font.hmtx + 4 * (n - 1), 2, int32)

proc getGlyphLeftSideBearing*(font: OpenTypeObj, glyphId: GlyphId): int32 =
  let n = font.data.toInt(font.hhea + 34, 2, uint32)
  if uint32(glyphId) < n:
    font.data.toInt(font.hmtx + 4 * uint32(glyphId) + 2, 2, int32)
  else:
    font.data.toInt(font.hmtx + 4 * n + 2 * (uint32(glyphId) - n), 2, int32)

proc getGlyphId*(font: OpenTypeObj, unicodeCodepoint: uint32): GlyphId =
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

proc getGlyphGlyfOffset(font: OpenTypeObj, glyphId: GlyphId): uint32 =
  if uint32(glyphId) >= font.numGlyphs or font.indexToLocFormat >= 2:
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
    return

  font.glyf + offset1

proc getGlyphBox*(
    font: OpenTypeObj, glyphId: GlyphId, scaleX, scaleY, shiftX, shiftY: float32
): GlyphBox =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset > 0:
    let
      x1 = font.data.toInt(offset + 2, 2, int32)
      y1 = font.data.toInt(offset + 4, 2, int32)
      x2 = font.data.toInt(offset + 6, 2, int32)
      y2 = font.data.toInt(offset + 8, 2, int32)

    result.x1 = int32(floor(float32(x1) * scaleX + shiftX))
    result.y1 = int32(floor(-float32(y2) * scaleY + shiftY))
    result.x2 = int32(ceil(float32(x2) * scaleX + shiftX))
    result.y2 = int32(ceil(-float32(y1) * scaleY + shiftY))

proc getGlyphShapeAux(font: OpenTypeObj, glyphId: GlyphId, verts: var seq[GlyphVertex]) =
  let offset = font.getGlyphGlyfOffset(glyphId)
  if offset <= 0:
    return

  let count = font.data.toInt(offset, 2, int32)
  if count > 0:
    let
      ins = font.data.toInt(offset + 10 + uint32(count) * 2, 2, uint32)
      n = 1 + font.data.toInt(offset + 10 + uint32(count) * 2 - 2, 2, uint32)

    type
      GlyphPoint = object
        x, y, cx, cy: int16
        flags: uint8

    var
      points = newSeq[GlyphPoint](n)

    block:
      var
        x = default(int32)
        y = default(int32)
        flags = default(uint8)
        repeatCount = default(uint8)
        rpos = offset + 10 + uint32(count) * 2 + 2 + ins

      template next(n, T): auto =
        let data = font.data.toInt(rpos, n, T)
        inc rpos, n
        data

      for idx in 0 ..< n:
        if repeatCount == 0:
          flags = next(1, uint8)
          if (flags and 0x8) != 0:
            repeatCount = next(1, uint8)
        else:
          dec repeatCount, 1

        points[idx].flags = flags

      for idx in 0 ..< n:
        let p = points[idx].addr
        if (p.flags and 0x2) != 0:
          if (p.flags and 0x10) != 0:
            inc x, next(1, uint8)
          else:
            dec x, next(1, uint8)
        else:
          if (p.flags and 0x10) == 0:
            inc x, next(2, int32)

        p[].x = int16(x)

      for idx in 0 ..< n:
        let p = points[idx].addr
        if (p.flags and 0x4) != 0:
          if (p.flags and 0x20) != 0:
            inc y, next(1, uint8)
          else:
            dec y, next(1, uint8)
        else:
          if (p.flags and 0x20) == 0:
            inc y, next(2, int32)

        p[].y = int16(y)

    block:
      var
        beginIdx = default(uint32)
        vert = default(GlyphVertex)

      for idx in 0 ..< uint32(count):
        let
          endIdx = font.data.toInt(offset + 10 + idx * 2, 2, uint32)
          n = endIdx - beginIdx + 1

        var
          cur = points[endIdx].addr
          next = points[beginIdx].addr

        if (cur.flags and 0x1) > 0:
          vert.x = cur.x
          vert.y = cur.y

        elif (next.flags and 0x1) > 0:
          vert.x = next.x
          vert.y = next.y

        else:
          vert.x = (cur.x + next.x) div 2
          vert.y = (cur.y + next.y) div 2

        vert.command = GlyphShapeCommand.MOVE
        vert.cx = 0
        vert.cy = 0
        verts.add(vert)

        for idx in 0 ..< n:
          cur = next
          next = points[beginIdx + (idx + 1) mod n].addr

          if (cur.flags and 0x1) > 0:
            vert.command = GlyphShapeCommand.LINE
            vert.x = cur.x
            vert.y = cur.y
            vert.cx = 0
            vert.cy = 0
          else:
            var
              x = next.x
              y = next.y

            if (next.flags and 0x1) <= 0:
              x = (cur.x + next.x) div 2
              y = (cur.y + next.y) div 2

            vert.command = GlyphShapeCommand.BEZIER
            vert.x = x
            vert.y = y
            vert.cx = cur.x
            vert.cy = cur.y

          verts.add(vert)

        vert.command = GlyphShapeCommand.CLOSE
        vert.x = 0
        vert.y = 0
        vert.cx = 0
        vert.cy = 0

        verts.add(vert)

        beginIdx = endIdx + 1

  elif count < 0:
    var
      more = true
      rpos = offset + 10

    template next(n, T): auto =
      let data = font.data.toInt(rpos, n, T)
      inc rpos, n
      data

    while more:
      let
        flags = next(2, uint32)
        glyphId2 = GlyphId(next(2, uint32))
        oldLen = verts.len

      var transform = mat2d()

      if (flags and 0x2) > 0:
        if (flags and 0x1) > 0:
          transform[4] = float32(next(2, int32))
          transform[5] = float32(next(2, int32))

        else:
          transform[4] = float32(next(1, int32))
          transform[5] = float32(next(1, int32))

      if (flags and 0x8) > 0:
        let v = float32(next(2, int32)) / 16384

        transform[0] = v
        transform[3] = v
        transform[1] = 0
        transform[2] = 0

      elif (flags and 0x40) > 0:
        let
          v1 = float32(next(2, int32)) / 16384
          v2 = float32(next(2, int32)) / 16384

        transform[0] = v1
        transform[1] = 0
        transform[2] = 0
        transform[3] = v2

      elif (flags and 0x80) > 0:
        let
          v1 = float32(next(2, int32)) / 16384
          v2 = float32(next(2, int32)) / 16384
          v3 = float32(next(2, int32)) / 16384
          v4 = float32(next(2, int32)) / 16384

        transform[0] = v1
        transform[1] = v2
        transform[2] = v3
        transform[3] = v4

      font.getGlyphShapeAux(glyphId2, verts)

      for idx in oldLen ..< verts.len:
        let v = verts[idx].addr

        case v.command
        of GlyphShapeCommand.MOVE, GlyphShapeCommand.LINE:
          let
            p = transform * vec2(float32(v.x), float32(v.y))

          v.x = int16(p[0])
          v.y = int16(p[1])

        of GlyphShapeCommand.BEZIER:
          let
            p = transform * vec2(float32(v.x), float32(v.y))
            cp = transform * vec2(float32(v.cx), float32(v.cy))

          v.x = int16(p[0])
          v.y = int16(p[1])
          v.cx = int16(cp[0])
          v.cy = int16(cp[1])

        else:
          discard

      more = (flags and 0x20) != 0

proc getGlyphShape*(font: OpenTypeObj, glyphId: GlyphId): seq[
    GlyphVertex] {.inline.} =
  font.getGlyphShapeAux(glyphId, result)

proc rayBezier(
    orig, ray, q1, q2, q3: array[2, float32], hits: var array[2, array[2, float32]]
): uint32 =
  let
    q1perp = q1[1] * ray[0] - q1[0] * ray[1]
    q2perp = q2[1] * ray[0] - q2[0] * ray[1]
    q3perp = q3[1] * ray[0] - q3[0] * ray[1]
    roperp = orig[1] * ray[0] - orig[0] * ray[1]

    a = q1perp - 2 * q2perp + q3perp
    b = q2perp - q1perp
    c = q1perp - roperp

  var
    n = uint32(0)
    s1 = default(float32)
    s2 = default(float32)

  if a != 0:
    let discriminant = b * b - a * c
    if discriminant > 0:
      let
        rcpna = float32(-1) / a
        d = sqrt(discriminant)

      s1 = (b + d) * rcpna
      s2 = (b - d) * rcpna

      if s1 > 0 and s1 <= 1:
        n = 1

      if d > 0 and s2 > 0 and s2 <= 1:
        if n <= 0:
          s1 = s2

        inc n, 1
  else:
    s1 = c / (-2 * b)
    if s1 > 0 and s1 <= 1:
      n = 1

  if n > 0:
    let
      rcpLen2 = 1 / (ray[0] * ray[0] + ray[1] * ray[1])
      raynX = ray[0] * rcpLen2
      raynY = ray[1] * rcpLen2

      q1d = q1[0] * raynX + q1[1] * raynY
      q2d = q2[0] * raynX + q2[1] * raynY
      q3d = q3[0] * raynX + q3[1] * raynY
      rod = orig[0] * raynX + orig[1] * raynY

      q21d = q2d - q1d
      q31d = q3d - q1d
      q1rd = q1d - rod

    hits[0][0] = q1rd + s1 * (2.0f - 2.0f * s1) * q21d + s1 * s1 * q31d
    hits[0][1] = a * s1 + b
    result = 1

    if n > 1:
      hits[1][0] = q1rd + s2 * (2.0f - 2.0f * s2) * q21d + s2 * s2 * q31d
      hits[1][1] = a * s2 + b
      result = 2

proc computeCrossX(x, y: float32, verts: seq[GlyphVertex]): int32 =
  var y = y

  let frac = y mod 1
  if frac < 0.01f:
    y = y + 0.01
  elif frac > 0.99f:
    y = y - 0.01

  var
    orig = [x, y]
    ray = [float32(1), 0]
    winding = default(int32)
    hints = default(array[2, array[2, float32]])

  for idx in 1 ..< len(verts):
    let
      v1 = verts[idx].addr
      v2 = verts[idx - 1].addr

    template check() =
      let
        x1 = v2.x
        y1 = v2.y
        x2 = v1.x
        y2 = v1.y

      if y > float32(min(y1, y2)) and y < float32(max(y1, y2)) and
          x > float32(min(x1, x2)):
        let inter =
          (y - float32(y1)) / float32(y2 - y1) * float32(x2 - x1) + float32(x1)
        if inter < x:
          if y1 < y2:
            inc winding, 1
          else:
            dec winding, 1

    if v1.command == GlyphShapeCommand.LINE:
      check()
    elif v1.command == GlyphShapeCommand.BEZIER:
      let
        x1 = v2.x
        y1 = v2.y
        x2 = v1.cx
        y2 = v1.cy
        x3 = v1.x
        y3 = v1.y

        ax = min(x1, min(x2, x3))
        ay = min(y1, min(y2, y3))
        by = max(y1, max(y2, y3))

      if y > float32(ay) and y < float32(by) and x > float32(ax):
        let
          q1 = [float32(x1), float32(y1)]
          q2 = [float32(x2), float32(y2)]
          q3 = [float32(x3), float32(y3)]

        if q1 == q2 or q2 == q3:
          check()
        else:
          let n = rayBezier(orig, ray, q1, q2, q3, hints)
          for idx in 0 ..< n:
            if hints[idx][0] < 0:
              if hints[idx][1] < 0:
                dec winding, 1
              else:
                inc winding, 1

  winding

proc solveCubic(a, b, c: float32, res: var array[3, float32]): uint32 =
  let
    s = -a / 3
    p = b - a * a / 3
    q = a * (2 * a * a - 9 * b) / 27 + c
    p3 = p * p * p
    d = q * q + 4 * p3 / 27

  template cubeRoot(v: float32): float32 =
    let sign = float32(sgn(v))
    sign * pow(sign * v, float32(1) / float32(3))

  if d >= 0:
    let
      z = sqrt(d)
      u = cubeRoot((-q + z) / 2)
      v = cubeRoot((-q - z) / 2)

    res[0] = s + u + v
    result = 1
  else:
    let
      u = sqrt(-p / 3)
      v = arccos(-sqrt(-27 / p3) * q / 2) / 3
      m = cos(v)
      n = cos(v - PI / 2) * 1.732050808f

    res[0] = s + u * 2 * m
    res[1] = s - u * (m + n)
    res[2] = s - u * (m - n)
    result = 3

proc getGlyphSDF*(
    font: OpenTypeObj,
    glyphId: GlyphId,
    scale: float32,
    padding: int32,
    edge: byte,
    pixelDistScale: float32,
): GlyphSDF =
  if scale <= 0:
    return

  let glyphBox = font.getGlyphBox(glyphId, scale, scale, 0, 0)
  if glyphBox.x1 == glyphBox.x2 or glyphBox.y1 == glyphBox.y2:
    return

  let
    x1 = glyphBox.x1 - padding
    y1 = glyphBox.y1 - padding
    x2 = glyphBox.x2 + padding
    y2 = glyphBox.y2 + padding

    w = x2 - x1
    h = y2 - y1

  result.w = w
  result.h = h
  result.data.setLen(w * h)

  let
    scaleX = scale
    scaleY = -scale # invert for y-downwards bitmaps

  const
    eps = float32(1) / float32(1024)
    eps2 = eps * eps

  let verts = font.getGlyphShape(glyphId)

  var
    i = default(uint32)
    j = uint32(len(verts) - 1)
    data = newSeq[float32](len(verts))

  while i < uint32(len(verts)):
    let
      v1 = verts[i].addr
      v2 = verts[j].addr

    if v1.command == GlyphShapeCommand.LINE:
      let
        x1 = float32(v1.x) * scaleX
        y1 = float32(v1.y) * scaleY
        x2 = float32(v2.x) * scaleX
        y2 = float32(v2.y) * scaleY

        dx = x2 - x1
        dy = y2 - y1
        dist = sqrt(dx * dx + dy * dy)

      if dist >= eps:
        data[i] = float32(1) / dist

    elif v1.command == GlyphShapeCommand.BEZIER:
      let
        x3 = float32(v2.x) * scaleX
        y3 = float32(v2.y) * scaleY
        x2 = float32(v1.cx) * scaleX
        y2 = float32(v1.cy) * scaleY
        x1 = float32(v1.x) * scaleX
        y1 = float32(v1.y) * scaleY

        bx = x1 - 2 * x2 + x3
        by = y1 - 2 * y2 + y3
        len2 = bx * bx + by * by

      if len2 >= eps2:
        data[i] = float32(1) / len2

    j = i
    inc i, 1

  for y in y1 ..< y2:
    for x in x1 ..< x2:
      var
        sx = float32(x) + 0.5f
        sy = float32(y) + 0.5f

        xSpace = sx / scaleX
        ySpace = sy / scaleY

        minDist = float32(999999)

      let winding = computeCrossX(xSpace, ySpace, verts)

      for idx in 1 ..< len(verts):
        let
          v1 = verts[idx].addr
          v2 = verts[idx - 1].addr

          x1 = float32(v1.x) * scaleX
          y1 = float32(v1.y) * scaleY

        if v1.command == GlyphShapeCommand.LINE and data[idx] != 0:
          let
            x2 = float32(v2.x) * scaleX
            y2 = float32(v2.y) * scaleY

            dx = x2 - x1
            dy = y2 - y1

            px = x1 - sx
            py = y1 - sy
            dist2 = px * px + py * py

          if dist2 < minDist * minDist:
            minDist = sqrt(dist2)

          let dist = abs(dx * py - dy * px) * data[idx]
          if dist < minDist:
            let t = -(px * dx + py * dy) / (dx * dx + dy * dy)
            if t >= 0 and t <= 1:
              minDist = dist
        elif v1.command == GlyphShapeCommand.BEZIER:
          let
            x3 = float32(v2.x) * scaleX
            y3 = float32(v2.y) * scaleY
            x2 = float32(v1.cx) * scaleX
            y2 = float32(v1.cy) * scaleY

          let
            bx1 = min(min(x1, x2), x3)
            by1 = min(min(y1, y2), y3)
            bx2 = max(max(x1, x2), x3)
            by2 = max(max(y1, y2), y3)

          if sx > (bx1 - minDist) and sx < (bx2 + minDist) and sy > (by1 -
              minDist) and sy < (by2 + minDist):
            let
              ax = x2 - x1
              ay = y2 - y1
              bx = x1 - 2 * x2 + x3
              by = y1 - 2 * y2 + y3
              mx = x1 - sx
              my = y1 - sy
              aInv = data[idx]

            var
              n = default(uint32)
              res = default(array[3, float32])

            if aInv == 0:
              let
                a = 3 * (ax * bx + ay * by)
                b = 2 * (ax * ax + ay * ay) + (mx * bx + my * by)
                c = mx * ax + my * ay

              if abs(a) < eps2:
                if abs(b) >= eps2:
                  res[n] = -c / b
                  inc n, 1
              else:
                let discriminant = b * b - 4 * a * c
                if discriminant < 0:
                  n = 0
                else:
                  let root = sqrt(discriminant)
                  res[0] = (-b - root) / (2 * a)
                  res[1] = (-b + root) / (2 * a)
                  n = 2
            else:
              let
                b = 3 * (ax * bx + ay * by) * aInv
                c = (2 * (ax * ax + ay * ay) + (mx * bx + my * by)) * aInv
                d = (mx * ax + my * ay) * aInv

              n = solveCubic(b, c, d, res)

            var dist2 = mx * mx + my * my
            if dist2 < minDist * minDist:
              minDist = sqrt(dist2)

            for idx in 0 ..< n:
              if res[idx] >= 0 and res[idx] <= 1:
                let
                  t = res[idx]
                  it = float32(1) - t
                  px = it * it * x1 + 2 * t * it * x2 + t * t * x3
                  py = it * it * y1 + 2 * t * it * y2 + t * t * y3

                  dx = px - sx
                  dy = py - sy

                dist2 = dx * dx + dy * dy
                if dist2 < minDist * minDist:
                  minDist = sqrt(dist2)

      if winding == 0:
        minDist = -minDist

      let
        v1 = float32(edge) + pixelDistScale * minDist
        v2 = clamp(v1, float32(0), float32(255))
        idx = (y - y1) * w + (x - x1)

      result.data[idx] = byte(v2)

proc getCoverageIndex(
    font: OpenTypeObj, coverageTable: uint32, glyphId: GlyphId
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

proc getGlyphClass(font: OpenTypeObj, classDefTable: uint32,
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

proc getGlyphGposInfoAdvance(font: OpenTypeObj, glyphId1,
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

proc getGlyphKernInfoAdvance(font: OpenTypeObj, glyphId1,
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

proc getGlyphKernAdvance*(font: OpenTypeObj, glyphId1,
    glyphId2: GlyphId): uint32 =
  if font.gpos > 0:
    result = font.getGlyphGposInfoAdvance(glyphId1, glyphId2)
    if result != 0:
      return

  if font.kern > 0:
    result = font.getGlyphKernInfoAdvance(glyphId1, glyphId2)

proc getGlyphColrOffset(font: OpenTypeObj, glyphId: GlyphId): uint32 =
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

proc getPaletteColor*(font: OpenTypeObj, paletteIdx: uint32,
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

proc getGlyphLayers*(font: OpenTypeObj, glyphId: GlyphId): seq[GlyphLayer] =
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

proc hasColor*(font: OpenTypeObj, glyphId: GlyphId): bool =
  if font.colr > 0 and font.cpal > 0:
    result = font.getGlyphColrOffset(glyphId) > 0
