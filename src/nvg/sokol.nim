import pkg/sokol/gfx except Color

import ./color
import ./context
import ./core
import ./glsl
import ./math
import ./params
import ./pieces
import ./tiles
import ./vec2

import std/math

when defined(NVG_DEBUG_VERTS):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

type
  ShaderType = enum
    FillSolid = 1
    FillGradient
    # FillImage
    # FillText

  VertexUniformObj = object
    view: Vec2
    pad: array[8, uint8]

  CallType = enum
    FillCall = 1
    ConvexFillCall
    TrianglesCall

  BlendObj = object
    srcRGB: BlendFactor
    dstRGB: BlendFactor
    srcAlpha: BlendFactor
    dstAlpha: BlendFactor

  CallObj = object
    callType: CallType
    fillOffset: uint32
    fillCount: uint32
    triangleOffset: uint32
    triangleCount: uint32
    uniformOffset: uint32
    blend: BlendObj

  FragmentUniformObj = object
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

  OpenglBackendContextObj = object
    shader: Shader
    smpDummy: Sampler
    texDummy: Image
    texEdges: Image
    texLayerCount: int32

    vertBuf: Buffer
    vertBufSize: int32

    blend: array[CallType, uint32]
    pipeline: array[CallType, Pipeline]

    vertexUniform: VertexUniformObj
    tiles: Tiles
    calls: seq[CallObj]
    verts: seq[Vec4]
    edges: seq[Vec4]
    uniforms: seq[FragmentUniformObj]

proc addQuad(verts: var seq[Vec4], bounds: array[4, float32]) {.inline.} =
  verts.add(vec4(bounds[2], bounds[3], 0, 0))
  verts.add(vec4(bounds[2], bounds[1], 0, 0))
  verts.add(vec4(bounds[0], bounds[3], 0, 0))
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
  verts.add(vec4(v0, v1, 0, 0))

proc toBlend(op: CompositeOperation): BlendObj {.inline.} =
  type BlendOp = object
    src: BlendFactor
    dst: BlendFactor

  const blendOpTbl: array[CompositeOperation, BlendOp] = [
    BlendOp(src: blendFactorOne, dst: blendFactorOneMinusSrcAlpha),
    BlendOp(src: blendFactorDstAlpha, dst: blendFactorZero),
    BlendOp(src: blendFactorOneMinusDstAlpha, dst: blendFactorZero),
    BlendOp(src: blendFactorDstAlpha, dst: blendFactorOneMinusSrcAlpha),
    BlendOp(src: blendFactorOneMinusDstAlpha, dst: blendFactorOne),
    BlendOp(src: blendFactorZero, dst: blendFactorSrcAlpha),
    BlendOp(src: blendFactorZero, dst: blendFactorOneMinusSrcAlpha),
    BlendOp(src: blendFactorOneMinusDstAlpha, dst: blendFactorSrcAlpha),
    BlendOp(src: blendFactorOne, dst: blendFactorOne),
    BlendOp(src: blendFactorOne, dst: blendFactorZero),
    BlendOp(src: blendFactorOneMinusDstAlpha, dst: blendFactorOneMinusSrcAlpha),
  ]

  let blendOp = blendOpTbl[op]
  BlendObj(
    srcRGB: blendOp.src,
    dstRGB: blendOp.dst,
    srcAlpha: blendOp.src,
    dstAlpha: blendOp.dst,
  )

proc toFillType(pathFlags: PathFlags): uint32 =
  if pathFlags.evenOdd:
    result = result or (1 shl 0)

  if pathFlags.convex:
    result = result or (1 shl 1)

proc toUniform(
    ctx: ptr OpenglBackendContextObj, paint: Paint, pathFlags: PathFlags
): FragmentUniformObj {.inline.} =
  var
    shaderType = FillSolid
    texType = default(uint32)
    fillType = toFillType(pathFlags)
    uniform = default(FragmentUniformObj)

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

proc reserve*[T](s: var seq[T], n: Natural) {.inline.} =
  let
    l = s.len
    c = n + s.len

  if capacity(s) < c:
    s.setLenUninit(c)
    s.setLenUninit(l)

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    pathFlags: PathFlags,
    bounds: Vec4,
    paths: openArray[FlattenedPath],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  var
    ncalls = 0
    nedges = 0

  for idx in 0 ..< paths.len:
    let p = paths[idx].addr
    inc nedges, p.fill.len
    if idx <= 0 or p.restart:
      inc ncalls, 1

  when defined(NVG_DEBUG_VERTS):
    printf("fill nedges: %u\n", nedges)

  if nedges <= 0:
    return

  var
    ltrb: array[4, float32]
    callw = default(float32)
    callh = default(float32)

  ltrb[0] = clamp(bounds[0], 0, ctx.vertexUniform.view[0 and 0x1])
  ltrb[1] = clamp(bounds[1], 0, ctx.vertexUniform.view[1 and 0x1])
  ltrb[2] = clamp(bounds[2], 0, ctx.vertexUniform.view[2 and 0x1])
  ltrb[3] = clamp(bounds[3], 0, ctx.vertexUniform.view[3 and 0x1])

  callw = ltrb[2] - ltrb[0]
  callh = ltrb[3] - ltrb[1]

  when defined(NVG_DEBUG_VERTS):
    printf(
      "%.6f %.6f %.6f %.6f callw[%.6f] cellh[%.6f]\n",
      bounds[0],
      bounds[1],
      bounds[2],
      bounds[3],
      callw,
      callh,
    )

  if callw <= 0 or callh <= 0:
    return

  var
    flags = pathFlags
    call = default(CallObj)

  if paths.len == 1 and paths[0].convex and paths[0].fill.len > 2:
    flags.convex = true

  call.callType = FillCall
  call.blend = toBlend(compositeOperation)

  let uniform = ctx.toUniform(paint, pathFlags)
  if ctx.uniforms.len > 0 and ctx.uniforms[ctx.uniforms.len - 1] == uniform:
    call.uniformOffset = uint32(ctx.uniforms.len) - 1
  else:
    call.uniformOffset = uint32(ctx.uniforms.len)
    ctx.uniforms.add(uniform)

  when defined(NVG_DEBUG_VERTS):
    printf(
      "ncalls[%u] npaths[%u] convex[%u] nfill[%u] uniformOffset[%u]\n",
      ncalls,
      paths.len,
      paths[0].convex,
      paths[0].fill.len,
      call.uniformOffset,
    )

  const tileSize = 32

  if flags.convex:
    call.callType = ConvexFillCall
    call.fillOffset = 0
    call.fillCount = 0
    call.triangleCount = uint32(paths[0].fill.len)
    call.triangleOffset = uint32(ctx.verts.len)

    ctx.verts.add(paths[0].fill.toOpenArray)
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

    when defined(NVG_DEBUG_VERTS):
      printf(
        "ltrb[%.6f %.6f %.6f %.6f] callw[%.6f] callh[%.6f] xtiles[%u] ytiles[%u] tilew[%u] tileh[%u]\n",
        ltrb[0],
        ltrb[1],
        ltrb[2],
        ltrb[3],
        callw,
        callh,
        xtiles,
        ytiles,
        tilew,
        tileh,
      )

    ctx.tiles.setup(xtiles, ytiles, nedges)

    nedges = 0
    ncalls = 0

    for p in paths:
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

              # when defined(NVG_DEBUG_VERTS):
              #   printf(
              #     "%.6f %.6f %.6f %.6f tymax[%.6f]\n",
              #     p[][0],
              #     p[][1],
              #     p[][2],
              #     p[][3],
              #     tymax,
              #   )

              if y0 > tymax and y1 > tymax and p[][1] > tymax and x0 == p[][2] and
                  y0 == p[][3]:
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

        # when defined(NVG_DEBUG_VERTS):
        #   printf("x[%u] y[%u] nedges[%u]\n", ix, iy, fillCount)
        #   for vert in tiles:
        #     printf("%.6f %.6f %.6f %.6f\n", vert[0], vert[1], vert[2], vert[3])

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

    for p in paths:
      ctx.edges.add(p.fill.toOpenArray)

    ctx.verts.addQuad(ltrb, 0.5)
    ctx.calls.add(call)
  else:
    var
      lastIdx = 0
      callbnds = [1e6f, 1e6f, -1e6f, -1e6f]

    for idx in 0 ..< paths.len:
      let p = paths[idx].addr

      callbnds[0] = min(callbnds[0], p.bounds[0])
      callbnds[1] = min(callbnds[1], p.bounds[1])
      callbnds[2] = max(callbnds[2], p.bounds[2])
      callbnds[3] = max(callbnds[3], p.bounds[3])

      if (idx + 1) == paths.len or paths[idx + 1].restart:
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
            let p = paths[idx2].addr
            ctx.edges.add(p.fill.toOpenArray)

          lastIdx = idx + 1

          call.fillOffset = offset
          call.fillCount = uint32(ctx.edges.len) - offset
          call.triangleOffset = uint32(ctx.verts.len)
          call.triangleCount = 4

          ctx.verts.addQuad(callbnds, 0.5)
          ctx.calls.add(call)

        callbnds = [1e6f, 1e6f, -1e6f, -1e6f]

  when defined(NVG_DEBUG_VERTS):
    printf("nverts: %u\n", uint32(ctx.verts.len))
    for vert in ctx.verts:
      printf("%.6f %.6f %.6f %.6f\n", vert[0], vert[1], vert[2], vert[3])

    printf("nedges: %u\n", uint32(ctx.edges.len))
    for vert in ctx.edges:
      printf("%.6f %.6f %.6f %.6f\n", vert[0], vert[1], vert[2], vert[3])

    printf("ncalls: %u\n", uint32(ctx.calls.len))
    for call in ctx.calls:
      let
        uniform = ctx.uniforms[call.uniformOffset].addr
        shaderType = uint32(uniform.compressed3Type) and 0xFF
      printf(
        "type: %u, shaderType: %u, image: %u, fillOffset: %u, fillCount: %u, triangleOffset: %u, triangleCount: %u, uniformOffset: %u\n",
        call.callType, shaderType, 0, call.fillOffset, call.fillCount,
        call.triangleOffset, call.triangleCount, call.uniformOffset,
      )

    printf("nuniforms: %u\n", uint32(ctx.uniforms.len))
    for uniform in ctx.uniforms:
      let
        texType = (uint32(uniform.compressed3Type) shr 8) and 0xFF
        fillType = (uint32(uniform.compressed3Type) shr 16) and 0xFF

      printf(
        "transform: %.6f %.6f %.6f %.6f\ninnerColor: %.6f %.6f %.6f %.6f\nouterColor: %.6f %.6f %.6f %.6f\nextent: %.6f %.6f\nradius: %.6f\nfeather: %.6f\nstrokeMult: %.6f\nstrokeThr: %.6f\ntexType: %u\nfillType: %u\n",
        0, # uniform.transform[0],
        0, # uniform.transform[1],
        0, # uniform.transform[2],
        0, # uniform.transform[3],
        uniform.innerColor[0],
        uniform.innerColor[1],
        uniform.innerColor[2],
        uniform.innerColor[3],
        uniform.outerColor[0],
        uniform.outerColor[1],
        uniform.outerColor[2],
        uniform.outerColor[3],
        uniform.extent[0],
        uniform.extent[1],
        uniform.radius,
        uniform.feather,
        0, # uniform.strokeMult,
        0, # uniform.strokeThr,
        texType,
        fillType,
      )

proc getShader(): Shader =
  var s = ShaderDesc(label: "nvg.shader")

  case queryBackend()
  of backendGlcore:
    s.vertexFunc.source = cast[cstring](vsSourceGlsl410[0].addr)
    s.vertexFunc.entry = "main"
    s.fragmentFunc.source = cast[cstring](fsSourceGlsl410[0].addr)
    s.fragmentFunc.entry = "main"
    s.attrs[0].base_type = shaderAttrBaseTypeFloat
    s.attrs[0].glslName = "va_in"
    s.attrs[1].base_type = shaderAttrBaseTypeFloat
    s.attrs[1].glslName = "vb_in"
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].glslUniforms[0].type = uniformTypeFloat4
    s.uniformBlocks[0].glslUniforms[0].arrayCount = 1
    s.uniformBlocks[0].glslUniforms[0].glslName = "view"
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 16
    s.uniformBlocks[5].glslUniforms[0].type = uniformTypeInt4
    s.uniformBlocks[5].glslUniforms[0].arrayCount = 1
    s.uniformBlocks[5].glslUniforms[0].glslName = "fill"
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].glslUniforms[0].type = uniformTypeFloat4
    s.uniformBlocks[6].glslUniforms[0].arrayCount = 7
    s.uniformBlocks[6].glslUniforms[0].glslName = "paint"
    s.images[1].stage = shaderStageFragment
    s.images[1].multisampled = false
    s.images[1].imageType = imageType2d
    s.images[1].sampleType = imageSampleTypeFloat
    s.images[2].stage = shaderStageFragment
    s.images[2].multisampled = false
    s.images[2].imageType = imageTypeArray
    s.images[2].sampleType = imageSampleTypeFloat
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.imageSamplerPairs[0].stage = shaderStageFragment
    s.imageSamplerPairs[0].imageSlot = 2
    s.imageSamplerPairs[0].samplerSlot = 4
    s.imageSamplerPairs[0].glslName = "edgeTex_smp2"
    s.imageSamplerPairs[1].stage = shaderStageFragment
    s.imageSamplerPairs[1].imageSlot = 1
    s.imageSamplerPairs[1].samplerSlot = 3
    s.imageSamplerPairs[1].glslName = "imageTex_smp1"
  of backendGles3:
    s.vertexFunc.source = cast[cstring](vsSourceGlsl300es[0].addr)
    s.vertexFunc.entry = "main"
    s.fragmentFunc.source = cast[cstring](fsSourceGlsl300es[0].addr)
    s.fragmentFunc.entry = "main"
    s.attrs[0].base_type = shaderAttrBaseTypeFloat
    s.attrs[0].glslName = "va_in"
    s.attrs[1].base_type = shaderAttrBaseTypeFloat
    s.attrs[1].glslName = "vb_in"
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].glslUniforms[0].type = uniformTypeFloat4
    s.uniformBlocks[0].glslUniforms[0].arrayCount = 1
    s.uniformBlocks[0].glslUniforms[0].glslName = "view"
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 16
    s.uniformBlocks[5].glslUniforms[0].type = uniformTypeInt4
    s.uniformBlocks[5].glslUniforms[0].arrayCount = 1
    s.uniformBlocks[5].glslUniforms[0].glslName = "fill"
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].glslUniforms[0].type = uniformTypeFloat4
    s.uniformBlocks[6].glslUniforms[0].arrayCount = 7
    s.uniformBlocks[6].glslUniforms[0].glslName = "paint"
    s.images[1].stage = shaderStageFragment
    s.images[1].multisampled = false
    s.images[1].imageType = imageType2d
    s.images[1].sampleType = imageSampleTypeFloat
    s.images[2].stage = shaderStageFragment
    s.images[2].multisampled = false
    s.images[2].imageType = imageTypeArray
    s.images[2].sampleType = imageSampleTypeFloat
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.imageSamplerPairs[0].stage = shaderStageFragment
    s.imageSamplerPairs[0].imageSlot = 2
    s.imageSamplerPairs[0].samplerSlot = 4
    s.imageSamplerPairs[0].glslName = "edgeTex_smp2"
    s.imageSamplerPairs[1].stage = shaderStageFragment
    s.imageSamplerPairs[1].imageSlot = 1
    s.imageSamplerPairs[1].samplerSlot = 3
    s.imageSamplerPairs[1].glslName = "imageTex_smp1"
  of backendD3d11:
    s.vertexFunc.source = cast[cstring](vsSourceHlsl5[0].addr)
    s.vertexFunc.d3d11Target = "vs_5_0"
    s.vertexFunc.entry = "main"
    s.fragmentFunc.source = cast[cstring](fsSourceHlsl5[0].addr)
    s.fragmentFunc.d3d11Target = "ps_5_0"
    s.fragmentFunc.entry = "main"
    s.attrs[0].base_type = shaderAttrBaseTypeFloat
    s.attrs[0].hlslSemName = "TEXCOORD"
    s.attrs[0].hlslSemIndex = 0
    s.attrs[1].base_type = shaderAttrBaseTypeFloat
    s.attrs[1].hlslSemName = "TEXCOORD"
    s.attrs[1].hlslSemIndex = 1
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].hlslRegisterBN = 0
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 16
    s.uniformBlocks[5].hlslRegisterBN = 1
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].hlslRegisterBN = 0
    s.images[1].stage = shaderStageFragment
    s.images[1].multisampled = false
    s.images[1].imageType = imageType2d
    s.images[1].sampleType = imageSampleTypeFloat
    s.images[1].hlslRegisterTN = 1
    s.images[2].stage = shaderStageFragment
    s.images[2].multisampled = false
    s.images[2].imageType = imageTypeArray
    s.images[2].sampleType = imageSampleTypeFloat
    s.images[2].hlslRegisterTN = 0
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[3].hlslRegisterSN = 0
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[4].hlslRegisterSN = 1
    s.imageSamplerPairs[0].stage = shaderStageFragment
    s.imageSamplerPairs[0].imageSlot = 2
    s.imageSamplerPairs[0].samplerSlot = 4
    s.imageSamplerPairs[1].stage = shaderStageFragment
    s.imageSamplerPairs[1].imageSlot = 1
    s.imageSamplerPairs[1].samplerSlot = 3
  of backendWgpu:
    s.vertexFunc.source = cast[cstring](vsSourceWgsl[0].addr)
    s.vertexFunc.entry = "main"
    s.fragmentFunc.source = cast[cstring](fsSourceWgsl[0].addr)
    s.fragmentFunc.entry = "main"
    s.attrs[0].base_type = shaderAttrBaseTypeFloat
    s.attrs[1].base_type = shaderAttrBaseTypeFloat
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].wgslGroup0BindingN = 0
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 16
    s.uniformBlocks[5].wgslGroup0BindingN = 9
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].wgslGroup0BindingN = 8
    s.images[1].stage = shaderStageFragment
    s.images[1].multisampled = false
    s.images[1].imageType = imageType2d
    s.images[1].sampleType = imageSampleTypeFloat
    s.images[1].wgslGroup1BindingN = 65
    s.images[2].stage = shaderStageFragment
    s.images[2].multisampled = false
    s.images[2].imageType = imageTypeArray
    s.images[2].sampleType = imageSampleTypeFloat
    s.images[2].wgslGroup1BindingN = 64
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[3].wgslGroup1BindingN = 80
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[4].wgslGroup1BindingN = 81
    s.imageSamplerPairs[0].stage = shaderStageFragment
    s.imageSamplerPairs[0].imageSlot = 2
    s.imageSamplerPairs[0].samplerSlot = 4
    s.imageSamplerPairs[1].stage = shaderStageFragment
    s.imageSamplerPairs[1].imageSlot = 1
    s.imageSamplerPairs[1].samplerSlot = 3
  else:
    discard

  makeShader(s)

proc createImpl(): pointer =
  let ctx = create(OpenglBackendContextObj)

  ctx.texEdges = allocImage()
  ctx.vertBuf = allocBuffer()
  ctx.shader = getShader()
  ctx.smpDummy = makeSampler(
    SamplerDesc(
      minFilter: filterNearest,
      mipmapFilter: filterNearest,
      wrapU: wrapDefault,
      wrapV: wrapDefault,
      label: "nvg.smpDummy",
    )
  )

  for idx in low(CallType) .. high(CallType):
    ctx.pipeline[idx] = allocPipeline()

  const dummyPixels = [color(1, 1, 1, 1)]

  ctx.texDummy = makeImage(
    ImageDesc(
      type: imageType2d,
      width: 1,
      height: 1,
      usage: ImageUsage(immutable: true),
      pixelFormat: pixelFormatRgba32f,
      numMipmaps: 1,
      label: "nvg.texDummy",
      data:
        ImageData(subimage: [[Range(addr: dummyPixels[0].addr, size: sizeof(Color))]]),
    )
  )

  ctx

proc destroyImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  destroyShader(ctx.shader)
  destroySampler(ctx.smpDummy)
  destroyImage(ctx.texEdges)
  destroyImage(ctx.texDummy)
  destroyBuffer(ctx.vertBuf)

  for idx in low(CallType) .. high(CallType):
    destroyPipeline(ctx.pipeline[idx])

  reset(ctx[])
  dealloc(ctx)

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.verts.setLen(0)
  ctx.edges.setLen(0)
  ctx.calls.setLen(0)
  ctx.uniforms.setLen(0)

proc viewportImpl(ctx: pointer, view: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  cancelImpl(ctx)

  ctx.vertexUniform.view = view

proc updateVertBuf(ctx: ptr OpenglBackendContextObj) =
  if ctx.vertBufSize < ctx.verts.len:
    if ctx.vertBufSize > 0:
      ctx.vertBuf.uninitBuffer()

    ctx.vertBufSize = int32(ctx.verts.len)

    ctx.vertBuf.initBuffer(
      BufferDesc(
        size: ctx.vertBufSize * sizeof(Vec4),
        usage: BufferUsage(vertexBuffer: true, streamUpdate: true),
        label: "nvg.vertBuf",
      )
    )

  ctx.vertBuf.updateBuffer(
    Range(addr: ctx.verts[0].addr, size: sizeof(Vec4) * ctx.vertBufSize)
  )

proc updateTexEdges(ctx: ptr OpenglBackendContextObj) =
  const TILE_IMAGE_WIDTH = 256

  let
    layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
    layerCount = block:
      let n = if (ctx.edges.len mod layerSize) > 0: 1 else: 0
      ctx.edges.len div layerSize + n

    size = int(ceil(float32(ctx.edges.len) / float32(layerSize))) * layerSize

  if capacity(ctx.edges) < size:
    ctx.edges.setLen(size)

  let
    data = Range(addr: ctx.edges[0].addr, size: size * sizeof(Vec4))
    imageData = ImageData(subimage: [[data]])

  if ctx.texLayerCount != layerCount:
    if ctx.texLayerCount > 0:
      ctx.texEdges.uninitImage()
    ctx.texLayerCount = int32(layerCount)

    ctx.texEdges.initImage(
      ImageDesc(
        type: imageTypeArray,
        width: TILE_IMAGE_WIDTH,
        height: TILE_IMAGE_WIDTH,
        usage: ImageUsage(dynamicUpdate: true),
        pixelFormat: pixelFormatRgba32f,
        numMipmaps: 0,
        numSlices: int32(layerCount),
        label: "nvg.texEdges",
      )
    )

  ctx.texEdges.updateImage(imageData)

proc combineBlend(blend: BlendObj): uint32 {.inline.} =
  uint32(blend.srcRGB) or (uint32(blend.dstRGB) shl 4) or (uint32(blend.srcAlpha) shl 8) or
    (uint32(blend.dstAlpha) shl 12)

proc updatePipeline(
    ctx: ptr OpenglBackendContextObj, callType: CallType, blend: BlendObj
) =
  const
    BLEND_MASK = uint32(1 shl 16 - 1)
    ACTIVE_MASK = uint32(1 shl 16)

  let
    oldBlend = ctx.blend[callType]
    newBlend = combineBlend(blend)

  if (oldBlend and BLEND_MASK) != newBlend:
    if (oldBlend and ACTIVE_MASK) > 0:
      ctx.pipeline[callType].uninitPipeline()
    ctx.blend[callType] = newBlend or ACTIVE_MASK

    let blendState = BlendState(
      enabled: true,
      srcFactorRgb: blend.srcRGB,
      dstFactorRgb: blend.dstRGB,
      opRgb: blendOpAdd,
      srcFactorAlpha: blend.srcAlpha,
      dstFactorAlpha: blend.dstAlpha,
      opAlpha: blendOpAdd,
    )

    let primitiveType =
      case callType
      of FillCall: primitiveTypeTriangleStrip
      of ConvexFillCall: primitiveTypeTriangleStrip
      of TrianglesCall: primitiveTypeTriangles

    initPipeline(
      ctx.pipeline[callType],
      PipelineDesc(
        shader: ctx.shader,
        layout: VertexLayoutState(
          attrs: [
            VertexAttrState(format: vertexFormatFloat2),
            VertexAttrState(format: vertexFormatFloat2),
          ]
        ),
        stencil: StencilState(enabled: false),
        colors: [ColorTargetState(writeMask: colorMaskRgba, blend: blendState)],
        primitive_type: primitiveType,
        indexType: indexTypeNone,
        cullMode: cullModeBack,
        faceWinding: faceWindingCcw,
        label: "nvg.pipeline",
      ),
    )

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  if ctx.verts.len > 0:
    ctx.updateVertBuf()
    ctx.updateTexEdges()

    var bindings = default(Bindings)

    for call in ctx.calls:
      ctx.updatePipeline(call.callType, call.blend)

      applyPipeline(ctx.pipeline[call.callType])
      applyUniforms(
        0, Range(addr: ctx.vertexUniform.addr, size: sizeof(ctx.vertexUniform))
      )

      let fillParams = [call.fillCount, call.fillOffset, 0, 0]
      applyUniforms(5, Range(addr: fillParams[0].addr, size: sizeof(fillParams)))

      applyUniforms(
        6,
        Range(
          addr: ctx.uniforms[call.uniformOffset].addr, size: sizeof(FragmentUniformObj)
        ),
      )

      bindings.vertexBuffers[0] = ctx.vertBuf

      bindings.images[1] = ctx.texDummy
      bindings.samplers[3] = ctx.smpDummy

      bindings.images[2] = ctx.texEdges
      bindings.samplers[4] = ctx.smpDummy

      applyBindings(bindings)

      draw(int32(call.triangleOffset), int32(call.triangleCount), 1)

proc newContext*(): ptr Context =
  createInternal(
    BackendContextParams(
      createImpl: createImpl,
      destroyImpl: destroyImpl,
      fillImpl: fillImpl,
      trianglesImpl: nil,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
