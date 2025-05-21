import vmath
import opengl
import chroma

import ./core
import ./pool
import ./params
import ./seqs
import ./slice2

type
  ShaderType = enum
    FillGradientShader
    FillImageShader
    SimpleShader
    ImageShader
    BlurImageShader

  ShaderObj = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint
    viewLoc: GLint
    texLoc: GLint
    colorMapLoc: GLint
    fragmentLoc: GLint

  TextureObj = object
    id: Vid
    tex: GLuint
    size: IVec2
    tp: TextureType
    imageFlags: ImageFlags

  VertexUniformObj = object
    view: Vec2
    pad: array[8, uint8]

  CallType = enum
    FillCall = 1
    FillConvexCall
    StrokeCall
    TrianglesCall

  BlendObj = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  CallObj = object
    callType: CallType
    image: ImageId
    colorMap: ImageId
    clipContourOffset: uint32
    clipContourCount: uint32
    pathOffset: uint32
    pathCount: uint32
    triangleOffset: uint32
    triangleCount: uint32
    uniformOffset: uint32
    blend: BlendObj

  Contour2Obj = object
    fillOffset: uint32
    fillCount: uint32
    strokeOffset: uint32
    strokeCount: uint32

  FragmentUniformObj = object
    extent: Vec2
    blurDir: Vec2
    innerColor: Color
    outerColor: Color
    paintMat: Mat3
    shaderType: uint32
    texType: uint32
    radius: float32
    feather: float32
    pad: array[12, uint8]

  OpenglBackendContextObj = object
    shader: ShaderObj
    texturePool: Pool[TextureObj]
    vertBuf: GLuint
    vertArr: GLuint
    vertexUniform: VertexUniformObj
    calls: seq[CallObj]
    contours: seq[Contour2Obj]
    verts: seq[Vec4]
    uniforms: seq[FragmentUniformObj]

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
    assert false

  s

proc createShader(vs, fs: cstring): ShaderObj =
  let
    program = glCreateProgram()
    vsShader = createGlShader(GL_VERTEX_SHADER, vs)
    fsShader = createGlShader(GL_FRAGMENT_SHADER, fs)

  glAttachShader(program, vsShader)
  glAttachShader(program, fsShader)

  glBindAttribLocation(program, 0, "vertex")
  glBindAttribLocation(program, 1, "tcoord")

  glLinkProgram(program)

  var status = default(GLint)

  glGetProgramiv(program, GL_LINK_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    assert false

  ShaderObj(
    program: program,
    fsShader: fsShader,
    vsShader: vsShader,
    viewLoc: glGetUniformLocation(program, "viewSize"),
    texLoc: glGetUniformLocation(program, "tex_smp"),
    colorMapLoc: glGetUniformLocation(program, "colorMap_smp"),
    fragmentLoc: glGetUniformLocation(program, "frag_arr"),
  )

proc bindTexture(ctx: ptr OpenglBackendContextObj, imageId: ImageId) =
  if int(imageId) != 0:
    let tex = ctx.texturePool[Vid(imageId)]
    assert not tex.isNil

    glBindTexture(GL_TEXTURE_2D, tex.tex)
  else:
    glBindTexture(GL_TEXTURE_2D, 0)

proc applyUniforms(
    ctx: ptr OpenglBackendContextObj,
    uniform: ptr FragmentUniformObj,
    imageId: ImageId,
    colorMap: ImageId,
) =
  glUniform4fv(
    ctx.shader.fragmentLoc,
    GLsizei(sizeof(FragmentUniformObj) / sizeof(Vec4)),
    cast[ptr GLfloat](uniform),
  )

  glActiveTexture(GL_TEXTURE1)
  ctx.bindTexture(colorMap)

  glActiveTexture(GL_TEXTURE0)
  ctx.bindTexture(imageId)

proc fillContours(ctx: ptr OpenglBackendContextObj, offset, count: uint32) {.inline.} =
  var
    i = offset
    j = offset + count - 1

  while i <= j:
    glDrawArrays(
      GL_TRIANGLE_FAN,
      GLint(ctx.contours[i].fillOffset),
      GLsizei(ctx.contours[i].fillCount),
    )
    inc i, 1

proc strokeContours(
    ctx: ptr OpenglBackendContextObj, offset, count: uint32
) {.inline.} =
  var
    i = offset
    j = offset + count - 1

  while i <= j:
    glDrawArrays(
      GL_TRIANGLE_STRIP,
      GLint(ctx.contours[i].strokeOffset),
      GLsizei(ctx.contours[i].strokeCount),
    )
    inc i, 1

template getAddr(body): auto =
  when NimMajor > 1: body.addr else: body.unsafeAddr

proc stencilClipPaths(ctx: ptr OpenglBackendContextObj, call: ptr CallObj) =
  let simple = FragmentUniformObj(shaderType: uint32(SimpleShader))
  ctx.applyUniforms(simple.getAddr, default(ImageId), default(ImageId))

  const convex = false
  if convex:
    glStencilMask(0x80)
    glStencilFunc(GL_ALWAYS, 0x80, 0xFF)
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)

    ctx.fillContours(call.clipContourOffset, call.clipContourCount)
  else:
    glStencilMask(0x7F)
    glStencilFunc(GL_ALWAYS, 0x00, 0xFF)
    glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP)
    glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP)
    glDisable(GL_CULL_FACE)

    ctx.fillContours(call.clipContourOffset, call.clipContourCount)

    glEnable(GL_CULL_FACE)

    # cover step
    glStencilFunc(GL_NOTEQUAL, 0x80, 0x7F)
    glStencilMask(0xFF)
    glStencilOp(GL_ZERO, GL_ZERO, GL_REPLACE)
    glDrawArrays(
      GL_TRIANGLE_STRIP, GLint(call.triangleOffset), GLsizei(call.triangleCount)
    )

proc fill(ctx: ptr OpenglBackendContextObj, call: ptr CallObj) =
  glEnable(GL_STENCIL_TEST)

  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)

  if call.clipContourCount > 0:
    ctx.stencilClipPaths(call)

    glStencilFunc(GL_EQUAL, 0x80, 0x80)
    glStencilMask(0x7F)
  else:
    glStencilFunc(GL_ALWAYS, 0x00, 0xFF)
    glStencilMask(0xFF)

  let
    uniform1 = ctx.uniforms[call.uniformOffset].addr
    uniform2 = ctx.uniforms[call.uniformOffset + 1].addr
  ctx.applyUniforms(uniform1, call.image, call.colorMap)

  glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP)
  glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP)
  glDisable(GL_CULL_FACE)

  ctx.fillContours(call.pathOffset, call.pathCount)
  glEnable(GL_CULL_FACE)

  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)

  ctx.applyUniforms(uniform2, call.image, call.colorMap)

  glStencilFunc(GL_NOTEQUAL, 0x00, 0x7F)
  glStencilMask(0xFF)
  glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO)

  glDrawArrays(
    GL_TRIANGLE_STRIP, GLint(call.triangleOffset), GLsizei(call.triangleCount)
  )
  glDisable(GL_STENCIL_TEST)

proc fillConvex(ctx: ptr OpenglBackendContextObj, call: ptr CallObj) =
  if call.clipContourCount > 0:
    glEnable(GL_STENCIL_TEST)
    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)

    ctx.stencilClipPaths(call)

    glStencilFunc(GL_EQUAL, 0x80, 0xFF)
    glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO)

    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)

  let uniform = ctx.uniforms[call.uniformOffset].addr
  ctx.applyUniforms(uniform, call.image, call.colorMap)

  ctx.fillContours(call.pathOffset, call.pathCount)

  if call.clipContourCount > 0:
    glDisable(GL_STENCIL_TEST)

proc stroke(ctx: ptr OpenglBackendContextObj, call: ptr CallObj) =
  if call.clipContourCount > 0:
    glEnable(GL_STENCIL_TEST)
    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE)

    ctx.stencilClipPaths(call)

    glStencilFunc(GL_EQUAL, 0x80, 0xFF)
    glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO)

    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)

  let uniform = ctx.uniforms[call.uniformOffset].addr
  ctx.applyUniforms(uniform, call.image, call.colorMap)

  ctx.strokeContours(call.pathOffset, call.pathCount)

  if call.clipContourCount > 0:
    glDisable(GL_STENCIL_TEST)

proc triangles(ctx: ptr OpenglBackendContextObj, call: ptr CallObj) =
  let uniform = ctx.uniforms[call.uniformOffset].addr
  ctx.applyUniforms(uniform, call.image, call.colorMap)

  glDrawArrays(GL_TRIANGLES, GLint(call.triangleOffset), GLsizei(call.triangleCount))

proc toUniform(ctx: ptr OpenglBackendContextObj, paint: ptr Paint): FragmentUniformObj =
  result = default(FragmentUniformObj)
  result.innerColor = paint.innerColor
  result.outerColor = paint.outerColor
  result.extent = paint.extent

  if int(paint.image) != 0:
    let tex = ctx.texturePool[Vid(int(paint.image))]
    assert not tex.isNil

    if tex.imageFlags.flipY:
      let
        m1 = translate(vec2(0, paint.extent[1] * 0.5)) * paint.transform
        m2 = scale(vec2(1, -1)) * m1
        m3 = translate(vec2(0, -paint.extent[1] * 0.5)) * m2
      result.paintMat = inverse(m3)
    else:
      result.paintMat = inverse(paint.transform)

    if tex.tp == RGBA:
      if tex.imageFlags.premultiplied:
        result.texType = 0
      else:
        result.texType = 1
    elif int(paint.colorMap) == 0:
      result.texType = 2
    else:
      result.texType = 3

    if paint.blur[0] > 0 or paint.blur[1] > 0:
      result.shaderType = uint32(BlurImageShader)
      result.blurDir = paint.blur
    else:
      result.shaderType = uint32(FillImageShader)
  else:
    result.paintMat = inverse(paint.transform)
    result.shaderType = uint32(FillGradientShader)
    result.radius = paint.radius
    result.feather = paint.feather

template ternaryExpr(cond, body1, body2: untyped): auto =
  if cond: body1 else: body2

proc createTextureImpl(
    ctx: pointer,
    tp: TextureType,
    size: IVec2,
    imageFlags: ImageFlags,
    data: openArray[byte],
): ImageId =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let
    vid = ctx.texturePool.allocVid()
    tex = ctx.texturePool[vid]

  glGenTextures(1, tex.tex.addr)
  tex.size = size
  tex.tp = tp
  tex.imageFlags = imageFlags

  if imageFlags.generateMipmaps:
    glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, GLint(GL_TRUE))

  if data.len > 0:
    if tp == ALPHA:
      glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
      glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GLint(GL_LUMINANCE),
        size.x,
        size.y,
        0,
        GL_LUMINANCE,
        GL_UNSIGNED_BYTE,
        data[0].getAddr,
      )
      glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    elif tp == RGBA:
      glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GLint(GL_RGBA),
        size.x,
        size.y,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        data[0].getAddr,
      )

  if imageFlags.generateMipmaps:
    glTexParameteri(
      GL_TEXTURE_2D,
      GL_TEXTURE_MIN_FILTER,
      ternaryExpr(
        imageFlags.nearestNeighborFilter, GL_NEAREST_MIPMAP_NEAREST,
        GL_LINEAR_MIPMAP_LINEAR,
      ),
    )
  else:
    glTexParameteri(
      GL_TEXTURE_2D,
      GL_TEXTURE_MIN_FILTER,
      ternaryExpr(imageFlags.nearestNeighborFilter, GL_NEAREST, GL_LINEAR),
    )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    ternaryExpr(imageFlags.nearestNeighborFilter, GL_NEAREST, GL_LINEAR),
  )

  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_S,
    ternaryExpr(imageFlags.repeatX, GL_REPEAT, GL_CLAMP_TO_EDGE),
  )
  glTexParameteri(
    GL_TEXTURE_2D,
    GL_TEXTURE_WRAP_T,
    ternaryExpr(imageFlags.repeatY, GL_REPEAT, GL_CLAMP_TO_EDGE),
  )

  if imageFlags.generateMipmaps:
    glGenerateMipmap(GL_TEXTURE_2D)

  ImageId(vid)

proc deleteTextureImpl(ctx: pointer, image: ImageId) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.texturePool[Vid(image)]
  assert not tex.isNil

  if tex.tex != 0:
    glDeleteTextures(1, tex.tex.addr)

  ctx.texturePool.releaseVid(Vid(image))

proc updateTextureImpl(
    ctx: pointer,
    image: ImageId,
    size: IVec4,
    imageFlags: ImageFlags,
    data: openArray[byte],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.texturePool[Vid(image)]
  assert not tex.isNil

  let
    x = 0
    w = tex.size.x
    y0 = size.y * tex.size.x
    colorSize = ternaryExpr(tex.tp == RGBA, 4, 1)
    p = data[y0 * colorSize].getAddr

  glBindTexture(GL_TEXTURE_2D, tex.tex)

  if tex.tp == ALPHA:
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glTexSubImage2D(
      GL_TEXTURE_2D,
      0,
      GLint(x),
      GLint(size.y),
      w,
      size.w,
      GL_LUMINANCE,
      GL_UNSIGNED_BYTE,
      p,
    )
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  elif tex.tp == RGBA:
    glTexSubImage2D(
      GL_TEXTURE_2D, 0, GLint(x), GLint(size.y), w, size.w, GL_RGBA, GL_UNSIGNED_BYTE, p
    )

  glBindTexture(GL_TEXTURE_2D, 0)

proc getTextureSizeImpl(ctx: pointer, image: ImageId): IVec2 =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  let tex = ctx.texturePool[Vid(image)]
  assert not tex.isNil

  tex.size

proc viewportImpl(ctx: pointer, view: Vec2, devicePixelRatio: float32) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.vertexUniform.view = view

proc maxVertCount(contours: openArray[ContourObj]): uint32 {.inline.} =
  result = 0

  for p in contours:
    inc result, p.fill.len
    inc result, p.stroke.len

proc toBlend(op: CompositeOperation): BlendObj =
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

proc addCall(
    ctx: ptr OpenglBackendContextObj,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    bounds: Vec4,
    clipContours: openArray[ContourObj],
    contours: openArray[ContourObj],
    isFill: static[bool],
) =
  var call = default(CallObj)
  call.callType =
    if isFill:
      if contours.len == 1 and contours[0].convex: FillConvexCall else: FillCall
    else:
      StrokeCall

  if isFill or clipContours.len > 0:
    call.triangleCount = 4
  else:
    call.triangleCount = 0

  let vertCount =
    maxVertCount(clipContours) + maxVertCount(contours) + call.triangleCount

  ctx.verts.reserve(vertCount)

  if clipContours.len > 0:
    ctx.contours.reserve(clipContours.len)
    call.clipContourOffset = uint32(ctx.contours.len)
    call.clipContourCount = 0

    for p in clipContours:
      if p.fill.len > 0:
        var path = default(Contour2Obj)
        path.fillOffset = uint32(ctx.verts.len)
        path.fillCount = uint32(p.fill.len)

        ctx.contours.add(path)
        ctx.verts.add(p.fill.toOpenArray)

        inc call.clipContourCount, 1

  ctx.contours.reserve(contours.len)
  call.pathOffset = uint32(ctx.contours.len)
  call.pathCount = 0
  call.image = paint.image
  call.colorMap = paint.colorMap
  call.blend = toBlend(compositeOperation)
  call.uniformOffset = uint32(ctx.uniforms.len)

  for p in contours:
    var
      used = false
      path = default(Contour2Obj)

    if isFill or p.fill.len > 0:
      used = true
      path.fillOffset = uint32(ctx.verts.len)
      path.fillCount = uint32(p.fill.len)

      ctx.verts.add(p.fill.toOpenArray)

    if p.stroke.len > 0:
      used = true
      path.strokeOffset = uint32(ctx.verts.len)
      path.strokeCount = uint32(p.stroke.len)

      ctx.verts.add(p.stroke.toOpenArray)

    if used:
      ctx.contours.add(path)

      inc call.pathCount, 1

  if call.triangleCount > 0:
    call.triangleOffset = uint32(ctx.verts.len)

    ctx.verts.add(vec4(bounds[2], bounds[3], 0.5, 1.0))
    ctx.verts.add(vec4(bounds[2], bounds[1], 0.5, 1.0))
    ctx.verts.add(vec4(bounds[0], bounds[3], 0.5, 1.0))
    ctx.verts.add(vec4(bounds[0], bounds[1], 0.5, 1.0))

  ctx.calls.add(call)

  if call.callType == FillCall:
    ctx.uniforms.add(FragmentUniformObj(shaderType: uint32(SimpleShader)))
  ctx.uniforms.add(ctx.toUniform(paint))

proc fillImpl(
    ctx: pointer,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    bounds: Vec4,
    clipContours: openArray[ContourObj],
    contours: openArray[ContourObj],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  ctx.addCall(paint, compositeOperation, bounds, clipContours, contours, true)

proc strokeImpl(
    ctx: pointer,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    bounds: Vec4,
    clipContours: openArray[ContourObj],
    contours: openArray[ContourObj],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)
  ctx.addCall(paint, compositeOperation, bounds, clipContours, contours, false)

proc trianglesImpl(
    ctx: pointer,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    verts: openArray[Vec4],
) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  var call = default(CallObj)
  call.callType = TrianglesCall
  call.image = paint.image
  call.colorMap = paint.colorMap

  call.triangleOffset = uint32(ctx.verts.len)
  call.triangleCount = uint32(verts.len)
  call.uniformOffset = uint32(ctx.uniforms.len)

  var uniform = ctx.toUniform(paint)
  uniform.shaderType = uint32(ImageShader)

  ctx.verts.add(verts)
  ctx.uniforms.add(uniform)

proc cancelImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  ctx.verts.clear()
  ctx.uniforms.clear()
  ctx.contours.clear()
  ctx.calls.clear()

proc flushImpl(ctx: pointer) =
  let ctx = cast[ptr OpenglBackendContextObj](ctx)

  if ctx.calls.len > 0:
    glUseProgram(ctx.shader.program)

    glEnable(GL_CULL_FACE)
    glCullFace(GL_BACK)
    glFrontFace(GL_CCW)
    glEnable(GL_BLEND)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_SCISSOR_TEST)
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE)
    glStencilMask(GLuint(0xFFFFFFFF))
    glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)
    glStencilFunc(GL_ALWAYS, 0, GLuint(0xFFFFFFFF))
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, 0)

    glBindVertexArray(ctx.vertArr)

    glBindBuffer(GL_ARRAY_BUFFER, ctx.vertBuf)
    glBufferData(
      GL_ARRAY_BUFFER, ctx.verts.len * sizeof(Vec4), ctx.verts[0].addr, GL_STREAM_DRAW
    )
    glEnableVertexAttribArray(0)
    glEnableVertexAttribArray(1)

    glVertexAttribPointer(0, 2, cGL_FLOAT, GL_FALSE, GLsizei(sizeof(Vec4)), nil)
    glVertexAttribPointer(
      1,
      2,
      cGL_FLOAT,
      GL_FALSE,
      GLsizei(sizeof(Vec4)),
      cast[pointer](2 * sizeof(float32)),
    )

    glUniform1i(ctx.shader.texLoc, 0)
    glUniform1i(ctx.shader.colorMap_loc, 1)
    glUniform4fv(ctx.shader.viewLoc, 1, cast[ptr GLfloat](ctx.vertexUniform.addr))

    for call in ctx.calls:
      glBlendFuncSeparate(
        call.blend.srcRGB, call.blend.dstRGB, call.blend.srcAlpha, call.blend.dstAlpha
      )

      case call.callType
      of FillCall:
        ctx.fill(call.getAddr)
      of FillConvexCall:
        ctx.fillConvex(call.getAddr)
      of StrokeCall:
        ctx.stroke(call.getAddr)
      of TrianglesCall:
        ctx.triangles(call.getAddr)

    glDisableVertexAttribArray(0)
    glDisableVertexAttribArray(1)
    glBindVertexArray(0)
    glDisable(GL_CULL_FACE)
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glUseProgram(0)
    glBindTexture(GL_TEXTURE_2D, 0)

  ctx.verts.clear()
  ctx.uniforms.clear()
  ctx.contours.clear()
  ctx.calls.clear()

proc createImpl(): pointer =
  let ctx = create(OpenglBackendContextObj)

  const
    vs =
      """
      #version 410

      uniform vec4 viewSize;

      layout(location = 0) out vec2 ftcoord;
      layout(location = 1) in vec2 tcoord;
      layout(location = 1) out vec2 fpos;
      layout(location = 0) in vec2 vertex;

      void main()
      {
          ftcoord = tcoord;
          fpos = vertex;
          gl_Position = vec4(((2.0 * vertex.x) / viewSize.x) - 1.0, 1.0 - ((2.0 * vertex.y) / viewSize.y), 0.0, 1.0);
      }
    """

    fs =
      """
      #version 410

      uniform vec4 frag_arr[7];
      uniform sampler2D tex_smp;
      uniform sampler2D colorMap_smp;

      layout(location = 1) in vec2 fpos;
      layout(location = 0) in vec2 ftcoord;
      layout(location = 0) out vec4 outColor;

      float sdroundrect(vec2 pt, vec2 ext, float rad)
      {
          vec2 _26 = abs(pt) - (ext - vec2(rad, rad));
          return (min(max(_26.x, _26.y), 0.0) + length(max(_26, vec2(0.0)))) - rad;
      }

      void main()
      {
          vec4 result = vec4(0.0);
          int _61 = int(frag_arr[5].y);
          if (_61 == 0)
          {
              vec2 param = (mat3(vec3(frag_arr[3].x, frag_arr[3].y, frag_arr[3].z), vec3(frag_arr[3].w, frag_arr[4].x, frag_arr[4].y), vec3(frag_arr[4].z, frag_arr[4].w, frag_arr[5].x)) * vec3(fpos, 1.0)).xy;
              vec2 param_1 = frag_arr[0].xy;
              float param_2 = float(int(frag_arr[5].w));
              float _134 = float(int(frag_arr[6].x));
              result = mix(frag_arr[1], frag_arr[2], vec4(clamp(fma(_134, 0.5, sdroundrect(param, param_1, param_2)) / _134, 0.0, 1.0)));
          }
          else
          {
              if (_61 == 1)
              {
                  vec4 color = texture(tex_smp, (mat3(vec3(frag_arr[3].x, frag_arr[3].y, frag_arr[3].z), vec3(frag_arr[3].w, frag_arr[4].x, frag_arr[4].y), vec3(frag_arr[4].z, frag_arr[4].w, frag_arr[5].x)) * vec3(fpos, 1.0)).xy / frag_arr[0].xy);
                  int _222 = int(frag_arr[5].z);
                  if (_222 == 1)
                  {
                      color = vec4(color.xyz * color.w, color.w);
                  }
                  if (_222 == 2)
                  {
                      color = vec4(color.x);
                  }
                  if (_222 == 3)
                  {
                      vec4 _259 = texture(colorMap_smp, vec2(color.x, 0.5));
                      float _263 = _259.w;
                      color = vec4(_259.xyz * _263, _263);
                  }
                  vec4 _273 = color;
                  vec4 _274 = _273 * frag_arr[1];
                  color = _274;
                  result = _274;
              }
              else
              {
                  if (_61 == 2)
                  {
                      result = vec4(1.0);
                  }
                  else
                  {
                      if (_61 == 3)
                      {
                          vec4 color_1 = texture(tex_smp, ftcoord);
                          int _300 = int(frag_arr[5].z);
                          if (_300 == 1)
                          {
                              color_1 = vec4(color_1.xyz * color_1.w, color_1.w);
                          }
                          if (_300 == 2)
                          {
                              color_1 = vec4(color_1.x);
                          }
                          if (_300 == 3)
                          {
                              vec4 _336 = texture(colorMap_smp, vec2(color_1.x, 0.5));
                              float _340 = _336.w;
                              color_1 = vec4(_336.xyz * _340, _340);
                          }
                          result = color_1 * frag_arr[1];
                      }
                      else
                      {
                          discard;
                      }
                  }
              }
          }
          outColor = result;
      }
    """

  let shader = createShader(vs, fs)

  glGenBuffers(1, ctx.vertBuf.addr)
  glGenVertexArrays(1, ctx.vertArr.addr)

  ctx.shader = shader
  ctx

proc destroyImpl(ctx: pointer) =
  let ctx = create(OpenglBackendContextObj)

  if ctx.shader.program != GLuint(0):
    glDeleteProgram(ctx.shader.program)

  if ctx.shader.vsShader != GLuint(0):
    glDeleteShader(ctx.shader.vsShader)

  if ctx.shader.fsShader != GLuint(0):
    glDeleteShader(ctx.shader.fsShader)

  if ctx.vertArr != GLuint(0):
    glDeleteVertexArrays(1, ctx.vertArr.addr)

  if ctx.vertBuf != GLuint(0):
    glDeleteBuffers(1, ctx.vertBuf.addr)

  reset(ctx[])

  dealloc(ctx)

proc newContext*(): ptr ContextObj =
  createInternal(
    BackendContextParams(
      createImpl: createImpl,
      destroyImpl: destroyImpl,
      createTextureImpl: createTextureImpl,
      deleteTextureImpl: deleteTextureImpl,
      updateTextureImpl: updateTextureImpl,
      getTextureSizeImpl: getTextureSizeImpl,
      fillImpl: fillImpl,
      strokeImpl: strokeImpl,
      trianglesImpl: trianglesImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
