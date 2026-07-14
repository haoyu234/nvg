import std/unicode

import ./stack_array
import ./tracy
import ./unicode_data

type
  Script* = enum
    Common = 0
    Arabic
    Armenian
    Bengali
    Bopomofo
    Cyrillic
    Devanagari
    Georgian
    Greek
    Gujarati
    Gurmukhi
    Hangul
    Han
    Hebrew
    Hiragana
    Katakana
    Kannada
    Lao
    Latin
    Malayalam
    Oriya
    Tamil
    Telugu
    Thai
    Tibetan
    Braille
    CanadianAboriginal
    Cherokee
    Ethiopic
    Khmer
    Mongolian
    Myanmar
    Ogham
    Runic
    Sinhala
    Syriac
    Thaana
    Yi
    Deseret
    Gothic
    OldItalic
    Buhid
    Hanunoo
    Tagbanwa
    Tagalog
    Cypriot
    Limbu
    LinearB
    Osmanya
    Shavian
    TaiLe
    Ugaritic
    Buginese
    Coptic
    Glagolitic
    Kharoshthi
    SylotiNagri
    NewTaiLue
    Tifinagh
    OldPersian
    Balinese
    Nko
    PhagsPa
    Phoenician
    Cuneiform
    Carian
    Cham
    KayahLi
    Lepcha
    Lycian
    Lydian
    OlChiki
    Rejang
    Saurashtra
    Sundanese
    Vai
    ImperialAramaic
    Avestan
    Bamum
    EgyptianHieroglyphs
    Javanese
    Kaithi
    TaiTham
    Lisu
    MeeteiMayek
    OldTurkic
    InscriptionalPahlavi
    InscriptionalParthian
    Samaritan
    OldSouthArabian
    TaiViet
    Batak
    Brahmi
    Mandaic
    Chakma
    MeroiticCursive
    MeroiticHieroglyphs
    Miao
    Sharada
    SoraSompeng
    Takri
    CaucasianAlbanian
    BassaVah
    Duployan
    Elbasan
    Grantha
    PahawhHmong
    Khojki
    LinearA
    Mahajani
    Manichaean
    MendeKikakui
    Modi
    Mro
    OldNorthArabian
    Nabataean
    Palmyrene
    PauCinHau
    OldPermic
    PsalterPahlavi
    Siddham
    Khudawadi
    Tirhuta
    WarangCiti
    Ahom
    Hatran
    AnatolianHieroglyphs
    OldHungarian
    Multani
    SignWriting
    Adlam
    Bhaiksuki
    Marchen
    Newa
    Osage
    Tangut
    MasaramGondi
    Nushu
    Soyombo
    ZanabazarSquare
    Dogra
    GunjalaGondi
    Makasar
    Medefaidrin
    HanifiRohingya
    Sogdian
    OldSogdian
    Elymaic
    NyiakengPuachueHmong
    Nandinagari
    Wancho
    Chorasmian
    DivesAkuru
    KhitanSmallScript
    Yezidi
    CyproMinoan
    OldUyghur
    Tangsa
    Toto
    Vithkuqi
    Kawi
    NagMundari
    Garay
    GurungKhema
    KiratRai
    OlOnal
    Sunuwar
    Todhri
    TuluTigalari
    BeriaErfe
    Sidetic
    TaiYo
    TolongSiki
    Inherited
    Unknown
    Nil

  BracketType* = enum
    BracketNone = 0
    BracketOpen = 0x40
    BracketClose = 0x80

  ScriptStackItem = object
    script: Script
    mirror: uint32

  ScriptStack = object
    items: StackArray[64, ScriptStackItem]
    openCount: int32

  ScriptRun* = object
    offset*: int32
    length*: int32
    script*: Script

proc lookupScript*(codepoint: uint32): Script =
  if codepoint <= uint32(0x0E01EF):
    let
      branch = int32(branchScriptIndexes[codepoint div uint32(0x0200)])
      main = int32(mainScriptIndexes[branch + int32((codepoint mod uint32(
          0x0200)) div uint32(0x0010))])
    return Script(primaryScriptData[main + int32(codepoint mod uint32(0x0010))])
  return Unknown

proc lookupBracketPair*(codepoint: uint32): (uint32, BracketType) =
  if codepoint <= uint32(0xFF63):
    let
      data = pairData[
        int32(pairIndexes[codepoint div uint32(0x6A)]) +
        int32(codepoint mod uint32(0x6A))]
      btype = cast[BracketType](data and 0xC0)
    if btype != BracketNone:
      let diff = pairDifferences[int32(data and 0x3F)]
      let paired = uint32(int32(codepoint) + int32(diff))
      return (paired, btype)
  return (uint32(0), BracketNone)

proc lookupMirror*(codepoint: uint32): uint32 =
  lookupBracketPair(codepoint)[0]

proc isConcreteScript*(s: Script): bool =
  s notin {Common, Inherited, Unknown, Nil}

proc stackPush(s: var ScriptStack, script: Script, mirror: uint32) =
  if s.items.len >= 63:
    return

  s.items.add(ScriptStackItem(script: script, mirror: mirror))
  s.openCount += 1

proc stackPop(s: var ScriptStack) =
  if s.items.len > 0:
    s.items.setLen(s.items.len - 1)
    if s.openCount > 0:
      s.openCount -= 1

proc stackLeavePairs(s: var ScriptStack) =
  s.openCount = 0

proc stackSealPairs(s: var ScriptStack, script: Script) =
  let
    n = min(s.openCount, s.items.len)
  for idx in (s.items.len - n) ..< s.items.len:
    s.items[idx].script = script
  s.openCount = 0

proc stackIsEmpty(s: ScriptStack): bool =
  s.items.len == 0

proc stackGetScript(s: ScriptStack): Script =
  s.items[s.items.len - 1].script

proc stackGetMirror(s: ScriptStack): uint32 =
  s.items[s.items.len - 1].mirror

proc isSimilarScript(a, b: Script): bool =
  a == Common or b == Common or a == b

proc stepRun(stack: var ScriptStack, runScript: var Script, cp: uint32): bool =
  let
    zone = zoneBegin("unicode_script.stepRun")
  defer: zone.zoneEnd()

  var
    isStacked = false
    script = lookupScript(cp)

  if script == Common:
    let (mirror, btype) = lookupBracketPair(cp)
    if btype == BracketOpen:
      stackPush(stack, runScript, mirror)
    elif btype == BracketClose:
      if mirror != uint32(0):
        while not stackIsEmpty(stack):
          if stackGetMirror(stack) == cp:
            break

          stackPop(stack)

        if not stackIsEmpty(stack):
          isStacked = true
          script = stackGetScript(stack)

  if isSimilarScript(runScript, script):
    if runScript == Common and script != Common:
      runScript = script
      stackSealPairs(stack, runScript)

    if isStacked:
      stackPop(stack)

    result = true

template doScriptRuns*(RUNES, BODY: untyped) =
  var
    stack = default(ScriptStack)

    runeOffset: int32 = 0
    runeEnd: int32 = 0
    runScript = Common

  for r in RUNES:
    let
      cp = uint32(r)
    if stepRun(stack, runScript, cp):
      runeEnd += 1
    else:
      if runeEnd > runeOffset:
        stackLeavePairs(stack)

        let scriptRun {.inject.} = ScriptRun(
          offset: runeOffset, length: runeEnd - runeOffset, script: runScript)
        BODY

      runeOffset = runeEnd
      runScript = Common

      if not stepRun(stack, runScript, cp):
        stackLeavePairs(stack)

        let scriptRun {.inject.} = ScriptRun(offset: runeOffset, length: 1,
            script: runScript)
        BODY

        runeOffset = runeEnd + 1
        runeEnd = runeOffset
      else:
        runeEnd += 1

  if runeEnd > runeOffset:
    stackLeavePairs(stack)

    let scriptRun {.inject.} = ScriptRun(
      offset: runeOffset, length: runeEnd - runeOffset, script: runScript)
    BODY

iterator scriptRuns*(runes: openArray[Rune]): ScriptRun =
  doScriptRuns(runes):
    yield scriptRun
