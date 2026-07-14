import ./core
import ./pieces

type
  DrawPath* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    bounds*: Bounds

  DrawGlyph* = object
    drawRect*: Vec4
    glyphLocX*: int32
    glyphLocY*: int32
    maxBandX*: int32
    maxBandY*: int32
    color*: Color
    transform*: Mat2d

  BackendContext* = ref object of RootObj

method drawGlyphs*(ctx: BackendContext, paint: Paint, transform: Mat2d,
    curveImageId, bandImageId: ImageId, glyphs: openArray[DrawGlyph],
    compositeOperation: CompositeOperation) {.base.} =
  discard

method drawPaths*(ctx: BackendContext, paint: Paint, paths: openArray[
    DrawPath], fillRule: FillRule, compositeOperation: CompositeOperation) {.base.} =
  discard

method allocImage*(ctx: BackendContext, imageInfo: ImageInfo, imageFlags: set[
    ImageFlags]): ImageId {.base.} =
  discard

method getImageInfo*(ctx: BackendContext,
    imageId: ImageId): ImageInfo {.base.} =
  discard

method writeImagePixels*(ctx: BackendContext, imageId: ImageId, x, y, w, h,
    strideBytes: int32, data: pointer) {.base.} =
  discard

method deleteImage*(ctx: BackendContext, imageId: ImageId) {.base.} =
  discard

method flush*(ctx: BackendContext) {.base.} =
  discard

method resize*(ctx: BackendContext, w, h: int32) {.base.} =
  discard
