import ./slice2

proc clear*[T](s: var seq[T]) {.inline.} =
  when declared(setLenUninit):
    s.setLenUninit(0)
  else:
    s.setLen(0)

proc resize*[T](s: var seq[T], size: Natural) {.inline.} =
  when declared(setLenUninit):
    s.setLenUninit(size)
  else:
    s.setLen(size)

proc reserve*[T](s: var seq[T], size: Natural) {.inline.} =
  when declared(capacity):
    let
      oldLen = s.len
      newCap = oldLen + size

    if newCap > capacity(s):
      s.setLenUninit(newCap)
      s.setLenUninit(oldLen)
