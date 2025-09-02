type
  Vec2* = array[2, float32]
  Vec4* = array[4, float32]
  Mat2d* = array[6, float32]

  FontId* {.size: 4.} = enum
    _

  ImageId* {.size: 4.} = enum
    _

  ImageFlags* = enum
    ImageDefault = 0
    ImageGenerateMipmaps = 1 shl 0
    ImageRepeatX = 1 shl 1
    ImageRepeatY = 1 shl 2
    ImageFlipY = 1 shl 3
    ImagePremultiplied = 1 shl 4
    ImageNearest = 1 shl 5
    ImageExternalStorage = 1 shl 6

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
    TopBaseline
    MiddleBaseline
    AlphabeticBaseline
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
    image*: ImageId
    transform*: Mat2d
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color
    blur*: Vec2

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

  SomePaint* = Paint | Color

proc isNil*(fontId: FontId): bool {.inline.} =
  cast[uint32](fontId) == 0

proc isNil*(imageId: ImageId): bool {.inline.} =
  cast[uint32](imageId) == 0

proc vec2*(v1, v2: float32): Vec2 {.inline.} =
  [v1, v2]

proc vec4*(v1, v2, v3, v4: float32): Vec4 {.inline.} =
  [v1, v2, v3, v4]

proc vec4*(v1, v2: Vec2): Vec4 {.inline.} =
  [v1[0], v1[1], v2[0], v2[1]]

proc mat2d*(): Mat2d {.inline.} =
  [float32(1), 0, 0, 1, 0, 0]

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

converter parseSomePaint*(paint: SomePaint): Paint {.inline.} =
  when type(paint) is Color:
    result.setColor(paint)
  else:
    paint
