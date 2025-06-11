import ./core
import ./pieces

type
  PathFlags* = object
    evenOdd*: bool
    convex*: bool

  Contour* = object
    offset*: int32
    pointCount*: int32
    fill*: Piece[Vec4]
    closed*: bool
    restart*: bool
    convex*: bool
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
      paint: Paint,
      compositeOperation: CompositeOperation,
      pathFlags: PathFlags,
      bounds: Vec4,
      contours: openArray[Contour],
    ) {.nimcall.}

    trianglesImpl*: proc(
      ctx: pointer,
      paint: Paint,
      compositeOperation: CompositeOperation,
      verts: openArray[Vec4],
    ) {.nimcall.}

    viewportImpl*: proc(ctx: pointer, view: Vec2, devicePixelRatio: float32) {.nimcall.}

    cancelImpl*: proc(ctx: pointer) {.nimcall.}

    flushImpl*: proc(ctx: pointer) {.nimcall.}
