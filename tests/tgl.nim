import pkg/opengl
import pkg/windy

import nvg/core
import nvg/gl

import ./demo

let window = newWindow(
  "Windy Example",
  ivec2(400, 300),
  openglVersion = OpenGL4Dot1,
  msaa = msaa4x,
  vsync = false,
)

window.makeContextCurrent()
loadExtensions()

let
  numRun = 10000
  ctx = newContext()

ctx.initDemo("tgl")

proc display() =
  frameStart()

  let size = window.size

  glClearColor(0.3, 0.3, 0.32, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)
  glViewport(0, 0, size.x, size.y)

  ctx.begin([float32(size.x), float32(size.y)], float32(1))

  ctx.renderDemo1()
  ctx.renderDemo2()
  ctx.renderPerfGraph()

  ctx.flush()

  frameEnd()

  window.swapBuffers()

while not window.closeRequested:
  display()

  pollEvents()

dump()
