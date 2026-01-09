import ./core
import ./math
import ./pieces

const N = int32(16)

type
  SegmentSeq = object
    len: uint16
    capacity: uint16
    pos: int32
    next: int32
    tail: int32

  TileId* = distinct uint32

  Tiles* = object
    stride: int32
    tail: int32
    storage: seq[Vec4]

proc setup*(tiles: var Tiles, w, h, capacity: Natural) {.inline.} =
  let
    n = int32(w * h)
    len = int32(float32(capacity) * 1.5) + n

  tiles.tail = n
  tiles.stride = int32(w)
  tiles.storage.setLenUninit(len)

  let s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)
  for idx in 0 ..< n:
    let b = s[idx].addr
    b.len = 0
    b.capacity = 0
    b.pos = 0
    b.next = 0
    b.tail = 0

template `[]`*(tiles: var Tiles, x, y: Natural): TileId =
  assert x >= 0
  assert y >= 0

  TileId(int32(y) * tiles.stride + int32(x))

proc empty*(tiles: var Tiles, tileId: TileId): bool {.inline.} =
  let
    n = uint32(tileId)
    s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)

    h = s[n].addr

  h.len <= 0

proc tail*(tiles: var Tiles, tileId: TileId): ptr Vec4 {.inline.} =
  let
    n = uint32(tileId)
    s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)

  var
    h = s[n].addr
    b = h

  if b.tail > 0:
    b = s[b.tail].addr

  if b.len > 0:
    return tiles.storage[b.pos + int32(b.len) - 1].addr

proc add*(tiles: var Tiles, tileId: TileId, val: sink Vec4) {.inline.} =
  let
    n = uint32(tileId)
    s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)

  var
    h = s[n].addr
    pos = default(int32)
    b = h

  if b.tail > 0:
    b = s[b.tail].addr

  if b.pos <= 0:
    pos = tiles.tail

    b.pos = pos
    b.capacity = uint16(N)

    inc tiles.tail, N
  else:
    pos = b.pos + int32(b.len)

    if b.len >= b.capacity:
      if pos == tiles.tail and b.len < high(typeof(b.len)):
        inc tiles.tail, N
        inc b.capacity, N
      else:
        b.next = tiles.tail
        h.tail = tiles.tail

        b = s[tiles.tail].addr
        inc tiles.tail, 1

        b.len = 0
        b.capacity = uint16(N)
        b.pos = tiles.tail
        b.next = 0
        b.tail = 0

        pos = b.pos

        inc tiles.tail, N

  inc b.len, 1

  if pos + N >= int32(tiles.storage.len):
    tiles.storage.setLenUninit(uint32(float32(pos) * 1.5))

  tiles.storage[pos] = val

iterator items*(tiles: var Tiles, tileId: TileId): Vec4 =
  let
    n = uint32(tileId)
    s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)

  var b = s[n].addr

  while true:
    for idx in b.pos ..< b.pos + int32(b.len):
      yield tiles.storage[idx]

    if b.next > 0:
      b = s[b.next].addr
      continue
    break

iterator pieces*(tiles: var Tiles, tileId: TileId): Piece[Vec4] =
  let
    n = uint32(tileId)
    s = cast[ptr UncheckedArray[SegmentSeq]](tiles.storage[0].addr)

  var b = s[n].addr

  while true:
    let p = cast[ptr UncheckedArray[Vec4]](tiles.storage[b.pos].addr)
    yield piece(p, int32(b.len))

    if b.next > 0:
      b = s[b.next].addr
      continue
    break
