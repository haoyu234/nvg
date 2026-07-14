type
  LruItem* = object
    id*: int32 = high(int32)

  LruItemEntry* = object
    previous*: LruItem
    next*: LruItem

  LruHead* = object
    head*: LruItem
    tail*: LruItem

  Lru = concept
    proc getLruHead(a: Self): ptr LruHead {.inline.}
    proc getLru(a: Self, id: LruItem): ptr LruItemEntry {.inline.}

proc remove*(a: Lru, id: LruItem) {.inline.} =
  let
    lru = a.getLru(id)
    lruHead = a.getLruHead()

  if lru.previous.id != high(int32):
    let previous = a.getLru(lru.previous)
    previous.next = lru.next
  elif lruHead.head == id:
    lruHead.head = lru.next

  if lru.next.id != high(int32):
    let next = a.getLru(lru.next)
    next.previous = lru.previous
  elif lruHead.tail == id:
    lruHead.tail = lru.previous

  lru.previous = default(LruItem)
  lru.next = default(LruItem)

proc moveToFront*(a: Lru, id: LruItem) {.inline.} =
  let
    lru = a.getLru(id)
    lruHead = a.getLruHead()

  if lruHead.head != id:
    a.remove(id)

    lru.next = lruHead.head
    lruHead.head = id

    if lru.next.id != high(int32):
      let next = a.getLru(lru.next)
      next.previous = id
    else:
      lruHead.tail = id

iterator ordered*(a: Lru): LruItem =
  let
    lruHead = a.getLruHead()

  var
    id = lruHead.head

  while id.id != high(int32):
    let
      lru = a.getLru(id)
      nextIdx = lru.next

    yield id

    id = nextIdx

iterator reversed*(a: Lru): LruItem =
  let
    lruHead = a.getLruHead()

  var
    id = lruHead.tail

  while id.id != high(int32):
    let
      lru = a.getLru(id)
      previousIndex = lru.previous

    yield id

    id = previousIndex
