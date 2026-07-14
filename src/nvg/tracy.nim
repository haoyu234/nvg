when defined(feature.nvg.tracy):
  const
    TRACY_PATH {.strdefine.} = ""

  when TRACY_PATH.len == 0:
    {.error: "tracy enabled but no source path given, compile with -d:TRACY_PATH=<path to tracy repo>".}

  {.passC: "-DTRACY_ENABLE -I\"" & TRACY_PATH & "/public\"".}
  {.compile: TRACY_PATH & "/public/TracyClient.cpp".}

  when defined(windows):
    {.passL: "-lws2_32 -ldbghelp".}

  when defined(gcc) or defined(clang):
    {.passL: "-lstdc++".}

  type
    TracySourceLocation {.importc: "struct ___tracy_source_location_data",
        header: "tracy/TracyC.h", bycopy.} = object
      name: cstring
      function: cstring
      file: cstring
      line: uint32
      color: uint32

    TracyZoneContext* {.importc: "TracyCZoneCtx",
        header: "tracy/TracyC.h", bycopy.} = object
      id: uint32
      active: cint

  proc tracyEmitZoneBegin(sourceLocation: ptr TracySourceLocation,
      active: cint): TracyZoneContext {.
      importc: "___tracy_emit_zone_begin", header: "tracy/TracyC.h".}

  proc tracyEmitZoneEnd(context: TracyZoneContext) {.
      importc: "___tracy_emit_zone_end", header: "tracy/TracyC.h".}

  proc tracyEmitFrameMark(name: cstring) {.
      importc: "___tracy_emit_frame_mark", header: "tracy/TracyC.h".}

  proc tracyEmitPlot(name: cstring, value: cdouble) {.
      importc: "___tracy_emit_plot", header: "tracy/TracyC.h".}

  proc tracyEmitMessage(text: cstring, size: csize_t, callstack: cint) {.
      importc: "___tracy_emit_message", header: "tracy/TracyC.h".}

else:
  type
    TracyZoneContext* = object

template zoneBegin*(zoneName: static string): TracyZoneContext =
  when defined(feature.nvg.tracy):
    const
      zoneInfo = instantiationInfo(-1, true)

    let zoneSourceLocation {.global.} = TracySourceLocation(
      name: zoneName,
      function: zoneName,
      file: cstring(zoneInfo.filename),
      line: uint32(zoneInfo.line),
      color: 0,
    )

    tracyEmitZoneBegin(zoneSourceLocation.addr, 1)
  else:
    TracyZoneContext()

template zoneEnd*(zoneContext: TracyZoneContext) =
  when defined(feature.nvg.tracy):
    tracyEmitZoneEnd(zoneContext)
  else:
    discard zoneContext

template zoneScope*(zoneName: static string, body: untyped) =
  when defined(feature.nvg.tracy):
    const
      zoneInfo = instantiationInfo(-1, true)

    let zoneSourceLocation {.global.} = TracySourceLocation(
      name: zoneName,
      function: zoneName,
      file: cstring(zoneInfo.filename),
      line: uint32(zoneInfo.line),
      color: 0,
    )

    let zoneContext = tracyEmitZoneBegin(zoneSourceLocation.addr, 1)
    try:
      body
    finally:
      tracyEmitZoneEnd(zoneContext)
  else:
    body

template frameMark*() =
  when defined(feature.nvg.tracy):
    tracyEmitFrameMark(nil)

template plot*(plotName: static string, value: float) =
  when defined(feature.nvg.tracy):
    tracyEmitPlot(plotName, cdouble(value))

template message*(text: string) =
  when defined(feature.nvg.tracy):
    tracyEmitMessage(cstring(text), csize_t(text.len), 0)
