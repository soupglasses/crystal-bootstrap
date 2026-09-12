lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

enum Mode
  Quiet = 3
  Loud  = 7
end

PAIR = {12, Mode::Loud}

def bootstrap_main
  pair = PAIR
  Probe.emit(pair[0])
  Probe.emit(pair[1].value)
end

bootstrap_main
