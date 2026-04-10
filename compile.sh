#! /bin/bash

nim c -d:debug --passC:-g -d:feature.nvg.sokol -d:feature.nvg.simple_text --nimcache:nimcache tests/tdemo.nim
