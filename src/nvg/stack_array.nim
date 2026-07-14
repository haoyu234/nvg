import std/algorithm

import ./pieces

type
  StackArray*[N: static int; T] = object
    len: int32
    data: array[N, T]
    extra: seq[T]

proc len*[N, T](a: StackArray[N, T]): int32 =
  a.len

proc setLen*[N; T; L: Ordinal](a: var StackArray[N, T]; len: L) =
  let newLen = int32(len)
  assert newLen >= 0

  if newLen > a.len:
    let dataEnd = min(newLen, int32(a.data.len))
    for i in a.len ..< dataEnd:
      a.data[i] = default(T)

  a.len = newLen

  if newLen > int32(a.data.len):
    a.extra.setLen(newLen - int32(a.data.len))
  else:
    a.extra.setLen(0)

iterator items*[N, T](a: StackArray[N, T]): lent T =
  let
    n = min(a.len, int32(a.data.len))
    n2 = a.len - n

  for i in 0 ..< n:
    yield a.data.unsafeAddr[i]

  for i in 0 ..< n2:
    yield a.extra.unsafeAddr[i]

iterator pieces*[N, T](a: StackArray[N, T]): Piece[T] =
  let
    n = min(a.len, int32(a.data.len))
    n2 = a.len - n

  if n > 0:
    yield a.data.toOpenArray(0, n - 1).piece

  if n2 > 0:
    yield a.extra.toOpenArray(0, n2 - 1).piece

proc `[]`*[N; T; I: Ordinal](a: StackArray[N, T]; i: I): T =
  let
    i = (when I is BackwardsIndex: a.len - int32(i) else: int32(i))

  assert i >= 0 and i < a.len

  if i < int32(a.data.len):
    result = a.data[i]
    return

  result = a.extra[i - int32(a.data.len)]

proc `[]`*[N; T; I: Ordinal](a: var StackArray[N, T]; i: I): var T =
  let
    i = (when I is BackwardsIndex: a.len - int32(i) else: int32(i))

  assert i >= 0 and i < a.len

  if i < int32(a.data.len):
    result = a.data[i]
    return

  result = a.extra[i - int32(a.data.len)]

proc `[]=`*[N; T; I: Ordinal](a: var StackArray[N, T]; i: I;
    v: sink T) {.inline.} =
  let
    i = (when I is BackwardsIndex: a.len - int32(i) else: int32(i))

  assert i >= 0 and i < a.len

  if i < int32(a.data.len):
    a.data[i] = v
  else:
    a.extra[i - int32(a.data.len)] = v

proc add*[N, T](a: var StackArray[N, T]; v: sink T) =
  if a.len >= int32(a.data.len):
    a.extra.add(v)
  else:
    a.data[a.len] = v

  inc a.len, 1

proc add*[N, T](a: var StackArray[N, T]; v: openArray[T]) =
  if v.len <= 0:
    return

  let
    n = min(v.len, max(0, N - a.len))
  for idx in 0 ..< n:
    a.data[a.len + idx] = v[idx]

  if n < v.len:
    a.extra.add(v.toOpenArray(n, v.len - 1))

  inc a.len, v.len

converter toSeq*[N, T](a: StackArray[N, T]): seq[T] =
  let
    n = min(a.len, int32(a.data.len))
    n2 = a.len - n

  result = newSeqOfCap[T](a.len)
  result.add(a.data.toOpenArray(0, n - 1))
  result.add(a.extra.toOpenArray(0, n2 - 1))

proc sort*[N, T](a: var StackArray[N, T]) =
  let n = int(a.data.len)
  if a.len <= int32(n):
    if a.len > 1:
      sort(a.data.toOpenArray(0, int(a.len) - 1))
    return

  sort(a.data.toOpenArray(0, n - 1))
  sort(a.extra)

  let total = int32(a.len)
  var idx = (total + 1) div 2
  while true:
    var
      i = 0
      j = idx

    while j < total:
      if a[i] > a[i + idx]:
        swap(a[i], a[i + idx])
      i += 1
      j += 1
    if idx == 1:
      break
    idx = (idx + 1) div 2
