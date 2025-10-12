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
    ShaderSdf

  Image* = ref object
    imageId*: ImageId
    imageInfo*: ImageInfo
    data*: seq[byte]

  UniformParam* = object
    innerColor*: Color
    outerColor*: Color
    extent*: Vec2
    texSize*: Vec2
    transform1*: Vec2
    transform2*: Vec2
    transform3*: Vec2
    radius*: float32
    feather*: float32
    shaderType*: float32
    texType*: float32
    fillType*: float32
    pad: array[4, uint8]

  InstanceParam* = object
    fillCount*: int32
    fillOffset*: int32

  InstanceCall* = object
    imageId*: ImageId
    triangleOffset*: int32
    triangleCount*: int32
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
    instances*: seq[InstanceParam]

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32]) {.inline.} =
  let
    xMin = bounds[0]
    yMin = bounds[1]
    xMax = bounds[2]
    yMax = bounds[3]

  verts.add(vec4(xMax, yMax, 0, 0))
  verts.add(vec4(xMax, yMin, 0, 0))
  verts.add(vec4(xMin, yMin, 0, 0))
  verts.add(vec4(xMin, yMax, 0, 0))

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32],
    pad: float32) {.inline.} =
  let
    xMin = bounds[0] - pad
    yMin = bounds[1] - pad
    xMax = bounds[2] + pad
    yMax = bounds[3] + pad

  verts.add(vec4(xMax, yMax, 0, 0))
  verts.add(vec4(xMax, yMin, 0, 0))
  verts.add(vec4(xMin, yMin, 0, 0))
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
  ctx.calls.setLen(0)
  ctx.uniforms.setLen(0)
  ctx.instances.setLen(0)

proc addUniform(ctx: var RenderData, uniform: UniformParam): int32 =
  if ctx.uniforms.len <= 0 or ctx.uniforms[^1] != uniform:
    ctx.uniforms.add(uniform)

  int32(ctx.uniforms.len - 1)

proc addCall(ctx: var RenderData, call: InstanceCall) =
  if ctx.calls.len > 0:
    let prev = ctx.calls[^1].addr
    if prev.blend == call.blend and prev.imageId == call.imageId and
      prev.uniformIndex == call.uniformIndex:
      prev.instanceCount = prev.instanceCount + call.instanceCount
      prev.triangleCount = prev.triangleCount + call.triangleCount
      return

  ctx.calls.add(call)

proc allocId*(ctx: var RenderData): uint32 =
  while ctx.lastId == 0:
    inc ctx.lastId, 1

  ctx.lastId

proc createImage*(
  ctx: var RenderData,
  imageInfo: ImageInfo): Image =
  Image(
    imageId: ImageId(id: ctx.allocId()),
    imageInfo: imageInfo,
  )

proc updatePixels*(image: Image, x, y, w, h, stride: int32, data: pointer) =
  let imageInfo = image.imageInfo

  if image.data.len <= 0:
    image.data.setLen(
      imageInfo.width * imageInfo.height * imageInfo.pixelFormat.bytesPerPixel)

  let
    bytesPerPixel = imageInfo.pixelFormat.bytesPerPixel
    offset = x + y * imageInfo.width
    lineBytes = w * bytesPerPixel
    sourceStrideBytes = stride * bytesPerPixel
    sourcePixels = cast[ptr UncheckedArray[uint8]](data)
    destinationStrideBytes = imageInfo.width * bytesPerPixel
    destinationPixels = cast[ptr UncheckedArray[uint8]](image.data[offset *
        bytesPerPixel].addr)

  for idx in 0 ..< h:
    copyMem(destinationPixels[idx * destinationStrideBytes].addr, sourcePixels[
        idx * sourceStrideBytes].addr, lineBytes)

proc toUniform(call: var InstanceCall, paint: Paint,
    shaderType: ShaderType, image: Image, fillRule: FillRule): UniformParam =
  result.shaderType = float32(shaderType)
  result.fillType = 0
  result.feather = paint.feather
  result.innerColor = paint.innerColor.premultiplied
  result.outerColor = paint.outerColor.premultiplied
  result.extent = paint.extent
  result.transform1[0] = paint.transform.xx
  result.transform1[1] = paint.transform.yx
  result.transform2[0] = paint.transform.xy
  result.transform2[1] = paint.transform.yy
  result.transform3[0] = paint.transform.dx
  result.transform3[1] = paint.transform.dy

  if fillRule == EvenOdd:
    result.fillType = float32(1 shl 0)

  if not image.isNil:
    let
      imageInfo = image.imageInfo
      pixelFormat = uint8(imageInfo.pixelFormat)
      premultiplied = imageInfo.alphaType == AlphaPremultiplied

    result.texType = float32(pixelFormat or (uint8(premultiplied) shl 7))
    result.texSize = vec2(float32(imageInfo.width), float32(imageInfo.height))

    case imageInfo.pixelFormat
    of PixelFormatA8, PixelFormatA32f:
      result.texType = 2
    of PixelFormatRGB8, PixelFormatRGBA8, PixelFormatRGB32f, PixelFormatRGBA32f:
      if premultiplied:
        result.texType = 3
      else:
        result.texType = 1

    call.imageId = image.imageId

proc calcBounds(contours: openArray[Contour]): Vec4 =
  result = vec4(1e6, 1e6, -1e6, -1e6)

  for idx in 0 ..< contours.len:
    let p = contours[idx].addr

    p.bounds = vec4(1e6, 1e6, -1e6, -1e6)

    if p.fill.len <= 0:
      continue

    for v in p.fill.toOpenArray:
      p.bounds[0] = min(p.bounds[0], v[2])
      p.bounds[1] = min(p.bounds[1], v[3])
      p.bounds[2] = max(p.bounds[2], v[2])
      p.bounds[3] = max(p.bounds[3], v[3])

    result[0] = min(p.bounds[0], result[0])
    result[1] = min(p.bounds[1], result[1])
    result[2] = max(p.bounds[2], result[2])
    result[3] = max(p.bounds[3], result[3])

proc addRenderContourCall*(
  ctx: var RenderData,
  viewBound: Vec2,
  paint: Paint,
  image: Image,
  contours: openArray[Contour],
  fillRule: FillRule,
  compositeOperation: CompositeOperation,
) =
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
    callw = default(float32)
    callh = default(float32)
    ltrb = calcBounds(contours)

  ltrb[0] = clamp(ltrb[0], 0, viewBound[0 and 0x1])
  ltrb[1] = clamp(ltrb[1], 0, viewBound[1 and 0x1])
  ltrb[2] = clamp(ltrb[2], 0, viewBound[2 and 0x1])
  ltrb[3] = clamp(ltrb[3], 0, viewBound[3 and 0x1])

  callw = ltrb[2] - ltrb[0]
  callh = ltrb[3] - ltrb[1]

  if callw <= 0 or callh <= 0:
    return

  var
    call = default(InstanceCall)
    uniformParam = call.toUniform(paint, ShaderSolid, image, fillRule)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.triangleOffset = int32(ctx.verts.len)
  call.triangleCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  const tileSize = 32

  if edgeCount > 16 and (callw > 2 * tileSize or callh > 2 * tileSize):
    ltrb[0] = floor(ltrb[0])
    ltrb[1] = floor(ltrb[1])
    ltrb[2] = ceil(ltrb[2])
    ltrb[3] = ceil(ltrb[3])

    callw = ltrb[2] - ltrb[0]
    callh = ltrb[3] - ltrb[1]

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

      let pymin = clamp(int32(p.bounds[1] - ltrb[1] - 0.5) div tileh, 0,
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
          vxmin = clamp(int32(min(x0, x1) - ltrb[0] - 0.5) div tilew, 0,
              xtiles - 1)
          vxmax = clamp(int32(max(x0, x1) - ltrb[0] + 0.5) div tilew, 0,
              xtiles - 1)
          vymax = clamp(int32(max(y0, y1) - ltrb[1] + 0.5) div tileh, 0,
              ytiles - 1)

        for ix in vxmin .. vxmax:
          for iy in pymin .. vymax:
            let
              tileId = ctx.tiles[ix, iy]
              p = ctx.tiles.tail(tileId)

            if not p.isNil:
              let tymax = float32((iy + 1) * tileh) + ltrb[1]

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

    var tileBounds: array[4, float32]

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

        tileBounds[0] = ltrb[0] + float32(ix * tilew)
        tileBounds[1] = ltrb[1] + float32(iy * tileh)
        tileBounds[2] = min(ltrb[2], ltrb[0] + float32((ix + 1) * tilew))
        tileBounds[3] = min(ltrb[3], ltrb[1] + float32((iy + 1) * tileh))

        ctx.verts.addQuad(tileBounds)
        ctx.instances.add(instanceParam)

  else:
    instanceParam.fillOffset = int32(ctx.edges.len)

    for p in contours:
      ctx.edges.add(p.fill.toOpenArray)

    instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

    ctx.verts.addQuad(ltrb, 0.5)
    ctx.instances.add(instanceParam)

  if ctx.instances.len > call.instanceOffset:
    call.triangleCount = int32(ctx.verts.len) - call.triangleOffset
    call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
    call.uniformIndex = ctx.addUniform(uniformParam)

    ctx.addCall(call)

proc addRenderSdfCall*(
  ctx: var RenderData,
  view: Vec2,
  paint: Paint,
  image: Image,
  verts: openArray[Vec4],
  compositeOperation: CompositeOperation,
) =
  var
    call = default(InstanceCall)
    uniformParam = call.toUniform(paint, ShaderSdf, image, NonZero)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.triangleOffset = int32(ctx.verts.len)
  call.triangleCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  ctx.verts.add(verts)

  instanceParam.fillOffset = int32(ctx.edges.len)
  instanceParam.fillCount = 0

  var idx = 0
  while idx < verts.len:
    ctx.instances.add(instanceParam)
    inc idx, 4

  if ctx.instances.len > call.instanceOffset:
    call.triangleCount = int32(ctx.verts.len) - call.triangleOffset
    call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
    call.uniformIndex = ctx.addUniform(uniformParam)

    ctx.addCall(call)
