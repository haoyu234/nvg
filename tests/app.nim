import std/monotimes
import std/times

import nvg

type
  AppEventType* = enum
    EVENT_TYPE_NONE
    EVENT_TYPE_KEY_DOWN
    EVENT_TYPE_KEY_UP
    EVENT_TYPE_MOUSE_DOWN
    EVENT_TYPE_MOUSE_UP
    EVENT_TYPE_MOUSE_MOVE
    EVENT_TYPE_MOUSE_SCROLL

  AppMouseButton* = enum
    MOUSE_BUTTON_NONE
    MOUSE_BUTTON_LEFT
    MOUSE_BUTTON_RIGHT
    MOUSE_BUTTON_MIDDLE

  AppKeyCode* = enum
    KEY_CODE_NONE
    KEY_CODE_SPACE
    KEY_CODE_APOSTROPHE
    KEY_CODE_COMMA
    KEY_CODE_MINUS
    KEY_CODE_PERIOD
    KEY_CODE_SLASH
    KEY_CODE_0
    KEY_CODE_1
    KEY_CODE_2
    KEY_CODE_3
    KEY_CODE_4
    KEY_CODE_5
    KEY_CODE_6
    KEY_CODE_7
    KEY_CODE_8
    KEY_CODE_9
    KEY_CODE_SEMICOLON
    KEY_CODE_EQUAL
    KEY_CODE_A
    KEY_CODE_B
    KEY_CODE_C
    KEY_CODE_D
    KEY_CODE_E
    KEY_CODE_F
    KEY_CODE_G
    KEY_CODE_H
    KEY_CODE_I
    KEY_CODE_J
    KEY_CODE_K
    KEY_CODE_L
    KEY_CODE_M
    KEY_CODE_N
    KEY_CODE_O
    KEY_CODE_P
    KEY_CODE_Q
    KEY_CODE_R
    KEY_CODE_S
    KEY_CODE_T
    KEY_CODE_U
    KEY_CODE_V
    KEY_CODE_W
    KEY_CODE_X
    KEY_CODE_Y
    KEY_CODE_Z
    KEY_CODE_LEFT_BRACKET
    KEY_CODE_BACKSLASH
    KEY_CODE_RIGHT_BRACKET
    KEY_CODE_GRAVE_ACCENT
    KEY_CODE_ESCAPE
    KEY_CODE_ENTER
    KEY_CODE_TAB
    KEY_CODE_BACKSPACE
    KEY_CODE_INSERT
    KEY_CODE_DELETE
    KEY_CODE_RIGHT
    KEY_CODE_LEFT
    KEY_CODE_DOWN
    KEY_CODE_UP
    KEY_CODE_PAGE_UP
    KEY_CODE_PAGE_DOWN
    KEY_CODE_HOME
    KEY_CODE_END
    KEY_CODE_CAPS_LOCK
    KEY_CODE_SCROLL_LOCK
    KEY_CODE_NUM_LOCK
    KEY_CODE_PRINT_SCREEN
    KEY_CODE_PAUSE
    KEY_CODE_F1
    KEY_CODE_F2
    KEY_CODE_F3
    KEY_CODE_F4
    KEY_CODE_F5
    KEY_CODE_F6
    KEY_CODE_F7
    KEY_CODE_F8
    KEY_CODE_F9
    KEY_CODE_F10
    KEY_CODE_F11
    KEY_CODE_F12
    KEY_CODE_KP_0
    KEY_CODE_KP_1
    KEY_CODE_KP_2
    KEY_CODE_KP_3
    KEY_CODE_KP_4
    KEY_CODE_KP_5
    KEY_CODE_KP_6
    KEY_CODE_KP_7
    KEY_CODE_KP_8
    KEY_CODE_KP_9
    KEY_CODE_KP_DECIMAL
    KEY_CODE_KP_DIVIDE
    KEY_CODE_KP_MULTIPLY
    KEY_CODE_KP_SUBTRACT
    KEY_CODE_KP_ADD
    KEY_CODE_KP_ENTER
    KEY_CODE_KP_EQUAL
    KEY_CODE_LEFT_SHIFT
    KEY_CODE_LEFT_CONTROL
    KEY_CODE_LEFT_ALT
    KEY_CODE_LEFT_SUPER
    KEY_CODE_RIGHT_SHIFT
    KEY_CODE_RIGHT_CONTROL
    KEY_CODE_RIGHT_ALT
    KEY_CODE_RIGHT_SUPER
    KEY_CODE_MENU

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

  App* = ref object of RootObj
    w*, h*: int32
    name*: string
    ctx*: Context
    initImpl*: proc (app: App)
    frameImpl*: proc (app: App, deltaTime: Duration)
    eventImpl*: proc (app: App, event: AppEvent)
    isErr: bool
    lastFrameTime: MonoTime
    deltaTime: Duration

proc reportError*(app: App, where, msg: string) {.used.} =
  app.isErr = true

  writeLine(stderr, "[app] uncaught exception in " & where & ": " & msg)
  writeLine(stderr, "stack trace: " & getStackTrace())

proc reportException*(app: App, e: ref Exception, where: string) {.used.} =
  app.isErr = true

  writeLine(stderr, "[app] uncaught exception in " & where & ": " & e.msg)
  writeLine(stderr, "stack trace: " & e.getStackTrace())

when defined(feature.nvg.opengl) or defined(feature.nvg.sokol):
  import nvg/backend

  proc ensureContext(app: App, backendContext: BackendContext) =
    ## Create the default context unless the caller supplied one.
    if app.ctx.isNil:
      let
        fontCollection = createFontCollection()
        textLayoutContext = createSimpleTextLayoutContext()
      app.ctx = createContext(backendContext, fontCollection,
          textLayoutContext)

  proc updateDeltaTime(app: App) =
    let now = getMonoTime()
    if app.lastFrameTime == default(MonoTime):
      app.deltaTime = initDuration(milliseconds = 16)
    else:
      app.deltaTime = now - app.lastFrameTime
    app.lastFrameTime = now

  proc dispatchEvent(app: App, event: AppEvent) =
    if app.eventImpl.isNil:
      return

    try:
      app.eventImpl(app, event)
    except Exception as e:
      app.reportException(e, "app event")

  proc runFrame(app: App) =
    app.updateDeltaTime()
    app.ctx.save()
    try:
      if not app.frameImpl.isNil:
        app.frameImpl(app, app.deltaTime)

      app.ctx.flush()
    except Exception as e:
      app.reportException(e, "app frame")
    finally:
      app.ctx.restore()

  proc initApp(app: App, backendContext: BackendContext, pixelRatio: float32) =
    app.ensureContext(backendContext)
    app.ctx.setDevicePixelRatio(pixelRatio)
    if not app.initImpl.isNil:
      app.initImpl(app)

when defined(feature.nvg.opengl):
  import std/strformat

  import pkg/opengl
  import pkg/sdl2

  import nvg/tracy

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

  proc toAppEvent(sdlEvent: Event): AppEvent =
    case sdlEvent.kind
    of KeyDown, KeyUp:
      let
        keyEvent = cast[KeyboardEventPtr](sdlEvent.addr)
        keyCode = toAppKeyCode(keyEvent.keysym.sym)
      if keyCode == KEY_CODE_NONE:
        return
      if sdlEvent.kind == KeyDown:
        result.typ = EVENT_TYPE_KEY_DOWN
      else:
        result.typ = EVENT_TYPE_KEY_UP
      result.keyCode = keyCode
    of MouseButtonDown, MouseButtonUp:
      let mouseEvent = cast[MouseButtonEventPtr](sdlEvent.addr)
      case mouseEvent.button
      of BUTTON_LEFT:
        result.mouseButton = MOUSE_BUTTON_LEFT
      of BUTTON_RIGHT:
        result.mouseButton = MOUSE_BUTTON_RIGHT
      of BUTTON_MIDDLE:
        result.mouseButton = MOUSE_BUTTON_MIDDLE
      else:
        return
      if sdlEvent.kind == MouseButtonDown:
        result.typ = EVENT_TYPE_MOUSE_DOWN
      else:
        result.typ = EVENT_TYPE_MOUSE_UP
      result.mouseX = mouseEvent.x
      result.mouseY = mouseEvent.y
    of MouseMotion:
      let motionEvent = cast[MouseMotionEventPtr](sdlEvent.addr)
      result.typ = EVENT_TYPE_MOUSE_MOVE
      result.mouseX = motionEvent.x
      result.mouseY = motionEvent.y
      result.mouseDx = motionEvent.xrel
      result.mouseDy = motionEvent.yrel
    of MouseWheel:
      let wheelEvent = cast[MouseWheelEventPtr](sdlEvent.addr)
      result.typ = EVENT_TYPE_MOUSE_SCROLL
      result.scrollX = wheelEvent.x
      result.scrollY = wheelEvent.y
    else:
      discard

  proc setupPixelRatio(ctx: Context, window: WindowPtr, w, h: int32) =
    ctx.backendContext.resize(w, h)

    var
      drawW, drawH: cint

    glGetDrawableSize(window, drawW, drawH)
    glViewport(0, 0, drawW, drawH)

    let
      pixelRatio = float32(drawW) / float32(w)
    ctx.setDevicePixelRatio(pixelRatio)

  proc raiseSDLError(name: string) =
    raise newException(OSError, name & ": " & $sdl2.getError())

  proc launch*(app: App) =
    var
      window: WindowPtr = nil
      glCtx: GlContextPtr = nil
      runGame = true
    try:
      if not sdl2.setHint("SDL_WINDOWS_DPI_SCALING", "1"):
        writeLine(stderr, "[app] SDL_WINDOWS_DPI_SCALING hint not honored")
      if sdl2.init(INIT_VIDEO or INIT_EVENTS) != SdlSuccess:
        raise newException(OSError, "SDL_Init: " & $sdl2.getError())

      discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4.cint)
      discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3.cint)
      discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
          SDL_GL_CONTEXT_PROFILE_CORE.cint)
      discard glSetAttribute(SDL_GL_CONTEXT_FLAGS, (SDL_GL_CONTEXT_DEBUG_FLAG or
          SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG).cint)

      let
        name = fmt"{app.name} SDL2"
      window = createWindow(name.cstring, 100, 100,
          cint(app.w), cint(app.h),
          SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL or SDL_WINDOW_ALLOW_HIGHDPI)
      if window.isNil:
        raiseSDLError("SDL_CreateWindow")

      glCtx = window.glCreateContext()
      if glCtx.isNil:
        raiseSDLError("SDL_GL_CreateContext")

      discard window.glMakeCurrent(glCtx)
      loadExtensions()

      var
        drawW, drawH: cint
      glGetDrawableSize(window, drawW, drawH)

      let
        backendContext = createOpenglBackendContext(app.w, app.h)
      initApp(app, backendContext, float32(drawW) / float32(app.w))
      glViewport(0, 0, drawW, drawH)

      var
        sdlEvent = sdl2.defaultEvent

      while runGame and not app.isErr:
        glClearColor(0.93f, 0.93f, 0.93f, 1.0f)
        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

        app.runFrame()
        if not app.isErr:
          window.glSwapWindow()
        frameMark()

        while pollEvent(sdlEvent):
          case sdlEvent.kind
          of QuitEvent:
            runGame = false
            break

          of WindowEvent:
            let windowEvent = cast[WindowEventPtr](sdlEvent.addr)
            if windowEvent.event == WindowEvent_Resized or
                windowEvent.event == WindowEvent_SizeChanged:
              let
                w = int32(windowEvent.data1)
                h = int32(windowEvent.data2)
              if w > 0 and h > 0:
                app.ctx.setupPixelRatio(window, w, h)

          else:
            let appEvent = toAppEvent(sdlEvent)
            if appEvent.typ != EVENT_TYPE_NONE:
              app.dispatchEvent(appEvent)
    except Exception as e:
      app.reportException(e, "opengl launch")
    finally:
      if not glCtx.isNil:
        sdl2.glDeleteContext(glCtx)
      if not window.isNil:
        sdl2.destroyWindow(window)
      sdl2.quit()

elif defined(feature.nvg.sokol):
  import std/strformat

  import pkg/sokol/app as sapp
  import pkg/sokol/gfx
  import pkg/sokol/glue
  import pkg/sokol/log

  import nvg/tracy

  const action = PassAction(
    colors: [
      ColorAttachmentAction(
        loadAction: loadActionClear,
        clearValue: gfx.Color(r: 0.93f, g: 0.93f, b: 0.93f, a: 1.0f),
    )
  ]
  )

  var
    appState = default(App)

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

  proc toAppEvent(ev: ptr Event): AppEvent =
    case ev.`type`
    of eventTypeKeyDown, eventTypeKeyUp:
      let
        keyCode = toAppKeyCode(ev.keyCode)
      if keyCode == KEY_CODE_NONE:
        return
      if ev.`type` == eventTypeKeyDown:
        result.typ = EVENT_TYPE_KEY_DOWN
      else:
        result.typ = EVENT_TYPE_KEY_UP
      result.keyCode = keyCode
    of eventTypeMouseDown, eventTypeMouseUp:
      case ev.mouseButton
      of mouseButtonLeft:
        result.mouseButton = MOUSE_BUTTON_LEFT
      of mouseButtonRight:
        result.mouseButton = MOUSE_BUTTON_RIGHT
      of mouseButtonMiddle:
        result.mouseButton = MOUSE_BUTTON_MIDDLE
      else:
        return
      if ev.`type` == eventTypeMouseDown:
        result.typ = EVENT_TYPE_MOUSE_DOWN
      else:
        result.typ = EVENT_TYPE_MOUSE_UP
      result.mouseX = int32(ev.mouseX)
      result.mouseY = int32(ev.mouseY)
    of eventTypeMouseMove:
      result.typ = EVENT_TYPE_MOUSE_MOVE
      result.mouseX = int32(ev.mouseX)
      result.mouseY = int32(ev.mouseY)
      result.mouseDx = int32(ev.mouseDx)
      result.mouseDy = int32(ev.mouseDy)
    of eventTypeMouseScroll:
      result.typ = EVENT_TYPE_MOUSE_SCROLL
      result.scrollX = int32(ev.scrollX)
      result.scrollY = int32(ev.scrollY)
    else:
      discard

  proc init() {.cdecl.} =
    try:
      gfx.setup(gfx.Desc(
        environment: environment(),
        logger: gfx.Logger(fn: fn),
        pipelinePoolSize: 128,
        d3d11: D3d11Desc(shaderDebugging: true),
      ))

      case queryBackend()
      of backendGlcore:
        echo "using GLCORE backend"
      of backendD3d11:
        echo "using D3D11 backend"
      of backendMetalMacos:
        echo "using Metal backend"
      else:
        echo "using untested backend"

      setWindowTitle(fmt"{appState.name} {queryBackend()}".cstring)

      let
        backendContext = createSokolBackendContext(int32(width()), int32(height()))
      appState.initApp(backendContext, dpiScale())
    except Exception as e:
      appState.reportException(e, "sokol init")
      sapp.quit()

  proc event(ev: ptr Event) {.cdecl.} =
    if appState.isErr:
      return

    let appEvent = toAppEvent(ev)
    if appEvent.typ != EVENT_TYPE_NONE:
      appState.dispatchEvent(appEvent)

    if appState.isErr:
      sapp.quit()

  proc setupPixelRatio(ctx: Context, w, h: int32) =
    let
      scale = dpiScale()
      w = int32(float32(w) / scale)
      h = int32(float32(h) / scale)

    ctx.backendContext.resize(w, h)
    ctx.setDevicePixelRatio(dpiScale())

  proc frame() {.cdecl.} =
    if appState.isErr:
      sapp.quit()
      return

    appState.ctx.setupPixelRatio(width(), height())

    try:
      beginPass(Pass(action: action, swapchain: swapchain()))

      appState.runFrame()

      endPass()
      commit()
      frameMark()
    except Exception as e:
      appState.reportException(e, "sokol frame")
      sapp.quit()

  proc cleanup() {.cdecl.} =
    appState.ctx = nil
    appState = nil
    shutdown()

  proc launch*(app: App) =
    if app.isNil:
      return

    appState = app

    sapp.run(
      sapp.Desc(
        initCb: init,
        eventCb: event,
        frameCb: frame,
        cleanupCb: cleanup,
        swapInterval: 0,
        sampleCount: 4,
        highDpi: true,
        width: app.w,
        height: app.h,
        icon: IconDesc(sokol_default: true),
        logger: sapp.Logger(fn: log.fn),
      )
    )

else:
  proc launch*(app: App) =
    quit(0)
