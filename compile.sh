#! /bin/bash

nim -d:debug -d:danger --cc:gcc --passC:-g c tests/tgl.nim
nim -d:debug -d:danger --cc:gcc --passC:-g c tests/tsokol.nim
