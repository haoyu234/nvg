import pkg/opengl

import ./context
import ./core
import ./glsl
import ./params
import ./renderdata

import std/math

const
  NVG_USE_GLCORE = true
  NVG_STATS = false

const TILE_IMAGE_WIDTH = 256

type
  OpenglShaderProgram = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    viewLoc: GLint
    texLoc: GLint
    edgeTexLoc: GLint
    fillLoc: GLint
    paintLoc: GLint

  OpenglBlend = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  OpenglTexture = ref object of Texture
    pixels: ptr UncheckedArray[byte]
    texImage: GLuint
    smp: GLuint

  OpenglBackendContextObj = object
    shaderProgram: OpenglShaderProgram
    vertBuf: GLuint
    vertArr: GLuint
    fragmentBuf: GLint
    texEdge: GLuint
    smpDummy: GLuint

    viewBounds: Vec2
    renderData: RenderData

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

  glBindAttribLocation(program, 0, "va_in")
  glBindAttribLocation(program, 1, "vb_in")

  glLinkProgram(program)

  var status = default(GLint)

  glGetProgramiv(program, GL_LINK_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    assert false

  result.program = program
  result.fsShader = fsShader
  result.vsShader = vsShader
  result.viewLoc = glGetUniformLocation(program, "view")
  result.texLoc = glGetUniformLocation(program, "imageTex_smp1")
  result.edgeTexLoc = glGetUniformLocation(program, "edgeTex_smp2")
  result.fillLoc = glGetUniformLocation(program, "fill")
  result.paintLoc = glGetUniformLocation(program, "paint")

proc createImpl(): pointer =
  let ctx = create(OpenglBackendContextObj)

  when NVG_USE_GLCORE:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsSourceGlsl410[0].addr), cast[cstring](fsSourceGlsl410[0].addr)
    )
    glGenVertexArrays(1, ctx.vertArr.addr)
  else:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsSourceGlsl300es[0].addr), cast[cstring](fsSourceGlsl300es[0].addr)
    )

  glGenBuffers(1, ctx.vertBuf.addr)
  glGenTextures(1, ctx.texEdge.addr)

  glGenSamplers(1, ctx.smpDummy.addr)
  glSamplerParameteri(ctx.smpDummy, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glSamplerParameteri(ctx.smpDummy, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

  glFinish()

  ctx

proc destroyImpl(ctx: pointer) {.raises: [].} =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  if ctx.shaderProgram.vsShader != 0:
    try:
      glDeleteShader(ctx.shaderProgram.vsShader)
    except:
      discard

  if ctx.shaderProgram.fsShader != 0:
    try:
      glDeleteShader(ctx.shaderProgram.fsShader)
    except:
      discard

  when NVG_USE_GLCORE:
    if ctx.vertArr != 0:
      try:
        glDeleteVertexArrays(1, ctx.vertArr.addr)
      except:
        discard

  if ctx.vertBuf != 0:
    try:
      glDeleteBuffers(1, ctx.vertBuf.addr)
    except:
      discard

  if ctx.texEdge != 0:
    try:
      glDeleteTextures(1, ctx.texEdge.addr)
    except:
      discard

  reset(ctx[])
  dealloc(ctx)

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

proc createTextureImpl(ctx: pointer, typ: TextureType, w, h: int32,
    imageFlags: set[ImageFlags], data: pointer): ImageId =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  var tex = OpenglTexture()
  tex.width = w
  tex.height = h
  tex.typ = typ
  tex.imageFlags = imageFlags

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

  glGenTextures(1, tex.texImage.addr)
  glBindTexture(GL_TEXTURE_2D, tex.texImage)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, w)
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

  if ImageExternalStorage in imageFlags:
    tex.pixels = cast[ptr UncheckedArray[byte]](data)

  case typ
  of TextureRgba:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA8), w, h, 0, GL_RGBA,
        GL_UNSIGNED_BYTE, data)

  of TextureAlpha:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R8), w, h, 0, GL_RED,
        GL_UNSIGNED_BYTE, data)

  of TextureFloat:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_R32F), w, h, 0, GL_RED, cGL_FLOAT, data)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
  glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
  glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

  glGenSamplers(1, tex.smp.addr)
  glSamplerParameteri(tex.smp, GL_TEXTURE_MIN_FILTER, minFilter)
  glSamplerParameteri(tex.smp, GL_TEXTURE_MAG_FILTER, magFilter)
  glSamplerParameteri(tex.smp, GL_TEXTURE_WRAP_S, wrapX)
  glSamplerParameteri(tex.smp, GL_TEXTURE_WRAP_T, wrapY)

  if not data.isNil:
    if ImageGenerateMipmaps in imageFlags:
      glGenerateMipmap(GL_TEXTURE_2D)

  glBindTexture(GL_TEXTURE_2D, 0)

  ctx.renderData.addTexture(tex)

proc updateTexture(tex: OpenglTexture, x, y, w, h, stride: int32,
    data: ptr UncheckedArray[byte]) =
  glBindTexture(GL_TEXTURE_2D, tex.texImage)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, stride * tex.typ.bytePerPixel)

  case tex.typ
  of TextureRgba:
    glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_RGBA, GL_UNSIGNED_BYTE, data)

  of TextureAlpha:
    glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_RED, GL_UNSIGNED_BYTE, data)

  of TextureFloat:
    glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_RED, cGL_FLOAT, data)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

  glBindTexture(GL_TEXTURE_2D, 0)

proc updateTextureImpl(ctx: pointer, imageId: ImageId, x, y, w, h, stride: int32, data: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = OpenglTexture(tex)

    tex.updateTexture(x, y, w, h, stride, cast[ptr UncheckedArray[byte]](data))

proc markTextureDirtyImpl(ctx: pointer, imageId: ImageId, x, y, w, h: int32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = OpenglTexture(tex)
    if ImageExternalStorage in tex.imageFlags and not tex.pixels.isNil:
      let
        bytePerPixel = tex.typ.bytePerPixel
        offset = x + y * tex.width
        data = tex.pixels[offset * bytePerPixel].addr

      tex.updateTexture(x, y, w, h, tex.width, cast[ptr UncheckedArray[byte]](data))

proc getTextureSizeImpl(ctx: pointer, imageId: ImageId): Vec2 =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    result = vec2(float32(tex.width), float32(tex.height))

proc deleteTextureImpl(ctx: pointer, imageId: ImageId) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.renderData.getTexture(imageId)
  if not tex.isNil:
    let tex = OpenglTexture(tex)

    glDeleteSamplers(1, tex.smp.addr)
    glDeleteTextures(1, tex.texImage.addr)

    ctx.renderData.removeTexture(imageId)

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

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  if ctx.renderData.calls.len <= 0:
    return

  when NVG_STATS:
    var
      npix = default(float32)
      npixedges = default(float32)

    for idx in 0 ..< ctx.renderData.calls.len:
      let
        call = ctx.renderData.calls[idx].addr
        lt = ctx.verts[call.triangleOffset]
        rb = ctx.verts[call.triangleOffset + 3]
        callpix = (rb[0] - lt[0]) * (rb[1] - lt[1])

      npix = npix + callpix
      npixedges = float32(call.fillCount) * callpix

  glUseProgram(ctx.shaderProgram.program)
  glDisable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glDisable(GL_DEPTH_TEST)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.vertArr)

  glBindBuffer(GL_ARRAY_BUFFER, ctx.vertBuf)

  glBufferData(
    GL_ARRAY_BUFFER,
    GLsizeiptr(ctx.renderData.verts.len * sizeof(Vec4)),
    ctx.renderData.verts[0].addr,
    GL_STREAM_DRAW,
  )

  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  glVertexAttribPointer(0, 2, cGL_FLOAT, GL_FALSE, GLsizei(sizeof(Vec4)), nil)
  glVertexAttribPointer(
    1, 2, cGL_FLOAT, GL_FALSE, GLsizei(sizeof(Vec4)), cast[pointer](2 * sizeof(float32))
  )

  let layerSize = TILE_IMAGE_WIDTH * TILE_IMAGE_WIDTH
  let layerCount = block:
    let n = if (ctx.renderData.edges.len mod layerSize) > 0: 1 else: 0
    ctx.renderData.edges.len div layerSize + n

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texEdge)
  glBindSampler(0, ctx.smpDummy)

  let capacity = int(ceil(float32(ctx.renderData.edges.len) / float32(
      layerSize))) * layerSize
  ctx.renderData.edges.setLen(capacity)

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
    ctx.renderData.edges[0].addr,
  )

  glActiveTexture(GL_TEXTURE1)
  glBindTexture(GL_TEXTURE_2D, 0)

  let viewBounds = [ctx.viewBounds[0], ctx.viewBounds[1], 0, 0]
  glUniform4fv(
    ctx.shaderProgram.viewLoc, 1, cast[ptr GLfloat](viewBounds[0].addr)
  )

  glUniform1i(ctx.shaderProgram.texLoc, 1)
  glUniform1i(ctx.shaderProgram.edgeTexLoc, 0)

  for idx in 0 ..< ctx.renderData.calls.len:
    let
      call = ctx.renderData.calls[idx].addr
      blend = call.blend

      prevBlend = block:
        if idx > 0:
          ctx.renderData.calls[idx - 1].blend
        else:
          default(CompositeOperation)

    if idx == 0 or call.uniformOffset != ctx.renderData.calls[idx -
        1].uniformOffset:
      let uniform = ctx.renderData.uniforms[call.uniformOffset].addr
      gluniform4fv(ctx.shaderProgram.paintLoc, 7, cast[ptr GLfloat](uniform))

    if idx <= 0 or blend != prevBlend:
      let blend = toOpenglBlend(blend)
      glBlendFuncSeparate(blend.srcRGB, blend.dstRGB, blend.srcAlpha,
          blend.dstAlpha)

    let params = [call.fillCount, call.fillOffset, 0, 0]
    glUniform4iv(ctx.shaderProgram.fillLoc, 1, cast[ptr GLint](params[0].addr))

    if call.texture.isNil:
      glBindSampler(1, ctx.smpDummy)
    else:
      let tex = OpenglTexture(call.texture)
      glBindSampler(1, tex.smp)
      glBindTexture(GL_TEXTURE_2D, tex.texImage)

    if call.callType == FillCall:
      glDrawArrays(
        GL_TRIANGLE_STRIP, GLint(call.triangleOffset), GLsizei(
            call.triangleCount)
      )
    elif call.callType == ConvexFillCall:
      glDrawArrays(
        GL_TRIANGLE_FAN, GLint(call.triangleOffset), GLsizei(call.triangleCount)
      )
    elif call.callType == TrianglesCall:
      glDrawArrays(
        GL_TRIANGLES, GLint(call.triangleOffset), GLsizei(call.triangleCount)
      )

  glDisableVertexAttribArray(0)
  glDisableVertexAttribArray(1)

  when NVG_USE_GLCORE:
    glBindVertexArray(0)

  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glUseProgram(0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindSampler(1, 0)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, 0)
  glBindSampler(0, 0)

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
