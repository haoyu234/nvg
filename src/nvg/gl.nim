import pkg/opengl

import ./backend
import ./core
import ./glsl
import ./render_data

import std/math
import std/tables

const
  NVG_USE_GLCORE = true

const TILE_IMAGE_WIDTH = 256

type
  OpenglShaderProgram = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    viewSizeLoc: GLint
    triangleOffsetLoc: GLint

    texLoc: GLint
    texEdgeLoc: GLint
    texVertLoc: GLint

    paintLoc: GLint

  OpenglTexture = ref OpenglTextureObj
  OpenglTextureObj = object
    image: Image
    imageFlags: set[ImageFlags]
    texImage: GLuint
    smp: GLuint
    version: uint32

  OpenglStorage = object
    tex: GLuint
    layerCount: int32

  OpenglBlend = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  OpenglBackendContext = ref OpenglBackendContextObj
  OpenglBackendContextObj = object of BackendContext
    width: int32
    height: int32

    shaderProgram: OpenglShaderProgram
    vertArr: GLuint
    vertAndIndexDummyBuf: GLuint

    texEdge: OpenglStorage
    texVert: OpenglStorage

    texDummy: GLuint
    smpDummy: GLuint

    instanceBuf: GLuint
    instanceBufSize: int32

    renderData: RenderData

    textures: Table[ImageId, OpenglTexture]

    initial: bool

template tryCall(body: untyped) =
  try:
    body
  except:
    discard

proc `=destroy`(tex: var OpenglTextureObj) =
  tryCall glDeleteSamplers(1, tex.smp.addr)
  tryCall glDeleteTextures(1, tex.texImage.addr)

  `=destroy`(tex.image)
  `=destroy`(tex.imageFlags)

proc `=destroy`(storage: OpenglStorage) =
  tryCall glDeleteTextures(1, storage.tex.addr)

proc `=destroy`(ctx: var OpenglBackendContextObj) =
  if ctx.shaderProgram.vsShader != 0:
    tryCall glDeleteShader(ctx.shaderProgram.vsShader)

  if ctx.shaderProgram.fsShader != 0:
    tryCall glDeleteShader(ctx.shaderProgram.fsShader)

  if ctx.shaderProgram.program != 0:
    tryCall glDeleteProgram(ctx.shaderProgram.program)

  when NVG_USE_GLCORE:
    if ctx.vertArr != 0:
      tryCall glDeleteVertexArrays(1, ctx.vertArr.addr)

  if ctx.vertAndIndexDummyBuf != 0:
    tryCall glDeleteBuffers(1, ctx.vertAndIndexDummyBuf.addr)

  if ctx.instanceBuf != 0:
    tryCall glDeleteBuffers(1, ctx.instanceBuf.addr)

  if ctx.texDummy != 0:
    tryCall glDeleteTextures(1, ctx.texDummy.addr)

  if ctx.smpDummy != 0:
    tryCall glDeleteSamplers(1, ctx.smpDummy.addr)

  `=destroy`(ctx.renderData)

  `=destroy`(ctx.texEdge)
  `=destroy`(ctx.texVert)
  `=destroy`(ctx.textures)

proc initStorage(storage: var OpenglStorage) {.inline.} =
  glGenTextures(1, storage.tex.addr)
  storage.layerCount = -1

proc updateStorage(storage: var OpenglStorage, data: var seq[Vec4]) =
  if data.len <= 0 and storage.layerCount >= 0:
    return

  let
    layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
    layerCount = block:
      let n = if (data.len mod layerSize) > 0: 1 else: 0
      data.len div layerSize + n

    size = int32(ceil(float32(data.len) / float32(layerSize))) * layerSize

  if capacity(data) < size:
    data.setLen(size)

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, storage.tex)

  if storage.layerCount < layerCount:
    storage.layerCount = int32(layerCount)

    glTexImage3D(
      GL_TEXTURE_2D_ARRAY,
      0,
      GLint(GL_RGBA32F),
      TILE_IMAGE_WIDTH,
      TILE_IMAGE_WIDTH,
      GLsizei(layerCount),
      0,
      GL_RGBA,
      cGL_FLOAT,
      data[0].addr,
    )
  else:
    glTexSubImage3D(
      GL_TEXTURE_2D_ARRAY,
      0,
      0,
      0,
      0,
      TILE_IMAGE_WIDTH,
      TILE_IMAGE_WIDTH,
      GLsizei(layerCount),
      GL_RGBA,
      cGL_FLOAT,
      data[0].addr,
    )

proc addTexture(ctx: OpenglBackendContext, imageId: ImageId,
    tex: OpenglTexture) {.inline.} =
  ctx.textures[imageId] = tex

proc getTexture(ctx: OpenglBackendContext,
    imageId: ImageId): OpenglTexture {.inline.} =
  ctx.textures.withValue(imageId, tex):
    result = tex[]

proc deleteTexture(ctx: OpenglBackendContext,
    imageId: ImageId) {.inline.} =
  ctx.textures.del(imageId)

proc toOpenglBlend(op: CompositeOperation): OpenglBlend {.inline.} =
  type BlendOp = object
    src: GLenum
    dst: GLenum

  const blendOpTbl: array[CompositeOperation, BlendOp] = [
    BlendOp(src: GL_ONE, dst: GL_ONE_MINUS_SRC_ALPHA),
    BlendOp(src: GL_DST_ALPHA, dst: GL_ZERO),
    BlendOp(src: GL_ONE_MINUS_DST_ALPHA, dst: GL_ZERO),
    BlendOp(src: GL_DST_ALPHA, dst: GL_ONE_MINUS_SRC_ALPHA),
    BlendOp(src: GL_ONE_MINUS_DST_ALPHA, dst: GL_ONE),
    BlendOp(src: GL_ZERO, dst: GL_SRC_ALPHA),
    BlendOp(src: GL_ZERO, dst: GL_ONE_MINUS_SRC_ALPHA),
    BlendOp(src: GL_ONE_MINUS_DST_ALPHA, dst: GL_SRC_ALPHA),
    BlendOp(src: GL_ONE, dst: GL_ONE),
    BlendOp(src: GL_ONE, dst: GL_ZERO),
    BlendOp(src: GL_ONE_MINUS_DST_ALPHA, dst: GL_ONE_MINUS_SRC_ALPHA),
  ]

  let blendOp = blendOpTbl[op]
  OpenglBlend(
    srcRGB: blendOp.src,
    dstRGB: blendOp.dst,
    srcAlpha: blendOp.src,
    dstAlpha: blendOp.dst,
  )

proc createGlShader(tp: GLenum, source: cstring): GLuint =
  let s = glCreateShader(tp)

  var
    p = source
    len = GLint(source.len)
    status = default(GLint)

  glShaderSource(s, GLsizei(1), cast[cstringArray](p.addr), len.addr)
  glCompileShader(s)

  glGetShaderiv(s, GL_COMPILE_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    var log: array[256, char]

    glGetShaderInfoLog(s, GLsizei(len(log)), nil, cast[cstring](log[0].addr))
    assert false, $cast[cstring](log[0].addr)

  s

proc createShaderProgram(vs, fs: cstring): OpenglShaderProgram =
  let
    program = glCreateProgram()
    vsShader = createGlShader(GL_VERTEX_SHADER, vs)
    fsShader = createGlShader(GL_FRAGMENT_SHADER, fs)

  glAttachShader(program, vsShader)
  glAttachShader(program, fsShader)

  glBindAttribLocation(program, 0, "v_idx")
  glBindAttribLocation(program, 1, "v_fillCount")
  glBindAttribLocation(program, 2, "v_fillOffset")

  glLinkProgram(program)

  var status = default(GLint)

  glGetProgramiv(program, GL_LINK_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    assert false

  result.program = program
  result.fsShader = fsShader
  result.vsShader = vsShader
  result.viewSizeLoc = glGetUniformLocation(program, "_68.viewSize")
  result.triangleOffsetLoc = glGetUniformLocation(program, "_68.triangleOffset")
  result.texLoc = glGetUniformLocation(program, "imageTex_smp1")
  result.texEdgeLoc = glGetUniformLocation(program, "edgeTex_smp2")
  result.texVertLoc = glGetUniformLocation(program, "vertTex_smp3")
  result.paintLoc = glGetUniformLocation(program, "params")

proc initIfNeeded(ctx: OpenglBackendContext) =
  if ctx.initial:
    return

  ctx.initial = true

  when NVG_USE_GLCORE:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsSourceGlsl410[0].addr), cast[cstring](fsSourceGlsl410[0].addr)
    )
    glGenVertexArrays(1, ctx.vertArr.addr)
  else:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsSourceGlsl300es[0].addr), cast[cstring](fsSourceGlsl300es[0].addr)
    )

  glGenBuffers(1, ctx.instanceBuf.addr)
  glGenBuffers(1, ctx.vertAndIndexDummyBuf.addr)
  glGenTextures(1, ctx.texDummy.addr)

  ctx.texEdge.initStorage()
  ctx.texVert.initStorage()

  const
    vertAndIndex = [uint32(0), 1, 2, 0, 2, 3]
    pixels = [color(1, 1, 1, 1)]

  glBindBuffer(GL_ARRAY_BUFFER, ctx.vertAndIndexDummyBuf)
  glBufferData(
    GL_ARRAY_BUFFER,
    GLsizeiptr(6 * sizeof(uint32)),
    vertAndIndex[0].addr,
    GL_STATIC_DRAW,
  )
  glBindBuffer(GL_ARRAY_BUFFER, 0)

  glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
  glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA8), 1, 1, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, pixels[0].addr)
  glBindTexture(GL_TEXTURE_2D, 0)

  glGenSamplers(1, ctx.smpDummy.addr)
  glSamplerParameteri(ctx.smpDummy, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glSamplerParameteri(ctx.smpDummy, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

  glFinish()

proc createTexture(ctx: OpenglBackendContext, image: Image, imageFlags: set[
    ImageFlags]): OpenglTexture =
  var
    wrapX = GL_CLAMP_TO_EDGE
    wrapY = GL_CLAMP_TO_EDGE
    minFilter = GL_NEAREST
    magFilter = GL_NEAREST
    mipmapFilter = GL_NEAREST_MIPMAP_NEAREST

  if ImageRepeatX in imageFlags:
    wrapX = GL_REPEAT

  if ImageRepeatY in imageFlags:
    wrapY = GL_REPEAT

  if ImageNearest in imageFlags:
    magFilter = GL_NEAREST
    mipmapFilter = GL_NEAREST_MIPMAP_NEAREST
  else:
    magFilter = GL_LINEAR
    mipmapFilter = GL_LINEAR_MIPMAP_LINEAR

  if ImageGenerateMipmaps in imageFlags:
    minFilter = mipmapFilter
  else:
    minFilter = magFilter

  let imageInfo = image.imageInfo

  result = OpenglTexture()
  result.image = image
  result.imageFlags = imageFlags

  glGenTextures(1, result.texImage.addr)
  glBindTexture(GL_TEXTURE_2D, result.texImage)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, imageInfo.width *
      imageInfo.pixelFormat.bytesPerPixel)

  var pixels = default(pointer)
  if image.data.len > 0:
    pixels = image.data[0].addr

  case imageInfo.pixelFormat
  of PixelFormatA8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R8), imageInfo.width,
        imageInfo.height, 0, GL_RED, GL_UNSIGNED_BYTE, pixels)

  of PixelFormatRGB8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGB8), imageInfo.width,
        imageInfo.height, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels)

  of PixelFormatRGBA8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA8), imageInfo.width,
        imageInfo.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels)

  of PixelFormatA32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R32F), imageInfo.width,
        imageInfo.height, 0, GL_RED, cGL_FLOAT, pixels)

  of PixelFormatRGB32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGB32F), imageInfo.width,
        imageInfo.height, 0, GL_RGB, cGL_FLOAT, pixels)

  of PixelFormatRGBA32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA32F), imageInfo.width,
        imageInfo.height, 0, GL_RGBA, cGL_FLOAT, pixels)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

  glGenSamplers(1, result.smp.addr)
  glSamplerParameteri(result.smp, GL_TEXTURE_MIN_FILTER, minFilter)
  glSamplerParameteri(result.smp, GL_TEXTURE_MAG_FILTER, magFilter)
  glSamplerParameteri(result.smp, GL_TEXTURE_WRAP_S, wrapX)
  glSamplerParameteri(result.smp, GL_TEXTURE_WRAP_T, wrapY)

  glBindTexture(GL_TEXTURE_2D, 0)

proc updateInstanceBuf(ctx: OpenglBackendContext) =
  if ctx.renderData.instances.len <= 0:
    return

  glBindBuffer(GL_ARRAY_BUFFER, ctx.instanceBuf)

  if ctx.instanceBufSize < ctx.renderData.instances.len:
    ctx.instanceBufSize = int32(ctx.renderData.instances.len)

    glBufferData(
      GL_ARRAY_BUFFER,
      GLsizeiptr(ctx.renderData.instances.len * sizeof(InstanceParam)),
      ctx.renderData.instances[0].addr,
      GL_STREAM_DRAW,
    )
  else:
    glBufferSubData(
      GL_ARRAY_BUFFER,
      0,
      GLsizeiptr(ctx.renderData.instances.len * sizeof(InstanceParam)),
      ctx.renderData.instances[0].addr,
    )

proc drawCall(ctx: OpenglBackendContext, idx: int32, call: InstanceCall,
    prevBlend: CompositeOperation) =
  if idx <= 0 or call.uniformIndex != ctx.renderData.calls[idx -
      1].uniformIndex:
    let uniform = ctx.renderData.uniforms[call.uniformIndex].addr
    glUniform4fv(ctx.shaderProgram.paintLoc, 6, cast[ptr GLfloat](uniform))

  glUniform1i(ctx.shaderProgram.triangleOffsetLoc, call.triangleOffset)

  if idx <= 0 or call.blend != prevBlend:
    let blend = toOpenglBlend(call.blend)
    glBlendFuncSeparate(blend.srcRGB, blend.dstRGB, blend.srcAlpha,
        blend.dstAlpha)

  glActiveTexture(GL_TEXTURE0)

  var tex = default(OpenglTexture)
  if not call.imageId.isNil:
    tex = ctx.getTexture(call.imageId)

  if tex.isNil:
    glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
    glBindSampler(0, ctx.smpDummy)
  else:
    glBindTexture(GL_TEXTURE_2D, tex.texImage)
    glBindSampler(0, tex.smp)

  let offset = call.instanceOffset * int32(sizeof(InstanceParam))
  glVertexAttribIPointer(1, 1, cGL_INT, GLsizei(sizeof(InstanceParam)), cast[
      pointer](offset))
  glVertexAttribDivisor(1, 1)

  glVertexAttribIPointer(
    2, 1, cGL_INT, GLsizei(sizeof(InstanceParam)), cast[pointer](offset +
        sizeof(int32))
  )
  glVertexAttribDivisor(2, 1)

  glDrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, nil,
      call.instanceCount)

method drawContours(ctx: OpenglBackendContext, paint: Paint,
    contours: openArray[

Contour], fillRule: FillRule, compositeOperation: CompositeOperation) =
  var
    image = default(Image)
    imageFlags = default(set[ImageFlags])

  if not paint.imageId.isNil:
    let tex = ctx.getTexture(paint.imageId)
    if not tex.isNil:
      image = tex.image
      imageFlags = tex.imageFlags

  ctx.renderData.addCall(
    vec2(float32(ctx.width), float32(ctx.height)),
    paint,
    image,
    imageFlags,
    contours,
    fillRule,
    compositeOperation,
  )

method allocImage(ctx: OpenglBackendContext, imageInfo: ImageInfo,
    imageFlags: set[ImageFlags]): ImageId =
  let
    image = ctx.renderData.createImage(imageInfo)
    tex = ctx.createTexture(image, imageFlags)
  ctx.addTexture(image.imageId, tex)
  image.imageId

method getImageInfo(ctx: OpenglBackendContext, imageId: ImageId): ImageInfo =
  let
    tex = ctx.getTexture(imageId)

  if not tex.isNil:
    result = tex.image.imageInfo

method updateImage(ctx: OpenglBackendContext, imageId: ImageId, x, y, w, h,
    strideBytes: int32, data: pointer) =
  let
    tex = ctx.getTexture(imageId)

  if not tex.isNil:
    let
      image = tex.image
      imageInfo = image.imageInfo
      bytesPerPixel = imageInfo.pixelFormat.bytesPerPixel

    glBindTexture(GL_TEXTURE_2D, tex.texImage)

    let
      remainder = strideBytes mod bytesPerPixel
      rowPixelCount = strideBytes div bytesPerPixel

    assert remainder == 0

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowPixelCount)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

    case imageInfo.pixelFormat
    of PixelFormatA8:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
          GL_RED, GL_UNSIGNED_BYTE, data)

    of PixelFormatRGB8:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
          GL_RGB, GL_UNSIGNED_BYTE, data)

    of PixelFormatRGBA8:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
          GL_RGBA, GL_UNSIGNED_BYTE, data)

    of PixelFormatA32f:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
          GL_RED, cGL_FLOAT, data)

    of PixelFormatRGB32f:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
        GL_RGB, cGL_FLOAT, data)

    of PixelFormatRGBA32f:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
        GL_RGBA, cGL_FLOAT, data)

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

    if ImageGenerateMipmaps in tex.imageFlags:
      glGenerateMipmap(GL_TEXTURE_2D)

    glBindTexture(GL_TEXTURE_2D, 0)

method deleteImage(ctx: OpenglBackendContext, imageId: ImageId) =
  ctx.deleteTexture(imageId)

method flush(ctx: OpenglBackendContext) =
  ctx.initIfNeeded()

  if ctx.renderData.calls.len <= 0:
    return

  glUseProgram(ctx.shaderProgram.program)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.vertArr)

  ctx.updateInstanceBuf()
  ctx.texEdge.updateStorage(ctx.renderData.edges)
  ctx.texVert.updateStorage(ctx.renderData.verts)

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ctx.vertAndIndexDummyBuf)

  glBindBuffer(GL_ARRAY_BUFFER, ctx.vertAndIndexDummyBuf)
  glVertexAttribIPointer(0, 1, cGL_INT, GLsizei(sizeof(int32)), nil)
  glVertexAttribDivisor(0, 1)
  glEnableVertexAttribArray(0)

  glBindBuffer(GL_ARRAY_BUFFER, ctx.instanceBuf)
  glVertexAttribIPointer(1, 1, cGL_INT, GLsizei(sizeof(InstanceParam)), nil)
  glEnableVertexAttribArray(1)
  glVertexAttribIPointer(
    2, 1, cGL_INT, GLsizei(sizeof(InstanceParam)), cast[pointer](sizeof(int32))
  )
  glEnableVertexAttribArray(2)

  let view = vec2(float32(ctx.width), float32(ctx.height))
  glUniform2fv(
    ctx.shaderProgram.viewSizeLoc, 1, cast[ptr GLfloat](view[0].addr)
  )

  glUniform1i(ctx.shaderProgram.texLoc, 0)
  glUniform1i(ctx.shaderProgram.texVertLoc, 1)
  glUniform1i(ctx.shaderProgram.texEdgeLoc, 2)

  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texVert.tex)
  glBindSampler(1, ctx.smpDummy)

  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texEdge.tex)
  glBindSampler(2, ctx.smpDummy)

  for idx in 0 ..< int32(ctx.renderData.calls.len):
    let
      prevBlend = block:
        if idx > 0:
          ctx.renderData.calls[idx - 1].blend
        else:
          default(CompositeOperation)

    ctx.drawCall(idx, ctx.renderData.calls[idx], prevBlend)

  glDisableVertexAttribArray(0)
  glDisableVertexAttribArray(1)
  glDisableVertexAttribArray(2)

  when NVG_USE_GLCORE:
    glBindVertexArray(0)

  glUseProgram(0)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindSampler(0, 0)

  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D_ARRAY, 0)
  glBindSampler(1, 0)

  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D_ARRAY, 0)
  glBindSampler(2, 0)

  #
  ctx.renderData.clear()

proc createOpenglBackendContext*(
  width, height: int32): BackendContext =
  let backendContext = OpenglBackendContext()
  backendContext.width = width
  backendContext.height = height
  backendContext
