lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

struct Value
  Probe.emit(17)
end

def bootstrap_main
  1
end

bootstrap_main
