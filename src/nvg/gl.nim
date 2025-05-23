import pkg/vmath
import pkg/opengl
import pkg/chroma

import ./core
import ./params
import ./pieces
import ./tiles

import ./glsl

when defined(NVG_DEBUG_VERTS):
  proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

const
  NVG_USE_GLES3 = false
  NVG_USE_GLCORE = true
  NVG_STATS = false

const TILE_IMAGE_WIDTH = 256

type
  ShaderType = enum
    FillSimple
    FillSolid
    FillGradient
    # FillImage
    # FillText

  ShaderProgramObj = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    viewLoc: GLint
    texLoc: GLint
    edgeTexLoc: GLint
    fillLoc: GLint
    paintLoc: GLint

  VertexUniformObj = object
    view: Vec2
    pad: array[8, uint8]

  CallType = enum
    FillCall = 1
    ConvexFillCall
    TrianglesCall

  BlendObj = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

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
    shaderProgram: ShaderProgramObj
    vertBuf: GLuint
    vertArr: GLuint
    sampler: GLuint
    fragmentBuf: GLint
    texEdges: GLuint
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
    result = result or (1 shl 2)

proc toUniform(
    ctx: ptr OpenglBackendContextObj, paint: ptr PaintObj, pathFlags: PathFlags
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
    paint: ptr PaintObj,
    compositeOperation: CompositeOperation,
    pathFlags: PathFlags,
    bounds: Vec4,
    paths: openArray[PathObj],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  var
    ncalls = 1
    nedges = 0

  for p in paths:
    inc nedges, p.fill.len

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

  when defined(NVG_DEBUG_VERTS):
    printf(
      "ncalls[%u] npaths[%u] convex[%u] nfill[%u]\n",
      ncalls,
      paths.len,
      paths[0].convex,
      paths[0].fill.len,
    )

  call.callType = FillCall
  call.blend = toBlend(compositeOperation)
  call.uniformOffset = uint32(ctx.uniforms.len)

  ctx.uniforms.add(ctx.toUniform(paint, pathFlags))

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
        #     printf("%.6f %.6f %.6f %.6f\n", vert.x, vert.y, vert.z, vert.w)

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
    var callbnds = [1e6f, 1e6f, -1e6f, -1e6f]

    for p in paths:
      callbnds[0] = min(callbnds[0], p.bounds[0])
      callbnds[1] = min(callbnds[1], p.bounds[1])
      callbnds[2] = min(callbnds[2], p.bounds[1])
      callbnds[3] = min(callbnds[3], p.bounds[1])

    callbnds[0] = max(ltrb[0], callbnds[0])
    callbnds[1] = max(ltrb[1], callbnds[1])
    callbnds[2] = min(ltrb[2], callbnds[2])
    callbnds[3] = min(ltrb[3], callbnds[3])

    if callbnds[0] < callbnds[2] and callbnds[1] < callbnds[3]:
      let offset = uint32(ctx.edges.len)

      for p in paths:
        ctx.edges.add(p.fill.toOpenArray)

      call.fillOffset = offset
      call.fillCount = uint32(ctx.edges.len) - offset
      call.triangleOffset = uint32(ctx.verts.len)
      call.triangleCount = 4

      ctx.verts.addQuad(callbnds, 0.5)
      ctx.calls.add(call)

  when defined(NVG_DEBUG_VERTS):
    printf("nverts: %u\n", uint32(ctx.verts.len))
    for vert in ctx.verts:
      printf("%.6f %.6f %.6f %.6f\n", vert.x, vert.y, vert.z, vert.w)

    printf("nedges: %u\n", uint32(ctx.edges.len))
    for vert in ctx.edges:
      printf("%.6f %.6f %.6f %.6f\n", vert.x, vert.y, vert.z, vert.w)

    printf("ncalls: %u\n", uint32(ctx.calls.len))
    for call in ctx.calls:
      printf(
        "type: %u, shaderType: %u, image: %u, fillOffset: %u, fillCount: %u, triangleOffset: %u, triangleCount: %u, uniformOffset: %u\n",
        call.callType, call.shaderType, 0, call.fillOffset, call.fillCount,
        call.triangleOffset, call.triangleCount, call.uniformOffset,
      )

    printf("nuniforms: %u\n", uint32(ctx.uniforms.len))
    for uniform in ctx.uniforms:
      printf(
        "transform: %.6f %.6f %.6f %.6f\ninnerColor: %.6f %.6f %.6f %.6f\nouterColor: %.6f %.6f %.6f %.6f\nextent: %.6f %.6f\nradius: %.6f\nfeather: %.6f\nstrokeMult: %.6f\nstrokeThr: %.6f\ntexType: %u\nfillType: %u\n",
        uniform.transform[0],
        uniform.transform[1],
        uniform.transform[2],
        uniform.transform[3],
        uniform.innerColor.r,
        uniform.innerColor.g,
        uniform.innerColor.b,
        uniform.innerColor.a,
        uniform.outerColor.r,
        uniform.outerColor.g,
        uniform.outerColor.b,
        uniform.outerColor.a,
        uniform.extent[0],
        uniform.extent[1],
        uniform.radius,
        uniform.feather,
        0, # uniform.strokeMult,
        0, # uniform.strokeThr,
        uniform.texType,
        uniform.fillType,
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
  result.texLoc = glGetUniformLocation(program, "imageTex")
  result.edgeTexLoc = glGetUniformLocation(program, "edgeTex")
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

  ctx.verts.setLen(0)
  ctx.edges.setLen(0)
  ctx.calls.setLen(0)
  ctx.uniforms.setLen(0)

proc viewportImpl(ctx: pointer, view: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  cancelImpl(ctx)

  ctx.vertexUniform.view = view

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  if ctx.calls.len <= 0:
    return

  when NVG_STATS:
    var
      npix = default(float32)
      npixedges = default(float32)

    for idx in 0 ..< ctx.calls.len:
      let
        call = ctx.calls[idx].addr
        lt = ctx.verts[call.triangleOffset]
        rb = ctx.verts[call.triangleOffset + 3]
        callpix = (rb.x - lt.x) * (rb.y - lt.y)

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
    GLsizeiptr(ctx.verts.len * sizeof(Vec4)),
    ctx.verts[0].addr,
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
    let n = if (ctx.edges.len mod layerSize) > 0: 1 else: 0
    ctx.edges.len div layerSize + n

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D_ARRAY, ctx.texEdges)
  glBindSampler(0, ctx.sampler)

  let capacity = int(ceil(float32(ctx.edges.len) / float32(layerSize))) * layerSize
  ctx.edges.setLen(capacity)

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
    ctx.edges[0].addr,
  )

  glActiveTexture(GL_TEXTURE1)
  glBindSampler(1, ctx.sampler)
  glBindTexture(GL_TEXTURE_2D, 0)

  glUniform4fv(
    ctx.shaderProgram.viewLoc, 1, cast[ptr GLfloat](ctx.vertexUniform.view.addr)
  )
  glUniform1i(ctx.shaderProgram.texLoc, 0)
  glUniform1i(ctx.shaderProgram.edgeTexLoc, 1)

  for idx in 0 ..< ctx.calls.len:
    let
      call = ctx.calls[idx].addr
      blend = call.blend.addr
      prevBlend = block:
        if idx > 0:
          ctx.calls[idx - 1].blend.addr
        else:
          nil

    if idx == 0 or call.uniformOffset != ctx.calls[idx - 1].uniformOffset:
      let uniform = ctx.uniforms[call.uniformOffset].addr
      gluniform4fv(ctx.shaderProgram.paintLoc, 7, cast[ptr GLfloat](uniform))

    if prevBlend.isNil or blend.srcRGB != prevBlend.srcRGB or
        blend.srcAlpha != prevBlend.srcAlpha or blend.dstRGB != prevBlend.dstRGB or
        blend.dstAlpha != prevBlend.dstAlpha:
      glBlendFuncSeparate(blend.srcRGB, blend.dstRGB, blend.srcAlpha, blend.dstAlpha)

    let params = [call.fillCount, call.fillOffset, 0, 0]
    glUniform4iv(ctx.shaderProgram.fillLoc, 1, cast[ptr GLint](params[0].addr))

    if call.callType == FillCall:
      glDrawArrays(
        GL_TRIANGLE_STRIP, GLint(call.triangleOffset), GLsizei(call.triangleCount)
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

proc newContext*(): ptr ContextObj =
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
