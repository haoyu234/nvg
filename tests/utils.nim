import nvg/core
import nvg/path
import nvg/pieces

import std/strformat

proc dumpPath*(p: Path) =
  for command, data in p.commands:
    case command
    of MOVE:
      echo fmt"M {data[0]} {data[1]}"

    of LINE:
      echo fmt"L {data[0]} {data[1]}"

    of CURVE:
      echo fmt"C {data[0]} {data[1]} {data[2]} {data[3]}"

    of BEZIER:
      echo fmt"C {data[0]} {data[1]} {data[2]} {data[3]} {data[4]} {data[5]}"

    of CLOSE:
      echo "Z"
