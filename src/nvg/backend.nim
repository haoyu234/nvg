import ./core
import ./pieces

type
  Contour* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    bounds*: Vec4

  BackendContext* = ref object of RootObj
    width*: int32
    height*: int32

    renderSdfImpl*: proc (ctx: BackendContext, paint: Paint, verts: openArray[
        Vec4], compositeOperation: CompositeOperation) {.nimcall.}

    renderContourImpl*: proc (ctx: BackendContext, paint: Paint,
        contours: openArray[Contour], fillRule: FillRule,
        compositeOperation: CompositeOperation) {.nimcall.}

    allocImageImpl*: proc (ctx: BackendContext,
        imageInfo: ImageInfo, imageFlags: set[ImageFlags]): ImageId {.nimcall.}

    getImageInfoImpl*: proc (ctx: BackendContext,
        imageId: ImageId): ImageInfo {.nimcall.}

    updateImageImpl*: proc (ctx: BackendContext, imageId: ImageId, x, y, w, h,
        stride: int32, data: pointer) {.nimcall.}

    deleteImageImpl*: proc (ctx: BackendContext, imageId: ImageId) {.nimcall.}

    flushImpl*: proc (ctx: BackendContext) {.nimcall.}

proc renderSdf*(ctx: BackendContext, paint: Paint, verts: openArray[Vec4],
    compositeOperation: CompositeOperation) =
  if not ctx.renderSdfImpl.isNil:
    ctx.renderSdfImpl(ctx, paint, verts, compositeOperation)

proc renderContour*(ctx: BackendContext, paint: Paint, contours: openArray[
    Contour], fillRule: FillRule, compositeOperation: CompositeOperation) =
  if not ctx.renderContourImpl.isNil:
    ctx.renderContourImpl(ctx, paint, contours, fillRule, compositeOperation)

proc allocImage*(ctx: BackendContext, imageInfo: ImageInfo, imageFlags: set[
    ImageFlags]): ImageId =
  if not ctx.allocImageImpl.isNil:
    result = ctx.allocImageImpl(ctx, imageInfo, imageFlags)

proc getImageInfo*(ctx: BackendContext, imageId: ImageId): ImageInfo {.nimcall.} =
  if not ctx.getImageInfoImpl.isNil:
    result = ctx.getImageInfoImpl(ctx, imageId)

proc updateImage*(ctx: BackendContext, imageId: ImageId, x, y, w, h,
    stride: int32, data: pointer) =
  if not ctx.updateImageImpl.isNil:
    ctx.updateImageImpl(ctx, imageId, x, y, w, h, stride, data)

proc deleteImage*(ctx: BackendContext, imageId: ImageId) =
  if not ctx.deleteImageImpl.isNil:
    ctx.deleteImageImpl(ctx, imageId)

proc flush*(ctx: BackendContext) =
  if not ctx.flushImpl.isNil:
    ctx.flushImpl(ctx)
