import ./core
import ./math
import ./params
import ./pieces
import ./tiles

import std/math
import std/tables

type
  ShaderType* {.size: 4.} = enum
    Solid = 1
    Gradient
    Image
    Text

  Texture* = ref object of RootObj
    width*: int32
    height*: int32
    typ*: TextureType
    imageFlags*: set[ImageFlags]

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
    texture*: Texture
    triangleOffset*: int32
    triangleCount*: int32
    instanceOffset*: int32
    instanceCount*: int32
    uniformIndex*: int32
    blend*: CompositeOperation

  RenderData* = object
    idgen: uint32
    tiles: Tiles
    verts*: seq[Vec4]
    edges*: seq[Vec4]
    calls*: seq[InstanceCall]
    uniforms*: seq[UniformParam]
    instances*: seq[InstanceParam]
    images*: Table[ImageId, Texture]

proc addTexture*(
    ctx: var RenderData,
    texture: Texture): ImageId =
  inc ctx.idgen, 1
  let imageId = cast[ImageId](ctx.idgen)
  ctx.images[imageId] = texture
  imageId

proc getTexture*(
    ctx: var RenderData,
    imageId: ImageId): Texture =
  ctx.images.withValue(imageId, tex):
    result = tex[]

proc removeTexture*(
    ctx: var RenderData,
    imageId: ImageId) =
  ctx.images.del(imageId)

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32]) {.inline.} =
  verts.add(vec4(bounds[2], bounds[3], 0, 0))
  verts.add(vec4(bounds[2], bounds[1], 0, 0))
  verts.add(vec4(bounds[0], bounds[3], 0, 0))
  verts.add(vec4(bounds[0], bounds[3], 0, 0))
  verts.add(vec4(bounds[2], bounds[1], 0, 0))
  verts.add(vec4(bounds[0], bounds[1], 0, 0))

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32], pad: float32) {.inline.} =
  let
    v0 = bounds[0] - pad
    v1 = bounds[1] - pad
    v2 = bounds[2] + pad
    v3 = bounds[3] + pad

  verts.add(vec4(v2, v3, 0, 0))
  verts.add(vec4(v2, v1, 0, 0))
  verts.add(vec4(v0, v3, 0, 0))
  verts.add(vec4(v0, v3, 0, 0))
  verts.add(vec4(v2, v1, 0, 0))
  verts.add(vec4(v0, v1, 0, 0))

proc reserve[T](s: var seq[T], n: Natural) {.inline.} =
  let
    l = s.len
    c = n + s.len

  if capacity(s) < c:
    s.setLen(c)
    s.setLen(l)

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
    if prev.blend == call.blend and prev.texture == call.texture and
      prev.uniformIndex == call.uniformIndex:
        prev.instanceCount = prev.instanceCount + call.instanceCount
        prev.triangleCount = prev.triangleCount + call.triangleCount
        return

  ctx.calls.add(call)

proc premultiplied(c: Color): Color {.inline.} =
  result.r = c.r * c.a
  result.g = c.g * c.a
  result.b = c.b * c.a
  result.a = c.a

proc fillCall*(
    ctx: var RenderData,
    view: Vec2,
    paint: Paint,
    compositeOperation: CompositeOperation,
    renderFlags: set[RenderFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  var
    ncalls = 0
    nedges = 0

  for idx in 0 ..< contours.len:
    let p = contours[idx].addr
    inc nedges, p.fill.len
    if idx <= 0 or p.restart:
      inc ncalls, 1

  if nedges <= 0:
    return

  var
    ltrb: array[4, float32]
    callw = default(float32)
    callh = default(float32)

  ltrb[0] = clamp(bounds[0], 0, view[0 and 0x1])
  ltrb[1] = clamp(bounds[1], 0, view[1 and 0x1])
  ltrb[2] = clamp(bounds[2], 0, view[2 and 0x1])
  ltrb[3] = clamp(bounds[3], 0, view[3 and 0x1])

  callw = ltrb[2] - ltrb[0]
  callh = ltrb[3] - ltrb[1]

  if callw <= 0 or callh <= 0:
    return

  var
    call = default(InstanceCall)
    uniformParam = default(UniformParam)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.triangleOffset = int32(ctx.verts.len)
  call.triangleCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  uniformParam.shaderType = float32(Solid)
  uniformParam.fillType = 0
  uniformParam.feather = paint.feather
  uniformParam.innerColor = paint.innerColor.premultiplied
  uniformParam.outerColor = paint.outerColor.premultiplied
  uniformParam.extent = paint.extent
  uniformParam.transform1[0] = paint.transform[0]
  uniformParam.transform1[1] = paint.transform[1]
  uniformParam.transform2[0] = paint.transform[2]
  uniformParam.transform2[1] = paint.transform[3]
  uniformParam.transform3[0] = paint.transform[4]
  uniformParam.transform3[1] = paint.transform[5]

  if EvenOdd in renderFlags:
    uniformParam.fillType = float32(1 shl 0)

  if not paint.image.isNil:
    let tex = ctx.getTexture(paint.image)
    if not tex.isNil:
      case tex.typ
      of TextureRgba:
        if ImagePremultiplied in tex.imageFlags:
          uniformParam.texType = 3
        else:
          uniformParam.texType = 1

      of TextureAlpha, TextureFloat:
        uniformParam.texType = 2

      uniformParam.texSize = vec2(float32(tex.width), float32(tex.height))
      call.texture = tex

  const tileSize = 32

  if ncalls == 1 and nedges > 16 and (callw > 2 * tileSize or callh > 2 * tileSize):
    ltrb[0] = floor(ltrb[0])
    ltrb[1] = floor(ltrb[1])
    ltrb[2] = ceil(ltrb[2])
    ltrb[3] = ceil(ltrb[3])

    callw = ltrb[2] - ltrb[0]
    callh = ltrb[3] - ltrb[1]

    let
      xtiles = int(ceil(callw / tileSize))
      ytiles = int(ceil(callh / tileSize))
      tilew = int(ceil(callw / float32(xtiles)))
      tileh = int(ceil(callh / float32(ytiles)))

    ctx.tiles.setup(xtiles, ytiles, nedges)

    nedges = 0
    ncalls = 0

    for p in contours:
      if p.fill.len <= 0:
        continue

      let pymin = clamp(int(p.bounds[1] - ltrb[1] - 0.5) div tileh, 0, ytiles - 1)

      for v in p.fill.toOpenArray:
        let
          x0 = v[0]
          y0 = v[1]
          x1 = v[2]
          y1 = v[3]

        if x0 == x1:
          continue

        let
          vxmin = clamp(int(min(x0, x1) - ltrb[0] - 0.5) div tilew, 0, xtiles - 1)
          vxmax = clamp(int(max(x0, x1) - ltrb[0] + 0.5) div tilew, 0, xtiles - 1)
          vymax = clamp(int(max(y0, y1) - ltrb[1] + 0.5) div tileh, 0, ytiles - 1)

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
              inc ncalls, 1

            inc nedges, 1

            ctx.tiles.add(tileId, v)

    ctx.verts.reserve(ncalls * 6)
    ctx.edges.reserve(nedges)
    ctx.instances.reserve(xtiles * ytiles)

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

        instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

        tileBounds[0] = ltrb[0] + float32(ix * tilew)
        tileBounds[1] = ltrb[1] + float32(iy * tileh)
        tileBounds[2] = min(ltrb[2], ltrb[0] + float32((ix + 1) * tilew))
        tileBounds[3] = min(ltrb[3], ltrb[1] + float32((iy + 1) * tileh))

        ctx.verts.addQuad(tileBounds)
        ctx.instances.add(instanceParam)

  elif ncalls == 1:
    instanceParam.fillOffset = int32(ctx.edges.len)

    for p in contours:
      ctx.edges.add(p.fill.toOpenArray)

    instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

    ctx.verts.addQuad(ltrb, 0.5)
    ctx.instances.add(instanceParam)

  else:
    var
      lastIdx = 0
      callbnds = [1e6f, 1e6f, -1e6f, -1e6f]

    for idx in 0 ..< contours.len:
      let p = contours[idx].addr

      callbnds[0] = min(callbnds[0], p.bounds[0])
      callbnds[1] = min(callbnds[1], p.bounds[1])
      callbnds[2] = max(callbnds[2], p.bounds[2])
      callbnds[3] = max(callbnds[3], p.bounds[3])

      if (idx + 1) == contours.len or contours[idx + 1].restart:
        callbnds[0] = max(ltrb[0], callbnds[0])
        callbnds[1] = max(ltrb[1], callbnds[1])
        callbnds[2] = min(ltrb[2], callbnds[2])
        callbnds[3] = min(ltrb[3], callbnds[3])

        if callbnds[0] >= callbnds[2] or callbnds[1] >= callbnds[3]:
          if instanceParam.fillOffset > 0:
            ctx.verts.setLen(ctx.verts.len - 6)
            ctx.edges.setLen(int(instanceParam.fillOffset))
            ctx.instances.setLen(ctx.instances.len - 1)
        else:
          instanceParam.fillOffset = int32(ctx.edges.len)

          for idx2 in lastIdx .. idx:
            let p = contours[idx2].addr
            ctx.edges.add(p.fill.toOpenArray)

          lastIdx = idx + 1

          instanceParam.fillCount = int32(ctx.edges.len) - instanceParam.fillOffset

          ctx.verts.addQuad(callbnds, 0.5)
          ctx.instances.add(instanceParam)

        callbnds = [1e6f, 1e6f, -1e6f, -1e6f]

  if ctx.instances.len > call.instanceOffset:
    call.triangleCount = int32(ctx.verts.len) - call.triangleOffset
    call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
    call.uniformIndex = ctx.addUniform(uniformParam)

    ctx.addCall(call)

proc trianglesCall*(
    ctx: var RenderData,
    view: Vec2,
    paint: Paint,
    compositeOperation: CompositeOperation,
    renderFlags: set[RenderFlags],
    verts: openArray[Vec4],
) =
  var
    call = default(InstanceCall)
    uniformParam = default(UniformParam)
    instanceParam = default(InstanceParam)

  call.blend = compositeOperation
  call.triangleOffset = int32(ctx.verts.len)
  call.triangleCount = 0
  call.instanceOffset = int32(ctx.instances.len)
  call.instanceCount = 0

  uniformParam.shaderType = float32(Text)
  uniformParam.fillType = 0
  uniformParam.feather = paint.feather
  uniformParam.innerColor = paint.innerColor.premultiplied
  uniformParam.outerColor = paint.outerColor.premultiplied
  uniformParam.extent = paint.extent
  uniformParam.transform1[0] = paint.transform[0]
  uniformParam.transform1[1] = paint.transform[1]
  uniformParam.transform2[0] = paint.transform[2]
  uniformParam.transform2[1] = paint.transform[3]
  uniformParam.transform3[0] = paint.transform[4]
  uniformParam.transform3[1] = paint.transform[5]

  if EvenOdd in renderFlags:
    uniformParam.fillType = float32(1 shl 0)

  if not paint.image.isNil:
    let tex = ctx.getTexture(paint.image)
    if not tex.isNil:
      case tex.typ
      of TextureRgba:
        if ImagePremultiplied in tex.imageFlags:
          uniformParam.texType = 3
        else:
          uniformParam.texType = 1

      of TextureAlpha, TextureFloat:
        uniformParam.texType = 2

      uniformParam.texSize = vec2(float32(tex.width), float32(tex.height))
      call.texture = tex

  ctx.verts.add(verts)

  instanceParam.fillOffset = int32(ctx.edges.len)
  instanceParam.fillCount = 0

  var idx = 0
  while idx < verts.len:
    ctx.instances.add(instanceParam)
    inc idx, 6

  if ctx.instances.len > call.instanceOffset:
    call.triangleCount = int32(ctx.verts.len) - call.triangleOffset
    call.instanceCount = int32(ctx.instances.len) - call.instanceOffset
    call.uniformIndex = ctx.addUniform(uniformParam)

    ctx.addCall(call)
