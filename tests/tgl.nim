import opengl
import windy
import chroma

import nvg/gl
import nvg/core

let window = newWindow(
  "Windy Example",
  ivec2(400, 300),
  openglVersion = OpenGL4Dot1,
  msaa = msaa4x,
  vsync = false,
)

window.makeContextCurrent()
loadExtensions()

let ctx = newContext()

proc display() =
  let size = window.size

  glClearColor(0.3, 0.3, 0.32, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)
  glViewport(0, 0, size.x, size.y)

  ctx.begin(vec2(size), 1)

  ctx.save()
  ctx.setStrokeColor(color(1, 0, 0, 0.5))

  ctx.beginPath()
  ctx.moveTo(vec2(100, 100))

  ctx.arc(vec2(250, 170), 20, 40, 50, true)
  ctx.arc(vec2(250, 170), 20, 40, 50, false)
  ctx.arc(vec2(-340, -219), 170, -9, 181, true)
  ctx.arc(vec2(-340, -219), 170, -9, 181, false)
  ctx.arc(vec2(162, -219), 76, 610, -991, true)
  ctx.arc(vec2(162, -219), 76, 610, -991, false)

  ctx.fill()
  ctx.stroke()

  ctx.restore()

  ctx.flush()

  window.swapBuffers()

while not window.closeRequested:
  display()
  pollEvents()
