import ./context
import ./params

proc newContext*(): Context =
  createInternal(
    nil,
    default(BackendContextParams),
    nil,
  )
