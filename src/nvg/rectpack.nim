type
  Status = enum
    Freed
    Empty

  Item = object
    idx: uint32
    generation: uint32
    x: int32
    width: int32
    nextIdx: uint32
    rowIdx: uint32
    status: set[Status]

  Row = object
    idx: uint32
    y: int32
    height: int32
    baseHeight: int32
    maxDiff: int32
    maxEmptyItemWidth: int32
    firstItemIdx: uint32
    nextIdx: uint32
    status: set[Status]

  RectPack* = object
    width*: int32
    height*: int32
    occupancy: int32

    firstRowIdx: uint32
    rowFreeList: uint32
    itemFreeList: uint32

    rowStorage: seq[Row]
    itemStorage: seq[Item]

  RectId* = object
    idx: uint32
    generation: uint32

proc isNil*(id: RectId): bool {.inline.} =
  id.generation <= 0

proc getRow(p: RectPack, idx: uint32): ptr Row {.inline.} =
  p.rowStorage[idx].addr

proc getItem(p: RectPack, idx: uint32): ptr Item {.inline.} =
  p.itemStorage[idx].addr

proc getItem(p: RectPack, idx: RectId): ptr Item {.inline.} =
  if idx.idx >= uint32(p.itemStorage.len):
    return

  let item = p.getItem(idx.idx)
  if item.generation != idx.generation:
    return

  item

iterator rows(p: RectPack): ptr Row =
  var
    nextIdx = p.firstRowIdx

  while nextIdx != high(uint32):
    let row = p.getRow(nextIdx)
    nextIdx = row.nextIdx

    yield row

iterator items(p: RectPack, row: ptr Row): ptr Item =
  var
    nextIdx = row.firstItemIdx

  while nextIdx != high(uint32):
    let item = p.getItem(nextIdx)
    nextIdx = item.nextIdx

    yield item

proc allocRow(p: var RectPack): ptr Row {.inline.} =
  if p.rowFreeList != high(uint32):
    result = p.getRow(p.rowFreeList)
    p.rowFreeList = result.nextIdx
  else:
    let idx = uint32(p.rowStorage.len())
    p.rowStorage.setLen(idx + 1)

    result = p.getRow(idx)
    result.idx = idx
    result.nextIdx = high(uint32)

proc allocItem(p: var RectPack): ptr Item {.inline.} =
  if p.itemFreeList != high(uint32):
    result = p.getItem(p.itemFreeList)
    p.itemFreeList = result.nextIdx
  else:
    let idx = uint32(p.itemStorage.len())
    p.itemStorage.setLen(idx + 1)

    result = p.getItem(idx)
    result.generation = 1
    result.idx = idx
    result.nextIdx = high(uint32)

proc allocEmptyRow(p: var RectPack, y, height: int32): ptr Row {.inline.} =
  let
    row = p.allocRow()
    item = p.allocItem()

  row.y = y
  row.height = height
  row.maxDiff = 0
  row.baseHeight = 0
  row.maxEmptyItemWidth = high(int32)
  row.status.incl(Empty)
  row.firstItemIdx = item.idx

  item.x = 0
  item.width = p.width
  item.status.incl(Empty)
  item.rowIdx = row.idx

  row

proc allocRowItem(p: var RectPack, row: ptr Row,
    w: int32): ptr Item {.inline.} =
  for item in p.items(row):
    if Empty in item.status and item.width >= w:
      result = item
      break

  if result.isNil:
    return

  row.status.excl(Empty)
  row.maxEmptyItemWidth = high(int32)

  let
    remainderItem = p.allocItem()
    availableSpace = result.width

  remainderItem.rowIdx = row.idx
  remainderItem.x = result.x + w
  remainderItem.width = availableSpace - w
  remainderItem.status.incl(Empty)
  remainderItem.nextIdx = result.nextIdx

  result.width = w
  result.status.excl(Empty)
  result.nextIdx = remainderItem.idx

proc freeItem(p: var RectPack, item: ptr Item) {.inline.} =
  item.status.incl(Freed)
  item.nextIdx = p.itemFreeList
  p.itemFreeList = item.idx

proc freeRow(p: var RectPack, row: ptr Row) {.inline.} =
  for item in p.items(row):
    p.freeItem(item)

  row.status.incl(Freed)
  row.nextIdx = p.rowFreeList
  p.rowFreeList = row.idx

proc initIfNeeded(p: var RectPack) {.inline.} =
  if p.rowStorage.len <= 0:
    p.rowFreeList = high(uint32)
    p.itemFreeList = high(uint32)
    let newRow = p.allocEmptyRow(0, p.height)
    p.firstRowIdx = newRow.idx

proc rowHasSpace(p: var RectPack, row: ptr Row, w: int32): bool {.inline.} =
  if row.maxEmptyItemWidth == high(int32):
    row.maxEmptyItemWidth = 0

    for item in p.items(row):
      if Empty in item.status and item.width > row.maxEmptyItemWidth:
        row.maxEmptyItemWidth = item.width

  row.maxEmptyItemWidth >= w

proc align[T](v, align: T): T {.inline.} =
  (v + align - 1) and not (align - 1)

proc reserve[T](s: var seq[T], n: Natural) {.inline.} =
  let
    l = s.len
    c = n + s.len

  if capacity(s) < c:
    s.setLenUninit(c)
    s.setLenUninit(l)

proc allocRect*(p: var RectPack, w, h: int32): tuple[id: RectId, offsetX,
    offsetY: int32] =
  let
    w = max(1, w)
    h = align(h, 8)

  if w > p.width or h > p.height:
    return

  p.initIfNeeded()

  p.rowStorage.reserve(2)
  p.itemStorage.reserve(2)

  var
    bestRow = default(ptr Row)
    bestRowError = p.height

  for row in p.rows:
    if Empty in row.status:
      if h > row.height:
        continue

      if not p.rowHasSpace(row, w):
        continue

      if h < bestRowError:
        bestRowError = h
        bestRow = row
    else:
      let
        minHeight = row.baseHeight - row.maxDiff
        maxHeight = row.baseHeight + row.maxDiff

      if h < minHeight or h > maxHeight:
        continue

      if not p.rowHasSpace(row, w):
        continue

      if row.height == h:
        let item = p.allocRowItem(row, w)
        if item.isNil:
          assert false
          return

        inc p.occupancy, row.height * w
        result.id.idx = item.idx
        result.id.generation = item.generation
        result.offsetX = item.x
        result.offsetY = row.y
        return

      if h <= row.height:
        let error = row.height - h
        if error < bestRowError:
          bestRowError = error
          bestRow = row

      elif h > row.height and row.nextIdx != high(uint32):
        let error = h - row.height
        if error < bestRowError:
          let nextRow = p.getRow(row.nextIdx)
          if Empty in nextRow.status and (row.height + nextRow.height) >= h:
            bestRowError = error
            bestRow = row

  if bestRow.isNil:
    return

  if Empty in bestRow.status:
    let remainderRow = p.allocEmptyRow(bestRow.y + h, bestRow.height - h)
    remainderRow.nextIdx = bestRow.nextIdx

    bestRow.height = h
    bestRow.baseHeight = h
    bestRow.maxDiff = int32(float32(h) * 0.25)
    bestRow.nextIdx = remainderRow.idx

  elif h > bestRow.height:
    let
      nextRow = p.getRow(bestRow.nextIdx)
      diff = h - bestRow.height

    inc bestRow.height, diff
    inc nextRow.y, diff
    dec nextRow.height, diff

  let item = p.allocRowItem(bestRow, w)
  inc p.occupancy, bestRow.height * w
  result.id.idx = item.idx
  result.id.generation = item.generation
  result.offsetX = item.x
  result.offsetY = bestRow.y
  return

proc freeRect*(p: var RectPack, itemId: RectId) =
  var
    targetItem = p.getItem(itemId)

  if targetItem.isNil:
    return

  var
    targetRow = p.getRow(targetItem.rowIdx)
    prevItem = default(ptr Item)

  dec p.occupancy, targetRow.height * targetItem.width

  for item in p.items(targetRow):
    if item == targetItem:
      break

    prevItem = item

  targetItem.status.incl(Empty)
  inc targetItem.generation, 1

  if not prevItem.isNil and Empty in prevItem.status:
    inc prevItem.width, targetItem.width
    prevItem.nextIdx = targetItem.nextIdx
    p.freeItem(targetItem)
    targetItem = prevItem
  
  if targetItem.nextIdx != high(uint32):
    let
      nextItem = p.getItem(targetItem.nextIdx)

    if Empty in nextItem.status:
      inc targetItem.width, nextItem.width
      targetItem.nextIdx = nextItem.nextIdx
      p.freeItem(nextItem)

  targetRow.maxEmptyItemWidth = high(int32)

  let
    firstItem = p.getItem(targetRow.firstItemIdx)

  if Empty in firstItem.status and firstItem.nextIdx == high(uint32):
    targetRow.status.incl(Empty)

  if Empty in targetRow.status:
    targetRow.maxDiff = 0
    targetRow.baseHeight = 0

    var
      prevRow = default(ptr Row)
    for row in p.rows:
      if row == targetRow:
        break

      prevRow = row

    if not prevRow.isNil and Empty in prevRow.status:
      inc prevRow.height, targetRow.height
      prevRow.nextIdx = targetRow.nextIdx
      p.freeRow(targetRow)
      targetRow = prevRow

    if targetRow.nextIdx != high(uint32) and Empty in targetRow.status:
      let nextRow = p.getRow(targetRow.nextIdx)
      inc targetRow.height, nextRow.height
      targetRow.nextIdx = nextRow.nextIdx
      p.freeRow(nextRow)

proc expand*(p: var RectPack, w, h: int32) =
  if p.rowStorage.len <= 0:
    p.width = w
    p.height = h
    p.initIfNeeded()
    return

  if w > p.width:
    let
      expansionX = p.width
      expansionWidth = w - p.width

    p.width = w

    for row in p.rows:
      var
        lastItem = default(ptr Item)

      p.itemStorage.reserve(1)

      for item in p.items(row):
        lastItem = item

      if Empty in lastItem.status:
        inc lastItem.width, expansionWidth
      else:
        let item = p.allocItem()
        item.x = expansionX
        item.width = expansionWidth
        item.status.incl(Empty)
        item.nextIdx = lastItem.nextIdx
        item.rowIdx = row.idx
        lastItem.nextIdx = item.idx

      row.maxEmptyItemWidth = high(int32)

  if h > p.height:
    let
      expansionY = p.height
      expansionHeigh = w - p.height

    p.height = p.height
    p.rowStorage.reserve(1)

    var
      lastRow = default(ptr Row)

    for row in p.rows:
      lastRow = row

    if Empty in lastRow.status:
      inc lastRow.height, expansionHeigh
    else:
      let newRow = p.allocEmptyRow(expansionY, expansionHeigh)
      newRow.nextIdx = lastRow.nextIdx

      lastRow.nextIdx = newRow.idx

proc occupancy*(p: var RectPack): float32 {.inline.} =
  p.occupancy / (p.width * p.height)

proc clear*(p: var RectPack) {.inline.} =
  p.occupancy = 0
  p.rowStorage.setLen(0)
  p.itemStorage.setLen(0)
