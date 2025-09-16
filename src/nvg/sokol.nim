import pkg/sokol/gfx except Color

import ./context
import ./core
import ./glsl
import ./params
import ./renderdata

import std/math
import std/tables

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

  SokolImage = object
    tex: Image
    view: View
    layerCount: int32

  SokolBackendContextObj = object
    shader: Shader
    smpDummy: Sampler
    texDummy: Image
    texDummyView: View

    texEdge: SokolImage
    texVert: SokolImage

    vertDummyBuf: Buffer
    instanceBuf: Buffer
    instanceBufSize: int32

    blend: uint32
    pipeline: Pipeline

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
    s.attrs[0].base_type = shaderAttrBaseTypeSint
    s.attrs[0].glslName = "v_idx"
    s.attrs[1].base_type = shaderAttrBaseTypeSint
    s.attrs[1].glslName = "v_fillCount"
    s.attrs[2].base_type = shaderAttrBaseTypeSint
    s.attrs[2].glslName = "v_fillOffset"
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].glslUniforms[0].type = uniformTypeFloat2
    s.uniformBlocks[0].glslUniforms[0].arrayCount = 0
    s.uniformBlocks[0].glslUniforms[0].glslName = "_68.viewSize"
    s.uniformBlocks[0].glslUniforms[1].type = uniformTypeInt
    s.uniformBlocks[0].glslUniforms[1].arrayCount = 0
    s.uniformBlocks[0].glslUniforms[1].glslName = "_68.triangleOffset"
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 96
    s.uniformBlocks[5].glslUniforms[0].type = uniformTypeFloat4
    s.uniformBlocks[5].glslUniforms[0].arrayCount = 6
    s.uniformBlocks[5].glslUniforms[0].glslName = "params"
    s.views[1].texture.stage = shaderStageFragment
    s.views[1].texture.multisampled = false
    s.views[1].texture.imageType = imageType2d
    s.views[1].texture.sampleType = imageSampleTypeFloat
    s.views[2].texture.stage = shaderStageFragment
    s.views[2].texture.multisampled = false
    s.views[2].texture.imageType = imageTypeArray
    s.views[2].texture.sampleType = imageSampleTypeFloat
    s.views[6].texture.stage = shaderStageVertex
    s.views[6].texture.multisampled = false
    s.views[6].texture.imageType = imageTypeArray
    s.views[6].texture.sampleType = imageSampleTypeFloat
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[7].stage = shaderStageVertex
    s.samplers[7].samplerType = samplerTypeFiltering
    s.textureSamplerPairs[0].stage = shaderStageVertex
    s.textureSamplerPairs[0].viewSlot = 6
    s.textureSamplerPairs[0].samplerSlot = 7
    s.textureSamplerPairs[0].glslName = "vertTex_smp3"
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 2
    s.textureSamplerPairs[1].samplerSlot = 4
    s.textureSamplerPairs[1].glslName = "edgeTex_smp2"
    s.textureSamplerPairs[2].stage = shaderStageFragment
    s.textureSamplerPairs[2].viewSlot = 1
    s.textureSamplerPairs[2].samplerSlot = 3
    s.textureSamplerPairs[2].glslName = "imageTex_smp1"
  of backendD3d11:
    s.vertexFunc.source = cast[cstring](vsSourceHlsl5[0].addr)
    s.vertexFunc.d3d11Target = "vs_5_0"
    s.vertexFunc.entry = "main"
    s.fragmentFunc.source = cast[cstring](fsSourceHlsl5[0].addr)
    s.fragmentFunc.d3d11Target = "ps_5_0"
    s.fragmentFunc.entry = "main"
    s.attrs[0].base_type = shaderAttrBaseTypeSint
    s.attrs[0].hlslSemName = "TEXCOORD"
    s.attrs[0].hlslSemIndex = 0
    s.attrs[1].base_type = shaderAttrBaseTypeSint
    s.attrs[1].hlslSemName = "TEXCOORD"
    s.attrs[1].hlslSemIndex = 1
    s.attrs[2].base_type = shaderAttrBaseTypeSint
    s.attrs[2].hlslSemName = "TEXCOORD"
    s.attrs[2].hlslSemIndex = 2
    s.uniformBlocks[0].stage = shaderStageVertex
    s.uniformBlocks[0].layout = uniformLayoutStd140
    s.uniformBlocks[0].size = 16
    s.uniformBlocks[0].hlslRegisterBN = 0
    s.uniformBlocks[5].stage = shaderStageFragment
    s.uniformBlocks[5].layout = uniformLayoutStd140
    s.uniformBlocks[5].size = 96
    s.uniformBlocks[5].hlslRegisterBN = 5
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
    s.views[6].texture.stage = shaderStageVertex
    s.views[6].texture.multisampled = false
    s.views[6].texture.imageType = imageTypeArray
    s.views[6].texture.sampleType = imageSampleTypeFloat
    s.views[6].texture.hlslRegisterTN = 0
    s.samplers[3].stage = shaderStageFragment
    s.samplers[3].samplerType = samplerTypeFiltering
    s.samplers[3].hlslRegisterSN = 3
    s.samplers[4].stage = shaderStageFragment
    s.samplers[4].samplerType = samplerTypeFiltering
    s.samplers[4].hlslRegisterSN = 4
    s.samplers[7].stage = shaderStageVertex
    s.samplers[7].samplerType = samplerTypeFiltering
    s.samplers[7].hlslRegisterSN = 7
    s.textureSamplerPairs[0].stage = shaderStageVertex
    s.textureSamplerPairs[0].viewSlot = 6
    s.textureSamplerPairs[0].samplerSlot = 7
    s.textureSamplerPairs[1].stage = shaderStageFragment
    s.textureSamplerPairs[1].viewSlot = 2
    s.textureSamplerPairs[1].samplerSlot = 4
    s.textureSamplerPairs[2].stage = shaderStageFragment
    s.textureSamplerPairs[2].viewSlot = 1
    s.textureSamplerPairs[2].samplerSlot = 3
  else: discard

  makeShader(s)

proc initImage(image: var SokolImage) =
  image.tex = allocImage()
  image.view = allocView()
  image.layerCount = -1

proc updateImage(image: var SokolImage, name: cstring, data: var seq[Vec4]) =
  if data.len <= 0 and image.layerCount >= 0:
    return

  let
    layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
    layerCount = block:
      let n = if (data.len mod layerSize) > 0: 1 else: 0
      data.len div layerSize + n

    size = int32(ceil(float32(data.len) / float32(layerSize))) * layerSize

  if capacity(data) < size:
    data.setLen(size)

  if image.layerCount != layerCount:
    if image.layerCount > 0:
      image.tex.uninitImage()
      image.view.uninitView()

    image.layerCount = int32(layerCount)

    image.tex.initImage(
      ImageDesc(
        type: imageTypeArray,
        width: TILE_IMAGE_WIDTH,
        height: TILE_IMAGE_WIDTH,
        usage: ImageUsage(dynamicUpdate: true),
        pixelFormat: pixelFormatRgba32f,
        numMipmaps: 0,
        numSlices: int32(layerCount),
        label: name,
      )
    )

    image.view.initView(
      ViewDesc(
        texture: TextureViewDesc(
          image: image.tex
      )
    )
    )

  if data.len > 0:
    let data = Range(addr: data[0].addr, size: size * sizeof(Vec4))
    image.tex.updateImage(ImageData(subimage: [[data]]))

proc destroyImage(image: SokolImage) =
  destroyView(image.view)
  destroyImage(image.tex)

proc initImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  ctx.shader = getShader()
  ctx.vertDummyBuf = allocBuffer()
  ctx.instanceBuf = allocBuffer()
  ctx.pipeline = allocPipeline()

  ctx.texEdge.initImage()
  ctx.texVert.initImage()

  ctx.smpDummy = makeSampler(
    SamplerDesc(
      minFilter: filterDefault,
      mipmapFilter: filterDefault,
      wrapU: wrapClampToEdge,
      wrapV: wrapClampToEdge,
      label: "nvg.smpDummy",
    )
  )

  const
    verts = [int32(0), 1, 2, 3, 4, 5]

  ctx.vertDummyBuf.initBuffer(
    BufferDesc(
      size: sizeof(int32) * len(verts),
      usage: BufferUsage(vertexBuffer: true, immutable: true),
      label: "nvg.vertDummyBuf",
      data: Range(addr: verts[0].addr, size: sizeof(int32) * len(verts)),
    )
  )

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

proc destroyImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  destroyShader(ctx.shader)
  destroySampler(ctx.smpDummy)
  destroyImage(ctx.texDummy)
  destroyView(ctx.texDummyView)
  destroyBuffer(ctx.vertDummyBuf)
  destroyBuffer(ctx.instanceBuf)

  ctx.texEdge.destroyImage()
  ctx.texVert.destroyImage()

  for image in ctx.renderData.images.values():
    let tex = SokolTexture(image)
    destroyView(tex.texImageView)
    destroyImage(tex.texImage)
    destroySampler(tex.smp)

  destroyPipeline(ctx.pipeline)

  reset(ctx[])
  dealloc(ctx)

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  ctx.renderData.clear()

proc viewportImpl(ctx: pointer, viewBounds: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  ctx.viewBounds = viewBounds
  cancelImpl(ctx)

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
    ctx: ptr SokolBackendContextObj, blend: CompositeOperation
) =
  const
    BLEND_MASK = uint32(1 shl 16 - 1)
    ACTIVE_MASK = uint32(1 shl 16)

  let
    oldBlend = ctx.blend
    newBlend = uint32(blend)

  if (oldBlend and BLEND_MASK) != newBlend:
    if (oldBlend and ACTIVE_MASK) > 0:
      ctx.pipeline.uninitPipeline()
    ctx.blend = newBlend or ACTIVE_MASK

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

    initPipeline(
      ctx.pipeline,
      PipelineDesc(
        shader: ctx.shader,
        layout: VertexLayoutState(
          buffers: [
            VertexBufferLayoutState(),
            VertexBufferLayoutState(stepFunc: vertexStepPerInstance,
                stepRate: 1),
      ],
      attrs: [
        VertexAttrState(format: vertexFormatInt, bufferIndex: 0),
        VertexAttrState(format: vertexFormatInt, bufferIndex: 1),
        VertexAttrState(format: vertexFormatInt, bufferIndex: 1),
      ]
      ),
      stencil: StencilState(enabled: false),
      colors: [ColorTargetState(writeMask: colorMaskRgba, blend: blendState)],
      primitiveType: primitiveTypeTriangles,
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
    renderFlags: set[RenderFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)
  ctx.renderData.fillCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    renderFlags,
    bounds,
    contours,
  )

proc trianglesImpl(
  ctx: pointer,
  paint: Paint,
  compositeOperation: CompositeOperation,
  renderFlags: set[RenderFlags],
  verts: openArray[Vec4],
) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)
  ctx.renderData.trianglesCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    renderFlags,
    verts,
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

proc updateTexture(tex: SokolTexture, x, y, w, h, stride: int32,
    data: ptr UncheckedArray[byte]) =
  let
    bytePerPixel = tex.typ.bytePerPixel
    offset = x + y * tex.width
    lineBytes = w * bytePerPixel
    sourceStrideBytes = stride * bytePerPixel
    destinationStrideBytes = tex.width * bytePerPixel
    destinationPixels = cast[ptr UncheckedArray[byte]](tex.storage[offset *
        bytePerPixel].addr)

  for idx in 0 ..< h:
    copyMem(destinationPixels[idx * destinationStrideBytes].addr, data[idx *
        sourceStrideBytes].addr, lineBytes)

proc updateTextureImpl(ctx: pointer, imageId: ImageId, x, y, w, h,
    stride: int32, data: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = SokolTexture(tex)

    tex.dirty = true
    tex.updateTexture(x, y, w, h, stride, cast[
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

proc updateInstanceBuf(ctx: ptr SokolBackendContextObj) =
  if ctx.instanceBufSize < ctx.renderData.instances.len:
    if ctx.instanceBufSize > 0:
      ctx.instanceBuf.uninitBuffer()

    const defaultSize = int32(128)
    ctx.instanceBufSize = max(defaultSize, int32(ctx.renderData.instances.len))

    ctx.instanceBuf.initBuffer(
      BufferDesc(
        size: ctx.instanceBufSize * sizeof(InstanceParam),
        usage: BufferUsage(vertexBuffer: true, streamUpdate: true),
        label: "nvg.instanceBuf",
      )
    )

  if ctx.renderData.instances.len > 0:
    ctx.instanceBuf.updateBuffer(
      Range(
        addr: ctx.renderData.instances[0].addr,
        size: ctx.renderData.instances.len * sizeof(InstanceParam),
      )
    )

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr SokolBackendContextObj](ctx)

  if ctx.renderData.verts.len > 0:
    ctx.updateInstanceBuf()
    ctx.texEdge.updateImage("nvg.texEdge", ctx.renderData.edges)
    ctx.texVert.updateImage("nvg.texVert", ctx.renderData.verts)

    var bindings = default(Bindings)

    for call in ctx.renderData.calls:
      ctx.updatePipeline(call.blend)

      applyPipeline(ctx.pipeline)

      type
        VertexParam = object
          view: Vec2
          triangleOffset: int32
          pad: array[4, uint8]

      var param = default(VertexParam)
      param.view = ctx.viewBounds
      param.triangleOffset = call.triangleOffset

      applyUniforms(
        0, Range(addr: param.addr, size: sizeof(param))
      )

      applyUniforms(
        5,
        Range(
          addr: ctx.renderData.uniforms[call.uniformIndex].addr,
          size: sizeof(UniformParam)
        ),
      )

      bindings.vertexBuffers[0] = ctx.vertDummyBuf
      bindings.vertexBuffers[1] = ctx.instanceBuf
      bindings.vertexBufferOffsets[0] = 0
      bindings.vertexBufferOffsets[1] = call.instanceOffset * int32(sizeof(InstanceParam))

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

      bindings.views[2] = ctx.texEdge.view
      bindings.samplers[4] = ctx.smpDummy

      bindings.views[6] = ctx.texVert.view
      bindings.samplers[7] = ctx.smpDummy

      applyBindings(bindings)

      draw(0, 6, call.instanceCount)

proc newContext*(): Context =
  let ctx = create(SokolBackendContextObj)

  createInternal(
    ctx,
    BackendContextParams(
      initImpl: initImpl,
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
