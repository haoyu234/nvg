#! /bin/bash

nim -d:feature.nvg.sokol c -d:release -d:danger --cc:gcc -d:gl tests/tdemo.nim
