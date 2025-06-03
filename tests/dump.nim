import nvg/core
import nvg/math
import nvg/params
import nvg/pieces

proc printf(fmt: cstring) {.header: "<stdio.h>", importc: "printf", varargs.}

proc createImpl(): pointer =
  default(pointer)

proc destroyImpl(ctx: pointer) =
  discard

proc dumpPath(i: int, p: ptr PathObj) =
  printf(
    "-%03u offset[%u] count[%u] fill[%u] ccw[%u] closed[%u] convex[%u]\n",
    i + 1,
    p.offset,
    p.pointCount,
    p.fill.len,
    p.winding,
    p.closed,
    p.convex,
  )

  for v in p.fill.toOpenArray:
    printf("-- %.6f %.6f %.6f %.6f\n", v.x, v.y, v.z, v.w)

proc dumpPaint(p: ptr PaintObj) =
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
    p.extent.x,
    p.extent.y,
    p.blur.x,
    p.blur.y,
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
    paint: ptr PaintObj,
    compositeOperation: CompositeOperation,
    pathFlags: PathFlags,
    bounds: Vec4,
    paths: openArray[PathObj],
) =
  printf("bounds[%.6f %.6f %.6f %.6f]\n", bounds[0], bounds[1], bounds[2], bounds[3])
  dumpPaint(paint)

  printf("paths %u\n", paths.len)
  for i in 0 ..< paths.len:
    dumpPath(i, paths[i].addr)

proc trianglesImpl(
    ctx: pointer,
    paint: ptr PaintObj,
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

proc newContext*(): ptr ContextObj =
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
