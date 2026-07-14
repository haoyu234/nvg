import std/algorithm
import std/math

import ./core
import ./math
import ./stack_array
import ./tracy

const
  NVG_SLUG_TEXTURE_WIDTH* = int32(4096)
  NVG_SLUG_TEXTURE_HEIGHT* = int32(512)

type
  QuadCurve* = object
    p1*: Vec2
    p2*: Vec2
    p3*: Vec2

  BandsEntry* = object
    curveIndex*: int32
    sortKey*: float32

  Bands* = object
    bands*: seq[BandsEntry]

  ContourRange* = object
    start*: int32
    count*: int32

  GlyphBuild* = object
    curves*: seq[QuadCurve]
    contours*: seq[ContourRange]
    horizontalBands*: seq[Bands]
    verticalBands*: seq[Bands]
    rawBBox*: Bounds
    advance*: float32
    lsb*: float32
    glyphLoc*: array[2, int32]

  SlugGlyphBaked* = object
    curveBlock*: seq[float32]
    bandBlock*: seq[uint32]
    bandHeaderSize*: int32
    curveSize*: int32
    bandSize*: int32

proc lineToQuadratic(p1, p2: Vec2): QuadCurve =
  let mid = (p1 + p2) / 2.0
  result.p1 = p1
  result.p2 = mid
  result.p3 = p2

proc getCurves(points: openArray[PathEntry], bounds: Bounds):
    (seq[QuadCurve], seq[ContourRange]) =
  let
    xMin = bounds.xMin.float32
    yMin = bounds.yMin.float32
    inverseWidth = 1.0f / max(bounds.xMax - bounds.xMin, float32(1.0))
    inverseHeight = 1.0f / max(bounds.yMax - bounds.yMin, float32(1.0))

  template normalizePoint(p: Vec2): Vec2 =
    vec2((p[0] - xMin) * inverseWidth, (p[1] - yMin) * inverseHeight)

  var
    curves = default(StackArray[256, QuadCurve])
    contours = default(StackArray[256, ContourRange])

  var
    current = default(Vec2)
    start = default(Vec2)
    inContour = false
    contourStart: int32 = 0

  for cmd in points:
    case cmd.command
    of Command.MOVE:
      if inContour:
        let curveCount = int32(curves.len) - contourStart
        if curveCount > 0:
          contours.add(ContourRange(start: int32(contourStart),
              count: curveCount))
      current = normalizePoint(cmd.p1)
      start = current
      contourStart = int32(curves.len)
      inContour = true

    of Command.LINE:
      curves.add(lineToQuadratic(current, normalizePoint(cmd.p1)))
      current = normalizePoint(cmd.p1)

    of Command.CURVE:
      curves.add(QuadCurve(
        p1: current,
        p2: normalizePoint(cmd.p1),
        p3: normalizePoint(cmd.p2),
      ))

      current = normalizePoint(cmd.p2)

    of Command.BEZIER:
      let
        startPoint = current
        controlPoint1 = normalizePoint(cmd.p1)
        controlPoint2 = normalizePoint(cmd.p2)
        endPoint = normalizePoint(cmd.p3)
        splitFraction = 1.0 / 3.0

      let
        firstLevel1 = startPoint + (controlPoint1 - startPoint) * splitFraction
        firstLevel2 = controlPoint1 + (controlPoint2 - controlPoint1) * splitFraction
        firstLevel3 = controlPoint2 + (endPoint - controlPoint2) * splitFraction
        secondLevel1 = firstLevel1 + (firstLevel2 - firstLevel1) * splitFraction
        secondLevel2 = firstLevel2 + (firstLevel3 - firstLevel2) * splitFraction
        splitPoint1 = secondLevel1 + (secondLevel2 - secondLevel1) * splitFraction
        firstQuadControl = (firstLevel1 + secondLevel1) * 0.5

      let
        midLevel1 = splitPoint1 + (secondLevel2 - splitPoint1) * 0.5
        midLevel2 = secondLevel2 + (firstLevel3 - secondLevel2) * 0.5
        midLevel3 = firstLevel3 + (endPoint - firstLevel3) * 0.5
        midLevel4 = midLevel1 + (midLevel2 - midLevel1) * 0.5
        midLevel5 = midLevel2 + (midLevel3 - midLevel2) * 0.5
        splitPoint2 = midLevel4 + (midLevel5 - midLevel4) * 0.5
        secondQuadControl = (midLevel1 + midLevel4) * 0.5
        thirdQuadControl = (midLevel2 + midLevel5) * 0.5

      curves.add(QuadCurve(p1: startPoint, p2: firstQuadControl, p3: splitPoint1))
      curves.add(QuadCurve(p1: splitPoint1, p2: secondQuadControl, p3: splitPoint2))
      curves.add(QuadCurve(p1: splitPoint2, p2: thirdQuadControl, p3: endPoint))
      current = endPoint

    of Command.CLOSE:
      curves.add(lineToQuadratic(current, start))
      current = start

  if inContour:
    let curveCount = int32(curves.len) - contourStart
    if curveCount > 0:
      contours.add(ContourRange(start: int32(contourStart), count: curveCount))

  result = (curves.toSeq(), contours.toSeq())

proc compareBandsEntry(a, b: BandsEntry): int =
  if a.sortKey > b.sortKey:
    -1
  elif a.sortKey < b.sortKey:
    1
  else:
    0

proc buildBands*(curves: openArray[QuadCurve], bandCount: int32 = 0):
    tuple[horizontalBands: seq[Bands], verticalBands: seq[Bands]] =
  let
    numBands = if bandCount > 0: bandCount
               else: clamp(int32(curves.len), 1, 16)

  var
    horizontalBands = newSeq[Bands](numBands)
    verticalBands = newSeq[Bands](numBands)

  let
    bandHeight = 1.0f / float32(numBands)
    bandWidth = 1.0f / float32(numBands)
    horizontalPad = bandHeight * float32(0.5)
    verticalPad = bandWidth * float32(0.5)

  for curveIndex in 0 ..< int32(curves.len):
    let
      curve = curves[curveIndex]
      curveYMin = min(min(curve.p1[1], curve.p2[1]), curve.p3[1])
      curveYMax = max(max(curve.p1[1], curve.p2[1]), curve.p3[1])
      curveXMin = min(min(curve.p1[0], curve.p2[0]), curve.p3[0])
      curveXMax = max(max(curve.p1[0], curve.p2[0]), curve.p3[0])

    let
      bandFirst = clamp(int32(floor((curveYMin - horizontalPad) / bandHeight)),
          int32(0), numBands - 1)
      bandLast = clamp(int32(floor((curveYMax + horizontalPad) / bandHeight)),
          int32(0), numBands - 1)

    for bandIndex in bandFirst .. bandLast:
      horizontalBands[bandIndex].bands.add(BandsEntry(curveIndex: curveIndex,
          sortKey: curveXMax))

    let
      verticalBandFirst = clamp(int32(floor((curveXMin - verticalPad) / bandWidth)),
          int32(0), numBands - 1)
      verticalBandLast = clamp(int32(floor((curveXMax + verticalPad) / bandWidth)),
          int32(0), numBands - 1)

    for bandIndex in verticalBandFirst .. verticalBandLast:
      verticalBands[bandIndex].bands.add(BandsEntry(curveIndex: curveIndex,
          sortKey: curveYMax))

  for band in horizontalBands.mitems:
    sort(band.bands, compareBandsEntry)

  for band in verticalBands.mitems:
    sort(band.bands, compareBandsEntry)

  result = (
    horizontalBands: horizontalBands,
    verticalBands: verticalBands,
  )

proc buildGlyph*(path: openArray[PathEntry], bounds: Bounds,
    advance: float32 = float32(0.0), lsb: float32 = float32(0.0)):
    GlyphBuild =
  let
    (curves, contours) = getCurves(path, bounds)
  let
    bands = buildBands(curves)
  result.curves = curves
  result.contours = contours
  result.horizontalBands = bands.horizontalBands
  result.verticalBands = bands.verticalBands
  result.rawBBox = bounds
  result.advance = advance
  result.lsb = lsb

proc writeBandSet(bands: openArray[Bands],
    bandPixels: var seq[uint32], glyphStart, headerOffset: int32,
    curveTexelOf: openArray[int32], outlineCurveStart: int32,
    writeOffset: var int32) =
  let
    zone = zoneBegin("slug.writeBandSet")
  defer: zone.zoneEnd()

  var dataOffset = writeOffset
  for i in 0 ..< bands.len:
    let dataIndex = (glyphStart + headerOffset + int32(i)) * 4
    bandPixels[dataIndex + 0] = uint32(bands[i].bands.len)
    bandPixels[dataIndex + 1] = uint32(dataOffset)
    dataOffset += int32(bands[i].bands.len)
  for band in bands:
    for item in band.bands:
      let
        curveTexel = outlineCurveStart + curveTexelOf[item.curveIndex]
        curveTexelX = curveTexel mod NVG_SLUG_TEXTURE_WIDTH
        curveTexelY = curveTexel div NVG_SLUG_TEXTURE_WIDTH
        dataIndex = (glyphStart + writeOffset) * 4
      bandPixels[dataIndex + 0] = uint32(curveTexelX)
      bandPixels[dataIndex + 1] = uint32(curveTexelY)
      inc writeOffset

proc bakeGlyph*(glyph: GlyphBuild): SlugGlyphBaked =
  let
    zone = zoneBegin("slug.bakeGlyph")
  defer: zone.zoneEnd()

  var
    curveTexelSize = int32(0)
    curveTextureHeight = int32(0)
    curvePixels: seq[float32]
    bandPixels: seq[uint32]
    curveTexelOf: seq[int32]

  let
    numCurves = int32(glyph.curves.len)
    numContours = int32(glyph.contours.len)
    estimatedCurveSize = numCurves + numContours

  curveTexelSize += estimatedCurveSize

  let firstCurveHeight = int32(max(1, (curveTexelSize +
      NVG_SLUG_TEXTURE_WIDTH - 1) div NVG_SLUG_TEXTURE_WIDTH))
  if firstCurveHeight > curveTextureHeight:
    curveTextureHeight = firstCurveHeight
    curvePixels.setLen(NVG_SLUG_TEXTURE_WIDTH * curveTextureHeight * 4)

  curveTexelOf.setLen(numCurves)
  var
    pixelIndex = int32(0)

  for contour in glyph.contours:
    for k in 0 ..< contour.count:
      let
        curveIndex = contour.start + k
      curveTexelOf[curveIndex] = pixelIndex

      let
        texelIndex = pixelIndex
        texelColumn = texelIndex mod NVG_SLUG_TEXTURE_WIDTH
        texelRow = texelIndex div NVG_SLUG_TEXTURE_WIDTH
        byteOffset = (texelRow * NVG_SLUG_TEXTURE_WIDTH + texelColumn) * 4

      curvePixels[byteOffset + 0] = glyph.curves[curveIndex].p1[0]
      curvePixels[byteOffset + 1] = glyph.curves[curveIndex].p1[1]
      curvePixels[byteOffset + 2] = glyph.curves[curveIndex].p2[0]
      curvePixels[byteOffset + 3] = glyph.curves[curveIndex].p2[1]

      inc pixelIndex

    if contour.count > 0:
      let
        lastCurveIndex = contour.start + contour.count - 1
        endTexelIndex = pixelIndex
        endColumn = endTexelIndex mod NVG_SLUG_TEXTURE_WIDTH
        endRow = endTexelIndex div NVG_SLUG_TEXTURE_WIDTH
        byteOffset = (endRow * NVG_SLUG_TEXTURE_WIDTH + endColumn) * 4

      curvePixels[byteOffset + 0] = glyph.curves[lastCurveIndex].p3[0]
      curvePixels[byteOffset + 1] = glyph.curves[lastCurveIndex].p3[1]
      curvePixels[byteOffset + 2] = 0.0f
      curvePixels[byteOffset + 3] = 0.0f

      inc pixelIndex

  var
    bandTexelSize = int32(0)
    bandTextureHeight = int32(0)

  let
    headerSize = int32(glyph.horizontalBands.len) + int32(glyph.verticalBands.len)

  bandTexelSize += headerSize

  for band in glyph.horizontalBands:
    bandTexelSize += int32(band.bands.len)

  for band in glyph.verticalBands:
    bandTexelSize += int32(band.bands.len)

  let firstBandHeight = int32(max(1, (bandTexelSize +
      NVG_SLUG_TEXTURE_WIDTH - 1) div NVG_SLUG_TEXTURE_WIDTH))
  if firstBandHeight > bandTextureHeight:
    bandTextureHeight = firstBandHeight
    bandPixels.setLen(NVG_SLUG_TEXTURE_WIDTH * bandTextureHeight * 4)

  let
    numHorizontalBands = int32(glyph.horizontalBands.len)

  var writeOffset = headerSize
  writeBandSet(glyph.horizontalBands, bandPixels, 0, 0,
      curveTexelOf, 0, writeOffset)
  writeBandSet(glyph.verticalBands, bandPixels, 0, numHorizontalBands,
      curveTexelOf, 0, writeOffset)

  let
    curveSize = curveTexelSize
    bandSize = bandTexelSize
    curveElemCount = curveSize * int32(4)
    bandElemCount = bandSize * int32(4)

  SlugGlyphBaked(
    curveBlock: curvePixels[0 ..< curveElemCount],
    bandBlock: bandPixels[0 ..< bandElemCount],
    bandHeaderSize: headerSize,
    curveSize: curveSize,
    bandSize: bandSize,
  )
