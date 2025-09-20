import nvg
import nvg/fontstash
import nvg/params
import nvg/truetype

import ./app
import ./fonts

proc fillGlyphSdfImpl(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    fontSize: float32, color: Color) =
  let glyph = font.getGlyph(glyphId)
  if glyph.isNil:
    return

  let quad = ctx.fons.getGlyphQuad(glyph, x, y, fontSize)
  if quad.imageId.isNil:
    return
  
  var paint = default(Paint)
  paint.image = quad.imageId
  paint.innerColor = color
  paint.outerColor = color
  paint.innerColor.a = ctx.globalAlpha * paint.innerColor.a
  paint.outerColor.a = ctx.globalAlpha * paint.outerColor.a

  let transform = ctx.getTransform()
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
  let layers = font.trueType.getGlyphLayers(glyphId)
  if layers.len <= 0:
    fillGlyphSdfImpl(ctx, font, glyphId, x, y, fontSize, ctx.fillStyle.innerColor)
    return

  let fillColor = ctx.fillStyle.innerColor

  for layer in layers:
    var color = fillColor
    if layer.paletteIdx != 0xFFFF:
      color = font.trueType.getPaletteColor(layer.paletteIdx, 0)

    fillGlyphSdfImpl(ctx, font, layer.glyphId, x, y, fontSize, color)

proc getGlyphPathImpl(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    scale: float32): Path =
  let glyph = font.getGlyph(glyphId)
  if glyph.isNil:
    return

  result = font.getGlyphPath(glyph)
  if not result.empty:
    let matrix = [scale, 0, 0, -scale, x, y]
    result.transform(matrix)

proc fillGlyphPath(ctx: Context, font: Font, glyphId: GlyphId, x, y,
    fontSize: float32) =
  let scale = font.getPixelHeightScale(fontSize)

  let layers = font.trueType.getGlyphLayers(glyphId)
  if layers.len <= 0:
    let p = ctx.getGlyphPathImpl(font, glyphId, x, y, scale)
    ctx.fillPath(p)
    return

  let oldStyle = ctx.fillStyle

  for layer in layers:
    if layer.paletteIdx != 0xFFFF:
      ctx.fillStyle = font.trueType.getPaletteColor(layer.paletteIdx, 0)
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
