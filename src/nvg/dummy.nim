import ./context
import ./core
import ./params
import ./vec2

proc createImpl(): pointer =
  default(pointer)

proc destroyImpl(ctx: pointer) =
  discard

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    pathFlags: PathFlags,
    bounds: Vec4,
    paths: openArray[FlattenedPath],
) =
  discard

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
