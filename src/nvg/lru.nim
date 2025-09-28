type
  LruItem* = object
    prev*: int32
    next*: int32

  LruHead* = object
    head*: int32
    tail*: int32

  Lru = concept
    proc getLruHead(a: Self): ptr LruHead {.inline.}
    proc getLru(a: Self, idx: int32): ptr LruItem {.inline.}

proc initLru*(lru: var LruItem) {.inline.} =
  lru.prev = high(int32)
  lru.next = high(int32)

proc initLru*(lru: var LruHead) {.inline.} =
  lru.head = high(int32)
  lru.tail = high(int32)

proc removeLru*(a: Lru, idx: int32) {.inline.} =
  let
    lru = a.getLru(idx)
    lruHead = a.getLruHead()

  if lru.prev != high(int32):
    let prev = a.getLru(lru.prev)
    prev.next = lru.next
  elif lruHead.head == idx:
    lruHead.head = lru.next

  if lru.next != high(int32):
    let next = a.getLru(lru.next)
    next.prev = lru.prev
  elif lruHead.tail == idx:
    lruHead.tail = lru.prev

  initLru(lru[])

proc moveToFrontLru*(a: Lru, idx: int32) {.inline.} =
  let
    lru = a.getLru(idx)
    lruHead = a.getLruHead()

  if lruHead.head != idx:
    a.removeLru(idx)

    lru.next = lruHead.head
    lruHead.head = idx

    if lru.next != high(int32):
      let next = a.getLru(lru.next)
      next.prev = idx
    else:
      lruHead.tail = idx

iterator orderedLru*(a: Lru): int32 =
  let
    lruHead = a.getLruHead()

  var
    idx = lruHead.head

  while idx != high(int32):
    let
      lru = a.getLru(idx)
      nextIdx = lru.next

    yield idx

    idx = nextIdx

iterator reversedLru*(a: Lru): int32 =
  let
    lruHead = a.getLruHead()

  var
    idx = lruHead.tail

  while idx != high(int32):
    let
      lru = a.getLru(idx)
      prevIdx = lru.prev

    yield idx

    idx = prevIdx
