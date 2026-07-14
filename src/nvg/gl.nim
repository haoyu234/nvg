import std/tables

import pkg/opengl

import ./backend
import ./core
import ./draw_list
import ./glsl_gen
import ./math
import ./tracy

const
  NVG_USE_GLES* = defined(feature.nvg.gles)
  NVG_USE_GLCORE* = defined(feature.nvg.glcore) or not NVG_USE_GLES

static:
  assert not (NVG_USE_GLCORE and NVG_USE_GLES)

const
  NVG_DEFAULT_STORAGE_CAPACITY = 32 * 1024

type
  OpenglShaderProgram = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    vsViewSizeLoc: GLint
    fsImageTexLoc: GLint
    fsExtentLoc: GLint
    fsPaintTransformIndexLoc: GLint
    fsRadiusLoc: GLint
    fsFeatherLoc: GLint
    fsRenderFlagsLoc: GLint

  OpenglGlyphShaderProgram = object
    program: GLuint
    fsShader: GLuint
    vsShader: GLuint

    vsViewSizeLoc: GLint
    vsMvpIndexLoc: GLint
    fsCurveTexLoc: GLint
    fsBandTexLoc: GLint
    fsImageTexLoc: GLint
    fsExtentLoc: GLint
    fsPaintTransformIndexLoc: GLint
    fsRadiusLoc: GLint
    fsFeatherLoc: GLint
    fsRenderFlagsLoc: GLint

  OpenglTexture = ref OpenglTextureObj
  OpenglTextureObj = object
    image: Image
    imageFlags: set[ImageFlags]
    texImage: GLuint
    smp: GLuint
    version: uint32

  StorageUsage = enum
    StorageUsageVertexBuffer
    StorageUsageStorageBuffer

  OpenglStorage = object
    usage: StorageUsage
    buffer: GLuint
    cap: int32

  OpenglBlend = object
    srcRGB: GLenum
    dstRGB: GLenum
    srcAlpha: GLenum
    dstAlpha: GLenum

  OpenglBackendContext = ref OpenglBackendContextObj
  OpenglBackendContextObj = object of BackendContext
    size: Vec2

    pathVao: GLuint
    glyphVao: GLuint

    shaderProgram: OpenglShaderProgram
    textShaderProgram: OpenglGlyphShaderProgram

    texDummy: GLuint
    smpDummy: GLuint

    drawList: DrawList

    edges: OpenglStorage
    paths: OpenglStorage
    glyphs: OpenglStorage
    transforms: OpenglStorage

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

proc `=destroy`(s: OpenglStorage) =
  tryCall glDeleteBuffers(1, s.buffer.addr)

proc `=destroy`(ctx: var OpenglBackendContextObj) =
  if ctx.shaderProgram.vsShader != 0:
    tryCall glDeleteShader(ctx.shaderProgram.vsShader)

  if ctx.shaderProgram.fsShader != 0:
    tryCall glDeleteShader(ctx.shaderProgram.fsShader)

  if ctx.shaderProgram.program != 0:
    tryCall glDeleteProgram(ctx.shaderProgram.program)

  if ctx.textShaderProgram.vsShader != 0:
    tryCall glDeleteShader(ctx.textShaderProgram.vsShader)

  if ctx.textShaderProgram.fsShader != 0:
    tryCall glDeleteShader(ctx.textShaderProgram.fsShader)

  if ctx.textShaderProgram.program != 0:
    tryCall glDeleteProgram(ctx.textShaderProgram.program)

  if ctx.pathVao != 0:
    tryCall glDeleteVertexArrays(1, ctx.pathVao.addr)

  if ctx.glyphVao != 0:
    tryCall glDeleteVertexArrays(1, ctx.glyphVao.addr)

  if ctx.texDummy != 0:
    tryCall glDeleteTextures(1, ctx.texDummy.addr)

  if ctx.smpDummy != 0:
    tryCall glDeleteSamplers(1, ctx.smpDummy.addr)

  `=destroy`(ctx.drawList)

  `=destroy`(ctx.edges)
  `=destroy`(ctx.paths)
  `=destroy`(ctx.glyphs)
  `=destroy`(ctx.transforms)
  `=destroy`(ctx.textures)

proc initStorage(s: var OpenglStorage, usage: StorageUsage) {.inline.} =
  s.usage = usage
  glGenBuffers(1, s.buffer.addr)

proc target(s: OpenglStorage): GLenum {.inline.} =
  case s.usage
  of StorageUsageVertexBuffer:
    result = GL_ARRAY_BUFFER
  of StorageUsageStorageBuffer:
    result = GL_SHADER_STORAGE_BUFFER

proc reserveStorage(s: var OpenglStorage, needBytes: int32) =
  var
    cap = s.cap * 2
  if cap < needBytes:
    cap = needBytes

  s.cap = cap
  glBindBuffer(s.target, s.buffer)
  glBufferData(s.target, GLsizeiptr(cap), nil,
      GL_DYNAMIC_DRAW)

proc updateStorage[T: Vec2 | Vec4 | Color | object](s: var OpenglStorage,
    data: var seq[T]) =
  if data.len <= 0:
    return

  let byteSize = int32(data.len * sizeof(T))

  glBindBuffer(s.target, s.buffer)

  if byteSize > s.cap:
    s.reserveStorage(max(byteSize, NVG_DEFAULT_STORAGE_CAPACITY))

  glBufferSubData(s.target, 0, GLsizeiptr(byteSize),
      data[0].addr)

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
  result = glCreateShader(tp)

  var
    p = source
    len = GLint(source.len)
    status = GLint(0)

  glShaderSource(result, GLsizei(1), cast[cstringArray](p.addr), len.addr)
  glCompileShader(result)

  glGetShaderiv(result, GL_COMPILE_STATUS, status.addr)

  if status != GLint(GL_TRUE):
    var
      buffer: array[256, char]
      pBuf = cast[cstring](buffer[0].addr)

    glGetShaderInfoLog(result, GLsizei(len(buffer)), nil, pBuf)
    echo $pBuf

proc createShaderProgram(vs, fs: cstring): OpenglShaderProgram =
  let
    program = glCreateProgram()
    vsShader = createGlShader(GL_VERTEX_SHADER, vs)
    fsShader = createGlShader(GL_FRAGMENT_SHADER, fs)

  glAttachShader(program, vsShader)
  glAttachShader(program, fsShader)

  glBindAttribLocation(program, 0, "v_fill_count")
  glBindAttribLocation(program, 1, "v_fill_offset")
  glBindAttribLocation(program, 2, "vs_draw_rect")
  glBindAttribLocation(program, 3, "v_fill_color")
  glBindAttribLocation(program, 4, "v_fill_outer_color")
  glBindAttribLocation(program, 5, "vs_backdrop_color")

  glLinkProgram(program)

  var
    status = GLint(0)

  glGetProgramiv(program, GL_LINK_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    var
      buffer: array[256, char]
      pBuf = cast[cstring](buffer[0].addr)

    glGetProgramInfoLog(program, GLsizei(len(buffer)), nil, pBuf)
    echo $pBuf

  result.program = program
  result.fsShader = fsShader
  result.vsShader = vsShader
  result.fsImageTexLoc = glGetUniformLocation(program, "image_tex_image_smp")
  result.vsViewSizeLoc = glGetUniformLocation(program, "_66.view_size")
  result.fsExtentLoc = glGetUniformLocation(program, "_261.extent")
  result.fsPaintTransformIndexLoc = glGetUniformLocation(program, "_261.paint_transform_index")
  result.fsRadiusLoc = glGetUniformLocation(program, "_261.radius")
  result.fsFeatherLoc = glGetUniformLocation(program, "_261.feather")
  result.fsRenderFlagsLoc = glGetUniformLocation(program, "_261.render_flags")

proc createGlyphShaderProgram(vs, fs: cstring): OpenglGlyphShaderProgram =
  let
    program = glCreateProgram()
    vsShader = createGlShader(GL_VERTEX_SHADER, vs)
    fsShader = createGlShader(GL_FRAGMENT_SHADER, fs)

  glAttachShader(program, vsShader)
  glAttachShader(program, fsShader)

  glBindAttribLocation(program, 0, "vs_draw_rect")
  glBindAttribLocation(program, 1, "vs_text_color")
  glBindAttribLocation(program, 2, "vs_backdrop_color")
  glBindAttribLocation(program, 3, "vs_glyph_params")
  glBindAttribLocation(program, 4, "vs_glyph_transform_index")

  glLinkProgram(program)

  var
    status = GLint(0)

  glGetProgramiv(program, GL_LINK_STATUS, status.addr)
  if status != GLint(GL_TRUE):
    var
      buffer: array[256, char]
      pBuf = cast[cstring](buffer[0].addr)

    glGetProgramInfoLog(program, GLsizei(len(buffer)), nil, pBuf)
    echo $pBuf

  result.program = program
  result.fsShader = fsShader
  result.vsShader = vsShader
  result.vsViewSizeLoc = glGetUniformLocation(program, "_70.view_size")
  result.vsMvpIndexLoc = glGetUniformLocation(program, "_70.mvp_index")
  result.fsCurveTexLoc = glGetUniformLocation(program, "curve_tex_point_sampler")
  result.fsBandTexLoc = glGetUniformLocation(program, "band_tex_band_smp")
  result.fsImageTexLoc = glGetUniformLocation(program, "image_tex_image_smp")
  result.fsExtentLoc = glGetUniformLocation(program, "_783.extent")
  result.fsPaintTransformIndexLoc = glGetUniformLocation(program, "_783.paint_transform_index")
  result.fsRadiusLoc = glGetUniformLocation(program, "_783.radius")
  result.fsFeatherLoc = glGetUniformLocation(program, "_783.feather")
  result.fsRenderFlagsLoc = glGetUniformLocation(program, "_783.render_flags")

proc initIfNeeded(ctx: OpenglBackendContext) =
  if ctx.initial:
    return

  ctx.initial = true

  when NVG_USE_GLCORE:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsPathSourceGlsl430[0].addr), cast[cstring](
          fsPathSourceGlsl430[0].addr)
    )
    ctx.textShaderProgram = createGlyphShaderProgram(
      cast[cstring](vsGlyphSourceGlsl430[0].addr), cast[cstring](
          fsGlyphSourceGlsl430[0].addr)
    )
    glGenVertexArrays(1, ctx.pathVao.addr)
    glGenVertexArrays(1, ctx.glyphVao.addr)

  when NVG_USE_GLES:
    ctx.shaderProgram = createShaderProgram(
      cast[cstring](vsPathSourceGlsl310es[0].addr), cast[cstring](
          fsPathSourceGlsl310es[0].addr)
    )
    ctx.textShaderProgram = createGlyphShaderProgram(
      cast[cstring](vsGlyphSourceGlsl310es[0].addr), cast[cstring](
          fsGlyphSourceGlsl310es[0].addr)
    )

  glGenTextures(1, ctx.texDummy.addr)

  ctx.edges.initStorage(StorageUsageStorageBuffer)
  ctx.paths.initStorage(StorageUsageVertexBuffer)
  ctx.glyphs.initStorage(StorageUsageVertexBuffer)
  ctx.transforms.initStorage(StorageUsageStorageBuffer)

  const
    pixels = [color(255, 255, 255, 255)]

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

  of PixelFormatRGBA32u:
    glTexImage2D(GL_TEXTURE_2D, 0, GLint(GL_RGBA32UI), imageInfo.width,
        imageInfo.height, 0, GL_RGBA_INTEGER, GL_UNSIGNED_INT, pixels)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)

  glGenSamplers(1, result.smp.addr)
  glSamplerParameteri(result.smp, GL_TEXTURE_MIN_FILTER, minFilter)
  glSamplerParameteri(result.smp, GL_TEXTURE_MAG_FILTER, magFilter)
  glSamplerParameteri(result.smp, GL_TEXTURE_WRAP_S, wrapX)
  glSamplerParameteri(result.smp, GL_TEXTURE_WRAP_T, wrapY)

  glBindTexture(GL_TEXTURE_2D, 0)

proc drawPathCall(ctx: OpenglBackendContext, idx: int32, drawCall: PathDrawCall,
    blend: CompositeOperation, prevBlend: CompositeOperation) =
  let
    zone = zoneBegin("opengl.drawPathCall")
  defer: zone.zoneEnd()

  if idx <= 0 or ctx.drawList.calls[idx - 1].kind != DrawCallPath or
      drawCall.uniformIndex != ctx.drawList.calls[idx -
          1].path.uniformIndex:
    let p = ctx.drawList.uniforms[drawCall.uniformIndex]
    glUniform2fv(ctx.shaderProgram.fsExtentLoc, 1, p.extent[0].addr)
    glUniform1i(ctx.shaderProgram.fsPaintTransformIndexLoc,
        p.paintTransformIndex)
    glUniform1f(ctx.shaderProgram.fsRadiusLoc, p.radius)
    glUniform1f(ctx.shaderProgram.fsFeatherLoc, p.feather)
    glUniform1i(ctx.shaderProgram.fsRenderFlagsLoc, int32(p.renderFlags))

  if idx <= 0 or blend != prevBlend:
    let openglBlend = toOpenglBlend(blend)
    glBlendFuncSeparate(openglBlend.srcRGB, openglBlend.dstRGB,
        openglBlend.srcAlpha, openglBlend.dstAlpha)

  glActiveTexture(GL_TEXTURE0)

  var tex = default(OpenglTexture)
  if not drawCall.imageId.isNil:
    tex = ctx.getTexture(drawCall.imageId)

  if tex.isNil:
    glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
    glBindSampler(0, ctx.smpDummy)
  else:
    glBindTexture(GL_TEXTURE_2D, tex.texImage)
    glBindSampler(0, tex.smp)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.pathVao)
    glDrawArraysInstancedBaseInstance(GL_TRIANGLE_STRIP, 0, 4,
        drawCall.instanceCount, GLuint(drawCall.instanceOffset))

  when NVG_USE_GLES:
    glBindBuffer(GL_ARRAY_BUFFER, ctx.paths.buffer)
    let
      offset = drawCall.instanceOffset * int32(sizeof(PathInstanceParam))
      stride = GLsizei(sizeof(PathInstanceParam))
    glVertexAttribIPointer(0, 1, cGL_INT, stride, cast[pointer](offset))
    glVertexAttribDivisor(0, 1)
    glVertexAttribIPointer(1, 1, cGL_INT, stride, cast[pointer](offset + sizeof(int32)))
    glVertexAttribDivisor(1, 1)
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
        cast[pointer](offset + sizeof(int32) * 2))
    glVertexAttribDivisor(2, 1)
    glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
        cast[pointer](offset + sizeof(int32) * 3))
    glVertexAttribDivisor(3, 1)
    glVertexAttribPointer(4, 4, cGL_FLOAT, GL_FALSE, stride,
        cast[pointer](offset + sizeof(int32) * 4))
    glVertexAttribDivisor(4, 1)
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, drawCall.instanceCount)

proc drawGlyphCall(ctx: OpenglBackendContext, idx: int32,
    drawCall: GlyphDrawCall, blend: CompositeOperation,
        prevBlend: CompositeOperation) =
  let
    zone = zoneBegin("opengl.drawGlyphCall")
  defer: zone.zoneEnd()

  glUniform2fv(ctx.textShaderProgram.vsViewSizeLoc, 1, ctx.size[0].addr)
  glUniform1i(ctx.textShaderProgram.vsMvpIndexLoc, drawCall.mvpIndex)

  if idx <= 0 or ctx.drawList.calls[idx - 1].kind != DrawCallGlyph or
      drawCall.uniformIndex != ctx.drawList.calls[idx -
          1].glyph.uniformIndex:
    let f = ctx.drawList.uniforms[drawCall.uniformIndex]
    glUniform2fv(ctx.textShaderProgram.fsExtentLoc, 1, f.extent[0].addr)
    glUniform1i(ctx.textShaderProgram.fsPaintTransformIndexLoc,
        f.paintTransformIndex)
    glUniform1f(ctx.textShaderProgram.fsRadiusLoc, f.radius)
    glUniform1f(ctx.textShaderProgram.fsFeatherLoc, f.feather)
    glUniform1i(ctx.textShaderProgram.fsRenderFlagsLoc, int32(f.renderFlags))

  if idx <= 0 or blend != prevBlend:
    let openglBlend = toOpenglBlend(blend)
    glBlendFuncSeparate(openglBlend.srcRGB, openglBlend.dstRGB,
        openglBlend.srcAlpha, openglBlend.dstAlpha)

  var
    curveTex = default(OpenglTexture)
    bandTex = default(OpenglTexture)
    imageTex = default(OpenglTexture)
  if not drawCall.curveImageId.isNil:
    curveTex = ctx.getTexture(drawCall.curveImageId)
  if not drawCall.bandImageId.isNil:
    bandTex = ctx.getTexture(drawCall.bandImageId)
  if not drawCall.imageId.isNil:
    imageTex = ctx.getTexture(drawCall.imageId)

  glActiveTexture(GL_TEXTURE4)
  if curveTex.isNil:
    glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
  else:
    glBindTexture(GL_TEXTURE_2D, curveTex.texImage)

  glActiveTexture(GL_TEXTURE5)
  if bandTex.isNil:
    glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
  else:
    glBindTexture(GL_TEXTURE_2D, bandTex.texImage)

  glActiveTexture(GL_TEXTURE6)
  if imageTex.isNil:
    glBindTexture(GL_TEXTURE_2D, ctx.texDummy)
    glBindSampler(6, ctx.smpDummy)
  else:
    glBindTexture(GL_TEXTURE_2D, imageTex.texImage)
    glBindSampler(6, imageTex.smp)
  glUniform1i(ctx.textShaderProgram.fsImageTexLoc, 6)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.glyphVao)
    glDrawArraysInstancedBaseInstance(GL_TRIANGLE_STRIP, 0, 4,
        drawCall.instanceCount, GLuint(drawCall.instanceOffset))

  when NVG_USE_GLES:
    let
      offset = drawCall.instanceOffset * int32(sizeof(GlyphInstanceParam))
      stride = GLsizei(sizeof(GlyphInstanceParam))
    glBindBuffer(GL_ARRAY_BUFFER, ctx.glyphs.buffer)
    glVertexAttribPointer(0, 4, cGL_FLOAT, GL_FALSE, stride, cast[pointer](offset))
    glVertexAttribDivisor(0, 1)
    glVertexAttribPointer(1, 4, cGL_FLOAT, GL_FALSE, stride,
        cast[pointer](offset + sizeof(Vec4)))
    glVertexAttribDivisor(1, 1)
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
        cast[pointer](offset + sizeof(Vec4) * 2))
    glVertexAttribDivisor(2, 1)
    glVertexAttribPointer(3, 4, cGL_FLOAT, GL_FALSE, stride,
        cast[pointer](offset + sizeof(Vec4) * 2 + sizeof(uint32)))
    glVertexAttribDivisor(3, 1)
    glVertexAttribIPointer(4, 4, cGL_INT, stride,
        cast[pointer](offset + sizeof(Vec4) * 3 + sizeof(uint32)))
    glVertexAttribDivisor(4, 1)
    glVertexAttribIPointer(5, 1, cGL_INT, stride,
        cast[pointer](offset + sizeof(Vec4) * 4 + sizeof(uint32)))
    glVertexAttribDivisor(5, 1)
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, drawCall.instanceCount)

method drawGlyphs*(ctx: OpenglBackendContext, paint: Paint, transform: Mat2d,
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

method drawPaths(ctx: OpenglBackendContext, paint: Paint,
    paths: openArray[DrawPath], fillRule: FillRule,
        compositeOperation: CompositeOperation) =
  var
    image = default(Image)
    imageFlags = default(set[ImageFlags])

  if not paint.imageId.isNil:
    let tex = ctx.getTexture(paint.imageId)
    if not tex.isNil:
      image = tex.image
      imageFlags = tex.imageFlags

  ctx.drawList.addPathCall(ctx.size, paint, image, imageFlags, paths, fillRule, compositeOperation)

method allocImage(ctx: OpenglBackendContext, imageInfo: ImageInfo,
    imageFlags: set[ImageFlags]): ImageId =
  let
    image = ctx.drawList.createImage(imageInfo)
    tex = ctx.createTexture(image, imageFlags)
  ctx.addTexture(image.imageId, tex)
  image.imageId

method getImageInfo(ctx: OpenglBackendContext, imageId: ImageId): ImageInfo =
  let
    tex = ctx.getTexture(imageId)

  if not tex.isNil:
    result = tex.image.imageInfo

method writeImagePixels(ctx: OpenglBackendContext, imageId: ImageId, x, y, w, h,
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

    of PixelFormatRGBA32u:
      glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h,
        GL_RGBA_INTEGER, GL_UNSIGNED_INT, data)

    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)

    if ImageGenerateMipmaps in tex.imageFlags:
      glGenerateMipmap(GL_TEXTURE_2D)

    glBindTexture(GL_TEXTURE_2D, 0)

method deleteImage(ctx: OpenglBackendContext, imageId: ImageId) =
  ctx.deleteTexture(imageId)

proc setupPathPipeline(ctx: OpenglBackendContext) =
  glUseProgram(ctx.shaderProgram.program)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.pathVao)

  glBindBuffer(GL_ARRAY_BUFFER, ctx.paths.buffer)

  glVertexAttribIPointer(0, 1, cGL_INT, GLsizei(sizeof(PathInstanceParam)), nil)
  glEnableVertexAttribArray(0)
  glVertexAttribDivisor(0, 1)

  glVertexAttribIPointer(1, 1, cGL_INT, GLsizei(sizeof(PathInstanceParam)),
      cast[pointer](sizeof(int32)))
  glEnableVertexAttribArray(1)
  glVertexAttribDivisor(1, 1)

  glVertexAttribPointer(2, 4, cGL_FLOAT, GL_FALSE,
      GLsizei(sizeof(PathInstanceParam)), cast[pointer](sizeof(int32) * 2))
  glEnableVertexAttribArray(2)
  glVertexAttribDivisor(2, 1)

  glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE,
      GLsizei(sizeof(PathInstanceParam)),
      cast[pointer](sizeof(Vec4) + sizeof(int32) * 2))
  glEnableVertexAttribArray(3)
  glVertexAttribDivisor(3, 1)

  glVertexAttribPointer(4, 4, GL_UNSIGNED_BYTE, GL_TRUE,
      GLsizei(sizeof(PathInstanceParam)),
      cast[pointer](sizeof(Vec4) + sizeof(int32) * 2 + sizeof(uint32)))
  glEnableVertexAttribArray(4)
  glVertexAttribDivisor(4, 1)

  glVertexAttribPointer(5, 4, GL_UNSIGNED_BYTE, GL_TRUE,
      GLsizei(sizeof(PathInstanceParam)),
      cast[pointer](sizeof(Vec4) + sizeof(int32) * 2 + sizeof(uint32) * 2))
  glEnableVertexAttribArray(5)
  glVertexAttribDivisor(5, 1)

  glUniform1i(ctx.shaderProgram.fsImageTexLoc, 0)
  glUniform2fv(ctx.shaderProgram.vsViewSizeLoc, 1, ctx.size[0].addr)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, ctx.edges.buffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 5, ctx.transforms.buffer)

proc setupGlyphPipeline(ctx: OpenglBackendContext) =
  glUseProgram(ctx.textShaderProgram.program)

  when NVG_USE_GLCORE:
    glBindVertexArray(ctx.glyphVao)

  glBindBuffer(GL_ARRAY_BUFFER, ctx.glyphs.buffer)
  let stride = GLsizei(sizeof(GlyphInstanceParam))
  glVertexAttribPointer(0, 4, cGL_FLOAT, GL_FALSE, stride, nil)
  glEnableVertexAttribArray(0)
  glVertexAttribDivisor(0, 1)
  glVertexAttribPointer(1, 4, cGL_UNSIGNED_BYTE, GL_TRUE, stride,
      cast[pointer](sizeof(Vec4)))
  glEnableVertexAttribArray(1)
  glVertexAttribDivisor(1, 1)
  glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
      cast[pointer](sizeof(Vec4) + sizeof(uint32)))
  glEnableVertexAttribArray(2)
  glVertexAttribDivisor(2, 1)
  glVertexAttribIPointer(3, 4, cGL_INT, stride,
      cast[pointer](sizeof(Vec4) + sizeof(uint32) * 2))
  glEnableVertexAttribArray(3)
  glVertexAttribDivisor(3, 1)

  glVertexAttribIPointer(4, 1, cGL_INT, stride,
      cast[pointer](sizeof(Vec4) + sizeof(uint32) * 2 + sizeof(Vec4)))
  glEnableVertexAttribArray(4)
  glVertexAttribDivisor(4, 1)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

  glActiveTexture(GL_TEXTURE4)
  glBindSampler(4, ctx.smpDummy)
  glActiveTexture(GL_TEXTURE5)
  glBindSampler(5, ctx.smpDummy)
  glUniform1i(ctx.textShaderProgram.fsCurveTexLoc, 4)
  glUniform1i(ctx.textShaderProgram.fsBandTexLoc, 5)

  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, ctx.transforms.buffer)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 7, ctx.transforms.buffer)

  glActiveTexture(GL_TEXTURE0)

proc teardownPathPipeline(ctx: OpenglBackendContext) =
  glDisableVertexAttribArray(0)
  glDisableVertexAttribArray(1)
  glDisableVertexAttribArray(2)
  glDisableVertexAttribArray(3)
  glDisableVertexAttribArray(4)
  when NVG_USE_GLCORE:
    glBindVertexArray(0)
  glUseProgram(0)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, 0)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 5, 0)

proc teardownGlyphPipeline(ctx: OpenglBackendContext) =
  glDisableVertexAttribArray(0)
  glDisableVertexAttribArray(1)
  glDisableVertexAttribArray(2)
  glDisableVertexAttribArray(3)
  glDisableVertexAttribArray(4)
  glDisableVertexAttribArray(5)
  when NVG_USE_GLCORE:
    glBindVertexArray(0)
  glUseProgram(0)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, 0)
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 7, 0)
  glActiveTexture(GL_TEXTURE4)
  glBindSampler(4, 0)
  glActiveTexture(GL_TEXTURE5)
  glBindSampler(5, 0)
  glActiveTexture(GL_TEXTURE0)

proc teardownPipeline(ctx: OpenglBackendContext, kind: DrawCallType) =
  case kind
  of DrawCallPath: ctx.teardownPathPipeline()
  of DrawCallGlyph: ctx.teardownGlyphPipeline()

proc uploadStorage(ctx: OpenglBackendContext) =
  let
    zone = zoneBegin("opengl.uploadStorage")
  defer: zone.zoneEnd()

  if ctx.drawList.paths.len > 0:
    ctx.paths.updateStorage(ctx.drawList.paths)

  if ctx.drawList.glyphs.len > 0:
    ctx.glyphs.updateStorage(ctx.drawList.glyphs)

  if ctx.drawList.edges.len > 0:
    ctx.edges.updateStorage(ctx.drawList.edges)

  if ctx.drawList.transforms.len > 0:
    ctx.transforms.updateStorage(ctx.drawList.transforms)

method flush(ctx: OpenglBackendContext) =
  let
    zone = zoneBegin("opengl.flush")
  defer: zone.zoneEnd()

  if ctx.drawList.calls.len <= 0:
    return

  ctx.initIfNeeded()
  ctx.uploadStorage()

  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)

  var
    prevBlend = default(CompositeOperation)
    activeKind = DrawCallPath
    pipelineActive = false

  for idx in 0 ..< int32(ctx.drawList.calls.len):
    let c = ctx.drawList.calls[idx]
    if not pipelineActive or activeKind != c.kind:
      if pipelineActive:
        ctx.teardownPipeline(activeKind)
      case c.kind
      of DrawCallPath:
        ctx.setupPathPipeline()
      of DrawCallGlyph:
        ctx.setupGlyphPipeline()
      activeKind = c.kind
      pipelineActive = true

    case c.kind
    of DrawCallPath:
      ctx.drawPathCall(idx, c.path, c.blend, prevBlend)
    of DrawCallGlyph:
      ctx.drawGlyphCall(idx, c.glyph, c.blend, prevBlend)

    prevBlend = c.blend

  if pipelineActive:
    ctx.teardownPipeline(activeKind)

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindSampler(0, 0)

  ctx.drawList.clear()

method resize(ctx: OpenglBackendContext, w, h: int32) =
  ctx.size[0] = float32(w)
  ctx.size[1] = float32(h)

proc createOpenglBackendContext*(w, h: int32): BackendContext =
  let backendContext = OpenglBackendContext()
  backendContext.size[0] = float32(w)
  backendContext.size[1] = float32(h)
  backendContext
