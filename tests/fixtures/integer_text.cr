lib Probe
  fun emit = probe_emit(value : Int32) : Void
end

def bootstrap_main
  Probe.emit(Int64::MIN.to_s == "-9223372036854775808" ? 1 : 0)
  Probe.emit(UInt64::MAX.to_s(16, upcase: true) == "FFFFFFFFFFFFFFFF" ? 1 : 0)
  Probe.emit(31.to_s(2, precision: 8) == "00011111" ? 1 : 0)
  Probe.emit(0.to_s(precision: 0).empty? ? 1 : 0)
  Probe.emit(61.to_s(62) == "Z" ? 1 : 0)
  begin
    1.to_s(63)
  rescue ArgumentError
    Probe.emit(9)
  end
end

bootstrap_main
