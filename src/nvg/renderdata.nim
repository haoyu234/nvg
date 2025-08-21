import ./core
import ./math
import ./params
import ./pieces
import ./tiles

import std/math

type
  ShaderType* = enum
    FillSolid = 1
    FillGradient

  CallType* = enum
    FillCall = 1
    ConvexFillCall
    TrianglesCall

  Call* = object
    callType*: CallType
    fillOffset*: uint32
    fillCount*: uint32
    triangleOffset*: uint32
    triangleCount*: uint32
    uniformOffset*: uint32
    blend*: CompositeOperation

  FragmentUniform* = object
    transform: Mat3
    pad1: array[12, uint8]
    innerColor: Color
    outerColor: Color
    extent: Vec2
    texSize: Vec2
    radius: float32
    feather: float32
    compressed3Type: float32
    pad2: array[4, uint8]

  RenderData* = object
    tiles: Tiles
    calls*: seq[Call]
    verts*: seq[Vec4]
    edges*: seq[Vec4]
    uniforms*: seq[FragmentUniform]

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32]) {.inline.} =
  verts.add(vec4(bounds[2], bounds[3], 0, 0))
  verts.add(vec4(bounds[2], bounds[1], 0, 0))
  verts.add(vec4(bounds[0], bounds[3], 0, 0))
  verts.add(vec4(bounds[0], bounds[1], 0, 0))

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32],
    pad: float32) {.inline.} =
  let
    v0 = bounds[0] - pad
    v1 = bounds[1] - pad
    v2 = bounds[2] + pad
    v3 = bounds[3] + pad

  verts.add(vec4(v2, v3, 0, 0))
  verts.add(vec4(v2, v1, 0, 0))
  verts.add(vec4(v0, v3, 0, 0))
  verts.add(vec4(v0, v1, 0, 0))

proc toFillType(contourFlags: set[ContourFlags]): uint32 {.inline.} =
  if EvenOdd in contourFlags:
    result = result or (1 shl 0)

  if Convex in contourFlags:
    result = result or (1 shl 2)

proc toUniform(
    paint: Paint, contourFlags: set[ContourFlags]
): FragmentUniform {.inline.} =
  var
    shaderType = FillSolid
    texType = default(uint32)
    fillType = toFillType(contourFlags)
    uniform = default(FragmentUniform)

  uniform.innerColor = paint.innerColor
  uniform.outerColor = paint.outerColor
  uniform.extent = paint.extent

  if paint.innerColor != paint.outerColor:
    shaderType = FillGradient
    uniform.radius = paint.radius
    uniform.feather = paint.feather

  uniform.compressed3Type =
    float32(uint32(shaderType) or (texType shl 8) or (fillType shl 16))
  uniform

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

proc buildCall*(
    ctx: var RenderData,
    view: Vec2,
    paint: Paint,
    compositeOperation: CompositeOperation,
    contourFlags: set[ContourFlags],
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
    contourFlags = contourFlags
    call = default(Call)

  if contours.len == 1 and contours[0].convex and contours[0].fill.len > 2:
    contourFlags.incl(ContourFlags.Convex)

  call.callType = FillCall
  call.blend = compositeOperation

  let uniform = toUniform(paint, contourFlags)
  if ctx.uniforms.len > 0 and ctx.uniforms[ctx.uniforms.len - 1] == uniform:
    call.uniformOffset = uint32(ctx.uniforms.len) - 1
  else:
    call.uniformOffset = uint32(ctx.uniforms.len)
    ctx.uniforms.add(uniform)

  const tileSize = 32

  if ContourFlags.Convex in contourFlags:
    call.callType = ConvexFillCall
    call.fillOffset = 0
    call.fillCount = 0
    call.triangleCount = uint32(contours[0].fill.len)
    call.triangleOffset = uint32(ctx.verts.len)

    ctx.verts.add(contours[0].fill.toOpenArray)
  elif ncalls == 1 and nedges > 16 and (callw > 2 * tileSize or callh > 2 * tileSize):
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

    ctx.verts.reserve(ncalls * 4)
    ctx.edges.reserve(nedges)
    ctx.calls.reserve(xtiles * ytiles)

    var tileBounds: array[4, float32]

    for ix in 0 ..< xtiles:
      for iy in 0 ..< ytiles:
        let tileId = ctx.tiles[ix, iy]

        if ctx.tiles.empty(tileId):
          continue

        call.fillOffset = uint32(ctx.edges.len)
        call.fillCount = 0
        call.triangleOffset = uint32(ctx.verts.len)
        call.triangleCount = 4

        for s in ctx.tiles.pieces(tileId):
          ctx.edges.add(s.toOpenArray)

          inc call.fillCount, s.len

        tileBounds[0] = ltrb[0] + float32(ix * tilew)
        tileBounds[1] = ltrb[1] + float32(iy * tileh)
        tileBounds[2] = min(ltrb[2], ltrb[0] + float32((ix + 1) * tilew))
        tileBounds[3] = min(ltrb[3], ltrb[1] + float32((iy + 1) * tileh))

        ctx.verts.addQuad(tileBounds)
        ctx.calls.add(call)
  elif ncalls == 1:
    call.fillOffset = uint32(ctx.edges.len)
    call.fillCount = uint32(nedges)
    call.triangleOffset = uint32(ctx.verts.len)
    call.triangleCount = 4

    for p in contours:
      ctx.edges.add(p.fill.toOpenArray)

    ctx.verts.addQuad(ltrb, 0.5)
    ctx.calls.add(call)
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
          if call.fillOffset > 0:
            ctx.calls.setLen(ctx.calls.len - 1)
            ctx.verts.setLen(ctx.verts.len - 4)
            ctx.edges.setLen(int(call.fillOffset))
        else:
          let offset = uint32(ctx.edges.len)

          for idx2 in lastIdx .. idx:
            let p = contours[idx2].addr
            ctx.edges.add(p.fill.toOpenArray)

          lastIdx = idx + 1

          call.fillOffset = offset
          call.fillCount = uint32(ctx.edges.len) - offset
          call.triangleOffset = uint32(ctx.verts.len)
          call.triangleCount = 4

          ctx.verts.addQuad(callbnds, 0.5)
          ctx.calls.add(call)

        callbnds = [1e6f, 1e6f, -1e6f, -1e6f]
