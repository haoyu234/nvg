import nvg/bmp
import nvg/core
import nvg/math
import nvg/msdf
import nvg/path
import nvg/truetype

import std/cmdline
import std/strutils
import std/math

import ./utils

const
  FONT = staticRead("../msyh.ttf")

proc lerp[T](p1, p2: T, weight: float32): T {.inline.} =
  p1 * (1.0f - weight) + p2 * weight

proc lerp[T](p1, p2, p3: T, weight: float32): T {.inline.} =
  lerp(lerp(p1, p2, weight), lerp(p2, p3, weight), weight)

proc f32ToU8(v: float32): uint8 {.inline.} =
  let
    v1 = clamp(v, 0, 1)
    v2 = not int32(255.0f - 255.0f * v1)
    v3 = uint8(v2)
  v3

proc u8ToF32(v: uint8): float32 {.inline.} =
  1.0f / 255.0f * float32(v)

proc renderSDF(sdf: seq[float32], w, h, outputW, outputH: int32,
    pixelRange: Slice[int32], sdThreshold: float32): seq[uint8] =
  let
    sdfPixelRangeScale = float32(outputW + outputH) / float32(w + h)
    sdfPixelRange = int32(float32(pixelRange.a) * sdfPixelRangeScale) .. int32(
        float32(pixelRange.b) * sdfPixelRangeScale)
    rangeSize = sdfPixelRange.b - sdfPixelRange.a
    scale = vec2(float32(w) / float32(outputW), float32(h) / float32(outputH))
    translate = sdfPixelRange.a / rangeSize
    sdBias = 0.5f - sdThreshold

  result.setLen(outputH * outputW)

  for y in 0 ..< outputH:
    for x in 0 ..< outputW:
      var
        pos = vec2(float32(x) + 0.5f, float32(y) + 0.5f) * scale

      pos[0] = clamp(pos[0], 0, float32(w)) - 0.5f
      pos[1] = clamp(pos[1], 0, float32(h)) - 0.5f

      var
        l = int32(floor(pos[0]))
        b = int32(floor(pos[1]))
        r = l + 1
        t = b + 1

      let
        lr = pos[0] - float32(l)
        bt = pos[1] - float32(b)

      l = clamp(l, 0, w - 1)
      r = clamp(r, 0, w - 1)
      b = clamp(b, 0, h - 1)
      t = clamp(t, 0, h - 1)

      let
        lbv = sdf[l + w * b]
        rbv = sdf[r + w * b]
        ltv = sdf[l + w * t]
        rtv = sdf[r + w * t]

        v1 = lerp(lbv, rbv, lr)
        v2 = lerp(ltv, rtv, lr)

        sd = lerp(v1, v2, bt)

        v3 = float32(rangeSize) * (sd + sdBias + translate) + 0.5
        v4 = clamp(v3, 0, 1)

      result[x + outputH * y] = f32ToU8(v4)

proc main() =
  if paramCount() < 1:
    return

  let
    font = parseTrueType(cast[seq[byte]](FONT), 0)
    glyphId = parseInt(paramStr(1))

  let path = font.getGlyphPath(GlyphId(glyphId))
  if not path.empty:
    dumpPath(path)

    var df = default(ShapeDistanceFinder)
    var sdf = df.generateDistanceField(
      path,
      32,
      32,
      int32(-2) .. int32(2))

    for idx in 0 ..< sdf.len:
      let value = sdf[idx]
      sdf[idx] = u8ToF32(f32ToU8(value))

    let pixels = renderSDF(sdf, 32, 32, 120, 120, int32(-2) .. int32(2), 0.5f)
    writeBmp("./sdf.bmp", pixels, 120, 120, 1)

main()
