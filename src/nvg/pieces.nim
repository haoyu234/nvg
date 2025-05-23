type Piece*[T] = object
  storage: ptr UncheckedArray[T]
  len: int

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

proc len*[T](s: Piece[T]): int {.inline.} =
  s.len

proc piece*[T](p: ptr UncheckedArray[T], len: int): Piece[T] {.inline.} =
  Piece[T](storage: p, len: len)

proc piece*[T](p: openArray[T]): Piece[T] {.inline.} =
  Piece[T](storage: cast[ptr UncheckedArray[T]](p[0].addr), len: p.len)

proc piece*[T](p: var openArray[T]): Piece[T] {.inline.} =
  Piece[T](storage: cast[ptr UncheckedArray[T]](p[0].addr), len: p.len)

proc piece*[T](s: var seq[T]): Piece[T] {.inline.} =
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
  Piece[T](storage: cast[ptr UncheckedArray[T]](s.storage[a].addr), len: L)

proc `[]`*[T](s: Piece[T], i: Natural): var T {.inline.} =
  s.storage[i]

proc `[]`*[T](s: Piece[T], i: BackwardsIndex): var T {.inline.} =
  s.storage[s.len - int(i)]

proc `[]=`*[T](s: Piece[T], i: Natural, v: sink T) {.inline.} =
  s.storage[i] = v
