type
  Vec2* = array[2, float32]
  Vec4* = array[4, float32]
  Mat3* = array[9, float32]

  FontId* = distinct uint32

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
    transform*: Mat3
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
  uint32(fontId) == 0

proc vec2*(v1, v2: float32): Vec2 {.inline.} =
  [v1, v2]

proc vec4*(v1, v2, v3, v4: float32): Vec4 {.inline.} =
  [v1, v2, v3, v4]

proc mat3*(): Mat3 {.inline.} =
  [float32(1), 0, 0, 0, 1, 0, 0, 0, 1]

proc color*(r, g, b, a: float32): Color {.inline.} =
  result.r = r
  result.g = g
  result.b = b
  result.a = a

proc setColor(p: var Paint, color: Color) {.inline.} =
  p.transform = mat3()
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
