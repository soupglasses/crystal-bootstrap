lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def guarded(mode : Int32) : Int32
  begin
    raise "body" if mode == 1
    return 7
  rescue
    Probe.emit(8)
    return 9
  ensure
    Probe.emit(6)
  end
end

def replace_return_with_exception : Int32
  begin
    return 4
  ensure
    raise "cleanup"
  end
end

def nested_cleanup : Int32
  begin
    begin
      return 5
    ensure
      Probe.emit(10)
    end
  ensure
    Probe.emit(11)
  end
end

def normal_cleanup : Int32
  begin
    12
  ensure
    Probe.emit(13)
  end
end

def bootstrap_main
  Probe.emit(guarded(0))
  Probe.emit(guarded(1))
  begin
    Probe.emit(replace_return_with_exception)
  rescue
    Probe.emit(99)
  end
  Probe.emit(nested_cleanup)
  Probe.emit(normal_cleanup)
end

bootstrap_main
