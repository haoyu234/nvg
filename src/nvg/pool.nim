type
  Vid* = distinct uint32

  Slot[T] = object
    isFree: bool
    data: T

  Pool*[T] = object
    freeIdx: uint32
    storage: seq[Slot[T]]

proc getSlot[T](vp: var Pool[T], idx: Natural): ptr Slot[T] {.inline.} =
  vp.storage[idx].addr

proc allocVid*[T](vp: var Pool[T]): Vid {.raises: [].} =
  var slot = default(ptr Slot[T])

  while int(vp.freeIdx) < vp.storage.len:
    let s = vp.getSlot(vp.freeIdx)

    if s.isFree:
      slot = s
      break

    inc vp.freeIdx

  if slot.isNil:
    vp.storage.setLen(max(256, int(vp.freeIdx * 2)))
    slot = vp.getSlot(vp.freeIdx)

  result = Vid(vp.freeIdx)

  inc vp.freeIdx

proc releaseVid*[T](vp: var Pool[T], vid: Vid) {.raises: [].} =
  if int(vid) < vp.storage.len:
    let s = vp.getSlot(int(vid))
    if not s.isFree:
      s.isFree = true
      s.data = default(T)

      vp.freeIdx = min(vp.freeIdx, uint32(vid))

proc `[]`*[T](vp: var Pool[T], vid: Vid): ptr T {.inline.} =
  if int(vid) < vp.storage.len:
    let s = vp.getSlot(int(vid))
    result = s.data.addr
  else:
    result = nil

iterator items*[T](vp: var Pool[T]): ptr T =
  for slot in vp.storage.mitems:
    if slot.isFree:
      continue

    yield slot.data.addr
