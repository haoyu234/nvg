type
  Piece*[T] = object
    data: ptr UncheckedArray[T]
    len: int32

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int32(i) else: int32(i))

proc len*[T](s: Piece[T]): int32 {.inline.} =
  s.len

proc piece*[T; L: Ordinal](p: ptr UncheckedArray[T]; len: L): Piece[T] {.inline,
    raises: [].} =
  Piece[T](data: p, len: int32(len))

proc piece*[T](s: openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](data: cast[ptr UncheckedArray[T]](s[0].addr), len: int32(s.len))

proc piece*[T](s: var openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](data: cast[ptr UncheckedArray[T]](s[0].addr), len: int32(s.len))

template toOpenArray*[T](s: Piece[T]): openArray[T] =
  s.data.toOpenArray(0, s.len - 1)

template toOpenArray*[T](s: Piece[T]; i: Ordinal): openArray[T] =
  assert int32(i) < s.len

  s.data.toOpenArray(i, s.len - 1)

template toOpenArray*[T](s: Piece[T]; i, j: Ordinal): openArray[T] =
  assert int32(i) <= int32(j)
  assert int32(j) < s.len

  s.data.toOpenArray(i, j)

proc `[]`*[T; L, H: Ordinal](s: Piece[T]; x: HSlice[L, H]): Piece[T] {.inline.} =
  let
    a = s ^^ x.a
    L = (s ^^ x.b) - a + 1

  assert L <= s.len
  assert (a + L) <= s.len

  if L <= 0:
    return

  piece(cast[ptr UncheckedArray[T]](s.data[a].addr), L)

proc `[]`*[T; I: Ordinal](s: Piece[T]; i: I): var T {.inline.} =
  assert int32(i) < s.len

  s.data[i]

proc `[]`*[T](s: Piece[T]; i: BackwardsIndex): var T {.inline.} =
  let i = s.len - int32(i)
  assert i < s.len

  s.data[i]

proc `[]=`*[T; I: Ordinal](s: Piece[T]; i: I; v: sink T) {.inline.} =
  assert int32(i) < s.len

  s.data[i] = v
