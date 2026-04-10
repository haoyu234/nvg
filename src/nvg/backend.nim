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

method drawGlyphQuads*(ctx: BackendContext, paint: Paint, transform: Mat2d,
    glyphQuads: openArray[GlyphQuad],
    compositeOperation: CompositeOperation) {.base.} =
  discard

method drawContours*(ctx: BackendContext, paint: Paint, contours: openArray[
    Contour], fillRule: FillRule, compositeOperation: CompositeOperation) {.base.} =
  discard

method allocImage*(ctx: BackendContext, imageInfo: ImageInfo, imageFlags: set[
    ImageFlags]): ImageId {.base.} =
  discard

method getImageInfo*(ctx: BackendContext,
    imageId: ImageId): ImageInfo {.base.} =
  discard

method updateImage*(ctx: BackendContext, imageId: ImageId, x, y, w, h,
    strideBytes: int32, data: pointer) {.base.} =
  discard

method deleteImage*(ctx: BackendContext, imageId: ImageId) {.base.} =
  discard

method flush*(ctx: BackendContext) {.base.} =
  discard
