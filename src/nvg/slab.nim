type
  Slab* = object
    cap: int32
    freeList*: seq[Slice[int32]]

proc createSlab*(cap: int32): Slab =
  assert cap > 0

  result.cap = cap
  result.freeList = @[(int32(0) ..< cap)]

proc allocate*(slab: var Slab, span: int32): int32 =
  assert span > 0

  for i in 0 ..< slab.freeList.len:
    let
      iv = slab.freeList[i]
      s = iv.a
      e = iv.b + 1
    if s + span <= e:
      if span >= e - s:
        slab.freeList.delete(i)
      else:
        slab.freeList[i] = (s + span) ..< e
      result = s
      return

  -1

proc release*(slab: var Slab, base, used: int32) =
  if used <= 0:
    return

  let
    s = base
    e = base + used
  if s < 0 or e > slab.cap:
    return

  var
    pos = slab.freeList.len
  for i in 0 ..< slab.freeList.len:
    if slab.freeList[i].a > s:
      pos = i
      break

  let
    l = pos - 1
    r = pos
  if l >= 0 and slab.freeList[l].b + 1 >= s:
    if r < slab.freeList.len and slab.freeList[r].a <= e:
      slab.freeList[l] = slab.freeList[l].a ..< (slab.freeList[r].b + 1)
      slab.freeList.delete(r)
    else:
      slab.freeList[l] = slab.freeList[l].a ..< e
  elif r < slab.freeList.len and slab.freeList[r].a <= e:
    slab.freeList[r] = s ..< (slab.freeList[r].b + 1)
  else:
    slab.freeList.insert(s ..< e, pos)

proc usedSpace*(slab: Slab): int32 =
  var
    free = int32(0)
  for iv in slab.freeList:
    free += (iv.b + 1) - iv.a
  slab.cap - free
