import nvg
import nvg/fontstash
import nvg/opentype
import nvg/params

import ./app
import ./fonts

proc fillGlyphSdfImpl(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    fontSize: float32, paint: Paint) =
  let glyph = font.getGlyph(glyphId)
  if glyph.isNil:
    return

  let
    scale = float32(ctx.fons.atlasFontSize) / fontSize

  let quad = ctx.fons.getGlyphQuad(glyph, x, y, fontSize)
  if quad.imageId.isNil:
    return

  let transform = ctx.getTransform()

  var paint = paint
  paint.image = quad.imageId
  paint.transform[0] = length(vec2(transform[0], transform[2])) / scale
  paint.transform[3] = length(vec2(transform[1], transform[3])) / scale
  paint.extent = vec2(float32(ctx.fons.atlasFontSize), float32(
      ctx.fons.atlasFontSize))
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a
  paint.radius = ctx.fontBlur

  let
    p1 = transform * vec2(quad.x1, quad.y1)
    p2 = transform * vec2(quad.x2, quad.y1)
    p3 = transform * vec2(quad.x2, quad.y2)
    p4 = transform * vec2(quad.x1, quad.y2)

  var
    rev = default(int32)
    vertBuf = default(array[6, Vec4])

  if transform[0] * transform[3] < 0:
    rev = 1

  vertBuf[0] = vec4(p1, vec2(quad.s1, quad.t1))
  vertBuf[1 + rev] = vec4(p3, vec2(quad.s2, quad.t2))
  vertBuf[2 - rev] = vec4(p2, vec2(quad.s2, quad.t1))
  vertBuf[3] = vec4(p1, vec2(quad.s1, quad.t1))
  vertBuf[4 + rev] = vec4(p4, vec2(quad.s1, quad.t2))
  vertBuf[5 - rev] = vec4(p3, vec2(quad.s2, quad.t2))

  ctx.params.trianglesImpl(
    ctx.ctx,
    paint,
    ctx.compositeOperation,
    default(set[RenderFlags]),
    vertBuf,
  )

proc fillGlyphSdf(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    fontSize: float32) =
  let layers = font.openType.getGlyphLayers(glyphId)
  if layers.len <= 0:
    fillGlyphSdfImpl(ctx, font, glyphId, x, y, fontSize, ctx.fillStyle)
    return

  let oldStyle = ctx.fillStyle

  for layer in layers:
    var style = oldStyle
    if layer.paletteIdx != 0xFFFF:
      style = font.openType.getPaletteColor(layer.paletteIdx, 0)

    fillGlyphSdfImpl(ctx, font, layer.glyphId, x, y, fontSize, style)

proc getGlyphPathImpl(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    scale: float32): Path =
  let glyph = font.getGlyph(glyphId)
  if glyph.isNil:
    return

  let verts = font.getGlyphShape(glyph)
  if len(verts) <= 0:
    return

  var matrix = [scale, 0, 0, -scale, x, y]
  matrix.multiply(ctx.getTransform())

  for idx in 0 ..< verts.len:
    let v = verts[idx].addr

    case v.command
    of GlyphShapeCommand.MOVE:
      let p = matrix * vec2(float32(v.x), float32(v.y))
      result.moveTo(p)

      if idx <= 0:
        result.appendCommands([float32(PathCommand.RESTART)])

    of GlyphShapeCommand.LINE:
      let p = matrix * vec2(float32(v.x), float32(v.y))
      result.lineTo(p)

    of GlyphShapeCommand.BEZIER:
      let
        p = matrix * vec2(float32(v.x), float32(v.y))
        cp = matrix * vec2(float32(v.cx), float32(v.cy))

      result.quadCurveTo(cp, p)

    of GlyphShapeCommand.CLOSE:
      result.closePath()

proc fillGlyphPath(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    fontSize: float32) =
  let scale = font.getPixelHeightScale(fontSize)

  let layers = font.openType.getGlyphLayers(glyphId)
  if layers.len <= 0:
    let p = ctx.getGlyphPathImpl(font, glyphId, x, y, scale)
    ctx.fillPath(p)
    return

  let oldStyle = ctx.fillStyle

  for layer in layers:
    if layer.paletteIdx != 0xFFFF:
      ctx.fillStyle = font.openType.getPaletteColor(layer.paletteIdx, 0)
    else:
      ctx.fillStyle = oldStyle

    let p = ctx.getGlyphPathImpl(font, layer.glyphId, x, y, scale)
    ctx.fillPath(p)

  ctx.fillStyle = oldStyle

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()

  const text = "\uE000\uE049\uE04A"

  let emoji = ctx.fons.getFont(ctx.getEmojiFont())

  ctx.fillStyle = color(0, 0, 0, 1)
  ctx.fontId = ctx.getDefaultFont()
  ctx.textAlign = LeftAlign
  ctx.textBaseline = AlphabeticBaseline
  ctx.fontSize = 32

  ctx.fillText("SDF: ", vec2(10, 150))
  ctx.fillText("PATH: ", vec2(10, 250))

  let fontSize_emoji = float32(64)
  for x, y, glyphId in ctx.fons.arrange(emoji, text, 0, 0, LeftAlign,
      AlphabeticBaseline, fontSize_emoji, 0):
    fillGlyphSdf(ctx, emoji, glyphId, x + 80, y + 150, fontSize_emoji)
    fillGlyphPath(ctx, emoji, glyphId, x + 80, y + 250, fontSize_emoji)

launch(400, 300, App(
  name: "temoji.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
