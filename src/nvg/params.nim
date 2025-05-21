import vmath
import chroma

import ./slice2

type
  ImageId* = distinct int32

  Paint* = object
    transform*: Mat3
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color
    blur*: Vec2
    image*: ImageId
    colorMap*: ImageId

  TextureType* = enum
    ALPHA
    RGBA

  ImageFlags* = object
    generateMipmaps*: bool
    repeatX*: bool
    repeatY*: bool
    flipY*: bool
    premultiplied*: bool
    nearestNeighborFilter*: bool

  CompositeOperation* = enum
    SourceOverOperation
    SourceInOperation
    SourceOutOperation
    ATopOperation
    DestinationOverOperation
    DestinationInOperation
    DestinationOutOperation
    DestinationATopOperation
    LighterOperation
    CopyOperation
    XorOperation

  ContourObj* = object
    offset*: int32
    pointCount*: int32
    bevelCount*: int32
    fill*: Slice2[Vec4]
    stroke*: Slice2[Vec4]
    ccw*: bool
    closed*: bool
    convex*: bool

  BackendContextParams* = object
    createImpl*: proc(): pointer {.nimcall.}
    destroyImpl*: proc(ctx: pointer) {.nimcall.}

    createTextureImpl*: proc(
      ctx: pointer,
      tp: TextureType,
      size: IVec2,
      imageFlags: ImageFlags,
      data: openArray[byte],
    ): ImageId {.nimcall.}

    deleteTextureImpl*: proc(ctx: pointer, image: ImageId) {.nimcall.}

    updateTextureImpl*: proc(
      ctx: pointer,
      image: ImageId,
      size: IVec4,
      imageFlags: ImageFlags,
      data: openArray[byte],
    ) {.nimcall.}

    getTextureSizeImpl*: proc(ctx: pointer, image: ImageId): IVec2 {.nimcall.}

    fillImpl*: proc(
      ctx: pointer,
      paint: ptr Paint,
      compositeOperation: CompositeOperation,
      bounds: Vec4,
      clipContours: openArray[ContourObj],
      contours: openArray[ContourObj],
    ) {.nimcall.}

    strokeImpl*: proc(
      ctx: pointer,
      paint: ptr Paint,
      compositeOperation: CompositeOperation,
      bounds: Vec4,
      clipContours: openArray[ContourObj],
      contours: openArray[ContourObj],
    ) {.nimcall.}

    trianglesImpl*: proc(
      ctx: pointer,
      paint: ptr Paint,
      compositeOperation: CompositeOperation,
      verts: openArray[Vec4],
    ) {.nimcall.}

    viewportImpl*: proc(ctx: pointer, view: Vec2, devicePixelRatio: float32) {.nimcall.}

    cancelImpl*: proc(ctx: pointer) {.nimcall.}

    flushImpl*: proc(ctx: pointer) {.nimcall.}
