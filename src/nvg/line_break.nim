##
## UAX #14 (Unicode Line Breaking Algorithm) port.
## Ported from libunibreak ((C) Wu Yongwei, zlib license).
##
## Entry points:
## - `lineBreakRuns`: generic iterator yielding line-break runs
##   (symmetric to `scriptRuns`)
## - `setLineBreaks`: per-character break-kind array
##

import std/enumerate
import std/unicode

import ./line_break_data
import ./tracy

type
  LineBreakClass* = enum
    lbpUndefined = 0
    lbpOP = 1
    lbpCL = 2
    lbpCP = 3
    lbpQU = 4
    lbpGL = 5
    lbpNS = 6
    lbpEX = 7
    lbpSY = 8
    lbpIS = 9
    lbpPR = 10
    lbpPO = 11
    lbpNU = 12
    lbpAL = 13
    lbpHL = 14
    lbpID = 15
    lbpIN = 16
    lbpHY = 17
    lbpBA = 18
    lbpBB = 19
    lbpB2 = 20
    lbpZW = 21
    lbpCM = 22
    lbpWJ = 23
    lbpH2 = 24
    lbpH3 = 25
    lbpJL = 26
    lbpJV = 27
    lbpJT = 28
    lbpRI = 29
    lbpEB = 30
    lbpEM = 31
    lbpZWJ = 32
    lbpCB = 33
    lbpAI = 34
    lbpBK = 35
    lbpCJ = 36
    lbpCR = 37
    lbpLF = 38
    lbpNL = 39
    lbpSA = 40
    lbpSG = 41
    lbpSP = 42
    lbpXX = 43

  BreakAction* = enum
    brkDirect
    brkIndirect
    brkCmi
    brkCmp
    brkProhibited

  EawKind* = enum
    eawNeutral
    eawAmbiguous
    eawWide
    eawFullWidth
    eawHalfWidth
    eawNarrow

  LineBreakResult* = enum
    LineBreakMustBreak
    LineBreakAllowBreak
    LineBreakNoBreak
    LineBreakUndefined # simple rules inconclusive; fall back to table lookup
    LineBreakIndeterminate

  LineBreakRun* = object
    offset*: int32
    stop*: int32
    mustBreak*: bool

  LineBreakContext = object
    lang: string
    lbcCur: LineBreakClass
    lbcNew: LineBreakClass
    lbcLast: LineBreakClass
    eaNew: EawKind
    eaLast: EawKind
    fLb8aZwj: bool
    fLb21aHebrew: bool
    cLb30aRI: int

proc lookupLineBreakClass(ranges: openArray[LbRange], cp: uint32): LineBreakClass =
  var
    l = 0
    r = ranges.len - 1
  while l <= r:
    let mid = (l + r) shr 1
    if cp < ranges[mid].start:
      r = mid - 1
    elif cp > ranges[mid].stop:
      l = mid + 1
    else:
      result = LineBreakClass(ranges[mid].cls)
      return

  lbpXX

proc lookupEawKind(ranges: openArray[EawRange], cp: uint32): EawKind =
  var
    l = 0
    r = ranges.len - 1
  while l <= r:
    let mid = (l + r) shr 1
    if cp < ranges[mid].start:
      r = mid - 1
    elif cp > ranges[mid].stop:
      l = mid + 1
    else:
      result = EawKind(ranges[mid].kind)
      return

  eawNeutral

proc getLineBreakClass(cp: uint32): LineBreakClass =
  if cp < 65536:
    LineBreakClass(lineBreakClassBmp[cp])
  else:
    lookupLineBreakClass(lineBreakClassSupplementary, cp)

proc getEawKind(cp: uint32): EawKind =
  lookupEawKind(lineBreakEawRanges, cp)

proc resolveLineBreakClass(lbc: LineBreakClass, lang: string): LineBreakClass =
  case lbc
  of lbpAI:
    # AI -> ID for zh/ja/ko
    if lang.len >= 2 and (lang[0..1] == "zh" or lang[0..1] == "ja" or lang[
        0..1] == "ko"):
      lbpID
    else:
      lbpAL
  of lbpCJ:
    lbpID # CJ -> ID under normal (non-strict) rules
  of lbpSA, lbpSG, lbpXX:
    lbpAL
  else:
    lbc

proc prepareFirstChar(ctx: var LineBreakContext) =
  ctx.lbcNew = ctx.lbcCur
  case ctx.lbcCur
  of lbpLF, lbpNL:
    ctx.lbcCur = lbpBK # LB5
  of lbpSP:
    ctx.lbcCur = lbpWJ # LB7: leading space treated as WJ
    ctx.lbcNew = lbpSP
  else:
    discard

proc getSimpleBreakResult(ctx: var LineBreakContext): LineBreakResult =
  # LB4, LB5: mandatory break after BK / CR-LF
  if ctx.lbcCur == lbpBK or (ctx.lbcCur == lbpCR and ctx.lbcNew != lbpLF):
    return LineBreakMustBreak

  case ctx.lbcNew
  of lbpSP:
    return LineBreakNoBreak # LB7
  of lbpBK, lbpLF, lbpNL:
    ctx.lbcCur = lbpBK
    return LineBreakNoBreak # LB6
  of lbpCR:
    ctx.lbcCur = lbpCR
    return LineBreakNoBreak # LB6
  else:
    LineBreakUndefined # lookup required

proc getLookupBreakResult(ctx: var LineBreakContext): LineBreakResult =
  let
    cur = int(ctx.lbcCur) - 1
    nxt = int(ctx.lbcNew) - 1

  if cur < 0 or cur > 32 or nxt < 0 or nxt > 32:
    ctx.lbcCur = ctx.lbcNew
    result = LineBreakNoBreak
    return

  case BreakAction(lineBreakActionTable[cur][nxt])
  of brkDirect:
    result = LineBreakAllowBreak
  of brkIndirect:
    result = if ctx.lbcLast == lbpSP: LineBreakAllowBreak else: LineBreakNoBreak
  of brkCmi:
    result = LineBreakAllowBreak
    if ctx.lbcLast != lbpSP:
      result = LineBreakNoBreak
      return
  of brkCmp:
    result = LineBreakNoBreak
    if ctx.lbcLast != lbpSP:
      return
  of brkProhibited:
    result = LineBreakNoBreak

  # LB8a: ZWJ
  if ctx.fLb8aZwj:
    result = LineBreakNoBreak

  # LB21a: Hebrew hyphen
  if ctx.fLb21aHebrew and (ctx.lbcCur == lbpHY or ctx.lbcCur == lbpBA):
    result = LineBreakNoBreak
    ctx.fLb21aHebrew = false
  else:
    ctx.fLb21aHebrew = (ctx.lbcCur == lbpHL)

  # LB30: no break between alnum and a (narrow) opening bracket,
  # or between a (narrow) closing bracket and alnum.
  let
    isFullWidth = ctx.eaNew in {eawFullWidth, eawWide, eawHalfWidth}
    isLastFullWidth = ctx.eaLast in {eawFullWidth, eawWide, eawHalfWidth}

  if ((ctx.lbcLast == lbpAL or ctx.lbcLast == lbpHL or ctx.lbcLast == lbpNU) and
      (ctx.lbcNew == lbpOP and not isFullWidth)) or
     ((ctx.lbcLast == lbpCP and not isLastFullWidth) and
      (ctx.lbcNew == lbpAL or ctx.lbcNew == lbpHL or ctx.lbcNew == lbpNU)):
    result = LineBreakNoBreak

  # LB30a: RI pairs
  elif ctx.lbcCur == lbpRI:
    ctx.cLb30aRI += 1
    if ctx.cLb30aRI == 2 and ctx.lbcNew == lbpRI:
      result = LineBreakAllowBreak
      ctx.cLb30aRI = 0
  else:
    ctx.cLb30aRI = 0

  ctx.lbcCur = ctx.lbcNew

proc initBreakContext(ctx: var LineBreakContext, firstCp: uint32,
    lang: string) =
  ctx.lang = lang
  ctx.lbcCur = resolveLineBreakClass(getLineBreakClass(firstCp), lang)
  ctx.lbcNew = lbpUndefined
  ctx.lbcLast = lbpUndefined
  ctx.eaNew = eawNeutral
  ctx.eaLast = eawNeutral
  ctx.fLb8aZwj = (getLineBreakClass(firstCp) == lbpZWJ)
  ctx.fLb21aHebrew = false
  ctx.cLb30aRI = 0
  prepareFirstChar(ctx)

proc processNextChar(ctx: var LineBreakContext, cp: uint32): LineBreakResult =
  # LB9, LB10: combining characters attach to the preceding base
  if ctx.lbcLast == lbpBK or ctx.lbcLast == lbpCR or
     ctx.lbcLast == lbpLF or ctx.lbcLast == lbpNL or
     ctx.lbcLast == lbpSP or ctx.lbcLast == lbpZW or
     ctx.lbcLast == lbpUndefined or
     not (ctx.lbcNew == lbpCM or ctx.lbcNew == lbpZWJ):
    ctx.lbcLast = ctx.lbcNew

  if ctx.lbcLast == lbpCM or ctx.lbcLast == lbpZWJ:
    ctx.lbcLast = lbpAL

  ctx.lbcNew = getLineBreakClass(cp)
  ctx.eaLast = ctx.eaNew
  ctx.eaNew = getEawKind(cp)

  result = getSimpleBreakResult(ctx)
  case result
  of LineBreakMustBreak:
    ctx.lbcCur = resolveLineBreakClass(ctx.lbcNew, ctx.lang)
    prepareFirstChar(ctx)
  of LineBreakUndefined:
    ctx.lbcNew = resolveLineBreakClass(ctx.lbcNew, ctx.lang)
    result = getLookupBreakResult(ctx)
  else:
    discard

  # LB8a flag for the next round
  ctx.fLb8aZwj = ctx.lbcNew == lbpZWJ

proc setLineBreaks*(text: openArray[Rune], lang = ""): seq[LineBreakResult] =
  ## UAX #14 break positions for `text`.
  ## `result[i]` is the break kind after character i:
  ##   LineBreakMustBreak / LineBreakAllowBreak / LineBreakNoBreak
  let
    zone = zoneBegin("linebreak.setLineBreaks")
  defer: zone.zoneEnd()

  if text.len == 0:
    return

  result = newSeq[LineBreakResult](text.len)

  var
    ctx: LineBreakContext

  initBreakContext(ctx, uint32(text[0]), lang)

  for idx, rune in enumerate(text.toOpenArray(1, text.len - 1)):
    let
      cp = uint32(rune)
    result[idx] = processNextChar(ctx, cp)

  let lastBrk = getSimpleBreakResult(ctx)
  if lastBrk == LineBreakMustBreak:
    result[text.len - 1] = LineBreakMustBreak
  else:
    result[text.len - 1] = LineBreakIndeterminate

iterator lineBreakRuns*(runes: openArray[Rune], lang = ""): LineBreakRun =
  ## Iterate line-break runs of `runes`, symmetric to `scriptRuns`.
  ## Each run is a character range [offset, stop) with no inner break
  ## opportunity; `mustBreak` means a mandatory break follows the run
  ## (e.g. after a line feed).
  ##
  ## Unlike `setLineBreaks`, the state machine advances inline and no
  ## per-character array is materialized.
  let
    zone = zoneBegin("linebreak.lineBreakRuns")
  defer: zone.zoneEnd()

  var
    ctx: LineBreakContext
    runStart = int32(0)
  if runes.len > 0:
    initBreakContext(ctx, uint32(runes[0]), lang)

  for idx in 1 ..< int32(runes.len):
    # processNextChar(runes[idx]) -> break between runes[idx-1] and runes[idx]
    let brk = processNextChar(ctx, uint32(runes[idx]))
    case brk
    of LineBreakMustBreak:
      # a mandatory break char (runes[idx-1], e.g. \n) joins no run:
      # end the run before it and resume after it
      yield LineBreakRun(
        offset: runStart,
        stop: int32(idx) - 1,
        mustBreak: true,
      )
      runStart = int32(idx)
    of LineBreakAllowBreak:
      yield LineBreakRun(
        offset: runStart,
        stop: int32(idx),
        mustBreak: false,
      )
      runStart = int32(idx)
    else:
      discard

  # trailing
  if runStart < int32(runes.len):
    let
      lastCls = getLineBreakClass(uint32(runes[runes.len - 1]))
      isMandatoryBreak = lastCls in {lbpBK, lbpLF, lbpNL, lbpCR}
    if isMandatoryBreak:
      # ends with a mandatory break char: the run stops before it
      yield LineBreakRun(
        offset: runStart,
        stop: int32(runes.len) - 1,
        mustBreak: true,
      )
    else:
      let lastBrk = getSimpleBreakResult(ctx)
      yield LineBreakRun(
        offset: runStart,
        stop: int32(runes.len),
        mustBreak: lastBrk == LineBreakMustBreak,
      )
