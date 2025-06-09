import pkg/sdl2
import pkg/opengl

import nvg/context
import nvg/gl

import ./demo

discard sdl2.init(INIT_EVERYTHING)

discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE.cint)
discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4.cint)
discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1.cint)
discard glSetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_DEBUG_FLAG.cint)

var
  window = createWindow("tgl.nim SDL2", 100, 100, 640,480, SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL)
  glContext = window.glCreateContext()

loadExtensions()

var
  evt = sdl2.defaultEvent
  runGame = true

  ctx = newContext()

initDemo(ctx)

while runGame:
  while pollEvent(evt):
    if evt.kind == QuitEvent:
      runGame = false
      break

  frameStart()

  glClearColor(0.3, 0.3, 0.32, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  ctx.begin([float32(640), float32(480)], float32(1))
  ctx.renderDemo1()
  ctx.renderDemo2()
  ctx.renderPerfGraph()

  ctx.flush()

  frameEnd()

  window.glSwapWindow()

destroy window
