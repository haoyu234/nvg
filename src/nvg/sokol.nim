import pkg/sokol/gfx except Color

import ./context
import ./core
import ./glsl
import ./params
import ./renderdata

import std/math

type
  Blend = object
    srcRGB: BlendFactor
    dstRGB: BlendFactor
    srcAlpha: BlendFactor
    dstAlpha: BlendFactor

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

    viewBounds: Vec2
    renderData: RenderData

proc toBlend(op: CompositeOperation): Blend {.inline.} =
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
  Blend(
    srcRGB: blendOp.src,
    dstRGB: blendOp.dst,
    srcAlpha: blendOp.src,
    dstAlpha: blendOp.dst,
  )

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    contourFlags: set[ContourFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  ctx.renderData.buildCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    contourFlags,
    bounds,
    contours,
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

  ctx.renderData.clear()

proc viewportImpl(ctx: pointer, viewBounds: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.viewBounds = viewBounds
  cancelImpl(ctx)

proc updateVertBuf(ctx: ptr OpenglBackendContextObj) =
  if ctx.vertBufSize < ctx.renderData.verts.len:
    if ctx.vertBufSize > 0:
      ctx.vertBuf.uninitBuffer()

    ctx.vertBufSize = int32(ctx.renderData.verts.len)

    ctx.vertBuf.initBuffer(
      BufferDesc(
        size: ctx.vertBufSize * sizeof(Vec4),
        usage: BufferUsage(vertexBuffer: true, streamUpdate: true),
        label: "nvg.vertBuf",
      )
    )

  ctx.vertBuf.updateBuffer(
    Range(addr: ctx.renderData.verts[0].addr, size: sizeof(Vec4) * ctx.vertBufSize)
  )

proc updateTexEdges(ctx: ptr OpenglBackendContextObj) =
  const TILE_IMAGE_WIDTH = 256

  let
    layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
    layerCount = block:
      let n = if (ctx.renderData.edges.len mod layerSize) > 0: 1 else: 0
      ctx.renderData.edges.len div layerSize + n

    size = int(ceil(float32(ctx.renderData.edges.len) / float32(layerSize))) * layerSize

  if capacity(ctx.renderData.edges) < size:
    ctx.renderData.edges.setLen(size)

  let
    data = Range(addr: ctx.renderData.edges[0].addr, size: size * sizeof(Vec4))
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

proc updatePipeline(
    ctx: ptr OpenglBackendContextObj, callType: CallType,
        blend: CompositeOperation
) =
  const
    BLEND_MASK = uint32(1 shl 16 - 1)
    ACTIVE_MASK = uint32(1 shl 16)

  let
    oldBlend = ctx.blend[callType]
    newBlend = uint32(blend)

  if (oldBlend and BLEND_MASK) != newBlend:
    if (oldBlend and ACTIVE_MASK) > 0:
      ctx.pipeline[callType].uninitPipeline()
    ctx.blend[callType] = newBlend or ACTIVE_MASK

    let blend = toBlend(blend)

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

  if ctx.renderData.verts.len > 0:
    ctx.updateVertBuf()
    ctx.updateTexEdges()

    var bindings = default(Bindings)

    for call in ctx.renderData.calls:
      ctx.updatePipeline(call.callType, call.blend)

      applyPipeline(ctx.pipeline[call.callType])

      let viewBounds = [ctx.viewBounds[0], ctx.viewBounds[1], 0, 0]
      applyUniforms(
        0, Range(addr: viewBounds[0].addr, size: sizeof(viewBounds))
      )

      let fillParams = [call.fillCount, call.fillOffset, 0, 0]
      applyUniforms(5, Range(addr: fillParams[0].addr, size: sizeof(fillParams)))

      applyUniforms(
        6,
        Range(
          addr: ctx.renderData.uniforms[call.uniformOffset].addr, size: sizeof(FragmentUniform)
        ),
      )

      bindings.vertexBuffers[0] = ctx.vertBuf

      bindings.images[1] = ctx.texDummy
      bindings.samplers[3] = ctx.smpDummy

      bindings.images[2] = ctx.texEdges
      bindings.samplers[4] = ctx.smpDummy

      applyBindings(bindings)

      draw(int32(call.triangleOffset), int32(call.triangleCount), 1)

proc newContext*(): Context =
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
