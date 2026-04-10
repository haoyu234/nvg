import ./core

type
  FontCollection* = ref object of RootObj

  TextBlob* = ref object of RootObj
  TextBlobCache* = ref object of RootObj
  TextLayoutContext* = ref object of RootObj
  TextRenderContext* = ref object of RootObj

  TextAttribs* = object
    fontSize*: float32
    fontColor*: Color
    letterSpacing*: float32
    wordSpacing*: float32
    lineHeight*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    textWrap*: TextWrap
    textOverflow*: TextOverflow

method createTextBlob*(textLayoutContext: TextLayoutContext,
    fontCollection: FontCollection, textAttribs: TextAttribs, text: openArray[
    char]): TextBlob {.base.} =
  discard

method flush*(textLayoutContext: TextLayoutContext) {.base.} =
  discard

method flush*(textRenderContext: TextRenderContext) {.base.} =
  discard

method compact*(textBlobCache: TextBlobCache) {.base.} =
  discard

method loadFromMemory*(fontCollection: FontCollection, name: string,
    buffer: seq[byte], fontFamily: FontFamily): FontId {.base.} =
  discard

method fillText*(textRenderContext: TextRenderContext,
    textLayoutContext: TextLayoutContext, textBlobCache: TextBlobCache,
    fontCollection: FontCollection, textAttribs: TextAttribs, text: openArray[
    char], pos: Vec2, transform: Mat2d) {.base.} =
  discard

method fillTextBlob*(textRenderContext: TextRenderContext, textBlob: TextBlob,
    pos: Vec2, transform: Mat2d) {.base.} =
  discard
