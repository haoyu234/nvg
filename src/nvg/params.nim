import ./core
import ./pieces

type
  RenderFlags* = enum
    EvenOdd

  Contour* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    bounds*: Vec4

  BackendContextParams* = object
    initImpl*: proc(ctx: pointer) {.nimcall.}
    destroyImpl*: proc(ctx: pointer) {.nimcall, raises: [].}

    fillImpl*: proc(
      ctx: pointer,
      paint: Paint,
      compositeOperation: CompositeOperation,
      renderFlags: set[RenderFlags],
      bounds: Vec4,
      contours: openArray[Contour],
    ) {.nimcall.}

    trianglesImpl*: proc(
      ctx: pointer,
      paint: Paint,
      compositeOperation: CompositeOperation,
      renderFlags: set[RenderFlags],
      verts: openArray[Vec4],
    ) {.nimcall.}

    viewportImpl*: proc(ctx: pointer, view: Vec2,
        devicePixelRatio: float32) {.nimcall.}

    cancelImpl*: proc(ctx: pointer) {.nimcall.}

    flushImpl*: proc(ctx: pointer) {.nimcall.}
