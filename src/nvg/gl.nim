import pkg/opengl

import ./context
import ./core
import ./fontstash
import ./glsl
import ./params
import ./renderdata

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

  OpenglBlend = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  OpenglTexture = ref object
    image: Image
    texImage: GLuint
    smp: GLuint
    version: uint32

  OpenglBackendContextObj = object
    shaderProgram: OpenglShaderProgram
    vertArr: GLuint
    vertAndIndexDummyBuf: GLuint
    instanceBuf: GLuint
    texEdge: GLuint
    texVert: GLuint
    texDummy: GLuint
    smpDummy: GLuint

    maxInstanceBufSize: int32
    maxTexEdgeLayerCount: int32
    maxTexVertLayerCount: int32

    viewBounds: Vec2
    renderData: RenderData

    textures: Table[pointer, OpenglTexture]

template tryCall(body: untyped) =
  try:
    body
  except:
    discard

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

proc initImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

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
  glGenTextures(1, ctx.texEdge.addr)
  glGenTextures(1, ctx.texVert.addr)
  glGenTextures(1, ctx.texDummy.addr)

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

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.renderData.clear()

proc viewportImpl(ctx: pointer, viewBounds: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.viewBounds = viewBounds
  cancelImpl(ctx)

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    renderFlags: set[RenderFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
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
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  ctx.renderData.trianglesCall(
    ctx.viewBounds,
    paint,
    compositeOperation,
    renderFlags,
    verts
  )

proc createTexture(image: Image): OpenglTexture =
  var
    wrapX = GL_CLAMP_TO_EDGE
    wrapY = GL_CLAMP_TO_EDGE
    minFilter = GL_NEAREST
    magFilter = GL_NEAREST
    mipmapFilter = GL_NEAREST_MIPMAP_NEAREST

  if ImageRepeatX in image.imageFlags:
    wrapX = GL_REPEAT

  if ImageRepeatY in image.imageFlags:
    wrapY = GL_REPEAT

  if ImageNearest in image.imageFlags:
    magFilter = GL_NEAREST
    mipmapFilter = GL_NEAREST_MIPMAP_NEAREST
  else:
    magFilter = GL_LINEAR
    mipmapFilter = GL_LINEAR_MIPMAP_LINEAR

  if ImageGenerateMipmaps in image.imageFlags:
    minFilter = mipmapFilter
  else:
    minFilter = magFilter

  let
    tex = OpenglTexture()

  tex.image = image

  glGenTextures(1, tex.texImage.addr)
  glBindTexture(GL_TEXTURE_2D, tex.texImage)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, image.width *
      image.pixelFormat.bytesPerPixel)

  case image.pixelFormat
  of PixelFormatA8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R8), image.width, image.height, 0,
        GL_RED, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatRGB8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGB8), image.width, image.height, 0,
        GL_RGB, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatRGBA8:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA8), image.width, image.height,
        0, GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatA32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R32F), image.width, image.height, 0,
        GL_RED, cGL_FLOAT, image.data[0].addr)

  of PixelFormatRGB32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGB32F), image.width, image.height,
        0, GL_RGB, cGL_FLOAT, image.data[0].addr)

  of PixelFormatRGBA32f:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA32F), image.width, image.height,
        0, GL_RGBA, cGL_FLOAT, image.data[0].addr)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

  glGenSamplers(1, tex.smp.addr)
  glSamplerParameteri(tex.smp, GL_TEXTURE_MIN_FILTER, minFilter)
  glSamplerParameteri(tex.smp, GL_TEXTURE_MAG_FILTER, magFilter)
  glSamplerParameteri(tex.smp, GL_TEXTURE_WRAP_S, wrapX)
  glSamplerParameteri(tex.smp, GL_TEXTURE_WRAP_T, wrapY)

  if image.data.len > 0:
    if ImageGenerateMipmaps in image.imageFlags:
      glGenerateMipmap(GL_TEXTURE_2D)

  glBindTexture(GL_TEXTURE_2D, 0)

  tex

proc updateTexture(tex: OpenglTexture) =
  let
    image = tex.image

  tex.version = image.version

  glBindTexture(GL_TEXTURE_2D, tex.texImage)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, image.width *
      image.pixelFormat.bytesPerPixel)

  case image.pixelFormat
  of PixelFormatA8:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
        GL_RED, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatRGB8:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
        GL_RGB, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatRGBA8:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
        GL_RGBA, GL_UNSIGNED_BYTE, image.data[0].addr)

  of PixelFormatA32f:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
        GL_RED, cGL_FLOAT, image.data[0].addr)

  of PixelFormatRGB32f:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
       GL_RGB, cGL_FLOAT, image.data[0].addr)

  of PixelFormatRGBA32f:
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, image.width, image.height,
       GL_RGBA, cGL_FLOAT, image.data[0].addr)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

  glBindTexture(GL_TEXTURE_2D, 0)

proc destroyTexture(tex: OpenglTexture) {.inline.} =
  tryCall glDeleteSamplers(1, tex.smp.addr)
  tryCall glDeleteTextures(1, tex.texImage.addr)

  tex.image = nil

proc addTexture(ctx: ptr OpenglBackendContextObj,
    image: Image, tex: OpenglTexture) {.inline.} =
  ctx.textures[cast[pointer](image)] = tex

proc getTexture(ctx: ptr OpenglBackendContextObj,
    image: Image): OpenglTexture {.inline.} =
  ctx.textures.withValue(cast[pointer](image), tex):
    result = tex[]

# proc deleteTexture(ctx: ptr OpenglBackendContextObj,
#     tex: OpenglTexture) {.inline.} =
#   ctx.textures.del(cast[pointer](tex.image))

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

proc updateTex(ctx: ptr OpenglBackendContextObj, target: GLuint, data: var seq[
    Vec4], maxLayerCount: var int32) =
  if data.len <= 0:
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
  glBindTexture(GL_TEXTURE_2D_ARRAY, target)
  glBindSampler(0, 0)

  if maxLayerCount < layerCount:
    maxLayerCount = int32(layerCount)

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

proc updateInstanceBuf(ctx: ptr OpenglBackendContextObj) =
  if ctx.renderData.instances.len <= 0:
    return

  glBindBuffer(GL_ARRAY_BUFFER, ctx.instanceBuf)

  if ctx.maxInstanceBufSize < ctx.renderData.instances.len:
    ctx.maxInstanceBufSize = int32(ctx.renderData.instances.len)

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

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  if ctx.renderData.calls.len <= 0:
    return

  glUseProgram(ctx.shaderProgram.program)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.vertArr)

  ctx.updateInstanceBuf()
  ctx.updateTex(ctx.texEdge, ctx.renderData.edges, ctx.maxTexEdgeLayerCount)
  ctx.updateTex(ctx.texVert, ctx.renderData.verts, ctx.maxTexVertLayerCount)

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

  glUniform2fv(
    ctx.shaderProgram.viewSizeLoc, 1, cast[ptr GLfloat](ctx.viewBounds[0].addr)
  )

  glUniform1i(ctx.shaderProgram.texLoc, 0)
  glUniform1i(ctx.shaderProgram.texVertLoc, 1)
  glUniform1i(ctx.shaderProgram.texEdgeLoc, 2)

  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texVert)
  glBindSampler(1, ctx.smpDummy)

  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texEdge)
  glBindSampler(2, ctx.smpDummy)

  for idx in 0 ..< ctx.renderData.calls.len:
    let
      call = ctx.renderData.calls[idx].addr
      blend = call.blend

      prevBlend = block:
        if idx > 0:
          ctx.renderData.calls[idx - 1].blend
        else:
          default(CompositeOperation)

    if idx <= 0 or call.uniformIndex != ctx.renderData.calls[idx -
        1].uniformIndex:
      let uniform = ctx.renderData.uniforms[call.uniformIndex].addr
      glUniform4fv(ctx.shaderProgram.paintLoc, 6, cast[ptr GLfloat](uniform))

    glUniform1i(ctx.shaderProgram.triangleOffsetLoc, call.triangleOffset)

    if idx <= 0 or blend != prevBlend:
      let blend = toOpenglBlend(blend)
      glBlendFuncSeparate(blend.srcRGB, blend.dstRGB, blend.srcAlpha,
          blend.dstAlpha)

    glActiveTexture(GL_TEXTURE0)
    if call.image.isNil:
      glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
      glBindSampler(0, ctx.smpDummy)
    else:
      var
        tex = ctx.getTexture(call.image)
        isDirty = false

      if tex.isNil:
        tex = createTexture(call.image)
        ctx.addTexture(call.image, tex)
      elif tex.version != call.image.version:
        isDirty = true

      if isDirty:
        tex.updateTexture()

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

proc destroyImpl(ctx: pointer) {.raises: [].} =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

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

  if ctx.texEdge != 0:
    tryCall glDeleteTextures(1, ctx.texEdge.addr)

  if ctx.texVert != 0:
    tryCall glDeleteTextures(1, ctx.texVert.addr)

  if ctx.texDummy != 0:
    tryCall glDeleteTextures(1, ctx.texDummy.addr)

  if ctx.smpDummy != 0:
    tryCall glDeleteSamplers(1, ctx.smpDummy.addr)

  for tex in ctx.textures.values:
    tex.destroyTexture()

  reset(ctx[])
  dealloc(ctx)

proc newContext*(fons: FonsStash = nil): Context =
  let ctx = create(OpenglBackendContextObj)

  createInternal(
    ctx,
    BackendContextParams(
      initImpl: initImpl,
      destroyImpl: destroyImpl,
      fillImpl: fillImpl,
      trianglesImpl: trianglesImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    ),
    fons,
  )
