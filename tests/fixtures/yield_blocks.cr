lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def apply_twice(value : Int32, &)
  yield value
  yield value &+ 1
ensure
  Probe.emit(8)
end

def apply_once(&)
  yield 7
end

def early_return
  apply_twice(2) do |value|
    return value &+ 10
  end
end

def bootstrap_main
  offset = 3
  result = apply_twice(4) do |value|
    offset = offset &+ value
    offset
  end
  Probe.emit(result)
  Probe.emit(offset)
  Probe.emit(early_return)
  stopped = apply_twice(5) do |value|
    begin
      break value &+ 20
    ensure
      Probe.emit(9)
    end
  end
  Probe.emit(stopped)
  continued = apply_twice(5) do |value|
    begin
      next value &+ 30
    ensure
      Probe.emit(10)
    end
  end
  Probe.emit(continued)
  reader = apply_once { |value| -> { value &+ 2 } }
  Probe.emit(reader.call)
end

bootstrap_main
