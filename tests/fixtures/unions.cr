lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def choose(flag : Bool)
  flag ? 7 : false
end

def number(value : Int32 | Bool)
  if value.is_a?(Int32)
    value &+ 1
  else
    value ? 9 : 10
  end
end

def optional_text(value : String?)
  return 2 unless value.is_a?(String)
  value.size
end

def record_value(value : Int32)
  Probe.emit(value)
  nil
end

def record_value(value : Bool)
  "recorded"
end

def bootstrap_main
  Probe.emit(number(choose(true)))
  Probe.emit(number(choose(false)))
  Probe.emit(optional_text("abc"))
  Probe.emit(optional_text(nil))
  record_value(choose(true))
end

bootstrap_main
