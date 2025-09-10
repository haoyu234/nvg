#! /bin/bash

nim -d:feature.nvg.opengl c -d:release -d:danger --cc:gcc --passC:-g -d:gl tests/tdemo.nim
nim -d:feature.nvg.opengl c -d:release -d:danger --cc:gcc --passC:-g -d:gl tests/tdash.nim
nim -d:feature.nvg.opengl c -d:release -d:danger --cc:gcc --passC:-g -d:gl tests/temoji.nim
