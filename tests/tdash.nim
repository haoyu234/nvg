import nvg

import std/unicode

import ./app
import ./fonts

proc initImpl(ctx: Context) =
  discard

proc frameImpl(ctx: Context) =
  ctx.resetTransform()

  let
    size = 68f
    padding = 5f

  var p1 = Path()
  p1.rect(vec4(0, 0, size, size))

  var p2 = Path()
  p2.moveTo(vec2(size / 2, padding))
  p2.lineTo(vec2(size / 2, size - padding))

  var p3 = Path()
  p3.moveTo(vec2(padding, size / 2))
  p3.lineTo(vec2(size - padding, size / 2))

  let text = "秦时明月汉时关，万里长征人未还。但使龙城飞将在，不教胡马度阴山。"
  var idxChar = 0
  var idxLine = 0
  var lastIdx = 0

  while true:
    inc idxChar, 1

    if idxChar mod 8 == 1:
      inc idxLine, 1

      ctx.resetTransform()
      ctx.translate(vec2(padding, padding + float32(idxLine - 1) * (size +
          padding * 3)))

    ctx.strokeWidth = 3
    ctx.strokeStyle = color(152f / 255f, 15f / 255f, 41f / 255f, 1)
    ctx.strokePath(p1)
    ctx.strokeWidth = 2

    ctx.dashArray = @[padding, padding]
    ctx.strokeStyle = color(221f / 255f, 153f / 255f, 160f / 255f, 1)
    ctx.strokePath(p2)
    ctx.strokePath(p3)
    ctx.dashArray.setLen(0)

    let n = text.runeLenAt(lastIdx)
    ctx.fontId = ctx.getDefaultFont()
    ctx.fontSize = size
    ctx.fillStyle = color(51f / 255f, 51f / 255f, 51f / 255f, 1)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline

    ctx.fillText(text.toOpenArray(lastIdx, lastIdx + n - 1), vec2(
        size / 2, size / 2))

    inc lastIdx, n

    ctx.translate(vec2(size, 0))

    if lastIdx >= len(text):
      break

launch(800, 600, App(
  name: "tdash.nim",
  initImpl: initImpl,
  frameImpl: frameImpl,
))
