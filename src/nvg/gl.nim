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
  ShaderProgramObj = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    viewLoc: GLint
    texLoc: GLint
    edgeTexLoc: GLint
    fillLoc: GLint
    paintLoc: GLint

  Blend = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  OpenglBackendContextObj = object
    shaderProgram: ShaderProgramObj
    vertBuf: GLuint
    vertArr: GLuint
    sampler: GLuint
    fragmentBuf: GLint
    texEdges: GLuint

    viewBounds: Vec2
    renderData: RenderData

proc toBlend(op: CompositeOperation): Blend {.inline.} =
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

proc createProgram(vs, fs: cstring): ShaderProgramObj =
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
    ctx.shaderProgram = createProgram(
      cast[cstring](vsSourceGlsl410[0].addr), cast[cstring](fsSourceGlsl410[0].addr)
    )
    glGenVertexArrays(1, ctx.vertArr.addr)
  else:
    ctx.shaderProgram = createProgram(
      cast[cstring](vsSourceGlsl300es[0].addr), cast[cstring](fsSourceGlsl300es[0].addr)
    )

  glGenBuffers(1, ctx.vertBuf.addr)
  glGenTextures(1, ctx.texEdges.addr)

  glGenSamplers(1, ctx.sampler.addr)
  glSamplerParameteri(ctx.sampler, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glSamplerParameteri(ctx.sampler, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

  glFinish()

  ctx

proc destroyImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  if ctx.shaderProgram.vsShader != 0:
    glDeleteShader(ctx.shaderProgram.vsShader)
  if ctx.shaderProgram.fsShader != 0:
    glDeleteShader(ctx.shaderProgram.fsShader)
  when NVG_USE_GLCORE:
    if ctx.vertArr != 0:
      glDeleteVertexArrays(1, ctx.vertArr.addr)
  if ctx.vertBuf != 0:
    glDeleteBuffers(1, ctx.vertBuf.addr)
  if ctx.texEdges != 0:
    glDeleteTextures(1, ctx.texEdges.addr)

  reset(ctx[])
  dealloc(ctx)

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.renderData.clear()

proc viewportImpl(ctx: pointer, viewBounds: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.viewBounds = viewBounds
  cancelImpl(ctx)

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
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texEdges)
  glBindSampler(0, ctx.sampler)

  let capacity = int(ceil(float32(ctx.renderData.edges.len) / float32(layerSize))) * layerSize
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
  glBindSampler(1, ctx.sampler)
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

    if idx == 0 or call.uniformOffset != ctx.renderData.calls[idx - 1].uniformOffset:
      let uniform = ctx.renderData.uniforms[call.uniformOffset].addr
      gluniform4fv(ctx.shaderProgram.paintLoc, 7, cast[ptr GLfloat](uniform))

    if idx <= 0 or blend != prevBlend:
      let blend = toBlend(blend)
      glBlendFuncSeparate(blend.srcRGB, blend.dstRGB, blend.srcAlpha,
          blend.dstAlpha)

    let params = [call.fillCount, call.fillOffset, 0, 0]
    glUniform4iv(ctx.shaderProgram.fillLoc, 1, cast[ptr GLint](params[0].addr))

    if call.callType == FillCall:
      glDrawArrays(
        GL_TRIANGLE_STRIP, GLint(call.triangleOffset), GLsizei(
            call.triangleCount)
      )
    elif call.callType == ConvexFillCall:
      glDrawArrays(
        GL_TRIANGLE_FAN, GLint(call.triangleOffset), GLsizei(call.triangleCount)
      )
    elif call.callType != TrianglesCall:
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
      trianglesImpl: nil,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
