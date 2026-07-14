#! /bin/bash

nim c -d:debug --passC:-g -d:feature.nvg.opengl --nimcache:build/opengl -o:tdemo_opengl tests/tdemo.nim
nim c -d:debug --passC:-g -d:feature.nvg.sokol --nimcache:build/sokol_d3d -o:tdemo_sokol_d3d tests/tdemo.nim
nim c -d:debug --passC:-g -d:feature.nvg.sokol -d:gl --nimcache:build/sokol_gl -o:tdemo_sokol_gl tests/tdemo.nim
