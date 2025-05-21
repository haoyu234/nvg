import ./core
import ./params

import vmath

proc createImpl(): pointer =
  default(pointer)

proc destroyImpl(ctx: pointer) =
  discard

proc createTextureImpl(
    ctx: pointer,
    tp: TextureType,
    size: IVec2,
    imageFlags: ImageFlags,
    data: openArray[byte],
): ImageId =
  default(ImageId)

proc deleteTextureImpl(ctx: pointer, image: ImageId) =
  discard

proc updateTextureImpl(
    ctx: pointer,
    image: ImageId,
    size: IVec4,
    imageFlags: ImageFlags,
    data: openArray[byte],
) =
  discard

proc getTextureSizeImpl(ctx: pointer, image: ImageId): IVec2 =
  default(IVec2)

proc fillImpl(
    ctx: pointer,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    bounds: Vec4,
    clipContours: openArray[ContourObj],
    contours: openArray[ContourObj],
) =
  discard

proc strokeImpl(
    ctx: pointer,
    paint: ptr Paint,
    compositeOperation: CompositeOperation,
    bounds: Vec4,
    clipContours: openArray[ContourObj],
    contours: openArray[ContourObj],
) =
  discard

proc trianglesImpl(
    ctx: pointer,
    paint: ptr Paint,
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
      createTextureImpl: createTextureImpl,
      deleteTextureImpl: deleteTextureImpl,
      updateTextureImpl: updateTextureImpl,
      getTextureSizeImpl: getTextureSizeImpl,
      fillImpl: fillImpl,
      strokeImpl: strokeImpl,
      trianglesImpl: trianglesImpl,
      viewportImpl: viewportImpl,
      cancelImpl: cancelImpl,
      flushImpl: flushImpl,
    )
  )
