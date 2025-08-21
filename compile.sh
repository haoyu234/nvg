#! /bin/bash

nim c -d:release -d:danger --cc:gcc --passC:-g tests/tgl.nim
nim c -d:release -d:danger --cc:gcc --passC:-g -d:gl tests/tsokol.nim
