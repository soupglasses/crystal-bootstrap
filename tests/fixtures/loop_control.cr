lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  count = 0
  result = while count < 5
    count += 1
    begin
      next if count == 1
      break 42 if count == 3
      Probe.emit(count)
    ensure
      Probe.emit(count + 10)
    end
  end
  Probe.emit(result || 0)
end

bootstrap_main
