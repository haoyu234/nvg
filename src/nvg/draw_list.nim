import std/math

import ./backend
import ./core
import ./math
import ./pieces
import ./tiles
import ./tracy

const
  NVG_TILE_SIZE = 32

type
  ShaderType* {.size: 4.} = enum
    ShaderSolid = 1
    ShaderGradient
    ShaderImage

  TextureType* = enum
    Plain = 0
    Rgb = 1
    Alpha = 2
    Premultiplied = 3

  Image* = ref object
    imageId*: ImageId
    imageInfo*: ImageInfo
    data*: seq[byte]

  UniformParam* = object
    extent*: Vec2
    paintTransformIndex*: int32

    radius*: float32
    feather*: float32
    renderFlags*: uint32
    pad*: array[8, uint8]

  PathInstanceParam* = object
    fillCount*: int32
    fillOffset*: int32
    drawRect*: Vec4
    innerColor*: uint32
    outerColor*: uint32
    backdropColor*: uint32

  PathDrawCall* = object
    imageId*: ImageId
    instanceOffset*: int32
    instanceCount*: int32
    uniformIndex*: int32

  GlyphInstanceParam* = object
    drawRect*: Vec4
    textColor*: uint32
    backdropColor*: uint32
    glyphLocX*: int32
    glyphLocY*: int32
    maxBandX*: int32
    maxBandY*: int32
    glyphTransformIndex*: int32

  GlyphDrawCall* = object
    imageId*: ImageId
    curveImageId*: ImageId
    bandImageId*: ImageId
    instanceOffset*: int32
    instanceCount*: int32
    mvpIndex*: int32
    uniformIndex*: int32

  DrawCallType* = enum
    DrawCallPath = 0
    DrawCallGlyph

  DrawCall* = object
    bounds*: Bounds
    blend*: CompositeOperation
    case kind*: DrawCallType
    of DrawCallPath: path*: PathDrawCall
    of DrawCallGlyph: glyph*: GlyphDrawCall

  DrawList* = object
    lastId: uint32
    tiles: Tiles
    edges*: seq[Vec4]
    calls*: seq[DrawCall]
    uniforms*: seq[UniformParam]
    paths*: seq[PathInstanceParam]
    glyphs*: seq[GlyphInstanceParam]
    transforms*: seq[Mat2d]

proc clear*(ctx: var DrawList) =
  ctx.edges.setLen(0)
  ctx.calls.setLen(0)
  ctx.uniforms.setLen(0)
  ctx.paths.setLen(0)
  ctx.glyphs.setLen(0)
  ctx.transforms.setLen(0)

proc addUniform(ctx: var DrawList, uniform: UniformParam): int32 =
  for i in 0 ..< ctx.uniforms.len:
    if ctx.uniforms[i] == uniform:
      result = int32(i)
      return

  ctx.uniforms.add(uniform)

  int32(ctx.uniforms.len - 1)

proc addTransform(ctx: var DrawList, transform: Mat2d): int32 =
  for i in 0 ..< ctx.transforms.len:
    if ctx.transforms[i] == transform:
      result = int32(i)
      return

  ctx.transforms.add(transform)

  int32(ctx.transforms.len - 1)

proc canMerge(a, b: DrawCall): bool =
  if a.blend != b.blend:
    return

  case a.kind
  of DrawCallPath:
    a.path.imageId == b.path.imageId and
    a.path.uniformIndex == b.path.uniformIndex

  of DrawCallGlyph:
    a.glyph.curveImageId == b.glyph.curveImageId and
    a.glyph.bandImageId == b.glyph.bandImageId and
    a.glyph.mvpIndex == b.glyph.mvpIndex and
    a.glyph.uniformIndex == b.glyph.uniformIndex

proc addCall(ctx: var DrawList, c: DrawCall) =
  if ctx.calls.len == 0:
    ctx.calls.add(c)
    return

  var
    r = int32(ctx.calls.len) - 1
    l = max(0, r - 16)

  while r >= l:
    let
      p = ctx.calls[r].addr
    if p.kind != c.kind:
      if p.bounds.overlap(c.bounds):
        break
    elif p[].canMerge(c):
      case c.kind
      of DrawCallPath:
        p.path.instanceCount = p.path.instanceCount +
            c.path.instanceCount

      of DrawCallGlyph:
        p.glyph.instanceCount = p.glyph.instanceCount +
            c.glyph.instanceCount
      p.bounds = union(p.bounds, c.bounds)
      return
    else:
      break

    dec r, 1

  ctx.calls.add(c)

proc allocId*(ctx: var DrawList): uint32 =
  inc ctx.lastId, 1
  while ctx.lastId == 0:
    inc ctx.lastId, 1

  ctx.lastId

proc createImage*(ctx: var DrawList, imageInfo: ImageInfo): Image =
  result = Image()
  result.imageId.id = ctx.allocId()
  result.imageInfo.width = imageInfo.width
  result.imageInfo.height = imageInfo.height
  result.imageInfo.pixelFormat = imageInfo.pixelFormat
  result.imageInfo.alphaType = imageInfo.alphaType

  if imageInfo.strideBytes > 0:
    result.imageInfo.strideBytes = imageInfo.strideBytes
  else:
    let
      bytesPerPixel = imageInfo.pixelFormat.bytesPerPixel
    result.imageInfo.strideBytes = imageInfo.width * bytesPerPixel

proc writePixels*(image: Image, x, y, w, h, strideBytes: int32,
    data: pointer) =
  let
    imageInfo = image.imageInfo
    bytesPerPixel = imageInfo.pixelFormat.bytesPerPixel

  if image.data.len <= 0:
    image.data.setLen(imageInfo.height * imageInfo.strideBytes)

  let
    sourceRowBytes = w * bytesPerPixel
    sourceStrideBytes = strideBytes
    sourcePixels = cast[ptr UncheckedArray[uint8]](data)
    destinationStrideBytes = imageInfo.strideBytes
    destinationOffset = x + y * destinationStrideBytes
    destinationPixels = cast[ptr UncheckedArray[uint8]](image.data[
        destinationOffset].addr)

  for idx in 0 ..< h:
    copyMem(destinationPixels[idx * destinationStrideBytes].addr, sourcePixels[
        idx * sourceStrideBytes].addr, sourceRowBytes)

proc toShaderType(paint: Paint, image: Image): ShaderType =
  if not image.isNil:
    result = ShaderImage
  elif paint.innerColor != paint.outerColor:
    result = ShaderGradient
  else:
    result = ShaderSolid

proc toRenderFlags(shaderType: ShaderType, texType: TextureType,
    fillRule: FillRule): uint32 =
  uint32(shaderType) or (uint32(texType) shl 8) or (uint32(fillRule) shl 16)

proc toTransform(paint: Paint, imageFlags: set[ImageFlags]): Mat2d =
  let
    paintIsPlain = paint.imageId.isNil and
        paint.innerColor == paint.outerColor

  result = paint.transform

  if not paintIsPlain:
    if ImageFlipY in imageFlags:
      let dx = paint.extent[1] * 0.5
      result.translate(vec2(0, dx))
      result.scale(vec2(1, -1))
      result.translate(vec2(0, -dx))

    result.inverse()

proc toUniform(paint: Paint, shaderType: ShaderType, image: Image,
    imageFlags: set[ImageFlags], fillRule: FillRule): UniformParam =
  var
    texType = TextureType.Plain
  result.feather = paint.feather
  result.extent = paint.extent
  result.radius = paint.radius

  if not image.isNil:
    let
      imageInfo = image.imageInfo

    case imageInfo.pixelFormat
    of PixelFormatA8, PixelFormatA32f:
      texType = TextureType.Alpha
    of PixelFormatRGB8, PixelFormatRGBA8, PixelFormatRGB32f, PixelFormatRGBA32f,
        PixelFormatRGBA32u:
      if imageInfo.alphaType == AlphaPremultiplied:
        texType = TextureType.Premultiplied
      else:
        texType = TextureType.Rgb

  result.renderFlags = toRenderFlags(shaderType, texType, fillRule)

  if shaderType == ShaderSolid:
    result.extent = vec2(0, 0)
    result.radius = 0
    result.feather = 0

proc bounds(paths: openArray[DrawPath]): Bounds =
  if paths.len <= 0:
    return

  result.xMin = 1e6
  result.yMin = 1e6
  result.xMax = -1e6
  result.yMax = -1e6

  for idx in 0 ..< paths.len:
    let p = paths[idx].addr
    if p.fill.len <= 0:
      continue

    result.xMin = min(p.bounds.xMin, result.xMin)
    result.yMin = min(p.bounds.yMin, result.yMin)
    result.xMax = max(p.bounds.xMax, result.xMax)
    result.yMax = max(p.bounds.yMax, result.yMax)

proc addTileEdges(ctx: var DrawList, bounds: var Bounds, count: uint32,
    paths: openArray[DrawPath], instanceParam: var PathInstanceParam) =
  let
    zone = zoneBegin("drawList.addTileEdges")
  defer: zone.zoneEnd()

  bounds.xMin = floor(bounds.xMin)
  bounds.yMin = floor(bounds.yMin)
  bounds.xMax = ceil(bounds.xMax)
  bounds.yMax = ceil(bounds.yMax)

  let
    width = bounds.xMax - bounds.xMin
    height = bounds.yMax - bounds.yMin
    xtiles = int32(ceil(width / NVG_TILE_SIZE))
    ytiles = int32(ceil(height / NVG_TILE_SIZE))
    tilew = int32(ceil(width / float32(xtiles)))
    tileh = int32(ceil(height / float32(ytiles)))

  ctx.tiles.setup(xtiles, ytiles, count)

  for p in paths:
    if p.fill.len <= 0:
      continue

    let pymin = clamp(int32(p.bounds.yMin - bounds.yMin - 0.5) div tileh, 0,
        ytiles - 1)

    for v in p.fill.toOpenArray:
      let
        x0 = v[0]
        y0 = v[1]
        x1 = v[2]
        y1 = v[3]

      if x0 == x1:
        continue

      let
        vxmin = clamp(int32(min(x0, x1) - bounds.xMin - 0.5) div tilew, 0,
            xtiles - 1)
        vxmax = clamp(int32(max(x0, x1) - bounds.xMin + 0.5) div tilew, 0,
            xtiles - 1)
        vymax = clamp(int32(max(y0, y1) - bounds.yMin + 0.5) div tileh, 0,
            ytiles - 1)

      for ix in vxmin .. vxmax:
        for iy in pymin .. vymax:
          let
            tileId = ctx.tiles[ix, iy]
            p = ctx.tiles.tail(tileId)

          if not p.isNil:
            let tymax = float32((iy + 1) * tileh) + bounds.yMin

            if y0 > tymax and y1 > tymax and p[][1] > tymax and x0 == p[][
                2] and y0 == p[][3]:
              p[][2] = x1
              p[][3] = y1
              continue

          ctx.tiles.add(tileId, v)

  var
    tileBounds = default(Bounds)

  for ix in 0 ..< xtiles:
    for iy in 0 ..< ytiles:
      let tileId = ctx.tiles[ix, iy]

      if ctx.tiles.empty(tileId):
        continue

      instanceParam.fillOffset = int32(ctx.edges.len)
      instanceParam.fillCount = 0

      for s in ctx.tiles.pieces(tileId):
        ctx.edges.add(s.toOpenArray)

      instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

      tileBounds.xMin = bounds.xMin + float32(ix * tilew)
      tileBounds.yMin = bounds.yMin + float32(iy * tileh)
      tileBounds.xMax = min(bounds.xMax, bounds.xMin + float32((ix + 1) * tilew))
      tileBounds.yMax = min(bounds.yMax, bounds.yMin + float32((iy + 1) * tileh))

      instanceParam.drawRect[0] = tileBounds.xMin
      instanceParam.drawRect[1] = tileBounds.yMin
      instanceParam.drawRect[2] = tileBounds.xMax - tileBounds.xMin
      instanceParam.drawRect[3] = tileBounds.yMax - tileBounds.yMin

      ctx.paths.add(instanceParam)

proc addEdges(ctx: var DrawList, bounds: Bounds,
    paths: openArray[DrawPath], instanceParam: var PathInstanceParam) =
  let
    zone = zoneBegin("drawList.addEdges")
  defer: zone.zoneEnd()

  instanceParam.fillOffset = int32(ctx.edges.len)
  instanceParam.fillCount = 0

  for p in paths:
    ctx.edges.add(p.fill.toOpenArray)

  instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

  let
    boxPad = float32(0.5)

  instanceParam.drawRect[0] = bounds.xMin - boxPad
  instanceParam.drawRect[1] = bounds.yMin - boxPad
  instanceParam.drawRect[2] = (bounds.xMax - bounds.xMin) + float32(2) * boxPad
  instanceParam.drawRect[3] = (bounds.yMax - bounds.yMin) + float32(2) * boxPad

  ctx.paths.add(instanceParam)

proc toUInt32Color(c: Color): uint32 {.inline.} =
  let
    a = float32(c.a) / 255.0
    pr = uint8(float32(c.r) * a)
    pg = uint8(float32(c.g) * a)
    pb = uint8(float32(c.b) * a)
  result = (uint32(c.a) shl 24) or (uint32(pb) shl 16) or (uint32(pg) shl 8) or
      uint32(pr)

proc addPathCall*(ctx: var DrawList, viewBound: Vec2, paint: Paint,
    image: Image, imageFlags: set[ImageFlags], paths: openArray[DrawPath],
    fillRule: FillRule, compositeOperation: CompositeOperation) =
  let
    zone = zoneBegin("drawList.addPathCall")
  defer: zone.zoneEnd()

  var
    count = uint32(0)
  for idx in 0 ..< paths.len:
    let p = paths[idx].addr
    inc count, p.fill.len

  if count <= 0:
    return

  var
    bounds = bounds(paths)
  bounds.xMin = clamp(bounds.xMin, 0, viewBound[0])
  bounds.yMin = clamp(bounds.yMin, 0, viewBound[1])
  bounds.xMax = clamp(bounds.xMax, 0, viewBound[0])
  bounds.yMax = clamp(bounds.yMax, 0, viewBound[1])

  var
    w = bounds.xMax - bounds.xMin
    h = bounds.yMax - bounds.yMin
  if w <= 0 or h <= 0:
    return

  let
    shaderType = toShaderType(paint, image)

  var
    drawCall = default(PathDrawCall)
    uniform = toUniform(paint, shaderType, image, imageFlags, fillRule)
    instanceParam = default(PathInstanceParam)

  instanceParam.innerColor = paint.innerColor.toUInt32Color
  instanceParam.outerColor = paint.outerColor.toUInt32Color
  instanceParam.backdropColor = paint.backdropColor.toUInt32Color

  drawCall.instanceOffset = int32(ctx.paths.len)
  drawCall.instanceCount = 0

  if not image.isNil:
    drawCall.imageId = image.imageId

  if count > 16 and (w > 2 * NVG_TILE_SIZE or h > 2 *
      NVG_TILE_SIZE):
    ctx.addTileEdges(bounds, count, paths, instanceParam)
  else:
    ctx.addEdges(bounds, paths, instanceParam)

  if ctx.paths.len > drawCall.instanceOffset:
    drawCall.instanceCount = int32(ctx.paths.len) - drawCall.instanceOffset

    let
      paintTransform = paint.toTransform(imageFlags)
    uniform.paintTransformIndex = ctx.addTransform(paintTransform)
    drawCall.uniformIndex = ctx.addUniform(uniform)

    ctx.addCall(
      DrawCall(
        kind: DrawCallPath,
        bounds: bounds,
        blend: compositeOperation,
        path: drawCall
      )
    )

proc addGlyphCall*(ctx: var DrawList, viewBound: Vec2, paint: Paint,
    image: Image, imageFlags: set[ImageFlags], curveImageId,
    bandImageId: ImageId, transform: Mat2d, glyphs: openArray[DrawGlyph],
    compositeOperation: CompositeOperation) =
  let
    zone = zoneBegin("drawList.addGlyphCall")
  defer: zone.zoneEnd()

  if glyphs.len <= 0:
    return

  if curveImageId.isNil or bandImageId.isNil:
    return

  let
    baseOffset = int32(ctx.glyphs.len)
    clipRect = inversed(transform) * Bounds(
      xMin: 0, yMin: 0, xMax: viewBound[0], yMax: viewBound[1])

  var
    layerBounds = Bounds(xMin: 1e6, yMin: 1e6, xMax: -1e6, yMax: -1e6)
  for i in 0 ..< glyphs.len:
    let
      dr = glyphs[i].drawRect
      gxMax = dr[0] + dr[2]
      gyMax = dr[1] + dr[3]
      glyphLayer = glyphs[i].transform *
        Bounds(xMin: dr[0], yMin: dr[1], xMax: gxMax, yMax: gyMax)

    if glyphLayer.xMax < clipRect.xMin or glyphLayer.yMax < clipRect.yMin or
        glyphLayer.xMin > clipRect.xMax or glyphLayer.yMin > clipRect.yMax:
      continue

    ctx.glyphs.add(GlyphInstanceParam(
      drawRect: dr,
      textColor: glyphs[i].color.toUInt32Color,
      glyphLocX: glyphs[i].glyphLocX,
      glyphLocY: glyphs[i].glyphLocY,
      maxBandX: glyphs[i].maxBandX,
      maxBandY: glyphs[i].maxBandY,
      glyphTransformIndex: ctx.addTransform(glyphs[i].transform),
      backdropColor: paint.backdropColor.toUInt32Color,
    ))

    layerBounds.xMin = min(layerBounds.xMin, glyphLayer.xMin)
    layerBounds.yMin = min(layerBounds.yMin, glyphLayer.yMin)
    layerBounds.xMax = max(layerBounds.xMax, glyphLayer.xMax)
    layerBounds.yMax = max(layerBounds.yMax, glyphLayer.yMax)

  let
    instanceCount = int32(ctx.glyphs.len) - baseOffset
  if instanceCount <= 0:
    return

  let
    screenBounds = transform * layerBounds
    bounds = Bounds(
      xMin: clamp(screenBounds.xMin, 0, viewBound[0]),
      yMin: clamp(screenBounds.yMin, 0, viewBound[1]),
      xMax: clamp(screenBounds.xMax, 0, viewBound[0]),
      yMax: clamp(screenBounds.yMax, 0, viewBound[1]),
    )

  let
    shaderType = toShaderType(paint, image)
    paintTransform = paint.toTransform(imageFlags)

  var
    drawCall = default(GlyphDrawCall)
    uniform = toUniform(paint, shaderType, image, imageFlags, NonZero)

  uniform.paintTransformIndex = ctx.addTransform(paintTransform)
  drawCall.uniformIndex = ctx.addUniform(uniform)
  drawCall.mvpIndex = ctx.addTransform(transform)

  drawCall.curveImageId = curveImageId
  drawCall.bandImageId = bandImageId
  drawCall.instanceOffset = baseOffset
  drawCall.instanceCount = instanceCount

  if not image.isNil:
    drawCall.imageId = image.imageId

  ctx.addCall(
    DrawCall(
      kind: DrawCallGlyph,
      bounds: bounds,
      blend: compositeOperation,
      glyph: drawCall
    )
  )
