import pkg/sokol/app
import pkg/sokol/gfx
import pkg/sokol/glue
import pkg/sokol/log

import nvg/context
import nvg/sokol
import nvg/core
import nvg/path

import std/strformat
import std/monotimes
import std/unicode

import ./fonts
import ./perfgraph

const action = PassAction(
  colors: [
    ColorAttachmentAction(
      loadAction: loadActionClear,
      clearValue: gfx.Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    )
  ]
)

var ctx = default(Context)
var fpsGraph = initGraph("fps", PERF_GRAPH_RENDER_FPS)

proc frame() {.cdecl.} =
  let t1 = getMonoTime()
  beginPass(Pass(action: action, swapchain: swapchain()))

  ctx.begin(vec2(float32(width()), float32(height())), dpiScale())

  let
    size = 68f
    padding = 5f

  var p1 = Path()
  p1.rectXYWH(vec4(0, 0, size, size))

  var p2 = Path()
  p2.moveTo(vec2(size / 2, padding))
  p2.lineTo(vec2(size / 2, size - padding))

  var p3 = Path()
  p3.moveTo(vec2(padding, size / 2))
  p3.lineTo(vec2(size - padding, size / 2))

  let text = "秦时明月汉时关，万里长征人未还。但使龙城飞将在，不教胡马度阴山。"
  var idxChar = 0
  var idxLine = 0
  var lastIdx = 0

  while true:
    inc idxChar, 1

    if idxChar mod 8 == 1:
      inc idxLine, 1

      ctx.resetTransform()
      ctx.translate(vec2(padding, padding + float32(idxLine - 1) * (size +
          padding * 3)))

    ctx.strokeWidth = 3
    ctx.strokeStyle = color(152f / 255f, 15f / 255f, 41f / 255f, 1)
    ctx.strokePath(p1)
    ctx.strokeWidth = 2

    ctx.dashArray = @[padding, padding]
    ctx.strokeStyle = color(221f / 255f, 153f / 255f, 160f / 255f, 1)
    ctx.strokePath(p2)
    ctx.strokePath(p3)
    ctx.dashArray.setLen(0)

    let n = text.runeLenAt(lastIdx)
    ctx.fontId = ctx.getDefaultFont()
    ctx.fontSize = size
    ctx.fillStyle = color(51f / 255f, 51f / 255f, 51f / 255f, 1)
    ctx.textAlign = CenterAlign
    ctx.textBaseline = MiddleBaseline
    let p4 = ctx.textToPath(text.toOpenArray(lastIdx, lastIdx + n - 1), vec2(
        size / 2, size / 2))
    ctx.fillPath(p4)

    inc lastIdx, n

    ctx.translate(vec2(size, 0))

    if lastIdx >= len(text):
      break

  ctx.resetTransform()
  ctx.renderGraph(vec2(padding, float32(height()) - padding - 80), fpsGraph)

  ctx.flush()

  endPass()
  commit()

  let t2 = getMonoTime()
  fpsGraph.updateGraph(t2 - t1)

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

  setWindowTitle(fmt"tdash.nim {queryBackend()}".cstring)

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
    width: 600,
    height: 400,
    icon: IconDesc(sokol_default: true),
    logger: app.Logger(fn: log.fn),
  )
)
