import std/unicode

import ./core
import ./font
import ./math
import ./stack_array
import ./tracy

type
  FontCollection* = ref object
    fonts: seq[Font]

const
  STRETCH_RATIOS: array[FontStretch, float32] = [
    float32(1.0),   # Normal
    float32(0.5),   # UltraCondensed
    float32(0.625), # ExtraCondensed
    float32(0.75),  # Condensed
    float32(0.875), # SemiCondensed
    float32(1.125), # SemiExpanded
    float32(1.25),  # Expanded
    float32(1.5),   # ExtraExpanded
    float32(2.0),   # UltraExpanded
  ]

  WEIGHT_VALUES: array[FontWeight, int32] = [
    int32(400),     # Normal
    int32(100),     # Thin
    int32(200),     # ExtraLight
    int32(200),     # UltraLight
    int32(300),     # Light
    int32(400),     # Regular
    int32(500),     # Medium
    int32(600),     # Demibold
    int32(600),     # Semibold
    int32(700),     # Bold
    int32(800),     # ExtraBold
    int32(800),     # UltraBold
    int32(900),     # Black
    int32(900),     # Heavy
    int32(950),     # ExtraBlack
    int32(950),     # UltraBlack
  ]

proc createFontCollection*(): FontCollection =
  FontCollection()

proc len*(fontCollection: FontCollection): int32 =
  int32(fontCollection.fonts.len)

proc add*(fontCollection: FontCollection, font: Font) =
  fontCollection.fonts.add(font)

proc getFont*(fontCollection: FontCollection, fontId: FontId): Font =
  for font in fontCollection.fonts:
    if font.getFontId() == fontId:
      result = font
      return

proc getFontByRune*(fontCollection: FontCollection, rune: Rune): Font =
  let
    zone = zoneBegin("fontCollection.getFontByRune")
  defer: zone.zoneEnd()

  let
    cp = uint32(rune)

  for font in fontCollection.fonts:
    let
      glyphId = font.getGlyphId(cp)
    if glyphId.id != 0:
      result = font
      return

  # No font covers the rune; keep the first font as fallback.
  if fontCollection.fonts.len > 0:
    result = fontCollection.fonts[0]

proc matchFonts*(fontCollection: FontCollection, lang: uint8,
    script: uint8, fontFamily: FontFamily,
    weight: FontWeight, style: FontStyle,
    stretch: FontStretch): seq[Font] =
  let
    zone = zoneBegin("fontCollection.matchFonts")
  defer: zone.zoneEnd()

  var
    multipleStretch = false
    multipleStyles = false
    multipleWeights = false
    matched: StackArray[64, int32]

  block matchBlock:

    for idx in 0 ..< int32(fontCollection.fonts.len):
      let
        font = fontCollection.fonts[idx]
        familyMatch = font.getFontFamily() == fontFamily
        scriptMatch = (fontFamily == Emoji) or (script == 0) or
            (script in font.getScripts())

      if familyMatch and scriptMatch:
        if matched.len > 0:
          let
            prevFontIdx = matched[matched.len - 1]
            prevFont = fontCollection.fonts[prevFontIdx]

          # Reference compares the resolved numeric values (font->stretch /
          # font->weight), not enum identity: two distinct enums can map to
          # the same number (ExtraLight/UltraLight -> 200, etc.) and must
          # NOT be counted as "multiple" weights.
          multipleStretch = multipleStretch or not nearEqual(
              STRETCH_RATIOS[prevFont.getStretch()],
              STRETCH_RATIOS[font.getStretch()], 0.01)
          multipleStyles = multipleStyles or (prevFont.getStyle() !=
              font.getStyle())
          multipleWeights = multipleWeights or
              (WEIGHT_VALUES[prevFont.getWeight()] !=
              WEIGHT_VALUES[font.getWeight()])

        matched.add(idx)

    if matched.len <= 0:
      break matchBlock

    if multipleStretch:
      let
        requestedStretch = STRETCH_RATIOS[stretch]

      var
        exactStretchMatch = false
        nearestNarrowRatioError = high(float32)
        nearestNarrowRatio = requestedStretch
        nearestWideRatioError = high(float32)
        nearestWideRatio = requestedStretch

      for idx in 0..<matched.len:
        let
          fontIdx = matched[idx]
          font = fontCollection.fonts[fontIdx]
          fontStretchRatio = STRETCH_RATIOS[font.getStretch()]

        if nearEqual(requestedStretch, fontStretchRatio, 0.01):
          exactStretchMatch = true
          break

        let error = abs(fontStretchRatio - requestedStretch)
        if fontStretchRatio < requestedStretch:
          if error < nearestNarrowRatioError:
            nearestNarrowRatioError = error
            nearestNarrowRatio = fontStretchRatio
        else:
          if error < nearestWideRatioError:
            nearestWideRatioError = error
            nearestWideRatio = fontStretchRatio

      var selectedStretch = float32(-1.0)
      if exactStretchMatch:
        selectedStretch = requestedStretch
      else:
        if requestedStretch <= 1.0:
          if nearestNarrowRatioError < high(float32):
            selectedStretch = nearestNarrowRatio
          elif nearestWideRatioError < high(float32):
            selectedStretch = nearestWideRatio
        else:
          if nearestWideRatioError < high(float32):
            selectedStretch = nearestWideRatio
          elif nearestNarrowRatioError < high(float32):
            selectedStretch = nearestNarrowRatio

      var writeIdx = int32(0)
      for idx in 0..<matched.len:
        let
          fontIdx = matched[idx]
          font = fontCollection.fonts[fontIdx]

        if nearEqual(selectedStretch, STRETCH_RATIOS[font.getStretch()], 0.01):
          matched[writeIdx] = fontIdx
          inc writeIdx, 1
      matched.setLen(writeIdx)

      if matched.len <= 1:
        break matchBlock

    if multipleStyles:
      var
        normalCount = int32(0)
        italicCount = int32(0)
        obliqueCount = int32(0)

      for idx in 0..<matched.len:
        let
          fontIdx = matched[idx]
          font = fontCollection.fonts[fontIdx]

        case font.getStyle()
        of Normal: inc normalCount, 1
        of Italic: inc italicCount, 1
        of Oblique: inc obliqueCount, 1

      var
        candidateStyles: array[3, FontStyle]
        candidateStyleCount = int32(0)

      case style
      of Italic:
        if italicCount > 0 or obliqueCount > 0:
          candidateStyles[candidateStyleCount] = Italic
          inc candidateStyleCount, 1
          candidateStyles[candidateStyleCount] = Oblique
          inc candidateStyleCount, 1
        candidateStyles[candidateStyleCount] = Normal
        inc candidateStyleCount, 1

      of Oblique:
        if italicCount > 0 or obliqueCount > 0:
          candidateStyles[candidateStyleCount] = Oblique
          inc candidateStyleCount, 1
          candidateStyles[candidateStyleCount] = Italic
          inc candidateStyleCount, 1
        candidateStyles[candidateStyleCount] = Normal
        inc candidateStyleCount, 1

      else:
        if normalCount > 0:
          candidateStyles[candidateStyleCount] = Normal
          inc candidateStyleCount, 1
        else:
          candidateStyles[candidateStyleCount] = Italic
          inc candidateStyleCount, 1
          candidateStyles[candidateStyleCount] = Oblique
          inc candidateStyleCount, 1

      var writeIdx = int32(0)
      for styleIdx in 0..<candidateStyleCount:
        let targetStyle = candidateStyles[styleIdx]
        for idx in 0..<matched.len:
          let
            fontIdx = matched[idx]
            font = fontCollection.fonts[fontIdx]

          if font.getStyle() == targetStyle:
            # stable reorder: move the matched item to writeIdx, shifting
            # intermediate elements right, preserving original order within style
            var moveIdx = idx
            while moveIdx > writeIdx:
              matched[moveIdx] = matched[moveIdx - 1]
              dec moveIdx, 1
            matched[writeIdx] = fontIdx
            inc writeIdx, 1

      matched.setLen(writeIdx)

      if matched.len <= 1:
        break matchBlock

    if multipleWeights:
      let requestedWeight = WEIGHT_VALUES[weight]
      var
        exactWeightMatch = false
        hasWeight400 = false
        hasWeight500 = false
        nearestLighterWeightError = high(int32)
        nearestLighterWeight = requestedWeight
        nearestDarkerWeightError = high(int32)
        nearestDarkerWeight = requestedWeight

      for idx in 0..<matched.len:
        let
          fontIdx = matched[idx]
          font = fontCollection.fonts[fontIdx]
          fontWeightValue = WEIGHT_VALUES[font.getWeight()]

        if requestedWeight == fontWeightValue:
          exactWeightMatch = true
          break

        let error = abs(fontWeightValue - requestedWeight)
        if fontWeightValue <= 450:
          if error < nearestLighterWeightError:
            nearestLighterWeightError = error
            nearestLighterWeight = fontWeightValue
        else:
          if error < nearestDarkerWeightError:
            nearestDarkerWeightError = error
            nearestDarkerWeight = fontWeightValue

        hasWeight400 = hasWeight400 or (fontWeightValue == 400)
        hasWeight500 = hasWeight500 or (fontWeightValue == 500)

      var selectedWeight = int32(0)
      if exactWeightMatch:
        selectedWeight = requestedWeight
      else:
        # CSS font-matching: when no exact match, 400..449 prefers 500, and
        # exactly 450 prefers 400. (Was previously < 500 / >= 500 && < 600,
        # which was wrong per the reference algorithm.)
        if requestedWeight >= 400 and requestedWeight < 450 and hasWeight500:
          selectedWeight = 500
        elif requestedWeight == 450 and hasWeight400:
          selectedWeight = 400
        else:
          if requestedWeight <= 450:
            if nearestLighterWeightError < high(int32):
              selectedWeight = nearestLighterWeight
            elif nearestDarkerWeightError < high(int32):
              selectedWeight = nearestDarkerWeight
          else:
            if nearestDarkerWeightError < high(int32):
              selectedWeight = nearestDarkerWeight
            elif nearestLighterWeightError < high(int32):
              selectedWeight = nearestLighterWeight

      var writeIdx = int32(0)
      for idx in 0..<matched.len:
        let
          fontIdx = matched[idx]
          font = fontCollection.fonts[fontIdx]

        if WEIGHT_VALUES[font.getWeight()] == selectedWeight:
          matched[writeIdx] = fontIdx
          inc writeIdx, 1
      matched.setLen(writeIdx)

      break matchBlock

  for idx in 0..<matched.len:
    let
      fontIdx = matched[idx]
      font = fontCollection.fonts[fontIdx]

    result.add(font)
