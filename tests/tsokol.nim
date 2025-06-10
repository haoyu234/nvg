import pkg/sokol/app
import pkg/sokol/gfx
import pkg/sokol/glue
import pkg/sokol/log

import nvg/context
import nvg/sokol
import nvg/vec2

import std/strformat

import ./demo

const action = PassAction(
  colors: [
    ColorAttachmentAction(
      loadAction: loadActionClear,
      clearValue: gfx.Color(r: 0.3, g: 0.3, b: 0.32, a: 1.0),
    )
  ]
)

var ctx = default(Context)

proc frame() {.cdecl.} =
  frameStart()

  beginPass(Pass(action: action, swapchain: swapchain()))

  ctx.begin(vec2(float32(width()), float32(height())), dpiScale())

  ctx.renderDemo1()
  ctx.renderDemo2()
  ctx.renderPerfGraph()

  ctx.flush()

  endPass()
  commit()

  frameEnd()

proc init() {.cdecl.} =
  gfx.setup(
    gfx.Desc(
      environment: environment(),
      logger: gfx.Logger(fn: fn),
      pipelinePoolSize: 128, # d3d11ShaderDebugging: true,
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

  ctx.initDemo()

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

dump()
