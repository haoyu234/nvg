import ./context
import ./core
import ./params

proc createImpl(): pointer =
  default(pointer)

proc destroyImpl(ctx: pointer) =
  discard

proc fillImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    contourFlags: set[ContourFlags],
    bounds: Vec4,
    contours: openArray[Contour],
) =
  discard

proc trianglesImpl(
    ctx: pointer,
    paint: Paint,
    compositeOperation: CompositeOperation,
    verts: openArray[Vec4],
) =
  discard

proc createTextureImpl(ctx: pointer, typ: TextureType, w, h: int32,
        imageFlags: set[ImageFlags], data: pointer): ImageId =
  discard

proc updateTextureImpl(ctx: pointer, imageId: ImageId, x, y, w, h,
      stride: int32, data: pointer) =
  discard

proc markTextureDirtyImpl(ctx: pointer, imageId: ImageId, x, y, w, h: int32) =
  discard

proc getTextureSizeImpl(ctx: pointer, imageId: ImageId): Vec2 =
  discard

proc deleteTextureImpl(ctx: pointer, imageId: ImageId) =
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
      createTextureImpl: createTextureImpl,
      updateTextureImpl: updateTextureImpl,
      markTextureDirtyImpl: markTextureDirtyImpl,
      getTextureSizeImpl: getTextureSizeImpl,
      deleteTextureImpl: deleteTextureImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
