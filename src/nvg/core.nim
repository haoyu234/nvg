type
  Vec2* = array[2, float32]
  Vec4* = array[4, float32]

  Mat2d* = object
    xx*, yx*: float32  # linear row 0: xx scales x, yx is y's contribution to the new x
    xy*, yy*: float32  # linear row 1: xy is x's contribution to the new y, yy scales y
    x0*, y0*: float32  # translation (x0, y0) applied after the linear part

  FontId* = object
    id*: uint32

  ImageId* = object
    id*: uint32

  GlyphId* = object
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
    PixelFormatRGBA32u

  AlphaType* = enum
    AlphaDefault
    AlphaPremultiplied

  ImageInfo* = object
    width*: int32
    height*: int32
    strideBytes*: int32
    pixelFormat*: PixelFormat
    alphaType*: AlphaType

  FillRule* = enum
    NonZero
    EvenOdd

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

  FontFamily* = enum
    Default
    Emoji
    SansSerif
    Serif
    MonoSpace
    Math

  FontStyle* = enum
    Normal
    Italic
    Oblique

  FontStretch* = enum
    Normal         # Normal (1.0), (Default, when zero initialized)
    UltraCondensed # Ultra condensed (0.5)
    ExtraCondensed # Extra condensed (0.625)
    Condensed      # Condensed (0.75)
    SemiCondensed  # Semi condensed (0.875)
    SemiExpanded   # Semi expanded (1.125)
    Expanded       # Expanded (1.25)
    ExtraExpanded  # Extra expanded (1.5)
    UltraExpanded  # Ultra expanded (2.0)

  FontWeight* = enum
    Normal     # Normal (400), (Default, when zero initialized)
    Thin       # Thin (100)
    ExtraLight # Extra light (200)
    UltraLight # Ultra light (200)
    Light      # Light (300)
    Regular    # Regular (400)
    Medium     # Medium (500)
    Demibold   # Demibold (600)
    Semibold   # Semibold (600)
    Bold       # Bold (700)
    ExtraBold  # Extra bold (800)
    UltraBold  # Ultra bold (800)
    Black      # Black (800)
    Heavy      # Heavy (900)
    ExtraBlack # Extra black (950)
    UltraBlack # Ultra black (950)

  FontMetrics* = object
    ascender*: int32
    descender*: int32
    lineGap*: int32
    unitsPerEm*: uint32

  GlyphMetrics* = object
    advance*: int32
    bearing*: int32

  TextWrap* = enum
    NoWrap
    WordWrap
    WordCharWrap

  TextOverflow* = enum
    Hidden
    Ellipsis

  Color* = object
    r*: uint8
    g*: uint8
    b*: uint8
    a*: uint8

  Paint* = object
    imageId*: ImageId
    transform*: Mat2d
    extent*: Vec2
    radius*: float32
    feather*: float32
    innerColor*: Color
    outerColor*: Color
    backdropColor*: Color

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

  Bounds* = object
    xMin*: float32
    yMin*: float32
    xMax*: float32
    yMax*: float32

  PathEntry* = object
    command*: Command
    p1*: Vec2
    p2*: Vec2
    p3*: Vec2

  Path* = object
    version*: uint32
    start*: Vec2
    last*: Vec2
    commands*: seq[PathEntry]

  SomePaint* = Paint | Color

proc isNil*(fontId: FontId): bool {.inline.} =
  fontId.id == 0

proc isNil*(glyphId: GlyphId): bool {.inline.} =
  glyphId.id == 0

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
  result.x0 = 0
  result.y0 = 0

proc mat2d*(xx, yx, xy, yy, x0, y0: float32): Mat2d {.inline.} =
  result.xx = xx
  result.yx = yx
  result.xy = xy
  result.yy = yy
  result.x0 = x0
  result.y0 = y0

proc color*(r, g, b, a: uint8): Color {.inline.} =
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

proc bytesPerPixel*(typ: PixelFormat): int32 =
  case typ
  of PixelFormatA8: int32(sizeof(uint8))
  of PixelFormatRGB8: int32(sizeof(uint32))
  of PixelFormatRGBA8: int32(sizeof(uint32))
  of PixelFormatA32f: int32(sizeof(float32))
  of PixelFormatRGB32f: int32(sizeof(array[3, float32]))
  of PixelFormatRGBA32f: int32(sizeof(array[4, float32]))
  of PixelFormatRGBA32u: int32(sizeof(array[4, uint32]))

proc overlap*(a, b: Bounds): bool {.inline.} =
  not (a.xMax < b.xMin or b.xMax < a.xMin or
       a.yMax < b.yMin or b.yMax < a.yMin)

proc union*(a, b: Bounds): Bounds {.inline.} =
  result.xMin = min(a.xMin, b.xMin)
  result.yMin = min(a.yMin, b.yMin)
  result.xMax = max(a.xMax, b.xMax)
  result.yMax = max(a.yMax, b.yMax)
