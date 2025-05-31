#! /bin/bash

nim c -d:release -d:danger --cc:gcc --passC:-g tests/tgl.nim
nim c -d:release -d:danger --cc:gcc --passC:-g -d:gl tests/tsokol.nim

# nim -d:NVG_DEBUG_VERTS -d:NVG_DEBUG_CORE -d:debug --cc:gcc --passC:-g c tests/tgl.nim
# nim -d:NVG_DEBUG_VERTS -d:NVG_DEBUG_CORE -d:debug -d:gl --cc:gcc --passC:-g c tests/tsokol.nim
