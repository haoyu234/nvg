import std/strutils
import std/unicode

import nvg

import ./app
import ./fonts
import ./rich_run

const
  CARD_WIDTH = float32(620)
  CARD_PADDING = float32(24)
  CORNER_RADIUS = float32(12)

  INK_COLOR = color(38, 38, 38, 255)

  LINE_COLORS = [
    color(58, 116, 108, 255),
    color(173, 116, 66, 255),
    color(70, 88, 134, 255),
    color(199, 79, 60, 255),
  ]
  ENGLISH_COLOR = color(140, 140, 140, 255)
  TITLE_COLOR = color(34, 34, 34, 255)
  SUBTITLE_COLOR = color(150, 150, 150, 255)
  CARD_COLOR = color(255, 255, 255, 255)
  CARD_BORDER = color(228, 228, 228, 255)
  DIVIDER_COLOR = color(232, 232, 232, 255)
  ACCENT_COLOR = color(196, 84, 66, 255)

  POEM_LINES = [
    ("床前明月光，", "Abed, I see a silver light,"),
    ("疑是地上霜。", "I wonder if it's frost aground."),
    ("举头望明月，", "Looking up, I find the moon bright;"),
    ("低头思故乡。", "Bowing, in homesickness I'm drowned."),
  ]

  TEXT = join([
    "This is a test.",
    "😬👀🚨",
    "این یک تست است",
    "शकति शक्ति ",
    "今天天气晴朗。 ",
  ], "\n")

  ATTRIBS = [TextAttribSpan(
    runeRange: int32(0) .. high(int32),
    attribs: [
      TextAttrib(kind: akFontSize, fontSize: 32),
      TextAttrib(kind: akColor, color: INK_COLOR),
      TextAttrib(kind: akTextWrap, textWrap: WordCharWrap),
      TextAttrib(kind: akTextBaseline, textBaseline: MiddleBaseline),
    ],
  )]

proc roundedRectPath(ctx: Context, x, y, w, h, r: float32) =
  ctx.beginPath()
  ctx.moveTo(vec2(x + r, y))
  ctx.lineTo(vec2(x + w - r, y))
  ctx.arcTo(vec2(x + w, y), vec2(x + w, y + r), r)
  ctx.lineTo(vec2(x + w, y + h - r))
  ctx.arcTo(vec2(x + w, y + h), vec2(x + w - r, y + h), r)
  ctx.lineTo(vec2(x + r, y + h))
  ctx.arcTo(vec2(x, y + h), vec2(x, y + h - r), r)
  ctx.lineTo(vec2(x, y + r))
  ctx.arcTo(vec2(x, y), vec2(x + r, y), r)
  ctx.closePath()

var
  blob = default(TextBlob)
  titleBlob = default(TextBlob)
  bodyBlob = default(TextBlob)

proc demo_text_attribs*(app: App, ctx: Context) =
  let
    innerWidth = CARD_WIDTH - CARD_PADDING * 2

  if blob.isNil:
    blob = createTextBlob(
      ctx.textLayoutContext, getPlexFontCollection(),
      toRunes(TEXT), ATTRIBS, float32(460), float32(0))

  if titleBlob.isNil:
    let
      titleRuns = assembleRuns([
        RichRun(text: "静夜思\n", attribs: [
          TextAttrib(kind: akFontSize, fontSize: 46),
          TextAttrib(kind: akColor, color: TITLE_COLOR),
          TextAttrib(kind: akTextAlign, textAlign: CenterAlign),
          TextAttrib(kind: akLetterSpacing, letterSpacing: 6),
        ]),
        RichRun(text: "---- ", attribs: [
          TextAttrib(kind: akFontSize, fontSize: 16),
          TextAttrib(kind: akColor, color: ACCENT_COLOR),
          TextAttrib(kind: akTextAlign, textAlign: CenterAlign),
        ]),
        RichRun(text: "唐 · 李白\n", attribs: [
          TextAttrib(kind: akFontSize, fontSize: 16),
          TextAttrib(kind: akColor, color: SUBTITLE_COLOR),
          TextAttrib(kind: akTextAlign, textAlign: CenterAlign),
          TextAttrib(kind: akLetterSpacing, letterSpacing: 4),
        ]),
      ], TextAttribs(attribs: [
        TextAttrib(kind: akTextBaseline, textBaseline: TopBaseline),
      ]))

    titleBlob = createTextBlob(
      ctx.textLayoutContext, ctx.fontCollection,
      toRunes(titleRuns.text), titleRuns.attribs, innerWidth, float32(0))

  if bodyBlob.isNil:
    var
      runs: seq[RichRun]
    for index in 0 ..< POEM_LINES.len:
      runs.add(RichRun(text: POEM_LINES[index][0] & "\n", attribs: [
        TextAttrib(kind: akFontSize, fontSize: 30),
        TextAttrib(kind: akColor, color: LINE_COLORS[index]),
        TextAttrib(kind: akLineHeight, lineHeight: 36),
      ]))
      runs.add(RichRun(text: POEM_LINES[index][1] & "\n", attribs: [
        TextAttrib(kind: akFontSize, fontSize: 22),
        TextAttrib(kind: akColor, color: ENGLISH_COLOR),
        TextAttrib(kind: akFontStyle, fontStyle: Italic),
        TextAttrib(kind: akLineHeight, lineHeight: 54),
      ]))

    let
      bodyRuns = assembleRuns(runs, TextAttribs(attribs: [
        TextAttrib(kind: akTextWrap, textWrap: WordCharWrap),
        TextAttrib(kind: akTextBaseline, textBaseline: TopBaseline),
      ]))

    bodyBlob = createTextBlob(
      ctx.textLayoutContext, ctx.fontCollection,
      toRunes(bodyRuns.text), bodyRuns.attribs, innerWidth, float32(0))

  let
    dividerY = titleBlob.height + float32(12)
    bodyY = titleBlob.height + float32(22)
    cardHeight = CARD_PADDING * 2 + bodyY + bodyBlob.height

  ctx.save()
  ctx.translate(vec2(24, 16))

  # Card body: pure white fill + hairline stroke
  ctx.fillStyle = CARD_COLOR
  roundedRectPath(ctx, 0, 0, CARD_WIDTH, cardHeight, CORNER_RADIUS)
  ctx.fill()
  ctx.strokeStyle = CARD_BORDER
  ctx.strokeWidth = 1
  ctx.lineCap = ButtCap
  roundedRectPath(ctx, 0.5, 0.5, CARD_WIDTH - 1, cardHeight - 1, CORNER_RADIUS)
  ctx.stroke()

  ctx.translate(vec2(CARD_PADDING, CARD_PADDING))

  # Title + subtitle (the brown dash prefix of the subtitle is centered with the text)
  ctx.fillTextBlob(titleBlob, vec2(0, 0))

  # Hairline divider between title and body
  ctx.strokeStyle = DIVIDER_COLOR
  ctx.strokeWidth = 1
  ctx.lineCap = ButtCap
  ctx.beginPath()
  ctx.moveTo(vec2(0, dividerY))
  ctx.lineTo(vec2(innerWidth, dividerY))
  ctx.stroke()

  # Chinese / English interleaved body
  ctx.fillTextBlob(bodyBlob, vec2(0, bodyY))

  # emoji
  ctx.fillTextBlob(blob, vec2(380, 128))

  ctx.restore()
