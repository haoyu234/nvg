import nvg/context
import nvg/core
import nvg/math
import nvg/path

export
  context,
  core,
  math,
  path

when defined(feature.nvg.opengl) or defined(feature.nvg.sokol):
  when defined(feature.nvg.opengl):
    import nvg/gl
    export gl
  else:
    import nvg/sokol
    export sokol

  proc newContext*(width, height: int32): Context =
    let backendContext = createBackendContext(width, height)
    createInternal(backendContext)

else:
  import nvg/backend

  proc newContext*(width, height: int32): Context =
    createInternal(BackendContext())
