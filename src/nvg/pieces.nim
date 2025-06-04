type Piece*[T] = object
  storage: ptr UncheckedArray[T]
  len: int

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

proc len*[T](s: Piece[T]): int {.inline.} =
  s.len

proc piece*[T](p: ptr UncheckedArray[T], len: int): Piece[T] {.inline, raises: [].} =
  Piece[T](storage: p, len: len)

proc piece*[T](s: openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), len: s.len)

proc piece*[T](s: var openArray[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), len: s.len)

proc piece*[T](s: var seq[T]): Piece[T] {.inline, raises: [].} =
  if s.len <= 0:
    return

  Piece[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), len: s.len)

template toOpenArray*[T](s: Piece[T]): openArray[T] =
  s.storage.toOpenArray(0, s.len - 1)

template toOpenArray*[T](s: Piece[T], i: Natural): openArray[T] =
  s.storage.toOpenArray(i, s.len - 1)

template toOpenArray*[T](s: Piece[T], i, j: Natural): openArray[T] =
  s.storage.toOpenArray(i, j)

proc `[]`*[T; L, H: Ordinal](s: Piece[T], x: HSlice[L, H]): Piece[T] {.inline.} =
  let a = s ^^ x.a
  let L = (s ^^ x.b) - a + 1

  assert L <= s.len
  assert (a + L) <= s.len

  if L <= 0:
    return

  piece(cast[ptr UncheckedArray[T]](s.storage[a].addr), L)

proc `[]`*[T](s: Piece[T], i: Natural): var T {.inline.} =
  assert int(i) < s.len

  s.storage[i]

proc `[]`*[T](s: Piece[T], i: BackwardsIndex): var T {.inline.} =
  let i = s.len - int(i)
  assert int(i) < s.len

  s.storage[i]

proc `[]=`*[T](s: Piece[T], i: Natural, v: sink T) {.inline.} =
  assert int(i) < s.len

  s.storage[i] = v
