type Piece*[T] = object
  storage: ptr UncheckedArray[T]
  dataLen: int32

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.dataLen - int32(i) else: int32(i))

proc len*[T](s: Piece[T]): int {.inline.} =
  int(s.dataLen)

proc piece*[T](p: ptr UncheckedArray[T], len: Natural): Piece[T] {.inline, raises: [].} =
  Piece[T](storage: p, dataLen: int32(len))

proc piece*[T](s: openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), dataLen: int32(s.len))

proc piece*[T](s: var openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), dataLen: int32(s.len))

template toOpenArray*[T](s: Piece[T]): openArray[T] =
  s.storage.toOpenArray(0, s.dataLen - 1)

template toOpenArray*[T](s: Piece[T], i: Natural): openArray[T] =
  assert int32(i) < s.dataLen

  s.storage.toOpenArray(i, s.dataLen - 1)

template toOpenArray*[T](s: Piece[T], i, j: Natural): openArray[T] =
  assert int32(i) <= int32(j)
  assert int32(j) < s.dataLen

  s.storage.toOpenArray(i, j)

proc `[]`*[T; L, H: Ordinal](s: Piece[T], x: HSlice[L, H]): Piece[T] {.inline.} =
  let a = s ^^ x.a
  let L = (s ^^ x.b) - a + 1

  assert L <= s.dataLen
  assert (a + L) <= s.dataLen

  if L <= 0:
    return

  piece(cast[ptr UncheckedArray[T]](s.storage[a].addr), L)

proc `[]`*[T](s: Piece[T], i: Natural): var T {.inline.} =
  assert int32(i) < s.dataLen

  s.storage[i]

proc `[]`*[T](s: Piece[T], i: BackwardsIndex): var T {.inline.} =
  let i = s.dataLen - int32(i)
  assert i < s.dataLen

  s.storage[i]

proc `[]=`*[T](s: Piece[T], i: Natural, v: sink T) {.inline.} =
  assert int32(i) < s.dataLen

  s.storage[i] = v
