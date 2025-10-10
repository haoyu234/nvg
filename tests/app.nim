import nvg

type
  AppEventType* = enum
    EVENT_TYPE_NONE = 0
    EVENT_TYPE_KEY_DOWN = 1
    EVENT_TYPE_KEY_UP = 2
    EVENT_TYPE_MOUSE_DOWN = 3
    EVENT_TYPE_MOUSE_UP = 4
    EVENT_TYPE_MOUSE_MOVE = 5
    EVENT_TYPE_MOUSE_SCROLL = 6

  AppMouseButton* = enum
    MOUSE_BUTTON_NONE = 0
    MOUSE_BUTTON_LEFT = 1
    MOUSE_BUTTON_RIGHT = 2
    MOUSE_BUTTON_MIDDLE = 3

  AppKeyCode* = enum
    KEY_CODE_NONE = 0
    KEY_CODE_SPACE = 1
    KEY_CODE_APOSTROPHE = 2
    KEY_CODE_COMMA = 3
    KEY_CODE_MINUS = 4
    KEY_CODE_PERIOD = 5
    KEY_CODE_SLASH = 6
    KEY_CODE_0 = 7
    KEY_CODE_1 = 8
    KEY_CODE_2 = 9
    KEY_CODE_3 = 10
    KEY_CODE_4 = 11
    KEY_CODE_5 = 12
    KEY_CODE_6 = 13
    KEY_CODE_7 = 14
    KEY_CODE_8 = 15
    KEY_CODE_9 = 16
    KEY_CODE_SEMICOLON = 17
    KEY_CODE_EQUAL = 18
    KEY_CODE_A = 19
    KEY_CODE_B = 20
    KEY_CODE_C = 21
    KEY_CODE_D = 22
    KEY_CODE_E = 23
    KEY_CODE_F = 24
    KEY_CODE_G = 25
    KEY_CODE_H = 26
    KEY_CODE_I = 27
    KEY_CODE_J = 28
    KEY_CODE_K = 29
    KEY_CODE_L = 30
    KEY_CODE_M = 31
    KEY_CODE_N = 32
    KEY_CODE_O = 33
    KEY_CODE_P = 34
    KEY_CODE_Q = 35
    KEY_CODE_R = 36
    KEY_CODE_S = 37
    KEY_CODE_T = 38
    KEY_CODE_U = 39
    KEY_CODE_V = 40
    KEY_CODE_W = 41
    KEY_CODE_X = 42
    KEY_CODE_Y = 43
    KEY_CODE_Z = 44
    KEY_CODE_LEFT_BRACKET = 45
    KEY_CODE_BACKSLASH = 46
    KEY_CODE_RIGHT_BRACKET = 47
    KEY_CODE_GRAVE_ACCENT = 48
    KEY_CODE_ESCAPE = 49
    KEY_CODE_ENTER = 50
    KEY_CODE_TAB = 51
    KEY_CODE_BACKSPACE = 52
    KEY_CODE_INSERT = 53
    KEY_CODE_DELETE = 54
    KEY_CODE_RIGHT = 55
    KEY_CODE_LEFT = 56
    KEY_CODE_DOWN = 57
    KEY_CODE_UP = 58
    KEY_CODE_PAGE_UP = 59
    KEY_CODE_PAGE_DOWN = 60
    KEY_CODE_HOME = 61
    KEY_CODE_END = 62
    KEY_CODE_CAPS_LOCK = 63
    KEY_CODE_SCROLL_LOCK = 64
    KEY_CODE_NUM_LOCK = 65
    KEY_CODE_PRINT_SCREEN = 66
    KEY_CODE_PAUSE = 67
    KEY_CODE_F1 = 68
    KEY_CODE_F2 = 69
    KEY_CODE_F3 = 70
    KEY_CODE_F4 = 71
    KEY_CODE_F5 = 72
    KEY_CODE_F6 = 73
    KEY_CODE_F7 = 74
    KEY_CODE_F8 = 75
    KEY_CODE_F9 = 76
    KEY_CODE_F10 = 77
    KEY_CODE_F11 = 78
    KEY_CODE_F12 = 79
    KEY_CODE_KP_0 = 80
    KEY_CODE_KP_1 = 81
    KEY_CODE_KP_2 = 82
    KEY_CODE_KP_3 = 83
    KEY_CODE_KP_4 = 84
    KEY_CODE_KP_5 = 85
    KEY_CODE_KP_6 = 86
    KEY_CODE_KP_7 = 87
    KEY_CODE_KP_8 = 88
    KEY_CODE_KP_9 = 89
    KEY_CODE_KP_DECIMAL = 90
    KEY_CODE_KP_DIVIDE = 91
    KEY_CODE_KP_MULTIPLY = 92
    KEY_CODE_KP_SUBTRACT = 93
    KEY_CODE_KP_ADD = 94
    KEY_CODE_KP_ENTER = 95
    KEY_CODE_KP_EQUAL = 96
    KEY_CODE_LEFT_SHIFT = 97
    KEY_CODE_LEFT_CONTROL = 98
    KEY_CODE_LEFT_ALT = 99
    KEY_CODE_LEFT_SUPER = 100
    KEY_CODE_RIGHT_SHIFT = 101
    KEY_CODE_RIGHT_CONTROL = 102
    KEY_CODE_RIGHT_ALT = 103
    KEY_CODE_RIGHT_SUPER = 104
    KEY_CODE_MENU = 105

  AppEvent* = object
    typ*: AppEventType
    keyCode*: AppKeyCode
    mouseButton*: AppMouseButton
    mouseX*: int32
    mouseY*: int32
    mouseDx*: int32
    mouseDy*: int32
    scrollX*: int32
    scrollY*: int32

  App* = object
    name*: string
    initImpl*: proc (ctx: Context)
    frameImpl*: proc (ctx: Context)
    eventImpl*: proc (ctx: Context, event: AppEvent)

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

  proc toAppKeyCode(keyCode: cint): AppKeyCode =
    case keyCode
    of K_SPACE: KEY_CODE_SPACE
    of K_QUOTE: KEY_CODE_APOSTROPHE
    of K_COMMA: KEY_CODE_COMMA
    of K_MINUS: KEY_CODE_MINUS
    of K_PERIOD: KEY_CODE_PERIOD
    of K_SLASH: KEY_CODE_SLASH
    of K_0: KEY_CODE_0
    of K_1: KEY_CODE_1
    of K_2: KEY_CODE_2
    of K_3: KEY_CODE_3
    of K_4: KEY_CODE_4
    of K_5: KEY_CODE_5
    of K_6: KEY_CODE_6
    of K_7: KEY_CODE_7
    of K_8: KEY_CODE_8
    of K_9: KEY_CODE_9
    of K_SEMICOLON: KEY_CODE_SEMICOLON
    of K_EQUALS: KEY_CODE_EQUAL
    of K_a: KEY_CODE_A
    of K_b: KEY_CODE_B
    of K_c: KEY_CODE_C
    of K_d: KEY_CODE_D
    of K_e: KEY_CODE_E
    of K_f: KEY_CODE_F
    of K_g: KEY_CODE_G
    of K_h: KEY_CODE_H
    of K_i: KEY_CODE_I
    of K_j: KEY_CODE_J
    of K_k: KEY_CODE_K
    of K_l: KEY_CODE_L
    of K_m: KEY_CODE_M
    of K_n: KEY_CODE_N
    of K_o: KEY_CODE_O
    of K_p: KEY_CODE_P
    of K_q: KEY_CODE_Q
    of K_r: KEY_CODE_R
    of K_s: KEY_CODE_S
    of K_t: KEY_CODE_T
    of K_u: KEY_CODE_U
    of K_v: KEY_CODE_V
    of K_w: KEY_CODE_W
    of K_x: KEY_CODE_X
    of K_y: KEY_CODE_Y
    of K_z: KEY_CODE_Z
    of K_LEFTBRACKET: KEY_CODE_LEFT_BRACKET
    of K_BACKSLASH: KEY_CODE_BACKSLASH
    of K_RIGHTBRACKET: KEY_CODE_RIGHT_BRACKET
    of K_BACKQUOTE: KEY_CODE_GRAVE_ACCENT
    of K_ESCAPE: KEY_CODE_ESCAPE
    of K_RETURN: KEY_CODE_ENTER
    of K_TAB: KEY_CODE_TAB
    of K_BACKSPACE: KEY_CODE_BACKSPACE
    of K_INSERT: KEY_CODE_INSERT
    of K_DELETE: KEY_CODE_DELETE
    of K_RIGHT: KEY_CODE_RIGHT
    of K_LEFT: KEY_CODE_LEFT
    of K_DOWN: KEY_CODE_DOWN
    of K_UP: KEY_CODE_UP
    of K_PAGEUP: KEY_CODE_PAGE_UP
    of K_PAGEDOWN: KEY_CODE_PAGE_DOWN
    of K_HOME: KEY_CODE_HOME
    of K_END: KEY_CODE_END
    of K_CAPSLOCK: KEY_CODE_CAPS_LOCK
    of K_SCROLLLOCK: KEY_CODE_SCROLL_LOCK
    of K_NUMLOCKCLEAR: KEY_CODE_NUM_LOCK
    of K_PRINTSCREEN: KEY_CODE_PRINT_SCREEN
    of K_PAUSE: KEY_CODE_PAUSE
    of K_F1: KEY_CODE_F1
    of K_F2: KEY_CODE_F2
    of K_F3: KEY_CODE_F3
    of K_F4: KEY_CODE_F4
    of K_F5: KEY_CODE_F5
    of K_F6: KEY_CODE_F6
    of K_F7: KEY_CODE_F7
    of K_F8: KEY_CODE_F8
    of K_F9: KEY_CODE_F9
    of K_F10: KEY_CODE_F10
    of K_F11: KEY_CODE_F11
    of K_F12: KEY_CODE_F12
    of K_KP_0: KEY_CODE_KP_0
    of K_KP_1: KEY_CODE_KP_1
    of K_KP_2: KEY_CODE_KP_2
    of K_KP_3: KEY_CODE_KP_3
    of K_KP_4: KEY_CODE_KP_4
    of K_KP_5: KEY_CODE_KP_5
    of K_KP_6: KEY_CODE_KP_6
    of K_KP_7: KEY_CODE_KP_7
    of K_KP_8: KEY_CODE_KP_8
    of K_KP_9: KEY_CODE_KP_9
    of K_KP_DECIMAL: KEY_CODE_KP_DECIMAL
    of K_KP_DIVIDE: KEY_CODE_KP_DIVIDE
    of K_KP_MULTIPLY: KEY_CODE_KP_MULTIPLY
    of K_KP_MINUS: KEY_CODE_KP_SUBTRACT
    of K_KP_PLUS: KEY_CODE_KP_ADD
    of K_KP_ENTER: KEY_CODE_KP_ENTER
    of K_KP_EQUALS: KEY_CODE_KP_EQUAL
    of K_LSHIFT: KEY_CODE_LEFT_SHIFT
    of K_LCTRL: KEY_CODE_LEFT_CONTROL
    of K_LALT: KEY_CODE_LEFT_ALT
    of K_LGUI: KEY_CODE_LEFT_SUPER
    of K_RSHIFT: KEY_CODE_RIGHT_SHIFT
    of K_RCTRL: KEY_CODE_RIGHT_CONTROL
    of K_RALT: KEY_CODE_RIGHT_ALT
    of K_RGUI: KEY_CODE_RIGHT_SUPER
    of K_MENU: KEY_CODE_MENU
    else: KEY_CODE_NONE

  proc launch*(w, h: int32, app: App) =
    var
      name = fmt"{app.name} SDL2"
      window = createWindow(name.cstring, 100, 100, cint(w), cint(h),
          SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL)

    discard window.glCreateContext()

    loadExtensions()

    var
      e = sdl2.defaultEvent
      runGame = true

      ctx = newContext(w, h)

    ctx.setDevicePixelRatio(1)

    app.initImpl(ctx)

    var
      frameCount = 0
      frameStartTime = default(MonoTime)
      fpsGraph = initGraph("fps", PERF_GRAPH_RENDER_FPS)
      totalTime = default(Duration)

    while runGame:
      block: # begin
        frameStartTime = getMonoTime()

      block: # render
        glClearColor(0.93f, 0.93f, 0.93f, 1.0f)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

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

      while pollEvent(e):
        var
          event = default(AppEvent)

        case e.kind
        of QuitEvent:
          runGame = false
          continue

        of KeyDown, KeyUp:
          let e2 = cast[KeyboardEventPtr](e.addr)
          if e.kind == KeyDown:
            event.typ = EVENT_TYPE_KEY_DOWN
          else:
            event.typ = EVENT_TYPE_KEY_UP

          event.keyCode = toAppKeyCode(e2.keysym.sym)
          if event.keyCode == KEY_CODE_NONE:
            continue

        of MouseButtonDown, MouseButtonUp:
          let e2 = cast[MouseButtonEventPtr](e.addr)
          if e.kind == MouseButtonDown:
            event.typ = EVENT_TYPE_MOUSE_DOWN
          else:
            event.typ = EVENT_TYPE_MOUSE_UP

          case e2.button
          of BUTTON_LEFT:
            event.mouseButton = MOUSE_BUTTON_LEFT
          of BUTTON_RIGHT:
            event.mouseButton = MOUSE_BUTTON_RIGHT
          of BUTTON_MIDDLE:
            event.mouseButton = MOUSE_BUTTON_MIDDLE
          else:
            continue

          event.mouseX = e2.x
          event.mouseY = e2.y

        of MouseMotion:
          let e2 = cast[MouseMotionEventPtr](e.addr)
          event.typ = EVENT_TYPE_MOUSE_MOVE
          event.mouseX = e2.x
          event.mouseY = e2.y
          event.mouseDx = e2.xrel
          event.mouseDy = e2.yrel

        of MouseWheel:
          let e2 = cast[MouseWheelEventPtr](e.addr)
          event.typ = EVENT_TYPE_MOUSE_SCROLL
          event.scrollX = e2.x
          event.scrollY = e2.y

        else:
          continue

        if not app.eventImpl.isNil:
          app.eventImpl(ctx, event)

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
        clearValue: gfx.Color(r: 0.93f, g: 0.93f, b: 0.93f, a: 1.0f),
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

    g_ctx = newContext(width(), height())
    g_ctx.setDevicePixelRatio(dpiScale())

    if not g_app.initImpl.isNil:
      g_app.initImpl(g_ctx)

  proc toAppKeyCode(keyCode: Keycode): AppKeyCode =
    case keyCode
    of keyCodeInvalid: KEY_CODE_NONE
    of keyCodeSpace: KEY_CODE_SPACE
    of keyCodeApostrophe: KEY_CODE_APOSTROPHE
    of keyCodeComma: KEY_CODE_COMMA
    of keyCodeMinus: KEY_CODE_MINUS
    of keyCodePeriod: KEY_CODE_PERIOD
    of keyCodeSlash: KEY_CODE_SLASH
    of keyCode0: KEY_CODE_0
    of keyCode1: KEY_CODE_1
    of keyCode2: KEY_CODE_2
    of keyCode3: KEY_CODE_3
    of keyCode4: KEY_CODE_4
    of keyCode5: KEY_CODE_5
    of keyCode6: KEY_CODE_6
    of keyCode7: KEY_CODE_7
    of keyCode8: KEY_CODE_8
    of keyCode9: KEY_CODE_9
    of keyCodeSemicolon: KEY_CODE_SEMICOLON
    of keyCodeEqual: KEY_CODE_EQUAL
    of keyCodeA: KEY_CODE_A
    of keyCodeB: KEY_CODE_B
    of keyCodeC: KEY_CODE_C
    of keyCodeD: KEY_CODE_D
    of keyCodeE: KEY_CODE_E
    of keyCodeF: KEY_CODE_F
    of keyCodeG: KEY_CODE_G
    of keyCodeH: KEY_CODE_H
    of keyCodeI: KEY_CODE_I
    of keyCodeJ: KEY_CODE_J
    of keyCodeK: KEY_CODE_K
    of keyCodeL: KEY_CODE_L
    of keyCodeM: KEY_CODE_M
    of keyCodeN: KEY_CODE_N
    of keyCodeO: KEY_CODE_O
    of keyCodeP: KEY_CODE_P
    of keyCodeQ: KEY_CODE_Q
    of keyCodeR: KEY_CODE_R
    of keyCodeS: KEY_CODE_S
    of keyCodeT: KEY_CODE_T
    of keyCodeU: KEY_CODE_U
    of keyCodeV: KEY_CODE_V
    of keyCodeW: KEY_CODE_W
    of keyCodeX: KEY_CODE_X
    of keyCodeY: KEY_CODE_Y
    of keyCodeZ: KEY_CODE_Z
    of keyCodeLeftBracket: KEY_CODE_LEFT_BRACKET
    of keyCodeBackslash: KEY_CODE_BACKSLASH
    of keyCodeRightBracket: KEY_CODE_RIGHT_BRACKET
    of keyCodeGraveAccent: KEY_CODE_GRAVE_ACCENT
    of keyCodeEscape: KEY_CODE_ESCAPE
    of keyCodeEnter: KEY_CODE_ENTER
    of keyCodeTab: KEY_CODE_TAB
    of keyCodeBackspace: KEY_CODE_BACKSPACE
    of keyCodeInsert: KEY_CODE_INSERT
    of keyCodeDelete: KEY_CODE_DELETE
    of keyCodeRight: KEY_CODE_RIGHT
    of keyCodeLeft: KEY_CODE_LEFT
    of keyCodeDown: KEY_CODE_DOWN
    of keyCodeUp: KEY_CODE_UP
    of keyCodePageUp: KEY_CODE_PAGE_UP
    of keyCodePageDown: KEY_CODE_PAGE_DOWN
    of keyCodeHome: KEY_CODE_HOME
    of keyCodeEnd: KEY_CODE_END
    of keyCodeCapsLock: KEY_CODE_CAPS_LOCK
    of keyCodeScrollLock: KEY_CODE_SCROLL_LOCK
    of keyCodeNumLock: KEY_CODE_NUM_LOCK
    of keyCodePrintScreen: KEY_CODE_PRINT_SCREEN
    of keyCodePause: KEY_CODE_PAUSE
    of keyCodeF1: KEY_CODE_F1
    of keyCodeF2: KEY_CODE_F2
    of keyCodeF3: KEY_CODE_F3
    of keyCodeF4: KEY_CODE_F4
    of keyCodeF5: KEY_CODE_F5
    of keyCodeF6: KEY_CODE_F6
    of keyCodeF7: KEY_CODE_F7
    of keyCodeF8: KEY_CODE_F8
    of keyCodeF9: KEY_CODE_F9
    of keyCodeF10: KEY_CODE_F10
    of keyCodeF11: KEY_CODE_F11
    of keyCodeF12: KEY_CODE_F12
    of keyCodeKp0: KEY_CODE_KP_0
    of keyCodeKp1: KEY_CODE_KP_1
    of keyCodeKp2: KEY_CODE_KP_2
    of keyCodeKp3: KEY_CODE_KP_3
    of keyCodeKp4: KEY_CODE_KP_4
    of keyCodeKp5: KEY_CODE_KP_5
    of keyCodeKp6: KEY_CODE_KP_6
    of keyCodeKp7: KEY_CODE_KP_7
    of keyCodeKp8: KEY_CODE_KP_8
    of keyCodeKp9: KEY_CODE_KP_9
    of keyCodeKpDecimal: KEY_CODE_KP_DECIMAL
    of keyCodeKpDivide: KEY_CODE_KP_DIVIDE
    of keyCodeKpMultiply: KEY_CODE_KP_MULTIPLY
    of keyCodeKpSubtract: KEY_CODE_KP_SUBTRACT
    of keyCodeKpAdd: KEY_CODE_KP_ADD
    of keyCodeKpEnter: KEY_CODE_KP_ENTER
    of keyCodeKpEqual: KEY_CODE_KP_EQUAL
    of keyCodeLeftShift: KEY_CODE_LEFT_SHIFT
    of keyCodeLeftControl: KEY_CODE_LEFT_CONTROL
    of keyCodeLeftAlt: KEY_CODE_LEFT_ALT
    of keyCodeLeftSuper: KEY_CODE_LEFT_SUPER
    of keyCodeRightShift: KEY_CODE_RIGHT_SHIFT
    of keyCodeRightControl: KEY_CODE_RIGHT_CONTROL
    of keyCodeRightAlt: KEY_CODE_RIGHT_ALT
    of keyCodeRightSuper: KEY_CODE_RIGHT_SUPER
    of keyCodeMenu: KEY_CODE_MENU
    else: KEY_CODE_NONE

  proc event(e: ptr Event) {.cdecl.} =
    var event = default(AppEvent)

    case e.`type`
    of eventTypeKeyDown, eventTypeKeyUp:
      if e.`type` == eventTypeKeyDown:
        event.typ = EVENT_TYPE_KEY_DOWN
      else:
        event.typ = EVENT_TYPE_KEY_UP

      event.keyCode = toAppKeyCode(e.keyCode)
      if event.keyCode == KEY_CODE_NONE:
        return

    of eventTypeMouseDown, eventTypeMouseUp:
      if e.`type` == eventTypeMouseDown:
        event.typ = EVENT_TYPE_MOUSE_DOWN
      else:
        event.typ = EVENT_TYPE_MOUSE_UP

      case e.mouseButton
      of mouseButtonLeft:
        event.mouseButton = MOUSE_BUTTON_LEFT
      of mouseButtonRight:
        event.mouseButton = MOUSE_BUTTON_RIGHT
      of mouseButtonMiddle:
        event.mouseButton = MOUSE_BUTTON_MIDDLE
      else:
        return

      event.mouseX = int32(e.mouseX)
      event.mouseY = int32(e.mouseY)

    of eventTypeMouseMove:
      event.typ = EVENT_TYPE_MOUSE_MOVE
      event.mouseX = int32(e.mouseX)
      event.mouseY = int32(e.mouseY)
      event.mouseDx = int32(e.mouseDx)
      event.mouseDy = int32(e.mouseDy)

    of eventTypeMouseScroll:
      event.typ = EVENT_TYPE_MOUSE_SCROLL
      event.scrollX = int32(e.scrollX)
      event.scrollY = int32(e.scrollY)

    else:
      return

    if not g_app.eventImpl.isNil:
      g_app.eventImpl(g_ctx, event)

  proc frame() {.cdecl.} =
    block: # begin
      g_frameStartTime = getMonoTime()

    block: # render
      beginPass(Pass(action: action, swapchain: swapchain()))

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
        eventCb: event,
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
