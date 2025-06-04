import ./color
import ./fontstash
import ./vec2

type
  FontId* = distinct FonsFontId

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

  Paint* = object
    transform*: Mat3
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color
    blur*: Vec2

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

  SomePaint* = Paint | Color

proc isNil*(fontId: FontId): bool {.inline.} =
  FonsFontId(fontId).isNil

proc setColor(p: var Paint, color: Color) =
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
