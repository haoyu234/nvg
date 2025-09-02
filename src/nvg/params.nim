import ./core
import ./pieces

type
  ContourFlags* = enum
    EvenOdd
    Convex

  Contour* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    restart*: bool
    convex*: bool
    bounds*: Vec4

  TextureType* = enum
    TextureRgba
    TextureAlpha
    TextureFloat

  BackendContextParams* = object
    createImpl*: proc(): pointer {.nimcall.}
    destroyImpl*: proc(ctx: pointer) {.nimcall, raises: [].}

    fillImpl*: proc(
      ctx: pointer,
      paint: Paint,
      compositeOperation: CompositeOperation,
      contourFlags: set[ContourFlags],
      bounds: Vec4,
      contours: openArray[Contour],
    ) {.nimcall.}

    trianglesImpl*: proc(
      ctx: pointer,
      paint: Paint,
      compositeOperation: CompositeOperation,
      verts: openArray[Vec4],
    ) {.nimcall.}

    createTextureImpl*: proc(ctx: pointer, typ: TextureType, w, h: int32,
        imageFlags: set[ImageFlags], data: pointer): ImageId {.nimcall.}

    updateTextureImpl*: proc(ctx: pointer, imageId: ImageId, x, y, w, h,
      stride: int32, data: pointer) {.nimcall.}

    markTextureDirtyImpl*: proc(ctx: pointer, imageId: ImageId, x, y, w, h: int32) {.nimcall.}

    getTextureSizeImpl*: proc(ctx: pointer, imageId: ImageId): Vec2 {.nimcall.}

    deleteTextureImpl*: proc(ctx: pointer, imageId: ImageId) {.nimcall.}

    viewportImpl*: proc(ctx: pointer, view: Vec2,
        devicePixelRatio: float32) {.nimcall.}

    cancelImpl*: proc(ctx: pointer) {.nimcall.}

    flushImpl*: proc(ctx: pointer) {.nimcall.}

proc bytePerPixel*(typ: TextureType): int32 =
  case typ
  of TextureRgba:
    int32(sizeof(Vec4))

  of TextureAlpha:
    int32(sizeof(byte))

  of TextureFloat:
    int32(sizeof(float32))
