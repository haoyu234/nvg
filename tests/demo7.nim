import nvg

const
  TEXTs = [
    "你好, 世界",
    "hello world ~",
    "😬👀🚨"
  ]

proc demo_text*(ctx: Context) =
  ctx.fontColor = color(255, 0, 0, 255)
  ctx.translate(vec2(100, 100))

  for text in TEXTs:
    ctx.fillText(text, vec2(0, 0))
    ctx.translate(vec2(0, 40))
