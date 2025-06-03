type
  Vec2* = array[2, float32]
  Vec4* = array[4, float32]
  Mat3* = array[9, float32]

proc vec2*(v1, v2: float32): Vec2 {.inline.} =
  [v1, v2]

proc vec4*(v1, v2, v3, v4: float32): Vec4 {.inline.} =
  [v1, v2, v3, v4]

proc mat3*(): Mat3 {.inline.} =
  [float32(1), 0, 0, 0, 1, 0, 0, 0, 1]
