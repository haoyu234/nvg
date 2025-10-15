type
  Vec2* = array[2, float32]
  Vec4* = array[4, float32]

  Mat2d* = object
    xx*, yx*: float32
    xy*, yy*: float32
    dx*, dy*: float32

  FontId* = object
    id*: uint32

  ImageId* = object
    id*: uint32

  ImageFlags* = enum
    ImageDefault
    ImageGenerateMipmaps
    ImageRepeatX
    ImageRepeatY
    ImageFlipY
    ImageNearest

  PixelFormat* = enum
    PixelFormatA8
    PixelFormatRGB8
    PixelFormatRGBA8
    PixelFormatA32f
    PixelFormatRGB32f
    PixelFormatRGBA32f

  AlphaType* = enum
    AlphaDefault
    AlphaPremultiplied

  ImageInfo* = object
    width*: int32
    height*: int32
    pixelFormat*: PixelFormat
    alphaType*: AlphaType

  LineCap* = enum
    ButtCap
    RoundCap
    SquareCap

  LineJoin* = enum
    MiterJoin
    RoundJoin
    BevelJoin

  HorizontalAlignment* = enum
    LeftAlign
    CenterAlign
    RightAlign

  BaselineAlignment* = enum
    AlphabeticBaseline
    TopBaseline
    MiddleBaseline
    BottomBaseline

  FillRule* = enum
    NonZero
    EvenOdd

  Color* = object
    r*: float32
    g*: float32
    b*: float32
    a*: float32

  Paint* = object
    imageId*: ImageId
    transform*: Mat2d
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color

  CompositeOperation* = enum
    SourceOverOperation = 1
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

  Command* = enum
    MOVE
    LINE
    CURVE
    BEZIER
    CLOSE

  Path* = object
    version*: uint32
    startPos*: Vec2
    currentPos*: Vec2
    data*: seq[float32]

  SomePaint* = Paint | Color

proc isNil*(fontId: FontId): bool {.inline.} =
  fontId.id == 0

proc isNil*(imageId: ImageId): bool {.inline.} =
  imageId.id == 0

proc vec2*(v1, v2: float32): Vec2 {.inline.} =
  [float32(v1), float32(v2)]

proc vec4*(v1, v2, v3, v4: float32): Vec4 {.inline.} =
  [float32(v1), float32(v2), float32(v3), float32(v4)]

proc vec4*(v1, v2: Vec2): Vec4 {.inline.} =
  [v1[0], v1[1], v2[0], v2[1]]

proc mat2d*(): Mat2d {.inline.} =
  result.xx = 1
  result.yx = 0
  result.xy = 0
  result.yy = 1
  result.dx = 0
  result.dy = 0

proc mat2d*(xx, yx, xy, yy, dx, dy: float32): Mat2d {.inline.} =
  result.xx = xx
  result.yx = yx
  result.xy = xy
  result.yy = yy
  result.dx = dx
  result.dy = dy

proc color*(r, g, b, a: float32): Color {.inline.} =
  result.r = r
  result.g = g
  result.b = b
  result.a = a

proc setColor(p: var Paint, color: Color) {.inline.} =
  p.transform = mat2d()
  p.extent = vec2(0, 0)
  p.radius = 0
  p.feather = 1
  p.innerColor = color
  p.outerColor = color

proc premultiplied*(c: Color): Color {.inline.} =
  result.r = c.r * c.a
  result.g = c.g * c.a
  result.b = c.b * c.a
  result.a = c.a

converter parseSomePaint*(paint: SomePaint): Paint {.inline.} =
  when type(paint) is Color:
    result.setColor(paint)
  else:
    paint

proc bytesPerPixel*(typ: PixelFormat): int32 =
  case typ
  of PixelFormatA8: int32(sizeof(uint8))
  of PixelFormatRGB8: int32(sizeof(uint32))
  of PixelFormatRGBA8: int32(sizeof(uint32))
  of PixelFormatA32f: int32(sizeof(float32))
  of PixelFormatRGB32f: int32(sizeof(array[3, float32]))
  of PixelFormatRGBA32f: int32(sizeof(array[4, float32]))
