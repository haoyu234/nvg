type Slice2*[T] = object
  storage: ptr UncheckedArray[T]
  len: int

template `^^`(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

proc len*[T](s: Slice2[T]): int {.inline.} =
  s.len

proc slice*[T](p: ptr UncheckedArray[T], len: int): Slice2[T] {.inline.} =
  Slice2[T](storage: p, len: len)

proc slice*[T](p: var openArray[T]): Slice2[T] {.inline.} =
  Slice2[T](storage: cast[ptr UncheckedArray[T]](p[0].addr), len: p.len)

proc slice*[T](s: var seq[T]): Slice2[T] {.inline.} =
  Slice2[T](storage: cast[ptr UncheckedArray[T]](s[0].addr), len: s.len)

template toOpenArray*[T](s: Slice2[T]): openArray[T] =
  s.storage.toOpenArray(0, s.len - 1)

template toOpenArray*[T](s: Slice2[T], i: Natural): openArray[T] =
  s.storage.toOpenArray(i, s.len - 1)

template toOpenArray*[T](s: Slice2[T], i, j: Natural): openArray[T] =
  s.storage.toOpenArray(i, j)

proc `[]`*[T; L, H: Ordinal](s: Slice2[T], x: HSlice[L, H]): Slice2[T] {.inline.} =
  let a = s ^^ x.a
  let L = (s ^^ x.b) - a + 1
  Slice2[T](storage: cast[ptr UncheckedArray[T]](s.storage[a].addr), len: L)

proc `[]`*[T](s: Slice2[T], i: Natural): var T {.inline.} =
  s.storage[i]

proc `[]`*[T](s: Slice2[T], i: BackwardsIndex): var T {.inline.} =
  s.storage[s.len - int(i)]

proc `[]=`*[T](s: Slice2[T], i: Natural, v: sink T) {.inline.} =
  s.storage[i] = v
