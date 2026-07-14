import std/unicode

import nvg

import ./app
import ./fonts

const
  ALIGN_TEXT = "Quick brown hamburgerfontstiv with aïoli."
  CELL_W = float32(100)
  CELL_H = float32(100)
  GAP = float32(70)
  PITCH = CELL_W + GAP
  H_ALIGNS = [LeftAlign, CenterAlign, RightAlign, LeftAlign, RightAlign]
  V_LABELS = ["Top", "Center", "Bottom"]
  H_LABELS = ["Start", "Center", "End", "left", "Right"]
  BORDER_COLOR = color(255, 192, 0, 255)
  LABEL_COLOR = color(0, 0, 0, 128)
  GRID_W = float32(4) * PITCH + CELL_W
  GRID_H = float32(2) * PITCH + CELL_H
  TOP_MARGIN = float32(30)
  BOTTOM_MARGIN = float32(60)
  SIDE_MARGIN = float32(30)

  DEFAULT_ATTRIBS = TextAttribSpan(
    runeRange: int32(0) .. high(int32),
    attribs: [
      TextAttrib(kind: akFontSize, fontSize: 24),
      TextAttrib(kind: akColor, color: color(0, 0, 0, 255)),
      TextAttrib(kind: akTextWrap, textWrap: WordWrap),
      TextAttrib(kind: akTextOverflow, textOverflow: Ellipsis),
      TextAttrib(kind: akTextBaseline, textBaseline: MiddleBaseline),
    ],
  )

var
  blobs: array[5, TextBlob]

proc demo_aligns*(app: App, ctx: Context) =
  ctx.beginPath()
  ctx.rect(vec4(0, 0, float32(app.w), float32(app.h)))
  ctx.fillStyle = color(255, 255, 255, 255)
  ctx.fill()

  let
    availW = float32(app.w) - 2 * SIDE_MARGIN
    availH = float32(app.h) - TOP_MARGIN - BOTTOM_MARGIN
    fit = min(min(availW / GRID_W, availH / GRID_H), float32(1))
    originX = (float32(app.w) - GRID_W * fit) / 2
    originY = TOP_MARGIN + (availH - GRID_H * fit) / 2

  ctx.save()
  ctx.translate(vec2(originX, originY))
  ctx.scale(vec2(fit, fit))

  for v in 0 ..< 3:
    for h in 0 ..< 5:
      let
        cellX = float32(h) * PITCH
        cellY = float32(v) * PITCH

      if blobs[h].isNil:
        let
          attribs = TextAttribSpan(
            runeRange: int32(0) .. high(int32),
          attribs: [
            TextAttrib(kind: akTextAlign,
              textAlign: H_ALIGNS[h])],
            )

        blobs[h] = createTextBlob(ctx.textLayoutContext, getPlexFontCollection(
            ), toRunes(ALIGN_TEXT),
            [DEFAULT_ATTRIBS, attribs],
            CELL_W, CELL_H)

      ctx.beginPath()
      ctx.rect(vec4(cellX, cellY, CELL_W, CELL_H))
      ctx.strokeStyle = BORDER_COLOR
      ctx.strokeWidth = 1.5
      ctx.stroke()

      var
        offsetY = float32(0)
      if v == 1:
        offsetY = (CELL_H - blobs[h].height) * 0.5
      elif v == 2:
        if blobs[h].height < CELL_H:
          offsetY = CELL_H - blobs[h].height

      ctx.save()
      ctx.translate(vec2(cellX, cellY + offsetY))
      ctx.fillTextBlob(blobs[h], vec2(0, 0))
      ctx.restore()

    ctx.fontSize = 13
    ctx.fillStyle = LABEL_COLOR
    ctx.textBaseline = MiddleBaseline
    ctx.textAlign = RightAlign
    ctx.fillText(V_LABELS[v], vec2(float32(-8), float32(v) * PITCH + CELL_H * 0.5))

  for h in 0 ..< 5:
    ctx.fontSize = 14
    ctx.fillStyle = LABEL_COLOR
    ctx.textBaseline = BottomBaseline
    ctx.textAlign = CenterAlign
    ctx.fillText(H_LABELS[h], vec2(float32(h) * PITCH + CELL_W * 0.5, float32(-8)))

  ctx.restore()
