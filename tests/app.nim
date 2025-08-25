import nvg

type
  App* = object
    name*: string
    initImpl*: proc (ctx: Context)
    frameImpl*: proc (ctx: Context)

when defined(feature.nvg.opengl):
  import pkg/sdl2
  import pkg/opengl

  import ./perfgraph

  import std/monotimes
  import std/strformat
  import std/times

  discard sdl2.init(INIT_EVERYTHING)

  discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
      SDL_GL_CONTEXT_PROFILE_CORE.cint)
  discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4.cint)
  discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1.cint)
  discard glSetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_DEBUG_FLAG.cint)

  proc launch*(w, h: int32, app: App) =
    var
      name = fmt"{app.name} SDL2"
      window = createWindow(name.cstring, 100, 100, cint(w), cint(h),
          SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL)
      glContext = window.glCreateContext()

    loadExtensions()

    var
      evt = sdl2.defaultEvent
      runGame = true

      ctx = newContext()

    app.initImpl(ctx)

    var
      frameCount = 0
      frameStartTime = default(MonoTime)
      fpsGraph = initGraph("fps", PERF_GRAPH_RENDER_FPS)
      totalTime = default(Duration)

    while runGame:
      while pollEvent(evt):
        if evt.kind == QuitEvent:
          runGame = false
          break

      block: # begin
        frameStartTime = getMonoTime()

      block: # render
        glClearColor(1.0, 1.0, 1.0, 1)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

        ctx.begin([float32(w), float32(h)], float32(1))

        ctx.save()
        app.frameImpl(ctx)
        ctx.restore()

        ctx.renderGraph(vec2(float32(w - 300), 10), fpsGraph)

        ctx.flush()

      block: # end
        inc frameCount, 1
        let diff = getMonoTime() - frameStartTime
        totalTime = totalTime + diff

        fpsGraph.updateGraph(diff)

      window.glSwapWindow()

    destroy window

elif defined(feature.nvg.sokol):
  import pkg/sokol/app as sapp
  import pkg/sokol/gfx
  import pkg/sokol/glue
  import pkg/sokol/log

  import ./perfgraph

  import std/monotimes
  import std/strformat
  import std/times

  const action = PassAction(
    colors: [
      ColorAttachmentAction(
        loadAction: loadActionClear,
        clearValue: gfx.Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    )
  ]
  )

  var
    g_app = default(App)
    g_ctx = default(Context)

  var
    g_frameStartTime = default(MonoTime)
    g_fpsGraph = initGraph("fps", PERF_GRAPH_RENDER_FPS)
    g_totalTime = default(Duration)

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

    setWindowTitle(fmt"{g_app.name} {queryBackend()}".cstring)

    g_ctx = newContext()

    if not g_app.initImpl.isNil:
      g_app.initImpl(g_ctx)

  proc frame() {.cdecl.} =
    block: # begin
      g_frameStartTime = getMonoTime()

    block: # render
      beginPass(Pass(action: action, swapchain: swapchain()))

      g_ctx.begin(vec2(float32(width()), float32(height())), dpiScale())

      if not g_app.frameImpl.isNil:
        g_ctx.save()
        g_app.frameImpl(g_ctx)
        g_ctx.restore()

      g_ctx.renderGraph(vec2(float32(width() - 300), 10), g_fpsGraph)

      g_ctx.flush()

      endPass()
      commit()

    block: # end
      let diff = getMonoTime() - g_frameStartTime
      g_totalTime = g_totalTime + diff

      g_fpsGraph.updateGraph(diff)

  proc cleanup() {.cdecl.} =
    g_ctx = nil
    shutdown()

  proc launch*(w, h: int32, app: App) =
    g_app = app

    sapp.run(
      sapp.Desc(
        initCb: init,
        frameCb: frame,
        cleanupCb: cleanup,
        swapInterval: 0,
        sampleCount: 4,
        width: w,
        height: h,
        icon: IconDesc(sokol_default: true),
        logger: sapp.Logger(fn: log.fn),
      )
    )

else:
  proc launch*(w, h: int32, app: App) =
    quit(0)
