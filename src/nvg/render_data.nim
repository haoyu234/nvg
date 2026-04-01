import ./backend
import ./core
import ./math
import ./pieces
import ./tiles

import std/math
import std/tables

type
  ShaderType* {.size: 4.} = enum
    ShaderSolid = 1
    ShaderGradient
    ShaderImage
    ShaderGlyphQuad

  Image* = ref object
    imageId*: ImageId
    imageInfo*: ImageInfo
    data*: seq[byte]

  UniformParam* = object
    innerColor*: Color32f
    outerColor*: Color32f
    extent*: Vec2
    texSize*: array[2, float32]
    transform1*: Vec2
    transform2*: Vec2
    transform3*: Vec2
    radius*: float32
    feather*: float32
    shaderType*: float32
    texType*: float32
    fillType*: float32
    isSdf*: float32

  InstanceParam* = object
    fillCount*: int32
    fillOffset*: int32
    colorIndex*: int32
    pad: int32

  InstanceCall* = object
    imageId*: ImageId
    vertexOffset*: int32
    vertexCount*: int32
    instanceOffset*: int32
    instanceCount*: int32
    uniformIndex*: int32
    blend*: CompositeOperation

  RenderData* = object
    lastId: uint32
    tiles: Tiles
    verts*: seq[Vec4]
    edges*: seq[Vec4]
    calls*: seq[InstanceCall]
    uniforms*: seq[UniformParam]
    colors*: seq[Color32f]
    instances*: seq[InstanceParam]

proc addQuad(verts: var seq[Vec4], bounds: Bounds) {.inline.} =
  verts.add(vec4(bounds.xMin, bounds.yMin, 0, 0))
  verts.add(vec4(bounds.xMax, bounds.yMin, 0, 0))
  verts.add(vec4(bounds.xMax, bounds.yMax, 0, 0))
  verts.add(vec4(bounds.xMin, bounds.yMax, 0, 0))

proc addQuad(verts: var seq[Vec4], bounds: Bounds,
    pad: float32) {.inline.} =
  let
    xMin = bounds.xMin - pad
    yMin = bounds.yMin - pad
    xMax = bounds.xMax + pad
    yMax = bounds.yMax + pad

  verts.add(vec4(xMin, yMin, 0, 0))
  verts.add(vec4(xMax, yMin, 0, 0))
  verts.add(vec4(xMax, yMax, 0, 0))
  verts.add(vec4(xMin, yMax, 0, 0))

proc reserve[T](s: var seq[T], n: Natural) {.inline.} =
  let
    l = s.len
    c = n + s.len

  if capacity(s) < c:
    s.setLenUninit(c)
    s.setLenUninit(l)

proc clear*(ctx: var RenderData) =
  ctx.verts.setLen(0)
  ctx.edges.setLen(0)
  ctx.colors.setLen(0)
  ctx.calls.setLen(0)
  ctx.uniforms.setLen(0)
  ctx.instances.setLen(0)

proc addUniform(ctx: var RenderData, uniform: UniformParam): int32 =
  if ctx.uniforms.len <= 0 or ctx.uniforms[^1] != uniform:
    ctx.uniforms.add(uniform)

  int32(ctx.uniforms.len - 1)

proc addColor(ctx: var RenderData, color: Color32f): int32 =
  if ctx.colors.len <= 0:
    ctx.colors.add(Color32f()) # transparent
    ctx.colors.add(color)
  elif ctx.colors[^1] != color:
    ctx.colors.add(color)

  int32(ctx.colors.len - 1)

proc addCall(ctx: var RenderData, call: InstanceCall) =
  if ctx.calls.len > 0:
    let prev = ctx.calls[^1].addr
    if prev.blend == call.blend and prev.imageId == call.imageId and
      prev.uniformIndex == call.uniformIndex:
      prev.instanceCount = prev.instanceCount + call.instanceCount
      prev.vertexCount = prev.vertexCount + call.vertexCount
      return

  ctx.calls.add(call)

proc allocId*(ctx: var RenderData): uint32 =
  inc ctx.lastId, 1
  while ctx.lastId == 0:
    inc ctx.lastId, 1

  ctx.lastId

proc createImage*(ctx: var RenderData, imageInfo: ImageInfo): Image =
  result = Image()
  result.imageId.id = ctx.allocId()
  result.imageInfo.width = imageInfo.width
  result.imageInfo.height = imageInfo.height
  result.imageInfo.pixelFormat = imageInfo.pixelFormat
  result.imageInfo.alphaType = imageInfo.alphaType
  result.imageInfo.strideBytes =
    if imageInfo.strideBytes > 0: imageInfo.strideBytes else:
      let
        bytesPerPixel = imageInfo.pixelFormat.bytesPerPixel
      imageInfo.width * bytesPerPixel

proc updatePixels*(image: Image, x, y, w, h, strideBytes: int32,
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

proc toUniform(call: var InstanceCall, paint: Paint, shaderType: ShaderType,
    image: Image, imageFlags: set[ImageFlags], isSdf: bool,
    fillRule: FillRule): UniformParam =
  result.shaderType = float32(shaderType)
  result.fillType = 0
  result.feather = paint.feather
  result.innerColor = paint.innerColor.premultiplied
  result.outerColor = paint.outerColor.premultiplied
  result.extent = paint.extent
  result.isSdf = float32(isSdf)

  if fillRule == EvenOdd:
    result.fillType = float32(1 shl 0)

  if not image.isNil or paint.innerColor != paint.outerColor:
    var transform = paint.transform

    if ImageFlipY in imageFlags:
      let dx = paint.extent[1] * 0.5
      transform.translate(vec2(0, dx))
      transform.scale(vec2(1, -1))
      transform.translate(vec2(0, -dx))

    transform.inverse()

    result.transform1[0] = transform.xx
    result.transform1[1] = transform.yx
    result.transform2[0] = transform.xy
    result.transform2[1] = transform.yy
    result.transform3[0] = transform.dx
    result.transform3[1] = transform.dy

  if not image.isNil:
    let
      imageInfo = image.imageInfo

    case imageInfo.pixelFormat
    of PixelFormatA8, PixelFormatA32f:
      result.texType = float32(2)
    of PixelFormatRGB8, PixelFormatRGBA8, PixelFormatRGB32f, PixelFormatRGBA32f:
      if imageInfo.alphaType == AlphaPremultiplied:
        result.texType = float32(3)
      else:
        result.texType = float32(1)

    call.imageId = image.imageId
    result.texSize[0] = float32(imageInfo.width)
    result.texSize[1] = float32(imageInfo.height)

proc calcBounds(contours: openArray[Contour]): Bounds =
  if contours.len <= 0:
    return

  result.xMin = 1e6
  result.yMin = 1e6
  result.xMax = -1e6
  result.yMax = -1e6

  for idx in 0 ..< contours.len:
    let p = contours[idx].addr
    if p.fill.len <= 0:
      continue

    result.xMin = min(p.bounds.xMin, result.xMin)
    result.yMin = min(p.bounds.yMin, result.yMin)
    result.xMax = max(p.bounds.xMax, result.xMax)
    result.yMax = max(p.bounds.yMax, result.yMax)

proc addCall*(ctx: var RenderData, viewBound: Vec2, paint: Paint,
    image: Image, imageFlags: set[ImageFlags], contours: openArray[Contour],
    fillRule: FillRule, compositeOperation: CompositeOperation) =
  let edgeCount =
    block:
      var edgeCount = uint32(0)
      for idx in 0 ..< contours.len:
        let p = contours[idx].addr
        inc edgeCount, p.fill.len
      edgeCount

  if edgeCount <= 0:
    return

  var
    bounds = calcBounds(contours)
  bounds.xMin = clamp(bounds.xMin, 0, viewBound[0 and 0x1])
  bounds.yMin = clamp(bounds.yMin, 0, viewBound[1 and 0x1])
  bounds.xMax = clamp(bounds.xMax, 0, viewBound[2 and 0x1])
  bounds.yMax = clamp(bounds.yMax, 0, viewBound[3 and 0x1])

  var
    callw = bounds.xMax - bounds.xMin
    callh = bounds.yMax - bounds.yMin
  if callw <= 0 or callh <= 0:
    return

  var shaderType = ShaderSolid
  if not image.isNil:
    shaderType = ShaderImage

  var
    call = default(InstanceCall)
    uniformParam = call.toUniform(paint, shaderType, image, imageFlags, false, fillRule)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.vertexOffset = int32(ctx.verts.len)
  call.vertexCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  const tileSize = 32

  if edgeCount > 16 and (callw > 2 * tileSize or callh > 2 * tileSize):
    bounds.xMin = floor(bounds.xMin)
    bounds.yMin = floor(bounds.yMin)
    bounds.xMax = ceil(bounds.xMax)
    bounds.yMax = ceil(bounds.yMax)

    callw = bounds.xMax - bounds.xMin
    callh = bounds.yMax - bounds.yMin

    let
      xtiles = int32(ceil(callw / tileSize))
      ytiles = int32(ceil(callh / tileSize))
      tilew = int32(ceil(callw / float32(xtiles)))
      tileh = int32(ceil(callh / float32(ytiles)))

    ctx.tiles.setup(xtiles, ytiles, edgeCount)

    var
      edgeIdx = uint32(0)
      callIdx = uint32(0)

    for p in contours:
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
            else:
              inc callIdx, 1

            inc edgeIdx, 1

            ctx.tiles.add(tileId, v)

    ctx.edges.reserve(edgeIdx)
    ctx.instances.reserve(xtiles * ytiles)
    ctx.verts.reserve(callIdx * 4)

    var tileBounds = default(Bounds)

    for ix in 0 ..< xtiles:
      for iy in 0 ..< ytiles:
        let tileId = ctx.tiles[ix, iy]

        if ctx.tiles.empty(tileId):
          continue

        instanceParam.fillOffset = int32(ctx.edges.len)
        instanceParam.fillCount = 0

        for s in ctx.tiles.pieces(tileId):
          ctx.edges.add(s.toOpenArray)

        instanceParam.fillCount = int32(ctx.edges.len) -
            instanceParam.fillOffset

        tileBounds.xMin = bounds.xMin + float32(ix * tilew)
        tileBounds.yMin = bounds.yMin + float32(iy * tileh)
        tileBounds.xMax = min(bounds.xMax, bounds.xMin + float32((ix + 1) * tilew))
        tileBounds.yMax = min(bounds.yMax, bounds.yMin + float32((iy + 1) * tileh))

        ctx.verts.addQuad(tileBounds)
        ctx.instances.add(instanceParam)

  else:
    instanceParam.fillOffset = int32(ctx.edges.len)
    instanceParam.fillCount = 0

    for p in contours:
      ctx.edges.add(p.fill.toOpenArray)

    instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

    ctx.verts.addQuad(bounds, 0.5)
    ctx.instances.add(instanceParam)

  if ctx.instances.len > call.instanceOffset:
    call.vertexCount = int32(ctx.verts.len) - call.vertexOffset
    call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
    call.uniformIndex = ctx.addUniform(uniformParam)

    ctx.addCall(call)

proc addCall*(ctx: var RenderData, viewBound: Vec2, paint: Paint, image: Image,
    imageFlags: set[ImageFlags], isSdf: bool, color: Color, verts: openArray[
    Vec4], compositeOperation: CompositeOperation) =
  if verts.len <= 0:
    return

  var
    call = default(InstanceCall)
    uniformParam = call.toUniform(paint, ShaderGlyphQuad, image, imageFlags,
        isSdf, NonZero)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.vertexOffset = int32(ctx.verts.len)
  call.vertexCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  ctx.verts.add(verts)

  instanceParam.fillOffset = int32(ctx.edges.len)
  instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset
  instanceParam.colorIndex = ctx.addColor(color.premultiplied)

  for _ in 0 ..< verts.len div 4:
    ctx.instances.add(instanceParam)

  call.vertexCount = int32(ctx.verts.len) - call.vertexOffset
  call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
  call.uniformIndex = ctx.addUniform(uniformParam)

  ctx.addCall(call)
