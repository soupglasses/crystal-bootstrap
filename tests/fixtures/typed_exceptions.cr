lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

class ParseFailure < Exception
end

def bootstrap_main
  begin
    begin
      raise ParseFailure.new("invalid")
    rescue IndexError
      Probe.emit(99)
    rescue error : ParseFailure
      Probe.emit(1)
      raise error
    ensure
      Probe.emit(2)
    end
  rescue Exception
    Probe.emit(3)
  end
  begin
    Probe.emit(2147483647 + 1)
  rescue OverflowError
    Probe.emit(4)
  end
  begin
    Probe.emit([1][2])
  rescue IndexError
    Probe.emit(5)
  end
  begin
    Probe.emit(6)
  rescue
    Probe.emit(99)
  else
    Probe.emit(7)
  end
end

bootstrap_main
