type
  Color* = array[4, float32]

proc color*(r, g, b, a: float32): Color =
  [r, g, b, a]
