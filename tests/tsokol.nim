import pkg/chroma
import pkg/vmath

import nvg/core
import nvg/sokol

import pkg/sokol/app
import pkg/sokol/gfx
import pkg/sokol/glue
import pkg/sokol/log

import std/monotimes
import std/strformat
import std/times

const action = PassAction(
  colors: [
    ColorAttachmentAction(
      loadAction: loadActionClear,
      clearValue: gfx.Color(r: 0.3, g: 0.3, b: 0.32, a: 1.0),
    )
  ]
)

var
  ctx = default(ptr ContextObj)

  i = 0
  diff = default(Duration)
  total = default(Duration)

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

proc frame() {.cdecl.} =
  inc i, 1

  let a = getMonoTime()

  beginPass(Pass(action: action, swapchain: swapchain()))

  ctx.begin(vec2(float32(width()), float32(height())), dpiScale())

  draw(ctx)

  ctx.flush()

  endPass()
  commit()

  let b = getMonoTime()

  diff = b - a
  total = total + diff

proc init() {.cdecl.} =
  gfx.setup(
    gfx.Desc(
      environment: environment(),
      logger: gfx.Logger(fn: fn),
      pipelinePoolSize: 128,
      # d3d11ShaderDebugging: true,
    )
  )

  case queryBackend()
  of backendGlcore:
    echo "using GLCORE backend"
  of backendD3d11:
    echo "using D3D11 backend"
  of backendMetalMacos:
    echo "using Metal backend"
  else:
    echo "using untested backend"

  setWindowTitle(fmt"tsokol.nim {queryBackend()}".cstring)

  ctx = newContext()

proc cleanup() {.cdecl.} =
  shutdown()

app.run(
  app.Desc(
    initCb: init,
    frameCb: frame,
    cleanupCb: cleanup,
    swapInterval: 0,
    sampleCount: 4,
    width: 400,
    height: 300,
    icon: IconDesc(sokol_default: true),
    logger: app.Logger(fn: log.fn),
  )
)

let us = total.inMicroseconds

echo fmt"nim version: {NimVersion}"
echo fmt"times: {i}"
echo fmt"total time: {us} usecs"
echo fmt"average time: {float(us) / float(i)} usecs"
