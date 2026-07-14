import std/unicode

import ./core
import ./font_collection
import ./stack_array

type
  GlyphRun* = object
    fontId*: FontId
    glyphId*: GlyphId
    x*, y*: float32
    advance*: float32
    unicodeCodepoint*: uint32
    metrics*: GlyphMetrics
    runePos*: int32

  TextLine* = object
    runStart*: int32 # run pool range
    runLen*: int32
    width*: float32
    ascender*: float32
    descender*: float32

  TextAttribKind* = enum
    akColor
    akFontSize
    akLetterSpacing
    akWordSpacing
    akFontWeight
    akFontStyle
    akFontStretch
    akFontFamily
    akLineHeight
    akTextAlign
    akTextBaseline
    akTextWrap
    akTextOverflow

  TextAttrib* = object
    case kind*: TextAttribKind
    of akColor:
      color*: Color
    of akFontSize:
      fontSize*: float32
    of akLetterSpacing:
      letterSpacing*: float32
    of akWordSpacing:
      wordSpacing*: float32
    of akFontWeight:
      fontWeight*: FontWeight
    of akFontStyle:
      fontStyle*: FontStyle
    of akFontStretch:
      fontStretch*: FontStretch
    of akFontFamily:
      fontFamily*: FontFamily
    of akLineHeight:
      lineHeight*: float32
    of akTextAlign:
      textAlign*: HorizontalAlignment
    of akTextBaseline:
      textBaseline*: BaselineAlignment
    of akTextWrap:
      textWrap*: TextWrap
    of akTextOverflow:
      textOverflow*: TextOverflow

  TextAttribs* = object
    attribs*: StackArray[16, TextAttrib]

  TextAttribSpan* = object
    attribs*: StackArray[16, TextAttrib]
    runeRange*: Slice[int32]

  TextBlob* = ref object
    lines*: seq[TextLine]
    runs*: seq[GlyphRun]
    spans*: seq[TextAttribSpan]
    width*, height*: float32
    fontCollection*: FontCollection

  TextLayoutContext* = ref object of RootObj

proc value(attrib: TextAttrib,
    kind: static[TextAttribKind]): auto =
  when kind == akColor:
    result = attrib.color
  elif kind == akFontSize:
    result = attrib.fontSize
  elif kind == akLetterSpacing:
    result = attrib.letterSpacing
  elif kind == akWordSpacing:
    result = attrib.wordSpacing
  elif kind == akFontWeight:
    result = attrib.fontWeight
  elif kind == akFontStyle:
    result = attrib.fontStyle
  elif kind == akFontStretch:
    result = attrib.fontStretch
  elif kind == akFontFamily:
    result = attrib.fontFamily
  elif kind == akLineHeight:
    result = attrib.lineHeight
  elif kind == akTextAlign:
    result = attrib.textAlign
  elif kind == akTextBaseline:
    result = attrib.textBaseline
  elif kind == akTextWrap:
    result = attrib.textWrap
  elif kind == akTextOverflow:
    result = attrib.textOverflow

proc getAttrib*(spans: openArray[TextAttribSpan], pos: int32,
    kind: static[TextAttribKind]): auto =
  for i in countdown(spans.len - 1, 0):
    let
      span = spans[i]
    if pos in span.runeRange:
      for attrib in span.attribs:
        if attrib.kind == kind:
          result = attrib.value(kind)
          return

proc getAttrib*(spans: openArray[TextAttribSpan],
    kind: static[TextAttribKind]): auto =
  for i in countdown(spans.len - 1, 0):
    for attrib in spans[i].attribs:
      if attrib.kind == kind:
        result = attrib.value(kind)
        return

converter toAttribsStackArray*[M: static int](a: array[M,
    TextAttrib]): StackArray[16, TextAttrib] =
  result.add(a)

method createTextBlob*(textLayoutContext: TextLayoutContext,
    fontCollection: FontCollection, text: openArray[Rune],
    spans: openArray[TextAttribSpan], width,
        height: float32): TextBlob {.base.} =
  discard
