import ./core
import ./path
import ./truetype
import ./pieces

import std/math

proc rayBezier(
    orig, ray, q1, q2, q3: Vec2, hits: var array[2, Vec2]
): uint32 =
  let
    q1perp = q1[1] * ray[0] - q1[0] * ray[1]
    q2perp = q2[1] * ray[0] - q2[0] * ray[1]
    q3perp = q3[1] * ray[0] - q3[0] * ray[1]
    roperp = orig[1] * ray[0] - orig[0] * ray[1]

    a = q1perp - 2 * q2perp + q3perp
    b = q2perp - q1perp
    c = q1perp - roperp

  var
    n = uint32(0)
    s1 = default(float32)
    s2 = default(float32)

  if a != 0:
    let discriminant = b * b - a * c
    if discriminant > 0:
      let
        rcpna = float32(-1) / a
        d = sqrt(discriminant)

      s1 = (b + d) * rcpna
      s2 = (b - d) * rcpna

      if s1 > 0 and s1 <= 1:
        n = 1

      if d > 0 and s2 > 0 and s2 <= 1:
        if n <= 0:
          s1 = s2

        inc n, 1
  else:
    s1 = c / (-2 * b)
    if s1 > 0 and s1 <= 1:
      n = 1

  if n > 0:
    let
      rcpLen2 = 1 / (ray[0] * ray[0] + ray[1] * ray[1])
      raynX = ray[0] * rcpLen2
      raynY = ray[1] * rcpLen2

      q1d = q1[0] * raynX + q1[1] * raynY
      q2d = q2[0] * raynX + q2[1] * raynY
      q3d = q3[0] * raynX + q3[1] * raynY
      rod = orig[0] * raynX + orig[1] * raynY

      q21d = q2d - q1d
      q31d = q3d - q1d
      q1rd = q1d - rod

    hits[0][0] = q1rd + s1 * (2.0f - 2.0f * s1) * q21d + s1 * s1 * q31d
    hits[0][1] = a * s1 + b
    result = 1

    if n > 1:
      hits[1][0] = q1rd + s2 * (2.0f - 2.0f * s2) * q21d + s2 * s2 * q31d
      hits[1][1] = a * s2 + b
      result = 2

iterator simplify(path: Path): (Command, Vec2, Piece[float32]) =
  var
    s = default(Vec2)
    p = default(Vec2)

  for command, data in path.commands:
    case command
    of MOVE:
      let p1 = vec2(data[0], data[1])
      s = p1
      p = p1

    of LINE:
      let p1 = vec2(data[0], data[1])
      if p != p1:
        yield (command, p, data)
        p = p1

    of CURVE:
      let
        p2 = vec2(data[2], data[3])

      if p != p2:
        yield (command, p, data)
        p = p2

    of BEZIER:
      let
        p3 = vec2(data[3], data[4])

      if p != p3:
        yield (command, p, data)
        p = p3

    of CLOSE:
      if p != s:
        yield (LINE, p, piece(s))
        p = s

proc computeCrossX(x, y: float32, path: Path): int32 =
  var y = y

  let frac = y mod 1
  if frac < 0.01f:
    y = y + 0.01
  elif frac > 0.99f:
    y = y - 0.01

  var
    orig = vec2(x, y)
    ray = vec2(float32(1), 0)
    winding = default(int32)
    hints = default(array[2, Vec2])

  template check: untyped =
    let
      x1 = p[0]
      y1 = p[1]
      x2 = c[0]
      y2 = c[1]

    if y > min(y1, y2) and y < max(y1, y2) and x > min(x1, x2):
      let inter = (y - y1) / (y2 - y1) * (x2 - x1) + x1
      if inter < x:
        if y1 < y2:
          inc winding, 1
        else:
          dec winding, 1

  for command, p, data in path.simplify:
    case command
    of LINE:
      let c = vec2(data[0], data[1])
      check()

    of CURVE:
      let
        cp = vec2(data[0], data[1])
        c = vec2(data[2], data[3])

      let
        ax = min(p[0], min(cp[0], c[0]))
        ay = min(p[1], min(cp[1], c[1]))
        by = max(p[1], max(cp[1], c[1]))

      if y > ay and y < by and x > ax:
        if p == cp or cp == c:
          check()
        else:
          let n = rayBezier(orig, ray, p, cp, c, hints)
          for idx in 0 ..< n:
            if hints[idx][0] < 0:
              if hints[idx][1] < 0:
                dec winding, 1
              else:
                inc winding, 1

    of BEZIER:
      discard

    else:
      discard

  winding

proc solveCubic(a, b, c: float32, res: var array[3, float32]): uint32 =
  let
    s = -a / 3
    p = b - a * a / 3
    q = a * (2 * a * a - 9 * b) / 27 + c
    p3 = p * p * p
    d = q * q + 4 * p3 / 27

  template cubeRoot(v: float32): float32 =
    let sign = float32(sgn(v))
    sign * pow(sign * v, float32(1) / float32(3))

  if d >= 0:
    let
      z = sqrt(d)
      u = cubeRoot((-q + z) / 2)
      v = cubeRoot((-q - z) / 2)

    res[0] = s + u + v
    result = 1
  else:
    let
      u = sqrt(-p / 3)
      v = arccos(-sqrt(-27 / p3) * q / 2) / 3
      m = cos(v)
      n = cos(v - PI / 2) * 1.732050808f

    res[0] = s + u * 2 * m
    res[1] = s - u * (m + n)
    res[2] = s - u * (m - n)
    result = 3

proc generateGlyphSDF*(
    trueType: TrueType,
    glyphId: GlyphId,
    scale: float32,
    padding: int32,
    edge: byte,
    pixelDistScale: float32,
): tuple[w, h: int32, data: seq[uint8], glyphBox: GlyphBox] =
  if scale <= 0:
    return

  let glyphBox = trueType.getGlyphBitmapBox(glyphId, scale, scale, 0, 0)
  if glyphBox.xMin == glyphBox.xMax or glyphBox.yMin == glyphBox.yMax:
    return

  let
    x1 = glyphBox.xMin - padding
    y1 = glyphBox.yMin - padding
    x2 = glyphBox.xMax + padding
    y2 = glyphBox.yMax + padding

    w = x2 - x1
    h = y2 - y1

  result.w = w
  result.h = h
  result.data.setLen(w * h)
  result.glyphBox = glyphBox

  let
    scaleX = scale
    scaleY = -scale # invert for y-downwards bitmaps
    path = trueType.getGlyphPath(glyphId)

  const
    eps = float32(1) / float32(1024)
    eps2 = eps * eps

  var
    data2 = newSeq[float32]()

  for command, p, data in path.simplify:
    case command
    of LINE:
      let
        x2 = p[0] * scaleX
        y2 = p[1] * scaleY
        x1 = data[0] * scaleX
        y1 = data[1] * scaleY

        dx = x2 - x1
        dy = y2 - y1
        dist = sqrt(dx * dx + dy * dy)

      if dist >= eps:
        let v = float32(1) / dist
        data2.add(v)
      else:
        data2.add(0)

    of CURVE:
      let
        x3 = p[0] * scaleX
        y3 = p[1] * scaleY
        x2 = data[0] * scaleX
        y2 = data[1] * scaleY
        x1 = data[2] * scaleX
        y1 = data[3] * scaleY

        bx = x1 - 2 * x2 + x3
        by = y1 - 2 * y2 + y3
        len2 = bx * bx + by * by

      if len2 >= eps2:
        let v = float32(1) / len2
        data2.add(v)
      else:
        data2.add(0)

    of BEZIER:
      discard

    else:
      discard

  for y in y1 ..< y2:
    for x in x1 ..< x2:
      var
        idx = default(int32)
        sx = float32(x) + 0.5f
        sy = float32(y) + 0.5f

        xSpace = sx / scaleX
        ySpace = sy / scaleY

        minDist = float32(999999)

      let winding = computeCrossX(xSpace, ySpace, path)

      for command, p, data in path.simplify:
        case command
        of LINE:
          if data2[idx] != 0:
            let
              x2 = p[0] * scaleX
              y2 = p[1] * scaleY
              x1 = data[0] * scaleX
              y1 = data[1] * scaleY

              dx = x2 - x1
              dy = y2 - y1

              px = x1 - sx
              py = y1 - sy
              dist2 = px * px + py * py

            if dist2 < minDist * minDist:
              minDist = sqrt(dist2)

            let dist = abs(dx * py - dy * px) * data2[idx]
            if dist < minDist:
              let t = -(px * dx + py * dy) / (dx * dx + dy * dy)
              if t >= 0 and t <= 1:
                minDist = dist

        of CURVE:
          let
            x3 = p[0] * scaleX
            y3 = p[1] * scaleY
            x2 = data[0] * scaleX
            y2 = data[1] * scaleY
            x1 = data[2] * scaleX
            y1 = data[3] * scaleY

          let
            bx1 = min(min(x1, x2), x3)
            by1 = min(min(y1, y2), y3)
            bx2 = max(max(x1, x2), x3)
            by2 = max(max(y1, y2), y3)

          if sx > (bx1 - minDist) and sx < (bx2 + minDist) and sy > (by1 -
              minDist) and sy < (by2 + minDist):
            let
              ax = x2 - x1
              ay = y2 - y1
              bx = x1 - 2 * x2 + x3
              by = y1 - 2 * y2 + y3
              mx = x1 - sx
              my = y1 - sy
              aInv = data2[idx]

            var
              n = default(uint32)
              res = default(array[3, float32])

            if aInv == 0:
              let
                a = 3 * (ax * bx + ay * by)
                b = 2 * (ax * ax + ay * ay) + (mx * bx + my * by)
                c = mx * ax + my * ay

              if abs(a) < eps2:
                if abs(b) >= eps2:
                  res[n] = -c / b
                  inc n, 1
              else:
                let discriminant = b * b - 4 * a * c
                if discriminant < 0:
                  n = 0
                else:
                  let root = sqrt(discriminant)
                  res[0] = (-b - root) / (2 * a)
                  res[1] = (-b + root) / (2 * a)
                  n = 2
            else:
              let
                b = 3 * (ax * bx + ay * by) * aInv
                c = (2 * (ax * ax + ay * ay) + (mx * bx + my * by)) * aInv
                d = (mx * ax + my * ay) * aInv

              n = solveCubic(b, c, d, res)

            var dist2 = mx * mx + my * my
            if dist2 < minDist * minDist:
              minDist = sqrt(dist2)

            for idx in 0 ..< n:
              if res[idx] >= 0 and res[idx] <= 1:
                let
                  t = res[idx]
                  it = float32(1) - t
                  px = it * it * x1 + 2 * t * it * x2 + t * t * x3
                  py = it * it * y1 + 2 * t * it * y2 + t * t * y3

                  dx = px - sx
                  dy = py - sy

                dist2 = dx * dx + dy * dy
                if dist2 < minDist * minDist:
                  minDist = sqrt(dist2)

        of BEZIER:
          discard

        else:
          discard

        inc idx, 1

      if winding == 0:
        minDist = -minDist

      let
        v1 = float32(edge) + pixelDistScale * minDist
        v2 = clamp(v1, float32(0), float32(255))
        offset = (y - y1) * w + (x - x1)

      result.data[offset] = uint8(v2)
