import std/unicode

import nvg
import nvg/stack_array

const
  PLEX_METRICS_RATIO = float32(1.35)

proc metricsLineHeight*(fontSize, relative: float32): float32 =
  PLEX_METRICS_RATIO * fontSize * relative

type
  RichRun* = object
    text*: string
    attribs*: StackArray[16, TextAttrib]

proc assembleRuns*(runs: openArray[RichRun],
    defaultAttribs: TextAttribs): tuple[text: string,
    attribs: seq[TextAttribSpan]] =
  var
    runeOffset = int32(0)
    spans: seq[TextAttribSpan]

  spans.add(
    TextAttribSpan(
      runeRange: int32(0) .. high(int32),
      attribs: defaultAttribs.attribs,
    ))

  for run in runs:
    var
      runeCount = int32(0)
    for _ in runes(run.text):
      inc runeCount, 1

    spans.add(TextAttribSpan(
        runeRange: runeOffset .. (runeOffset + runeCount - 1),
        attribs: run.attribs,
    ))

    result.text.add(run.text)
    runeOffset += runeCount

  result.attribs = spans
