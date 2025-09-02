import pkg/sokol/gfx except Color

import ./context
import ./core
import ./glsl
import ./params
import ./renderdata

import std/math

const TILE_IMAGE_WIDTH = 256

type
  SokolBlend = object
    srcRGB: BlendFactor
    dstRGB: BlendFactor
    srcAlpha: BlendFactor
    dstAlpha: BlendFactor

  SokolTexture = ref object of Texture
    storage: seq[byte]
    pixels: ptr UncheckedArray[byte]
    texImage: Image
    texImageView: View
    smp: Sampler
    dirty: bool

  SokolBackendContextObj = object
    shader: Shader
    smpDummy: Sampler
    texDummy: Image
    texDummyView: View
    texEdge: Image
    texEdgeView: View
    texLayerCount: int32

    vertBuf: Buffer
    vertBufSize: int32

    blend: array[CallType, uint32]
    pipeline: array[CallType, Pipeline]

    viewBounds: Vec2
    renderData: RenderData

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
    s.views[1].texture.stage = shaderStageFragment
    s.views[1].texture.multisampled = false
    s.views[1].texture.imageType = imageType2d
    s.views[1].texture.sampleType = imageSampleTypeFloat
    s.views[2].texture.stage = shaderStageFragment
    s.views[2].texture.multisampled = false
    s.views[2].texture.imageType = imageTypeArray
    s.views[2].texture.sampleType = imageSampleTypeFloat
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.textureSamplerPairs[0].stage = shaderStageFragment
    s.textureSamplerPairs[0].viewSlot = 2
    s.textureSamplerPairs[0].samplerSlot = 4
    s.textureSamplerPairs[0].glslName = "edgeTex_smp2"
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 1
    s.textureSamplerPairs[1].samplerSlot = 3
    s.textureSamplerPairs[1].glslName = "imageTex_smp1"
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
    s.views[1].texture.stage = shaderStageFragment
    s.views[1].texture.multisampled = false
    s.views[1].texture.imageType = imageType2d
    s.views[1].texture.sampleType = imageSampleTypeFloat
    s.views[2].texture.stage = shaderStageFragment
    s.views[2].texture.multisampled = false
    s.views[2].texture.imageType = imageTypeArray
    s.views[2].texture.sampleType = imageSampleTypeFloat
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.textureSamplerPairs[0].stage = shaderStageFragment
    s.textureSamplerPairs[0].viewSlot = 2
    s.textureSamplerPairs[0].samplerSlot = 4
    s.textureSamplerPairs[0].glslName = "edgeTex_smp2"
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 1
    s.textureSamplerPairs[1].samplerSlot = 3
    s.textureSamplerPairs[1].glslName = "imageTex_smp1"
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
    s.uniformBlocks[5].hlslRegisterBN = 5
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].hlslRegisterBN = 6
    s.views[1].texture.stage = shaderStageFragment
    s.views[1].texture.multisampled = false
    s.views[1].texture.imageType = imageType2d
    s.views[1].texture.sampleType = imageSampleTypeFloat
    s.views[1].texture.hlslRegisterTN = 0
    s.views[2].texture.stage = shaderStageFragment
    s.views[2].texture.multisampled = false
    s.views[2].texture.imageType = imageTypeArray
    s.views[2].texture.sampleType = imageSampleTypeFloat
    s.views[2].texture.hlslRegisterTN = 1
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[3].hlslRegisterSN = 3
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[4].hlslRegisterSN = 4
    s.textureSamplerPairs[0].stage = shaderStageFragment
    s.textureSamplerPairs[0].viewSlot = 2
    s.textureSamplerPairs[0].samplerSlot = 4
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 1
    s.textureSamplerPairs[1].samplerSlot = 3
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
    s.uniformBlocks[5].wgslGroup0BindingN = 13
    s.uniformBlocks[6].stage = shaderStageFragment
    s.uniformBlocks[6].layout = uniformLayoutStd140
    s.uniformBlocks[6].size = 112
    s.uniformBlocks[6].wgslGroup0BindingN = 14
    s.views[1].texture.stage = shaderStageFragment
    s.views[1].texture.multisampled = false
    s.views[1].texture.imageType = imageType2d
    s.views[1].texture.sampleType = imageSampleTypeFloat
    s.views[1].texture.wgslGroup1BindingN = 64
    s.views[2].texture.stage = shaderStageFragment
    s.views[2].texture.multisampled = false
    s.views[2].texture.imageType = imageTypeArray
    s.views[2].texture.sampleType = imageSampleTypeFloat
    s.views[2].texture.wgslGroup1BindingN = 65
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[3].wgslGroup1BindingN = 66
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[4].wgslGroup1BindingN = 67
    s.textureSamplerPairs[0].stage = shaderStageFragment
    s.textureSamplerPairs[0].viewSlot = 2
    s.textureSamplerPairs[0].samplerSlot = 4
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 1
    s.textureSamplerPairs[1].samplerSlot = 3
  else:
    discard

  makeShader(s)

proc createImpl(): pointer =
  let ctx = create(SokolBackendContextObj)

  ctx.shader = getShader()
  ctx.vertBuf = allocBuffer()

  ctx.texEdge = makeImage(
    ImageDesc(
      type: imageTypeArray,
      width: TILE_IMAGE_WIDTH,
      height: TILE_IMAGE_WIDTH,
      usage: ImageUsage(dynamicUpdate: true),
      pixelFormat: pixelFormatRgba32f,
      numMipmaps: 0,
      numSlices: 0,
      label: "nvg.texEdge",
    )
  )

  ctx.texEdgeView = makeView(
    ViewDesc(
      texture: TextureViewDesc(
        image: ctx.texEdge
    )
  )
  )

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

  let
    data = [color(1, 1, 1, 1)]
    dataRange = Range(addr: data[0].addr, size: sizeof(Color))

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
    ImageData(subimage: [[dataRange]]),
  )
  )

  ctx.texDummyView = makeView(
    ViewDesc(
      texture: TextureViewDesc(
        image: ctx.texDummy
    )
  )
  )

  ctx

proc destroyImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  destroyShader(ctx.shader)
  destroySampler(ctx.smpDummy)
  destroyImage(ctx.texEdge)
  destroyImage(ctx.texDummy)
  destroyView(ctx.texEdgeView)
  destroyView(ctx.texDummyView)
  destroyBuffer(ctx.vertBuf)

  for idx in low(CallType) .. high(CallType):
    destroyPipeline(ctx.pipeline[idx])

  reset(ctx[])
  dealloc(ctx)

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  ctx.renderData.clear()

proc viewportImpl(ctx: pointer, viewBounds: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  ctx.viewBounds = viewBounds
  cancelImpl(ctx)

proc updateVertBuf(ctx: ptr SokolBackendContextObj) =
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
    Range(addr: ctx.renderData.verts[0].addr, size: sizeof(Vec4) *
        ctx.vertBufSize)
  )

proc updateTexEdges(ctx: ptr SokolBackendContextObj) =
  let
    layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
    layerCount = block:
      let n = if (ctx.renderData.edges.len mod layerSize) > 0: 1 else: 0
      ctx.renderData.edges.len div layerSize + n

    size = int(ceil(float32(ctx.renderData.edges.len) / float32(layerSize))) * layerSize

  if capacity(ctx.renderData.edges) < size:
    ctx.renderData.edges.setLen(size)

  if ctx.texLayerCount != layerCount:
    ctx.texEdge.uninitImage()
    ctx.texEdgeView.uninitView()

    ctx.texLayerCount = int32(layerCount)

    ctx.texEdge.initImage(
      ImageDesc(
        type: imageTypeArray,
        width: TILE_IMAGE_WIDTH,
        height: TILE_IMAGE_WIDTH,
        usage: ImageUsage(dynamicUpdate: true),
        pixelFormat: pixelFormatRgba32f,
        numMipmaps: 0,
        numSlices: int32(layerCount),
        label: "nvg.texEdge",
      )
    )

    ctx.texEdgeView.initView(
      ViewDesc(
        texture: TextureViewDesc(
          image: ctx.texEdge
      )
    )
    )

  let data = Range(addr: ctx.renderData.edges[0].addr, size: size * sizeof(Vec4))
  ctx.texEdge.updateImage(ImageData(subimage: [[data]]))

proc toSokolBlend(op: CompositeOperation): SokolBlend {.inline.} =
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
  SokolBlend(
    srcRGB: blendOp.src,
    dstRGB: blendOp.dst,
    srcAlpha: blendOp.src,
    dstAlpha: blendOp.dst,
  )

proc updatePipeline(
    ctx: ptr SokolBackendContextObj, callType: CallType,
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

    let blend = toSokolBlend(blend)

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
        primitiveType: primitiveType,
        indexType: indexTypeNone,
        cullMode: cullModeBack,
        faceWinding: faceWindingCcw,
        label: "nvg.pipeline",
      ),
    )

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    contourFlags: set[ContourFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)
  ctx.renderData.fillCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    contourFlags,
    bounds,
    contours,
  )

proc trianglesImpl(
  ctx: pointer,
  paint: Paint,
  compositeOperation: CompositeOperation,
  verts: openArray[Vec4],
) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)
  ctx.renderData.trianglesCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    verts
  )

proc toSokolPixelFormat(typ: TextureType): PixelFormat =
  case typ
    of TextureRgba:
      pixelFormatRgba32f

    of TextureAlpha:
      pixelFormatR8

    of TextureFloat:
      pixelFormatR32f

proc createTextureImpl(ctx: pointer, typ: TextureType, w, h: int32,
    imageFlags: set[ImageFlags], data: pointer): ImageId =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  var tex = SokolTexture()
  tex.width = w
  tex.height = h
  tex.typ = typ
  tex.imageFlags = imageFlags

  var
    wrapX = wrapClampToEdge
    wrapY = wrapClampToEdge
    minFilter = filterDefault
    magFilter = filterDefault
    mipmapFilter = filterDefault

    dataRange = default(Range)
    imageUsage = default(ImageUsage)

  if ImageRepeatX in imageFlags:
    wrapX = wrapRepeat

  if ImageRepeatY in imageFlags:
    wrapY = wrapRepeat

  if ImageNearest in imageFlags:
    minFilter = filterNearest
    magFilter = filterNearest
    mipmapFilter = filterNearest
  else:
    minFilter = filterLinear
    magFilter = filterLinear
    mipmapFilter = filterLinear

  if ImageGenerateMipmaps in imageFlags:
    minFilter = filterDefault
  else:
    mipmapFilter = filterDefault

  if not data.isNil and ImageGenerateMipmaps in imageFlags:
    imageUsage.immutable = true
  else:
    imageUsage.dynamicUpdate = true

  let
    size = w * h * typ.bytePerPixel

  if ImageExternalStorage in imageFlags:
    tex.pixels = cast[ptr UncheckedArray[byte]](data)
  else:
    tex.storage.setLenUninit(size)
    tex.pixels = cast[ptr UncheckedArray[byte]](tex.storage[0].addr)

    if not data.isNil:
      copyMem(tex.pixels, data, size)

  if not tex.pixels.isNil and imageUsage.immutable:
    dataRange = Range(addr: tex.pixels[0].addr, size: size)

  tex.texImage = makeImage(
      ImageDesc(
        type: imageType2d,
        width: w,
        height: h,
        usage: imageUsage,
        data: ImageData(subimage: [[dataRange]]),
        pixelFormat: typ.toSokolPixelFormat,
        numMipmaps: 1,
        label: "nvg.image",
    )
  )

  tex.smp = makeSampler(
    SamplerDesc(
      minFilter: minFilter,
      magFilter: magFilter,
      mipmapFilter: mipmapFilter,
      wrapU: wrapX,
      wrapV: wrapY,
    )
  )

  tex.texImageView = makeView(
    ViewDesc(
      texture: TextureViewDesc(
        image: tex.texImage
    )
  )
  )

  ctx.renderData.addTexture(tex)

proc updateTexture(tex: SokolTexture, x, y, w, h, strideBytes: int32,
    data: ptr UncheckedArray[byte]) =
  let
    bytePerPixel = tex.typ.bytePerPixel
    lineBytes1 = tex.width * bytePerPixel
    lineBytes2 = w * bytePerPixel

    offset = x * bytePerPixel + y * lineBytes1
    dstPixelBytes = cast[ptr UncheckedArray[byte]](tex.pixels[offset].addr)

  for idx in 0 ..< h:
    copyMem(dstPixelBytes[idx * lineBytes1].addr, data[idx * strideBytes].addr, lineBytes2)

proc updateTextureImpl(ctx: pointer, imageId: ImageId, x, y, w, h,
    strideBytes: int32, data: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = SokolTexture(tex)

    tex.dirty = true
    tex.updateTexture(x, y, w, h, strideBytes, cast[
        ptr UncheckedArray[byte]](data))

proc markTextureDirtyImpl(ctx: pointer, imageId: ImageId, x, y, w, h: int32) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = SokolTexture(tex)

    if ImageExternalStorage in tex.imageFlags and not tex.pixels.isNil:
      discard

    tex.dirty = true

proc getTextureSizeImpl(ctx: pointer, imageId: ImageId): Vec2 =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    result = vec2(float32(tex.width), float32(tex.height))

proc deleteTextureImpl(ctx: pointer, imageId: ImageId) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = SokolTexture(tex)

    destroySampler(tex.smp)
    destroyImage(tex.texImage)

    ctx.renderData.removeTexture(imageId)

proc updateTexImage(ctx: ptr SokolBackendContextObj, tex: SokolTexture) =
  let
    data = Range(addr: tex.pixels[0].addr, size: tex.width * tex.height *
        tex.typ.bytePerPixel)

  tex.texImage.updateImage(ImageData(subimage: [[data]]))

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  if ctx.renderData.verts.len > 0:
    ctx.updateVertBuf()

    if ctx.renderData.edges.len > 0:
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

      if call.texture.isNil:
        bindings.views[1] = ctx.texDummyView
        bindings.samplers[3] = ctx.smpDummy
      else:
        let tex = SokolTexture(call.texture)
        if tex.dirty:
          ctx.updateTexImage(tex)
          tex.dirty = false

        bindings.views[1] = tex.texImageView
        bindings.samplers[3] = tex.smp

      bindings.views[2] = ctx.texEdgeView
      bindings.samplers[4] = ctx.smpDummy

      applyBindings(bindings)

      draw(int32(call.triangleOffset), int32(call.triangleCount), 1)

proc newContext*(): Context =
  createInternal(
    BackendContextParams(
      createImpl: createImpl,
      destroyImpl: destroyImpl,
      fillImpl: fillImpl,
      trianglesImpl: trianglesImpl,
      createTextureImpl: createTextureImpl,
      updateTextureImpl: updateTextureImpl,
      markTextureDirtyImpl: markTextureDirtyImpl,
      getTextureSizeImpl: getTextureSizeImpl,
      deleteTextureImpl: deleteTextureImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
