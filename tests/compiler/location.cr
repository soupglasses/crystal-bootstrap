require "compiler/crystal/syntax"

lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  location = Crystal::Location.new("input.cr", 12, 34)
  Probe.emit(location.line_number)
  Probe.emit(location.column_number)
end

bootstrap_main
