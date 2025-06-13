import nvg/context
import nvg/core
import nvg/params
import nvg/pieces

proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

proc createImpl(): pointer =
  default(pointer)

proc destroyImpl(ctx: pointer) =
  discard

proc dumpPath(i: int, p: ptr Contour) =
  printf(
    "-%03u offset[%u] count[%u] fill[%u] ccw[%u] closed[%u] convex[%u]\n",
    i + 1,
    p.offset,
    p.pointCount,
    p.fill.len,
    # p.winding,
    0,
    p.closed,
    p.convex,
  )

  for v in p.fill.toOpenArray:
    printf("-- %.6f %.6f %.6f %.6f\n", v[0], v[1], v[2], v[3])

proc dumpPaint(p: Paint) =
  let t = cast[ptr UncheckedArray[float32]](p.transform.addr)
  printf(
    "transform[%.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f]\nextent[%.6f %.6f] blur[%.6f %.6f] radius[%.6f] feather[%.6f] image[%u] colorMap[%u]\ninnerColor[%.6f %.6f %.6f %.6f]\nouterColor[%.6f %.6f %.6f %.6f] outerColor[%.6f %.6f %.6f %.6f]\n",
    t[0],
    t[1],
    t[2],
    t[3],
    t[4],
    t[5],
    t[6],
    t[7],
    t[8],
    p.extent[0],
    p.extent[1],
    p.blur[0],
    p.blur[1],
    p.radius,
    p.feather,
    0,
    0,
    p.innerColor.r,
    p.innerColor.g,
    p.innerColor.b,
    p.innerColor.a,
    p.outerColor.r,
    p.outerColor.g,
    p.outerColor.b,
    p.outerColor.a,
    p.outerColor.r,
    p.outerColor.g,
    p.outerColor.b,
    p.outerColor.a,
  )

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    contourFlags: set[ContourFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  printf("bounds[%.6f %.6f %.6f %.6f]\n", bounds[0], bounds[1], bounds[2], bounds[3])
  dumpPaint(paint)

  printf("contours %u\n", contours.len)
  for i in 0 ..< contours.len:
    dumpPath(i, contours[i].addr)

proc trianglesImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    verts: openArray[Vec4],
) =
  discard

proc viewportImpl(ctx: pointer, view: Vec2, devicePixelRatio: float32) =
  discard

proc cancelImpl(ctx: pointer) =
  discard

proc flushImpl(ctx: pointer) =
  discard

proc newContext*(): Context =
  createInternal(
    BackendContextParams(
      createImpl: createImpl,
      destroyImpl: destroyImpl,
      fillImpl: fillImpl,
      trianglesImpl: trianglesImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
