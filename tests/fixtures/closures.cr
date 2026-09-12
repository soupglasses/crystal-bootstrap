lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def counter(start : Int32)
  count = start
  ->(delta : Int32) { count = count &+ delta }
end

def bootstrap_main
  increment = counter(1)
  alias_of_increment = increment
  independent = counter(10)
  Probe.emit(increment.call(2))
  Probe.emit(alias_of_increment.call(3))
  Probe.emit(independent.call(1))
  Probe.emit(increment.call(4))

  # Both closures and the enclosing scope must observe the same mutable cell.
  count = 20
  add = ->(delta : Int32) { count = count &+ delta }
  read = -> { count }
  Probe.emit(add.call(2))
  Probe.emit(read.call)
  count = 30
  Probe.emit(read.call)
end

bootstrap_main
