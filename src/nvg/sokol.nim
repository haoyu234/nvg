import std/tables

import pkg/sokol/gfx except Color, Image, ImageInfo, PixelFormat

import ./backend
import ./core
import ./draw_list
import ./math
import ./sokol_gen
import ./tracy

const
  NVG_DEFAULT_STORAGE_CAPACITY = 32 * 1024

type
  SokolBlend = object
    srcRGB: BlendFactor
    dstRGB: BlendFactor
    srcAlpha: BlendFactor
    dstAlpha: BlendFactor

  SokolTexture = ref SokolTextureObj
  SokolTextureObj = object
    image: Image
    imageFlags: set[ImageFlags]
    texImage: gfx.Image
    texImageView: View
    smp: Sampler
    dirty: bool

  StorageUsage = enum
    StorageUsageVertexBuffer
    StorageUsageStorageBuffer

  SokolStorage = object
    buffer: gfx.Buffer
    view: View
    cap: int32
    name: cstring
    usage: StorageUsage

  SokolBackendContext = ref SokolBackendContextObj
  SokolBackendContextObj = object of BackendContext
    size: Vec2

    smpDummy: Sampler
    texDummy: gfx.Image
    texDummyView: View

    pathShader: Shader
    pathPipeline: Pipeline
    pathBlend: uint32

    glyphShader: Shader
    glyphPipeline: Pipeline
    glyphBlend: uint32

    drawList: DrawList

    edges: SokolStorage
    paths: SokolStorage
    glyphs: SokolStorage
    transforms: SokolStorage
    textures: Table[ImageId, SokolTexture]

    initial: bool
    supportDrawBaseVertex: bool
    supportDrawBaseInstance: bool

proc `=destroy`(tex: var SokolTextureObj) =
  destroyView(tex.texImageView)
  destroyImage(tex.texImage)
  destroySampler(tex.smp)

  `=destroy`(tex.image)
  `=destroy`(tex.imageFlags)

proc `=destroy`(s: SokolStorage) =
  destroyView(s.view)
  destroyBuffer(s.buffer)

proc `=destroy`(ctx: var SokolBackendContextObj) =
  destroyShader(ctx.pathShader)
  destroySampler(ctx.smpDummy)
  destroyImage(ctx.texDummy)
  destroyView(ctx.texDummyView)
  destroyPipeline(ctx.pathPipeline)
  destroyShader(ctx.glyphShader)
  destroyPipeline(ctx.glyphPipeline)

  `=destroy`(ctx.drawList)

  `=destroy`(ctx.edges)
  `=destroy`(ctx.paths)
  `=destroy`(ctx.glyphs)
  `=destroy`(ctx.transforms)
  `=destroy`(ctx.textures)

proc initStorage(s: var SokolStorage, name: cstring,
    usage: StorageUsage) {.inline.} =
  s.buffer = allocBuffer()
  s.name = name
  s.usage = usage

proc initIfNeeded(ctx: SokolBackendContext) =
  if ctx.initial:
    return

  ctx.initial = true

  let
    backend = queryBackend()
    pathShader = makeShader(getPathShaderDesc(backend))
    glyphShader = makeShader(getGlyphShaderDesc(backend))

  ctx.pathShader = pathShader
  ctx.pathPipeline = allocPipeline()
  ctx.glyphShader = glyphShader
  ctx.glyphPipeline = allocPipeline()
  ctx.glyphBlend = 0

  ctx.edges.initStorage("nvg.edges", StorageUsageStorageBuffer)
  ctx.paths.initStorage("nvg.paths", StorageUsageVertexBuffer)
  ctx.glyphs.initStorage("nvg.glyphs", StorageUsageVertexBuffer)
  ctx.transforms.initStorage("nvg.transforms", StorageUsageStorageBuffer)

  ctx.smpDummy = makeSampler(
    SamplerDesc(
      minFilter: filterDefault,
      magFilter: filterDefault,
      mipmapFilter: filterDefault,
      wrapU: wrapClampToEdge,
      wrapV: wrapClampToEdge,
      label: "nvg.smpDummy",
    )
  )

  let
    data = [color(255, 255, 255, 255)]
    dataRange = Range(addr: data[0].addr, size: sizeof(Color))

  ctx.texDummy = makeImage(
    ImageDesc(
      type: imageType2d,
      width: 1,
      height: 1,
      usage: ImageUsage(immutable: true),
      pixelFormat: pixelFormatRgba8,
      numMipmaps: 1,
      label: "nvg.texDummy",
      data: ImageData(mipLevels: [dataRange]),
    )
  )

  ctx.texDummyView = makeView(
    ViewDesc(
      texture: TextureViewDesc(
        image: ctx.texDummy
    )
  )
  )

  let
    features = queryFeatures()
  ctx.supportDrawBaseVertex = features.drawBaseVertex
  ctx.supportDrawBaseInstance = features.drawBaseInstance

proc reserveStorage(s: var SokolStorage, needBytes: int32) =
  var
    cap = s.cap * 2
  if cap < int32(needBytes):
    cap = int32(needBytes)

  if s.cap > 0:
    s.buffer.uninitBuffer()
    if s.usage == StorageUsageStorageBuffer:
      s.view.uninitView()

  s.cap = cap
  s.buffer.initBuffer(
    BufferDesc(
      size: cap,
      usage: BufferUsage(
        vertexBuffer: s.usage == StorageUsageVertexBuffer,
        storageBuffer: s.usage == StorageUsageStorageBuffer,
        dynamicUpdate: true,
    ),
    label: s.name,
  )
  )
  if s.usage == StorageUsageStorageBuffer:
    s.view = makeView(
      ViewDesc(
        storageBuffer: BufferViewDesc(
          buffer: s.buffer,
          offset: 0,
      )
    )
    )

proc updateStorage[T: Vec2 | Vec4 | Color | object](s: var SokolStorage,
    data: var seq[T]) =
  if data.len <= 0:
    return

  let byteSize = int32(data.len * sizeof(T))
  if byteSize > s.cap:
    s.reserveStorage(max(byteSize, NVG_DEFAULT_STORAGE_CAPACITY))

  s.buffer.updateBuffer(
    Range(addr: data[0].addr, size: byteSize)
  )

proc addTexture(ctx: SokolBackendContext, imageId: ImageId,
    tex: SokolTexture) {.inline.} =
  ctx.textures[imageId] = tex

proc getTexture(ctx: SokolBackendContext,
    imageId: ImageId): SokolTexture {.inline.} =
  ctx.textures.withValue(imageId, tex):
    result = tex[]

proc deleteTexture(ctx: SokolBackendContext,
    imageId: ImageId) {.inline.} =
  ctx.textures.del(imageId)

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

proc updatePathPipeline(ctx: SokolBackendContext, blend: CompositeOperation) =
  const
    BLEND_MASK = uint32(1 shl 16 - 1)
    ACTIVE_MASK = uint32(1 shl 16)

  let
    oldBlend = ctx.pathBlend
    newBlend = uint32(blend)

  if (oldBlend and BLEND_MASK) != newBlend:
    if (oldBlend and ACTIVE_MASK) > 0:
      ctx.pathPipeline.uninitPipeline()
    ctx.pathBlend = newBlend or ACTIVE_MASK

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
      ctx.pathPipeline,
      PipelineDesc(
        shader: ctx.pathShader,
        layout: VertexLayoutState(
          buffers: [
            VertexBufferLayoutState(
              stride: int32(sizeof(PathInstanceParam)),
              stepFunc: vertexStepPerInstance,
              stepRate: 1,
      ),
    ],
          attrs: [
            VertexAttrState(format: vertexFormatUint, bufferIndex: 0),
            VertexAttrState(format: vertexFormatUint, bufferIndex: 0),
            VertexAttrState(format: vertexFormatFloat4, bufferIndex: 0),
            VertexAttrState(format: vertexFormatUbyte4n, bufferIndex: 0),
            VertexAttrState(format: vertexFormatUbyte4n, bufferIndex: 0),
            VertexAttrState(format: vertexFormatUbyte4n, bufferIndex: 0),
      ]
    ),
        indexType: indexTypeNone,
        stencil: StencilState(enabled: false),
        colors: [
          ColorTargetState(
            writeMask: colorMaskRgba,
            blend: blendState,
      ),
    ],
        primitiveType: primitiveTypeTriangleStrip,
        label: "nvg.pathPipeline",
      ),
    )

proc updateGlyphPipeline(ctx: SokolBackendContext, blend: CompositeOperation) =
  const
    BLEND_MASK = uint32(1 shl 16 - 1)
    ACTIVE_MASK = uint32(1 shl 16)

  let
    oldBlend = ctx.glyphBlend
    newBlend = uint32(blend)

  if (oldBlend and BLEND_MASK) != newBlend:
    if (oldBlend and ACTIVE_MASK) > 0:
      ctx.glyphPipeline.uninitPipeline()
    ctx.glyphBlend = newBlend or ACTIVE_MASK

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
      ctx.glyphPipeline,
      PipelineDesc(
        shader: ctx.glyphShader,
        layout: VertexLayoutState(
          buffers: [
            VertexBufferLayoutState(stepFunc: vertexStepPerInstance,
                stepRate: 1),
      ],
      attrs: [
        VertexAttrState(format: vertexFormatFloat4, bufferIndex: 0),
        VertexAttrState(format: vertexFormatUbyte4n, bufferIndex: 0),
        VertexAttrState(format: vertexFormatUbyte4n, bufferIndex: 0),
        VertexAttrState(format: vertexFormatInt4, bufferIndex: 0),
        VertexAttrState(format: vertexFormatInt, bufferIndex: 0),
      ],
    ),
        indexType: indexTypeNone,
        stencil: StencilState(enabled: false),
        colors: [
          ColorTargetState(
            writeMask: colorMaskRgba,
            blend: blendState
      ),
    ],
        primitiveType: primitiveTypeTriangleStrip,
        label: "nvg.glyphPipeline",
      ),
    )

proc toSokolPixelFormat(typ: PixelFormat): gfx.PixelFormat {.inline.} =
  case typ
  of PixelFormatA8: gfx.pixelFormatR8
  of PixelFormatRGB8: gfx.pixelFormatRgba8
  of PixelFormatRGBA8: gfx.pixelFormatRgba8
  of PixelFormatA32f: gfx.pixelFormatR32f
  of PixelFormatRGB32f: gfx.pixelFormatRgba32f
  of PixelFormatRGBA32f: gfx.pixelFormatRgba32f
  of PixelFormatRGBA32u: gfx.pixelFormatRgba32ui

proc createTexture(ctx: SokolBackendContext, image: Image, imageFlags: set[
    ImageFlags]): SokolTexture =
  var
    wrapX = wrapClampToEdge
    wrapY = wrapClampToEdge
    minFilter = filterDefault
    magFilter = filterDefault
    mipmapFilter = filterDefault

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

  let imageInfo = image.imageInfo

  result = SokolTexture()
  result.image = image
  result.imageFlags = imageFlags
  result.texImage = makeImage(
    ImageDesc(
      type: imageType2d,
      width: imageInfo.width,
      height: imageInfo.height,
      usage: ImageUsage(dynamicUpdate: true),
      pixelFormat: imageInfo.pixelFormat.toSokolPixelFormat,
      numMipmaps: 1,
      label: "nvg.image",
    )
  )

  result.smp = makeSampler(
    SamplerDesc(
      minFilter: minFilter,
      magFilter: magFilter,
      mipmapFilter: mipmapFilter,
      wrapU: wrapX,
      wrapV: wrapY,
    )
  )

  result.texImageView = makeView(
    ViewDesc(
      texture: TextureViewDesc(
        image: result.texImage
    ),
  )
  )

proc updateTexture(tex: SokolTexture) {.inline.} =
  let
    image = tex.image
    imageInfo = image.imageInfo
    size = imageInfo.width * imageInfo.height *
        imageInfo.pixelFormat.bytesPerPixel

  if image.data.len > 0:
    tex.texImage.updateImage(ImageData(mipLevels: [
      Range(
        addr: image.data[0].addr,
        size: size
      )
    ]))

proc drawPathCall(ctx: SokolBackendContext, drawCall: PathDrawCall,
    blend: CompositeOperation) =
  let
    zone = zoneBegin("sokol.drawPathCall")
  defer: zone.zoneEnd()

  ctx.updatePathPipeline(blend)

  applyPipeline(ctx.pathPipeline)

  type
    VertexParam = object
      viewSize: array[2, float32] # offset 0, std140 vec2
      pad: array[2, float32]      # pad the block to 16 bytes

  var param = default(VertexParam)
  param.viewSize = ctx.size

  applyUniforms(
    0,
    Range(
      addr: param.addr,
      size: sizeof(param)
    )
  )

  let
    uniform = ctx.drawList.uniforms[drawCall.uniformIndex].addr

  applyUniforms(
    1,
    Range(
      addr: uniform,
      size: sizeof(uniform[])
    )
  )

  var bindings = default(Bindings)
  bindings.vertexBuffers[0] = ctx.paths.buffer

  var tex = default(SokolTexture)
  if not drawCall.imageId.isNil:
    tex = ctx.getTexture(drawCall.imageId)

  if tex.isNil:
    bindings.views[2] = ctx.texDummyView
    bindings.samplers[3] = ctx.smpDummy
  else:
    if tex.dirty:
      tex.dirty = false
      tex.updateTexture()

    bindings.views[2] = tex.texImageView
    bindings.samplers[3] = tex.smp

  bindings.views[4] = ctx.edges.view
  bindings.views[5] = ctx.transforms.view

  if not ctx.supportDrawBaseInstance:
    bindings.vertexBufferOffsets[0] = drawCall.instanceOffset * int32(sizeof(PathInstanceParam))

  applyBindings(bindings)

  if not ctx.supportDrawBaseInstance:
    draw(0, 4, drawCall.instanceCount)
  else:
    drawEx(0, 4, drawCall.instanceCount, 0, drawCall.instanceOffset)

proc drawGlyphCall(ctx: SokolBackendContext, drawCall: GlyphDrawCall,
    blend: CompositeOperation) =
  let
    zone = zoneBegin("sokol.drawGlyphCall")
  defer: zone.zoneEnd()

  ctx.updateGlyphPipeline(blend)

  applyPipeline(ctx.glyphPipeline)

  type
    VertexParam = object
      viewSize: array[2, float32] # offset 0, std140 vec2
      transformIndex: int32       # offset 8
      pad: array[4, uint8]        # pad to 16 bytes

  var param = default(VertexParam)
  param.viewSize = ctx.size
  param.transformIndex = drawCall.mvpIndex

  applyUniforms(0,
    Range(
      addr: param.addr,
      size: sizeof(param)
    )
  )

  let
    fragUniform = ctx.drawList.uniforms[drawCall.uniformIndex].addr
  applyUniforms(6,
    Range(
      addr: fragUniform,
      size: sizeof(fragUniform[])
    )
  )

  var
    curveTex = ctx.getTexture(drawCall.curveImageId)
    bandTex = ctx.getTexture(drawCall.bandImageId)
  if not curveTex.isNil and curveTex.dirty:
    curveTex.dirty = false
    curveTex.updateTexture()
  if not bandTex.isNil and bandTex.dirty:
    bandTex.dirty = false
    bandTex.updateTexture()

  var bindings = default(Bindings)
  bindings.vertexBuffers[0] = ctx.glyphs.buffer

  if not ctx.supportDrawBaseInstance:
    bindings.vertexBufferOffsets[0] = drawCall.instanceOffset *
        int32(sizeof(GlyphInstanceParam))

  if not curveTex.isNil:
    bindings.views[2] = curveTex.texImageView
    bindings.samplers[4] = curveTex.smp
  else:
    bindings.views[2] = ctx.texDummyView
    bindings.samplers[4] = ctx.smpDummy

  if not bandTex.isNil:
    bindings.views[3] = bandTex.texImageView
    bindings.samplers[5] = bandTex.smp
  else:
    bindings.views[3] = ctx.texDummyView
    bindings.samplers[5] = ctx.smpDummy

  var imageTex = ctx.getTexture(drawCall.imageId)
  if not imageTex.isNil and imageTex.dirty:
    imageTex.dirty = false
    imageTex.updateTexture()

  if not imageTex.isNil:
    bindings.views[8] = imageTex.texImageView
    bindings.samplers[9] = imageTex.smp
  else:
    bindings.views[8] = ctx.texDummyView
    bindings.samplers[9] = ctx.smpDummy

  bindings.views[1] = ctx.transforms.view
  bindings.views[7] = ctx.transforms.view

  applyBindings(bindings)

  if not ctx.supportDrawBaseInstance:
    draw(0, 4, drawCall.instanceCount)
  else:
    drawEx(0, 4, drawCall.instanceCount, 0, drawCall.instanceOffset)

method drawPaths(ctx: SokolBackendContext, paint: Paint, paths: openArray[
    DrawPath], fillRule: FillRule, compositeOperation: CompositeOperation) =
  var
    image = default(Image)
    imageFlags = default(set[ImageFlags])

  if not paint.imageId.isNil:
    let tex = ctx.getTexture(paint.imageId)
    if not tex.isNil:
      image = tex.image
      imageFlags = tex.imageFlags

  ctx.drawList.addPathCall(ctx.size, paint, image, imageFlags, paths, fillRule, compositeOperation)

method drawGlyphs*(ctx: SokolBackendContext, paint: Paint, transform: Mat2d,
    curveImageId, bandImageId: ImageId, glyphs: openArray[DrawGlyph],
    compositeOperation: CompositeOperation) =
  var
    image = default(Image)
    imageFlags = default(set[ImageFlags])

  if not paint.imageId.isNil:
    let tex = ctx.getTexture(paint.imageId)
    if not tex.isNil:
      image = tex.image
      imageFlags = tex.imageFlags

  ctx.drawList.addGlyphCall(ctx.size, paint, image, imageFlags, curveImageId,
      bandImageId, transform, glyphs, compositeOperation)

method allocImage(ctx: SokolBackendContext, imageInfo: ImageInfo,
    imageFlags: set[ImageFlags]): ImageId =
  let
    image = ctx.drawList.createImage(imageInfo)
    tex = ctx.createTexture(image, imageFlags)
  ctx.addTexture(image.imageId, tex)
  image.imageId

method getImageInfo(ctx: SokolBackendContext, imageId: ImageId): ImageInfo =
  let
    tex = ctx.getTexture(imageId)

  if not tex.isNil:
    result = tex.image.imageInfo

method writeImagePixels(ctx: SokolBackendContext, imageId: ImageId, x, y, w, h,
    strideBytes: int32, data: pointer) =
  let
    tex = ctx.getTexture(imageId)

  if not tex.isNil:
    tex.dirty = true
    tex.image.writePixels(x, y, w, h, strideBytes, data)

method deleteImage(ctx: SokolBackendContext, imageId: ImageId) =
  ctx.deleteTexture(imageId)

proc uploadStorage(ctx: SokolBackendContext) =
  let
    zone = zoneBegin("sokol.uploadStorage")
  defer: zone.zoneEnd()

  if ctx.drawList.edges.len > 0:
    ctx.edges.updateStorage(ctx.drawList.edges)

  if ctx.drawList.paths.len > 0:
    ctx.paths.updateStorage(ctx.drawList.paths)

  if ctx.drawList.glyphs.len > 0:
    ctx.glyphs.updateStorage(ctx.drawList.glyphs)

  if ctx.drawList.transforms.len > 0:
    ctx.transforms.updateStorage(ctx.drawList.transforms)

method flush(ctx: SokolBackendContext) =
  let
    zone = zoneBegin("sokol.flush")
  defer: zone.zoneEnd()

  ctx.initIfNeeded()
  ctx.uploadStorage()

  for drawCall in ctx.drawList.calls:
    case drawCall.kind
    of DrawCallPath:
      ctx.drawPathCall(drawCall.path, drawCall.blend)
    of DrawCallGlyph:
      ctx.drawGlyphCall(drawCall.glyph, drawCall.blend)

  #
  ctx.drawList.clear()

method resize(ctx: SokolBackendContext, w, h: int32) =
  ctx.size[0] = float32(w)
  ctx.size[1] = float32(h)

proc createSokolBackendContext*(w, h: int32): BackendContext =
  let backendContext = SokolBackendContext()
  backendContext.size[0] = float32(w)
  backendContext.size[1] = float32(h)
  backendContext
