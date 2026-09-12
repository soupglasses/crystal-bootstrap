lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def combine(left : Int32, right : Int32) : Int32
  Probe.emit(left)
  right
end

def bootstrap_main
  Probe.emit(2147483647 &+ 1)
  begin
    value = 2147483647
    Probe.emit(value + 1)
  rescue
    Probe.emit(7)
  end
  value = 1
  Probe.emit(combine(value, value = 2))
  value = 1
  Probe.emit(value &+ (value = 2))
  count = 0
  while count < 3
    Probe.emit(count)
    count = count &+ 1
  end
end

bootstrap_main
