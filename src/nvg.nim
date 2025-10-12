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

  import nvg/atlas
  import nvg/fontstash

  proc newContext*(width, height: int32): Context =
    let
      backendContext = createBackendContext(width, height)
      atlas = newAtlas(2048, 2048, backendContext)
      fons = newFonsStash(TopLeftOrigin, atlas)
    createInternal(fons, backendContext)

else:
  import nvg/backend

  proc newContext*(width, height: int32): Context =
    createInternal(nil, BackendContext())
