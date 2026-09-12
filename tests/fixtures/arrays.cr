lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  values = [1, 2, 3]
  alias_values = values
  values << 4
  Probe.emit(alias_values.size)
  Probe.emit(values[-1])
  values[0] = 7
  Probe.emit(alias_values[0])
  Probe.emit(values.pop)
  mapped = values.map { |value| value &+ 10 }
  Probe.emit(mapped.sum)
  total = 0
  mapped.each { |value| total = total &+ value }
  Probe.emit(total)
  values.clear
  Probe.emit(alias_values.size)
  flags = Array(Bool).new(4)
  flags << true
  Probe.emit(flags[0] ? 1 : 0)
end

bootstrap_main
