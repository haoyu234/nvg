import nvg/rectpack

var p = RectPack(
  height: 1024,
  width: 1024,
)

let
  r1 = p.allocRect(32, 32)
  r2 = p.allocRect(70, 90)

echo r1
echo r2

p.freeRect(r1.id)
p.freeRect(r2.id)

let
  r3 = p.allocRect(32, 32)

echo r3
