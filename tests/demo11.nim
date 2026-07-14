import std/unicode

import nvg

import ./app
import ./fonts
import ./rich_run

const
  INK_COLOR = color(38, 38, 38, 255)

  RICH_IPSUM =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam eget blandit purus, sit amet faucibus quam. Morbi vulputate tellus in nulla fermentum feugiat id eu diam. Sed id orci sapien. " &
    "Donec sodales vitae odio dapibus pulvinar. Maecenas molestie lorem vulputate, gravida ex sed, dignissim erat. Suspendisse vel magna sed libero fringilla tincidunt id eget nisl. " &
    "Suspendisse potenti. Maecenas fringilla magna sollicitudin, porta ipsum sed, rutrum magna. Sed ac semper magna. Phasellus porta nunc nulla, non dignissim magna pretium a. " &
    "Aenean condimentum, nisi vitae sollicitudin ullamcorper, tellus elit suscipit risus, aliquet hendrerit sem velit in leo. Sed ut est pellentesque, vehicula ligula consectetur, tincidunt tellus. " &
    "Aliquam erat volutpat. Etiam efficitur consequat turpis, vitae faucibus erat porta sed.\n"

  RICH_ATTRIBS = TextAttribs(attribs: [
    TextAttrib(kind: akTextWrap, textWrap: WordCharWrap),
    TextAttrib(kind: akTextBaseline, textBaseline: MiddleBaseline),
    TextAttrib(kind: akColor, color: INK_COLOR),
  ])

  RICH_RUNS = assembleRuns([
    RichRun(text: RICH_IPSUM, attribs: [
      TextAttrib(kind: akFontSize, fontSize: 17),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(17, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "moikkelis!\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 64),
      TextAttrib(kind: akFontStyle, fontStyle: Italic),
      TextAttrib(kind: akLetterSpacing, letterSpacing: 20),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(64, 1)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "این یک 😬👀🚨 تست است\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 28),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(28, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "Donec sodales ", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 15),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(15, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "vitae odio ", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 25),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(25, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "dapibus pulvinar\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 18),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(18, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "ہے۔ kofi یہ ایک\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 15),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(15, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "POKS! 🧁\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 128),
      TextAttrib(kind: akFontWeight, fontWeight: Bold),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(128,
          0.75)),
      TextAttrib(kind: akColor, color: color(220, 40, 40, 255))]),
    RichRun(text: "11/17\n", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 48),
      TextAttrib(kind: akFontWeight, fontWeight: Bold),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(48, 1)),
      TextAttrib(kind: akColor, color: color(180, 110, 190, 255))]),
    RichRun(text: "शकति शक्ति ", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 64),
      TextAttrib(kind: akFontStyle, fontStyle: Italic),
      TextAttrib(kind: akLetterSpacing, letterSpacing: 20),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(64, 1)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
    RichRun(text: "こんにちは世界。 ", attribs: [
      TextAttrib(kind: akFontSize, fontSize: 15),
      TextAttrib(kind: akLineHeight, lineHeight: metricsLineHeight(15, 1.3)),
      TextAttrib(kind: akColor, color: INK_COLOR)]),
  ], RICH_ATTRIBS)

var
  richBlob = default(TextBlob)

proc demo_rich_text*(app: App, ctx: Context) =
  if richBlob.isNil:
    richBlob = createTextBlob(
      ctx.textLayoutContext, getPlexFontCollection(),
      toRunes(RICH_RUNS.text), RICH_RUNS.attribs, float32(460), float32(0))
  
  let
    pad = float32(20)
    w = richBlob.width + pad * 2
    h = richBlob.height + pad * 2

    offsetX = (float32(app.w) - w) / 2

  ctx.beginPath()
  ctx.rect(vec4(offsetX, pad, w, h))
  ctx.fillStyle = color(255, 255, 255, 255)
  ctx.fill()

  ctx.fillTextBlob(richBlob, vec2(offsetX + pad, pad + pad))
