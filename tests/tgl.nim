import pkg/chroma
import pkg/opengl
import pkg/windy

import nvg/core
import nvg/gl

import std/monotimes
import std/strformat
import std/times

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

proc draw(ctx: ptr ContextObj) =
  ctx.save()

  ctx.setFillColor(color(1, 0, 0, 0.501961))
  ctx.setStrokeColor(color(0, 1, 0, 0.501961))

  ctx.beginPath()
  ctx.moveTo(vec2(100, 100))

  ctx.arc(vec2(250, 170), 20, 40, 50, true)
  ctx.arc(vec2(250, 170), 20, 40, 50, false)
  ctx.arc(vec2(-340, -219), 170, -9, 181, true)
  ctx.arc(vec2(-340, -219), 170, -9, 181, false)
  ctx.arc(vec2(162, -219), 76, 610, -991, true)
  ctx.arc(vec2(162, -219), 76, 610, -991, false)

  ctx.quadCurveTo(vec2(250, 170), vec2(230, 20))

  ctx.fill()
  ctx.stroke()

  ctx.restore()

proc display() =
  let size = window.size

  glClearColor(0.3, 0.3, 0.32, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)
  glViewport(0, 0, size.x, size.y)
  ctx.begin(vec2(size), 1)

  draw(ctx)

  ctx.flush()

  window.swapBuffers()

var
  i = 0
  diff = default(Duration)
  total = default(Duration)

while i < numRun and not window.closeRequested:
  let a = getMonoTime()
  display()
  let b = getMonoTime()

  diff = b - a
  total = total + diff

  pollEvents()

  inc i, 1

let us = total.inMicroseconds

echo fmt"nim version: {NimVersion}"
echo fmt"times: {numRun}"
echo fmt"total time: {us} usecs"
echo fmt"average time: {float(us) / float(numRun)} usecs"
