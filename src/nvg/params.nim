import pkg/chroma
import pkg/vmath

import ./pieces

type
  PaintObj* = object
    transform*: Mat3
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color
    blur*: Vec2

  # TextureType* = enum
  #   ALPHA
  #   RGBA

  # ImageFlags* = object
  #   generateMipmaps*: bool
  #   repeatX*: bool
  #   repeatY*: bool
  #   flipY*: bool
  #   premultiplied*: bool
  #   nearestNeighborFilter*: bool

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

  PathFlags* = object
    evenOdd*: bool
    convex*: bool

  PathWinding* = enum
    Default
    Ccw
    Cw

  PathObj* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    restart*: bool
    convex*: bool
    winding*: PathWinding
    bounds*: Vec4

  BackendContextParams* = object
    createImpl*: proc(): pointer {.nimcall.}
    destroyImpl*: proc(ctx: pointer) {.nimcall.}

    # createTextureImpl*: proc(
    #   ctx: pointer,
    #   tp: TextureType,
    #   size: IVec2,
    #   imageFlags: ImageFlags,
    #   data: openArray[byte],
    # ): ImageId {.nimcall.}

    # deleteTextureImpl*: proc(ctx: pointer, image: ImageId) {.nimcall.}

    # updateTextureImpl*: proc(
    #   ctx: pointer,
    #   image: ImageId,
    #   size: IVec4,
    #   imageFlags: ImageFlags,
    #   data: openArray[byte],
    # ) {.nimcall.}

    # getTextureSizeImpl*: proc(ctx: pointer, image: ImageId): IVec2 {.nimcall.}

    fillImpl*: proc(
      ctx: pointer,
      paint: ptr PaintObj,
      compositeOperation: CompositeOperation,
      pathFlags: PathFlags,
      bounds: Vec4,
      paths: openArray[PathObj],
    ) {.nimcall.}

    trianglesImpl*: proc(
      ctx: pointer,
      paint: ptr PaintObj,
      compositeOperation: CompositeOperation,
      verts: openArray[Vec4],
    ) {.nimcall.}

    viewportImpl*: proc(ctx: pointer, view: Vec2, devicePixelRatio: float32) {.nimcall.}

    cancelImpl*: proc(ctx: pointer) {.nimcall.}

    flushImpl*: proc(ctx: pointer) {.nimcall.}
