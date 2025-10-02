# Package

version = "0.1.0"
author = "haoyu234"
description = "lightweight vector graphics library implementing exact-coverage antialiasing"
license = "MIT"
srcDir = "src"

# Dependencies

requires "nim >= 2.2.0"

feature "sokol":
  requires "sokol >= 0.6.0"

feature "opengl":
  requires "opengl >= 1.2.9"

feature "dev":
  requires "sdl2 >= 2.0.5"
